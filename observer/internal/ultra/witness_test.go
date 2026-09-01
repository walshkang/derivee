package ultra

import (
	"testing"

	"observer/internal/raptor"
)

func TestWitnessEngineDominancePruning(t *testing.T) {
	// Synthetic timetable:
	// Route 0 connects Stop 0 -> Stop 1 in 3 minutes (180s)
	// Walking transfer candidate between Stop 0 and Stop 1 takes 10 minutes (600s)
	// The walking transfer candidate should be pruned by the transit witness!
	tt := &raptor.CompiledTimetable{
		Stops: []raptor.Stop{
			{RoutesOffset: 0, RouteCount: 1}, // Stop 0
			{RoutesOffset: 0, RouteCount: 1}, // Stop 1
			{RoutesOffset: 0, RouteCount: 0}, // Stop 2 (isolated)
		},
		Routes: []raptor.Route{
			{TripsOffset: 0, RouteStopsOffset: 0, TripCount: 1, StopCount: 2},
		},
		Trips: []raptor.Trip{
			{StopTimesOffset: 0, StopTimesCount: 2},
		},
		StopTimes: []raptor.StopTime{
			{DepartureTimeSec: 28800, ArrivalTimeSec: 28800, StopID: 0}, // 08:00
			{DepartureTimeSec: 28980, ArrivalTimeSec: 28980, StopID: 1}, // 08:03 (180s later)
		},
		StopRoutes: []uint32{0},
		RouteStops: []uint32{0, 1},
	}

	compactTT := BuildCompactTimetable(tt)
	witnessEngine := NewWitnessEngine(3)

	candidates := []TransferCandidate{
		{TargetStop: 1, Duration: 600, Flags: 0}, // Walk takes 600s (dominated by 180s transit)
		{TargetStop: 2, Duration: 300, Flags: 0}, // Stop 2 is not on transit line (not dominated)
	}

	surviving := witnessEngine.PruneShortcutsWithWitnesses(0, candidates, compactTT, tt)

	if len(surviving) != 1 {
		t.Fatalf("expected 1 surviving shortcut, got %d", len(surviving))
	}

	if surviving[0].TargetStop != 2 {
		t.Errorf("expected Stop 2 to survive, got Stop %d", surviving[0].TargetStop)
	}
}
