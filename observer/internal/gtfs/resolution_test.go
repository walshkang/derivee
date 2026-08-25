package gtfs

import (
	"testing"
)

func TestBuildStopResolutionClosure(t *testing.T) {
	stops := map[string]Stop{
		// Parent Station
		"P_TIMES_SQ": {
			StopID:             "P_TIMES_SQ",
			StopName:           "Times Sq - 42 St",
			StopLat:            40.7552,
			StopLon:            -73.9870,
			LocationType:       1,
			PlatformCode:       "",
			WheelchairBoarding: 1,
		},
		// Child Platform 1 (Northbound)
		"127N": {
			StopID:             "127N",
			StopName:           "Times Sq - 42 St (Uptown)",
			StopLat:            40.7553,
			StopLon:            -73.9871,
			LocationType:       0,
			ParentStation:      "P_TIMES_SQ",
			PlatformCode:       "1",
			WheelchairBoarding: 1,
		},
		// Child Platform 2 (Southbound)
		"127S": {
			StopID:             "127S",
			StopName:           "Times Sq - 42 St (Downtown)",
			StopLat:            40.7551,
			StopLon:            -73.9869,
			LocationType:       0,
			ParentStation:      "P_TIMES_SQ",
			PlatformCode:       "2",
			WheelchairBoarding: 1,
		},
		// Standalone Street Bus Stop (No Parent)
		"B_BEDFORD_N7": {
			StopID:             "B_BEDFORD_N7",
			StopName:           "Bedford Av / N 7 St",
			StopLat:            40.7180,
			StopLon:            -73.9560,
			LocationType:       0,
			ParentStation:      "",
			PlatformCode:       "",
			WheelchairBoarding: 0,
		},
	}

	resolutions := BuildStopResolutionClosure(stops)

	resMap := make(map[string]StopResolution)
	for _, r := range resolutions {
		key := r.ParentStopID + "->" + r.ChildStopID
		resMap[key] = r
	}

	// Verify Rule 1: Parent -> Child Platform (is_parent = 0)
	r1N, ok1N := resMap["P_TIMES_SQ->127N"]
	if !ok1N || r1N.IsParent != 0 || r1N.PlatformCode != "1" {
		t.Errorf("Rule 1 failed for P_TIMES_SQ->127N: %+v", r1N)
	}

	r1S, ok1S := resMap["P_TIMES_SQ->127S"]
	if !ok1S || r1S.IsParent != 0 || r1S.PlatformCode != "2" {
		t.Errorf("Rule 1 failed for P_TIMES_SQ->127S: %+v", r1S)
	}

	// Verify Rule 2: Parent -> Parent (Self-referential, is_parent = 1)
	r2, ok2 := resMap["P_TIMES_SQ->P_TIMES_SQ"]
	if !ok2 || r2.IsParent != 1 {
		t.Errorf("Rule 2 failed for P_TIMES_SQ->P_TIMES_SQ: %+v", r2)
	}

	// Verify Rule 3: Child Platform -> Parent (Reverse lookup, is_parent = 1)
	r3N, ok3N := resMap["127N->P_TIMES_SQ"]
	if !ok3N || r3N.IsParent != 1 {
		t.Errorf("Rule 3 failed for 127N->P_TIMES_SQ: %+v", r3N)
	}

	// Verify Rule 4: Child Platform -> Child Platform (Self-referential, is_parent = 0)
	r4N, ok4N := resMap["127N->127N"]
	if !ok4N || r4N.IsParent != 0 || r4N.PlatformCode != "1" {
		t.Errorf("Rule 4 failed for 127N->127N: %+v", r4N)
	}

	// Verify Standalone Stop: B_BEDFORD_N7 -> B_BEDFORD_N7
	rStandalone, okSA := resMap["B_BEDFORD_N7->B_BEDFORD_N7"]
	if !okSA || rStandalone.IsParent != 0 {
		t.Errorf("Standalone resolution failed for B_BEDFORD_N7: %+v", rStandalone)
	}
}
