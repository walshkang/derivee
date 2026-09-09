package builder

import (
	"database/sql"
	"fmt"
	"strings"

	_ "github.com/mattn/go-sqlite3"

	"observer/internal/gtfs"
)

// InitTransitDB initializes a new SQLite transit database with target schema
func InitTransitDB(dbPath string) (*sql.DB, error) {
	db, err := sql.Open("sqlite3", dbPath+"?_journal_mode=OFF&_synchronous=OFF")
	if err != nil {
		return nil, fmt.Errorf("failed to open database %s: %w", dbPath, err)
	}

	schemaSQL := `
	CREATE TABLE stops (
		stop_id TEXT PRIMARY KEY,
		stop_name TEXT NOT NULL,
		stop_lat REAL NOT NULL,
		stop_lon REAL NOT NULL,
		location_type INTEGER NOT NULL DEFAULT 0,
		routes TEXT NOT NULL DEFAULT "",
		parent_station TEXT DEFAULT NULL
	);
	CREATE INDEX idx_stops_coords ON stops(stop_lat, stop_lon);
	CREATE INDEX idx_stops_loc_type ON stops(location_type);
	CREATE INDEX idx_stops_parent ON stops(parent_station);

	CREATE TABLE routes (
		route_id TEXT PRIMARY KEY,
		agency_id TEXT,
		route_short_name TEXT NOT NULL,
		route_long_name TEXT,
		route_type INTEGER NOT NULL,
		route_color TEXT,
		route_text_color TEXT
	);

	CREATE TABLE complexes (
		complex_id          INTEGER NOT NULL,
		complex_name        TEXT    NOT NULL,
		borough             TEXT,
		latitude            REAL    NOT NULL,
		longitude           REAL    NOT NULL,
		is_hub              INTEGER NOT NULL DEFAULT 0 CHECK(is_hub IN (0, 1)),
		PRIMARY KEY (complex_id)
	) WITHOUT ROWID;

	CREATE TABLE stop_resolution (
		complex_id          INTEGER NOT NULL,
		feed_id             TEXT    NOT NULL,
		parent_station_id   TEXT    NOT NULL,
		child_stop_id       TEXT    NOT NULL,
		platform_code       TEXT,
		direction_id        INTEGER CHECK(direction_id IN (0, 1, NULL)),
		wheelchair_boarding INTEGER NOT NULL DEFAULT 0 CHECK(wheelchair_boarding IN (0, 1, 2)),
		PRIMARY KEY (complex_id, feed_id, parent_station_id, child_stop_id)
	) WITHOUT ROWID;
	CREATE UNIQUE INDEX idx_stop_resolution_reverse 
	ON stop_resolution (feed_id, child_stop_id, complex_id, parent_station_id);
	CREATE INDEX idx_stop_resolution_parent
	ON stop_resolution (feed_id, parent_station_id, complex_id);

	CREATE TABLE scheduled_hourly_patterns (
		stop_id TEXT NOT NULL,
		route_id TEXT NOT NULL,
		direction_id INTEGER NOT NULL,
		hour_of_day INTEGER NOT NULL,
		service_mask INTEGER NOT NULL,
		baseline_days_of_week INTEGER NOT NULL,
		minute_offsets TEXT NOT NULL,
		headsign TEXT NOT NULL,
		PRIMARY KEY (stop_id, route_id, direction_id, hour_of_day, service_mask)
	);
	CREATE INDEX idx_patterns_lookup ON scheduled_hourly_patterns(stop_id, route_id, direction_id);

	CREATE TABLE headway_history (
		stop_id TEXT NOT NULL,
		day_offset INTEGER NOT NULL,
		headway_min REAL NOT NULL,
		PRIMARY KEY (stop_id, day_offset)
	);

	CREATE TABLE stop_events (
		event_id TEXT PRIMARY KEY,
		trip_id TEXT NOT NULL,
		route_id TEXT NOT NULL,
		stop_id TEXT NOT NULL,
		scheduled_time INTEGER,
		actual_time INTEGER NOT NULL,
		delay_seconds INTEGER NOT NULL,
		observed_at INTEGER NOT NULL,
		direction_id INTEGER NOT NULL DEFAULT 0
	);
	CREATE INDEX idx_stop_events_observed ON stop_events(observed_at);

	CREATE TABLE stop_reliability_hourly (
		route_id TEXT NOT NULL,
		stop_id TEXT NOT NULL,
		hour_of_day INTEGER NOT NULL,
		day_of_week INTEGER NOT NULL,
		median_delay_sec INTEGER NOT NULL,
		p90_delay_sec INTEGER NOT NULL,
		ewt_seconds REAL NOT NULL,
		on_time_pct REAL NOT NULL,
		sample_count INTEGER NOT NULL,
		direction_id INTEGER NOT NULL DEFAULT 0,
		median_headway_sec INTEGER NOT NULL DEFAULT 0,
		headway_stddev_sec INTEGER NOT NULL DEFAULT 0,
		PRIMARY KEY (route_id, stop_id, hour_of_day, day_of_week)
	);
	`

	if _, err := db.Exec(schemaSQL); err != nil {
		db.Close()
		return nil, fmt.Errorf("failed to create schema: %w", err)
	}

	return db, nil
}

// BulkInsertStops populates the stops table
func BulkInsertStops(db *sql.DB, stops map[string]gtfs.Stop, stopRoutes map[string][]string) error {
	tx, err := db.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()

	stmt, err := tx.Prepare(`
		INSERT INTO stops (stop_id, stop_name, stop_lat, stop_lon, location_type, routes, parent_station)
		VALUES (?, ?, ?, ?, ?, ?, ?)
	`)
	if err != nil {
		return err
	}
	defer stmt.Close()

	for stopID, s := range stops {
		var routesStr string
		if rList, ok := stopRoutes[stopID]; ok && len(rList) > 0 {
			routesStr = strings.Join(rList, ",")
		}

		var parentStation interface{} = nil
		if s.ParentStation != "" {
			parentStation = s.ParentStation
		}

		if _, err := stmt.Exec(s.StopID, s.StopName, s.StopLat, s.StopLon, s.LocationType, routesStr, parentStation); err != nil {
			return fmt.Errorf("failed to insert stop %s: %w", s.StopID, err)
		}
	}

	return tx.Commit()
}

// BulkInsertRoutes populates the routes table
func BulkInsertRoutes(db *sql.DB, routes map[string]gtfs.Route) error {
	tx, err := db.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()

	stmt, err := tx.Prepare(`
		INSERT OR REPLACE INTO routes (route_id, agency_id, route_short_name, route_long_name, route_type, route_color, route_text_color)
		VALUES (?, ?, ?, ?, ?, ?, ?)
	`)
	if err != nil {
		return err
	}
	defer stmt.Close()

	for _, r := range routes {
		if _, err := stmt.Exec(r.RouteID, r.AgencyID, r.RouteShortName, r.RouteLongName, r.RouteType, r.RouteColor, r.RouteTextColor); err != nil {
			return fmt.Errorf("failed to insert route %s: %w", r.RouteID, err)
		}
	}

	return tx.Commit()
}

// BulkInsertComplexes populates the complexes table
func BulkInsertComplexes(db *sql.DB, complexes []gtfs.Complex) error {
	tx, err := db.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()

	stmt, err := tx.Prepare(`
		INSERT INTO complexes (complex_id, complex_name, borough, latitude, longitude, is_hub)
		VALUES (?, ?, ?, ?, ?, ?)
		ON CONFLICT(complex_id) DO UPDATE SET
			complex_name = excluded.complex_name,
			borough = COALESCE(excluded.borough, complexes.borough),
			latitude = (complexes.latitude + excluded.latitude) / 2.0,
			longitude = (complexes.longitude + excluded.longitude) / 2.0,
			is_hub = max(complexes.is_hub, excluded.is_hub);
	`)
	if err != nil {
		return err
	}
	defer stmt.Close()

	for _, c := range complexes {
		var borough interface{} = nil
		if c.Borough != "" {
			borough = c.Borough
		}
		if _, err := stmt.Exec(c.ComplexID, c.ComplexName, borough, c.Latitude, c.Longitude, c.IsHub); err != nil {
			return fmt.Errorf("failed to insert complex %d: %w", c.ComplexID, err)
		}
	}

	return tx.Commit()
}

// BulkInsertStopResolution populates the stop_resolution table
func BulkInsertStopResolution(db *sql.DB, resolutions []gtfs.StopResolution) error {
	tx, err := db.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()

	stmt, err := tx.Prepare(`
		INSERT OR REPLACE INTO stop_resolution (
			complex_id, feed_id, parent_station_id, child_stop_id,
			platform_code, direction_id, wheelchair_boarding
		)
		VALUES (?, ?, ?, ?, ?, ?, ?)
	`)
	if err != nil {
		return err
	}
	defer stmt.Close()

	for _, r := range resolutions {
		var platform interface{} = nil
		if r.PlatformCode != "" {
			platform = r.PlatformCode
		}

		parentStation := r.ParentStationID
		if parentStation == "" {
			parentStation = r.ParentStopID
		}
		feedID := r.FeedID
		if feedID == "" {
			feedID = "subway"
		}

		var direction interface{} = nil
		if r.DirectionID != nil {
			direction = *r.DirectionID
		}

		if _, err := stmt.Exec(r.ComplexID, feedID, parentStation, r.ChildStopID, platform, direction, r.WheelchairBoarding); err != nil {
			return fmt.Errorf("failed to insert stop_resolution (%d, %s, %s, %s): %w", r.ComplexID, feedID, parentStation, r.ChildStopID, err)
		}
	}

	return tx.Commit()
}

// BulkInsertPatterns populates the scheduled_hourly_patterns table in batches
func BulkInsertPatterns(db *sql.DB, patterns []gtfs.ScheduledHourlyPattern) error {
	const batchSize = 2000
	for i := 0; i < len(patterns); i += batchSize {
		end := i + batchSize
		if end > len(patterns) {
			end = len(patterns)
		}

		tx, err := db.Begin()
		if err != nil {
			return err
		}

		stmt, err := tx.Prepare(`
			INSERT OR REPLACE INTO scheduled_hourly_patterns 
			(stop_id, route_id, direction_id, hour_of_day, service_mask, baseline_days_of_week, minute_offsets, headsign)
			VALUES (?, ?, ?, ?, ?, ?, ?, ?)
		`)
		if err != nil {
			tx.Rollback()
			return err
		}

		for _, p := range patterns[i:end] {
			if _, err := stmt.Exec(p.StopID, p.RouteID, p.DirectionID, p.HourOfDay, p.ServiceMask, p.BaselineDaysOfWeek, p.MinuteOffsets, p.Headsign); err != nil {
				stmt.Close()
				tx.Rollback()
				return fmt.Errorf("failed to insert pattern (%s, %s, h=%d): %w", p.StopID, p.RouteID, p.HourOfDay, err)
			}
		}

		stmt.Close()
		if err := tx.Commit(); err != nil {
			return err
		}
	}

	return nil
}
