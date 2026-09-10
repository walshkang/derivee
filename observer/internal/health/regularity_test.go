package health

import (
	"math"
	"testing"
)

func TestAnalyzeCorridorRegularity_Validation(t *testing.T) {
	// Insufficient vehicles (< 2)
	_, err := AnalyzeCorridorRegularity("LINE_1", []ActiveVehicleInput{
		{VehicleID: "V1", CurvilinearOffsetM: 100, SpeedMetersPerSec: 12.0},
	}, 600.0, 12.0)
	if err == nil {
		t.Errorf("expected error for < 2 vehicles, got nil")
	}

	// Non-positive scheduled headway
	_, err = AnalyzeCorridorRegularity("LINE_1", []ActiveVehicleInput{
		{VehicleID: "V1", CurvilinearOffsetM: 100, SpeedMetersPerSec: 12.0},
		{VehicleID: "V2", CurvilinearOffsetM: 200, SpeedMetersPerSec: 12.0},
	}, 0.0, 12.0)
	if err == nil {
		t.Errorf("expected error for schedHeadway <= 0, got nil")
	}
}

func TestAnalyzeCorridorRegularity_PerfectService(t *testing.T) {
	// 5 vehicles evenly spaced by 7200m at 12 m/s -> exactly 600s (10 min) headway.
	schedHeadway := 600.0
	speed := 12.0
	dist := schedHeadway * speed // 7200m

	vehicles := []ActiveVehicleInput{
		{VehicleID: "V1", CurvilinearOffsetM: 0 * dist, SpeedMetersPerSec: speed},
		{VehicleID: "V2", CurvilinearOffsetM: 1 * dist, SpeedMetersPerSec: speed},
		{VehicleID: "V3", CurvilinearOffsetM: 2 * dist, SpeedMetersPerSec: speed},
		{VehicleID: "V4", CurvilinearOffsetM: 3 * dist, SpeedMetersPerSec: speed},
		{VehicleID: "V5", CurvilinearOffsetM: 4 * dist, SpeedMetersPerSec: speed},
	}

	res, err := AnalyzeCorridorRegularity("LINE_1", vehicles, schedHeadway, speed)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	if res.VehicleCount != 5 {
		t.Errorf("expected vehicle count 5, got %d", res.VehicleCount)
	}
	if math.Abs(res.MeanHeadwaySec-600.0) > 1e-6 {
		t.Errorf("expected mean headway 600.0, got %f", res.MeanHeadwaySec)
	}
	if math.Abs(res.HeadwayStdDevSec) > 1e-6 {
		t.Errorf("expected std dev 0.0, got %f", res.HeadwayStdDevSec)
	}
	if math.Abs(res.CoefficientOfVar) > 1e-6 {
		t.Errorf("expected CV 0.0, got %f", res.CoefficientOfVar)
	}
	if math.Abs(res.GiniCoefficient) > 1e-6 {
		t.Errorf("expected Gini 0.0, got %f", res.GiniCoefficient)
	}
	// Osuna-Newell wait: E[W] = (600 / 2) * (1 + 0) = 300s
	if math.Abs(res.ExpectedWaitTimeSec-300.0) > 1e-6 {
		t.Errorf("expected Osuna-Newell wait 300.0, got %f", res.ExpectedWaitTimeSec)
	}
	if res.BunchingEventCount != 0 {
		t.Errorf("expected 0 bunching events, got %d", res.BunchingEventCount)
	}
	if res.ServiceGapCount != 0 {
		t.Errorf("expected 0 service gaps, got %d", res.ServiceGapCount)
	}
	if res.CorridorHealthScore != 100.0 {
		t.Errorf("expected health score 100.0, got %f", res.CorridorHealthScore)
	}
	if res.Status != StatusGood {
		t.Errorf("expected status Good, got %s", res.Status)
	}
}

func TestAnalyzeCorridorRegularity_BunchedPair(t *testing.T) {
	// Sched headway = 600s. Bunching threshold = 0.25 * 600 = 150s.
	// V1 and V2 are separated by only 600m at 12 m/s -> 50s headway (bunched!).
	// V2 and V3 are separated by 14400m at 12 m/s -> 1200s (gap!).
	schedHeadway := 600.0
	speed := 12.0

	vehicles := []ActiveVehicleInput{
		{VehicleID: "V1", CurvilinearOffsetM: 0, SpeedMetersPerSec: speed},
		{VehicleID: "V2", CurvilinearOffsetM: 600, SpeedMetersPerSec: speed},   // 50s from V1 -> BUNCHED
		{VehicleID: "V3", CurvilinearOffsetM: 15000, SpeedMetersPerSec: speed}, // 1200s from V2 -> GAP
	}

	res, err := AnalyzeCorridorRegularity("LINE_1", vehicles, schedHeadway, speed)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	if res.BunchingEventCount != 1 {
		t.Errorf("expected 1 bunching event, got %d", res.BunchingEventCount)
	}
	if res.ServiceGapCount != 1 {
		t.Errorf("expected 1 service gap, got %d", res.ServiceGapCount)
	}

	// Any active bunching MUST force status to Delayed per Research Doc 19 (§2)
	if res.Status != StatusDelayed {
		t.Errorf("expected status Delayed due to active bunching, got %s", res.Status)
	}

	// Classifications check
	if !res.Classifications[0].IsBunched {
		t.Errorf("expected V1 classification to be bunched")
	}
	if !res.Classifications[1].IsServiceGap {
		t.Errorf("expected V2 classification to be service gap")
	}
}

func TestAnalyzeCorridorRegularity_ServiceGapOnly(t *testing.T) {
	// Sched headway = 600s. Gap threshold = 1.75 * 600 = 1050s.
	// V1 -> V2: 600s (normal)
	// V2 -> V3: 1100s (gap!)
	// V3 -> V4: 600s (normal)
	schedHeadway := 600.0
	speed := 12.0

	vehicles := []ActiveVehicleInput{
		{VehicleID: "V1", CurvilinearOffsetM: 0, SpeedMetersPerSec: speed},
		{VehicleID: "V2", CurvilinearOffsetM: 7200, SpeedMetersPerSec: speed},  // 600s
		{VehicleID: "V3", CurvilinearOffsetM: 20400, SpeedMetersPerSec: speed}, // 1100s -> GAP
		{VehicleID: "V4", CurvilinearOffsetM: 27600, SpeedMetersPerSec: speed}, // 600s
	}

	res, err := AnalyzeCorridorRegularity("LINE_1", vehicles, schedHeadway, speed)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	if res.BunchingEventCount != 0 {
		t.Errorf("expected 0 bunching events, got %d", res.BunchingEventCount)
	}
	if res.ServiceGapCount != 1 {
		t.Errorf("expected 1 service gap, got %d", res.ServiceGapCount)
	}
	if res.Status != StatusGaps {
		t.Errorf("expected status Gaps, got %s", res.Status)
	}
}

func TestAnalyzeCorridorRegularity_DwellingVehicleFallback(t *testing.T) {
	// V1 is dwelling (speed = 0.5 m/s < 2.5 m/s threshold).
	// Nominal speed is 12.0 m/s.
	// Offset difference is 7200m -> Headway should evaluate using 12.0 m/s = 600s, NOT 7200 / 0.5 = 14400s.
	schedHeadway := 600.0
	nominalSpeed := 12.0

	vehicles := []ActiveVehicleInput{
		{VehicleID: "V1", CurvilinearOffsetM: 0, SpeedMetersPerSec: 0.5},
		{VehicleID: "V2", CurvilinearOffsetM: 7200, SpeedMetersPerSec: 12.0},
	}

	res, err := AnalyzeCorridorRegularity("LINE_1", vehicles, schedHeadway, nominalSpeed)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	if math.Abs(res.MeanHeadwaySec-600.0) > 1e-6 {
		t.Errorf("expected headway 600.0 using nominal speed fallback, got %f", res.MeanHeadwaySec)
	}
}

func TestAnalyzeCorridorRegularity_UnsortedVehicles(t *testing.T) {
	// Provide vehicles out of order; engine should sort ascending by CurvilinearOffsetM.
	schedHeadway := 600.0
	speed := 12.0

	vehicles := []ActiveVehicleInput{
		{VehicleID: "V3", CurvilinearOffsetM: 14400, SpeedMetersPerSec: speed},
		{VehicleID: "V1", CurvilinearOffsetM: 0, SpeedMetersPerSec: speed},
		{VehicleID: "V2", CurvilinearOffsetM: 7200, SpeedMetersPerSec: speed},
	}

	res, err := AnalyzeCorridorRegularity("LINE_1", vehicles, schedHeadway, speed)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	if res.Classifications[0].VehicleID != "V1" {
		t.Errorf("expected first classification to be V1, got %s", res.Classifications[0].VehicleID)
	}
	if res.Classifications[1].VehicleID != "V2" {
		t.Errorf("expected second classification to be V2, got %s", res.Classifications[1].VehicleID)
	}
	if res.Classifications[2].VehicleID != "V3" {
		t.Errorf("expected third classification to be V3, got %s", res.Classifications[2].VehicleID)
	}
}

func BenchmarkAnalyzeCorridorRegularity(b *testing.B) {
	benchmarks := []struct {
		name         string
		vehicleCount int
	}{
		{"10_Vehicles", 10},
		{"50_Vehicles", 50},
		{"200_Vehicles", 200},
	}

	for _, bm := range benchmarks {
		b.Run(bm.name, func(b *testing.B) {
			schedHeadway := 600.0
			speed := 12.0
			vehicles := make([]ActiveVehicleInput, bm.vehicleCount)
			for i := 0; i < bm.vehicleCount; i++ {
				vehicles[i] = ActiveVehicleInput{
					VehicleID:          "VEH",
					CurvilinearOffsetM: float64(i) * 7200.0,
					SpeedMetersPerSec:  speed,
				}
			}

			b.ResetTimer()
			for i := 0; i < b.N; i++ {
				_, _ = AnalyzeCorridorRegularity("ROUTE_1", vehicles, schedHeadway, speed)
			}
		})
	}
}
