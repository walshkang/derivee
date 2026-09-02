package walk

import (
	"math"
	"math/rand"
	"os"
	"path/filepath"
	"testing"
)

func generateSyntheticNodes(count int, seed int64) []WalkNode {
	r := rand.New(rand.NewSource(seed))
	nodes := make([]WalkNode, count)

	// NYC bounds approximately: [40.700000, -74.020000] to [40.800000, -73.920000]
	minLat := 407000000
	maxLat := 408000000
	minLon := -740200000
	maxLon := -739200000

	for i := 0; i < count; i++ {
		lat := int32(minLat + r.Intn(maxLat-minLat))
		lon := int32(minLon + r.Intn(maxLon-minLon))
		nodes[i] = WalkNode{
			LatQuantized: lat,
			LonQuantized: lon,
			FirstEdgeIdx: uint32(i * 2),
			EdgeCount:    2,
			AccessFlags:  uint16(FlagWalkable),
		}
	}
	return nodes
}

func TestPackedRTreeConstruction(t *testing.T) {
	nodes := generateSyntheticNodes(250, 42)
	tree, err := BuildPackedRTree(nodes, 16)
	if err != nil {
		t.Fatalf("BuildPackedRTree failed: %v", err)
	}

	if tree.Metadata.NumLeaves != 250 {
		t.Errorf("expected 250 leaves, got %d", tree.Metadata.NumLeaves)
	}
	if tree.Metadata.BranchingFactor != 16 {
		t.Errorf("expected branching factor 16, got %d", tree.Metadata.BranchingFactor)
	}
	if tree.Metadata.NumLevels < 2 {
		t.Errorf("expected at least 2 levels for 250 nodes with M=16, got %d", tree.Metadata.NumLevels)
	}

	// Verify root bounds encompass all nodes
	root := tree.Nodes[0]
	for i, n := range nodes {
		if n.LatQuantized < root.MinLatQ || n.LatQuantized > root.MaxLatQ ||
			n.LonQuantized < root.MinLonQ || n.LonQuantized > root.MaxLonQ {
			t.Errorf("node %d (%d, %d) outside root bbox [%d, %d, %d, %d]",
				i, n.LatQuantized, n.LonQuantized, root.MinLatQ, root.MinLonQ, root.MaxLatQ, root.MaxLonQ)
		}
	}
}

func TestRTreeSerializationRoundtrip(t *testing.T) {
	tempDir := t.TempDir()
	treePath := filepath.Join(tempDir, "walk_rtree.bin")

	nodes := generateSyntheticNodes(100, 123)
	tree, err := BuildPackedRTree(nodes, 16)
	if err != nil {
		t.Fatalf("BuildPackedRTree failed: %v", err)
	}

	header, err := WriteRTreeFile(tree, treePath)
	if err != nil {
		t.Fatalf("WriteRTreeFile failed: %v", err)
	}

	if header.Magic != MagicWalkRTree {
		t.Errorf("expected Magic 0x%08X, got 0x%08X", MagicWalkRTree, header.Magic)
	}

	f, err := os.Open(treePath)
	if err != nil {
		t.Fatalf("failed to open file: %v", err)
	}
	defer f.Close()

	fi, _ := f.Stat()
	readTree, err := ReadRTree(f, fi.Size())
	if err != nil {
		t.Fatalf("ReadRTree failed: %v", err)
	}

	if readTree.Metadata.TotalNodes != tree.Metadata.TotalNodes {
		t.Errorf("total nodes mismatch: %d != %d", readTree.Metadata.TotalNodes, tree.Metadata.TotalNodes)
	}
	if readTree.Metadata.NumLeaves != tree.Metadata.NumLeaves {
		t.Errorf("num leaves mismatch: %d != %d", readTree.Metadata.NumLeaves, tree.Metadata.NumLeaves)
	}
	if len(readTree.Nodes) != len(tree.Nodes) {
		t.Fatalf("nodes length mismatch: %d != %d", len(readTree.Nodes), len(tree.Nodes))
	}

	for i := range tree.Nodes {
		if readTree.Nodes[i] != tree.Nodes[i] {
			t.Errorf("node[%d] mismatch: expected %+v, got %+v", i, tree.Nodes[i], readTree.Nodes[i])
			break
		}
	}
}

func TestRTreeBBoxQuery(t *testing.T) {
	nodes := generateSyntheticNodes(500, 999)
	tree, err := BuildPackedRTree(nodes, 16)
	if err != nil {
		t.Fatalf("BuildPackedRTree failed: %v", err)
	}

	// Query box around mid NYC
	qMinLat := int32(407300000)
	qMaxLat := int32(407600000)
	qMinLon := int32(-739900000)
	qMaxLon := int32(-739500000)

	// Ground truth via linear scan
	expectedSet := make(map[uint32]bool)
	for i, n := range nodes {
		if n.LatQuantized >= qMinLat && n.LatQuantized <= qMaxLat &&
			n.LonQuantized >= qMinLon && n.LonQuantized <= qMaxLon {
			expectedSet[uint32(i)] = true
		}
	}

	var buf [512]uint32
	results := tree.SearchBBox(qMinLat, qMinLon, qMaxLat, qMaxLon, buf[:0])

	resultSet := make(map[uint32]bool)
	for _, idx := range results {
		resultSet[idx] = true
	}

	if len(resultSet) != len(expectedSet) {
		t.Errorf("result count mismatch: expected %d, got %d", len(expectedSet), len(resultSet))
	}

	for exp := range expectedSet {
		if !resultSet[exp] {
			t.Errorf("expected node %d missing from bbox search results", exp)
		}
	}
}

func TestRTreeFindNearest(t *testing.T) {
	nodes := generateSyntheticNodes(500, 777)
	tree, err := BuildPackedRTree(nodes, 16)
	if err != nil {
		t.Fatalf("BuildPackedRTree failed: %v", err)
	}

	// Query from fixed point inside NYC bbox
	qLat := int32(407500000)
	qLon := int32(-739800000)

	// Ground truth: linear scan
	var expectedNearest uint32
	var expectedDist uint32 = math.MaxUint32

	for i, n := range nodes {
		d := uint32(CalculateDistanceCM(qLat, qLon, n.LatQuantized, n.LonQuantized))
		if d < expectedDist {
			expectedDist = d
			expectedNearest = uint32(i)
		}
	}

	nearestNode, distCM, found := tree.FindNearest(qLat, qLon, 5000.0) // 5km search radius
	if !found {
		t.Fatal("expected to find nearest node within 5km, got not found")
	}

	if nearestNode != expectedNearest {
		t.Errorf("nearest node mismatch: expected %d, got %d", expectedNearest, nearestNode)
	}
	if uint32(distCM) != expectedDist {
		t.Errorf("nearest distance mismatch: expected %d cm, got %d cm", expectedDist, distCM)
	}
}

func TestRTreeZeroAllocations(t *testing.T) {
	nodes := generateSyntheticNodes(500, 555)
	tree, err := BuildPackedRTree(nodes, 16)
	if err != nil {
		t.Fatalf("BuildPackedRTree failed: %v", err)
	}

	qMinLat := int32(407300000)
	qMaxLat := int32(407600000)
	qMinLon := int32(-739900000)
	qMaxLon := int32(-739500000)
	qLat := int32(407500000)
	qLon := int32(-739800000)

	// Pre-allocated buffer for SearchBBox
	preallocBuf := make([]uint32, 512)

	// 1. Verify 0 allocs in SearchBBox
	bboxAllocs := testing.AllocsPerRun(100, func() {
		_ = tree.SearchBBox(qMinLat, qMinLon, qMaxLat, qMaxLon, preallocBuf[:0])
	})
	if bboxAllocs != 0 {
		t.Errorf("SearchBBox generated %.2f allocations, expected 0", bboxAllocs)
	}

	// 2. Verify 0 allocs in FindNearest
	nearestAllocs := testing.AllocsPerRun(100, func() {
		_, _, _ = tree.FindNearest(qLat, qLon, 1000.0)
	})
	if nearestAllocs != 0 {
		t.Errorf("FindNearest generated %.2f allocations, expected 0", nearestAllocs)
	}
}
