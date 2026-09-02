package walk

import (
	"bytes"
	"encoding/binary"
	"fmt"
	"io"
	"math"
	"os"
	"unsafe"

	"github.com/cespare/xxhash/v2"
)

const (
	// DefaultBranchingFactor is the default FlatGeobuf-compatible fanout factor M = 16
	DefaultBranchingFactor uint32 = 16
)

// RTreeIndex represents an in-memory or memory-mapped static packed Hilbert R-Tree
type RTreeIndex struct {
	Metadata RTreeMetadata
	Nodes    []RTreeNodeItem // Flat breadth-first array starting with Root at index 0
}

// BuildPackedRTree constructs a static packed Hilbert R-tree from a slice of WalkNode entries
func BuildPackedRTree(nodes []WalkNode, branchingFactor uint32) (*RTreeIndex, error) {
	if len(nodes) == 0 {
		return &RTreeIndex{
			Metadata: RTreeMetadata{
				BranchingFactor: branchingFactor,
				NumLevels:       0,
				TotalNodes:      0,
				NumLeaves:       0,
			},
			Nodes: []RTreeNodeItem{},
		}, nil
	}

	if branchingFactor < 2 {
		branchingFactor = DefaultBranchingFactor
	}

	// 1. Compute global bounding box
	minLat := int32(math.MaxInt32)
	minLon := int32(math.MaxInt32)
	maxLat := int32(math.MinInt32)
	maxLon := int32(math.MinInt32)

	for _, n := range nodes {
		if n.LatQuantized < minLat {
			minLat = n.LatQuantized
		}
		if n.LatQuantized > maxLat {
			maxLat = n.LatQuantized
		}
		if n.LonQuantized < minLon {
			minLon = n.LonQuantized
		}
		if n.LonQuantized > maxLon {
			maxLon = n.LonQuantized
		}
	}

	// 2. Sort nodes by Hilbert curve
	sortedItems := SortNodesByHilbert(nodes, minLat, minLon, maxLat, maxLon)
	numLeaves := len(sortedItems)

	// 3. Build Leaf Level (Level 0)
	leafNodes := make([]RTreeNodeItem, numLeaves)
	for i, item := range sortedItems {
		leafNodes[i] = RTreeNodeItem{
			MinLatQ:     item.LatQ,
			MinLonQ:     item.LonQ,
			MaxLatQ:     item.LatQ,
			MaxLonQ:     item.LonQ,
			ChildOffset: item.OriginalIndex, // In leaf, ChildOffset is original graph node index
			NumChildren: 1,
			Flags:       RTreeFlagLeaf,
		}
	}

	if numLeaves == 1 {
		return &RTreeIndex{
			Metadata: RTreeMetadata{
				MinLatQ:         minLat,
				MinLonQ:         minLon,
				MaxLatQ:         maxLat,
				MaxLonQ:         maxLon,
				BranchingFactor: branchingFactor,
				NumLevels:       1,
				TotalNodes:      1,
				NumLeaves:       1,
			},
			Nodes: leafNodes,
		}, nil
	}

	// 4. Build Parent Levels Bottom-Up
	// levels[0] = leaves, levels[1] = parents of leaves, ..., levels[top] = root
	levels := [][]RTreeNodeItem{leafNodes}
	currentLevel := leafNodes

	for len(currentLevel) > 1 {
		numParents := (len(currentLevel) + int(branchingFactor) - 1) / int(branchingFactor)
		parentLevel := make([]RTreeNodeItem, numParents)

		for p := 0; p < numParents; p++ {
			startIdx := p * int(branchingFactor)
			endIdx := startIdx + int(branchingFactor)
			if endIdx > len(currentLevel) {
				endIdx = len(currentLevel)
			}
			childSlice := currentLevel[startIdx:endIdx]

			pMinLat := childSlice[0].MinLatQ
			pMinLon := childSlice[0].MinLonQ
			pMaxLat := childSlice[0].MaxLatQ
			pMaxLon := childSlice[0].MaxLonQ

			for _, c := range childSlice[1:] {
				if c.MinLatQ < pMinLat {
					pMinLat = c.MinLatQ
				}
				if c.MinLonQ < pMinLon {
					pMinLon = c.MinLonQ
				}
				if c.MaxLatQ > pMaxLat {
					pMaxLat = c.MaxLatQ
				}
				if c.MaxLonQ > pMaxLon {
					pMaxLon = c.MaxLonQ
				}
			}

			parentLevel[p] = RTreeNodeItem{
				MinLatQ:     pMinLat,
				MinLonQ:     pMinLon,
				MaxLatQ:     pMaxLat,
				MaxLonQ:     pMaxLon,
				ChildOffset: uint32(startIdx), // Temporary intra-level offset, fixed in flattening step
				NumChildren: uint16(len(childSlice)),
				Flags:       RTreeFlagInternal,
			}
		}

		levels = append(levels, parentLevel)
		currentLevel = parentLevel
	}

	// 5. Flatten levels top-down (Breadth-first: Root -> ... -> Leaves)
	numLevels := len(levels)
	totalNodes := 0
	for _, lvl := range levels {
		totalNodes += len(lvl)
	}

	flattenedNodes := make([]RTreeNodeItem, totalNodes)
	// Calculate level offsets in the flattened array
	levelBaseOffsets := make([]uint32, numLevels)
	cursor := uint32(0)

	// Top level (Root) is levels[numLevels - 1], bottom level (Leaves) is levels[0]
	for lvlIdx := numLevels - 1; lvlIdx >= 0; lvlIdx-- {
		levelBaseOffsets[lvlIdx] = cursor
		cursor += uint32(len(levels[lvlIdx]))
	}

	// Fill flattenedNodes and fix ChildOffset to absolute array indices
	for lvlIdx := numLevels - 1; lvlIdx >= 0; lvlIdx-- {
		base := levelBaseOffsets[lvlIdx]
		childBase := uint32(0)
		if lvlIdx > 0 {
			childBase = levelBaseOffsets[lvlIdx-1]
		}

		for i, node := range levels[lvlIdx] {
			targetIdx := base + uint32(i)
			if node.Flags&RTreeFlagLeaf != 0 {
				// Leaf node: keep original node index as ChildOffset
				flattenedNodes[targetIdx] = node
			} else {
				// Internal node: child offset points to childBase + intra-level offset
				node.ChildOffset = childBase + node.ChildOffset
				flattenedNodes[targetIdx] = node
			}
		}
	}

	metadata := RTreeMetadata{
		MinLatQ:         minLat,
		MinLonQ:         minLon,
		MaxLatQ:         maxLat,
		MaxLonQ:         maxLon,
		BranchingFactor: branchingFactor,
		NumLevels:       uint32(numLevels),
		TotalNodes:      uint32(totalNodes),
		NumLeaves:       uint32(numLeaves),
	}

	return &RTreeIndex{
		Metadata: metadata,
		Nodes:    flattenedNodes,
	}, nil
}

// SerializeRTree serializes an RTreeIndex into binary format with 232-byte MasterHeader
func SerializeRTree(tree *RTreeIndex, w io.Writer) (*MasterHeader, error) {
	if err := ValidateLayout(); err != nil {
		return nil, fmt.Errorf("layout validation failed: %w", err)
	}

	metaSize := uint64(unsafe.Sizeof(RTreeMetadata{})) // 32 bytes
	nodeSize := uint64(unsafe.Sizeof(RTreeNodeItem{}))  // 24 bytes
	numNodes := uint64(len(tree.Nodes))
	nodesPayloadLen := numNodes * nodeSize

	section0Offset := ((uint64(MasterHeaderSize) + 63) / 64) * 64 // 256 bytes (64-byte aligned)
	section1Offset := section0Offset + metaSize
	if section1Offset%8 != 0 {
		section1Offset += 8 - (section1Offset % 8)
	}

	totalFileSize := section1Offset + nodesPayloadLen
	if totalFileSize%64 != 0 {
		totalFileSize += 64 - (totalFileSize % 64)
	}

	payloadBuf := new(bytes.Buffer)
	payloadBuf.Grow(int(totalFileSize - uint64(MasterHeaderSize)))

	if section0Offset > uint64(MasterHeaderSize) {
		pad := make([]byte, section0Offset-uint64(MasterHeaderSize))
		payloadBuf.Write(pad)
	}

	// Write Section 0: Metadata
	if err := binary.Write(payloadBuf, binary.LittleEndian, tree.Metadata); err != nil {
		return nil, fmt.Errorf("failed to write metadata: %w", err)
	}

	// Pad between Section 0 and Section 1
	currentLen := uint64(payloadBuf.Len())
	targetS1RelOffset := section1Offset - uint64(MasterHeaderSize)
	if currentLen < targetS1RelOffset {
		pad := make([]byte, targetS1RelOffset-currentLen)
		payloadBuf.Write(pad)
	}

	// Write Section 1: Nodes
	for _, n := range tree.Nodes {
		if err := binary.Write(payloadBuf, binary.LittleEndian, n); err != nil {
			return nil, fmt.Errorf("failed to write rtree node: %w", err)
		}
	}

	// Trailing padding to 64 bytes
	currentTotal := uint64(MasterHeaderSize) + uint64(payloadBuf.Len())
	if currentTotal < totalFileSize {
		pad := make([]byte, totalFileSize-currentTotal)
		payloadBuf.Write(pad)
	}

	payloadBytes := payloadBuf.Bytes()
	checksum := xxhash.Sum64(payloadBytes)

	header := MasterHeader{
		Magic:         MagicWalkRTree,
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
				SizeBytes: metaSize,
				ItemCount: 1,
			},
			{
				Offset:    section1Offset,
				SizeBytes: nodesPayloadLen,
				ItemCount: numNodes,
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

// WriteRTreeFile serializes an RTreeIndex directly to a binary file
func WriteRTreeFile(tree *RTreeIndex, outputPath string) (*MasterHeader, error) {
	f, err := os.Create(outputPath)
	if err != nil {
		return nil, fmt.Errorf("failed to create output file %s: %w", outputPath, err)
	}
	defer f.Close()

	header, err := SerializeRTree(tree, f)
	if err != nil {
		return nil, err
	}
	if err := f.Sync(); err != nil {
		return nil, fmt.Errorf("failed to sync file: %w", err)
	}
	return header, nil
}

// ReadRTree parses and validates a walk_rtree.bin file
func ReadRTree(r io.ReaderAt, fileSize int64) (*RTreeIndex, error) {
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

	if header.Magic != MagicWalkRTree {
		return nil, fmt.Errorf("invalid magic: 0x%08X (expected 0x%08X)", header.Magic, MagicWalkRTree)
	}
	if header.SchemaVersion != SchemaVersion {
		return nil, fmt.Errorf("schema version mismatch: %d", header.SchemaVersion)
	}
	if header.EndianMarker != EndianMarker {
		return nil, fmt.Errorf("endianness mismatch: 0x%08X", header.EndianMarker)
	}
	if int64(header.FileSize) != fileSize {
		return nil, fmt.Errorf("header file_size %d != physical %d", header.FileSize, fileSize)
	}

	payloadSize := fileSize - int64(MasterHeaderSize)
	payloadBytes := make([]byte, payloadSize)
	if _, err := r.ReadAt(payloadBytes, int64(MasterHeaderSize)); err != nil {
		return nil, fmt.Errorf("failed to read payload: %w", err)
	}

	if xxhash.Sum64(payloadBytes) != header.ChecksumXXH64 {
		return nil, fmt.Errorf("checksum mismatch in rtree binary")
	}

	// Section 0: Metadata
	s0 := header.TOC[0]
	var metadata RTreeMetadata
	s0Bytes := make([]byte, s0.SizeBytes)
	if _, err := r.ReadAt(s0Bytes, int64(s0.Offset)); err != nil {
		return nil, fmt.Errorf("failed to read section 0: %w", err)
	}
	if err := binary.Read(bytes.NewReader(s0Bytes), binary.LittleEndian, &metadata); err != nil {
		return nil, fmt.Errorf("failed to parse rtree metadata: %w", err)
	}

	// Section 1: Nodes
	s1 := header.TOC[1]
	nodes := make([]RTreeNodeItem, s1.ItemCount)
	s1Bytes := make([]byte, s1.SizeBytes)
	if _, err := r.ReadAt(s1Bytes, int64(s1.Offset)); err != nil {
		return nil, fmt.Errorf("failed to read section 1: %w", err)
	}
	if err := binary.Read(bytes.NewReader(s1Bytes), binary.LittleEndian, &nodes); err != nil {
		return nil, fmt.Errorf("failed to parse rtree nodes: %w", err)
	}

	return &RTreeIndex{
		Metadata: metadata,
		Nodes:    nodes,
	}, nil
}
