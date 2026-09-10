package health

import (
	"encoding/json"
	"fmt"
	"math"
	"time"
)

// GeoJSON semantic color palette per Research Doc 19 (§5).
const (
	ColorBunchedStatus = "#D32F2F" // Red 700
	ColorBunchedHalo   = "#FFCDD2" // Red 100
	ColorGapStatus     = "#F57C00" // Orange 700
	ColorGapHalo       = "#FFE0B2" // Orange 100
	ColorNormalStatus  = "#388E3C" // Green 700
	ColorNormalHalo    = "#C8E6C9" // Green 100

	ColorBunchingLine   = "#B71C1C" // Red 900
	ColorBunchingCasing = "#FFEBEE" // Red 50
)

// GeoJSONFeatureCollection models the top-level GeoJSON FeatureCollection with corridor metadata.
type GeoJSONFeatureCollection struct {
	Type     string                 `json:"type"`
	Metadata map[string]interface{} `json:"metadata"`
	Features []GeoJSONFeature       `json:"features"`
}

// GeoJSONGeometry represents a GeoJSON geometry (Point or LineString).
type GeoJSONGeometry struct {
	Type        string      `json:"type"`
	Coordinates interface{} `json:"coordinates"`
}

// GeoJSONFeature represents an individual GeoJSON feature.
type GeoJSONFeature struct {
	Type       string                 `json:"type"`
	ID         string                 `json:"id"`
	Geometry   GeoJSONGeometry        `json:"geometry"`
	Properties map[string]interface{} `json:"properties"`
}

// GenerateCorridorGeoJSON serializes a CorridorHealthResult and vehicle telemetry into the
// GeoJSON FeatureCollection specification defined in Research Doc 19 (§5).
func GenerateCorridorGeoJSON(
	result *CorridorHealthResult,
	vehicles []ActiveVehicleInput,
) (*GeoJSONFeatureCollection, error) {
	if result == nil {
		return nil, fmt.Errorf("corridor health result cannot be nil")
	}

	ts := result.Timestamp
	if ts <= 0 {
		ts = time.Now().Unix()
	}

	// Index classifications by vehicle ID for rapid lookup.
	classMap := make(map[string]VehicleClassification, len(result.Classifications))
	for _, c := range result.Classifications {
		classMap[c.VehicleID] = c
	}

	// Index vehicles by vehicle ID.
	vehMap := make(map[string]ActiveVehicleInput, len(vehicles))
	for _, v := range vehicles {
		vehMap[v.VehicleID] = v
	}

	metadata := map[string]interface{}{
		"route_id":                 result.RouteID,
		"route_short_name":         result.RouteShortName,
		"timestamp":                ts,
		"corridor_health_score":    result.CorridorHealthScore,
		"corridor_status":          string(result.Status),
		"coefficient_of_variation": math.Round(result.CoefficientOfVar*1000.0) / 1000.0,
		"active_bunching_count":    result.BunchingEventCount,
		"active_gap_count":         result.ServiceGapCount,
		"expected_wait_sec":        math.Round(result.ExpectedWaitTimeSec*10.0) / 10.0,
		"vehicle_count":            result.VehicleCount,
		"scheduled_headway_sec":    result.ScheduledHeadwaySec,
	}

	features := make([]GeoJSONFeature, 0, len(vehicles)+result.BunchingEventCount)

	// 1. Vehicle point marker features
	for _, v := range vehicles {
		c, hasClass := classMap[v.VehicleID]
		statusColor := ColorNormalStatus
		haloColor := ColorNormalHalo

		if hasClass {
			if c.IsBunched {
				statusColor = ColorBunchedStatus
				haloColor = ColorBunchedHalo
			} else if c.IsServiceGap {
				statusColor = ColorGapStatus
				haloColor = ColorGapHalo
			}
		}

		headwaySec := result.ScheduledHeadwaySec
		if hasClass {
			headwaySec = math.Round(c.TemporalHeadway*10.0) / 10.0
		}

		props := map[string]interface{}{
			"feature_class":         "vehicle_marker",
			"vehicle_id":            v.VehicleID,
			"trip_id":               v.TripID,
			"bearing":               v.Bearing,
			"speed_mps":             v.SpeedMetersPerSec,
			"delay_sec":             v.DelaySec,
			"is_target":             v.IsTargetVehicle,
			"is_bunched":            hasClass && c.IsBunched,
			"is_service_gap":        hasClass && c.IsServiceGap,
			"curvilinear_offset_m":  v.CurvilinearOffsetM,
			"headway_sec":           headwaySec,
			"scheduled_headway_sec": result.ScheduledHeadwaySec,
			"status_color":          statusColor,
			"halo_color":            haloColor,
		}

		feat := GeoJSONFeature{
			Type: "Feature",
			ID:   fmt.Sprintf("veh_%s", v.VehicleID),
			Geometry: GeoJSONGeometry{
				Type:        "Point",
				Coordinates: []float64{v.Longitude, v.Latitude},
			},
			Properties: props,
		}
		features = append(features, feat)
	}

	// 2. Bunching segment LineString features between adjacent bunched vehicles
	// Search through classifications for bunched followers and connect to downstream leader.
	for i, c := range result.Classifications {
		if c.IsBunched && i < len(result.Classifications)-1 {
			followerID := c.VehicleID
			leaderID := result.Classifications[i+1].VehicleID

			follower, ok1 := vehMap[followerID]
			leader, ok2 := vehMap[leaderID]

			if ok1 && ok2 && (follower.Latitude != 0 || follower.Longitude != 0) &&
				(leader.Latitude != 0 || leader.Longitude != 0) {

				lineCoords := [][]float64{
					{follower.Longitude, follower.Latitude},
					{leader.Longitude, leader.Latitude},
				}

				compressionRatio := c.CompressionRatio
				if compressionRatio == 0 && result.ScheduledHeadwaySec > 0 {
					compressionRatio = c.TemporalHeadway / result.ScheduledHeadwaySec
				}

				segmentFeat := GeoJSONFeature{
					Type: "Feature",
					ID:   fmt.Sprintf("segment_bunch_%s_%s", followerID, leaderID),
					Geometry: GeoJSONGeometry{
						Type:        "LineString",
						Coordinates: lineCoords,
					},
					Properties: map[string]interface{}{
						"feature_class":             "bunching_segment",
						"severity":                  "critical",
						"trailing_vehicle_id":       followerID,
						"leading_vehicle_id":        leaderID,
						"segment_length_m":          math.Round(c.SpatialHeadwayM*10.0) / 10.0,
						"headway_compression_ratio": math.Round(compressionRatio*1000.0) / 1000.0,
						"line_color":                ColorBunchingLine,
						"casing_color":              ColorBunchingCasing,
					},
				}
				features = append(features, segmentFeat)
			}
		}
	}

	return &GeoJSONFeatureCollection{
		Type:     "FeatureCollection",
		Metadata: metadata,
		Features: features,
	}, nil
}

// MarshalCorridorGeoJSON returns the compact JSON byte representation of the corridor GeoJSON.
func MarshalCorridorGeoJSON(result *CorridorHealthResult, vehicles []ActiveVehicleInput) ([]byte, error) {
	fc, err := GenerateCorridorGeoJSON(result, vehicles)
	if err != nil {
		return nil, err
	}
	return json.Marshal(fc)
}
