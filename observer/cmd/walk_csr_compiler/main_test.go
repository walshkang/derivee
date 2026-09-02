package main

import (
	"os"
	"path/filepath"
	"testing"

	"observer/internal/walk"
)

func TestWalkCSRCompilerEndToEnd(t *testing.T) {
	tempDir := t.TempDir()
	walkGraphPath := filepath.Join(tempDir, "walk_graph.bin")
	offsetsPath := filepath.Join(tempDir, "walk_offsets.bin")
	edgesPath := filepath.Join(tempDir, "walk_edges.bin")
	rtreePath := filepath.Join(tempDir, "walk_rtree.bin")

	// 1. Create a synthetic walk graph
	nodes := []walk.WalkNode{
		{LatQuantized: 407580000, LonQuantized: -739850000, FirstEdgeIdx: 0, EdgeCount: 2, AccessFlags: uint16(walk.FlagWalkable | walk.FlagWheelchairAccessible)},
		{LatQuantized: 407590000, LonQuantized: -739840000, FirstEdgeIdx: 2, EdgeCount: 1, AccessFlags: uint16(walk.FlagWalkable | walk.FlagWheelchairAccessible)},
		{LatQuantized: 407600000, LonQuantized: -739830000, FirstEdgeIdx: 3, EdgeCount: 0, AccessFlags: uint16(walk.FlagWalkable)},
	}
	edges := []walk.WalkEdge{
		{TargetNodeIdx: 1, DistanceCM: 5000, WeightMS: 3750},
		{TargetNodeIdx: 2, DistanceCM: 10000, WeightMS: 7500},
		{TargetNodeIdx: 0, DistanceCM: 5000, WeightMS: 3750},
	}

	graph := &walk.CompiledWalkGraph{
		Nodes: nodes,
		Edges: edges,
	}

	_, err := walk.WriteWalkGraphFile(graph, walkGraphPath)
	if err != nil {
		t.Fatalf("WriteWalkGraphFile failed: %v", err)
	}

	// 2. Execute compilation steps
	fWalk, err := os.Open(walkGraphPath)
	if err != nil {
		t.Fatalf("failed to open walk graph: %v", err)
	}
	defer fWalk.Close()

	fiWalk, _ := fWalk.Stat()
	walkView, err := walk.ReadWalkGraph(fWalk, fiWalk.Size())
	if err != nil {
		t.Fatalf("ReadWalkGraph failed: %v", err)
	}

	compiledGraph := &walk.CompiledWalkGraph{
		Nodes: walkView.Nodes,
		Edges: walkView.Edges,
	}

	csrGraph, err := walk.CompileForwardCSR(compiledGraph)
	if err != nil {
		t.Fatalf("CompileForwardCSR failed: %v", err)
	}

	rtree, err := walk.BuildPackedRTree(compiledGraph.Nodes, 16)
	if err != nil {
		t.Fatalf("BuildPackedRTree failed: %v", err)
	}

	// 3. Serialize all 3 binaries
	offHeader, err := walk.WriteOffsetsFile(csrGraph.Offsets, offsetsPath)
	if err != nil {
		t.Fatalf("WriteOffsetsFile failed: %v", err)
	}
	if offHeader.Magic != walk.MagicWalkOffsets {
		t.Errorf("expected magic 0x%08X, got 0x%08X", walk.MagicWalkOffsets, offHeader.Magic)
	}

	edgHeader, err := walk.WriteEdgesFile(csrGraph.Edges, edgesPath)
	if err != nil {
		t.Fatalf("WriteEdgesFile failed: %v", err)
	}
	if edgHeader.Magic != walk.MagicWalkEdges {
		t.Errorf("expected magic 0x%08X, got 0x%08X", walk.MagicWalkEdges, edgHeader.Magic)
	}

	treeHeader, err := walk.WriteRTreeFile(rtree, rtreePath)
	if err != nil {
		t.Fatalf("WriteRTreeFile failed: %v", err)
	}
	if treeHeader.Magic != walk.MagicWalkRTree {
		t.Errorf("expected magic 0x%08X, got 0x%08X", walk.MagicWalkRTree, treeHeader.Magic)
	}

	// 4. Verify deserialized assets
	fOff, _ := os.Open(offsetsPath)
	fiOff, _ := fOff.Stat()
	readOffsets, _, err := walk.ReadOffsets(fOff, fiOff.Size())
	fOff.Close()
	if err != nil {
		t.Fatalf("ReadOffsets failed: %v", err)
	}
	if len(readOffsets) != 4 {
		t.Errorf("expected 4 offsets, got %d", len(readOffsets))
	}

	fEdg, _ := os.Open(edgesPath)
	fiEdg, _ := fEdg.Stat()
	readEdges, _, err := walk.ReadEdges(fEdg, fiEdg.Size())
	fEdg.Close()
	if err != nil {
		t.Fatalf("ReadEdges failed: %v", err)
	}
	if len(readEdges) != 3 {
		t.Errorf("expected 3 edges, got %d", len(readEdges))
	}

	fTree, _ := os.Open(rtreePath)
	fiTree, _ := fTree.Stat()
	readTree, err := walk.ReadRTree(fTree, fiTree.Size())
	fTree.Close()
	if err != nil {
		t.Fatalf("ReadRTree failed: %v", err)
	}
	if readTree.Metadata.NumLeaves != 3 {
		t.Errorf("expected 3 leaves in RTree, got %d", readTree.Metadata.NumLeaves)
	}

	// Test spatial search on readTree
	nearest, distCM, found := readTree.FindNearest(407580000, -739850000, 100.0)
	if !found {
		t.Fatal("expected to find node 0, got not found")
	}
	if nearest != 0 || distCM != 0 {
		t.Errorf("expected nearest node 0 dist 0, got node %d dist %d", nearest, distCM)
	}
}
