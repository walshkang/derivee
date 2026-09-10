package fetcher

import (
	"github.com/MobilityData/gtfs-realtime-bindings/golang/gtfs"
)

// VehiclePosition models an ingested GTFS-RT vehicle position update.
type VehiclePosition struct {
	VehicleID           string  `json:"vehicle_id"`
	TripID              string  `json:"trip_id"`
	RouteID             string  `json:"route_id"`
	DirectionID         uint32  `json:"direction_id"`
	Latitude            float64 `json:"latitude"`
	Longitude           float64 `json:"longitude"`
	Bearing             float64 `json:"bearing"`
	SpeedMPS            float64 `json:"speed_mps"`
	CurrentStatus       string  `json:"current_status"`
	CurrentStopSequence uint32  `json:"current_stop_sequence"`
	StopID              string  `json:"stop_id"`
	Timestamp           uint64  `json:"timestamp"`
}

// ParseVehiclePositions extracts active vehicle locations and telemetry from a GTFS-RT FeedMessage.
func ParseVehiclePositions(feed *gtfs.FeedMessage) []VehiclePosition {
	if feed == nil {
		return nil
	}

	var positions []VehiclePosition

	for _, entity := range feed.Entity {
		if entity.Vehicle != nil {
			vp := entity.Vehicle

			pos := VehiclePosition{}

			if vp.Vehicle != nil {
				pos.VehicleID = vp.Vehicle.GetId()
			}
			if pos.VehicleID == "" && entity.Id != nil {
				pos.VehicleID = *entity.Id
			}

			if vp.Trip != nil {
				pos.TripID = vp.Trip.GetTripId()
				pos.RouteID = vp.Trip.GetRouteId()
				pos.DirectionID = vp.Trip.GetDirectionId()
			}

			if vp.Position != nil {
				pos.Latitude = float64(vp.Position.GetLatitude())
				pos.Longitude = float64(vp.Position.GetLongitude())
				pos.Bearing = float64(vp.Position.GetBearing())
				pos.SpeedMPS = float64(vp.Position.GetSpeed())
			}

			if vp.CurrentStatus != nil {
				pos.CurrentStatus = vp.CurrentStatus.String()
			}

			pos.CurrentStopSequence = vp.GetCurrentStopSequence()
			pos.StopID = vp.GetStopId()
			pos.Timestamp = vp.GetTimestamp()

			positions = append(positions, pos)
		}
	}

	return positions
}
