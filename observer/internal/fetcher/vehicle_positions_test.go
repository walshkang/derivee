package fetcher

import (
	"testing"

	"github.com/MobilityData/gtfs-realtime-bindings/golang/gtfs"
	"google.golang.org/protobuf/proto"
)

func TestParseVehiclePositions(t *testing.T) {
	// Nil feed
	if res := ParseVehiclePositions(nil); res != nil {
		t.Errorf("expected nil for nil feed, got %v", res)
	}

	// Empty feed
	emptyFeed := &gtfs.FeedMessage{}
	if res := ParseVehiclePositions(emptyFeed); len(res) != 0 {
		t.Errorf("expected empty slice for empty feed, got %d", len(res))
	}

	// Populated feed
	entityID := "entity_1"
	vehicleID := "veh_9021"
	tripID := "trip_1001"
	routeID := "1"
	dirID := uint32(0)
	lat := float32(40.7505)
	lon := float32(-73.9935)
	bearing := float32(180.0)
	speed := float32(11.5)
	status := gtfs.VehiclePosition_IN_TRANSIT_TO
	stopSeq := uint32(14)
	stopID := "128S"
	timestamp := uint64(1774958400)

	feed := &gtfs.FeedMessage{
		Header: &gtfs.FeedHeader{
			GtfsRealtimeVersion: proto.String("2.0"),
		},
		Entity: []*gtfs.FeedEntity{
			{
				Id: &entityID,
				Vehicle: &gtfs.VehiclePosition{
					Trip: &gtfs.TripDescriptor{
						TripId:      &tripID,
						RouteId:     &routeID,
						DirectionId: &dirID,
					},
					Vehicle: &gtfs.VehicleDescriptor{
						Id: &vehicleID,
					},
					Position: &gtfs.Position{
						Latitude:  &lat,
						Longitude: &lon,
						Bearing:   &bearing,
						Speed:     &speed,
					},
					CurrentStopSequence: &stopSeq,
					CurrentStatus:       &status,
					Timestamp:           &timestamp,
					StopId:              &stopID,
				},
			},
		},
	}

	positions := ParseVehiclePositions(feed)
	if len(positions) != 1 {
		t.Fatalf("expected 1 vehicle position, got %d", len(positions))
	}

	pos := positions[0]
	if pos.VehicleID != "veh_9021" {
		t.Errorf("expected VehicleID 'veh_9021', got '%s'", pos.VehicleID)
	}
	if pos.TripID != "trip_1001" {
		t.Errorf("expected TripID 'trip_1001', got '%s'", pos.TripID)
	}
	if pos.RouteID != "1" {
		t.Errorf("expected RouteID '1', got '%s'", pos.RouteID)
	}
	if pos.DirectionID != 0 {
		t.Errorf("expected DirectionID 0, got %d", pos.DirectionID)
	}
	if pos.Latitude != float64(lat) {
		t.Errorf("expected Latitude %f, got %f", lat, pos.Latitude)
	}
	if pos.Longitude != float64(lon) {
		t.Errorf("expected Longitude %f, got %f", lon, pos.Longitude)
	}
	if pos.Bearing != float64(bearing) {
		t.Errorf("expected Bearing %f, got %f", bearing, pos.Bearing)
	}
	if pos.SpeedMPS != float64(speed) {
		t.Errorf("expected SpeedMPS %f, got %f", speed, pos.SpeedMPS)
	}
	if pos.CurrentStatus != "IN_TRANSIT_TO" {
		t.Errorf("expected CurrentStatus 'IN_TRANSIT_TO', got '%s'", pos.CurrentStatus)
	}
	if pos.CurrentStopSequence != stopSeq {
		t.Errorf("expected CurrentStopSequence %d, got %d", stopSeq, pos.CurrentStopSequence)
	}
	if pos.StopID != "128S" {
		t.Errorf("expected StopID '128S', got '%s'", pos.StopID)
	}
	if pos.Timestamp != timestamp {
		t.Errorf("expected Timestamp %d, got %d", timestamp, pos.Timestamp)
	}
}
