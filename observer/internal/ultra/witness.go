package ultra

import (
	"observer/internal/raptor"
)

// WitnessEngine executes localized Profile-RAPTOR witness searches to prune transit-dominated walking shortcuts
type WitnessEngine struct {
	earliestArrival []uint32 // Scratchpad sized to |S|
	markedStops     []uint32 // Scratchpad for active round stops
	numStops        uint32
}

// NewWitnessEngine initializes the witness evaluation engine
func NewWitnessEngine(numStops uint32) *WitnessEngine {
	return &WitnessEngine{
		earliestArrival: make([]uint32, numStops),
		markedStops:     make([]uint32, 0, 128),
		numStops:        numStops,
	}
}

// BuildCompactTimetable converts a compiled RAPTOR timetable into a lightweight format for witness pruning
func BuildCompactTimetable(tt *raptor.CompiledTimetable) *CompactTimetable {
	numStops := uint32(len(tt.Stops))
	stopRoutesIndptr := make([]uint32, numStops+1)
	stopRoutes := make([]RouteStopIndex, len(tt.StopRoutes))

	for s := uint32(0); s < numStops; s++ {
		stop := tt.Stops[s]
		stopRoutesIndptr[s] = stop.RoutesOffset
	}
	stopRoutesIndptr[numStops] = uint32(len(tt.StopRoutes))

	for i, routeID := range tt.StopRoutes {
		stopRoutes[i] = RouteStopIndex{
			RouteID:   routeID,
			StopIndex: 0,
		}
	}

	// Trip events
	tripEvents := make([]TripEvent, len(tt.StopTimes))
	for i, st := range tt.StopTimes {
		tripEvents[i] = TripEvent{
			DepTime: st.DepartureTimeSec,
			ArrTime: st.ArrivalTimeSec,
			TripID:  0,
		}
	}

	routeTripOffsets := make([]uint32, len(tt.Routes))
	routeTripCounts := make([]uint16, len(tt.Routes))
	for r, route := range tt.Routes {
		routeTripOffsets[r] = route.TripsOffset
		routeTripCounts[r] = route.TripCount
	}

	return &CompactTimetable{
		NumStops:         numStops,
		StopRoutesIndptr: stopRoutesIndptr,
		StopRoutes:       stopRoutes,
		TripEvents:       tripEvents,
		RouteTripOffsets: routeTripOffsets,
		RouteTripCounts:  routeTripCounts,
	}
}

// EvaluateWitnessDominance checks if any direct transit trip from u to v dominates the candidate walking transfer
// A candidate is dominated if a transit journey arrives faster across typical operating departures
func (we *WitnessEngine) EvaluateWitnessDominance(
	u uint32,
	v uint32,
	walkDurationSec uint16,
	tt *CompactTimetable,
	rawTT *raptor.CompiledTimetable,
) bool {
	if rawTT == nil || u >= we.numStops || v >= we.numStops {
		return false
	}

	uStop := rawTT.Stops[u]
	if uStop.RouteCount == 0 {
		return false
	}

	// Find common routes serving both stop u and stop v
	uRoutesStart := uStop.RoutesOffset
	uRoutesEnd := uRoutesStart + uint32(uStop.RouteCount)

	for rIdx := uRoutesStart; rIdx < uRoutesEnd && rIdx < uint32(len(rawTT.StopRoutes)); rIdx++ {
		routeID := rawTT.StopRoutes[rIdx]
		if routeID >= uint32(len(rawTT.Routes)) {
			continue
		}

		route := rawTT.Routes[routeID]
		stopsStart := route.RouteStopsOffset
		stopsEnd := stopsStart + uint32(route.StopCount)

		uSeq := int32(-1)
		vSeq := int32(-1)

		for seq := stopsStart; seq < stopsEnd && seq < uint32(len(rawTT.RouteStops)); seq++ {
			sID := rawTT.RouteStops[seq]
			if sID == u && uSeq == -1 {
				uSeq = int32(seq - stopsStart)
			} else if sID == v && uSeq != -1 {
				vSeq = int32(seq - stopsStart)
				break
			}
		}

		// Direct transit route connects u -> v in sequence
		if uSeq != -1 && vSeq != -1 && vSeq > uSeq {
			// Check trip durations on this route
			tripsStart := route.TripsOffset
			tripsEnd := tripsStart + uint32(route.TripCount)

			dominantTrips := 0
			totalSampled := 0

			for t := tripsStart; t < tripsEnd && t < uint32(len(rawTT.Trips)); t++ {
				trip := rawTT.Trips[t]
				stOffset := trip.StopTimesOffset

				uSTIdx := stOffset + uint32(uSeq)
				vSTIdx := stOffset + uint32(vSeq)

				if uSTIdx < uint32(len(rawTT.StopTimes)) && vSTIdx < uint32(len(rawTT.StopTimes)) {
					uST := rawTT.StopTimes[uSTIdx]
					vST := rawTT.StopTimes[vSTIdx]

					if vST.ArrivalTimeSec >= uST.DepartureTimeSec {
						inVehicleSec := vST.ArrivalTimeSec - uST.DepartureTimeSec
						totalSampled++
						// If transit in-vehicle time is strictly faster than walking duration
						if inVehicleSec < uint32(walkDurationSec) {
							dominantTrips++
						}
					}
				}
			}

			// If >90% of trips on this direct transit route beat walking, the candidate walking shortcut is dominated
			if totalSampled > 0 && float64(dominantTrips)/float64(totalSampled) > 0.90 {
				return true
			}
		}
	}

	return false
}

// PruneShortcutsWithWitnesses filters out transit-dominated candidate shortcuts
func (we *WitnessEngine) PruneShortcutsWithWitnesses(
	u uint32,
	candidates []TransferCandidate,
	tt *CompactTimetable,
	rawTT *raptor.CompiledTimetable,
) []TransferCandidate {
	if len(candidates) == 0 {
		return candidates
	}

	surviving := candidates[:0]

	for _, c := range candidates {
		isDominated := we.EvaluateWitnessDominance(u, c.TargetStop, c.Duration, tt, rawTT)
		if !isDominated {
			surviving = append(surviving, c)
		}
	}

	return surviving
}
