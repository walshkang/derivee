package ultra

import (
	"fmt"
	"unsafe"
)

const (
	// MagicUltraCSR is the 4-byte magic signature "ULTR" (0x554C5452 little-endian)
	MagicUltraCSR uint32 = 0x554C5452
	// SchemaVersion is the current binary format version
	SchemaVersion uint16 = 1
	// HeaderSize is the fixed 32-byte header size
	HeaderSize uint16 = 32

	// BucketSize is the number of circular buckets in Dial's Queue (power of 2)
	BucketSize = 1024
	// BucketMask is the bitmask for single-cycle modulo: b = dist & BucketMask
	BucketMask = BucketSize - 1
	// InfDist represents unreachable distance in Dijkstra search
	InfDist uint32 = ^uint32(0)
	// NilNode represents an empty pointer/node index
	NilNode int32 = -1

	// FlagWheelchairAccessible represents step-free wheelchair accessible transfers (bit 0)
	FlagWheelchairAccessible uint8 = 1 << 0
	// FlagTimeExpanded represents time-expanded / profile transfer constraints (bit 1)
	FlagTimeExpanded uint8 = 1 << 1

	// DefaultTauMaxSec is the default bounded search cutoff threshold (15 minutes = 900s)
	DefaultTauMaxSec uint32 = 900
)

// BinaryHeader represents the fixed 32-byte file header matching C++ UltraCsrHeader
type BinaryHeader struct {
	MagicBytes   uint32   // 0x554C5452 ("ULTR")
	Version      uint32   // 0x00000001 (Format version)
	NumStops     uint32   // Number of source transit stops |S|
	NumShortcuts uint64   // Total count of verified shortcuts N
	TauMax       uint32   // Bounded cutoff limit in seconds (900)
	Reserved     [2]uint32 // Zero-padded alignment space (8 Bytes)
}

// NodeState is an 8-byte interleaved struct packing Dist and Gen into a single cache-aligned unit.
// Exactly 8 NodeState structs fit in a single 64-byte AMD Zen / ARM L1d cache line.
type NodeState struct {
	Dist uint32 // 4 Bytes: Current tentative SSSP distance in ticks/seconds
	Gen  uint32 // 4 Bytes: Generation counter (O(1) search resets)
}

// TransferCandidate represents an unverified candidate walking transfer shortcut
type TransferCandidate struct {
	TargetStop uint32 // Target stop index (0 <= idx < |S|)
	Duration   uint16 // Walking duration in seconds (<= tau_max)
	Flags      uint8  // Accessibility / attribute flags (bit 0 = wheelchair)
}

// SnappedStop represents a transit stop associated with a specific walk graph node
type SnappedStop struct {
	StopIndex    uint32 // Index in transit stops array (0 <= idx < |S|)
	DistanceCM   uint16 // Distance in centimeters from stop coordinate to walk node
	TimeSec      uint16 // Walking time in seconds from stop to walk node
	IsWheelchair bool   // Whether the snap link is step-free
}

// TripEvent represents a departure and arrival time pair for a trip at a stop
type TripEvent struct {
	DepTime uint32 // Seconds from daily epoch
	ArrTime uint32 // Seconds from daily epoch
	TripID  uint32 // Internal trip identifier
}

// RouteStopIndex maps a stop to a route and its 0-indexed position along the route
type RouteStopIndex struct {
	RouteID   uint32
	StopIndex uint16
}

// CompactTimetable provides compact schedule event lookups for profile witness searches
type CompactTimetable struct {
	NumStops         uint32
	StopRoutesIndptr []uint32         // Index into StopRoutes array (|S| + 1)
	StopRoutes       []RouteStopIndex // Flattened route indices per stop
	TripEvents       []TripEvent      // Flattened departure/arrival events
	RouteTripOffsets []uint32         // Index into TripEvents per route
	RouteTripCounts  []uint16         // Number of trips per route
}

// UltraCSR represents the in-memory or deserialized view of ultra_transfers.csr
type UltraCSR struct {
	Header       BinaryHeader
	Indptr       []uint64
	TargetStops  []uint32
	DurationsSec []uint16
	Flags        []uint8
}

// ValidateLayout performs static runtime struct layout assertions matching C++ contracts
func ValidateLayout() error {
	if sz := unsafe.Sizeof(BinaryHeader{}); sz != 32 {
		return fmt.Errorf("BinaryHeader size mismatch: expected 32 bytes, got %d", sz)
	}
	if sz := unsafe.Sizeof(NodeState{}); sz != 8 {
		return fmt.Errorf("NodeState size mismatch: expected 8 bytes, got %d", sz)
	}
	if sz := unsafe.Sizeof(TransferCandidate{}); sz != 8 {
		// uint32 (4B) + uint16 (2B) + uint8 (1B) + 1B padding = 8B
		return fmt.Errorf("TransferCandidate size mismatch: expected 8 bytes, got %d", sz)
	}
	return nil
}
