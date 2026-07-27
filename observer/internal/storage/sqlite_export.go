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
		stop_id TEXT NOT NULL,
		scheduled_time INTEGER,
		actual_time INTEGER NOT NULL,
		delay_seconds INTEGER NOT NULL,
		observed_at INTEGER NOT NULL
	) WITHOUT ROWID;

	CREATE TABLE IF NOT EXISTS stop_reliability_hourly (
		route_id TEXT NOT NULL,
		stop_id TEXT NOT NULL,
		hour_of_day INTEGER NOT NULL,
		day_of_week INTEGER NOT NULL,
		median_delay_sec INTEGER NOT NULL,
		p90_delay_sec INTEGER NOT NULL,
		ewt_seconds REAL NOT NULL,
		on_time_pct REAL NOT NULL,
		sample_count INTEGER NOT NULL,
		PRIMARY KEY (route_id, stop_id, hour_of_day, day_of_week)
	) WITHOUT ROWID;
	
	CREATE INDEX IF NOT EXISTS idx_stop_events_observed ON stop_events(observed_at);
	`
	
	if _, err := db.Exec(createTablesSQL); err != nil {
		return nil, fmt.Errorf("failed to create tables: %w", err)
	}

	return &Database{db: db}, nil
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
		INSERT INTO stop_events (event_id, trip_id, route_id, stop_id, scheduled_time, actual_time, delay_seconds, observed_at) 
		VALUES (?, ?, ?, ?, ?, ?, ?, ?)
		ON CONFLICT(event_id) DO NOTHING;
	`)
	if err != nil {
		tx.Rollback()
		return err
	}
	defer stmt.Close()

	for _, e := range events {
		_, err = stmt.Exec(e.EventID, e.TripID, e.RouteID, e.StopID, e.ScheduledTime, e.ActualTime, e.DelaySeconds, e.ObservedAt)
		if err != nil {
			log.Printf("Failed to insert event %s: %v", e.EventID, err)
		}
	}

	return tx.Commit()
}

func (d *Database) Close() error {
	return d.db.Close()
}
