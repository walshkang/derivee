package walk

import (
	"testing"
)

func TestBoundingBox(t *testing.T) {
	bbox := BoundingBox{
		MinLat: 40.7,
		MinLon: -74.0,
		MaxLat: 40.8,
		MaxLon: -73.9,
	}

	if bbox.IsZero() {
		t.Errorf("expected IsZero to be false")
	}

	// Inside
	if !bbox.Contains(40.75, -73.95) {
		t.Errorf("expected (40.75, -73.95) to be inside bbox")
	}

	// Outside lat
	if bbox.Contains(40.69, -73.95) {
		t.Errorf("expected (40.69, -73.95) to be outside bbox")
	}

	// Outside lon
	if bbox.Contains(40.75, -73.89) {
		t.Errorf("expected (40.75, -73.89) to be outside bbox")
	}

	// Zero bbox
	zeroBbox := BoundingBox{}
	if !zeroBbox.IsZero() {
		t.Errorf("expected zeroBbox.IsZero() to be true")
	}
}
