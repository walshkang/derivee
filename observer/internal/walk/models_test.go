package walk

import (
	"testing"
	"unsafe"
)

func TestStructSizes(t *testing.T) {
	if sz := unsafe.Sizeof(MasterHeader{}); sz != 136 {
		t.Fatalf("MasterHeader size must be exactly 136 bytes, got %d", sz)
	}
	if sz := unsafe.Sizeof(SectionDesc{}); sz != 24 {
		t.Fatalf("SectionDesc size must be exactly 24 bytes, got %d", sz)
	}
	if sz := unsafe.Sizeof(WalkNode{}); sz != 16 {
		t.Fatalf("WalkNode size must be exactly 16 bytes, got %d", sz)
	}
	if sz := unsafe.Sizeof(WalkEdge{}); sz != 8 {
		t.Fatalf("WalkEdge size must be exactly 8 bytes, got %d", sz)
	}

	if err := ValidateLayout(); err != nil {
		t.Fatalf("ValidateLayout returned error: %v", err)
	}
}

func TestEdgeFlagsBitmask(t *testing.T) {
	var flags uint8 = 0
	flags |= FlagWalkable
	if (flags & FlagWalkable) == 0 {
		t.Errorf("expected FlagWalkable to be set")
	}

	flags |= FlagWheelchairAccessible
	if (flags & FlagWheelchairAccessible) == 0 {
		t.Errorf("expected FlagWheelchairAccessible to be set")
	}

	flags |= FlagIsSteps
	if (flags & FlagIsSteps) == 0 {
		t.Errorf("expected FlagIsSteps to be set")
	}

	flags |= FlagIsElevator
	if (flags & FlagIsElevator) == 0 {
		t.Errorf("expected FlagIsElevator to be set")
	}

	// Verify exact bit positions
	if FlagWalkable != 1 {
		t.Errorf("FlagWalkable bit mismatch: got %d, expected 1", FlagWalkable)
	}
	if FlagWheelchairAccessible != 2 {
		t.Errorf("FlagWheelchairAccessible bit mismatch: got %d, expected 2", FlagWheelchairAccessible)
	}
	if FlagIsSteps != 4 {
		t.Errorf("FlagIsSteps bit mismatch: got %d, expected 4", FlagIsSteps)
	}
	if FlagIsElevator != 8 {
		t.Errorf("FlagIsElevator bit mismatch: got %d, expected 8", FlagIsElevator)
	}
}
