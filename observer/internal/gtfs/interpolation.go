package gtfs

import "math"

// InterpolateTripStopTimes ensures all stop times for a trip have valid ArrivalTimeSec and DepartureTimeSec
// using shape_dist_traveled or sequence-based linear interpolation.
func InterpolateTripStopTimes(stopTimes []StopTime) []StopTime {
	n := len(stopTimes)
	if n == 0 {
		return stopTimes
	}

	result := make([]StopTime, n)
	copy(result, stopTimes)

	// Step 1: Normalize intra-stop times (if arrival is present but departure is missing or vice versa)
	for i := 0; i < n; i++ {
		if result[i].ArrivalTimeSec >= 0 && result[i].DepartureTimeSec < 0 {
			result[i].DepartureTimeSec = result[i].ArrivalTimeSec
		} else if result[i].DepartureTimeSec >= 0 && result[i].ArrivalTimeSec < 0 {
			result[i].ArrivalTimeSec = result[i].DepartureTimeSec
		}
	}

	// Step 2: Find indices of stops with known times
	var knownIndices []int
	for i := 0; i < n; i++ {
		if result[i].DepartureTimeSec >= 0 {
			knownIndices = append(knownIndices, i)
		}
	}

	if len(knownIndices) == 0 {
		// No times known at all - cannot interpolate
		return result
	}

	// If only 1 stop time is known, fill all with that time
	if len(knownIndices) == 1 {
		t := result[knownIndices[0]].DepartureTimeSec
		for i := 0; i < n; i++ {
			result[i].ArrivalTimeSec = t
			result[i].DepartureTimeSec = t
		}
		return result
	}

	// Step 3: Interpolate intermediate segments between known indices
	for k := 0; k < len(knownIndices)-1; k++ {
		idxA := knownIndices[k]
		idxB := knownIndices[k+1]

		if idxB-idxA <= 1 {
			continue // Contiguous, no intermediate stops
		}

		tA := float64(result[idxA].DepartureTimeSec)
		tB := float64(result[idxB].ArrivalTimeSec)
		dA := result[idxA].ShapeDistTraveled
		dB := result[idxB].ShapeDistTraveled

		useDistance := (dB > dA) && (dA >= 0)

		for i := idxA + 1; i < idxB; i++ {
			var fraction float64
			if useDistance && result[i].ShapeDistTraveled >= dA {
				fraction = (result[i].ShapeDistTraveled - dA) / (dB - dA)
			} else {
				fraction = float64(i-idxA) / float64(idxB-idxA)
			}

			// Clamp fraction
			if fraction < 0 {
				fraction = 0
			} else if fraction > 1 {
				fraction = 1
			}

			interpolatedTime := int(math.Round(tA + fraction*(tB-tA)))
			result[i].ArrivalTimeSec = interpolatedTime
			result[i].DepartureTimeSec = interpolatedTime
		}
	}

	// Step 4: Handle leading unknown stops (before first known index)
	firstKnown := knownIndices[0]
	if firstKnown > 0 {
		secondKnown := knownIndices[1]
		timeDeltaPerStop := float64(result[secondKnown].ArrivalTimeSec-result[firstKnown].DepartureTimeSec) / float64(secondKnown-firstKnown)
		for i := firstKnown - 1; i >= 0; i-- {
			projected := int(math.Round(float64(result[firstKnown].DepartureTimeSec) - float64(firstKnown-i)*timeDeltaPerStop))
			if projected < 0 {
				projected = 0
			}
			result[i].ArrivalTimeSec = projected
			result[i].DepartureTimeSec = projected
		}
	}

	// Step 5: Handle trailing unknown stops (after last known index)
	lastKnown := knownIndices[len(knownIndices)-1]
	if lastKnown < n-1 {
		prevKnown := knownIndices[len(knownIndices)-2]
		timeDeltaPerStop := float64(result[lastKnown].ArrivalTimeSec-result[prevKnown].DepartureTimeSec) / float64(lastKnown-prevKnown)
		for i := lastKnown + 1; i < n; i++ {
			projected := int(math.Round(float64(result[lastKnown].DepartureTimeSec) + float64(i-lastKnown)*timeDeltaPerStop))
			result[i].ArrivalTimeSec = projected
			result[i].DepartureTimeSec = projected
		}
	}

	return result
}
