package storage

import (
	"database/sql"
	"fmt"

	_ "github.com/mattn/go-sqlite3"
)

type Database struct {
	db *sql.DB
}

func InitDB(path string) (*Database, error) {
	db, err := sql.Open("sqlite3", path)
	if err != nil {
		return nil, fmt.Errorf("failed to open database: %w", err)
	}

	// Enforce WAL mode for performance
	if _, err := db.Exec(`PRAGMA journal_mode = WAL;`); err != nil {
		return nil, fmt.Errorf("failed to set WAL mode: %w", err)
	}

	// Create tables with WITHOUT ROWID for direct clustered B-Tree indexing on string primary keys
	createTablesSQL := `
	CREATE TABLE IF NOT EXISTS reliability_stats (
		route_id TEXT NOT NULL,
		station_id TEXT NOT NULL,
		reliability_score REAL NOT NULL,
		updated_at INTEGER NOT NULL,
		PRIMARY KEY (route_id, station_id)
	) WITHOUT ROWID;
	`
	
	if _, err := db.Exec(createTablesSQL); err != nil {
		return nil, fmt.Errorf("failed to create tables: %w", err)
	}

	return &Database{db: db}, nil
}

// ExportStats saves the reliability stats into the database
func (d *Database) ExportStats(routeID, stationID string, score float64, updatedAt int64) error {
	_, err := d.db.Exec(`
		INSERT INTO reliability_stats (route_id, station_id, reliability_score, updated_at) 
		VALUES (?, ?, ?, ?)
		ON CONFLICT(route_id, station_id) DO UPDATE SET 
			reliability_score = excluded.reliability_score,
			updated_at = excluded.updated_at;
	`, routeID, stationID, score, updatedAt)
	return err
}

func (d *Database) Close() error {
	return d.db.Close()
}
