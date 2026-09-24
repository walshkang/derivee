package gtfs

import (
	"math"
	"testing"
)

func TestHermiteFillet_C1Continuity_INV_FILLET_01(t *testing.T) {
	// Trunk heading East: T0 = (1, 0)
	// Branch diverging at 20° North of East: T1 = (cos(20°), sin(20°))
	deg20 := 20.0 * math.Pi / 180.0
	t0 := Vec2D{X: 1.0, Y: 0.0}
	t1 := Vec2D{X: math.Cos(deg20), Y: math.Sin(deg20)}

	// Lateral offset at trunk: P0 = (0, -3.66)
	// Target at branch: P1 = (50, 0)
	p0 := Vec2D{X: 0.0, Y: -3.66}
	p1 := Vec2D{X: 50.0, Y: 0.0}

	arcLengthM := 300.0 // 300m arc

	res, err := BuildHermiteFilletMetric(p0, p1, t0, t1, arcLengthM, 16)
	if err != nil {
		t.Fatalf("BuildHermiteFilletMetric failed: %v", err)
	}

	// Verify INV-FILLET-01
	if err := ValidateFilletContinuity_INV_FILLET_01(res); err != nil {
		t.Fatalf("INV-FILLET-01 failed: %v", err)
	}

	// Verify points generated
	if len(res.PointsVec) != 17 {
		t.Fatalf("expected 17 points, got %d", len(res.PointsVec))
	}
}

func TestHermiteFillet_LengthBounds_INV_FILLET_02(t *testing.T) {
	tests := []struct {
		name       string
		targetM    float64
		arcLengthM float64
		minExpect  float64
		maxExpect  float64
	}{
		{
			name:       "Standard 300m arc: target 50m respected",
			targetM:    50.0,
			arcLengthM: 300.0, // 0.35 * 300 = 105m
			minExpect:  20.0,
			maxExpect:  120.0,
		},
		{
			name:       "Short 80m arc: clamped to <= 35% (28m)",
			targetM:    50.0,
			arcLengthM: 80.0, // 0.35 * 80 = 28m
			minExpect:  20.0,
			maxExpect:  28.0,
		},
		{
			name:       "Very long 1000m express arc: clamped to <= 120m",
			targetM:    150.0,
			arcLengthM: 1000.0, // 0.35 * 1000 = 350m
			minExpect:  20.0,
			maxExpect:  120.0,
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			filletLen := ClampFilletLength(tc.targetM, tc.arcLengthM)
			if filletLen < tc.minExpect || filletLen > tc.maxExpect {
				t.Errorf("length %.1fm outside expected [%.1fm, %.1fm]", filletLen, tc.minExpect, tc.maxExpect)
			}
			if err := ValidateFilletLength_INV_FILLET_02(filletLen, tc.arcLengthM); err != nil {
				t.Errorf("INV-FILLET-02 validation failed: %v", err)
			}
		})
	}
}

func TestHermiteFillet_WGS84_Roundtrip(t *testing.T) {
	// Diverging switch near Queens Plaza (40.75N, -73.93W)
	p0 := Point2D{Lon: -73.937255, Lat: 40.749742} // Offset Blue E ribbon
	p1 := Point2D{Lon: -73.934166, Lat: 40.750875} // Branch target on centerline

	t0 := Point2D{Lon: 0.866, Lat: 0.5}
	t1 := Point2D{Lon: 0.707, Lat: 0.707}

	res, err := BuildHermiteFillet(p0, p1, t0, t1, 400.0, 10)
	if err != nil {
		t.Fatalf("BuildHermiteFillet failed: %v", err)
	}

	if len(res.PointsWGS) != 11 {
		t.Fatalf("expected 11 WGS points, got %d", len(res.PointsWGS))
	}
	if err := ValidateFilletContinuity_INV_FILLET_01(res); err != nil {
		t.Fatalf("INV-FILLET-01 check failed: %v", err)
	}
}

func TestOffsetPolylineWithFillet(t *testing.T) {
	// A 200m track along X axis from (0,0) to (200,0)
	pts := []Vec2D{
		{X: 0, Y: 0},
		{X: 50, Y: 0},
		{X: 100, Y: 0},
		{X: 150, Y: 0},
		{X: 200, Y: 0},
	}
	opts := DefaultOffsetOptions

	// Divergence: starts at offset -3.66m (trunk ribbon), transitions to 0.0m (centerline branch)
	offsetPts := OffsetPolylineWithFilletMetric(pts, -3.66, 0.0, opts)

	if len(offsetPts) != len(pts) {
		t.Fatalf("expected %d points, got %d", len(pts), len(offsetPts))
	}

	// First vertex should be at Y = -3.66
	if math.Abs(offsetPts[0].Y - (-3.66)) > 1e-3 {
		t.Errorf("expected start Y=-3.66, got %f", offsetPts[0].Y)
	}

	// Fillet length is clamp(50, 0.35*200 = 70, 120) = 50m.
	// So by X = 100m, the transition should be fully completed (Y = 0.0)
	if math.Abs(offsetPts[2].Y) > 1e-3 {
		t.Errorf("expected Y=0.0 at X=100m (beyond 50m fillet), got %f", offsetPts[2].Y)
	}
	if math.Abs(offsetPts[4].Y) > 1e-3 {
		t.Errorf("expected Y=0.0 at end, got %f", offsetPts[4].Y)
	}
}

