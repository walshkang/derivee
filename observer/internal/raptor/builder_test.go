package raptor

import (
	"testing"
	"time"

	"observer/internal/gtfs"
)

func createMockGTFSDataset() *gtfs.Dataset {
	ds := gtfs.NewDataset(time.Date(2026, 8, 31, 0, 0, 0, 0, time.UTC))

	// Stops (including parent/child platforms)
	ds.Stops = map[string]gtfs.Stop{
		"STOP_A": {StopID: "STOP_A", StopName: "Station Alpha", StopLat: 40.7128, StopLon: -74.0060, ParentStation: "STATION_1"},
		"STOP_B": {StopID: "STOP_B", StopName: "Station Beta", StopLat: 40.7200, StopLon: -74.0000, ParentStation: "STATION_1"},
		"STOP_C": {StopID: "STOP_C", StopName: "Station Gamma", StopLat: 40.7300, StopLon: -73.9900},
		"STOP_D": {StopID: "STOP_D", StopName: "Station Delta", StopLat: 40.7400, StopLon: -73.9800},
	}

	// Routes
	ds.Routes = map[string]gtfs.Route{
		"ROUTE_1": {RouteID: "ROUTE_1", RouteShortName: "1", RouteType: 1},
		"ROUTE_2": {RouteID: "ROUTE_2", RouteShortName: "2", RouteType: 1},
	}

	// Calendars
	ds.Calendars = map[string]gtfs.Calendar{
		"SVC_ALL": {
			ServiceID: "SVC_ALL",
			Monday:    true, Tuesday: true, Wednesday: true, Thursday: true, Friday: true, Saturday: true, Sunday: true,
			StartDate: "20260101", EndDate: "20261231",
		},
	}

	// Trips (Route 1 has 2 trips A->C->D, Route 2 has 1 trip B->C)
	ds.Trips = map[string]gtfs.Trip{
		"TRIP_1_EARLY": {TripID: "TRIP_1_EARLY", RouteID: "ROUTE_1", ServiceID: "SVC_ALL", DirectionID: 0},
		"TRIP_1_LATE":  {TripID: "TRIP_1_LATE", RouteID: "ROUTE_1", ServiceID: "SVC_ALL", DirectionID: 0},
		"TRIP_2":       {TripID: "TRIP_2", RouteID: "ROUTE_2", ServiceID: "SVC_ALL", DirectionID: 0},
	}

	// Stop Times
	ds.StopTimes = map[string][]gtfs.StopTime{
		"TRIP_1_EARLY": {
			{TripID: "TRIP_1_EARLY", StopID: "STOP_A", StopSequence: 1, ArrivalTimeSec: 28800, DepartureTimeSec: 28800}, // 08:00
			{TripID: "TRIP_1_EARLY", StopID: "STOP_C", StopSequence: 2, ArrivalTimeSec: 29100, DepartureTimeSec: 29130}, // 08:05
			{TripID: "TRIP_1_EARLY", StopID: "STOP_D", StopSequence: 3, ArrivalTimeSec: 29400, DepartureTimeSec: 29400}, // 08:10
		},
		"TRIP_1_LATE": {
			{TripID: "TRIP_1_LATE", StopID: "STOP_A", StopSequence: 1, ArrivalTimeSec: 29400, DepartureTimeSec: 29400}, // 08:10 (10 min headway)
			{TripID: "TRIP_1_LATE", StopID: "STOP_C", StopSequence: 2, ArrivalTimeSec: 29700, DepartureTimeSec: 29730},
			{TripID: "TRIP_1_LATE", StopID: "STOP_D", StopSequence: 3, ArrivalTimeSec: 30000, DepartureTimeSec: 30000},
		},
		"TRIP_2": {
			{TripID: "TRIP_2", StopID: "STOP_B", StopSequence: 1, ArrivalTimeSec: 28900, DepartureTimeSec: 28900},
			{TripID: "TRIP_2", StopID: "STOP_C", StopSequence: 2, ArrivalTimeSec: 29200, DepartureTimeSec: 29230},
		},
	}

	return ds
}

func TestCompileTimetable(t *testing.T) {
	ds := createMockGTFSDataset()
	anchor := time.Date(2026, 8, 31, 0, 0, 0, 0, time.UTC)

	tt, err := CompileTimetable(ds, anchor)
	if err != nil {
		t.Fatalf("CompileTimetable failed: %v", err)
	}

	// 1. Verify Stops
	if len(tt.Stops) != 4 {
		t.Errorf("expected 4 stops, got %d", len(tt.Stops))
	}

	// 2. Verify Routes (2 distinct route patterns)
	if len(tt.Routes) != 2 {
		t.Fatalf("expected 2 route patterns, got %d", len(tt.Routes))
	}

	// Route 1 should have 2 trips, Route 2 should have 1 trip
	r0 := tt.Routes[0]
	if r0.TripCount != 2 {
		t.Errorf("expected Route 0 to have 2 trips, got %d", r0.TripCount)
	}
	if r0.StopCount != 3 {
		t.Errorf("expected Route 0 to have 3 stops, got %d", r0.StopCount)
	}

	// 3. Verify Trip Sorting (Trip 1 Early must come before Trip 1 Late)
	t0 := tt.Trips[r0.TripsOffset]
	t1 := tt.Trips[r0.TripsOffset+1]

	st0 := tt.StopTimes[t0.StopTimesOffset]
	st1 := tt.StopTimes[t1.StopTimesOffset]

	if st0.DepartureTimeSec >= st1.DepartureTimeSec {
		t.Errorf("expected trip 0 departure (%d) < trip 1 departure (%d)", st0.DepartureTimeSec, st1.DepartureTimeSec)
	}
	if st0.DepartureTimeSec != 28800 || st1.DepartureTimeSec != 29400 {
		t.Errorf("unexpected departure times: %d, %d", st0.DepartureTimeSec, st1.DepartureTimeSec)
	}

	// 4. Verify RouteStops Array
	rs := tt.RouteStops[r0.RouteStopsOffset : r0.RouteStopsOffset+uint32(r0.StopCount)]
	if len(rs) != 3 {
		t.Fatalf("expected 3 route stops, got %d", len(rs))
	}

	// 5. Verify Inverted Index StopRoutes
	stopAIdx := tt.StopIDToIndex["STOP_A"]
	stopA := tt.Stops[stopAIdx]
	if stopA.RouteCount == 0 {
		t.Errorf("expected STOP_A to have route references")
	}

	// STOP_C is visited by both Route 0 and Route 1
	stopCIdx := tt.StopIDToIndex["STOP_C"]
	stopC := tt.Stops[stopCIdx]
	if stopC.RouteCount != 2 {
		t.Errorf("expected STOP_C to have 2 serving routes, got %d", stopC.RouteCount)
	}

	// 6. Verify Parent Station Transfers (STOP_A and STOP_B share STATION_1)
	stopBIdx := tt.StopIDToIndex["STOP_B"]
	stopB := tt.Stops[stopBIdx]

	if stopA.TransferCount != 1 {
		t.Errorf("expected STOP_A to have 1 platform transfer to STOP_B, got %d", stopA.TransferCount)
	} else {
		tr := tt.Transfers[stopA.TransfersOffset]
		if tr.TargetStopID != stopBIdx {
			t.Errorf("expected STOP_A transfer target to be STOP_B (%d), got %d", stopBIdx, tr.TargetStopID)
		}
		if tr.DurationSec != 120 {
			t.Errorf("expected transfer duration 120s, got %d", tr.DurationSec)
		}
	}

	if stopB.TransferCount != 1 {
		t.Errorf("expected STOP_B to have 1 platform transfer to STOP_A, got %d", stopB.TransferCount)
	}

	// 7. Verify Stochastic Weights (168 slots per route)
	if len(tt.StochasticWeights) != len(tt.Routes)*168 {
		t.Fatalf("expected %d stochastic weights, got %d", len(tt.Routes)*168, len(tt.StochasticWeights))
	}

	// Slot for Route 0, Monday (d=0), 8 AM (h=8)
	slot0_8am := SlotIndex(0, 0, 8)
	sw := tt.StochasticWeights[slot0_8am]
	// Two departures in hour: 08:00 (28800) and 08:10 (29400) -> headway = 600s -> E[wait] = 300s (variance=0)
	if sw.ExpectedWaitSec != 300 {
		t.Errorf("expected ExpectedWaitSec ~300s, got %d", sw.ExpectedWaitSec)
	}
	if sw.VariancePenalty != 0 {
		t.Errorf("expected VariancePenalty 0 for uniform headways, got %d", sw.VariancePenalty)
	}
}
