package gtfs

import (
	"fmt"
	"sort"
)

type patternGroupKey struct {
	stopID             string
	routeID            string
	directionID        int
	hourOfDay          int
	serviceMask        uint16
	baselineDaysOfWeek uint8
}

type patternGroupValue struct {
	minutes   []int
	headsigns map[string]int
}

// CompactDataset transforms a GTFS Dataset into normalized, compacted ScheduledHourlyPattern rows
func CompactDataset(dataset *Dataset) []ScheduledHourlyPattern {
	resolver := NewCalendarResolver(dataset.CompilationDate, dataset.Calendars, dataset.CalendarDates)
	groups := make(map[patternGroupKey]*patternGroupValue)

	// Pre-cache service masks and baseline masks
	serviceMaskCache := make(map[string]uint16)
	baselineCache := make(map[string]uint8)

	getServiceMask := func(serviceID string) uint16 {
		if mask, ok := serviceMaskCache[serviceID]; ok {
			return mask
		}
		mask := resolver.ComputeServiceMask(serviceID)
		serviceMaskCache[serviceID] = mask
		return mask
	}

	getBaseline := func(serviceID string) uint8 {
		if mask, ok := baselineCache[serviceID]; ok {
			return mask
		}
		mask := resolver.ComputeBaselineDaysOfWeek(serviceID)
		baselineCache[serviceID] = mask
		return mask
	}

	for tripID, trip := range dataset.Trips {
		baseStopTimes, hasStopTimes := dataset.StopTimes[tripID]
		if !hasStopTimes || len(baseStopTimes) == 0 {
			continue
		}

		// Sort stop times by sequence
		sort.Slice(baseStopTimes, func(i, j int) bool {
			return baseStopTimes[i].StopSequence < baseStopTimes[j].StopSequence
		})

		var tripInstances []SynthesizedTripInstance
		if freqs, hasFreqs := dataset.Frequencies[tripID]; hasFreqs && len(freqs) > 0 {
			tripInstances = ExpandFrequencyTrips(trip, baseStopTimes, freqs)
		} else {
			tripInstances = []SynthesizedTripInstance{
				{
					TripID:      trip.TripID,
					InstanceID:  trip.TripID,
					ServiceID:   trip.ServiceID,
					RouteID:     trip.RouteID,
					DirectionID: trip.DirectionID,
					Headsign:    trip.TripHeadsign,
					StopTimes:   baseStopTimes,
				},
			}
		}

		for _, instance := range tripInstances {
			interpolatedTimes := InterpolateTripStopTimes(instance.StopTimes)
			serviceMask := getServiceMask(instance.ServiceID)
			baselineDays := getBaseline(instance.ServiceID)

			for _, st := range interpolatedTimes {
				depSec := st.DepartureTimeSec
				if depSec < 0 {
					depSec = st.ArrivalTimeSec
				}
				if depSec < 0 {
					continue
				}

				// Handle overnight trips (>= 24:00:00)
				dayShift := depSec / 86400
				wallClockSec := depSec % 86400
				if wallClockSec < 0 {
					wallClockSec += 86400
					dayShift -= 1
				}

				hourOfDay := wallClockSec / 3600
				minute := (wallClockSec % 3600) / 60
				shiftedMask := ShiftServiceMask(serviceMask, dayShift)

				if shiftedMask == 0 && baselineDays == 0 {
					continue
				}

				key := patternGroupKey{
					stopID:             st.StopID,
					routeID:            instance.RouteID,
					directionID:        instance.DirectionID,
					hourOfDay:          hourOfDay,
					serviceMask:        shiftedMask,
					baselineDaysOfWeek: baselineDays,
				}

				group, ok := groups[key]
				if !ok {
					group = &patternGroupValue{
						minutes:   make([]int, 0, 4),
						headsigns: make(map[string]int),
					}
					groups[key] = group
				}

				group.minutes = append(group.minutes, minute)
				headsign := instance.Headsign
				if headsign != "" {
					group.headsigns[headsign]++
				}
			}
		}
	}

	// Flatten groups into ScheduledHourlyPattern slices
	patterns := make([]ScheduledHourlyPattern, 0, len(groups))
	for key, group := range groups {
		if len(group.minutes) == 0 {
			continue
		}

		// Sort and deduplicate minutes
		sort.Ints(group.minutes)
		var uniqueMinutes []int
		for i, m := range group.minutes {
			if i == 0 || m != group.minutes[i-1] {
				uniqueMinutes = append(uniqueMinutes, m)
			}
		}

		// Build comma-separated minute string e.g. "04,16,28,40,52"
		minuteStr := ""
		for i, m := range uniqueMinutes {
			if i > 0 {
				minuteStr += ","
			}
			minuteStr += fmt.Sprintf("%02d", m)
		}

		// Resolve dominant headsign
		dominantHeadsign := ""
		maxCount := 0
		for hs, count := range group.headsigns {
			if count > maxCount {
				maxCount = count
				dominantHeadsign = hs
			}
		}

		patterns = append(patterns, ScheduledHourlyPattern{
			StopID:             key.stopID,
			RouteID:            key.routeID,
			DirectionID:        key.directionID,
			HourOfDay:          key.hourOfDay,
			ServiceMask:        key.serviceMask,
			BaselineDaysOfWeek: key.baselineDaysOfWeek,
			MinuteOffsets:      minuteStr,
			Headsign:           dominantHeadsign,
		})
	}

	// Sort patterns for deterministic DB inserts
	sort.Slice(patterns, func(i, j int) bool {
		if patterns[i].StopID != patterns[j].StopID {
			return patterns[i].StopID < patterns[j].StopID
		}
		if patterns[i].RouteID != patterns[j].RouteID {
			return patterns[i].RouteID < patterns[j].RouteID
		}
		if patterns[i].DirectionID != patterns[j].DirectionID {
			return patterns[i].DirectionID < patterns[j].DirectionID
		}
		if patterns[i].HourOfDay != patterns[j].HourOfDay {
			return patterns[i].HourOfDay < patterns[j].HourOfDay
		}
		return patterns[i].ServiceMask < patterns[j].ServiceMask
	})

	return patterns
}
