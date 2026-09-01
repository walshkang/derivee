package raptor

import (
	"bytes"
	"encoding/binary"
	"fmt"
	"io"
	"os"
	"unsafe"

	"github.com/cespare/xxhash/v2"
)

// TimetableView provides a typed deserialized view of the binary timetable
type TimetableView struct {
	Header            MasterHeader
	Stops             []Stop
	Routes            []Route
	Trips             []Trip
	StopTimes         []StopTime
	Transfers         []Transfer
	StopRoutes        []uint32
	RouteStops        []uint32
	StochasticWeights []StochasticWeight
}

// SerializeTimetable serializes a CompiledTimetable into a byte stream with the 232-byte MasterHeader
func SerializeTimetable(tt *CompiledTimetable, w io.Writer) (*MasterHeader, error) {
	if err := ValidateLayout(); err != nil {
		return nil, fmt.Errorf("layout validation failed: %w", err)
	}

	numStops := uint64(len(tt.Stops))
	numRoutes := uint64(len(tt.Routes))
	numTrips := uint64(len(tt.Trips))
	numStopTimes := uint64(len(tt.StopTimes))
	numTransfers := uint64(len(tt.Transfers))
	numStopRoutes := uint64(len(tt.StopRoutes))
	numRouteStops := uint64(len(tt.RouteStops))
	numStochastic := uint64(len(tt.StochasticWeights))

	lenS0 := numStops * uint64(unsafe.Sizeof(Stop{}))
	lenS1 := numRoutes * uint64(unsafe.Sizeof(Route{}))
	lenS2 := numTrips * uint64(unsafe.Sizeof(Trip{}))
	lenS3 := numStopTimes * uint64(unsafe.Sizeof(StopTime{}))
	lenS4 := numTransfers * uint64(unsafe.Sizeof(Transfer{}))
	lenS5 := numStopRoutes * uint64(unsafe.Sizeof(uint32(0)))
	lenS6 := numRouteStops * uint64(unsafe.Sizeof(uint32(0)))
	lenS7 := numStochastic * uint64(unsafe.Sizeof(StochasticWeight{}))

	align64 := func(off uint64) uint64 {
		if off%64 != 0 {
			return off + (64 - (off % 64))
		}
		return off
	}

	// Section offsets (64-byte cache line aligned)
	offS0 := align64(uint64(MasterHeaderSize)) // 256 bytes
	offS1 := align64(offS0 + lenS0)
	offS2 := align64(offS1 + lenS1)
	offS3 := align64(offS2 + lenS2)
	offS4 := align64(offS3 + lenS3)
	offS5 := align64(offS4 + lenS4)
	offS6 := align64(offS5 + lenS5)
	offS7 := align64(offS6 + lenS6)
	totalFileSize := align64(offS7 + lenS7)

	// 1. Build Payload buffer
	payloadBuf := new(bytes.Buffer)
	payloadBuf.Grow(int(totalFileSize - uint64(MasterHeaderSize)))

	writePad := func(targetAbsOffset uint64) {
		currentPayloadLen := uint64(payloadBuf.Len())
		targetRelOffset := targetAbsOffset - uint64(MasterHeaderSize)
		if currentPayloadLen < targetRelOffset {
			pad := make([]byte, targetRelOffset-currentPayloadLen)
			payloadBuf.Write(pad)
		}
	}

	// Section 0: Stops
	writePad(offS0)
	for _, s := range tt.Stops {
		if err := binary.Write(payloadBuf, binary.LittleEndian, s); err != nil {
			return nil, fmt.Errorf("failed to write stop: %w", err)
		}
	}

	// Section 1: Routes
	writePad(offS1)
	for _, r := range tt.Routes {
		if err := binary.Write(payloadBuf, binary.LittleEndian, r); err != nil {
			return nil, fmt.Errorf("failed to write route: %w", err)
		}
	}

	// Section 2: Trips
	writePad(offS2)
	for _, t := range tt.Trips {
		if err := binary.Write(payloadBuf, binary.LittleEndian, t); err != nil {
			return nil, fmt.Errorf("failed to write trip: %w", err)
		}
	}

	// Section 3: StopTimes
	writePad(offS3)
	for _, st := range tt.StopTimes {
		if err := binary.Write(payloadBuf, binary.LittleEndian, st); err != nil {
			return nil, fmt.Errorf("failed to write stop time: %w", err)
		}
	}

	// Section 4: Transfers
	writePad(offS4)
	for _, tr := range tt.Transfers {
		if err := binary.Write(payloadBuf, binary.LittleEndian, tr); err != nil {
			return nil, fmt.Errorf("failed to write transfer: %w", err)
		}
	}

	// Section 5: StopRoutes
	writePad(offS5)
	for _, sr := range tt.StopRoutes {
		if err := binary.Write(payloadBuf, binary.LittleEndian, sr); err != nil {
			return nil, fmt.Errorf("failed to write stop route: %w", err)
		}
	}

	// Section 6: RouteStops
	writePad(offS6)
	for _, rs := range tt.RouteStops {
		if err := binary.Write(payloadBuf, binary.LittleEndian, rs); err != nil {
			return nil, fmt.Errorf("failed to write route stop: %w", err)
		}
	}

	// Section 7: StochasticWeights
	writePad(offS7)
	for _, sw := range tt.StochasticWeights {
		if err := binary.Write(payloadBuf, binary.LittleEndian, sw); err != nil {
			return nil, fmt.Errorf("failed to write stochastic weight: %w", err)
		}
	}

	// Final file padding to 64-byte boundary
	currentTotal := uint64(MasterHeaderSize) + uint64(payloadBuf.Len())
	if currentTotal < totalFileSize {
		pad := make([]byte, totalFileSize-currentTotal)
		payloadBuf.Write(pad)
	}

	payloadBytes := payloadBuf.Bytes()

	// 2. Compute xxHash64 Checksum
	checksum := xxhash.Sum64(payloadBytes)

	// 3. Construct MasterHeader
	header := MasterHeader{
		Magic:         MagicTimetable,
		SchemaVersion: SchemaVersion,
		EndianMarker:  EndianMarker,
		HeaderSize:    MasterHeaderSize,
		FileSize:      totalFileSize,
		ChecksumXXH64: checksum,
		NumSections:   8,
		Flags:         0,
		TOC: [8]SectionDesc{
			{Offset: offS0, SizeBytes: lenS0, ItemCount: numStops},
			{Offset: offS1, SizeBytes: lenS1, ItemCount: numRoutes},
			{Offset: offS2, SizeBytes: lenS2, ItemCount: numTrips},
			{Offset: offS3, SizeBytes: lenS3, ItemCount: numStopTimes},
			{Offset: offS4, SizeBytes: lenS4, ItemCount: numTransfers},
			{Offset: offS5, SizeBytes: lenS5, ItemCount: numStopRoutes},
			{Offset: offS6, SizeBytes: lenS6, ItemCount: numRouteStops},
			{Offset: offS7, SizeBytes: lenS7, ItemCount: numStochastic},
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

// WriteTimetableFile serializes the timetable directly to a binary file
func WriteTimetableFile(tt *CompiledTimetable, outputPath string) (*MasterHeader, error) {
	f, err := os.Create(outputPath)
	if err != nil {
		return nil, fmt.Errorf("failed to create output file %s: %w", outputPath, err)
	}
	defer f.Close()

	header, err := SerializeTimetable(tt, f)
	if err != nil {
		return nil, err
	}

	if err := f.Sync(); err != nil {
		return nil, fmt.Errorf("failed to sync file: %w", err)
	}

	return header, nil
}

// ReadTimetable deserializes a timetable binary and validates all header markers and checksums
func ReadTimetable(r io.ReaderAt, fileSize int64) (*TimetableView, error) {
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
	if header.Magic != MagicTimetable {
		return nil, fmt.Errorf("invalid magic signature: 0x%08X (expected 0x%08X)", header.Magic, MagicTimetable)
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

	readSection := func(secIdx int, target any, itemSize int) error {
		sec := header.TOC[secIdx]
		if sec.ItemCount == 0 {
			return nil
		}
		if sec.Offset+sec.SizeBytes > uint64(fileSize) {
			return fmt.Errorf("section %d bounds exceed file size", secIdx)
		}
		secBytes := make([]byte, sec.SizeBytes)
		if _, err := r.ReadAt(secBytes, int64(sec.Offset)); err != nil {
			return fmt.Errorf("failed to read section %d bytes: %w", secIdx, err)
		}
		if err := binary.Read(bytes.NewReader(secBytes), binary.LittleEndian, target); err != nil {
			return fmt.Errorf("failed to parse section %d: %w", secIdx, err)
		}
		return nil
	}

	// Section 0: Stops
	stops := make([]Stop, header.TOC[0].ItemCount)
	if err := readSection(0, &stops, int(unsafe.Sizeof(Stop{}))); err != nil {
		return nil, err
	}

	// Section 1: Routes
	routes := make([]Route, header.TOC[1].ItemCount)
	if err := readSection(1, &routes, int(unsafe.Sizeof(Route{}))); err != nil {
		return nil, err
	}

	// Section 2: Trips
	trips := make([]Trip, header.TOC[2].ItemCount)
	if err := readSection(2, &trips, int(unsafe.Sizeof(Trip{}))); err != nil {
		return nil, err
	}

	// Section 3: StopTimes
	stopTimes := make([]StopTime, header.TOC[3].ItemCount)
	if err := readSection(3, &stopTimes, int(unsafe.Sizeof(StopTime{}))); err != nil {
		return nil, err
	}

	// Section 4: Transfers
	transfers := make([]Transfer, header.TOC[4].ItemCount)
	if err := readSection(4, &transfers, int(unsafe.Sizeof(Transfer{}))); err != nil {
		return nil, err
	}

	// Section 5: StopRoutes
	stopRoutes := make([]uint32, header.TOC[5].ItemCount)
	if err := readSection(5, &stopRoutes, int(unsafe.Sizeof(uint32(0)))); err != nil {
		return nil, err
	}

	// Section 6: RouteStops
	routeStops := make([]uint32, header.TOC[6].ItemCount)
	if err := readSection(6, &routeStops, int(unsafe.Sizeof(uint32(0)))); err != nil {
		return nil, err
	}

	// Section 7: StochasticWeights
	stochastic := make([]StochasticWeight, header.TOC[7].ItemCount)
	if err := readSection(7, &stochastic, int(unsafe.Sizeof(StochasticWeight{}))); err != nil {
		return nil, err
	}

	return &TimetableView{
		Header:            header,
		Stops:             stops,
		Routes:            routes,
		Trips:             trips,
		StopTimes:         stopTimes,
		Transfers:         transfers,
		StopRoutes:        stopRoutes,
		RouteStops:        routeStops,
		StochasticWeights: stochastic,
	}, nil
}
