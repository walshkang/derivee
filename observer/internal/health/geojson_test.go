package health

import (
	"encoding/json"
	"testing"
)

func TestGenerateCorridorGeoJSON_SpecConformity(t *testing.T) {
	// Setup 3 vehicles: V1 and V2 are bunched; V2 and V3 are separated normally.
	vehicles := []ActiveVehicleInput{
		{
			VehicleID:          "9021",
			TripID:             "trip_9920194A",
			CurvilinearOffsetM: 4120.5,
			SpeedMetersPerSec:  0.8, // dwelling
			DelaySec:           420,
			IsTargetVehicle:    true,
			Bearing:            45.0,
			Latitude:           37.774929,
			Longitude:          -122.419416,
		},
		{
			VehicleID:          "9022",
			TripID:             "trip_9920195A",
			CurvilinearOffsetM: 4280.0, // only 159.5m ahead -> bunched
			SpeedMetersPerSec:  11.2,
			DelaySec:           -60,
			IsTargetVehicle:    false,
			Bearing:            44.5,
			Latitude:           37.775820,
			Longitude:          -122.418210,
		},
		{
			VehicleID:          "9023",
			TripID:             "trip_9920196A",
			CurvilinearOffsetM: 11480.0, // 7200m ahead -> normal
			SpeedMetersPerSec:  12.0,
			DelaySec:           0,
			IsTargetVehicle:    false,
			Bearing:            45.0,
			Latitude:           37.785000,
			Longitude:          -122.408000,
		},
	}

	schedHeadway := 600.0
	speed := 12.0

	res, err := AnalyzeCorridorRegularity("METRO_101", vehicles, schedHeadway, speed)
	if err != nil {
		t.Fatalf("AnalyzeCorridorRegularity error: %v", err)
	}

	res.RouteShortName = "101"
	res.Timestamp = 1774958400

	fc, err := GenerateCorridorGeoJSON(res, vehicles)
	if err != nil {
		t.Fatalf("GenerateCorridorGeoJSON error: %v", err)
	}

	if fc.Type != "FeatureCollection" {
		t.Errorf("expected Type 'FeatureCollection', got '%s'", fc.Type)
	}

	// Verify metadata fields per Doc 19 §5
	meta := fc.Metadata
	if meta["route_id"] != "METRO_101" {
		t.Errorf("expected metadata route_id METRO_101, got %v", meta["route_id"])
	}
	if meta["route_short_name"] != "101" {
		t.Errorf("expected metadata route_short_name 101, got %v", meta["route_short_name"])
	}
	if meta["active_bunching_count"] != 1 {
		t.Errorf("expected 1 active bunching event in metadata, got %v", meta["active_bunching_count"])
	}
	if meta["corridor_status"] != "Delayed" {
		t.Errorf("expected metadata corridor_status Delayed, got %v", meta["corridor_status"])
	}

	// Features: 3 vehicles + 1 bunching segment = 4 features
	if len(fc.Features) != 4 {
		t.Fatalf("expected 4 features (3 vehicles + 1 bunching segment), got %d", len(fc.Features))
	}

	// Verify first vehicle marker
	v1Feat := fc.Features[0]
	if v1Feat.Geometry.Type != "Point" {
		t.Errorf("expected Point geometry, got %s", v1Feat.Geometry.Type)
	}
	props := v1Feat.Properties
	if props["feature_class"] != "vehicle_marker" {
		t.Errorf("expected feature_class 'vehicle_marker', got %v", props["feature_class"])
	}
	if props["vehicle_id"] != "9021" {
		t.Errorf("expected vehicle_id 9021, got %v", props["vehicle_id"])
	}
	if props["is_bunched"] != true {
		t.Errorf("expected is_bunched true, got %v", props["is_bunched"])
	}
	if props["status_color"] != ColorBunchedStatus {
		t.Errorf("expected bunched status color %s, got %v", ColorBunchedStatus, props["status_color"])
	}
	if props["halo_color"] != ColorBunchedHalo {
		t.Errorf("expected bunched halo color %s, got %v", ColorBunchedHalo, props["halo_color"])
	}

	// Verify bunching segment feature
	segmentFeat := fc.Features[3]
	if segmentFeat.Geometry.Type != "LineString" {
		t.Errorf("expected LineString geometry for bunching segment, got %s", segmentFeat.Geometry.Type)
	}
	segProps := segmentFeat.Properties
	if segProps["feature_class"] != "bunching_segment" {
		t.Errorf("expected feature_class 'bunching_segment', got %v", segProps["feature_class"])
	}
	if segProps["severity"] != "critical" {
		t.Errorf("expected severity 'critical', got %v", segProps["severity"])
	}
	if segProps["trailing_vehicle_id"] != "9021" || segProps["leading_vehicle_id"] != "9022" {
		t.Errorf("expected segment between 9021 and 9022, got %v and %v",
			segProps["trailing_vehicle_id"], segProps["leading_vehicle_id"])
	}
	if segProps["line_color"] != ColorBunchingLine {
		t.Errorf("expected bunching line color %s, got %v", ColorBunchingLine, segProps["line_color"])
	}

	// Verify JSON marshaling
	jsonBytes, err := MarshalCorridorGeoJSON(res, vehicles)
	if err != nil {
		t.Fatalf("failed to marshal GeoJSON: %v", err)
	}
	if len(jsonBytes) == 0 {
		t.Errorf("marshaled GeoJSON bytes is empty")
	}

	var roundtrip map[string]interface{}
	if err := json.Unmarshal(jsonBytes, &roundtrip); err != nil {
		t.Fatalf("failed to unmarshal JSON roundtrip: %v", err)
	}
	if roundtrip["type"] != "FeatureCollection" {
		t.Errorf("unmarshaled type is not FeatureCollection")
	}
}
