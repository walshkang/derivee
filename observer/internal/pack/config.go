package pack

import (
	"encoding/json"
	"fmt"
	"os"
)

// GeoBounds defines the rectangular geographic envelope for camera clamping and fog math
type GeoBounds struct {
	MinLatitude  float64 `json:"minLatitude"`
	MaxLatitude  float64 `json:"maxLatitude"`
	MinLongitude float64 `json:"minLongitude"`
	MaxLongitude float64 `json:"maxLongitude"`
}

// MapCenter defines default viewport camera center and zoom level
type MapCenter struct {
	Latitude    float64 `json:"latitude"`
	Longitude   float64 `json:"longitude"`
	DefaultZoom float64 `json:"defaultZoom"`
}

// RealtimeEndpoint defines an agency GTFS-RT feed configuration
type RealtimeEndpoint struct {
	FeedID              string            `json:"feedId"`
	URL                 string            `json:"url"`
	PollIntervalSeconds int               `json:"pollIntervalSeconds"`
	Headers             map[string]string `json:"headers,omitempty"`
}

// ScheduleValidity defines the calendar validity window of the static timetable
type ScheduleValidity struct {
	StartDate   string `json:"startDate"`
	EndDate     string `json:"endDate"`
	SeasonLabel string `json:"seasonLabel"`
}

// GBFSConfig defines micro-mobility bikeshare GBFS feed configuration
type GBFSConfig struct {
	SystemID                  string            `json:"systemId,omitempty"`
	StationInfoURL            string            `json:"stationInfoUrl,omitempty"`
	StationStatusURL          string            `json:"stationStatusUrl"`
	PollIntervalSeconds       float64           `json:"pollIntervalSeconds"`
	StalenessThresholdSeconds float64           `json:"stalenessThresholdSeconds"`
	Headers                   map[string]string `json:"headers,omitempty"`
}

// TransitConfig contains transit metadata, endpoints, attributions, and route mappings
type TransitConfig struct {
	AgencyName        string             `json:"agencyName"`
	Attributions      []string           `json:"attributions"`
	RealtimeEndpoints []RealtimeEndpoint `json:"realtimeEndpoints"`
	FeedRouteMapping  map[string]string  `json:"feedRouteMapping"`
	ScheduleValidity  ScheduleValidity   `json:"scheduleValidity"`
	GBFS              *GBFSConfig        `json:"gbfs,omitempty"`
}

// CityConfig defines the schema of city_config.json
type CityConfig struct {
	Version     int           `json:"version"`
	Slug        string        `json:"slug"`
	DisplayName string        `json:"displayName"`
	Region      string        `json:"region"`
	Bounds      GeoBounds     `json:"bounds"`
	Center      MapCenter     `json:"center"`
	Transit     TransitConfig `json:"transit"`
	GBFS        *GBFSConfig   `json:"gbfs,omitempty"`
	SHA256      string        `json:"sha256,omitempty"`
}

// CityManifestEntry defines metadata for a single city in cities.json
type CityManifestEntry struct {
	Slug                  string `json:"slug"`
	DisplayName           string `json:"displayName"`
	Region                string `json:"region"`
	CompressedSizeBytes   int64  `json:"compressedSizeBytes"`
	UncompressedSizeBytes int64  `json:"uncompressedSizeBytes"`
	IsBundled             bool   `json:"isBundled"`
	Version               string `json:"version"`
	SHA256                string `json:"sha256,omitempty"`
}

// CitiesManifest defines the remote catalog schema hosted at cdn.derivee.app/cities.json
type CitiesManifest struct {
	Version     int                 `json:"version"`
	LastUpdated string              `json:"lastUpdated"`
	Cities      []CityManifestEntry `json:"cities"`
}

// GetGBFS returns the active GBFSConfig checking top-level first, then transit.gbfs
func (cfg *CityConfig) GetGBFS() *GBFSConfig {
	if cfg.GBFS != nil {
		return cfg.GBFS
	}
	return cfg.Transit.GBFS
}

// ValidateCityConfig verifies that required fields are present and valid
func ValidateCityConfig(cfg *CityConfig) error {
	if cfg.Slug == "" {
		return fmt.Errorf("city_config missing required 'slug'")
	}
	if cfg.DisplayName == "" {
		return fmt.Errorf("city_config missing required 'displayName'")
	}
	if cfg.Bounds.MinLatitude >= cfg.Bounds.MaxLatitude {
		return fmt.Errorf("invalid bounds: minLatitude (%.4f) >= maxLatitude (%.4f)", cfg.Bounds.MinLatitude, cfg.Bounds.MaxLatitude)
	}
	if cfg.Bounds.MinLongitude >= cfg.Bounds.MaxLongitude {
		return fmt.Errorf("invalid bounds: minLongitude (%.4f) >= maxLongitude (%.4f)", cfg.Bounds.MinLongitude, cfg.Bounds.MaxLongitude)
	}
	if cfg.Center.Latitude < cfg.Bounds.MinLatitude || cfg.Center.Latitude > cfg.Bounds.MaxLatitude {
		return fmt.Errorf("center latitude (%.4f) is outside bounding box", cfg.Center.Latitude)
	}
	if cfg.Center.Longitude < cfg.Bounds.MinLongitude || cfg.Center.Longitude > cfg.Bounds.MaxLongitude {
		return fmt.Errorf("center longitude (%.4f) is outside bounding box", cfg.Center.Longitude)
	}

	if gbfs := cfg.GetGBFS(); gbfs != nil {
		if err := ValidateGBFSConfig(gbfs); err != nil {
			return fmt.Errorf("invalid gbfs config: %w", err)
		}
	}

	return nil
}

// ValidateGBFSConfig validates GBFS endpoint configuration and defaults values if needed
func ValidateGBFSConfig(gbfs *GBFSConfig) error {
	if gbfs.StationStatusURL == "" {
		return fmt.Errorf("missing required 'stationStatusUrl'")
	}
	if len(gbfs.StationStatusURL) < 8 || (gbfs.StationStatusURL[:7] != "http://" && gbfs.StationStatusURL[:8] != "https://") {
		return fmt.Errorf("stationStatusUrl must start with http:// or https:// (got %q)", gbfs.StationStatusURL)
	}
	if gbfs.StationInfoURL != "" {
		if len(gbfs.StationInfoURL) < 8 || (gbfs.StationInfoURL[:7] != "http://" && gbfs.StationInfoURL[:8] != "https://") {
			return fmt.Errorf("stationInfoUrl must start with http:// or https:// (got %q)", gbfs.StationInfoURL)
		}
	}
	if gbfs.PollIntervalSeconds == 0 {
		gbfs.PollIntervalSeconds = 30.0
	} else if gbfs.PollIntervalSeconds < 0 {
		return fmt.Errorf("pollIntervalSeconds must be positive (got %.1f)", gbfs.PollIntervalSeconds)
	}
	if gbfs.StalenessThresholdSeconds == 0 {
		gbfs.StalenessThresholdSeconds = 600.0
	} else if gbfs.StalenessThresholdSeconds < 0 {
		return fmt.Errorf("stalenessThresholdSeconds must be positive (got %.1f)", gbfs.StalenessThresholdSeconds)
	}
	if gbfs.StalenessThresholdSeconds < gbfs.PollIntervalSeconds {
		return fmt.Errorf("stalenessThresholdSeconds (%.1f) cannot be less than pollIntervalSeconds (%.1f)", gbfs.StalenessThresholdSeconds, gbfs.PollIntervalSeconds)
	}
	return nil
}

// LoadCityConfig parses a city_config.json file
func LoadCityConfig(filePath string) (*CityConfig, error) {
	data, err := os.ReadFile(filePath)
	if err != nil {
		return nil, fmt.Errorf("failed to read %s: %w", filePath, err)
	}

	var cfg CityConfig
	if err := json.Unmarshal(data, &cfg); err != nil {
		return nil, fmt.Errorf("failed to unmarshal JSON from %s: %w", filePath, err)
	}

	if err := ValidateCityConfig(&cfg); err != nil {
		return nil, err
	}

	return &cfg, nil
}

// SaveCityConfig writes a formatted city_config.json file
func SaveCityConfig(cfg *CityConfig, filePath string) error {
	data, err := json.MarshalIndent(cfg, "", "  ")
	if err != nil {
		return fmt.Errorf("failed to marshal city_config: %w", err)
	}
	return os.WriteFile(filePath, append(data, '\n'), 0644)
}

// LoadCitiesManifest parses a cities.json manifest
func LoadCitiesManifest(filePath string) (*CitiesManifest, error) {
	data, err := os.ReadFile(filePath)
	if err != nil {
		return nil, fmt.Errorf("failed to read %s: %w", filePath, err)
	}

	var manifest CitiesManifest
	if err := json.Unmarshal(data, &manifest); err != nil {
		return nil, fmt.Errorf("failed to unmarshal manifest from %s: %w", filePath, err)
	}

	return &manifest, nil
}

// SaveCitiesManifest writes a formatted cities.json manifest
func SaveCitiesManifest(manifest *CitiesManifest, filePath string) error {
	data, err := json.MarshalIndent(manifest, "", "  ")
	if err != nil {
		return fmt.Errorf("failed to marshal manifest: %w", err)
	}
	return os.WriteFile(filePath, append(data, '\n'), 0644)
}
