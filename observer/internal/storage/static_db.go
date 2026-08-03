package storage

import (
	"database/sql"
	"fmt"
	"log"
	"strings"

	_ "github.com/mattn/go-sqlite3"

	"observer/internal/fetcher"
)

type StaticDatabase struct {
	db *sql.DB
}

// InitStaticDB initializes the SQLite DB for GTFS static data
func InitStaticDB(path string) (*StaticDatabase, error) {
	db, err := sql.Open("sqlite3", path)
	if err != nil {
		return nil, fmt.Errorf("failed to open static database: %w", err)
	}

	if _, err := db.Exec(`PRAGMA journal_mode = WAL;`); err != nil {
		return nil, fmt.Errorf("failed to set WAL mode: %w", err)
	}

	// For bulk insert speed
	db.Exec(`PRAGMA synchronous = NORMAL;`)
	db.Exec(`PRAGMA temp_store = MEMORY;`)

	createTableSQL := `
	CREATE TABLE IF NOT EXISTS scheduled_stops (
		trip_id TEXT NOT NULL,
		stop_id TEXT NOT NULL,
		arrival_time INTEGER NOT NULL,
		PRIMARY KEY (trip_id, stop_id)
	) WITHOUT ROWID;

	CREATE TABLE IF NOT EXISTS stops (
		stop_id TEXT PRIMARY KEY,
		stop_name TEXT NOT NULL,
		stop_lat REAL NOT NULL,
		stop_lon REAL NOT NULL,
		location_type INTEGER NOT NULL DEFAULT 0
	) WITHOUT ROWID;
	`
	if _, err := db.Exec(createTableSQL); err != nil {
		return nil, fmt.Errorf("failed to create static tables: %w", err)
	}

	// We clear scheduled_stops on init because we will reload it from the latest GTFS zip
	db.Exec(`DELETE FROM scheduled_stops;`)

	return &StaticDatabase{db: db}, nil
}

// BulkInsertStopTimes inserts an array of records using a transaction and multiple values
func (d *StaticDatabase) BulkInsertStopTimes(records []fetcher.ScheduledStopTime) error {
	if len(records) == 0 {
		return nil
	}

	tx, err := d.db.Begin()
	if err != nil {
		return err
	}

	// Batch insert logic
	valueStrings := make([]string, 0, len(records))
	valueArgs := make([]interface{}, 0, len(records)*3)

	for _, r := range records {
		valueStrings = append(valueStrings, "(?, ?, ?)")
		valueArgs = append(valueArgs, r.TripID, r.StopID, r.ArrivalTime)
	}

	stmt := fmt.Sprintf("INSERT OR IGNORE INTO scheduled_stops (trip_id, stop_id, arrival_time) VALUES %s", strings.Join(valueStrings, ","))
	
	_, err = tx.Exec(stmt, valueArgs...)
	if err != nil {
		tx.Rollback()
		return fmt.Errorf("failed to execute bulk insert: %w", err)
	}

	return tx.Commit()
}

// BulkInsertStops inserts or updates GTFS static stops
func (d *StaticDatabase) BulkInsertStops(records []fetcher.GTFSStop) error {
	if len(records) == 0 {
		return nil
	}

	tx, err := d.db.Begin()
	if err != nil {
		return err
	}

	stmt, err := tx.Prepare(`
		INSERT INTO stops (stop_id, stop_name, stop_lat, stop_lon, location_type)
		VALUES (?, ?, ?, ?, ?)
		ON CONFLICT(stop_id) DO UPDATE SET
			stop_name = excluded.stop_name,
			stop_lat = excluded.stop_lat,
			stop_lon = excluded.stop_lon,
			location_type = excluded.location_type;
	`)
	if err != nil {
		tx.Rollback()
		return fmt.Errorf("failed to prepare insert stops stmt: %w", err)
	}
	defer stmt.Close()

	for _, r := range records {
		if _, err := stmt.Exec(r.StopID, r.StopName, r.StopLat, r.StopLon, r.LocationType); err != nil {
			log.Printf("Failed to insert static stop %s: %v", r.StopID, err)
		}
	}

	return tx.Commit()
}

// GetAllStops returns all stops from static database
func (d *StaticDatabase) GetAllStops() ([]fetcher.GTFSStop, error) {
	rows, err := d.db.Query(`SELECT stop_id, stop_name, stop_lat, stop_lon, location_type FROM stops`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var stops []fetcher.GTFSStop
	for rows.Next() {
		var s fetcher.GTFSStop
		if err := rows.Scan(&s.StopID, &s.StopName, &s.StopLat, &s.StopLon, &s.LocationType); err != nil {
			continue
		}
		stops = append(stops, s)
	}
	return stops, nil
}

// GetScheduledArrival looks up a scheduled arrival time
func (d *StaticDatabase) GetScheduledArrival(tripID, stopID string) (int, bool) {
	var arrivalTime int
	err := d.db.QueryRow(`
		SELECT arrival_time 
		FROM scheduled_stops 
		WHERE trip_id = ? AND stop_id = ?
	`, tripID, stopID).Scan(&arrivalTime)

	if err != nil {
		if err != sql.ErrNoRows {
			log.Printf("Error querying scheduled arrival for %s at %s: %v", tripID, stopID, err)
		}
		return 0, false
	}
	
	return arrivalTime, true
}

func (d *StaticDatabase) Close() error {
	return d.db.Close()
}

