package gtfs

import (
	"testing"
)

func TestFindSegmentIntersection(t *testing.T) {
	// Segment 1: (0, 0) -> (10, 10)
	// Segment 2: (0, 10) -> (10, 0)
	a := Vec2D{X: 0, Y: 0}
	b := Vec2D{X: 10, Y: 10}
	c := Vec2D{X: 0, Y: 10}
	d := Vec2D{X: 10, Y: 0}

	pt, t1, t2, ok := FindSegmentIntersection(a, b, c, d, 1e-4)
	if !ok {
		t.Fatalf("expected intersection, got none")
	}
	if pt.X != 5.0 || pt.Y != 5.0 {
		t.Errorf("expected intersection at (5,5), got (%.2f, %.2f)", pt.X, pt.Y)
	}
	if t1 != 0.5 || t2 != 0.5 {
		t.Errorf("expected t1=0.5, t2=0.5, got t1=%.2f, t2=%.2f", t1, t2)
	}
}

func TestClipSwallowtailsMetric_HairpinLoop(t *testing.T) {
	// Progenitor hairpin: (0,0) -> (50, 0) -> (50, 2) -> (0, 2)
	generator := []Vec2D{
		{X: 0, Y: 0},
		{X: 50, Y: 0},
		{X: 50, Y: 2},
		{X: 0, Y: 2},
	}

	// Create an offset with an explicit interior self-intersecting loop (swallowtail)
	// Polyline that crosses itself: (0, 5) -> (45, 5) -> (45, -2) -> (30, -2) -> (30, 8) -> (0, 8)
	// Segments (45, 5)->(45, -2) and (30, -2)->(30, 8) cross between Y=-2 and Y=5
	offsetWithLoop := []Vec2D{
		{X: 0, Y: 5},
		{X: 45, Y: 5},
		{X: 45, Y: -2},
		{X: 30, Y: -2},
		{X: 30, Y: 8},
		{X: 0, Y: 8},
	}

	if !HasSelfIntersections(offsetWithLoop) {
		t.Fatalf("fixture must have self-intersection before clipping")
	}

	clipped := ClipSwallowtailsMetric(offsetWithLoop, generator, 5.0)

	// Verify INV-OFFSET-02: zero self-intersections after clipping
	err := ValidateSelfIntersections_INV_OFFSET_02(clipped)
	if err != nil {
		t.Fatalf("INV-OFFSET-02 violated: %v", err)
	}
}

func TestOffsetAndClip_TightConcaveTurn(t *testing.T) {
	// Tight turn with radius R = 2m < offset d = 4m
	// Curve: (0,0) -> (10, 0) -> (12, 1) -> (12, 5)
	generator := []Point2D{
		{Lon: -73.950, Lat: 40.750},
		{Lon: -73.948, Lat: 40.750},
		{Lon: -73.947, Lat: 40.751},
		{Lon: -73.947, Lat: 40.753},
	}

	d := 4.0
	opts := DefaultOffsetOptions

	rawOffset, err := OffsetPolyline(generator, d, opts)
	if err != nil {
		t.Fatalf("OffsetPolyline failed: %v", err)
	}

	clipped := ClipSwallowtails(rawOffset, generator, d)

	metricClipped, _, _ := ProjectToLocalM(clipped)
	err = ValidateSelfIntersections_INV_OFFSET_02(metricClipped)
	if err != nil {
		t.Fatalf("INV-OFFSET-02 violated after clipping: %v", err)
	}
}
