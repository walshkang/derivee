package ultra

import (
	"testing"

	"observer/internal/walk"
)

func TestDijkstraEngineCandidateSearch(t *testing.T) {
	// Simple graph: 0 -> 1 (10s) -> 2 (20s) -> 3 (60s)
	// Stops mapped:
	// Node 0: Stop 0
	// Node 1: Stop 1
	// Node 2: Stop 2
	// Node 3: Stop 3 (out of tau_max = 25s)
	nodes := []walk.WalkNode{
		{FirstEdgeIdx: 0, EdgeCount: 1, AccessFlags: uint16(walk.FlagWalkable | walk.FlagWheelchairAccessible)},
		{FirstEdgeIdx: 1, EdgeCount: 1, AccessFlags: uint16(walk.FlagWalkable | walk.FlagWheelchairAccessible)},
		{FirstEdgeIdx: 2, EdgeCount: 1, AccessFlags: uint16(walk.FlagWalkable)},
		{FirstEdgeIdx: 3, EdgeCount: 0, AccessFlags: uint16(walk.FlagWalkable)},
	}

	edges := []walk.WalkEdge{
		{TargetNodeIdx: 1, DistanceCM: 1330, WeightMS: 10000}, // 10s
		{TargetNodeIdx: 2, DistanceCM: 2660, WeightMS: 20000}, // 20s (cumulative 30s)
		{TargetNodeIdx: 3, DistanceCM: 8000, WeightMS: 60000}, // 60s (cumulative 90s)
	}

	walkNodeToStops := [][]SnappedStop{
		{{StopIndex: 0, TimeSec: 0, IsWheelchair: true}},
		{{StopIndex: 1, TimeSec: 0, IsWheelchair: true}},
		{{StopIndex: 2, TimeSec: 0, IsWheelchair: true}},
		{{StopIndex: 3, TimeSec: 0, IsWheelchair: true}},
	}

	engine := NewDijkstraEngine(int32(len(nodes)))
	buf := make([]TransferCandidate, 0, 10)

	// Sweep from Stop 0 (Node 0) with tauMax = 50s
	candidates := engine.FindCandidateTransfers(
		nodes,
		edges,
		0,
		0,
		0,
		50, // tauMax = 50s (Stop 1 at 10s and Stop 2 at 30s included; Stop 3 at 90s excluded)
		walkNodeToStops,
		buf,
	)

	if len(candidates) != 2 {
		t.Fatalf("expected 2 candidates, got %d", len(candidates))
	}

	if candidates[0].TargetStop != 1 || candidates[0].Duration != 10 {
		t.Errorf("candidate 0 mismatch: expected target 1 dur 10, got target %d dur %d",
			candidates[0].TargetStop, candidates[0].Duration)
	}

	if candidates[1].TargetStop != 2 || candidates[1].Duration != 30 {
		t.Errorf("candidate 1 mismatch: expected target 2 dur 30, got target %d dur %d",
			candidates[1].TargetStop, candidates[1].Duration)
	}
}

func TestDijkstraEngineGenerationReset(t *testing.T) {
	nodes := []walk.WalkNode{
		{FirstEdgeIdx: 0, EdgeCount: 1, AccessFlags: uint16(walk.FlagWalkable)},
		{FirstEdgeIdx: 1, EdgeCount: 0, AccessFlags: uint16(walk.FlagWalkable)},
	}
	edges := []walk.WalkEdge{
		{TargetNodeIdx: 1, WeightMS: 5000}, // 5s
	}

	walkNodeToStops := [][]SnappedStop{
		{{StopIndex: 0, TimeSec: 0}},
		{{StopIndex: 1, TimeSec: 0}},
	}

	engine := NewDijkstraEngine(int32(len(nodes)))
	buf := make([]TransferCandidate, 0, 10)

	// First sweep
	c1 := engine.FindCandidateTransfers(nodes, edges, 0, 0, 0, 900, walkNodeToStops, buf)
	if len(c1) != 1 || c1[0].TargetStop != 1 {
		t.Fatalf("sweep 1 failed")
	}

	// Second sweep from Node 1 (no outgoing edges)
	c2 := engine.FindCandidateTransfers(nodes, edges, 1, 1, 0, 900, walkNodeToStops, buf)
	if len(c2) != 0 {
		t.Errorf("sweep 2 expected 0 candidates, got %d", len(c2))
	}

	// Node 0 should be unvisited (InfDist) in current generation
	if d := engine.GetDist(0); d != InfDist {
		t.Errorf("expected node 0 to be InfDist in generation %d, got %d", engine.CurrentGen, d)
	}
}
