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

// WalkGraphView provides a typed zero-copy view of the deserialized binary walk graph
type WalkGraphView struct {
	Header MasterHeader
	Nodes  []WalkNode
	Edges  []WalkEdge
}

// SerializeWalkGraph serializes a CompiledWalkGraph into a byte stream with the 128-byte MasterHeader
func SerializeWalkGraph(graph *CompiledWalkGraph, w io.Writer) (*MasterHeader, error) {
	if err := ValidateLayout(); err != nil {
		return nil, fmt.Errorf("layout validation failed: %w", err)
	}

	numNodes := uint64(len(graph.Nodes))
	numEdges := uint64(len(graph.Edges))

	nodeBytesLen := numNodes * uint64(unsafe.Sizeof(WalkNode{}))
	edgeBytesLen := numEdges * uint64(unsafe.Sizeof(WalkEdge{}))

	section0Offset := ((uint64(MasterHeaderSize) + 63) / 64) * 64 // 192 bytes (64-byte cache-line aligned)
	section1Offset := section0Offset + nodeBytesLen

	// Align section 1 offset to 8-byte boundary if needed
	if section1Offset%8 != 0 {
		section1Offset += 8 - (section1Offset % 8)
	}

	totalFileSize := section1Offset + edgeBytesLen
	// Align total file size to 64-byte cache line boundary
	if totalFileSize%64 != 0 {
		totalFileSize += 64 - (totalFileSize % 64)
	}

	// 1. Build Payload buffer to compute xxHash64
	payloadBuf := new(bytes.Buffer)
	payloadBuf.Grow(int(totalFileSize - uint64(MasterHeaderSize)))

	// Pad between MasterHeader and Section 0 if necessary (e.g. 136 -> 192 = 56 bytes)
	if section0Offset > uint64(MasterHeaderSize) {
		headerPad := make([]byte, section0Offset-uint64(MasterHeaderSize))
		payloadBuf.Write(headerPad)
	}

	// Write Section 0: Nodes
	for _, n := range graph.Nodes {
		if err := binary.Write(payloadBuf, binary.LittleEndian, n); err != nil {
			return nil, fmt.Errorf("failed to write node: %w", err)
		}
	}

	// Pad between Section 0 and Section 1 if necessary
	currentPayloadLen := uint64(payloadBuf.Len())
	targetS1RelOffset := section1Offset - uint64(MasterHeaderSize)
	if currentPayloadLen < targetS1RelOffset {
		padding := make([]byte, targetS1RelOffset-currentPayloadLen)
		payloadBuf.Write(padding)
	}

	// Write Section 1: Edges
	for _, e := range graph.Edges {
		if err := binary.Write(payloadBuf, binary.LittleEndian, e); err != nil {
			return nil, fmt.Errorf("failed to write edge: %w", err)
		}
	}

	// Trailing padding to align to 64 bytes
	currentTotal := uint64(MasterHeaderSize) + uint64(payloadBuf.Len())
	if currentTotal < totalFileSize {
		padding := make([]byte, totalFileSize-currentTotal)
		payloadBuf.Write(padding)
	}

	payloadBytes := payloadBuf.Bytes()

	// 2. Compute xxHash64 checksum over entire payload
	checksum := xxhash.Sum64(payloadBytes)

	// 3. Construct MasterHeader
	header := MasterHeader{
		Magic:         MagicWalkGraph,
		SchemaVersion: SchemaVersion,
		EndianMarker:  EndianMarker,
		HeaderSize:    MasterHeaderSize,
		FileSize:      totalFileSize,
		ChecksumXXH64: checksum,
		NumSections:   2,
		Flags:         0,
		TOC: [8]SectionDesc{
			{
				Offset:    section0Offset,
				SizeBytes: nodeBytesLen,
				ItemCount: numNodes,
			},
			{
				Offset:    section1Offset,
				SizeBytes: edgeBytesLen,
				ItemCount: numEdges,
			},
			{},
			{},
			{},
			{},
			{},
			{},
		},
	}

	// 4. Write MasterHeader
	if err := binary.Write(w, binary.LittleEndian, header); err != nil {
		return nil, fmt.Errorf("failed to write master header: %w", err)
	}

	// 5. Write Payload
	if _, err := w.Write(payloadBytes); err != nil {
		return nil, fmt.Errorf("failed to write payload: %w", err)
	}

	return &header, nil
}

// WriteWalkGraphFile serializes the walk graph directly to a binary file
func WriteWalkGraphFile(graph *CompiledWalkGraph, outputPath string) (*MasterHeader, error) {
	f, err := os.Create(outputPath)
	if err != nil {
		return nil, fmt.Errorf("failed to create output file %s: %w", outputPath, err)
	}
	defer f.Close()

	header, err := SerializeWalkGraph(graph, f)
	if err != nil {
		return nil, err
	}

	if err := f.Sync(); err != nil {
		return nil, fmt.Errorf("failed to sync file: %w", err)
	}

	return header, nil
}

// ReadWalkGraph deserializes a walk graph binary and validates all header markers and checksums
func ReadWalkGraph(r io.ReaderAt, fileSize int64) (*WalkGraphView, error) {
	if fileSize < int64(MasterHeaderSize) {
		return nil, fmt.Errorf("file size %d smaller than master header size %d", fileSize, MasterHeaderSize)
	}

	headerBytes := make([]byte, MasterHeaderSize)
	if _, err := r.ReadAt(headerBytes, 0); err != nil {
		return nil, fmt.Errorf("failed to read master header: %w", err)
	}

	var header MasterHeader
	if err := binary.Read(bytes.NewReader(headerBytes), binary.LittleEndian, &header); err != nil {
		return nil, fmt.Errorf("failed to parse master header: %w", err)
	}

	// Validate Header Invariants
	if header.Magic != MagicWalkGraph {
		return nil, fmt.Errorf("invalid magic signature: 0x%08X (expected 0x%08X)", header.Magic, MagicWalkGraph)
	}
	if header.SchemaVersion != SchemaVersion {
		return nil, fmt.Errorf("schema version mismatch: %d (expected %d)", header.SchemaVersion, SchemaVersion)
	}
	if header.EndianMarker != EndianMarker {
		return nil, fmt.Errorf("endianness marker mismatch: 0x%08X (expected 0x%08X)", header.EndianMarker, EndianMarker)
	}
	if header.HeaderSize != MasterHeaderSize {
		return nil, fmt.Errorf("invalid header size: %d (expected %d)", header.HeaderSize, MasterHeaderSize)
	}
	if int64(header.FileSize) != fileSize {
		return nil, fmt.Errorf("header file_size %d != physical file size %d", header.FileSize, fileSize)
	}

	// Verify Checksum
	payloadSize := fileSize - int64(MasterHeaderSize)
	payloadBytes := make([]byte, payloadSize)
	if _, err := r.ReadAt(payloadBytes, int64(MasterHeaderSize)); err != nil {
		return nil, fmt.Errorf("failed to read payload bytes: %w", err)
	}

	computedChecksum := xxhash.Sum64(payloadBytes)
	if computedChecksum != header.ChecksumXXH64 {
		return nil, fmt.Errorf("checksum mismatch: header has 0x%016X, computed 0x%016X", header.ChecksumXXH64, computedChecksum)
	}

	// Section 0: Nodes
	s0 := header.TOC[0]
	if s0.Offset+s0.SizeBytes > uint64(fileSize) {
		return nil, fmt.Errorf("section 0 bounds exceed file size")
	}
	nodes := make([]WalkNode, s0.ItemCount)
	s0Bytes := make([]byte, s0.SizeBytes)
	if _, err := r.ReadAt(s0Bytes, int64(s0.Offset)); err != nil {
		return nil, fmt.Errorf("failed to read section 0: %w", err)
	}
	if err := binary.Read(bytes.NewReader(s0Bytes), binary.LittleEndian, &nodes); err != nil {
		return nil, fmt.Errorf("failed to parse nodes: %w", err)
	}

	// Section 1: Edges
	s1 := header.TOC[1]
	if s1.Offset+s1.SizeBytes > uint64(fileSize) {
		return nil, fmt.Errorf("section 1 bounds exceed file size")
	}
	edges := make([]WalkEdge, s1.ItemCount)
	s1Bytes := make([]byte, s1.SizeBytes)
	if _, err := r.ReadAt(s1Bytes, int64(s1.Offset)); err != nil {
		return nil, fmt.Errorf("failed to read section 1: %w", err)
	}
	if err := binary.Read(bytes.NewReader(s1Bytes), binary.LittleEndian, &edges); err != nil {
		return nil, fmt.Errorf("failed to parse edges: %w", err)
	}

	return &WalkGraphView{
		Header: header,
		Nodes:  nodes,
		Edges:  edges,
	}, nil
}
