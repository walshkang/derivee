package walk

import (
	"fmt"
	"unsafe"
)

const (
	// MagicWalkGraph is the 4-byte magic signature "WALK" (0x4B4C4157 little-endian)
	MagicWalkGraph uint32 = 0x4B4C4157
	// MagicWalkOffsets is the 4-byte magic signature "WOFS" (0x53464F57 little-endian)
	MagicWalkOffsets uint32 = 0x53464F57
	// MagicWalkEdges is the 4-byte magic signature "WEDG" (0x47444557 little-endian)
	MagicWalkEdges uint32 = 0x47444557
	// MagicWalkRTree is the 4-byte magic signature "WLRT" (0x54524C57 little-endian)
	MagicWalkRTree uint32 = 0x54524C57
	// EndianMarker is the 4-byte validation marker strictly set to 0x01020304
	EndianMarker uint32 = 0x01020304
	// SchemaVersion is the current binary format version
	SchemaVersion uint32 = 1
	// MasterHeaderSize is the exact size of the master file header in bytes (40 + 8*24 = 232 bytes)
	MasterHeaderSize uint32 = 232
)

// EdgeFlags bitmask defining pedestrian path characteristics
const (
	// FlagWalkable represents standard pedestrian accessibility (bit 0)
	FlagWalkable uint8 = 1 << 0
	// FlagWheelchairAccessible represents step-free / wheelchair accessibility (bit 1)
	FlagWheelchairAccessible uint8 = 1 << 1
	// FlagIsSteps represents stairs or step structures (bit 2)
	FlagIsSteps uint8 = 1 << 2
	// FlagIsElevator represents elevator or vertical transport (bit 3)
	FlagIsElevator uint8 = 1 << 3
)

// RTreeFlags bitmask defining R-tree node properties
const (
	// RTreeFlagInternal represents an internal branch node (children are child RTree nodes)
	RTreeFlagInternal uint16 = 0
	// RTreeFlagLeaf represents a leaf node (ChildOffset is original WalkNode index)
	RTreeFlagLeaf uint16 = 1 << 0
)

// SectionDesc describes a typed binary payload section in the Table of Contents (24 bytes)
type SectionDesc struct {
	Offset    uint64 // Absolute byte offset in file (64-byte or 16 KiB aligned)
	SizeBytes uint64 // Raw byte length of payload
	ItemCount uint64 // Number of typed elements
}

// MasterHeader is the universal 232-byte binary file header matching C++ observer::format::MasterHeader
type MasterHeader struct {
	Magic         uint32
	SchemaVersion uint32
	EndianMarker  uint32
	HeaderSize    uint32
	FileSize      uint64
	ChecksumXXH64 uint64
	NumSections   uint32
	Flags         uint32
	TOC           [8]SectionDesc
}

// WalkNode represents a quantized pedestrian intersection or waypoint (16 bytes)
type WalkNode struct {
	LatQuantized int32  // Fixed-point latitude (* 1e7)
	LonQuantized int32  // Fixed-point longitude (* 1e7)
	FirstEdgeIdx uint32 // Index into edge payload array (CSR layout)
	EdgeCount    uint16 // Outgoing edge count
	AccessFlags  uint16 // Pedestrian accessibility bitmask / node attributes
}

// WalkEdge represents a quantized directed edge in the pedestrian walk graph (8 bytes)
type WalkEdge struct {
	TargetNodeIdx uint32 // Destination node index (0 <= idx < NumNodes)
	DistanceCM    uint16 // Traversal distance in centimeters (max 65535 cm = ~655.35 m)
	WeightMS      uint16 // Traversal cost in milliseconds
}

// RTreeNodeItem represents a packed bounding-box node entry in the static Hilbert R-Tree (24 bytes)
type RTreeNodeItem struct {
	MinLatQ     int32  // Minimum latitude * 1e7
	MinLonQ     int32  // Minimum longitude * 1e7
	MaxLatQ     int32  // Maximum latitude * 1e7
	MaxLonQ     int32  // Maximum longitude * 1e7
	ChildOffset uint32 // Index of first child node in R-tree array, or NodeIdx if leaf
	NumChildren uint16 // Number of active child items in this node (<= BranchingFactor)
	Flags       uint16 // RTreeFlags bitmask (0 = internal node, 1 = leaf node)
}

// RTreeMetadata encapsulates global indexing parameters for walk_rtree.bin (32 bytes)
type RTreeMetadata struct {
	MinLatQ         int32  // Global bounding box minimum latitude * 1e7
	MinLonQ         int32  // Global bounding box minimum longitude * 1e7
	MaxLatQ         int32  // Global bounding box maximum latitude * 1e7
	MaxLonQ         int32  // Global bounding box maximum longitude * 1e7
	BranchingFactor uint32 // Node branching factor M (typically 16)
	NumLevels       uint32 // Number of hierarchical levels (root level to leaf level)
	TotalNodes      uint32 // Total count of RTreeNodeItem entries stored in tree array
	NumLeaves       uint32 // Count of original indexed WalkNode entries
}

// ValidateLayout performs runtime struct layout verification matching C++ static_assert checks
func ValidateLayout() error {
	if sz := unsafe.Sizeof(SectionDesc{}); sz != 24 {
		return fmt.Errorf("SectionDesc size mismatch: expected 24 bytes, got %d", sz)
	}
	if sz := unsafe.Sizeof(MasterHeader{}); sz != 232 {
		return fmt.Errorf("MasterHeader size mismatch: expected 232 bytes, got %d", sz)
	}
	if sz := unsafe.Sizeof(WalkNode{}); sz != 16 {
		return fmt.Errorf("WalkNode size mismatch: expected 16 bytes, got %d", sz)
	}
	if sz := unsafe.Sizeof(WalkEdge{}); sz != 8 {
		return fmt.Errorf("WalkEdge size mismatch: expected 8 bytes, got %d", sz)
	}
	if sz := unsafe.Sizeof(RTreeNodeItem{}); sz != 24 {
		return fmt.Errorf("RTreeNodeItem size mismatch: expected 24 bytes, got %d", sz)
	}
	if sz := unsafe.Sizeof(RTreeMetadata{}); sz != 32 {
		return fmt.Errorf("RTreeMetadata size mismatch: expected 32 bytes, got %d", sz)
	}
	return nil
}
