package raptor

import (
	"bytes"
	"os"
	"path/filepath"
	"testing"
	"time"
)

func TestSerializeAndDeserializeRoundTrip(t *testing.T) {
	ds := createMockGTFSDataset()
	anchor := time.Date(2026, 8, 31, 0, 0, 0, 0, time.UTC)

	tt, err := CompileTimetable(ds, anchor)
	if err != nil {
		t.Fatalf("CompileTimetable failed: %v", err)
	}

	buf := new(bytes.Buffer)
	header, err := SerializeTimetable(tt, buf)
	if err != nil {
		t.Fatalf("SerializeTimetable failed: %v", err)
	}

	// 1. Verify Header Invariants
	if header.Magic != MagicTimetable {
		t.Errorf("expected Magic 0x%08X, got 0x%08X", MagicTimetable, header.Magic)
	}
	if header.SchemaVersion != SchemaVersion {
		t.Errorf("expected SchemaVersion %d, got %d", SchemaVersion, header.SchemaVersion)
	}
	if header.EndianMarker != EndianMarker {
		t.Errorf("expected EndianMarker 0x%08X, got 0x%08X", EndianMarker, header.EndianMarker)
	}
	if header.HeaderSize != MasterHeaderSize {
		t.Errorf("expected HeaderSize %d, got %d", MasterHeaderSize, header.HeaderSize)
	}
	if header.NumSections != 8 {
		t.Errorf("expected NumSections 8, got %d", header.NumSections)
	}

	// 2. Verify 64-byte alignment of each section offset and total file size
	for i := 0; i < 8; i++ {
		sec := header.TOC[i]
		if sec.Offset%64 != 0 {
			t.Errorf("section %d offset %d is not 64-byte aligned", i, sec.Offset)
		}
	}
	if header.FileSize%64 != 0 {
		t.Errorf("file size %d is not 64-byte aligned", header.FileSize)
	}

	// 3. Deserialize and verify field-by-field parity
	rawBytes := buf.Bytes()
	reader := bytes.NewReader(rawBytes)
	view, err := ReadTimetable(reader, int64(len(rawBytes)))
	if err != nil {
		t.Fatalf("ReadTimetable failed: %v", err)
	}

	if len(view.Stops) != len(tt.Stops) {
		t.Errorf("expected %d stops, got %d", len(tt.Stops), len(view.Stops))
	}
	for i := range tt.Stops {
		if view.Stops[i].Latitude != tt.Stops[i].Latitude || view.Stops[i].Longitude != tt.Stops[i].Longitude {
			t.Errorf("stop %d coordinate mismatch", i)
		}
		if view.Stops[i].RouteCount != tt.Stops[i].RouteCount {
			t.Errorf("stop %d route count mismatch", i)
		}
	}

	if len(view.Routes) != len(tt.Routes) {
		t.Errorf("expected %d routes, got %d", len(tt.Routes), len(view.Routes))
	}
	for i := range tt.Routes {
		if view.Routes[i].TripCount != tt.Routes[i].TripCount || view.Routes[i].StopCount != tt.Routes[i].StopCount {
			t.Errorf("route %d counts mismatch", i)
		}
	}

	if len(view.Trips) != len(tt.Trips) {
		t.Errorf("expected %d trips, got %d", len(tt.Trips), len(view.Trips))
	}
	if len(view.StopTimes) != len(tt.StopTimes) {
		t.Errorf("expected %d stop times, got %d", len(tt.StopTimes), len(view.StopTimes))
	}
	if len(view.Transfers) != len(tt.Transfers) {
		t.Errorf("expected %d transfers, got %d", len(tt.Transfers), len(view.Transfers))
	}
	if len(view.StopRoutes) != len(tt.StopRoutes) {
		t.Errorf("expected %d stop routes, got %d", len(tt.StopRoutes), len(view.StopRoutes))
	}
	if len(view.RouteStops) != len(tt.RouteStops) {
		t.Errorf("expected %d route stops, got %d", len(tt.RouteStops), len(view.RouteStops))
	}
	if len(view.StochasticWeights) != len(tt.StochasticWeights) {
		t.Errorf("expected %d stochastic weights, got %d", len(tt.StochasticWeights), len(view.StochasticWeights))
	}
}

func TestChecksumCorruptionDetection(t *testing.T) {
	ds := createMockGTFSDataset()
	tt, _ := CompileTimetable(ds, time.Now())

	buf := new(bytes.Buffer)
	_, err := SerializeTimetable(tt, buf)
	if err != nil {
		t.Fatalf("SerializeTimetable failed: %v", err)
	}

	rawBytes := buf.Bytes()
	// Corrupt a byte in the payload
	corrupted := make([]byte, len(rawBytes))
	copy(corrupted, rawBytes)
	corrupted[len(rawBytes)-10] ^= 0xFF

	_, err = ReadTimetable(bytes.NewReader(corrupted), int64(len(corrupted)))
	if err == nil {
		t.Fatalf("expected error on corrupted checksum, got nil")
	}
}

func TestWriteTimetableFile(t *testing.T) {
	ds := createMockGTFSDataset()
	tt, _ := CompileTimetable(ds, time.Now())

	tmpDir, err := os.MkdirTemp("", "raptor_test_*")
	if err != nil {
		t.Fatalf("failed to create temp dir: %v", err)
	}
	defer os.RemoveAll(tmpDir)

	outPath := filepath.Join(tmpDir, "timetable.bin")
	header, err := WriteTimetableFile(tt, outPath)
	if err != nil {
		t.Fatalf("WriteTimetableFile failed: %v", err)
	}

	fi, err := os.Stat(outPath)
	if err != nil {
		t.Fatalf("failed to stat output file: %v", err)
	}
	if uint64(fi.Size()) != header.FileSize {
		t.Errorf("file size on disk (%d) != header file size (%d)", fi.Size(), header.FileSize)
	}

	f, err := os.Open(outPath)
	if err != nil {
		t.Fatalf("failed to open output file: %v", err)
	}
	defer f.Close()

	view, err := ReadTimetable(f, fi.Size())
	if err != nil {
		t.Fatalf("ReadTimetable from file failed: %v", err)
	}
	if len(view.Stops) != len(tt.Stops) {
		t.Errorf("expected %d stops from file, got %d", len(tt.Stops), len(view.Stops))
	}
}

func TestNYCScaleMemoryFootprint(t *testing.T) {
	// Synthesize a NYC MTA scale timetable:
	// 15,500 stops, 1,200 routes, 30,000 trips, 1,050,000 stop times (~35 stops/trip)
	// 62,000 stop-route entries, 48,000 route-stop entries, 232,500 transfers
	const (
		numStops     = 15500
		numRoutes    = 1200
		numTrips     = 30000
		numStopTimes = 1050000
		numTransfers = 232500
		numStopRoutes = 62000
		numRouteStops = 48000
	)

	stops := make([]Stop, numStops)
	for i := range stops {
		stops[i] = Stop{
			Latitude:        40.7128,
			Longitude:       -74.0060,
			RoutesOffset:    uint32(i * 4),
			TransfersOffset: uint32(i * 15),
			RouteCount:      4,
			TransferCount:   15,
		}
	}

	routes := make([]Route, numRoutes)
	for i := range routes {
		routes[i] = Route{
			TripsOffset:      uint32(i * 25),
			RouteStopsOffset: uint32(i * 40),
			TripCount:        25,
			StopCount:        40,
		}
	}

	trips := make([]Trip, numTrips)
	for i := range trips {
		trips[i] = Trip{
			StopTimesOffset: uint32(i * 35),
			StopTimesCount:  35,
			ServiceID:       1,
		}
	}

	stopTimes := make([]StopTime, numStopTimes)
	for i := range stopTimes {
		stopTimes[i] = StopTime{
			ArrivalTimeSec:   uint32(28800 + i*60),
			DepartureTimeSec: uint32(28800 + i*60 + 30),
			StopID:           uint32(i % numStops),
		}
	}

	transfers := make([]Transfer, numTransfers)
	for i := range transfers {
		transfers[i] = Transfer{
			TargetStopID:   uint32((i + 1) % numStops),
			DurationSec:    180,
			DistanceMeters: 200,
		}
	}

	stopRoutes := make([]uint32, numStopRoutes)
	for i := range stopRoutes {
		stopRoutes[i] = uint32(i % numRoutes)
	}

	routeStops := make([]uint32, numRouteStops)
	for i := range routeStops {
		routeStops[i] = uint32(i % numStops)
	}

	stochastic := make([]StochasticWeight, numRoutes*SlotsPerWeek)
	for i := range stochastic {
		stochastic[i] = StochasticWeight{
			ExpectedWaitSec: 300,
			VariancePenalty: 50,
		}
	}

	compiled := &CompiledTimetable{
		Stops:             stops,
		Routes:            routes,
		Trips:             trips,
		StopTimes:         stopTimes,
		Transfers:         transfers,
		StopRoutes:        stopRoutes,
		RouteStops:        routeStops,
		StochasticWeights: stochastic,
	}

	buf := new(bytes.Buffer)
	header, err := SerializeTimetable(compiled, buf)
	if err != nil {
		t.Fatalf("SerializeTimetable failed: %v", err)
	}

	fileSizeMB := float64(header.FileSize) / (1024.0 * 1024.0)
	t.Logf("NYC MTA Scale Timetable Binary Size: %.3f MB (%d bytes)", fileSizeMB, header.FileSize)

	// Target: <= 20.64 MB (iOS Jetsam budget requirement)
	const maxAllowedMB = 20.64
	if fileSizeMB > maxAllowedMB {
		t.Fatalf("NYC scale timetable size %.3f MB exceeds ceiling of %.2f MB", fileSizeMB, maxAllowedMB)
	}
}
