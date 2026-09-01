package ultra

import (
	"os"
	"path/filepath"
	"testing"

	"observer/internal/raptor"
	"observer/internal/walk"
)

func TestPrecomputeUltraTransfersEndToEnd(t *testing.T) {
	tempDir, err := os.MkdirTemp("", "ultra_precompute_e2e_*")
	if err != nil {
		t.Fatalf("failed to create temp dir: %v", err)
	}
	defer os.RemoveAll(tempDir)

	// Synthetic Walk Graph:
	// Node 0 (0,0) -> Node 1 (0, 0.001) ~ 111m / 83s
	// Node 1 -> Node 2 (0, 0.002) ~ 111m / 83s
	nodes := []walk.WalkNode{
		{LatQuantized: 0, LonQuantized: 0, FirstEdgeIdx: 0, EdgeCount: 1, AccessFlags: uint16(walk.FlagWalkable | walk.FlagWheelchairAccessible)},
		{LatQuantized: 0, LonQuantized: 10000, FirstEdgeIdx: 1, EdgeCount: 1, AccessFlags: uint16(walk.FlagWalkable | walk.FlagWheelchairAccessible)},
		{LatQuantized: 0, LonQuantized: 20000, FirstEdgeIdx: 2, EdgeCount: 0, AccessFlags: uint16(walk.FlagWalkable | walk.FlagWheelchairAccessible)},
	}

	edges := []walk.WalkEdge{
		{TargetNodeIdx: 1, DistanceCM: 11100, WeightMS: 50000}, // 50s
		{TargetNodeIdx: 2, DistanceCM: 11100, WeightMS: 50000}, // 50s
	}

	walkGraph := &walk.CompiledWalkGraph{
		Nodes: nodes,
		Edges: edges,
	}

	// Synthetic Timetable: 3 stops placed exactly on the 3 nodes
	timetable := &raptor.CompiledTimetable{
		Stops: []raptor.Stop{
			{Latitude: 0.0, Longitude: 0.0, RoutesOffset: 0, RouteCount: 0},
			{Latitude: 0.0, Longitude: 0.001, RoutesOffset: 0, RouteCount: 0},
			{Latitude: 0.0, Longitude: 0.002, RoutesOffset: 0, RouteCount: 0},
		},
		Routes:            []raptor.Route{},
		Trips:             []raptor.Trip{},
		StopTimes:         []raptor.StopTime{},
		Transfers:         []raptor.Transfer{},
		StopRoutes:        []uint32{},
		RouteStops:        []uint32{},
		StochasticWeights: []raptor.StochasticWeight{},
	}

	outPath := filepath.Join(tempDir, "ultra_transfers.csr")
	cfg := PrecomputeConfig{
		TauMaxSec:      900,
		MaxSnapMeters:  250.0,
		TempDir:        tempDir,
		EnableWitness:  true,
		ValidateOutput: true,
	}

	stats, err := PrecomputeUltraTransfers(walkGraph, timetable, outPath, cfg)
	if err != nil {
		t.Fatalf("PrecomputeUltraTransfers failed: %v", err)
	}

	if stats.NumStops != 3 {
		t.Errorf("expected 3 stops, got %d", stats.NumStops)
	}

	// Stop 0 -> Stop 1 (50s), Stop 0 -> Stop 2 (100s) => 2 shortcuts from stop 0
	// Stop 1 -> Stop 2 (50s) => 1 shortcut from stop 1
	// Stop 2 -> none => 0 shortcuts
	// Total = 3 shortcuts
	if stats.TotalShortcuts != 3 {
		t.Errorf("expected 3 total shortcuts, got %d", stats.TotalShortcuts)
	}

	// Read and verify deserialized output
	f, err := os.Open(outPath)
	if err != nil {
		t.Fatalf("failed to open output file: %v", err)
	}
	defer f.Close()

	fi, _ := f.Stat()
	csr, err := ReadUltraCSR(f, fi.Size())
	if err != nil {
		t.Fatalf("ReadUltraCSR failed: %v", err)
	}

	if csr.Header.NumStops != 3 || csr.Header.NumShortcuts != 3 {
		t.Errorf("header mismatch: stops=%d, shortcuts=%d", csr.Header.NumStops, csr.Header.NumShortcuts)
	}
}
