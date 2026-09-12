package gtfs

import (
	"sort"
	"strings"
)

// ComputeRouteDirections computes the statistical mode of trip_headsign and the terminal stop_id
// for each (route_id, direction_id) combination in the dataset (Wave PB.5).
func ComputeRouteDirections(ds *Dataset) []RouteDirection {
	type routeDirKey struct {
		routeID     string
		directionID int
	}

	// Map key -> headsign -> frequency count
	headsignCounts := make(map[routeDirKey]map[string]int)
	// Map key -> headsign -> terminal stop_id -> frequency count
	termCountsByHeadsign := make(map[routeDirKey]map[string]map[string]int)
	// Map key -> terminal stop_id -> frequency count (global across all headsigns)
	globalTermCounts := make(map[routeDirKey]map[string]int)

	for tripID, trip := range ds.Trips {
		key := routeDirKey{
			routeID:     trip.RouteID,
			directionID: trip.DirectionID,
		}

		headsign := strings.TrimSpace(trip.TripHeadsign)

		var terminalStopID string
		if stList, ok := ds.StopTimes[tripID]; ok && len(stList) > 0 {
			maxSeq := -1
			for _, st := range stList {
				if st.StopSequence > maxSeq {
					maxSeq = st.StopSequence
					terminalStopID = st.StopID
				}
			}
		}

		if _, exists := headsignCounts[key]; !exists {
			headsignCounts[key] = make(map[string]int)
			termCountsByHeadsign[key] = make(map[string]map[string]int)
			globalTermCounts[key] = make(map[string]int)
		}

		headsignCounts[key][headsign]++
		if terminalStopID != "" {
			globalTermCounts[key][terminalStopID]++
			if _, exists := termCountsByHeadsign[key][headsign]; !exists {
				termCountsByHeadsign[key][headsign] = make(map[string]int)
			}
			termCountsByHeadsign[key][headsign][terminalStopID]++
		}
	}

	var results []RouteDirection
	for key, hCounts := range headsignCounts {
		// 1. Determine modal headsign
		// Prefer non-empty headsigns with the maximum count
		var bestHeadsign string
		maxCount := -1
		for h, count := range hCounts {
			if h == "" {
				continue
			}
			if count > maxCount || (count == maxCount && (bestHeadsign == "" || h < bestHeadsign)) {
				maxCount = count
				bestHeadsign = h
			}
		}

		// Fallback if all trips had blank headsign
		if bestHeadsign == "" {
			if route, ok := ds.Routes[key.routeID]; ok && route.RouteLongName != "" {
				bestHeadsign = route.RouteLongName
			}
		}

		// 2. Determine modal terminal stop ID
		var bestTerminalStopID string
		maxTermCount := -1

		// First try terminal counts for the chosen headsign
		if terms, ok := termCountsByHeadsign[key][bestHeadsign]; ok && len(terms) > 0 {
			for tID, count := range terms {
				if count > maxTermCount || (count == maxTermCount && (bestTerminalStopID == "" || tID < bestTerminalStopID)) {
					maxTermCount = count
					bestTerminalStopID = tID
				}
			}
		}

		// Fallback to global terminal counts for this (route, direction)
		if bestTerminalStopID == "" {
			for tID, count := range globalTermCounts[key] {
				if count > maxTermCount || (count == maxTermCount && (bestTerminalStopID == "" || tID < bestTerminalStopID)) {
					maxTermCount = count
					bestTerminalStopID = tID
				}
			}
		}

		// Final fallback for headsign if still blank: use terminal stop name
		if bestHeadsign == "" && bestTerminalStopID != "" {
			if stop, ok := ds.Stops[bestTerminalStopID]; ok && stop.StopName != "" {
				bestHeadsign = stop.StopName
			}
		}

		results = append(results, RouteDirection{
			RouteID:        key.routeID,
			DirectionID:    key.directionID,
			Headsign:       bestHeadsign,
			TerminalStopID: bestTerminalStopID,
		})
	}

	// Sort deterministically: route_id ASC, direction_id ASC
	sort.Slice(results, func(i, j int) bool {
		if results[i].RouteID != results[j].RouteID {
			return results[i].RouteID < results[j].RouteID
		}
		return results[i].DirectionID < results[j].DirectionID
	})

	return results
}
