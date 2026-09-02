package walk

import (
	"bytes"
	"encoding/binary"
	"fmt"
	"io"
	"os"
	"unsafe"

	"github.com/cespare/xxhash/v2"
)

// ForwardCSRGraph represents a pedestrian walk network with decoupled forward CSR offsets
type ForwardCSRGraph struct {
	NumNodes uint32
	Offsets  []uint32   // Array of size |V| + 1 where Offsets[u]..Offsets[u+1] indexes Edges
	Edges    []WalkEdge // Contiguous array of outgoing edges of size |E|
	Nodes    []WalkNode // Node coordinates and attributes of size |V|
}

// CompileForwardCSR converts a CompiledWalkGraph into a verified ForwardCSRGraph
func CompileForwardCSR(graph *CompiledWalkGraph) (*ForwardCSRGraph, error) {
	if err := ValidateGraphStructure(graph); err != nil {
		return nil, fmt.Errorf("cannot compile invalid graph: %w", err)
	}

	numNodes := uint32(len(graph.Nodes))
	offsets := make([]uint32, numNodes+1)
	offsets[0] = 0

	for i, n := range graph.Nodes {
		offsets[i+1] = offsets[i] + uint32(n.EdgeCount)
	}

	totalEdges := offsets[numNodes]
	if totalEdges != uint32(len(graph.Edges)) {
		return nil, fmt.Errorf("csr edge count mismatch: offsets sum %d != edges len %d", totalEdges, len(graph.Edges))
	}

	// Build sanitized nodes matching offsets
	nodesCopy := make([]WalkNode, numNodes)
	for i, n := range graph.Nodes {
		nodesCopy[i] = WalkNode{
			LatQuantized: n.LatQuantized,
			LonQuantized: n.LonQuantized,
			FirstEdgeIdx: offsets[i],
			EdgeCount:    uint16(offsets[i+1] - offsets[i]),
			AccessFlags:  n.AccessFlags,
		}
	}

	edgesCopy := make([]WalkEdge, len(graph.Edges))
	copy(edgesCopy, graph.Edges)

	return &ForwardCSRGraph{
		NumNodes: numNodes,
		Offsets:  offsets,
		Edges:    edgesCopy,
		Nodes:    nodesCopy,
	}, nil
}

// OutDegree returns the number of outgoing edges for vertex u
func (g *ForwardCSRGraph) OutDegree(u uint32) uint32 {
	if u >= g.NumNodes {
		return 0
	}
	return g.Offsets[u+1] - g.Offsets[u]
}

// OutEdges returns a slice of outgoing edges for vertex u without allocation
func (g *ForwardCSRGraph) OutEdges(u uint32) []WalkEdge {
	if u >= g.NumNodes {
		return nil
	}
	start := g.Offsets[u]
	end := g.Offsets[u+1]
	return g.Edges[start:end]
}

// SerializeOffsets serializes the forward CSR offsets array into a 232-byte header binary format
func SerializeOffsets(offsets []uint32, w io.Writer) (*MasterHeader, error) {
	if err := ValidateLayout(); err != nil {
		return nil, fmt.Errorf("layout validation failed: %w", err)
	}

	numItems := uint64(len(offsets))
	payloadBytesLen := numItems * 4 // uint32 = 4 bytes

	section0Offset := ((uint64(MasterHeaderSize) + 63) / 64) * 64 // 256 bytes (64-byte cache-line aligned)
	totalFileSize := section0Offset + payloadBytesLen
	if totalFileSize%64 != 0 {
		totalFileSize += 64 - (totalFileSize % 64)
	}

	payloadBuf := new(bytes.Buffer)
	payloadBuf.Grow(int(totalFileSize - uint64(MasterHeaderSize)))

	if section0Offset > uint64(MasterHeaderSize) {
		pad := make([]byte, section0Offset-uint64(MasterHeaderSize))
		payloadBuf.Write(pad)
	}

	for _, off := range offsets {
		if err := binary.Write(payloadBuf, binary.LittleEndian, off); err != nil {
			return nil, fmt.Errorf("failed to write offset: %w", err)
		}
	}

	// Trailing padding to align to 64 bytes
	currentTotal := uint64(MasterHeaderSize) + uint64(payloadBuf.Len())
	if currentTotal < totalFileSize {
		pad := make([]byte, totalFileSize-currentTotal)
		payloadBuf.Write(pad)
	}

	payloadBytes := payloadBuf.Bytes()
	checksum := xxhash.Sum64(payloadBytes)

	header := MasterHeader{
		Magic:         MagicWalkOffsets,
		SchemaVersion: SchemaVersion,
		EndianMarker:  EndianMarker,
		HeaderSize:    MasterHeaderSize,
		FileSize:      totalFileSize,
		ChecksumXXH64: checksum,
		NumSections:   1,
		Flags:         0,
		TOC: [8]SectionDesc{
			{
				Offset:    section0Offset,
				SizeBytes: payloadBytesLen,
				ItemCount: numItems,
			},
		},
	}

	if err := binary.Write(w, binary.LittleEndian, header); err != nil {
		return nil, fmt.Errorf("failed to write master header: %w", err)
	}
	if _, err := w.Write(payloadBytes); err != nil {
		return nil, fmt.Errorf("failed to write payload: %w", err)
	}

	return &header, nil
}

// WriteOffsetsFile writes forward CSR offsets directly to a binary file
func WriteOffsetsFile(offsets []uint32, outputPath string) (*MasterHeader, error) {
	f, err := os.Create(outputPath)
	if err != nil {
		return nil, fmt.Errorf("failed to create output file %s: %w", outputPath, err)
	}
	defer f.Close()

	header, err := SerializeOffsets(offsets, f)
	if err != nil {
		return nil, err
	}
	if err := f.Sync(); err != nil {
		return nil, fmt.Errorf("failed to sync file: %w", err)
	}
	return header, nil
}

// ReadOffsets parses and validates a walk_offsets.bin file
func ReadOffsets(r io.ReaderAt, fileSize int64) ([]uint32, *MasterHeader, error) {
	if fileSize < int64(MasterHeaderSize) {
		return nil, nil, fmt.Errorf("file size %d smaller than master header size %d", fileSize, MasterHeaderSize)
	}

	headerBytes := make([]byte, MasterHeaderSize)
	if _, err := r.ReadAt(headerBytes, 0); err != nil {
		return nil, nil, fmt.Errorf("failed to read master header: %w", err)
	}

	var header MasterHeader
	if err := binary.Read(bytes.NewReader(headerBytes), binary.LittleEndian, &header); err != nil {
		return nil, nil, fmt.Errorf("failed to parse master header: %w", err)
	}

	if header.Magic != MagicWalkOffsets {
		return nil, nil, fmt.Errorf("invalid magic: 0x%08X (expected 0x%08X)", header.Magic, MagicWalkOffsets)
	}
	if header.SchemaVersion != SchemaVersion {
		return nil, nil, fmt.Errorf("schema version mismatch: %d", header.SchemaVersion)
	}
	if header.EndianMarker != EndianMarker {
		return nil, nil, fmt.Errorf("endianness mismatch: 0x%08X", header.EndianMarker)
	}
	if int64(header.FileSize) != fileSize {
		return nil, nil, fmt.Errorf("header file_size %d != physical %d", header.FileSize, fileSize)
	}

	payloadSize := fileSize - int64(MasterHeaderSize)
	payloadBytes := make([]byte, payloadSize)
	if _, err := r.ReadAt(payloadBytes, int64(MasterHeaderSize)); err != nil {
		return nil, nil, fmt.Errorf("failed to read payload: %w", err)
	}

	if xxhash.Sum64(payloadBytes) != header.ChecksumXXH64 {
		return nil, nil, fmt.Errorf("checksum mismatch in offsets binary")
	}

	s0 := header.TOC[0]
	if s0.Offset+s0.SizeBytes > uint64(fileSize) {
		return nil, nil, fmt.Errorf("section 0 offset + size exceeds file size")
	}

	offsets := make([]uint32, s0.ItemCount)
	s0Bytes := make([]byte, s0.SizeBytes)
	if _, err := r.ReadAt(s0Bytes, int64(s0.Offset)); err != nil {
		return nil, nil, fmt.Errorf("failed to read section 0: %w", err)
	}
	if err := binary.Read(bytes.NewReader(s0Bytes), binary.LittleEndian, &offsets); err != nil {
		return nil, nil, fmt.Errorf("failed to parse offsets array: %w", err)
	}

	return offsets, &header, nil
}

// SerializeEdges serializes the forward CSR edges array into a 232-byte header binary format
func SerializeEdges(edges []WalkEdge, w io.Writer) (*MasterHeader, error) {
	if err := ValidateLayout(); err != nil {
		return nil, fmt.Errorf("layout validation failed: %w", err)
	}

	numItems := uint64(len(edges))
	edgeSize := uint64(unsafe.Sizeof(WalkEdge{}))
	payloadBytesLen := numItems * edgeSize

	section0Offset := ((uint64(MasterHeaderSize) + 63) / 64) * 64 // 256 bytes (64-byte cache-line aligned)
	totalFileSize := section0Offset + payloadBytesLen
	if totalFileSize%64 != 0 {
		totalFileSize += 64 - (totalFileSize % 64)
	}

	payloadBuf := new(bytes.Buffer)
	payloadBuf.Grow(int(totalFileSize - uint64(MasterHeaderSize)))

	if section0Offset > uint64(MasterHeaderSize) {
		pad := make([]byte, section0Offset-uint64(MasterHeaderSize))
		payloadBuf.Write(pad)
	}

	for _, edge := range edges {
		if err := binary.Write(payloadBuf, binary.LittleEndian, edge); err != nil {
			return nil, fmt.Errorf("failed to write edge: %w", err)
		}
	}

	currentTotal := uint64(MasterHeaderSize) + uint64(payloadBuf.Len())
	if currentTotal < totalFileSize {
		pad := make([]byte, totalFileSize-currentTotal)
		payloadBuf.Write(pad)
	}

	payloadBytes := payloadBuf.Bytes()
	checksum := xxhash.Sum64(payloadBytes)

	header := MasterHeader{
		Magic:         MagicWalkEdges,
		SchemaVersion: SchemaVersion,
		EndianMarker:  EndianMarker,
		HeaderSize:    MasterHeaderSize,
		FileSize:      totalFileSize,
		ChecksumXXH64: checksum,
		NumSections:   1,
		Flags:         0,
		TOC: [8]SectionDesc{
			{
				Offset:    section0Offset,
				SizeBytes: payloadBytesLen,
				ItemCount: numItems,
			},
		},
	}

	if err := binary.Write(w, binary.LittleEndian, header); err != nil {
		return nil, fmt.Errorf("failed to write master header: %w", err)
	}
	if _, err := w.Write(payloadBytes); err != nil {
		return nil, fmt.Errorf("failed to write payload: %w", err)
	}

	return &header, nil
}

// WriteEdgesFile writes forward CSR edges directly to a binary file
func WriteEdgesFile(edges []WalkEdge, outputPath string) (*MasterHeader, error) {
	f, err := os.Create(outputPath)
	if err != nil {
		return nil, fmt.Errorf("failed to create output file %s: %w", outputPath, err)
	}
	defer f.Close()

	header, err := SerializeEdges(edges, f)
	if err != nil {
		return nil, err
	}
	if err := f.Sync(); err != nil {
		return nil, fmt.Errorf("failed to sync file: %w", err)
	}
	return header, nil
}

// ReadEdges parses and validates a walk_edges.bin file
func ReadEdges(r io.ReaderAt, fileSize int64) ([]WalkEdge, *MasterHeader, error) {
	if fileSize < int64(MasterHeaderSize) {
		return nil, nil, fmt.Errorf("file size %d smaller than master header size %d", fileSize, MasterHeaderSize)
	}

	headerBytes := make([]byte, MasterHeaderSize)
	if _, err := r.ReadAt(headerBytes, 0); err != nil {
		return nil, nil, fmt.Errorf("failed to read master header: %w", err)
	}

	var header MasterHeader
	if err := binary.Read(bytes.NewReader(headerBytes), binary.LittleEndian, &header); err != nil {
		return nil, nil, fmt.Errorf("failed to parse master header: %w", err)
	}

	if header.Magic != MagicWalkEdges {
		return nil, nil, fmt.Errorf("invalid magic: 0x%08X (expected 0x%08X)", header.Magic, MagicWalkEdges)
	}
	if header.SchemaVersion != SchemaVersion {
		return nil, nil, fmt.Errorf("schema version mismatch: %d", header.SchemaVersion)
	}
	if header.EndianMarker != EndianMarker {
		return nil, nil, fmt.Errorf("endianness mismatch: 0x%08X", header.EndianMarker)
	}
	if int64(header.FileSize) != fileSize {
		return nil, nil, fmt.Errorf("header file_size %d != physical %d", header.FileSize, fileSize)
	}

	payloadSize := fileSize - int64(MasterHeaderSize)
	payloadBytes := make([]byte, payloadSize)
	if _, err := r.ReadAt(payloadBytes, int64(MasterHeaderSize)); err != nil {
		return nil, nil, fmt.Errorf("failed to read payload: %w", err)
	}

	if xxhash.Sum64(payloadBytes) != header.ChecksumXXH64 {
		return nil, nil, fmt.Errorf("checksum mismatch in edges binary")
	}

	s0 := header.TOC[0]
	if s0.Offset+s0.SizeBytes > uint64(fileSize) {
		return nil, nil, fmt.Errorf("section 0 offset + size exceeds file size")
	}

	edges := make([]WalkEdge, s0.ItemCount)
	s0Bytes := make([]byte, s0.SizeBytes)
	if _, err := r.ReadAt(s0Bytes, int64(s0.Offset)); err != nil {
		return nil, nil, fmt.Errorf("failed to read section 0: %w", err)
	}
	if err := binary.Read(bytes.NewReader(s0Bytes), binary.LittleEndian, &edges); err != nil {
		return nil, nil, fmt.Errorf("failed to parse edges array: %w", err)
	}

	return edges, &header, nil
}
