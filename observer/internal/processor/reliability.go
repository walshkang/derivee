package processor

import (
	"log"
	"time"

	"observer/internal/fetcher"
)

// TTL for a trip update before it is considered a "Ghost Train" and dropped
const TripTTL = 10 * time.Minute

// ActiveTrip tracks a trip currently in the system
type ActiveTrip struct {
	TripID      string
	RouteID     string
	DirectionID uint32
	LastSeen    time.Time
}

// ReliabilityEngine manages state for tracking reliability
type ReliabilityEngine struct {
	ActiveTrips map[string]*ActiveTrip
}

func NewReliabilityEngine() *ReliabilityEngine {
	return &ReliabilityEngine{
		ActiveTrips: make(map[string]*ActiveTrip),
	}
}

// ProcessUpdates ingests a batch of TripUpdates and updates active trips
func (r *ReliabilityEngine) ProcessUpdates(updates []fetcher.TripUpdate) {
	now := time.Now()
	for _, u := range updates {
		if trip, exists := r.ActiveTrips[u.TripID]; exists {
			trip.LastSeen = now
		} else {
			r.ActiveTrips[u.TripID] = &ActiveTrip{
				TripID:      u.TripID,
				RouteID:     u.RouteID,
				DirectionID: u.DirectionID,
				LastSeen:    now,
			}
		}
	}
	
	r.GarbageCollect(now)
}

// GarbageCollect removes trips that haven't been seen within the TTL (Ghost Trains)
func (r *ReliabilityEngine) GarbageCollect(now time.Time) {
	for tripID, trip := range r.ActiveTrips {
		if now.Sub(trip.LastSeen) > TripTTL {
			log.Printf("Ghost Train detected (TripID: %s, Route: %s). Dropping without penalty.", tripID, trip.RouteID)
			delete(r.ActiveTrips, tripID)
		}
	}
}
