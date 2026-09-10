package health

import (
	"errors"
	"math"
	"sort"
)

// AnalyzeCorridorRegularity evaluates real-time vehicle spacing along a corridor
// using a single-pass Welford algorithm, TCQSM bunching and service gap detection,
// Osuna-Newell expected passenger wait time, and composite health scoring per Research Doc 19.
func AnalyzeCorridorRegularity(
	routeID string,
	vehicles []ActiveVehicleInput,
	schedHeadwaySec float64,
	nominalSpeedMPS float64,
) (*CorridorHealthResult, error) {
	n := len(vehicles)
	if n < 2 {
		return nil, errors.New("insufficient vehicles active on corridor to assess headway regularity")
	}
	if schedHeadwaySec <= 0 {
		return nil, errors.New("scheduled headway must be strictly positive")
	}
	if nominalSpeedMPS <= 0 {
		nominalSpeedMPS = DefaultNominalSpeedMPS
	}

	// 1. Sort vehicles ascending by curvilinear distance offset from route origin.
	sortedVehicles := make([]ActiveVehicleInput, n)
	copy(sortedVehicles, vehicles)
	sort.Slice(sortedVehicles, func(i, j int) bool {
		return sortedVehicles[i].CurvilinearOffsetM < sortedVehicles[j].CurvilinearOffsetM
	})

	headwayCount := n - 1
	temporalHeadways := make([]float64, headwayCount)
	classifications := make([]VehicleClassification, n)

	welford := NewWelfordAccumulator()
	bunchCount := 0
	gapCount := 0

	bunchingThreshold := BunchingThresholdFactor * schedHeadwaySec
	gapThreshold := ServiceGapThresholdFactor * schedHeadwaySec

	// 2. Evaluate pairwise headways between follower i and leader i+1.
	for i := 0; i < headwayCount; i++ {
		follower := sortedVehicles[i]
		leader := sortedVehicles[i+1]

		deltaD := leader.CurvilinearOffsetM - follower.CurvilinearOffsetM
		if deltaD < 0 {
			deltaD = 0
		}

		effectiveSpeed := follower.SpeedMetersPerSec
		if effectiveSpeed < StoppedSpeedThresholdMPS {
			effectiveSpeed = nominalSpeedMPS
		}

		tHeadway := deltaD / effectiveSpeed
		temporalHeadways[i] = tHeadway
		welford.Update(tHeadway)

		isBunched := tHeadway < bunchingThreshold
		isGap := tHeadway > gapThreshold

		if isBunched {
			bunchCount++
		}
		if isGap {
			gapCount++
		}

		compressionRatio := 0.0
		if schedHeadwaySec > 0 {
			compressionRatio = tHeadway / schedHeadwaySec
		}

		classifications[i] = VehicleClassification{
			VehicleID:        follower.VehicleID,
			SpatialHeadwayM:  deltaD,
			TemporalHeadway:  tHeadway,
			IsBunched:        isBunched,
			IsServiceGap:     isGap,
			CompressionRatio: compressionRatio,
		}
	}

	// 3. Leading vehicle classification (heads the corridor platoon).
	classifications[n-1] = VehicleClassification{
		VehicleID:        sortedVehicles[n-1].VehicleID,
		SpatialHeadwayM:  0,
		TemporalHeadway:  schedHeadwaySec,
		IsBunched:        false,
		IsServiceGap:     false,
		CompressionRatio: 1.0,
	}

	// 4. Statistical dispersion from Welford accumulator.
	meanHeadway := welford.Mean()
	stdDev := welford.StdDev()
	cv := welford.CV()

	// 5. Osuna-Newell expected passenger wait time: E[W] = (mu_h / 2) * (1 + CV_h^2).
	expectedWait := (meanHeadway / 2.0) * (1.0 + (cv * cv))

	// 6. Gini coefficient across temporal headways with finite-sample correction.
	sortedHeadways := make([]float64, headwayCount)
	copy(sortedHeadways, temporalHeadways)
	sort.Float64s(sortedHeadways)

	fHeadwayCount := float64(headwayCount)
	sumHeadway := meanHeadway * fHeadwayCount

	var cumulativeRankSum float64
	for idx, val := range sortedHeadways {
		rank := float64(idx + 1)
		cumulativeRankSum += rank * val
	}

	gini := 0.0
	if sumHeadway > 0 && fHeadwayCount > 1 {
		rawGini := (2.0*cumulativeRankSum)/(fHeadwayCount*sumHeadway) - (fHeadwayCount+1.0)/fHeadwayCount
		gini = rawGini * (fHeadwayCount / (fHeadwayCount - 1.0))
		if gini < 0 {
			gini = 0
		}
	}

	// 7. Composite Corridor Health Score:
	// S = max(0, min(100, 100 * exp(-kappa * CV_h) - (w_b * N_bunch + w_g * N_gap)))
	baseScore := 100.0 * math.Exp(-KappaMetricParam*cv)
	totalPenalties := (float64(bunchCount) * WeightBunchPenalty) + (float64(gapCount) * WeightGapPenalty)
	score := baseScore - totalPenalties

	if score < 0.0 {
		score = 0.0
	} else if score > 100.0 {
		score = 100.0
	}

	// 8. Tri-tier status resolution per Research Doc 19 (§2):
	// - Good: S >= 75.0 and N_bunch == 0
	// - Gaps: (50.0 <= S < 75.0 and N_bunch == 0) or (N_gap > 0 and N_bunch == 0)
	// - Delayed: S < 50.0 or N_bunch > 0
	var status CorridorStatus
	if score >= 75.0 && bunchCount == 0 {
		status = StatusGood
	} else if (score >= 50.0 && bunchCount == 0) || (gapCount > 0 && bunchCount == 0) {
		status = StatusGaps
	} else {
		status = StatusDelayed
	}

	return &CorridorHealthResult{
		RouteID:             routeID,
		VehicleCount:        n,
		ScheduledHeadwaySec: schedHeadwaySec,
		MeanHeadwaySec:      meanHeadway,
		HeadwayStdDevSec:    stdDev,
		CoefficientOfVar:    cv,
		GiniCoefficient:     gini,
		ExpectedWaitTimeSec: expectedWait,
		BunchingEventCount:  bunchCount,
		ServiceGapCount:     gapCount,
		CorridorHealthScore: math.Round(score*10.0) / 10.0,
		Status:              status,
		Classifications:     classifications,
	}, nil
}
