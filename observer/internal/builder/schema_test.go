package builder_test

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"observer/internal/builder"
	"observer/internal/gtfs"
)

func TestRealtimeDeparturesClusteredSchemaAndPlan(t *testing.T) {
	tempDir, err := os.MkdirTemp("", "derivee_builder_test_*")
	if err != nil {
		t.Fatalf("Failed to create temp dir: %v", err)
	}
	defer os.RemoveAll(tempDir)

	dbPath := filepath.Join(tempDir, "test_transit.sqlite")
	db, err := builder.InitTransitDB(dbPath)
	if err != nil {
		t.Fatalf("Failed to init transit DB: %v", err)
	}
	defer db.Close()

	// 1. Verify schema includes WITHOUT ROWID and primary key
	var tableSQL string
	err = db.QueryRow("SELECT sql FROM sqlite_master WHERE type='table' AND name='realtime_departures'").Scan(&tableSQL)
	if err != nil {
		t.Fatalf("realtime_departures table missing: %v", err)
	}
	if !strings.Contains(tableSQL, "WITHOUT ROWID") {
		t.Errorf("realtime_departures table must be defined WITHOUT ROWID, got: %s", tableSQL)
	}
	if !strings.Contains(tableSQL, "PRIMARY KEY (complex_id, departure_time, feed_id, child_stop_id, trip_id)") {
		t.Errorf("realtime_departures missing expected clustered primary key, got: %s", tableSQL)
	}

	// 2. Insert test departures
	now := time.Now().Unix()
	departures := []gtfs.RealtimeDeparture{
		{
			ComplexID:             602,
			DepartureTime:         now + 120,
			FeedID:                "subway",
			ParentStationID:       "635",
			ChildStopID:           "635N",
			TripID:                "TRIP_4_NB_1",
			RouteID:               "4",
			RouteShortName:        "4",
			DirectionID:           0,
			DynamicTerminalStopID: "401",
			DynamicTerminalName:   "Woodlawn",
			IsExpress:             1,
			ScheduledTrack:        "3",
			ActualTrack:           "3",
			UpdatedAt:             now,
		},
		{
			ComplexID:             602,
			DepartureTime:         now + 180,
			FeedID:                "subway",
			ParentStationID:       "R20",
			ChildStopID:           "R20N",
			TripID:                "TRIP_N_NB_1",
			RouteID:               "N",
			RouteShortName:        "N",
			DirectionID:           0,
			DynamicTerminalStopID: "R01",
			DynamicTerminalName:   "Astoria-Ditmars Blvd",
			IsExpress:             1,
			ScheduledTrack:        "3",
			ActualTrack:           "3",
			UpdatedAt:             now,
		},
		{
			ComplexID:             602,
			DepartureTime:         now + 240,
			FeedID:                "subway",
			ParentStationID:       "L03",
			ChildStopID:           "L03N",
			TripID:                "TRIP_L_EB_1",
			RouteID:               "L",
			RouteShortName:        "L",
			DirectionID:           0,
			DynamicTerminalStopID: "L29",
			DynamicTerminalName:   "Canarsie-Rockaway Pkwy",
			IsExpress:             0,
			ScheduledTrack:        "1",
			ActualTrack:           "1",
			UpdatedAt:             now,
		},
	}

	err = builder.BulkInsertRealtimeDepartures(db, departures)
	if err != nil {
		t.Fatalf("BulkInsertRealtimeDepartures failed: %v", err)
	}

	// 3. Verify count
	var count int
	err = db.QueryRow("SELECT COUNT(*) FROM realtime_departures WHERE complex_id = 602").Scan(&count)
	if err != nil || count != 3 {
		t.Fatalf("Expected 3 departures, got %d (err=%v)", count, err)
	}

	// 4. Verify EXPLAIN QUERY PLAN eliminates USE TEMP B-TREE FOR ORDER BY
	planRows, err := db.Query(`
		EXPLAIN QUERY PLAN
		SELECT 
			complex_id,
			departure_time,
			feed_id,
			parent_station_id,
			child_stop_id,
			trip_id,
			route_id,
			route_short_name,
			direction_id,
			dynamic_terminal_stop_id,
			dynamic_terminal_name,
			is_express,
			COALESCE(actual_track, scheduled_track, '') AS track
		FROM realtime_departures
		WHERE complex_id = ?
		  AND departure_time >= ?
		ORDER BY departure_time ASC
		LIMIT ?
	`, 602, now, 30)
	if err != nil {
		t.Fatalf("EXPLAIN QUERY PLAN failed: %v", err)
	}
	defer planRows.Close()

	var planDetails []string
	hasClusteredSeek := false
	hasTempBTree := false

	for planRows.Next() {
		var id, parent, notused int
		var detail string
		if err := planRows.Scan(&id, &parent, &notused, &detail); err != nil {
			t.Fatalf("Failed scanning plan row: %v", err)
		}
		planDetails = append(planDetails, detail)
		if strings.Contains(detail, "PRIMARY KEY") && strings.Contains(detail, "complex_id=?") {
			hasClusteredSeek = true
		}
		if strings.Contains(detail, "USE TEMP B-TREE") {
			hasTempBTree = true
		}
	}

	if !hasClusteredSeek {
		t.Errorf("Expected clustered PRIMARY KEY scan, got plan: %s", strings.Join(planDetails, " | "))
	}
	if hasTempBTree {
		t.Errorf("CRITICAL GUARDRAIL VIOLATION: Query plan invoked USE TEMP B-TREE FOR ORDER BY! Plan: %s", strings.Join(planDetails, " | "))
	}
}
