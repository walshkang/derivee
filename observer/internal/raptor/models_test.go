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
