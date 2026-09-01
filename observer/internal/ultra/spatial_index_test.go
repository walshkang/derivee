package ultra

import (
	"testing"

	"observer/internal/walk"
)

func TestSpatialIndexNearestNeighbor(t *testing.T) {
	// NYC Coordinates (~40.75 N, -73.98 W)
	nodes := []walk.WalkNode{
		{
			LatQuantized: 407500000,
			LonQuantized: -739800000,
			FirstEdgeIdx: 0,
			EdgeCount:    2,
			AccessFlags:  uint16(walk.FlagWalkable),
		},
		{
			LatQuantized: 407550000, // ~550m north
			LonQuantized: -739800000,
			FirstEdgeIdx: 2,
			EdgeCount:    2,
			AccessFlags:  uint16(walk.FlagWalkable),
		},
	}

	si := BuildSpatialIndex(nodes)

	// Query near node 0 (within 50 meters)
	queryLat := int32(407500300)
	queryLon := int32(-739800200)

	nodeIdx, distCM := si.FindNearestWalkNode(queryLat, queryLon, 100.0)
	if nodeIdx != 0 {
		t.Errorf("expected node 0, got %d", nodeIdx)
	}
	if distCM == 0 {
		t.Errorf("expected non-zero distance")
	}

	// Query far away (out of max distance)
	farLat := int32(408000000)
	farLon := int32(-739000000)
	nodeIdxFar, _ := si.FindNearestWalkNode(farLat, farLon, 100.0)
	if nodeIdxFar != NilNode {
		t.Errorf("expected NilNode for out of range query, got %d", nodeIdxFar)
	}
}

func TestSpatialIndexMapStopsToWalkGraph(t *testing.T) {
	nodes := []walk.WalkNode{
		{
			LatQuantized: 407128000, // ~City Hall NYC
			LonQuantized: -740060000,
			FirstEdgeIdx: 0,
			EdgeCount:    1,
			AccessFlags:  uint16(walk.FlagWalkable),
		},
	}

	stops := []StopLocation{
		{
			StopIndex: 0,
			Lat:       40.71281, // Very close to node 0
			Lon:       -74.00601,
		},
		{
			StopIndex: 1,
			Lat:       40.75000, // Far away (should not snap within 100m)
			Lon:       -73.98000,
		},
	}

	si := BuildSpatialIndex(nodes)
	stopToNode, nodeToStops := si.MapStopsToWalkGraph(stops, 100.0)

	if stopToNode[0] != 0 {
		t.Errorf("expected stop 0 mapped to node 0, got %d", stopToNode[0])
	}
	if stopToNode[1] != NilNode {
		t.Errorf("expected stop 1 to be unmapped (NilNode), got %d", stopToNode[1])
	}

	if len(nodeToStops[0]) != 1 {
		t.Fatalf("expected 1 stop mapped to node 0, got %d", len(nodeToStops[0]))
	}
	if nodeToStops[0][0].StopIndex != 0 {
		t.Errorf("expected mapped stop 0, got %d", nodeToStops[0][0].StopIndex)
	}
}
