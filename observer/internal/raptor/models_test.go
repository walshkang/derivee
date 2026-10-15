package raptor

import (
	"testing"
	"unsafe"
)

func TestStructSizes(t *testing.T) {
	if sz := unsafe.Sizeof(SectionDesc{}); sz != 24 {
		t.Fatalf("SectionDesc size must be exactly 24 bytes, got %d", sz)
	}
	if sz := unsafe.Sizeof(MasterHeader{}); sz != 232 {
		t.Fatalf("MasterHeader size must be exactly 232 bytes, got %d", sz)
	}
	if sz := unsafe.Sizeof(Stop{}); sz != 20 {
		t.Fatalf("Stop size must be exactly 20 bytes, got %d", sz)
	}
	if sz := unsafe.Sizeof(Route{}); sz != 12 {
		t.Fatalf("Route size must be exactly 12 bytes, got %d", sz)
	}
	if sz := unsafe.Sizeof(Trip{}); sz != 8 {
		t.Fatalf("Trip size must be exactly 8 bytes, got %d", sz)
	}
	if sz := unsafe.Sizeof(StopTime{}); sz != 12 {
		t.Fatalf("StopTime size must be exactly 12 bytes, got %d", sz)
	}
	if sz := unsafe.Sizeof(Transfer{}); sz != 8 {
		t.Fatalf("Transfer size must be exactly 8 bytes, got %d", sz)
	}
	if sz := unsafe.Sizeof(StochasticWeight{}); sz != 4 {
		t.Fatalf("StochasticWeight size must be exactly 4 bytes, got %d", sz)
	}

	if err := ValidateLayout(); err != nil {
		t.Fatalf("ValidateLayout returned error: %v", err)
	}
}

func TestSlotIndexBounds(t *testing.T) {
	idx0 := SlotIndex(0, 0, 0)
	if idx0 != 0 {
		t.Errorf("expected slot 0, got %d", idx0)
	}

	idxEnd := SlotIndex(0, 6, 23)
	if idxEnd != 167 {
		t.Errorf("expected slot 167, got %d", idxEnd)
	}

	idxRoute1 := SlotIndex(1, 0, 0)
	if idxRoute1 != 168 {
		t.Errorf("expected slot 168, got %d", idxRoute1)
	}
}

func TestIsBusBitPack(t *testing.T) {
	var r Route
	r.TripCount = 150 // realistic trip count

	// Initially not a bus
	if IsBus(r) {
		t.Fatal("new Route should not be bus")
	}
	if r.TripCountValue() != 150 {
		t.Fatalf("TripCountValue should be 150, got %d", r.TripCountValue())
	}

	// Set bus bit
	SetIsBus(&r, true)
	if !IsBus(r) {
		t.Fatal("IsBus should be true after SetIsBus(true)")
	}
	if r.TripCountValue() != 150 {
		t.Fatalf("TripCountValue should still be 150 after setting bit, got %d", r.TripCountValue())
	}
	if r.TripCount != 150|IsBusBit {
		t.Fatalf("TripCount should be 150|0x8000, got %d", r.TripCount)
	}

	// Clear bus bit
	SetIsBus(&r, false)
	if IsBus(r) {
		t.Fatal("IsBus should be false after SetIsBus(false)")
	}
	if r.TripCount != 150 {
		t.Fatalf("TripCount should be 150 after clearing, got %d", r.TripCount)
	}
}

func TestIsBusStopBitPack(t *testing.T) {
	var s Stop
	s.RouteCount = 5 // realistic route count

	if IsBusStop(s) {
		t.Fatal("new Stop should not be bus stop")
	}

	SetIsBusStop(&s, true)
	if !IsBusStop(s) {
		t.Fatal("IsBusStop should be true after SetIsBusStop(true)")
	}
	if s.RouteCountValue() != 5 {
		t.Fatalf("RouteCountValue should still be 5, got %d", s.RouteCountValue())
	}

	SetIsBusStop(&s, false)
	if IsBusStop(s) {
		t.Fatal("IsBusStop should be false after SetIsBusStop(false)")
	}
}

func TestStructSizesUnchanged(t *testing.T) {
	// Bit-packing must not change struct sizes (C++ layout compatibility)
	if sz := unsafe.Sizeof(Route{}); sz != 12 {
		t.Fatalf("Route size must remain 12 bytes, got %d", sz)
	}
	if sz := unsafe.Sizeof(Stop{}); sz != 20 {
		t.Fatalf("Stop size must remain 20 bytes, got %d", sz)
	}
}
