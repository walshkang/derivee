package pack

import (
	"path/filepath"
	"testing"
)

func TestGBFSConfigValidation_Valid(t *testing.T) {
	cfg := &CityConfig{
		Version:     1,
		Slug:        "test-city",
		DisplayName: "Test City",
		Region:      "Test Region",
		Bounds: GeoBounds{
			MinLatitude:  40.0,
			MaxLatitude:  41.0,
			MinLongitude: -74.0,
			MaxLongitude: -73.0,
		},
		Center: MapCenter{
			Latitude:    40.5,
			Longitude:   -73.5,
			DefaultZoom: 13.0,
		},
		Transit: TransitConfig{
			AgencyName: "Test Transit",
			GBFS: &GBFSConfig{
				SystemID:                  "test_bike",
				StationInfoURL:            "https://gbfs.test.com/station_information.json",
				StationStatusURL:          "https://gbfs.test.com/station_status.json",
				PollIntervalSeconds:       30.0,
				StalenessThresholdSeconds: 600.0,
			},
		},
	}

	if err := ValidateCityConfig(cfg); err != nil {
		t.Fatalf("expected valid config, got error: %v", err)
	}

	gbfs := cfg.GetGBFS()
	if gbfs == nil {
		t.Fatalf("expected GetGBFS() to return non-nil")
	}
	if gbfs.SystemID != "test_bike" {
		t.Errorf("expected systemId 'test_bike', got %q", gbfs.SystemID)
	}
}

func TestGBFSConfigValidation_TopLevel(t *testing.T) {
	cfg := &CityConfig{
		Version:     2,
		Slug:        "test-top",
		DisplayName: "Test Top Level",
		Region:      "Test Region",
		Bounds: GeoBounds{
			MinLatitude:  40.0,
			MaxLatitude:  41.0,
			MinLongitude: -74.0,
			MaxLongitude: -73.0,
		},
		Center: MapCenter{
			Latitude:    40.5,
			Longitude:   -73.5,
			DefaultZoom: 13.0,
		},
		Transit: TransitConfig{
			AgencyName: "Test Transit",
		},
		GBFS: &GBFSConfig{
			SystemID:         "top_bike",
			StationStatusURL: "https://gbfs.test.com/status.json",
		},
	}

	if err := ValidateCityConfig(cfg); err != nil {
		t.Fatalf("expected valid config, got error: %v", err)
	}

	gbfs := cfg.GetGBFS()
	if gbfs == nil {
		t.Fatalf("expected GetGBFS() to return top-level GBFS")
	}
	if gbfs.PollIntervalSeconds != 30.0 {
		t.Errorf("expected default poll interval 30.0, got %.1f", gbfs.PollIntervalSeconds)
	}
	if gbfs.StalenessThresholdSeconds != 600.0 {
		t.Errorf("expected default staleness threshold 600.0, got %.1f", gbfs.StalenessThresholdSeconds)
	}
}

func TestGBFSConfigValidation_Invalid(t *testing.T) {
	tests := []struct {
		name        string
		gbfs        *GBFSConfig
		expectError string
	}{
		{
			name: "missing stationStatusUrl",
			gbfs: &GBFSConfig{
				SystemID: "test",
			},
			expectError: "missing required 'stationStatusUrl'",
		},
		{
			name: "invalid status url scheme",
			gbfs: &GBFSConfig{
				StationStatusURL: "ftp://gbfs.test.com/status.json",
			},
			expectError: "stationStatusUrl must start with http:// or https://",
		},
		{
			name: "invalid info url scheme",
			gbfs: &GBFSConfig{
				StationStatusURL: "https://gbfs.test.com/status.json",
				StationInfoURL:   "invalid-url",
			},
			expectError: "stationInfoUrl must start with http:// or https://",
		},
		{
			name: "negative poll interval",
			gbfs: &GBFSConfig{
				StationStatusURL:    "https://gbfs.test.com/status.json",
				PollIntervalSeconds: -5.0,
			},
			expectError: "pollIntervalSeconds must be positive",
		},
		{
			name: "staleness threshold less than poll interval",
			gbfs: &GBFSConfig{
				StationStatusURL:          "https://gbfs.test.com/status.json",
				PollIntervalSeconds:       60.0,
				StalenessThresholdSeconds: 30.0,
			},
			expectError: "stalenessThresholdSeconds (30.0) cannot be less than pollIntervalSeconds (60.0)",
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			cfg := &CityConfig{
				Version:     1,
				Slug:        "test-invalid",
				DisplayName: "Invalid City",
				Region:      "Region",
				Bounds: GeoBounds{
					MinLatitude:  40.0,
					MaxLatitude:  41.0,
					MinLongitude: -74.0,
					MaxLongitude: -73.0,
				},
				Center: MapCenter{
					Latitude:    40.5,
					Longitude:   -73.5,
					DefaultZoom: 13.0,
				},
				Transit: TransitConfig{
					AgencyName: "Test Transit",
					GBFS:       tc.gbfs,
				},
			}

			err := ValidateCityConfig(cfg)
			if err == nil {
				t.Fatalf("expected error containing %q, got nil", tc.expectError)
			}
		})
	}
}

func TestLoadCityConfig_WithGBFS(t *testing.T) {
	tempDir := t.TempDir()
	configPath := filepath.Join(tempDir, "city_config.json")

	cfg := &CityConfig{
		Version:     1,
		Slug:        "citi-nyc",
		DisplayName: "New York City",
		Region:      "New York, USA",
		Bounds: GeoBounds{
			MinLatitude:  40.48,
			MaxLatitude:  40.95,
			MinLongitude: -74.28,
			MaxLongitude: -73.68,
		},
		Center: MapCenter{
			Latitude:    40.7128,
			Longitude:   -74.0060,
			DefaultZoom: 13.0,
		},
		Transit: TransitConfig{
			AgencyName: "MTA",
			GBFS: &GBFSConfig{
				SystemID:                  "citi_bike_nyc",
				StationInfoURL:            "https://gbfs.citibikenyc.com/gbfs/en/station_information.json",
				StationStatusURL:          "https://gbfs.citibikenyc.com/gbfs/en/station_status.json",
				PollIntervalSeconds:       30.0,
				StalenessThresholdSeconds: 600.0,
			},
		},
	}

	if err := SaveCityConfig(cfg, configPath); err != nil {
		t.Fatalf("failed to save city config: %v", err)
	}

	loaded, err := LoadCityConfig(configPath)
	if err != nil {
		t.Fatalf("failed to load city config: %v", err)
	}

	gbfs := loaded.GetGBFS()
	if gbfs == nil {
		t.Fatalf("expected non-nil GBFS config")
	}
	if gbfs.SystemID != "citi_bike_nyc" {
		t.Errorf("expected 'citi_bike_nyc', got %q", gbfs.SystemID)
	}
	if gbfs.StationStatusURL != "https://gbfs.citibikenyc.com/gbfs/en/station_status.json" {
		t.Errorf("unexpected stationStatusUrl: %s", gbfs.StationStatusURL)
	}
}

func TestRoutingConfigValidation_V2(t *testing.T) {
	tempDir := t.TempDir()
	configPath := filepath.Join(tempDir, "city_config_v2.json")

	cfg := &CityConfig{
		Version:     2,
		Slug:        "nyc",
		DisplayName: "New York City",
		Region:      "New York, USA",
		Bounds: GeoBounds{
			MinLatitude:  40.48,
			MaxLatitude:  40.95,
			MinLongitude: -74.28,
			MaxLongitude: -73.68,
		},
		Center: MapCenter{
			Latitude:    40.7128,
			Longitude:   -74.0060,
			DefaultZoom: 13.0,
		},
		Routing: &RoutingConfig{
			TimetableBinFile: "timetable.bin",
			UltraCsrFile:     "ultra_transfers.csr",
			WalkGraphFile:    "walk_graph.bin",
			MaxWalkMinutes:   20,
			MaxRounds:        6,
		},
		Transit: TransitConfig{
			AgencyName: "MTA",
		},
	}

	if err := ValidateCityConfig(cfg); err != nil {
		t.Fatalf("expected valid v2 config, got: %v", err)
	}

	routing := cfg.GetRouting()
	if routing == nil {
		t.Fatalf("expected non-nil RoutingConfig")
	}
	if routing.TimetableBinFile != "timetable.bin" || routing.UltraCsrFile != "ultra_transfers.csr" || routing.WalkGraphFile != "walk_graph.bin" {
		t.Errorf("unexpected routing filenames: %+v", routing)
	}
	if routing.MaxWalkMinutes != 20 || routing.MaxRounds != 6 {
		t.Errorf("unexpected routing parameters: %+v", routing)
	}

	if err := SaveCityConfig(cfg, configPath); err != nil {
		t.Fatalf("failed to save city config: %v", err)
	}

	loaded, err := LoadCityConfig(configPath)
	if err != nil {
		t.Fatalf("failed to load city config: %v", err)
	}
	if loaded.Version != 2 {
		t.Errorf("expected version 2, got %d", loaded.Version)
	}
	if loaded.Routing == nil || loaded.Routing.TimetableBinFile != "timetable.bin" {
		t.Errorf("expected loaded routing to match: %+v", loaded.Routing)
	}
}

func TestRoutingConfigDefaults_ForV2WithoutExplicitRouting(t *testing.T) {
	cfg := &CityConfig{
		Version:     2,
		Slug:        "bos",
		DisplayName: "Boston",
		Region:      "Massachusetts, USA",
		Bounds: GeoBounds{
			MinLatitude:  42.20,
			MaxLatitude:  42.50,
			MinLongitude: -71.25,
			MaxLongitude: -70.90,
		},
		Center: MapCenter{
			Latitude:    42.3601,
			Longitude:   -71.0589,
			DefaultZoom: 13.0,
		},
		Transit: TransitConfig{
			AgencyName: "MBTA",
		},
	}

	routing := cfg.GetRouting()
	if routing == nil {
		t.Fatalf("expected GetRouting() to return default for version 2")
	}
	if routing.TimetableBinFile != "timetable.bin" || routing.UltraCsrFile != "ultra_transfers.csr" || routing.WalkGraphFile != "walk_graph.bin" {
		t.Errorf("expected default routing filenames, got: %+v", routing)
	}
	if routing.MaxWalkMinutes != 15 || routing.MaxRounds != 8 {
		t.Errorf("expected default limits, got: %+v", routing)
	}
}
