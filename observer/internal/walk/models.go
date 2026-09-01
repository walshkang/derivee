package walk

import (
	"fmt"
	"unsafe"
)

const (
	// MagicWalkGraph is the 4-byte magic signature "WALK" (0x4B4C4157 little-endian)
	MagicWalkGraph uint32 = 0x4B4C4157
	// EndianMarker is the 4-byte validation marker strictly set to 0x01020304
	EndianMarker uint32 = 0x01020304
	// SchemaVersion is the current binary format version
	SchemaVersion uint32 = 1
	// MasterHeaderSize is the exact size of the master file header in bytes (40 + 4*24 = 136 bytes)
	MasterHeaderSize uint32 = 136
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

// SectionDesc describes a typed binary payload section in the Table of Contents (24 bytes)
type SectionDesc struct {
	Offset    uint64 // Absolute byte offset in file (64-byte or 16 KiB aligned)
	SizeBytes uint64 // Raw byte length of payload
	ItemCount uint64 // Number of typed elements
}

// MasterHeader is the universal 128-byte binary file header matching C++ observer::format::MasterHeader
type MasterHeader struct {
	Magic         uint32
	SchemaVersion uint32
	EndianMarker  uint32
	HeaderSize    uint32
	FileSize      uint64
	ChecksumXXH64 uint64
	NumSections   uint32
	Flags         uint32
	TOC           [4]SectionDesc
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

// ValidateLayout performs runtime struct layout verification matching C++ static_assert checks
func ValidateLayout() error {
	if sz := unsafe.Sizeof(SectionDesc{}); sz != 24 {
		return fmt.Errorf("SectionDesc size mismatch: expected 24 bytes, got %d", sz)
	}
	if sz := unsafe.Sizeof(MasterHeader{}); sz != 136 {
		return fmt.Errorf("MasterHeader size mismatch: expected 136 bytes, got %d", sz)
	}
	if sz := unsafe.Sizeof(WalkNode{}); sz != 16 {
		return fmt.Errorf("WalkNode size mismatch: expected 16 bytes, got %d", sz)
	}
	if sz := unsafe.Sizeof(WalkEdge{}); sz != 8 {
		return fmt.Errorf("WalkEdge size mismatch: expected 8 bytes, got %d", sz)
	}
	return nil
}
