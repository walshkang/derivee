package gtfs

import (
	"testing"
	"time"
)

func TestComputeRouteDirections(t *testing.T) {
	ds := NewDataset(time.Now())

	ds.Routes["S51"] = Route{
		RouteID:        "S51",
		RouteShortName: "S51",
		RouteLongName:  "Midland Beach - St George Ferry",
		RouteType:      3,
	}

	ds.Stops["ST_GEORGE"] = Stop{
		StopID:   "ST_GEORGE",
		StopName: "St George Ferry Terminal",
	}
	ds.Stops["MIDLAND_BEACH"] = Stop{
		StopID:   "MIDLAND_BEACH",
		StopName: "Midland Beach",
	}
	ds.Stops["GRANT_CITY"] = Stop{
		StopID:   "GRANT_CITY",
		StopName: "Grant City",
	}

	// S51 Direction 0: 3 trips to St George Ferry, 1 short turn
	ds.Trips["t1"] = Trip{TripID: "t1", RouteID: "S51", DirectionID: 0, TripHeadsign: "St George Ferry"}
	ds.StopTimes["t1"] = []StopTime{
		{TripID: "t1", StopID: "MIDLAND_BEACH", StopSequence: 1},
		{TripID: "t1", StopID: "ST_GEORGE", StopSequence: 20},
	}

	ds.Trips["t2"] = Trip{TripID: "t2", RouteID: "S51", DirectionID: 0, TripHeadsign: "St George Ferry"}
	ds.StopTimes["t2"] = []StopTime{
		{TripID: "t2", StopID: "MIDLAND_BEACH", StopSequence: 1},
		{TripID: "t2", StopID: "ST_GEORGE", StopSequence: 20},
	}

	ds.Trips["t3"] = Trip{TripID: "t3", RouteID: "S51", DirectionID: 0, TripHeadsign: "St George Ferry"}
	ds.StopTimes["t3"] = []StopTime{
		{TripID: "t3", StopID: "GRANT_CITY", StopSequence: 1},
		{TripID: "t3", StopID: "ST_GEORGE", StopSequence: 15},
	}

	// Short turn to intermediate stop
	ds.Trips["t4"] = Trip{TripID: "t4", RouteID: "S51", DirectionID: 0, TripHeadsign: "Grymes Hill"}
	ds.StopTimes["t4"] = []StopTime{
		{TripID: "t4", StopID: "MIDLAND_BEACH", StopSequence: 1},
		{TripID: "t4", StopID: "GRYMES_HILL", StopSequence: 10},
	}

	// S51 Direction 1: 2 trips to Midland Beach, 1 to Grant City
	ds.Trips["t5"] = Trip{TripID: "t5", RouteID: "S51", DirectionID: 1, TripHeadsign: "Midland Beach"}
	ds.StopTimes["t5"] = []StopTime{
		{TripID: "t5", StopID: "ST_GEORGE", StopSequence: 1},
		{TripID: "t5", StopID: "MIDLAND_BEACH", StopSequence: 20},
	}
	ds.Trips["t6"] = Trip{TripID: "t6", RouteID: "S51", DirectionID: 1, TripHeadsign: "Midland Beach"}
	ds.StopTimes["t6"] = []StopTime{
		{TripID: "t6", StopID: "ST_GEORGE", StopSequence: 1},
		{TripID: "t6", StopID: "MIDLAND_BEACH", StopSequence: 20},
	}
	ds.Trips["t7"] = Trip{TripID: "t7", RouteID: "S51", DirectionID: 1, TripHeadsign: "Grant City"}
	ds.StopTimes["t7"] = []StopTime{
		{TripID: "t7", StopID: "ST_GEORGE", StopSequence: 1},
		{TripID: "t7", StopID: "GRANT_CITY", StopSequence: 12},
	}

	routeDirs := ComputeRouteDirections(ds)

	if len(routeDirs) != 2 {
		t.Fatalf("Expected 2 route directions, got %d", len(routeDirs))
	}

	// Direction 0
	d0 := routeDirs[0]
	if d0.RouteID != "S51" || d0.DirectionID != 0 {
		t.Errorf("Unexpected d0 key: %+v", d0)
	}
	if d0.Headsign != "St George Ferry" {
		t.Errorf("Expected modal headsign 'St George Ferry', got '%s'", d0.Headsign)
	}
	if d0.TerminalStopID != "ST_GEORGE" {
		t.Errorf("Expected terminal stop 'ST_GEORGE', got '%s'", d0.TerminalStopID)
	}

	// Direction 1
	d1 := routeDirs[1]
	if d1.RouteID != "S51" || d1.DirectionID != 1 {
		t.Errorf("Unexpected d1 key: %+v", d1)
	}
	if d1.Headsign != "Midland Beach" {
		t.Errorf("Expected modal headsign 'Midland Beach', got '%s'", d1.Headsign)
	}
	if d1.TerminalStopID != "MIDLAND_BEACH" {
		t.Errorf("Expected terminal stop 'MIDLAND_BEACH', got '%s'", d1.TerminalStopID)
	}
}

func TestComputeRouteDirectionsEmptyHeadsignFallback(t *testing.T) {
	ds := NewDataset(time.Now())

	ds.Routes["1"] = Route{
		RouteID:        "1",
		RouteShortName: "1",
		RouteLongName:  "Broadway - 7 Avenue Local",
		RouteType:      1,
	}

	ds.Stops["101"] = Stop{
		StopID:   "101",
		StopName: "Van Cortlandt Park-242 St",
	}

	// Trip with blank headsign
	ds.Trips["t101"] = Trip{TripID: "t101", RouteID: "1", DirectionID: 0, TripHeadsign: ""}
	ds.StopTimes["t101"] = []StopTime{
		{TripID: "t101", StopID: "142", StopSequence: 1},
		{TripID: "t101", StopID: "101", StopSequence: 38},
	}

	routeDirs := ComputeRouteDirections(ds)
	if len(routeDirs) != 1 {
		t.Fatalf("Expected 1 route direction, got %d", len(routeDirs))
	}

	if routeDirs[0].Headsign != "Broadway - 7 Avenue Local" {
		t.Errorf("Expected fallback to route long name 'Broadway - 7 Avenue Local', got '%s'", routeDirs[0].Headsign)
	}
	if routeDirs[0].TerminalStopID != "101" {
		t.Errorf("Expected terminal stop '101', got '%s'", routeDirs[0].TerminalStopID)
	}
}
