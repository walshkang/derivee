package fetcher

import (
	"fmt"
	"io"
	"net/http"
	"os"

	"github.com/MobilityData/gtfs-realtime-bindings/golang/gtfs"
	"google.golang.org/protobuf/proto"
)

const (
	// Example MTA subway endpoint (no API key required)
	SubwayURL = "https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/nyct%2Fgtfs"
	BusURL    = "http://bustime.mta.info/api/siri/vehicle-monitoring.json"
)

type TripUpdate struct {
	TripID      string
	RouteID     string
	DirectionID uint32
	Stops       []StopTimeUpdate
}

type StopTimeUpdate struct {
	StopID  string
	Arrival int64 // timestamp
}

// FetchSubwayGTFS fetches the anonymous protobuf feed from MTA
func FetchSubwayGTFS() (*gtfs.FeedMessage, error) {
	resp, err := http.Get(SubwayURL)
	if err != nil {
		return nil, fmt.Errorf("failed to fetch subway GTFS: %w", err)
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("failed to read body: %w", err)
	}

	feed := &gtfs.FeedMessage{}
	err = proto.Unmarshal(body, feed)
	if err != nil {
		return nil, fmt.Errorf("failed to unmarshal GTFS: %w", err)
	}

	return feed, nil
}

// FetchBuses fetches the JSON Siri feed
func FetchBuses() ([]byte, error) {
	apiKey := os.Getenv("MTA_BUS_API_KEY")
	if apiKey == "" {
		return nil, fmt.Errorf("MTA_BUS_API_KEY not set")
	}
	
	url := fmt.Sprintf("%s?key=%s", BusURL, apiKey)
	resp, err := http.Get(url)
	if err != nil {
		return nil, fmt.Errorf("failed to fetch buses: %w", err)
	}
	defer resp.Body.Close()

	return io.ReadAll(resp.Body)
}

// ParseTripUpdates parses the GTFS-RT feed for trip updates
func ParseTripUpdates(feed *gtfs.FeedMessage) []TripUpdate {
	var updates []TripUpdate

	for _, entity := range feed.Entity {
		if entity.TripUpdate != nil {
			tu := TripUpdate{
				TripID:      entity.TripUpdate.Trip.GetTripId(),
				RouteID:     entity.TripUpdate.Trip.GetRouteId(),
				DirectionID: entity.TripUpdate.Trip.GetDirectionId(),
			}

			for _, stu := range entity.TripUpdate.StopTimeUpdate {
				if stu.Arrival != nil {
					tu.Stops = append(tu.Stops, StopTimeUpdate{
						StopID:  stu.GetStopId(),
						Arrival: stu.Arrival.GetTime(),
					})
				}
			}
			updates = append(updates, tu)
		}
	}
	return updates
}
