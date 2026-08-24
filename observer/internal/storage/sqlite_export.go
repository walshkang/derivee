package storage

import (
	"database/sql"
	"fmt"
	"log"

	_ "github.com/mattn/go-sqlite3"

	"observer/internal/processor"
)

type Database struct {
	db *sql.DB
}

// InitDB initializes the SQLite DB with the required schema
func InitDB(path string) (*Database, error) {
	db, err := sql.Open("sqlite3", path)
	if err != nil {
		return nil, fmt.Errorf("failed to open database: %w", err)
	}

	// Enforce WAL mode for performance
	if _, err := db.Exec(`PRAGMA journal_mode = WAL;`); err != nil {
		return nil, fmt.Errorf("failed to set WAL mode: %w", err)
	}

	// Create tables
	createTablesSQL := `
	CREATE TABLE IF NOT EXISTS stop_events (
		event_id TEXT PRIMARY KEY,
		trip_id TEXT NOT NULL,
		route_id TEXT NOT NULL,
		direction_id INTEGER NOT NULL DEFAULT 0,
		stop_id TEXT NOT NULL,
		scheduled_time INTEGER,
		actual_time INTEGER NOT NULL,
		delay_seconds INTEGER NOT NULL,
		observed_at INTEGER NOT NULL
	) WITHOUT ROWID;

	CREATE TABLE IF NOT EXISTS stop_reliability_hourly (
		route_id TEXT NOT NULL,
		stop_id TEXT NOT NULL,
		direction_id INTEGER NOT NULL DEFAULT 0,
		hour_of_day INTEGER NOT NULL,
		day_of_week INTEGER NOT NULL,
		median_delay_sec INTEGER NOT NULL,
		p90_delay_sec INTEGER NOT NULL,
		median_headway_sec INTEGER NOT NULL DEFAULT 0,
		headway_stddev_sec INTEGER NOT NULL DEFAULT 0,
		ewt_seconds REAL NOT NULL,
		on_time_pct REAL NOT NULL,
		sample_count INTEGER NOT NULL,
		PRIMARY KEY (route_id, stop_id, direction_id, hour_of_day, day_of_week)
	) WITHOUT ROWID;

	CREATE TABLE IF NOT EXISTS stops (
		stop_id TEXT PRIMARY KEY,
		stop_name TEXT NOT NULL,
		stop_lat REAL NOT NULL,
		stop_lon REAL NOT NULL,
		location_type INTEGER NOT NULL DEFAULT 0,
		parent_station TEXT DEFAULT NULL
	) WITHOUT ROWID;

	CREATE INDEX IF NOT EXISTS idx_stops_parent ON stops(parent_station);
	
	CREATE INDEX IF NOT EXISTS idx_stop_events_observed ON stop_events(observed_at);
	`
	
	if _, err := db.Exec(createTablesSQL); err != nil {
		return nil, fmt.Errorf("failed to create tables: %w", err)
	}

	// Migrations for pre-existing databases missing columns
	db.Exec(`ALTER TABLE stop_events ADD COLUMN direction_id INTEGER NOT NULL DEFAULT 0;`)
	db.Exec(`ALTER TABLE stop_reliability_hourly ADD COLUMN direction_id INTEGER NOT NULL DEFAULT 0;`)
	db.Exec(`ALTER TABLE stop_reliability_hourly ADD COLUMN median_headway_sec INTEGER NOT NULL DEFAULT 0;`)
	db.Exec(`ALTER TABLE stop_reliability_hourly ADD COLUMN headway_stddev_sec INTEGER NOT NULL DEFAULT 0;`)
	db.Exec(`ALTER TABLE stops ADD COLUMN parent_station TEXT DEFAULT NULL;`)
	db.Exec(`CREATE INDEX IF NOT EXISTS idx_stops_parent ON stops(parent_station);`)

	return &Database{db: db}, nil
}

// SyncStopsFromStatic copies all static stop definitions into transit_delta.sqlite
func (d *Database) SyncStopsFromStatic(staticDB *StaticDatabase) error {
	stops, err := staticDB.GetAllStops()
	if err != nil {
		return fmt.Errorf("failed to get stops from static DB: %w", err)
	}

	if len(stops) == 0 {
		log.Println("No static stops found to sync into delta DB.")
		return nil
	}

	tx, err := d.db.Begin()
	if err != nil {
		return err
	}

	stmt, err := tx.Prepare(`
		INSERT INTO stops (stop_id, stop_name, stop_lat, stop_lon, location_type, parent_station)
		VALUES (?, ?, ?, ?, ?, ?)
		ON CONFLICT(stop_id) DO UPDATE SET
			stop_name = excluded.stop_name,
			stop_lat = excluded.stop_lat,
			stop_lon = excluded.stop_lon,
			location_type = excluded.location_type,
			parent_station = excluded.parent_station;
	`)
	if err != nil {
		tx.Rollback()
		return fmt.Errorf("failed to prepare sync stops stmt: %w", err)
	}
	defer stmt.Close()

	for _, s := range stops {
		var parentStn interface{} = nil
		if s.ParentStation != "" {
			parentStn = s.ParentStation
		}
		if _, err := stmt.Exec(s.StopID, s.StopName, s.StopLat, s.StopLon, s.LocationType, parentStn); err != nil {
			log.Printf("Failed to sync stop %s into delta DB: %v", s.StopID, err)
		}
	}

	log.Printf("Successfully synced %d static stops into transit_delta.sqlite", len(stops))
	return tx.Commit()
}

// InsertEvents batch inserts stop events
func (d *Database) InsertEvents(events []processor.StopEvent) error {
	if len(events) == 0 {
		return nil
	}

	tx, err := d.db.Begin()
	if err != nil {
		return err
	}

	stmt, err := tx.Prepare(`
		INSERT INTO stop_events (event_id, trip_id, route_id, direction_id, stop_id, scheduled_time, actual_time, delay_seconds, observed_at) 
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
		ON CONFLICT(event_id) DO NOTHING;
	`)
	if err != nil {
		tx.Rollback()
		return err
	}
	defer stmt.Close()

	for _, e := range events {
		_, err = stmt.Exec(e.EventID, e.TripID, e.RouteID, e.DirectionID, e.StopID, e.ScheduledTime, e.ActualTime, e.DelaySeconds, e.ObservedAt)
		if err != nil {
			log.Printf("Failed to insert event %s: %v", e.EventID, err)
		}
	}

	return tx.Commit()
}

func (d *Database) Close() error {
	return d.db.Close()
}

