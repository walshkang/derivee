package walk

import (
	"bytes"
	"os"
	"path/filepath"
	"testing"
)

func TestCompileForwardCSR(t *testing.T) {
	nodes := []WalkNode{
		{LatQuantized: 407580000, LonQuantized: -739850000, FirstEdgeIdx: 0, EdgeCount: 2, AccessFlags: uint16(FlagWalkable)},
		{LatQuantized: 407590000, LonQuantized: -739840000, FirstEdgeIdx: 2, EdgeCount: 1, AccessFlags: uint16(FlagWalkable | FlagWheelchairAccessible)},
		{LatQuantized: 407600000, LonQuantized: -739830000, FirstEdgeIdx: 3, EdgeCount: 0, AccessFlags: uint16(FlagWalkable)},
	}
	edges := []WalkEdge{
		{TargetNodeIdx: 1, DistanceCM: 5000, WeightMS: 3750},
		{TargetNodeIdx: 2, DistanceCM: 10000, WeightMS: 7500},
		{TargetNodeIdx: 0, DistanceCM: 5000, WeightMS: 3750},
	}

	graph := &CompiledWalkGraph{
		Nodes: nodes,
		Edges: edges,
	}

	csr, err := CompileForwardCSR(graph)
	if err != nil {
		t.Fatalf("CompileForwardCSR failed: %v", err)
	}

	if csr.NumNodes != 3 {
		t.Errorf("expected NumNodes 3, got %d", csr.NumNodes)
	}
	if len(csr.Offsets) != 4 {
		t.Fatalf("expected 4 offsets, got %d", len(csr.Offsets))
	}

	expectedOffsets := []uint32{0, 2, 3, 3}
	for i, exp := range expectedOffsets {
		if csr.Offsets[i] != exp {
			t.Errorf("offset[%d] mismatch: expected %d, got %d", i, exp, csr.Offsets[i])
		}
	}

	if csr.OutDegree(0) != 2 {
		t.Errorf("expected node 0 outdegree 2, got %d", csr.OutDegree(0))
	}
	if csr.OutDegree(1) != 1 {
		t.Errorf("expected node 1 outdegree 1, got %d", csr.OutDegree(1))
	}
	if csr.OutDegree(2) != 0 {
		t.Errorf("expected node 2 outdegree 0, got %d", csr.OutDegree(2))
	}

	outEdges0 := csr.OutEdges(0)
	if len(outEdges0) != 2 || outEdges0[0].TargetNodeIdx != 1 || outEdges0[1].TargetNodeIdx != 2 {
		t.Errorf("unexpected outEdges for node 0: %+v", outEdges0)
	}
}

func TestOffsetsSerializationRoundtrip(t *testing.T) {
	tempDir := t.TempDir()
	offsetsPath := filepath.Join(tempDir, "walk_offsets.bin")

	offsets := []uint32{0, 3, 7, 12, 12, 15}

	header, err := WriteOffsetsFile(offsets, offsetsPath)
	if err != nil {
		t.Fatalf("WriteOffsetsFile failed: %v", err)
	}

	if header.Magic != MagicWalkOffsets {
		t.Errorf("expected Magic 0x%08X, got 0x%08X", MagicWalkOffsets, header.Magic)
	}
	if header.SchemaVersion != SchemaVersion {
		t.Errorf("expected SchemaVersion %d, got %d", SchemaVersion, header.SchemaVersion)
	}
	if header.EndianMarker != EndianMarker {
		t.Errorf("expected EndianMarker 0x%08X, got 0x%08X", EndianMarker, header.EndianMarker)
	}

	f, err := os.Open(offsetsPath)
	if err != nil {
		t.Fatalf("failed to open offsets file: %v", err)
	}
	defer f.Close()

	fi, _ := f.Stat()
	readOffsets, readHeader, err := ReadOffsets(f, fi.Size())
	if err != nil {
		t.Fatalf("ReadOffsets failed: %v", err)
	}

	if readHeader.ChecksumXXH64 != header.ChecksumXXH64 {
		t.Errorf("checksum mismatch: 0x%016X != 0x%016X", readHeader.ChecksumXXH64, header.ChecksumXXH64)
	}

	if len(readOffsets) != len(offsets) {
		t.Fatalf("expected %d offsets, got %d", len(offsets), len(readOffsets))
	}
	for i := range offsets {
		if readOffsets[i] != offsets[i] {
			t.Errorf("offset[%d] mismatch: expected %d, got %d", i, offsets[i], readOffsets[i])
		}
	}
}

func TestEdgesSerializationRoundtrip(t *testing.T) {
	tempDir := t.TempDir()
	edgesPath := filepath.Join(tempDir, "walk_edges.bin")

	edges := []WalkEdge{
		{TargetNodeIdx: 1, DistanceCM: 2500, WeightMS: 1875},
		{TargetNodeIdx: 2, DistanceCM: 4500, WeightMS: 3375},
		{TargetNodeIdx: 0, DistanceCM: 2500, WeightMS: 1875},
	}

	header, err := WriteEdgesFile(edges, edgesPath)
	if err != nil {
		t.Fatalf("WriteEdgesFile failed: %v", err)
	}

	if header.Magic != MagicWalkEdges {
		t.Errorf("expected Magic 0x%08X, got 0x%08X", MagicWalkEdges, header.Magic)
	}

	f, err := os.Open(edgesPath)
	if err != nil {
		t.Fatalf("failed to open edges file: %v", err)
	}
	defer f.Close()

	fi, _ := f.Stat()
	readEdges, readHeader, err := ReadEdges(f, fi.Size())
	if err != nil {
		t.Fatalf("ReadEdges failed: %v", err)
	}

	if readHeader.ChecksumXXH64 != header.ChecksumXXH64 {
		t.Errorf("checksum mismatch: 0x%016X != 0x%016X", readHeader.ChecksumXXH64, header.ChecksumXXH64)
	}

	if len(readEdges) != len(edges) {
		t.Fatalf("expected %d edges, got %d", len(edges), len(readEdges))
	}
	for i := range edges {
		if readEdges[i] != edges[i] {
			t.Errorf("edge[%d] mismatch: expected %+v, got %+v", i, edges[i], readEdges[i])
		}
	}
}

func TestOffsetsCorruptChecksum(t *testing.T) {
	buf := new(bytes.Buffer)
	offsets := []uint32{0, 1, 2}
	_, err := SerializeOffsets(offsets, buf)
	if err != nil {
		t.Fatalf("SerializeOffsets failed: %v", err)
	}

	raw := buf.Bytes()
	// Corrupt a byte in payload
	raw[len(raw)-1] ^= 0xFF

	reader := bytes.NewReader(raw)
	_, _, err = ReadOffsets(reader, int64(len(raw)))
	if err == nil {
		t.Fatal("expected error on corrupt checksum, got nil")
	}
}
