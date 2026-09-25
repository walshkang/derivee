package gtfs

import (
	"math"
	"testing"
	"time"
)

func TestPlatformCapsule_Orthogonality(t *testing.T) {
	// Canonical diagonal arc from (0, 0) to (0.01, 0.01)
	arcPts := []Point2D{
		{Lon: -73.940, Lat: 40.750},
		{Lon: -73.930, Lat: 40.755},
	}

	station := StationCandidate{
		ID:        "STA_1",
		Name:      "Test Station",
		Lon:       -73.935,
		Lat:       40.753,
		RouteIDs:  map[string]bool{"R1": true, "R2": true},
		RouteList: []string{"R1", "R2"},
	}

	proj, ok := ProjectStationToArc(station, arcPts, 150.0)
	if !ok {
		t.Fatalf("ProjectStationToArc failed to snap station within 150m")
	}

	// Verify INV-CAPSULE-01: Tangent · Normal == 0
	dot := proj.Tangent.X*proj.Normal.X + proj.Tangent.Y*proj.Normal.Y
	if math.Abs(dot) > 1e-6 {
		t.Fatalf("INV-CAPSULE-01 violation: Tangent · Normal = %f, expected 0", dot)
	}

	// Verify unit vectors
	tLen := math.Sqrt(proj.Tangent.X*proj.Tangent.X + proj.Tangent.Y*proj.Tangent.Y)
	nLen := math.Sqrt(proj.Normal.X*proj.Normal.X + proj.Normal.Y*proj.Normal.Y)
	if math.Abs(tLen-1.0) > 1e-6 || math.Abs(nLen-1.0) > 1e-6 {
		t.Fatalf("Unit vector length error: |T|=%f, |N|=%f", tLen, nLen)
	}
}

func TestPlatformCapsule_SpanBounds(t *testing.T) {
	opts := DefaultPlatformCapsuleOptions // TrackSpacing = 22.0m, Halo = 2.5m

	// K = 2
	spanK2 := float64(2-1)*opts.TrackSpacingM + 2.0*opts.HaloM
	expectedK2 := 1.0*opts.TrackSpacingM + 5.0
	if math.Abs(spanK2-expectedK2) > 1e-6 {
		t.Fatalf("INV-CAPSULE-02: K=2 span = %f, expected %f", spanK2, expectedK2)
	}
	if spanK2 < float64(2-1)*opts.TrackSpacingM {
		t.Fatalf("INV-CAPSULE-02 violation: span %f does not cover tracks %f", spanK2, opts.TrackSpacingM)
	}

	// K = 3
	spanK3 := float64(3-1)*opts.TrackSpacingM + 2.0*opts.HaloM
	expectedK3 := 2.0*opts.TrackSpacingM + 5.0
	if math.Abs(spanK3-expectedK3) > 1e-6 {
		t.Fatalf("INV-CAPSULE-02: K=3 span = %f, expected %f", spanK3, expectedK3)
	}
	if spanK3 < float64(3-1)*opts.TrackSpacingM {
		t.Fatalf("INV-CAPSULE-02 violation: span %f does not cover tracks %f", spanK3, 2.0*opts.TrackSpacingM)
	}
}

func TestPlatformCapsule_SnappingDistance(t *testing.T) {
	arcPts := []Point2D{
		{Lon: -73.940, Lat: 40.750},
		{Lon: -73.930, Lat: 40.750}, // Horizontal line at lat 40.750
	}

	// Station 50m north (should snap)
	nearStation := StationCandidate{
		ID:   "NEAR",
		Name: "Near Station",
		Lon:  -73.935,
		Lat:  40.750 + (50.0 / EarthRadiusM) * (180.0 / math.Pi),
	}
	projNear, okNear := ProjectStationToArc(nearStation, arcPts, 150.0)
	if !okNear {
		t.Fatalf("Near station (50m) was not snapped")
	}
	if projNear.DistanceM < 45.0 || projNear.DistanceM > 55.0 {
		t.Fatalf("Near station distance %f, expected ~50m", projNear.DistanceM)
	}

	// Station 250m north (should be rejected by INV-CAPSULE-06)
	farStation := StationCandidate{
		ID:   "FAR",
		Name: "Far Station",
		Lon:  -73.935,
		Lat:  40.750 + (250.0 / EarthRadiusM) * (180.0 / math.Pi),
	}
	_, okFar := ProjectStationToArc(farStation, arcPts, 150.0)
	if okFar {
		t.Fatalf("INV-CAPSULE-06 violation: Far station (250m) was snapped, expected rejection")
	}
}

func TestPlatformCapsule_Deduplication(t *testing.T) {
	ds := NewDataset(time.Now())

	// Routes
	ds.Routes["R1"] = Route{RouteID: "R1", RouteShortName: "1", RouteType: 1, RouteColor: "FF0000"}
	ds.Routes["R2"] = Route{RouteID: "R2", RouteShortName: "2", RouteType: 1, RouteColor: "0000FF"}

	// Two platforms belonging to the same parent station, 15m apart
	ds.Stops["P1"] = Stop{StopID: "P1", StopName: "Grand Junction", StopLat: 40.7500, StopLon: -73.9350, LocationType: 1}
	ds.Stops["P1_N"] = Stop{StopID: "P1_N", StopName: "Grand Junction NB", StopLat: 40.7501, StopLon: -73.9350, ParentStation: "P1"}
	ds.Stops["P1_S"] = Stop{StopID: "P1_S", StopName: "Grand Junction SB", StopLat: 40.7499, StopLon: -73.9350, ParentStation: "P1"}

	// Trips & StopTimes
	ds.Trips["T1"] = Trip{TripID: "T1", RouteID: "R1"}
	ds.Trips["T2"] = Trip{TripID: "T2", RouteID: "R2"}
	ds.StopTimes["T1"] = []StopTime{{TripID: "T1", StopID: "P1_N", StopSequence: 1}}
	ds.StopTimes["T2"] = []StopTime{{TripID: "T2", StopID: "P1_S", StopSequence: 1}}

	arcPts := []Point2D{
		{Lon: -73.940, Lat: 40.750},
		{Lon: -73.930, Lat: 40.750},
	}

	simplifiedArcs := map[int][]Point2D{
		1: arcPts,
	}

	arcBundles := map[int][]*TrunkBundle{
		1: {
			{BundleSize: 2, TrunkColor: "#FF0000", RouteNames: []string{"1"}, ModalClass: 0},
			{BundleSize: 2, TrunkColor: "#0000FF", RouteNames: []string{"2"}, ModalClass: 0},
		},
	}

	capsules, err := GeneratePlatformCapsules(ds, simplifiedArcs, arcBundles, DefaultPlatformCapsuleOptions)
	if err != nil {
		t.Fatalf("GeneratePlatformCapsules failed: %v", err)
	}

	// Should produce exactly 1 deduplicated capsule, not 2
	if len(capsules) != 1 {
		t.Fatalf("Expected exactly 1 deduplicated capsule, got %d", len(capsules))
	}

	capsule := capsules[0]
	if capsule.Properties.FeatureType != "platform_capsule" {
		t.Fatalf("Expected feature_type 'platform_capsule', got '%s'", capsule.Properties.FeatureType)
	}
	if capsule.Properties.BundleSize != 2 {
		t.Fatalf("Expected bundle_size 2, got %d", capsule.Properties.BundleSize)
	}
	if capsule.Properties.StationName != "Grand Junction" {
		t.Fatalf("Expected station_name 'Grand Junction', got '%s'", capsule.Properties.StationName)
	}

	// Verify coordinates represent a 2-point LineString
	coords, ok := capsule.Geometry.Coordinates.([][2]float64)
	if !ok || len(coords) != 2 {
		t.Fatalf("Expected 2-point LineString coordinates, got %#v", capsule.Geometry.Coordinates)
	}

	// Verify capsule is perpendicular: for horizontal corridor (lat=40.750), normal is vertical (lon is constant)
	if math.Abs(coords[0][0]-coords[1][0]) > 1e-4 {
		t.Fatalf("Capsule for horizontal arc should have identical Lon (vertical segment), got %f vs %f", coords[0][0], coords[1][0])
	}
}
