package raptor

import (
	"math"
	"sort"
)

// SlotsPerWeek is 7 days * 24 hours = 168 hourly slots
const SlotsPerWeek = 168

// SlotIndex computes the 1D index into the StochasticWeights array for a given route, day of week, and hour
func SlotIndex(routeIdx uint32, dow int, hour int) uint32 {
	if dow < 0 {
		dow = 0
	} else if dow > 6 {
		dow = 6
	}
	if hour < 0 {
		hour = 0
	} else if hour > 23 {
		hour = 23
	}
	return routeIdx*SlotsPerWeek + uint32(dow*24+hour)
}

// ComputeStochasticWeights evaluates expected wait times and variance penalties across all 168 weekly slots for all routes
func ComputeStochasticWeights(routes []Route, trips []Trip, stopTimes []StopTime, serviceDays []uint8) []StochasticWeight {
	numRoutes := len(routes)
	weights := make([]StochasticWeight, numRoutes*SlotsPerWeek)

	for rIdx, route := range routes {
		// Group trips by (dow, hour)
		// dow: 0=Mon, 1=Tue, 2=Wed, 3=Thu, 4=Fri, 5=Sat, 6=Sun
		hourlyDepartures := make([][][]uint32, 7)
		for d := 0; d < 7; d++ {
			hourlyDepartures[d] = make([][]uint32, 24)
		}

		tripStart := route.TripsOffset
		tripEnd := tripStart + uint32(route.TripCount)

		for tIdx := tripStart; tIdx < tripEnd; tIdx++ {
			trip := trips[tIdx]
			if trip.StopTimesCount == 0 {
				continue
			}

			// First stop departure time
			firstST := stopTimes[trip.StopTimesOffset]
			depSec := firstST.DepartureTimeSec

			// Hour of day (0..23, normalized for late night >86400)
			normSec := depSec % 86400
			hour := int(normSec / 3600)
			if hour > 23 {
				hour = 23
			}

			// Service days mask (7-bit uint8: bit 0=Mon, ..., bit 6=Sun)
			var daysMask uint8 = 0x7F // default: all days
			if int(trip.ServiceID) < len(serviceDays) && serviceDays[trip.ServiceID] > 0 {
				daysMask = serviceDays[trip.ServiceID]
			}

			for d := 0; d < 7; d++ {
				if (daysMask & (1 << d)) != 0 {
					hourlyDepartures[d][hour] = append(hourlyDepartures[d][hour], depSec)
				}
			}
		}

		// Calculate stochastic metrics for all 168 slots
		for d := 0; d < 7; d++ {
			for h := 0; h < 24; h++ {
				slotIdx := SlotIndex(uint32(rIdx), d, h)
				deps := hourlyDepartures[d][h]

				if len(deps) >= 2 {
					sort.Slice(deps, func(i, j int) bool { return deps[i] < deps[j] })
					var sumH float64
					var sumH2 float64
					nHeadways := float64(len(deps) - 1)

					for i := 0; i < len(deps)-1; i++ {
						hSec := float64(deps[i+1] - deps[i])
						sumH += hSec
						sumH2 += hSec * hSec
					}

					meanH := sumH / nHeadways
					if meanH < 30.0 {
						meanH = 30.0 // Minimum 30s headway clamp
					}

					varianceH := math.Max(0.0, (sumH2/nHeadways)-(meanH*meanH))
					stdDevH := math.Sqrt(varianceH)

					// Osuna and Newell formulation: E[wait] = h/2 + sigma^2 / (2h)
					expectedWait := (meanH / 2.0) + (varianceH / (2.0 * meanH))
					if expectedWait > 65535.0 {
						expectedWait = 65535.0
					}

					// Variance risk penalty: min(1000, floor((sigma / mean) * 500))
					cv := stdDevH / meanH
					penalty := math.Min(1000.0, math.Floor(cv*500.0))

					weights[slotIdx] = StochasticWeight{
						ExpectedWaitSec: uint16(math.Round(expectedWait)),
						VariancePenalty: uint16(penalty),
					}
				} else if len(deps) == 1 {
					// Single trip in hour: expected wait ~ 30 minutes (1800s), moderate penalty
					weights[slotIdx] = StochasticWeight{
						ExpectedWaitSec: 1800,
						VariancePenalty: 250,
					}
				} else {
					// Zero trips in hour: sparse service, maximum wait (3600s), max risk penalty
					weights[slotIdx] = StochasticWeight{
						ExpectedWaitSec: 3600,
						VariancePenalty: 1000,
					}
				}
			}
		}
	}

	return weights
}
