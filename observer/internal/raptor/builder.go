package raptor

import (
	"fmt"
	"sort"
	"strings"
	"time"

	"observer/internal/gtfs"
)

// CompileTimetable compiles a parsed GTFS dataset into an in-memory CompiledTimetable structure
func CompileTimetable(ds *gtfs.Dataset, anchorDate time.Time) (*CompiledTimetable, error) {
	if ds == nil {
		return nil, fmt.Errorf("gtfs dataset is nil")
	}

	// 1. Assign deterministic contiguous indices to Stops
	stopIDs := make([]string, 0, len(ds.Stops))
	for sID := range ds.Stops {
		stopIDs = append(stopIDs, sID)
	}
	sort.Strings(stopIDs)

	stopIDToIndex := make(map[string]uint32, len(stopIDs))
	indexToStopID := make([]string, len(stopIDs))
	stops := make([]Stop, len(stopIDs))

	for idx, sID := range stopIDs {
		uIdx := uint32(idx)
		stopIDToIndex[sID] = uIdx
		indexToStopID[idx] = sID
		gtfsStop := ds.Stops[sID]
		stops[idx] = Stop{
			Latitude:  float32(gtfsStop.StopLat),
			Longitude: float32(gtfsStop.StopLon),
		}
	}

	// 2. Resolve Service IDs & Calendar bitmasks
	calResolver := gtfs.NewCalendarResolver(anchorDate, ds.Calendars, ds.CalendarDates)
	serviceIDMap := make(map[string]uint16)
	serviceDays := make([]uint8, 0)

	getServiceID := func(sID string) uint16 {
		if idx, ok := serviceIDMap[sID]; ok {
			return idx
		}
		newIdx := uint16(len(serviceIDMap))
		serviceIDMap[sID] = newIdx
		daysMask := calResolver.ComputeBaselineDaysOfWeek(sID)
		serviceDays = append(serviceDays, daysMask)
		return newIdx
	}

	// 3. Group Trips into RAPTOR Route Patterns
	type TripCandidate struct {
		TripID        string
		RouteID       string
		DirectionID   int
		ServiceID     uint16
		StopTimes     []gtfs.StopTime
		FirstDepSec   int
	}

	type RoutePatternKey struct {
		RouteID       string
		DirectionID   int
		StopSignature string
	}

	patternGroups := make(map[RoutePatternKey][]*TripCandidate)

	for tripID, trip := range ds.Trips {
		stList, ok := ds.StopTimes[tripID]
		if !ok || len(stList) < 2 {
			continue
		}

		// Sort stop times by StopSequence
		sortedST := make([]gtfs.StopTime, len(stList))
		copy(sortedST, stList)
		sort.Slice(sortedST, func(i, j int) bool {
			return sortedST[i].StopSequence < sortedST[j].StopSequence
		})

		// Build stop signature
		var sb strings.Builder
		validStops := true
		for i, st := range sortedST {
			if _, exists := stopIDToIndex[st.StopID]; !exists {
				validStops = false
				break
			}
			if i > 0 {
				sb.WriteString(",")
			}
			sb.WriteString(st.StopID)
		}
		if !validStops {
			continue
		}

		key := RoutePatternKey{
			RouteID:       trip.RouteID,
			DirectionID:   trip.DirectionID,
			StopSignature: sb.String(),
		}

		svcID := getServiceID(trip.ServiceID)
		firstDep := sortedST[0].DepartureTimeSec

		patternGroups[key] = append(patternGroups[key], &TripCandidate{
			TripID:      tripID,
			RouteID:     trip.RouteID,
			DirectionID: trip.DirectionID,
			ServiceID:   svcID,
			StopTimes:   sortedST,
			FirstDepSec: firstDep,
		})
	}

	// Sort pattern keys for deterministic route ordering
	patternKeys := make([]RoutePatternKey, 0, len(patternGroups))
	for k := range patternGroups {
		patternKeys = append(patternKeys, k)
	}
	sort.Slice(patternKeys, func(i, j int) bool {
		if patternKeys[i].RouteID != patternKeys[j].RouteID {
			return patternKeys[i].RouteID < patternKeys[j].RouteID
		}
		if patternKeys[i].DirectionID != patternKeys[j].DirectionID {
			return patternKeys[i].DirectionID < patternKeys[j].DirectionID
		}
		return patternKeys[i].StopSignature < patternKeys[j].StopSignature
	})

	// 4. Flatten Routes, Trips, StopTimes, and RouteStops
	routes := make([]Route, len(patternKeys))
	trips := make([]Trip, 0)
	stopTimes := make([]StopTime, 0)
	routeStops := make([]uint32, 0)

	routeIDToIndex := make(map[string]uint32, len(patternKeys))
	indexToRouteID := make([]string, len(patternKeys))
	tripIDToIndex := make(map[string]uint32)
	indexToTripID := make([]string, 0)

	stopToServingRoutes := make(map[uint32][]uint32)

	for rIdx, key := range patternKeys {
		uRouteIdx := uint32(rIdx)
		candList := patternGroups[key]

		// Sort trips within route monotonically by departure time at the first stop
		sort.Slice(candList, func(i, j int) bool {
			if candList[i].FirstDepSec != candList[j].FirstDepSec {
				return candList[i].FirstDepSec < candList[j].FirstDepSec
			}
			return candList[i].TripID < candList[j].TripID
		})

		// Parse stop sequence for this route pattern
		stopIDStrs := strings.Split(key.StopSignature, ",")
		rStopsOffset := uint32(len(routeStops))
		for _, sStr := range stopIDStrs {
			sIdx := stopIDToIndex[sStr]
			routeStops = append(routeStops, sIdx)
			stopToServingRoutes[sIdx] = append(stopToServingRoutes[sIdx], uRouteIdx)
		}

		routeTripsOffset := uint32(len(trips))
		for _, cand := range candList {
			tIdx := uint32(len(trips))
			tripIDToIndex[cand.TripID] = tIdx
			indexToTripID = append(indexToTripID, cand.TripID)

			stOffset := uint32(len(stopTimes))
			for _, st := range cand.StopTimes {
				stopTimes = append(stopTimes, StopTime{
					ArrivalTimeSec:   uint32(st.ArrivalTimeSec),
					DepartureTimeSec: uint32(st.DepartureTimeSec),
					StopID:           stopIDToIndex[st.StopID],
				})
			}

			trips = append(trips, Trip{
				StopTimesOffset: stOffset,
				StopTimesCount:  uint16(len(cand.StopTimes)),
				ServiceID:       cand.ServiceID,
			})
		}

		routeIDToIndex[key.RouteID] = uRouteIdx
		indexToRouteID[rIdx] = key.RouteID

		routes[rIdx] = Route{
			TripsOffset:      routeTripsOffset,
			RouteStopsOffset: rStopsOffset,
			TripCount:        uint16(len(candList)),
			StopCount:        uint16(len(stopIDStrs)),
		}
	}

	// 5. Build Stop-Routes Inverted Index
	stopRoutes := make([]uint32, 0)
	for sIdx := range stops {
		uSIdx := uint32(sIdx)
		rList := stopToServingRoutes[uSIdx]
		// Deduplicate and sort routes
		if len(rList) > 1 {
			sort.Slice(rList, func(i, j int) bool { return rList[i] < rList[j] })
			dedup := make([]uint32, 0, len(rList))
			for i, r := range rList {
				if i == 0 || r != rList[i-1] {
					dedup = append(dedup, r)
				}
			}
			rList = dedup
		}

		stops[sIdx].RoutesOffset = uint32(len(stopRoutes))
		stops[sIdx].RouteCount = uint16(len(rList))
		stopRoutes = append(stopRoutes, rList...)
	}

	// 6. Build Intra-Timetable Transfers (Parent/Child Platform Connections)
	parentToChildren := make(map[string][]uint32)
	for sID, sIdx := range stopIDToIndex {
		st := ds.Stops[sID]
		if st.ParentStation != "" {
			parentToChildren[st.ParentStation] = append(parentToChildren[st.ParentStation], sIdx)
		}
	}

	transfers := make([]Transfer, 0)
	for sIdx := range stops {
		uSIdx := uint32(sIdx)
		sID := indexToStopID[sIdx]
		st := ds.Stops[sID]

		stops[sIdx].TransfersOffset = uint32(len(transfers))
		var outgoing []Transfer

		if st.ParentStation != "" {
			siblings := parentToChildren[st.ParentStation]
			for _, sibIdx := range siblings {
				if sibIdx != uSIdx {
					outgoing = append(outgoing, Transfer{
						TargetStopID:   sibIdx,
						DurationSec:    120, // Nominal 2-minute station transfer
						DistanceMeters: 100, // Nominal 100-meter platform distance
					})
				}
			}
		}

		stops[sIdx].TransferCount = uint16(len(outgoing))
		transfers = append(transfers, outgoing...)
	}

	// 7. Compute Stochastic Weights
	stochasticWeights := ComputeStochasticWeights(routes, trips, stopTimes, serviceDays)

	return &CompiledTimetable{
		Stops:             stops,
		Routes:            routes,
		Trips:             trips,
		StopTimes:         stopTimes,
		Transfers:         transfers,
		StopRoutes:        stopRoutes,
		RouteStops:        routeStops,
		StochasticWeights: stochasticWeights,
		StopIDToIndex:     stopIDToIndex,
		IndexToStopID:     indexToStopID,
		RouteIDToIndex:    routeIDToIndex,
		IndexToRouteID:    indexToRouteID,
		TripIDToIndex:     tripIDToIndex,
		IndexToTripID:     indexToTripID,
	}, nil
}
