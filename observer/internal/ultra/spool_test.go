package ultra

import (
	"os"
	"path/filepath"
	"testing"
)

func TestSpoolWriterAndStitch(t *testing.T) {
	tempDir, err := os.MkdirTemp("", "ultra_spool_test_*")
	if err != nil {
		t.Fatalf("failed to create temp dir: %v", err)
	}
	defer os.RemoveAll(tempDir)

	numStops := uint32(3)
	tauMax := uint32(900)

	sw, err := NewSpoolWriter(tempDir, numStops, tauMax)
	if err != nil {
		t.Fatalf("NewSpoolWriter failed: %v", err)
	}
	defer sw.Close()

	// Stop 0 shortcuts: (1, 100s), (2, 200s)
	s0 := []TransferCandidate{
		{TargetStop: 1, Duration: 100, Flags: FlagWheelchairAccessible},
		{TargetStop: 2, Duration: 200, Flags: 0},
	}
	if err := sw.AppendStopShortcuts(0, s0); err != nil {
		t.Fatalf("AppendStopShortcuts(0) failed: %v", err)
	}

	// Stop 1 has 0 shortcuts (skip to stop 2)
	// Stop 2 shortcuts: (0, 150s)
	s2 := []TransferCandidate{
		{TargetStop: 0, Duration: 150, Flags: FlagWheelchairAccessible},
	}
	if err := sw.AppendStopShortcuts(2, s2); err != nil {
		t.Fatalf("AppendStopShortcuts(2) failed: %v", err)
	}

	outPath := filepath.Join(tempDir, "test_transfers.csr")
	header, err := sw.StitchToFile(outPath)
	if err != nil {
		t.Fatalf("StitchToFile failed: %v", err)
	}

	if header.NumStops != 3 {
		t.Errorf("expected 3 stops, got %d", header.NumStops)
	}
	if header.NumShortcuts != 3 {
		t.Errorf("expected 3 shortcuts, got %d", header.NumShortcuts)
	}

	// Validate stitched file
	if err := ValidateUltraCSRFile(outPath); err != nil {
		t.Fatalf("ValidateUltraCSRFile failed: %v", err)
	}

	// Read and verify deserialized view
	f, err := os.Open(outPath)
	if err != nil {
		t.Fatalf("failed to open output: %v", err)
	}
	defer f.Close()

	fi, _ := f.Stat()
	view, err := ReadUltraCSR(f, fi.Size())
	if err != nil {
		t.Fatalf("ReadUltraCSR failed: %v", err)
	}

	// Verify indptr: [0, 2, 2, 3]
	expectedIndptr := []uint64{0, 2, 2, 3}
	for i, exp := range expectedIndptr {
		if view.Indptr[i] != exp {
			t.Errorf("indptr[%d]: expected %d, got %d", i, exp, view.Indptr[i])
		}
	}

	// Verify target stops: [1, 2, 0]
	expectedTargets := []uint32{1, 2, 0}
	for i, exp := range expectedTargets {
		if view.TargetStops[i] != exp {
			t.Errorf("target_stops[%d]: expected %d, got %d", i, exp, view.TargetStops[i])
		}
	}

	// Verify durations: [100, 200, 150]
	expectedDurations := []uint16{100, 200, 150}
	for i, exp := range expectedDurations {
		if view.DurationsSec[i] != exp {
			t.Errorf("durations[%d]: expected %d, got %d", i, exp, view.DurationsSec[i])
		}
	}
}
