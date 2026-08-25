package builder

import (
	"database/sql"
	"fmt"

	_ "github.com/mattn/go-sqlite3"
)

// OptimizeDatabase runs query optimizer analysis and page defragmentation on the target database
func OptimizeDatabase(db *sql.DB) error {
	if _, err := db.Exec("PRAGMA analysis_limit = 1000;"); err != nil {
		return fmt.Errorf("failed to set PRAGMA analysis_limit: %w", err)
	}

	if _, err := db.Exec("ANALYZE;"); err != nil {
		return fmt.Errorf("failed to execute ANALYZE: %w", err)
	}

	if _, err := db.Exec("PRAGMA optimize(0x10000);"); err != nil {
		return fmt.Errorf("failed to execute PRAGMA optimize: %w", err)
	}

	if _, err := db.Exec("VACUUM;"); err != nil {
		return fmt.Errorf("failed to execute VACUUM: %w", err)
	}

	// Verify sqlite_stat1 exists and is populated
	var stat1Count int
	err := db.QueryRow("SELECT COUNT(*) FROM sqlite_stat1").Scan(&stat1Count)
	if err != nil {
		return fmt.Errorf("failed to query sqlite_stat1: %w", err)
	}

	if stat1Count == 0 {
		return fmt.Errorf("warning: sqlite_stat1 is empty after ANALYZE")
	}

	return nil
}

// OptimizeDatabaseFile opens a database file, optimizes it, and closes it
func OptimizeDatabaseFile(dbPath string) error {
	db, err := sql.Open("sqlite3", dbPath)
	if err != nil {
		return fmt.Errorf("failed to open database %s: %w", dbPath, err)
	}
	defer db.Close()

	return OptimizeDatabase(db)
}
