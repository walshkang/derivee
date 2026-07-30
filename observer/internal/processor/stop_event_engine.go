package processor

import (
	"log"
	"time"
	"github.com/google/uuid"

	"observer/internal/fetcher"
)

// TTL for a trip update before it is considered a "Ghost Train" and dropped
const TripTTL = 10 * time.Minute

// StopPrediction holds the last known prediction for a stop
type StopPrediction struct {
	StopID  string
	Arrival int64
}

// ActiveTrip tracks a trip currently in the system
type ActiveTrip struct {
	TripID      string
	RouteID     string
	DirectionID uint32
	LastSeen    time.Time
	UpcomingStops map[string]StopPrediction
}

// StopEvent represents a finalized arrival
type StopEvent struct {
	EventID       string
	TripID        string
	RouteID       string
	DirectionID   uint32
	StopID        string
	ScheduledTime int
	ActualTime    int
	DelaySeconds  int
	ObservedAt    int64
}

type ScheduledTimeProvider interface {
	GetScheduledArrival(tripID, stopID string) (int, bool)
}

// StopEventEngine manages state for tracking stop arrivals and reliability
type StopEventEngine struct {
	ActiveTrips map[string]*ActiveTrip
	StaticDB    ScheduledTimeProvider
	EventsQueue []StopEvent
}

func NewStopEventEngine(staticDB ScheduledTimeProvider) *StopEventEngine {
	return &StopEventEngine{
		ActiveTrips: make(map[string]*ActiveTrip),
		StaticDB:    staticDB,
		EventsQueue: make([]StopEvent, 0),
	}
}

// ProcessUpdates ingests a batch of TripUpdates and detects stop arrivals
func (e *StopEventEngine) ProcessUpdates(updates []fetcher.TripUpdate) {
	now := time.Now()
	
	for _, u := range updates {
		trip, exists := e.ActiveTrips[u.TripID]
		if !exists {
			trip = &ActiveTrip{
				TripID:        u.TripID,
				RouteID:       u.RouteID,
				DirectionID:   u.DirectionID,
				UpcomingStops: make(map[string]StopPrediction),
			}
			e.ActiveTrips[u.TripID] = trip
		}
		
		trip.LastSeen = now
		
		// Build map of new stops
		newStops := make(map[string]StopPrediction)
		for _, stu := range u.Stops {
			newStops[stu.StopID] = StopPrediction{
				StopID:  stu.StopID,
				Arrival: stu.Arrival,
			}
		}
		
		// Detect missing stops (stops that were upcoming, but are now gone from the update -> assumed passed)
		for stopID, oldPred := range trip.UpcomingStops {
			if _, stillUpcoming := newStops[stopID]; !stillUpcoming {
				// The stop has been passed!
				e.recordStopEvent(trip, oldPred, now)
			}
		}
		
		// Update the trip's upcoming stops
		trip.UpcomingStops = newStops
	}
	
	e.GarbageCollect(now)
}

func (e *StopEventEngine) recordStopEvent(trip *ActiveTrip, pred StopPrediction, now time.Time) {
	var scheduledTime int
	
	// Lookup scheduled time from static SQLite database
	if e.StaticDB != nil {
		if t, ok := e.StaticDB.GetScheduledArrival(trip.TripID, pred.StopID); ok {
			scheduledTime = t
		}
	}
	
	actualTime := pred.Arrival
	
	// If the prediction was in the past or unreasonably far, fallback to 'now'
	if actualTime == 0 || actualTime > now.Unix()+3600 {
		actualTime = now.Unix()
	}

	// Calculate seconds past midnight for the actual arrival
	nyc, _ := time.LoadLocation("America/New_York") // Default to NYC time
	if nyc == nil {
		nyc = time.Local
	}
	t := time.Unix(actualTime, 0).In(nyc)
	actualSecs := t.Hour()*3600 + t.Minute()*60 + t.Second()

	delay := 0
	if scheduledTime > 0 {
		delay = actualSecs - scheduledTime
	}

	event := StopEvent{
		EventID:       uuid.New().String(),
		TripID:        trip.TripID,
		RouteID:       trip.RouteID,
		DirectionID:   trip.DirectionID,
		StopID:        pred.StopID,
		ScheduledTime: scheduledTime,
		ActualTime:    int(actualTime),
		DelaySeconds:  delay,
		ObservedAt:    now.Unix(),
	}

	e.EventsQueue = append(e.EventsQueue, event)
}

// GarbageCollect removes trips that haven't been seen within the TTL
func (e *StopEventEngine) GarbageCollect(now time.Time) {
	for tripID, trip := range e.ActiveTrips {
		if now.Sub(trip.LastSeen) > TripTTL {
			log.Printf("Trip ended or Ghost Train detected (TripID: %s). Dropping.", tripID)
			
			// We could assume the remaining UpcomingStops were passed if it's the end of the line,
			// but to be safe and avoid false positives on ghost trains, we drop them.
			delete(e.ActiveTrips, tripID)
		}
	}
}

// DrainEvents returns all recorded events and clears the queue
func (e *StopEventEngine) DrainEvents() []StopEvent {
	events := e.EventsQueue
	e.EventsQueue = make([]StopEvent, 0)
	return events
}
