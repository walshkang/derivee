package gtfs

import (
	"math"
	"testing"
)

func TestOffsetPolylineMetric_StraightLine(t *testing.T) {
	// Horizontal line along X axis from (0,0) to (100,0)
	pts := []Vec2D{
		{X: 0, Y: 0},
		{X: 50, Y: 0},
		{X: 100, Y: 0},
	}
	d := 3.66 // offset left (positive Y)
	opts := DefaultOffsetOptions

	offset := OffsetPolylineMetric(pts, d, opts)
	if len(offset) != 3 {
		t.Fatalf("expected 3 vertices, got %d", len(offset))
	}

	for i, v := range offset {
		expectedX := pts[i].X
		expectedY := 3.66
		if math.Abs(v.X-expectedX) > 1e-4 || math.Abs(v.Y-expectedY) > 1e-4 {
			t.Errorf("vertex %d mismatch: got (%.4f, %.4f), expected (%.4f, %.4f)", i, v.X, v.Y, expectedX, expectedY)
		}
	}
}

func TestOffsetPolylineMetric_MiterLimit_INV_OFFSET_01(t *testing.T) {
	// Acute turn: incoming (0,0) -> (10, 0), outgoing (10,0) -> (1, 1) [very sharp hairpin angle ~20°]
	pts := []Vec2D{
		{X: 0, Y: 0},
		{X: 10, Y: 0},
		{X: 1, Y: 1},
	}
	d := 3.66
	opts := DefaultOffsetOptions // MiterLimit = 2.0, BevelSharpEdges = true

	offset := OffsetPolylineMetric(pts, d, opts)

	// Since angle is very acute (< 60°), miter ratio without bevel would exceed 2.0.
	// Bevel join must insert 2 vertices at the corner instead of 1.
	if len(offset) != 4 {
		t.Fatalf("expected 4 vertices (bevel join inserted), got %d", len(offset))
	}

	// Verify INV-OFFSET-01: miter ratio for all vertices <= 2.0
	err := ValidateMiterLimit_INV_OFFSET_01(offset, pts, d, opts.MiterLimit)
	if err != nil {
		t.Fatalf("INV-OFFSET-01 violated: %v", err)
	}
}

func TestOffsetPolylineMetric_RightAngleTurn(t *testing.T) {
	// 90° right turn: (0,0) -> (10,0) -> (10,10)
	pts := []Vec2D{
		{X: 0, Y: 0},
		{X: 10, Y: 0},
		{X: 10, Y: 10},
	}
	d := 3.66
	opts := DefaultOffsetOptions

	offset := OffsetPolylineMetric(pts, d, opts)
	// For 90° turn, interior angle is 90°, cos(alpha) = cos(45°) = 0.707, miter ratio = 1 / 0.707 = 1.414 <= 2.0
	// So single miter apex is generated (3 vertices total)
	if len(offset) != 3 {
		t.Fatalf("expected 3 vertices for 90° turn, got %d", len(offset))
	}

	err := ValidateMiterLimit_INV_OFFSET_01(offset, pts, d, opts.MiterLimit)
	if err != nil {
		t.Fatalf("INV-OFFSET-01 check failed: %v", err)
	}
}

func TestCalculateBundleOffsetDistance(t *testing.T) {
	opts := DefaultOffsetOptions // spacing = 3.66, dilation = 0.35

	// K = 1: zero offset
	off1 := CalculateBundleOffsetDistance(0, 1, opts)
	if math.Abs(off1) > 1e-6 {
		t.Errorf("K=1 expected 0 offset, got %f", off1)
	}

	// K = 2: symmetrical around 0 with dilation overlap
	off2_0 := CalculateBundleOffsetDistance(0, 2, opts)
	off2_1 := CalculateBundleOffsetDistance(1, 2, opts)

	if off2_0 >= 0 || off2_1 <= 0 {
		t.Errorf("K=2 offsets should have opposing signs: index 0=%f, index 1=%f", off2_0, off2_1)
	}
	if math.Abs(off2_0+off2_1) > 1e-6 {
		t.Errorf("K=2 offsets must be symmetrical around centerline: %f, %f", off2_0, off2_1)
	}

	// K = 3: index 0 negative, index 1 zero, index 2 positive
	off3_0 := CalculateBundleOffsetDistance(0, 3, opts)
	off3_1 := CalculateBundleOffsetDistance(1, 3, opts)
	off3_2 := CalculateBundleOffsetDistance(2, 3, opts)

	if math.Abs(off3_1) > 1e-6 {
		t.Errorf("K=3 center ribbon should have 0 offset, got %f", off3_1)
	}
	if off3_0 >= 0 || off3_2 <= 0 {
		t.Errorf("K=3 outer ribbons must have opposing signs: index 0=%f, index 2=%f", off3_0, off3_2)
	}
	if math.Abs(off3_0+off3_2) > 1e-6 {
		t.Errorf("K=3 outer ribbons must be symmetrical: %f, %f", off3_0, off3_2)
	}
}

func TestOffsetPolyline_WGS84_Roundtrip(t *testing.T) {
	// NYC Queens Boulevard corridor segment (around Queens Plaza: 40.75N, -73.93W)
	pts := []Point2D{
		{Lon: -73.937225, Lat: 40.749718},
		{Lon: -73.934166, Lat: 40.750875},
		{Lon: -73.929851, Lat: 40.752314},
		{Lon: -73.925812, Lat: 40.753892},
	}
	opts := DefaultOffsetOptions

	offset, err := OffsetPolyline(pts, 3.66, opts)
	if err != nil {
		t.Fatalf("OffsetPolyline failed: %v", err)
	}
	if len(offset) < len(pts) {
		t.Fatalf("expected at least %d points, got %d", len(pts), len(offset))
	}

	// Check that points are shifted by ~3.66 meters
	dist0 := CalculateHaversineDistance(pts[0].Lat, pts[0].Lon, offset[0].Lat, offset[0].Lon)
	if math.Abs(dist0-3.66) > 0.1 {
		t.Errorf("expected offset distance ~3.66m, got %.3fm", dist0)
	}
}
