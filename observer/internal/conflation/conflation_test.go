package conflation

import (
	"testing"

	"observer/internal/gtfs"
)

func TestParseLevels(t *testing.T) {
	tests := []struct {
		name     string
		levelStr string
		repeatOn string
		expected []float64
	}{
		{
			name:     "Single ground level",
			levelStr: "0",
			expected: []float64{0.0},
		},
		{
			name:     "Subterranean intermediate mezzanine",
			levelStr: "-1.5",
			expected: []float64{-1.5},
		},
		{
			name:     "Compound vertical connector",
			levelStr: "-1;0",
			expected: []float64{-1.0, 0.0},
		},
		{
			name:     "Positive range",
			levelStr: "1-3",
			expected: []float64{1.0, 2.0, 3.0},
		},
		{
			name:     "Negative basement range",
			levelStr: "-3--1",
			expected: []float64{-3.0, -2.0, -1.0},
		},
		{
			name:     "Base level with repeat_on",
			levelStr: "0",
			repeatOn: "1-3",
			expected: []float64{0.0, 1.0, 2.0, 3.0},
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			slices := ParseLevels(tc.levelStr, tc.repeatOn)
			if len(slices) != len(tc.expected) {
				t.Fatalf("Expected %d levels, got %d (%v)", len(tc.expected), len(slices), slices)
			}
			sliceMap := make(map[float64]bool)
			for _, s := range slices {
				sliceMap[s] = true
			}
			for _, exp := range tc.expected {
				if !sliceMap[exp] {
					t.Errorf("Expected level %f in slices, but missing from %v", exp, slices)
				}
			}
		})
	}
}

func TestResolveGTFSComplex_400mRadius(t *testing.T) {
	complexes := []gtfs.Complex{
		{
			ComplexID:   600001,
			ComplexName: "Penn Station - Moynihan Train Hall Complex",
			Latitude:    40.750568,
			Longitude:   -73.993519,
			IsHub:       1,
		},
		{
			ComplexID:   602,
			ComplexName: "14 St-Union Sq",
			Latitude:    40.735000,
			Longitude:   -73.990500,
			IsHub:       0,
		},
	}

	// Moynihan Train Hall concourse entrance (~150m west of Penn Station centroid)
	moynihanLat := 40.751500
	moynihanLon := -73.996000
	cid := ResolveGTFSComplex(moynihanLat, moynihanLon, complexes, 400.0)
	if cid != 600001 {
		t.Errorf("Expected Moynihan coordinates to resolve to Penn Station (600001), got %d", cid)
	}

	// 14 St-Union Sq mezzanine (~50m from centroid)
	unionSqMezzLat := 40.735200
	unionSqMezzLon := -73.990400
	cidUnion := ResolveGTFSComplex(unionSqMezzLat, unionSqMezzLon, complexes, 400.0)
	if cidUnion != 602 {
		t.Errorf("Expected Union Sq coordinates to resolve to 602, got %d", cidUnion)
	}

	// Distant coordinate in Central Park (>1000m from both)
	centralParkLat := 40.780000
	centralParkLon := -73.965000
	cidDistant := ResolveGTFSComplex(centralParkLat, centralParkLon, complexes, 400.0)
	if cidDistant != 0 {
		t.Errorf("Expected distant coordinate to resolve to unassigned (0), got %d", cidDistant)
	}
}

func TestRoundCoordinate(t *testing.T) {
	val := 40.750568123456
	rounded := RoundCoordinate(val)
	if rounded != 40.750568 {
		t.Errorf("Expected 40.750568, got %f", rounded)
	}
}
