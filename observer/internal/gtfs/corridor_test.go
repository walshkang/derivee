package gtfs

import (
	"encoding/json"
	"strings"
	"testing"
	"time"
)

// TestInvariant_INV_CORR_01_DeduplicationColorDistance verifies that routes sharing trunk color
// are consolidated (delta E <= 2.0), while cross-agency and cross-mode routes are never merged.
func TestInvariant_INV_CORR_01_DeduplicationColorDistance(t *testing.T) {
	// Case 1: NYC Subway Lexington Ave (4, 5, 6) sharing MTA Green (#00933C)
	routesLex := []Route{
		{RouteID: "4", AgencyID: "MTA", RouteShortName: "4", RouteLongName: "Lexington Ave Express", RouteType: 1, RouteColor: "00933C"},
		{RouteID: "5", AgencyID: "MTA", RouteShortName: "5", RouteLongName: "Lexington Ave Express", RouteType: 1, RouteColor: "00933C"},
		{RouteID: "6", AgencyID: "MTA", RouteShortName: "6", RouteLongName: "Lexington Ave Local", RouteType: 1, RouteColor: "00933C"},
	}

	bundlesLex, err := ConsolidateCorridorBundles(routesLex, DefaultColorDistance)
	if err != nil {
		t.Fatalf("Consolidation failed: %v", err)
	}
	if len(bundlesLex) != 1 {
		t.Fatalf("INV-CORR-01 violated: expected 1 consolidated bundle for 4/5/6, got %d", len(bundlesLex))
	}
	bLex := bundlesLex[0]
	if bLex.TrunkColor != "#00933C" {
		t.Errorf("Expected trunk color #00933C, got %s", bLex.TrunkColor)
	}
	if len(bLex.RouteNames) != 3 {
		t.Errorf("Expected 3 routes in bundle, got %v", bLex.RouteNames)
	}
	if bLex.CompositeKey != "badge_4_5_6" {
		t.Errorf("Expected composite key badge_4_5_6, got %s", bLex.CompositeKey)
	}

	// Case 2: Cross-Agency Isolation (MTA 8th Ave Blue vs. PATH Blue)
	// Prohibit cross-agency consolidation even if colors are identical or close
	routesCrossAgency := []Route{
		{RouteID: "A", AgencyID: "MTA", RouteShortName: "A", RouteType: 1, RouteColor: "0039A6"},
		{RouteID: "PATH-NWK-WTC", AgencyID: "PATH", RouteShortName: "NWK-WTC", RouteType: 1, RouteColor: "0062AF"},
	}

	bundlesCrossAgency, err := ConsolidateCorridorBundles(routesCrossAgency, DefaultColorDistance)
	if err != nil {
		t.Fatalf("Consolidation failed: %v", err)
	}
	if len(bundlesCrossAgency) != 2 {
		t.Fatalf("INV-CORR-01 cross-agency barrier violated: expected 2 distinct bundles, got %d", len(bundlesCrossAgency))
	}

	// Even if PATH used the exact same hex as MTA:
	routesIdenticalHexCrossAgency := []Route{
		{RouteID: "A", AgencyID: "MTA", RouteShortName: "A", RouteType: 1, RouteColor: "0039A6"},
		{RouteID: "PATH-TEST", AgencyID: "PATH", RouteShortName: "PATH", RouteType: 1, RouteColor: "0039A6"},
	}
	bundlesSameHex, err := ConsolidateCorridorBundles(routesIdenticalHexCrossAgency, DefaultColorDistance)
	if err != nil {
		t.Fatalf("Consolidation failed: %v", err)
	}
	if len(bundlesSameHex) != 2 {
		t.Fatalf("INV-CORR-01 cross-agency barrier violated: identical hex from different agencies must remain 2 bundles, got %d", len(bundlesSameHex))
	}

	// Case 3: Cross-Modal Isolation (LRT Green vs. Ferry Cyan)
	routesCrossModal := []Route{
		{RouteID: "Green-B", AgencyID: "MBTA", RouteShortName: "B", RouteType: 0, RouteColor: "00843D"},
		{RouteID: "F4", AgencyID: "MBTA", RouteShortName: "F4", RouteType: 4, RouteColor: "00843D"}, // Hypothetical green ferry
	}
	bundlesCrossModal, err := ConsolidateCorridorBundles(routesCrossModal, DefaultColorDistance)
	if err != nil {
		t.Fatalf("Consolidation failed: %v", err)
	}
	if len(bundlesCrossModal) != 2 {
		t.Fatalf("Cross-mode barrier violated: LRT and Ferry must remain distinct bundles, got %d", len(bundlesCrossModal))
	}
}

// TestInvariant_INV_CORR_02_MultiplicityCeiling verifies that bundle sizes never exceed K <= 3
func TestInvariant_INV_CORR_02_MultiplicityCeiling(t *testing.T) {
	// Queens Blvd trunk: E (Blue), F (Orange), M (Orange), R (Yellow)
	routesQBL := []Route{
		{RouteID: "E", AgencyID: "MTA", RouteShortName: "E", RouteType: 1, RouteColor: "0039A6"},
		{RouteID: "F", AgencyID: "MTA", RouteShortName: "F", RouteType: 1, RouteColor: "FF6319"},
		{RouteID: "M", AgencyID: "MTA", RouteShortName: "M", RouteType: 1, RouteColor: "FF6319"},
		{RouteID: "R", AgencyID: "MTA", RouteShortName: "R", RouteType: 1, RouteColor: "FCCC0A"},
	}

	bundlesQBL, err := ConsolidateCorridorBundles(routesQBL, DefaultColorDistance)
	if err != nil {
		t.Fatalf("Queens Blvd consolidation failed: %v", err)
	}

	if len(bundlesQBL) != 3 {
		t.Fatalf("INV-CORR-02 violated: expected K=3 for Queens Blvd (Blue E, Orange F/M, Yellow R), got %d", len(bundlesQBL))
	}

	// Check deterministic ordering and indexing
	for i, b := range bundlesQBL {
		if b.BundleIndex != i {
			t.Errorf("Bundle %d has incorrect BundleIndex %d", i, b.BundleIndex)
		}
		if b.BundleSize != 3 {
			t.Errorf("Bundle %d has incorrect BundleSize %d (expected 3)", i, b.BundleSize)
		}
	}

	// Check F and M consolidated into Orange ribbon
	foundOrange := false
	for _, b := range bundlesQBL {
		if b.TrunkColor == "#FF6319" {
			foundOrange = true
			if len(b.RouteNames) != 2 {
				t.Errorf("Expected 2 routes (F, M) in Orange bundle, got %v", b.RouteNames)
			}
			if b.CompositeKey != "badge_F_M" {
				t.Errorf("Expected composite key badge_F_M, got %s", b.CompositeKey)
			}
		}
	}
	if !foundOrange {
		t.Errorf("Orange trunk bundle missing from Queens Blvd")
	}

	// Test invariant enforcement when K > 3
	routesTooMany := []Route{
		{RouteID: "1", AgencyID: "MTA", RouteShortName: "1", RouteType: 1, RouteColor: "EE352E"}, // Red
		{RouteID: "4", AgencyID: "MTA", RouteShortName: "4", RouteType: 1, RouteColor: "00933C"}, // Green
		{RouteID: "7", AgencyID: "MTA", RouteShortName: "7", RouteType: 1, RouteColor: "B933AD"}, // Purple
		{RouteID: "A", AgencyID: "MTA", RouteShortName: "A", RouteType: 1, RouteColor: "0039A6"}, // Blue
	}
	_, errOverflow := ConsolidateCorridorBundles(routesTooMany, DefaultColorDistance)
	if errOverflow == nil {
		t.Fatalf("Expected error when K > 3 (INV-CORR-02), but got nil")
	}
	if !strings.Contains(errOverflow.Error(), "INV-CORR-02 violated") {
		t.Errorf("Expected INV-CORR-02 violation message, got: %v", errOverflow)
	}
}

// TestInvariant_INV_CORR_03_CanonicalDirectionality verifies that all canonical arcs and emitted GeoJSON
// features follow strict longitudinal ordering: NodeKey(Start) < NodeKey(End)
func TestInvariant_INV_CORR_03_CanonicalDirectionality(t *testing.T) {
	// Northbound shape (South to North: Lat increases)
	// Southbound shape (North to South: Lat decreases)
	shapes := map[string][]ShapePoint{
		"shape_nb": {
			{ShapeID: "shape_nb", ShapePtLon: -73.98, ShapePtLat: 40.70, ShapePtSequence: 1},
			{ShapeID: "shape_nb", ShapePtLon: -73.98, ShapePtLat: 40.75, ShapePtSequence: 2},
			{ShapeID: "shape_nb", ShapePtLon: -73.98, ShapePtLat: 40.80, ShapePtSequence: 3},
		},
		"shape_sb": {
			{ShapeID: "shape_sb", ShapePtLon: -73.98, ShapePtLat: 40.80, ShapePtSequence: 1},
			{ShapeID: "shape_sb", ShapePtLon: -73.98, ShapePtLat: 40.75, ShapePtSequence: 2},
			{ShapeID: "shape_sb", ShapePtLon: -73.98, ShapePtLat: 40.70, ShapePtSequence: 3},
		},
	}

	graph := BuildTopologyGraph(shapes)

	// Both directional shapes must collapse onto a single canonical Arc
	if len(graph.Arcs) != 1 {
		t.Fatalf("Expected 1 canonical Arc for opposing NB/SB shapes, got %d", len(graph.Arcs))
	}

	arc := graph.Arcs[0]
	// Verify INV-CORR-03: Arc.StartKey must be strictly less than Arc.EndKey
	if !LessPointKey(arc.StartKey, arc.EndKey) {
		t.Fatalf("INV-CORR-03 violated: arc %d start %v is not < end %v", arc.ID, arc.StartKey, arc.EndKey)
	}

	// Verify points array starts at StartKey and ends at EndKey
	firstPointKey := ToPointKey(arc.Points[0])
	lastPointKey := ToPointKey(arc.Points[len(arc.Points)-1])
	if firstPointKey != arc.StartKey || lastPointKey != arc.EndKey {
		t.Fatalf("Arc points orientation mismatch: points[0]=%v != StartKey=%v or points[last]=%v != EndKey=%v",
			firstPointKey, arc.StartKey, lastPointKey, arc.EndKey)
	}

	// End-to-end dataset with NB and SB trips
	ds := NewDataset(time.Now())
	ds.Routes["1"] = Route{RouteID: "1", RouteShortName: "1", RouteType: 1, RouteColor: "EE352E"}
	ds.Trips["t_nb"] = Trip{TripID: "t_nb", RouteID: "1", ShapeID: "shape_nb"}
	ds.Trips["t_sb"] = Trip{TripID: "t_sb", RouteID: "1", ShapeID: "shape_sb"}
	ds.Shapes["shape_nb"] = shapes["shape_nb"]
	ds.Shapes["shape_sb"] = shapes["shape_sb"]

	fc, _, err := GenerateTransitLinesGeoJSON(ds)
	if err != nil {
		t.Fatalf("GenerateTransitLinesGeoJSON failed: %v", err)
	}

	// Because NB and SB share the canonical arc, exactly 1 feature must be emitted (zero duplicate centerlines)
	if len(fc.Features) != 1 {
		t.Fatalf("Expected exactly 1 feature for bidirectional route 1, got %d", len(fc.Features))
	}

	feat := fc.Features[0]
	coords, ok := feat.Geometry.Coordinates.([][2]float64)
	if !ok || len(coords) < 2 {
		t.Fatalf("Invalid LineString coordinates in emitted feature")
	}

	startP := ToPointKey(Point2D{Lon: coords[0][0], Lat: coords[0][1]})
	endP := ToPointKey(Point2D{Lon: coords[len(coords)-1][0], Lat: coords[len(coords)-1][1]})
	if !LessPointKey(startP, endP) {
		t.Fatalf("Emitted GeoJSON feature does not follow canonical direction: start=%v, end=%v", startP, endP)
	}
}

// TestBackwardCompatibility_GeoJSONProperties verifies that all dual keys and additive corridor attributes
// are populated and valid for existing Swift MapLibre expressions.
func TestBackwardCompatibility_GeoJSONProperties(t *testing.T) {
	ds := NewDataset(time.Now())
	ds.Routes["4"] = Route{RouteID: "4", RouteShortName: "4", RouteLongName: "Lexington Ave Express", RouteType: 1, RouteColor: "00933C"}
	ds.Routes["5"] = Route{RouteID: "5", RouteShortName: "5", RouteLongName: "Lexington Ave Express", RouteType: 1, RouteColor: "00933C"}
	ds.Trips["t4"] = Trip{TripID: "t4", RouteID: "4", ShapeID: "shape_lex"}
	ds.Trips["t5"] = Trip{TripID: "t5", RouteID: "5", ShapeID: "shape_lex"}
	ds.Shapes["shape_lex"] = []ShapePoint{
		{ShapeID: "shape_lex", ShapePtLon: -73.9864, ShapePtLat: 40.7484, ShapePtSequence: 1},
		{ShapeID: "shape_lex", ShapePtLon: -73.9801, ShapePtLat: 40.7523, ShapePtSequence: 2},
		{ShapeID: "shape_lex", ShapePtLon: -73.9742, ShapePtLat: 40.7561, ShapePtSequence: 3},
	}

	fc, rawBytes, err := GenerateTransitLinesGeoJSON(ds)
	if err != nil {
		t.Fatalf("GenerateTransitLinesGeoJSON failed: %v", err)
	}

	if len(fc.Features) != 1 {
		t.Fatalf("Expected 1 consolidated feature for 4 and 5, got %d", len(fc.Features))
	}

	feat := fc.Features[0]
	props := feat.Properties

	// 1. Casing and Trunk Color keys
	if props.TrunkColor != "#00933C" || props.TrunkColorHex != "#00933C" {
		t.Errorf("TrunkColor failure: trunk_color=%s, trunk_color_hex=%s", props.TrunkColor, props.TrunkColorHex)
	}
	if props.CasingColor != "#FFFFFF" || props.CasingColorHex != "#FFFFFF" {
		t.Errorf("Casing dual-key failure: casing=%s, casing_hex=%s", props.CasingColor, props.CasingColorHex)
	}

	// 2. Wave V.3+V.4 casing widths, sorting, and arc length
	if props.CasingWidth != 4.5 || props.CasingWidthZ11 != 2.5 || props.CasingWidthZ17 != 8.1 {
		t.Errorf("Casing widths failure: z11=%f, z14=%f, z17=%f", props.CasingWidthZ11, props.CasingWidth, props.CasingWidthZ17)
	}
	if props.SortKey <= 0 {
		t.Errorf("Invalid sort_key: %d", props.SortKey)
	}
	if props.ArcLengthM <= 0 {
		t.Errorf("Invalid arc_length_m: %f", props.ArcLengthM)
	}
	if props.BundleSize != 1 {
		t.Errorf("Expected bundle_size 1, got %d", props.BundleSize)
	}
	if props.BundleIndex != 0 {
		t.Errorf("Expected bundle_index 0, got %d", props.BundleIndex)
	}
	if props.CompositeKey != "badge_4_5" {
		t.Errorf("Expected composite_key badge_4_5, got %s", props.CompositeKey)
	}
	if len(props.Routes) != 2 || props.Routes[0] != "4" || props.Routes[1] != "5" {
		t.Errorf("Expected routes [4, 5], got %v", props.Routes)
	}
	if !strings.HasPrefix(props.CorridorID, "corridor_arc_") {
		t.Errorf("Invalid corridor_id: %s", props.CorridorID)
	}

	// 3. Raw JSON validation
	var rawMap map[string]interface{}
	if err := json.Unmarshal(rawBytes, &rawMap); err != nil {
		t.Fatalf("JSON unmarshal failed: %v", err)
	}
}

// TestParallelCorridorBundling_MultiColorOffsets verifies Queens Boulevard multi-color bundle (K=3: E Blue, F Orange, R Yellow)
func TestParallelCorridorBundling_MultiColorOffsets(t *testing.T) {
	ds := NewDataset(time.Now())
	// E (Blue #0039A6), F (Orange #FF6319), R (Yellow #FCCC0A)
	ds.Routes["E"] = Route{RouteID: "E", RouteShortName: "E", RouteLongName: "8th Ave Express", RouteType: 1, RouteColor: "0039A6"}
	ds.Routes["F"] = Route{RouteID: "F", RouteShortName: "F", RouteLongName: "6th Ave Express", RouteType: 1, RouteColor: "FF6319"}
	ds.Routes["R"] = Route{RouteID: "R", RouteShortName: "R", RouteLongName: "Broadway Local", RouteType: 1, RouteColor: "FCCC0A"}

	ds.Trips["tE"] = Trip{TripID: "tE", RouteID: "E", ShapeID: "shape_qbl"}
	ds.Trips["tF"] = Trip{TripID: "tF", RouteID: "F", ShapeID: "shape_qbl"}
	ds.Trips["tR"] = Trip{TripID: "tR", RouteID: "R", ShapeID: "shape_qbl"}

	ds.Shapes["shape_qbl"] = []ShapePoint{
		{ShapeID: "shape_qbl", ShapePtLon: -73.937225, ShapePtLat: 40.749718, ShapePtSequence: 1},
		{ShapeID: "shape_qbl", ShapePtLon: -73.934166, ShapePtLat: 40.750875, ShapePtSequence: 2},
		{ShapeID: "shape_qbl", ShapePtLon: -73.929851, ShapePtLat: 40.752314, ShapePtSequence: 3},
		{ShapeID: "shape_qbl", ShapePtLon: -73.925812, ShapePtLat: 40.753892, ShapePtSequence: 4},
	}

	fc, _, err := GenerateTransitLinesGeoJSON(ds)
	if err != nil {
		t.Fatalf("GenerateTransitLinesGeoJSON failed: %v", err)
	}

	if len(fc.Features) != 3 {
		t.Fatalf("Expected exactly 3 parallel ribbon features for K=3 Queens Blvd, got %d", len(fc.Features))
	}

	// Verify properties and offset coordinates
	seenOffsets := make(map[float64]bool)
	var coordsList [][][2]float64

	for i, feat := range fc.Features {
		props := feat.Properties
		if props.BundleSize != 3 {
			t.Errorf("Feature %d: expected bundle_size 3, got %d", i, props.BundleSize)
		}
		if props.BundleIndex != i {
			t.Errorf("Feature %d: expected bundle_index %d, got %d", i, i, props.BundleIndex)
		}

		seenOffsets[props.DeltaOffset] = true

		coords, ok := ParseLineCoords(feat.Geometry.Coordinates)
		if !ok || len(coords) < 4 {
			t.Fatalf("Feature %d: invalid coordinates", i)
		}
		coordsList = append(coordsList, coords)

		// Zero self-intersections (INV-OFFSET-02)
		var pts2D []Point2D
		for _, c := range coords {
			pts2D = append(pts2D, Point2D{Lon: c[0], Lat: c[1]})
		}
		metricCoords, _, _ := ProjectToLocalM(pts2D)
		if err := ValidateSelfIntersections_INV_OFFSET_02(metricCoords); err != nil {
			t.Errorf("Feature %d: INV-OFFSET-02 violated: %v", i, err)
		}
	}

	// Verify offsets: -3.5pt, 0.0pt, +3.5pt
	if !seenOffsets[-3.5] || !seenOffsets[0.0] || !seenOffsets[3.5] {
		t.Errorf("Expected delta_offset values [-3.5, 0.0, 3.5], got map: %v", seenOffsets)
	}

	// Verify that ribbons are geometrically distinct (parallel separation)
	c0 := coordsList[0]
	c1 := coordsList[1]
	c2 := coordsList[2]

	for j := 0; j < len(c0); j++ {
		// Latitude and longitude should differ between ribbon 0, ribbon 1, ribbon 2
		dist01 := CalculateHaversineDistance(c0[j][1], c0[j][0], c1[j][1], c1[j][0])
		dist12 := CalculateHaversineDistance(c1[j][1], c1[j][0], c2[j][1], c2[j][0])
		if dist01 < 1.0 {
			t.Errorf("Vertex %d: ribbon 0 and ribbon 1 too close (<1m): %.3fm", j, dist01)
		}
		if dist12 < 1.0 {
			t.Errorf("Vertex %d: ribbon 1 and ribbon 2 too close (<1m): %.3fm", j, dist12)
		}
	}
}

