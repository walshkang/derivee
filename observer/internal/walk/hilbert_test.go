package walk

import (
	"testing"
)

func TestCoordinateNormalization(t *testing.T) {
	minLat, minLon := int32(400000000), int32(-740000000)
	maxLat, maxLon := int32(410000000), int32(-730000000)
	maxVal := uint32(65535)

	// Test bottom-left
	x, y := NormalizeCoordinates(minLat, minLon, minLat, minLon, maxLat, maxLon, maxVal)
	if x != 0 || y != 0 {
		t.Errorf("expected (0, 0), got (%d, %d)", x, y)
	}

	// Test top-right
	x, y = NormalizeCoordinates(maxLat, maxLon, minLat, minLon, maxLat, maxLon, maxVal)
	if x != maxVal || y != maxVal {
		t.Errorf("expected (%d, %d), got (%d, %d)", maxVal, maxVal, x, y)
	}

	// Test midpoint
	midLat := int32(405000000)
	midLon := int32(-735000000)
	x, y = NormalizeCoordinates(midLat, midLon, minLat, minLon, maxLat, maxLon, maxVal)
	if x < 32700 || x > 32800 || y < 32700 || y > 32800 {
		t.Errorf("expected midpoint near 32767, got (%d, %d)", x, y)
	}

	// Test clamping for out of bounds
	x, y = NormalizeCoordinates(390000000, -750000000, minLat, minLon, maxLat, maxLon, maxVal)
	if x != 0 || y != 0 {
		t.Errorf("expected clamped (0, 0), got (%d, %d)", x, y)
	}
}

func TestEncodeHilbert2DDeterminism(t *testing.T) {
	// Origin
	h0 := EncodeHilbert2D(0, 0, 16)
	if h0 != 0 {
		t.Errorf("expected Hilbert(0, 0) == 0, got %d", h0)
	}

	// Distinct points must have distinct values
	h1 := EncodeHilbert2D(1, 0, 16)
	h2 := EncodeHilbert2D(0, 1, 16)
	h3 := EncodeHilbert2D(1, 1, 16)

	if h1 == h0 || h2 == h0 || h3 == h0 || h1 == h2 || h2 == h3 || h1 == h3 {
		t.Errorf("collision in 2x2 quadrant: %d, %d, %d, %d", h0, h1, h2, h3)
	}
}

func TestSortNodesByHilbert(t *testing.T) {
	nodes := []WalkNode{
		{LatQuantized: 407500000, LonQuantized: -739800000}, // node 0
		{LatQuantized: 407100000, LonQuantized: -740100000}, // node 1
		{LatQuantized: 407900000, LonQuantized: -739500000}, // node 2
		{LatQuantized: 407300000, LonQuantized: -739900000}, // node 3
	}

	sorted := SortNodesByHilbert(nodes, 407000000, -740200000, 408000000, -739400000)
	if len(sorted) != len(nodes) {
		t.Fatalf("expected %d sorted items, got %d", len(nodes), len(sorted))
	}

	// Verify monotonically non-decreasing Hilbert values
	for i := 1; i < len(sorted); i++ {
		if sorted[i].HilbertVal < sorted[i-1].HilbertVal {
			t.Errorf("sorting inversion at %d: %d < %d", i, sorted[i].HilbertVal, sorted[i-1].HilbertVal)
		}
	}
}
