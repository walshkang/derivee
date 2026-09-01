package walk

import (
	"math"
	"testing"
)

func TestCoordinateQuantizationPrecision(t *testing.T) {
	testPoints := [][2]float64{
		{40.758896, -73.985130}, // Times Square
		{40.752726, -73.977229}, // Grand Central
		{42.360082, -71.058880}, // Boston Common
		{0.0, 0.0},              // Equator
		{85.0511, 179.9999},     // Polar limit
	}

	for _, pt := range testPoints {
		lat := pt[0]
		lon := pt[1]

		latQ := int32(math.Round(lat * 1e7))
		lonQ := int32(math.Round(lon * 1e7))

		latDequant := float64(latQ) * 1e-7
		lonDequant := float64(lonQ) * 1e-7

		latDiff := math.Abs(lat - latDequant)
		lonDiff := math.Abs(lon - lonDequant)

		if latDiff > 5e-8 {
			t.Errorf("latitude quantization error too large: %g for %f", latDiff, lat)
		}
		if lonDiff > 5e-8 {
			t.Errorf("longitude quantization error too large: %g for %f", lonDiff, lon)
		}

		// Maximum error in meters on earth surface (< 1.11 cm)
		errorMeters := latDiff * 111320.0
		if errorMeters > 0.011132 {
			t.Errorf("quantization surface error exceeds 1.11cm threshold: %f m", errorMeters)
		}
	}
}

func TestCalculateDistanceCM(t *testing.T) {
	// Point A: Times Square (40.758896, -73.985130)
	lat1Q := int32(407588960)
	lon1Q := int32(-739851300)

	// Same point -> 0 cm
	if d := CalculateDistanceCM(lat1Q, lon1Q, lat1Q, lon1Q); d != 0 {
		t.Errorf("distance to self should be 0, got %d", d)
	}

	// Point B: ~100 meters east
	// 0.00118 degrees longitude at lat 40.758896 is ~100 meters
	lon2Q := lon1Q + 11800 // +0.00118 * 1e7
	distCM := CalculateDistanceCM(lat1Q, lon1Q, lat1Q, lon2Q)

	if distCM < 9500 || distCM > 10500 {
		t.Errorf("expected distance around 10000 cm (~100m), got %d cm", distCM)
	}
}

func TestCalculateWeightMS(t *testing.T) {
	// 20 meters (2000 cm) at 1.33 m/s = 15.037 seconds = 15,038 ms
	wStandard := CalculateWeightMS(2000, FlagWalkable)
	if wStandard < 15000 || wStandard > 15100 {
		t.Errorf("expected ~15038 ms for 20m standard walk, got %d", wStandard)
	}

	// Steps: 0.66 m/s -> ~30,303 ms
	wSteps := CalculateWeightMS(2000, FlagWalkable|FlagIsSteps)
	if wSteps < 30200 || wSteps > 30400 {
		t.Errorf("expected ~30303 ms for 20m steps, got %d", wSteps)
	}

	// Elevator: 20m traversal + 30,000 ms wait penalty
	wElevator := CalculateWeightMS(2000, FlagWalkable|FlagIsElevator)
	if wElevator < 45000 || wElevator > 45200 {
		t.Errorf("expected ~45038 ms for elevator, got %d", wElevator)
	}
}

func TestBuildGraphTopology(t *testing.T) {
	// Create 3 nodes in a triangle
	dataset := &ExtractedDataset{
		Nodes: []RawNode{
			{OSMNodeID: 101, LatQuantized: 407588960, LonQuantized: -739851300, AccessFlags: uint16(FlagWalkable)},
			{OSMNodeID: 102, LatQuantized: 407588960, LonQuantized: -739841300, AccessFlags: uint16(FlagWalkable)},
			{OSMNodeID: 103, LatQuantized: 407598960, LonQuantized: -739851300, AccessFlags: uint16(FlagWalkable)},
		},
		OSMIDToNodeIdx: map[int64]uint32{
			101: 0,
			102: 1,
			103: 2,
		},
		Ways: []ExtractedWay{
			{
				OSMWayID:        1001,
				NodeIDs:         []int64{101, 102},
				EdgeFlags:       FlagWalkable | FlagWheelchairAccessible,
				IsBidirectional: true,
			},
			{
				OSMWayID:        1002,
				NodeIDs:         []int64{102, 103},
				EdgeFlags:       FlagWalkable | FlagIsSteps,
				IsBidirectional: false, // oneway
			},
		},
	}

	graph := BuildGraph(dataset)

	if len(graph.Nodes) != 3 {
		t.Fatalf("expected 3 nodes, got %d", len(graph.Nodes))
	}

	// Node 0 (101): has 1 outgoing edge to Node 1 (102)
	if graph.Nodes[0].EdgeCount != 1 {
		t.Errorf("node 0 expected 1 edge, got %d", graph.Nodes[0].EdgeCount)
	}

	// Node 1 (102): has 2 outgoing edges (back to Node 0 and oneway to Node 2)
	if graph.Nodes[1].EdgeCount != 2 {
		t.Errorf("node 1 expected 2 edges, got %d", graph.Nodes[1].EdgeCount)
	}

	// Node 2 (103): has 0 outgoing edges (target of oneway from Node 1)
	if graph.Nodes[2].EdgeCount != 0 {
		t.Errorf("node 2 expected 0 edges, got %d", graph.Nodes[2].EdgeCount)
	}

	// Total edges: 1 + 2 + 0 = 3
	if len(graph.Edges) != 3 {
		t.Fatalf("expected 3 total edges, got %d", len(graph.Edges))
	}

	// Verify CSR offsets
	if graph.Nodes[0].FirstEdgeIdx != 0 {
		t.Errorf("node 0 firstEdgeIdx expected 0, got %d", graph.Nodes[0].FirstEdgeIdx)
	}
	if graph.Nodes[1].FirstEdgeIdx != 1 {
		t.Errorf("node 1 firstEdgeIdx expected 1, got %d", graph.Nodes[1].FirstEdgeIdx)
	}
	if graph.Nodes[2].FirstEdgeIdx != 3 {
		t.Errorf("node 2 firstEdgeIdx expected 3, got %d", graph.Nodes[2].FirstEdgeIdx)
	}

	// Validate structure
	if err := ValidateGraphStructure(graph); err != nil {
		t.Fatalf("graph validation failed: %v", err)
	}
}
