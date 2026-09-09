package gtfs

import (
	"testing"
)

func TestBuildComplexResolutionHierarchy_RegionalHubs(t *testing.T) {
	stops := map[string]Stop{
		// Penn Station - 8th Ave (A C E)
		"A28": {
			StopID:       "A28",
			StopName:     "34 St-Penn Station",
			StopLat:      40.752287,
			StopLon:      -73.993391,
			LocationType: 1,
		},
		"A28N": {
			StopID:        "A28N",
			StopName:      "34 St-Penn Station (Uptown)",
			StopLat:       40.752300,
			StopLon:       -73.993400,
			LocationType:  0,
			ParentStation: "A28",
		},
		// Penn Station - 7th Ave (1 2 3)
		"128": {
			StopID:       "128",
			StopName:     "34 St-Penn Station",
			StopLat:      40.750373,
			StopLon:      -73.991057,
			LocationType: 1,
		},
		"128S": {
			StopID:        "128S",
			StopName:      "34 St-Penn Station (Downtown)",
			StopLat:       40.750350,
			StopLon:       -73.991040,
			LocationType:  0,
			ParentStation: "128",
		},
		// Grand Central - 4/5/6
		"631": {
			StopID:       "631",
			StopName:     "Grand Central-42 St",
			StopLat:      40.751776,
			StopLon:      -73.976848,
			LocationType: 1,
		},
		"631N": {
			StopID:        "631N",
			StopName:      "Grand Central-42 St (Northbound)",
			StopLat:       40.751780,
			StopLon:       -73.976850,
			LocationType:  0,
			ParentStation: "631",
		},
		// Grand Central - 7
		"723": {
			StopID:       "723",
			StopName:     "Grand Central-42 St",
			StopLat:      40.751431,
			StopLon:      -73.976041,
			LocationType: 1,
		},
		"723S": {
			StopID:        "723S",
			StopName:      "Grand Central-42 St (Flushing)",
			StopLat:       40.751420,
			StopLon:       -73.976030,
			LocationType:  0,
			ParentStation: "723",
		},
		// Atlantic Ave - Barclays Ctr
		"235": {
			StopID:       "235",
			StopName:     "Atlantic Av-Barclays Ctr",
			StopLat:      40.684411,
			StopLon:      -73.977821,
			LocationType: 1,
		},
		"235N": {
			StopID:        "235N",
			StopName:      "Atlantic Av-Barclays Ctr (Northbound)",
			StopLat:       40.684420,
			StopLon:       -73.977830,
			LocationType:  0,
			ParentStation: "235",
		},
	}

	complexes, resolutions := BuildComplexResolutionHierarchy(stops, nil, "subway", RegionalHubAnchors)

	if len(complexes) != 3 {
		t.Fatalf("Expected 3 regional hub complexes, got %d", len(complexes))
	}

	complexByID := make(map[int64]Complex)
	for _, c := range complexes {
		complexByID[c.ComplexID] = c
	}

	// 1. Verify Penn Station Complex (600001)
	penn, hasPenn := complexByID[600001]
	if !hasPenn {
		t.Fatalf("Missing Penn Station Complex (600001)")
	}
	if penn.IsHub != 1 {
		t.Errorf("Penn Station expected is_hub=1, got %d", penn.IsHub)
	}

	// 2. Verify Grand Central Complex (600002)
	gcm, hasGCM := complexByID[600002]
	if !hasGCM {
		t.Fatalf("Missing Grand Central Complex (600002)")
	}
	if gcm.IsHub != 1 {
		t.Errorf("Grand Central expected is_hub=1, got %d", gcm.IsHub)
	}

	// 3. Verify Atlantic Ave Complex (600003)
	atl, hasAtl := complexByID[600003]
	if !hasAtl {
		t.Fatalf("Missing Atlantic Ave Complex (600003)")
	}
	if atl.IsHub != 1 {
		t.Errorf("Atlantic Ave expected is_hub=1, got %d", atl.IsHub)
	}

	// 4. Verify Resolution Mapping for Child Platforms
	resByChild := make(map[string]StopResolution)
	for _, r := range resolutions {
		resByChild[r.ChildStopID] = r
	}

	// Both A28 and 128 platforms must resolve to Penn Station Complex 600001
	if r, ok := resByChild["A28N"]; !ok || r.ComplexID != 600001 {
		t.Errorf("Expected A28N to map to Complex 600001, got %+v", r)
	} else if r.DirectionID == nil || *r.DirectionID != 0 {
		t.Errorf("Expected A28N direction_id = 0, got %v", r.DirectionID)
	}

	if r, ok := resByChild["128S"]; !ok || r.ComplexID != 600001 {
		t.Errorf("Expected 128S to map to Complex 600001, got %+v", r)
	} else if r.DirectionID == nil || *r.DirectionID != 1 {
		t.Errorf("Expected 128S direction_id = 1, got %v", r.DirectionID)
	}

	// Both 631 and 723 platforms must resolve to Grand Central Complex 600002
	if r, ok := resByChild["631N"]; !ok || r.ComplexID != 600002 {
		t.Errorf("Expected 631N to map to Complex 600002, got %+v", r)
	}
	if r, ok := resByChild["723S"]; !ok || r.ComplexID != 600002 {
		t.Errorf("Expected 723S to map to Complex 600002, got %+v", r)
	}
}

func TestBuildComplexResolutionHierarchy_MTAComplexes(t *testing.T) {
	// Union Square: 14 St-Union Sq on Lexington (635), Broadway (R20), and Canarsie (L03)
	stops := map[string]Stop{
		"635": {StopID: "635", StopName: "14 St-Union Sq", StopLat: 40.734673, StopLon: -73.989951, LocationType: 1},
		"635N": {StopID: "635N", StopName: "14 St-Union Sq (Uptown)", StopLat: 40.734673, StopLon: -73.989951, LocationType: 0, ParentStation: "635"},
		"R20": {StopID: "R20", StopName: "14 St-Union Sq", StopLat: 40.735736, StopLon: -73.990568, LocationType: 1},
		"R20S": {StopID: "R20S", StopName: "14 St-Union Sq (Downtown)", StopLat: 40.735736, StopLon: -73.990568, LocationType: 0, ParentStation: "R20"},
		"L03": {StopID: "L03", StopName: "14 St-Union Sq", StopLat: 40.734789, StopLon: -73.990730, LocationType: 1},
		"L03N": {StopID: "L03N", StopName: "14 St-Union Sq (8 Av)", StopLat: 40.734789, StopLon: -73.990730, LocationType: 0, ParentStation: "L03"},
	}

	mtaLookup := map[string]int64{
		"635": 602,
		"R20": 602,
		"L03": 602,
	}

	complexes, resolutions := BuildComplexResolutionHierarchy(stops, mtaLookup, "subway", RegionalHubAnchors)

	if len(complexes) != 1 {
		t.Fatalf("Expected 1 unified Union Sq complex, got %d", len(complexes))
	}
	if complexes[0].ComplexID != 602 {
		t.Errorf("Expected ComplexID 602, got %d", complexes[0].ComplexID)
	}

	for _, r := range resolutions {
		if r.ComplexID != 602 {
			t.Errorf("Stop %s expected complex 602, got %d", r.ChildStopID, r.ComplexID)
		}
		if r.FeedID != "subway" {
			t.Errorf("Stop %s expected feed_id 'subway', got %s", r.ChildStopID, r.FeedID)
		}
	}
}
