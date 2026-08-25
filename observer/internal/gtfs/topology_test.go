package gtfs

import (
	"encoding/json"
	"math"
	"testing"
	"time"
)

func TestTriangleArea(t *testing.T) {
	// A right-angled triangle at (0,0), (4,0), (0,3) should have area 6.0
	p1 := Point2D{Lon: 0, Lat: 0}
	p2 := Point2D{Lon: 4, Lat: 0}
	p3 := Point2D{Lon: 0, Lat: 3}

	area := TriangleArea(p1, p2, p3)
	if math.Abs(area-6.0) > 1e-9 {
		t.Fatalf("Expected area 6.0, got %f", area)
	}

	// Collinear points should have area 0.0
	pCollinear := Point2D{Lon: 2, Lat: 0}
	areaCollinear := TriangleArea(p1, pCollinear, p2)
	if math.Abs(areaCollinear) > 1e-9 {
		t.Fatalf("Expected collinear area 0.0, got %f", areaCollinear)
	}
}

func TestVisvalingamWhyattSimplification(t *testing.T) {
	// A line with a minor bump in the middle
	pts := []Point2D{
		{Lon: 0.0, Lat: 0.0},
		{Lon: 1.0, Lat: 0.0001}, // small deviation
		{Lon: 2.0, Lat: 0.0},
		{Lon: 3.0, Lat: 1.0},    // sharp turn
		{Lon: 4.0, Lat: 1.0},
	}

	areas := ComputeEffectiveAreas(pts)
	if len(areas) != len(pts) {
		t.Fatalf("Expected %d effective areas, got %d", len(pts), len(areas))
	}

	// Endpoints must have area Inf
	if !math.IsInf(areas[0], 1) || !math.IsInf(areas[len(pts)-1], 1) {
		t.Fatalf("Endpoints must have Inf effective area: %v, %v", areas[0], areas[len(pts)-1])
	}

	// The minor bump at index 1 should have smaller effective area than the sharp turn at index 3
	if areas[1] >= areas[3] {
		t.Fatalf("Expected bump at index 1 area (%f) to be < sharp turn at index 3 (%f)", areas[1], areas[3])
	}

	// Simplifying with threshold between areas[1] and areas[3] should remove index 1 and keep index 3
	threshold := (areas[1] + areas[3]) / 2.0
	simplified := SimplifyPoints(pts, threshold)

	if len(simplified) != 4 {
		t.Fatalf("Expected 4 points after simplifying bump, got %d", len(simplified))
	}
	if simplified[1].Lon != 2.0 || simplified[1].Lat != 0.0 {
		t.Fatalf("Expected point 2.0, 0.0 at index 1, got %v", simplified[1])
	}
}

func TestPlanarTopologyGraphExtractionAndJunctionLocking(t *testing.T) {
	// Simulate 3 routes sharing a central trunk:
	// Route 4: A -> B -> C -> D -> E
	// Route 5: A -> B -> C -> D -> F (branches off at D)
	// Route 6: G -> B -> C -> D -> E (merges at B)
	shapes := map[string][]ShapePoint{
		"shape_4": {
			{ShapeID: "shape_4", ShapePtLon: -74.00, ShapePtLat: 40.70, ShapePtSequence: 1}, // A
			{ShapeID: "shape_4", ShapePtLon: -73.98, ShapePtLat: 40.75, ShapePtSequence: 2}, // B (Merge)
			{ShapeID: "shape_4", ShapePtLon: -73.96, ShapePtLat: 40.78, ShapePtSequence: 3}, // C (Trunk intermediate)
			{ShapeID: "shape_4", ShapePtLon: -73.94, ShapePtLat: 40.80, ShapePtSequence: 4}, // D (Branch)
			{ShapeID: "shape_4", ShapePtLon: -73.90, ShapePtLat: 40.85, ShapePtSequence: 5}, // E
		},
		"shape_5": {
			{ShapeID: "shape_5", ShapePtLon: -74.00, ShapePtLat: 40.70, ShapePtSequence: 1}, // A
			{ShapeID: "shape_5", ShapePtLon: -73.98, ShapePtLat: 40.75, ShapePtSequence: 2}, // B
			{ShapeID: "shape_5", ShapePtLon: -73.96, ShapePtLat: 40.78, ShapePtSequence: 3}, // C
			{ShapeID: "shape_5", ShapePtLon: -73.94, ShapePtLat: 40.80, ShapePtSequence: 4}, // D
			{ShapeID: "shape_5", ShapePtLon: -73.88, ShapePtLat: 40.88, ShapePtSequence: 5}, // F
		},
		"shape_6": {
			{ShapeID: "shape_6", ShapePtLon: -74.02, ShapePtLat: 40.71, ShapePtSequence: 1}, // G
			{ShapeID: "shape_6", ShapePtLon: -73.98, ShapePtLat: 40.75, ShapePtSequence: 2}, // B
			{ShapeID: "shape_6", ShapePtLon: -73.96, ShapePtLat: 40.78, ShapePtSequence: 3}, // C
			{ShapeID: "shape_6", ShapePtLon: -73.94, ShapePtLat: 40.80, ShapePtSequence: 4}, // D
			{ShapeID: "shape_6", ShapePtLon: -73.90, ShapePtLat: 40.85, ShapePtSequence: 5}, // E
		},
	}

	graph := BuildTopologyGraph(shapes)

	// Terminals A, E, F, G must be junctions
	nodeA := ToPointKey(Point2D{Lon: -74.00, Lat: 40.70})
	nodeE := ToPointKey(Point2D{Lon: -73.90, Lat: 40.85})
	nodeF := ToPointKey(Point2D{Lon: -73.88, Lat: 40.88})
	nodeG := ToPointKey(Point2D{Lon: -74.02, Lat: 40.71})

	if !graph.Junctions[nodeA] || !graph.Junctions[nodeE] || !graph.Junctions[nodeF] || !graph.Junctions[nodeG] {
		t.Fatalf("Expected all terminals to be locked junctions")
	}

	// Intersection/Branch nodes B and D must be junctions
	nodeB := ToPointKey(Point2D{Lon: -73.98, Lat: 40.75})
	nodeD := ToPointKey(Point2D{Lon: -73.94, Lat: 40.80})

	if !graph.Junctions[nodeB] {
		t.Fatalf("Expected merge node B to be detected as junction")
	}
	if !graph.Junctions[nodeD] {
		t.Fatalf("Expected branch node D to be detected as junction")
	}

	// Trunk intermediate node C should NOT be a junction (it's inside the shared B->C->D arc)
	nodeC := ToPointKey(Point2D{Lon: -73.96, Lat: 40.78})
	if graph.Junctions[nodeC] {
		t.Fatalf("Expected intermediate trunk node C to NOT be a junction")
	}

	// Check shared arc between B and D across shapes 4, 5, 6
	// Shape 4 refs
	var trunkArcID4, trunkArcID5, trunkArcID6 int = -1, -1, -1
	for _, ref := range graph.ShapeArcs["shape_4"] {
		arc := graph.Arcs[ref.ArcID]
		if (arc.StartKey == nodeB && arc.EndKey == nodeD) || (arc.StartKey == nodeD && arc.EndKey == nodeB) {
			trunkArcID4 = ref.ArcID
		}
	}
	for _, ref := range graph.ShapeArcs["shape_5"] {
		arc := graph.Arcs[ref.ArcID]
		if (arc.StartKey == nodeB && arc.EndKey == nodeD) || (arc.StartKey == nodeD && arc.EndKey == nodeB) {
			trunkArcID5 = ref.ArcID
		}
	}
	for _, ref := range graph.ShapeArcs["shape_6"] {
		arc := graph.Arcs[ref.ArcID]
		if (arc.StartKey == nodeB && arc.EndKey == nodeD) || (arc.StartKey == nodeD && arc.EndKey == nodeB) {
			trunkArcID6 = ref.ArcID
		}
	}

	if trunkArcID4 == -1 || trunkArcID5 == -1 || trunkArcID6 == -1 {
		t.Fatalf("Failed to find trunk arc for one or more shapes")
	}
	if trunkArcID4 != trunkArcID5 || trunkArcID5 != trunkArcID6 {
		t.Fatalf("Zero Z-Fighting violated: shapes 4, 5, 6 do not share the exact same canonical Arc ID (%d, %d, %d)",
			trunkArcID4, trunkArcID5, trunkArcID6)
	}
}

func TestGenerateTransitLinesGeoJSONZeroZFighting(t *testing.T) {
	ds := NewDataset(time.Now())

	// Subway Route Red (modal_class = 0)
	ds.Routes["Red"] = Route{
		RouteID:        "Red",
		RouteShortName: "RL",
		RouteLongName:  "Red Line",
		RouteType:      1,
		RouteColor:     "#DA291C",
	}
	// LRT Route Green-B (modal_class = 1)
	ds.Routes["Green-B"] = Route{
		RouteID:        "Green-B",
		RouteShortName: "B",
		RouteLongName:  "Green Line B",
		RouteType:      0,
		RouteColor:     "#00843D",
	}
	// LRT Route Green-C (modal_class = 1) sharing trunk with Green-B
	ds.Routes["Green-C"] = Route{
		RouteID:        "Green-C",
		RouteShortName: "C",
		RouteLongName:  "Green Line C",
		RouteType:      0,
		RouteColor:     "#00843D",
	}
	// Bus Route (modal_class = 2) - should be filtered out!
	ds.Routes["1"] = Route{
		RouteID:        "1",
		RouteShortName: "1",
		RouteLongName:  "Harvard - Dudley Bus",
		RouteType:      3,
		RouteColor:     "#FFC72C",
	}
	// Ferry Route (modal_class = 3)
	ds.Routes["F4"] = Route{
		RouteID:        "F4",
		RouteShortName: "F4",
		RouteLongName:  "Charlestown Ferry",
		RouteType:      4,
		RouteColor:     "#00A3E0",
	}

	// Add trips
	ds.Trips["t_red"] = Trip{TripID: "t_red", RouteID: "Red", ShapeID: "shape_red"}
	ds.Trips["t_gb"] = Trip{TripID: "t_gb", RouteID: "Green-B", ShapeID: "shape_gb"}
	ds.Trips["t_gc"] = Trip{TripID: "t_gc", RouteID: "Green-C", ShapeID: "shape_gc"}
	ds.Trips["t_bus"] = Trip{TripID: "t_bus", RouteID: "1", ShapeID: "shape_bus"}
	ds.Trips["t_ferry"] = Trip{TripID: "t_ferry", RouteID: "F4", ShapeID: "shape_ferry"}

	// Shapes: Green-B and Green-C share Park St -> Boylston -> Copley
	ds.Shapes["shape_red"] = []ShapePoint{
		{ShapeID: "shape_red", ShapePtLon: -71.0589, ShapePtLat: 42.3601, ShapePtSequence: 1},
		{ShapeID: "shape_red", ShapePtLon: -71.0570, ShapePtLat: 42.3550, ShapePtSequence: 2},
		{ShapeID: "shape_red", ShapePtLon: -71.0600, ShapePtLat: 42.3500, ShapePtSequence: 3},
	}
	ds.Shapes["shape_gb"] = []ShapePoint{
		{ShapeID: "shape_gb", ShapePtLon: -71.0620, ShapePtLat: 42.3560, ShapePtSequence: 1}, // Park St
		{ShapeID: "shape_gb", ShapePtLon: -71.0650, ShapePtLat: 42.3530, ShapePtSequence: 2}, // Boylston
		{ShapeID: "shape_gb", ShapePtLon: -71.0760, ShapePtLat: 42.3500, ShapePtSequence: 3}, // Copley
		{ShapeID: "shape_gb", ShapePtLon: -71.1200, ShapePtLat: 42.3450, ShapePtSequence: 4}, // Boston College
	}
	ds.Shapes["shape_gc"] = []ShapePoint{
		{ShapeID: "shape_gc", ShapePtLon: -71.0620, ShapePtLat: 42.3560, ShapePtSequence: 1}, // Park St
		{ShapeID: "shape_gc", ShapePtLon: -71.0650, ShapePtLat: 42.3530, ShapePtSequence: 2}, // Boylston
		{ShapeID: "shape_gc", ShapePtLon: -71.0760, ShapePtLat: 42.3500, ShapePtSequence: 3}, // Copley
		{ShapeID: "shape_gc", ShapePtLon: -71.1400, ShapePtLat: 42.3380, ShapePtSequence: 4}, // Cleveland Circle
	}
	ds.Shapes["shape_bus"] = []ShapePoint{
		{ShapeID: "shape_bus", ShapePtLon: -71.1180, ShapePtLat: 42.3730, ShapePtSequence: 1},
		{ShapeID: "shape_bus", ShapePtLon: -71.0850, ShapePtLat: 42.3300, ShapePtSequence: 2},
	}
	ds.Shapes["shape_ferry"] = []ShapePoint{
		{ShapeID: "shape_ferry", ShapePtLon: -71.0500, ShapePtLat: 42.3700, ShapePtSequence: 1},
		{ShapeID: "shape_ferry", ShapePtLon: -71.0450, ShapePtLat: 42.3600, ShapePtSequence: 2},
	}

	fc, rawBytes, err := GenerateTransitLinesGeoJSON(ds)
	if err != nil {
		t.Fatalf("GenerateTransitLinesGeoJSON failed: %v", err)
	}

	if len(fc.Features) != 4 {
		t.Fatalf("Expected 4 features (Red, Green-B, Green-C, Ferry; Bus excluded), got %d", len(fc.Features))
	}

	// Verify valid JSON
	var parsed map[string]interface{}
	if err := json.Unmarshal(rawBytes, &parsed); err != nil {
		t.Fatalf("Generated rawBytes failed json unmarshal: %v", err)
	}

	// Verify Bus route is not in features
	for _, f := range fc.Features {
		if f.Properties.RouteID == "1" {
			t.Fatalf("Bus route 1 was not excluded from transit-lines.geojson")
		}
	}

	// Verify Green-B and Green-C shared segment coordinates match bit-for-bit
	var gbCoords, gcCoords [][2]float64
	for _, f := range fc.Features {
		if f.Properties.RouteID == "Green-B" {
			if lines, ok := f.Geometry.Coordinates.([][2]float64); ok {
				gbCoords = lines
			}
		}
		if f.Properties.RouteID == "Green-C" {
			if lines, ok := f.Geometry.Coordinates.([][2]float64); ok {
				gcCoords = lines
			}
		}
	}

	if len(gbCoords) < 3 || len(gcCoords) < 3 {
		t.Fatalf("Expected at least 3 points in gbCoords and gcCoords")
	}

	// Shared Park St -> Boylston -> Copley (first 3 points) must be identical
	for i := 0; i < 3; i++ {
		if gbCoords[i][0] != gcCoords[i][0] || gbCoords[i][1] != gcCoords[i][1] {
			t.Fatalf("Z-Fighting detected: point %d differs between Green-B (%v) and Green-C (%v)",
				i, gbCoords[i], gcCoords[i])
		}
	}
}
