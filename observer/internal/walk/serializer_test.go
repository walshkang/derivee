package walk

import (
	"bytes"
	"os"
	"path/filepath"
	"testing"
)

func TestSerializeAndDeserializeRoundTrip(t *testing.T) {
	// 1. Create a synthetic test graph
	nodes := []WalkNode{
		{LatQuantized: 407588960, LonQuantized: -739851300, FirstEdgeIdx: 0, EdgeCount: 2, AccessFlags: uint16(FlagWalkable | FlagWheelchairAccessible)},
		{LatQuantized: 407588960, LonQuantized: -739841300, FirstEdgeIdx: 2, EdgeCount: 1, AccessFlags: uint16(FlagWalkable | FlagWheelchairAccessible)},
		{LatQuantized: 407598960, LonQuantized: -739851300, FirstEdgeIdx: 3, EdgeCount: 1, AccessFlags: uint16(FlagWalkable | FlagIsSteps)},
	}
	edges := []WalkEdge{
		{TargetNodeIdx: 1, DistanceCM: 8400, WeightMS: 6315},
		{TargetNodeIdx: 2, DistanceCM: 1113, WeightMS: 8369},
		{TargetNodeIdx: 0, DistanceCM: 8400, WeightMS: 6315},
		{TargetNodeIdx: 0, DistanceCM: 1113, WeightMS: 16866},
	}

	graph := &CompiledWalkGraph{
		Nodes: nodes,
		Edges: edges,
	}

	// 2. Serialize to in-memory buffer
	buf := new(bytes.Buffer)
	header, err := SerializeWalkGraph(graph, buf)
	if err != nil {
		t.Fatalf("SerializeWalkGraph failed: %v", err)
	}

	// 3. Verify Header invariants
	if header.Magic != MagicWalkGraph {
		t.Errorf("expected Magic 0x%08X, got 0x%08X", MagicWalkGraph, header.Magic)
	}
	if header.SchemaVersion != SchemaVersion {
		t.Errorf("expected SchemaVersion %d, got %d", SchemaVersion, header.SchemaVersion)
	}
	if header.EndianMarker != EndianMarker {
		t.Errorf("expected EndianMarker 0x%08X, got 0x%08X", EndianMarker, header.EndianMarker)
	}
	if header.HeaderSize != MasterHeaderSize {
		t.Errorf("expected HeaderSize %d, got %d", MasterHeaderSize, header.HeaderSize)
	}
	if header.NumSections != 2 {
		t.Errorf("expected 2 sections, got %d", header.NumSections)
	}
	if header.TOC[0].ItemCount != uint64(len(nodes)) {
		t.Errorf("section 0 item count mismatch: got %d, expected %d", header.TOC[0].ItemCount, len(nodes))
	}
	if header.TOC[1].ItemCount != uint64(len(edges)) {
		t.Errorf("section 1 item count mismatch: got %d, expected %d", header.TOC[1].ItemCount, len(edges))
	}

	// 4. Deserialize
	rawBytes := buf.Bytes()
	reader := bytes.NewReader(rawBytes)
	view, err := ReadWalkGraph(reader, int64(len(rawBytes)))
	if err != nil {
		t.Fatalf("ReadWalkGraph failed: %v", err)
	}

	// 5. Verify round-trip equivalence
	if len(view.Nodes) != len(nodes) {
		t.Fatalf("deserialized node count mismatch: %d != %d", len(view.Nodes), len(nodes))
	}
	for i := range nodes {
		if view.Nodes[i] != nodes[i] {
			t.Errorf("node %d mismatch: got %+v, expected %+v", i, view.Nodes[i], nodes[i])
		}
	}

	if len(view.Edges) != len(edges) {
		t.Fatalf("deserialized edge count mismatch: %d != %d", len(view.Edges), len(edges))
	}
	for i := range edges {
		if view.Edges[i] != edges[i] {
			t.Errorf("edge %d mismatch: got %+v, expected %+v", i, view.Edges[i], edges[i])
		}
	}
}

func TestChecksumCorruptionDetection(t *testing.T) {
	graph := &CompiledWalkGraph{
		Nodes: []WalkNode{
			{LatQuantized: 1000, LonQuantized: 2000, FirstEdgeIdx: 0, EdgeCount: 1, AccessFlags: 1},
		},
		Edges: []WalkEdge{
			{TargetNodeIdx: 0, DistanceCM: 500, WeightMS: 375},
		},
	}

	buf := new(bytes.Buffer)
	_, err := SerializeWalkGraph(graph, buf)
	if err != nil {
		t.Fatalf("serialization failed: %v", err)
	}

	rawBytes := buf.Bytes()
	// Corrupt a byte in the payload (after header)
	rawBytes[MasterHeaderSize+2] ^= 0xFF

	reader := bytes.NewReader(rawBytes)
	_, err = ReadWalkGraph(reader, int64(len(rawBytes)))
	if err == nil {
		t.Fatalf("expected ReadWalkGraph to fail on corrupted payload checksum, but it succeeded")
	}
}

func TestWriteAndValidateFile(t *testing.T) {
	tempDir := t.TempDir()
	outPath := filepath.Join(tempDir, "walk_graph.bin")

	graph := &CompiledWalkGraph{
		Nodes: []WalkNode{
			{LatQuantized: 407588960, LonQuantized: -739851300, FirstEdgeIdx: 0, EdgeCount: 1, AccessFlags: uint16(FlagWalkable | FlagWheelchairAccessible)},
			{LatQuantized: 407588960, LonQuantized: -739841300, FirstEdgeIdx: 1, EdgeCount: 1, AccessFlags: uint16(FlagWalkable | FlagIsElevator)},
		},
		Edges: []WalkEdge{
			{TargetNodeIdx: 1, DistanceCM: 5000, WeightMS: 37594},
			{TargetNodeIdx: 0, DistanceCM: 5000, WeightMS: 37594},
		},
	}

	header, err := WriteWalkGraphFile(graph, outPath)
	if err != nil {
		t.Fatalf("WriteWalkGraphFile failed: %v", err)
	}

	if header == nil {
		t.Fatal("expected non-nil header")
	}

	stats, err := ValidateBinaryFile(outPath)
	if err != nil {
		t.Fatalf("ValidateBinaryFile failed: %v", err)
	}

	if stats.TotalNodes != 2 {
		t.Errorf("stats.TotalNodes expected 2, got %d", stats.TotalNodes)
	}
	if stats.TotalEdges != 2 {
		t.Errorf("stats.TotalEdges expected 2, got %d", stats.TotalEdges)
	}
	if stats.ElevatorCount != 1 {
		t.Errorf("stats.ElevatorCount expected 1, got %d", stats.ElevatorCount)
	}
	if stats.TotalLengthMeters != 100.0 {
		t.Errorf("stats.TotalLengthMeters expected 100.0, got %f", stats.TotalLengthMeters)
	}

	// Verify file exists and size matches header
	info, err := os.Stat(outPath)
	if err != nil {
		t.Fatalf("stat failed: %v", err)
	}
	if info.Size() != int64(header.FileSize) {
		t.Errorf("file size on disk %d != header.FileSize %d", info.Size(), header.FileSize)
	}
}
