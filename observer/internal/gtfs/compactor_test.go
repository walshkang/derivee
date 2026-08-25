package gtfs

import (
	"testing"
	"time"
)

func TestCalendarResolver_14DayBitmask(t *testing.T) {
	// Anchor date: Monday, August 24, 2026
	anchor := time.Date(2026, 8, 24, 0, 0, 0, 0, time.UTC)

	calendars := map[string]Calendar{
		"weekday_service": {
			ServiceID: "weekday_service",
			Monday:    true,
			Tuesday:   true,
			Wednesday: true,
			Thursday:  true,
			Friday:    true,
			Saturday:  false,
			Sunday:    false,
			StartDate: "20260101",
			EndDate:   "20261231",
		},
		"weekend_service": {
			ServiceID: "weekend_service",
			Monday:    false,
			Tuesday:   false,
			Wednesday: false,
			Thursday:  false,
			Friday:    false,
			Saturday:  true,
			Sunday:    true,
			StartDate: "20260101",
			EndDate:   "20261231",
		},
	}

	calendarDates := map[string][]CalendarDate{
		"weekday_service": {
			// Holiday exception: Remove service on Wednesday Aug 26 (k=9)
			{ServiceID: "weekday_service", Date: "20260826", ExceptionType: 2},
			// Special add on Sunday Aug 30 (k=13)
			{ServiceID: "weekday_service", Date: "20260830", ExceptionType: 1},
		},
	}

	resolver := NewCalendarResolver(anchor, calendars, calendarDates)

	// Test Weekday Service Mask:
	// Window: [Aug 17 (Mon, k=0) .. Aug 30 (Sun, k=13)]
	// k=0: Aug 17 Mon -> 1
	// k=1: Aug 18 Tue -> 1
	// k=2: Aug 19 Wed -> 1
	// k=3: Aug 20 Thu -> 1
	// k=4: Aug 21 Fri -> 1
	// k=5: Aug 22 Sat -> 0
	// k=6: Aug 23 Sun -> 0
	// k=7: Aug 24 Mon (Anchor) -> 1 (Bit 7)
	// k=8: Aug 25 Tue -> 1
	// k=9: Aug 26 Wed -> 0 (Exception removed)
	// k=10: Aug 27 Thu -> 1
	// k=11: Aug 28 Fri -> 1
	// k=12: Aug 29 Sat -> 0
	// k=13: Aug 30 Sun -> 1 (Exception added)
	mask := resolver.ComputeServiceMask("weekday_service")

	// Expected bit 7 (Anchor) must be 1
	if (mask & (1 << 7)) == 0 {
		t.Errorf("Expected bit 7 (Anchor Date) to be 1, got mask %016b", mask)
	}

	// Bit 9 (Aug 26) must be 0 (exception removed)
	if (mask & (1 << 9)) != 0 {
		t.Errorf("Expected bit 9 (Aug 26 Exception Removed) to be 0, got mask %016b", mask)
	}

	// Bit 13 (Aug 30) must be 1 (exception added)
	if (mask & (1 << 13)) == 0 {
		t.Errorf("Expected bit 13 (Aug 30 Exception Added) to be 1, got mask %016b", mask)
	}

	// Bit 5 (Aug 22 Sat) must be 0
	if (mask & (1 << 5)) != 0 {
		t.Errorf("Expected bit 5 (Saturday) to be 0, got mask %016b", mask)
	}

	// Test Baseline Days of Week:
	// Mon..Fri = bits 1,2,3,4,5 = 0b00111110 = 62
	baseline := resolver.ComputeBaselineDaysOfWeek("weekday_service")
	expectedBaseline := uint8(0b00111110)
	if baseline != expectedBaseline {
		t.Errorf("Expected baseline %08b, got %08b", expectedBaseline, baseline)
	}

	// Test Weekend Baseline:
	// Sun (bit 0) | Sat (bit 6) = 0b01000001 = 65
	weekendBaseline := resolver.ComputeBaselineDaysOfWeek("weekend_service")
	expectedWeekend := uint8(0b01000001)
	if weekendBaseline != expectedWeekend {
		t.Errorf("Expected weekend baseline %08b, got %08b", expectedWeekend, weekendBaseline)
	}
}

func TestLinearInterpolation(t *testing.T) {
	stopTimes := []StopTime{
		{StopID: "S1", StopSequence: 1, ArrivalTimeSec: 3600, DepartureTimeSec: 3600, ShapeDistTraveled: 0.0},
		{StopID: "S2", StopSequence: 2, ArrivalTimeSec: -1, DepartureTimeSec: -1, ShapeDistTraveled: 500.0},
		{StopID: "S3", StopSequence: 3, ArrivalTimeSec: -1, DepartureTimeSec: -1, ShapeDistTraveled: 1500.0},
		{StopID: "S4", StopSequence: 4, ArrivalTimeSec: 4200, DepartureTimeSec: 4200, ShapeDistTraveled: 2000.0},
	}

	interpolated := InterpolateTripStopTimes(stopTimes)

	if len(interpolated) != 4 {
		t.Fatalf("Expected 4 stop times, got %d", len(interpolated))
	}

	// S1: 3600, S4: 4200 (Delta: 600s over 2000m = 0.3s/m)
	// S2: dist=500m -> 3600 + 500*0.3 = 3750
	// S3: dist=1500m -> 3600 + 1500*0.3 = 4050
	if interpolated[1].DepartureTimeSec != 3750 {
		t.Errorf("Expected S2 departure 3750, got %d", interpolated[1].DepartureTimeSec)
	}
	if interpolated[2].DepartureTimeSec != 4050 {
		t.Errorf("Expected S3 departure 4050, got %d", interpolated[2].DepartureTimeSec)
	}
}

func TestFrequencyExpansion(t *testing.T) {
	trip := Trip{
		TripID:       "T_FREQ",
		RouteID:      "R1",
		ServiceID:    "S1",
		TripHeadsign: "Uptown",
		DirectionID:  0,
	}

	baseStopTimes := []StopTime{
		{StopID: "S1", StopSequence: 1, DepartureTimeSec: 0},
		{StopID: "S2", StopSequence: 2, DepartureTimeSec: 600},
	}

	frequencies := []Frequency{
		{
			TripID:       "T_FREQ",
			StartTimeSec: 7 * 3600,  // 07:00
			EndTimeSec:   8 * 3600,  // 08:00
			HeadwaySecs:  15 * 60,   // 15 min (900s)
			ExactTimes:   0,
		},
	}

	instances := ExpandFrequencyTrips(trip, baseStopTimes, frequencies)

	// 07:00, 07:15, 07:30, 07:45 -> 4 instances
	if len(instances) != 4 {
		t.Fatalf("Expected 4 instances from frequency expansion, got %d", len(instances))
	}

	if instances[0].StopTimes[0].DepartureTimeSec != 7*3600 {
		t.Errorf("Expected first instance at 07:00 (25200s), got %d", instances[0].StopTimes[0].DepartureTimeSec)
	}
	if instances[3].StopTimes[0].DepartureTimeSec != 7*3600+45*60 {
		t.Errorf("Expected last instance at 07:45 (27900s), got %d", instances[3].StopTimes[0].DepartureTimeSec)
	}
}

func TestCompactDataset_OvernightAndPatterns(t *testing.T) {
	anchor := time.Date(2026, 8, 24, 0, 0, 0, 0, time.UTC) // Monday
	ds := NewDataset(anchor)

	ds.Calendars["weekday"] = Calendar{
		ServiceID: "weekday",
		Monday:    true,
		Tuesday:   true,
		Wednesday: true,
		Thursday:  true,
		Friday:    true,
		StartDate: "20260101",
		EndDate:   "20261231",
	}

	// Trip 1: Regular day departures at 08:04, 08:16, 08:28, 08:40, 08:52
	for i, min := range []int{4, 16, 28, 40, 52} {
		tripID := "T_DAY_" + string(rune('A'+i))
		ds.Trips[tripID] = Trip{
			TripID:       tripID,
			RouteID:      "L",
			ServiceID:    "weekday",
			TripHeadsign: "8 Av",
			DirectionID:  0,
		}
		ds.StopTimes[tripID] = []StopTime{
			{TripID: tripID, StopID: "L01", StopSequence: 1, DepartureTimeSec: 8*3600 + min*60},
		}
	}

	// Trip 2: Overnight departure at 24:15 (00:15 of next day)
	ds.Trips["T_NIGHT"] = Trip{
		TripID:       "T_NIGHT",
		RouteID:      "L",
		ServiceID:    "weekday",
		TripHeadsign: "8 Av",
		DirectionID:  0,
	}
	ds.StopTimes["T_NIGHT"] = []StopTime{
		{TripID: "T_NIGHT", StopID: "L01", StopSequence: 1, DepartureTimeSec: 24*3600 + 15*60},
	}

	patterns := CompactDataset(ds)

	var hour8Pattern, hour0Pattern *ScheduledHourlyPattern
	for i := range patterns {
		if patterns[i].HourOfDay == 8 {
			hour8Pattern = &patterns[i]
		}
		if patterns[i].HourOfDay == 0 {
			hour0Pattern = &patterns[i]
		}
	}

	if hour8Pattern == nil {
		t.Fatalf("Expected pattern for Hour 8")
	}
	if hour8Pattern.MinuteOffsets != "04,16,28,40,52" {
		t.Errorf("Expected minute offsets '04,16,28,40,52', got '%s'", hour8Pattern.MinuteOffsets)
	}

	if hour0Pattern == nil {
		t.Fatalf("Expected pattern for Hour 0 (from 24:15 overnight trip)")
	}
	if hour0Pattern.MinuteOffsets != "15" {
		t.Errorf("Expected overnight minute offset '15', got '%s'", hour0Pattern.MinuteOffsets)
	}
}
