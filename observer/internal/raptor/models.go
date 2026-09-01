package raptor

import (
	"fmt"
	"unsafe"
)

const (
	// MagicTimetable is the 4-byte magic signature "DRV1" (0x31565244 little-endian)
	MagicTimetable uint32 = 0x31565244
	// EndianMarker is the 4-byte validation marker strictly set to 0x01020304
	EndianMarker uint32 = 0x01020304
	// SchemaVersion is the current binary format version
	SchemaVersion uint32 = 1
	// MasterHeaderSize is the exact size of the universal master file header in bytes (40 + 8*24 = 232 bytes)
	MasterHeaderSize uint32 = 232
)

// SectionDesc describes a typed binary payload section in the Table of Contents (24 bytes)
type SectionDesc struct {
	Offset    uint64 // Absolute byte offset in file (64-byte aligned)
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

// Stop represents a physical station or transit stop (20 Bytes matching C++ Stop)
type Stop struct {
	Latitude        float32 // IEEE 754 32-bit floating point coordinate
	Longitude       float32 // IEEE 754 32-bit floating point coordinate
	RoutesOffset    uint32  // Index offset into global Stop-Routes inverted index array
	TransfersOffset uint32  // Index offset into global Transfer array
	RouteCount      uint16  // Number of transit routes serving this stop
	TransferCount   uint16  // Number of outgoing intra-timetable transfers
}

// Route groups trips operating on identical stop sequences (12 Bytes matching C++ Route)
type Route struct {
	TripsOffset      uint32 // Index offset into global contiguous Trip array
	RouteStopsOffset uint32 // Index offset into global Route-Stops sequence array
	TripCount        uint16 // Total number of trips scheduled on this route
	StopCount        uint16 // Number of stops along this route sequence
}

// Trip represents an individual vehicle journey (8 Bytes matching C++ Trip)
type Trip struct {
	StopTimesOffset uint32 // Index offset into global contiguous StopTime array
	StopTimesCount  uint16 // Number of stops served by this trip
	ServiceID       uint16 // Bitmask / ID for calendar service operational mask
}

// StopTime represents an arrival/departure event at a specific stop (12 Bytes matching C++ StopTime)
type StopTime struct {
	ArrivalTimeSec   uint32 // Seconds relative to daily epoch (supports > 86400)
	DepartureTimeSec uint32 // Departure time in seconds relative to daily epoch
	StopID           uint32 // 32-bit index into global contiguous Stop array
}

// Transfer represents a static outgoing transfer edge (8 Bytes matching C++ Transfer)
type Transfer struct {
	TargetStopID   uint32 // 32-bit index to destination stop
	DurationSec    uint16 // Walking / transfer duration in seconds
	DistanceMeters uint16 // Physical distance in meters
}

// StochasticWeight holds quantized expected wait time and variance penalty per (DoW x Hour) slot (4 Bytes)
type StochasticWeight struct {
	ExpectedWaitSec uint16 // E[wait] = h/2 + sigma^2/(2h) in seconds
	VariancePenalty uint16 // Quantized variance risk score (0-1000)
}

// CompiledTimetable encapsulates all flattened contiguous arrays ready for binary serialization
type CompiledTimetable struct {
	Stops             []Stop
	Routes            []Route
	Trips             []Trip
	StopTimes         []StopTime
	Transfers         []Transfer
	StopRoutes        []uint32
	RouteStops        []uint32
	StochasticWeights []StochasticWeight

	// Metadata string maps
	StopIDToIndex  map[string]uint32
	IndexToStopID  []string
	RouteIDToIndex map[string]uint32
	IndexToRouteID []string
	TripIDToIndex  map[string]uint32
	IndexToTripID  []string
}

// ValidateLayout performs runtime struct layout verification matching C++ static_assert checks
func ValidateLayout() error {
	if sz := unsafe.Sizeof(SectionDesc{}); sz != 24 {
		return fmt.Errorf("SectionDesc size mismatch: expected 24 bytes, got %d", sz)
	}
	if sz := unsafe.Sizeof(MasterHeader{}); sz != 232 {
		return fmt.Errorf("MasterHeader size mismatch: expected 232 bytes, got %d", sz)
	}
	if sz := unsafe.Sizeof(Stop{}); sz != 20 {
		return fmt.Errorf("Stop size mismatch: expected 20 bytes, got %d", sz)
	}
	if sz := unsafe.Sizeof(Route{}); sz != 12 {
		return fmt.Errorf("Route size mismatch: expected 12 bytes, got %d", sz)
	}
	if sz := unsafe.Sizeof(Trip{}); sz != 8 {
		return fmt.Errorf("Trip size mismatch: expected 8 bytes, got %d", sz)
	}
	if sz := unsafe.Sizeof(StopTime{}); sz != 12 {
		return fmt.Errorf("StopTime size mismatch: expected 12 bytes, got %d", sz)
	}
	if sz := unsafe.Sizeof(Transfer{}); sz != 8 {
		return fmt.Errorf("Transfer size mismatch: expected 8 bytes, got %d", sz)
	}
	if sz := unsafe.Sizeof(StochasticWeight{}); sz != 4 {
		return fmt.Errorf("StochasticWeight size mismatch: expected 4 bytes, got %d", sz)
	}
	return nil
}
