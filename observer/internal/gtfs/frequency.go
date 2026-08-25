package gtfs

import (
	"fmt"
)

// SynthesizedTripStopTimes represents a synthesized trip instance generated from frequencies.txt
type SynthesizedTripInstance struct {
	TripID       string
	InstanceID   string
	ServiceID    string
	RouteID      string
	DirectionID  int
	Headsign     string
	StopTimes    []StopTime
}

// ExpandFrequencyTrips expands frequency-based trips into concrete trip instances
func ExpandFrequencyTrips(
	trip Trip,
	baseStopTimes []StopTime,
	frequencies []Frequency,
) []SynthesizedTripInstance {
	if len(frequencies) == 0 || len(baseStopTimes) == 0 {
		return nil
	}

	baseOriginTime := baseStopTimes[0].DepartureTimeSec
	var instances []SynthesizedTripInstance

	for freqIdx, freq := range frequencies {
		if freq.HeadwaySecs <= 0 {
			continue
		}

		instanceNum := 0
		for t := freq.StartTimeSec; t < freq.EndTimeSec; t += freq.HeadwaySecs {
			instanceNum++
			instanceID := fmt.Sprintf("%s_freq_%d_%d", trip.TripID, freqIdx, instanceNum)
			timeOffset := t - baseOriginTime

			instanceStopTimes := make([]StopTime, len(baseStopTimes))
			for i, st := range baseStopTimes {
				instanceStopTimes[i] = StopTime{
					TripID:            instanceID,
					StopID:            st.StopID,
					StopSequence:      st.StopSequence,
					ArrivalTimeSec:    st.ArrivalTimeSec + timeOffset,
					DepartureTimeSec:  st.DepartureTimeSec + timeOffset,
					Timepoint:         st.Timepoint,
					ShapeDistTraveled: st.ShapeDistTraveled,
				}
			}

			instances = append(instances, SynthesizedTripInstance{
				TripID:      trip.TripID,
				InstanceID:  instanceID,
				ServiceID:   trip.ServiceID,
				RouteID:     trip.RouteID,
				DirectionID: trip.DirectionID,
				Headsign:    trip.TripHeadsign,
				StopTimes:   instanceStopTimes,
			})
		}
	}

	return instances
}
