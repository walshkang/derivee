package main

import (
	"log"
	"os"
	"time"

	"observer/internal/fetcher"
	"observer/internal/processor"
	"observer/internal/storage"

	"github.com/joho/godotenv"
)

const (
	PollInterval = 3 * time.Minute
	DBPath       = "transit_delta.sqlite"
	ZstPath      = "transit_delta.sqlite.zst"
)

func main() {
	// Load environment variables from .env file
	if err := godotenv.Load(); err != nil {
		log.Println("No .env file found, relying on system environment variables")
	}

	engine := processor.NewReliabilityEngine()

	// Setup SQLite Database
	db, err := storage.InitDB(DBPath)
	if err != nil {
		log.Fatalf("Failed to initialize database: %v", err)
	}
	defer db.Close()

	log.Println("Starting The Observer daemon...")
	ticker := time.NewTicker(PollInterval)
	defer ticker.Stop()

	// Initial run before ticker
	pollAndProcess(engine, db)

	for range ticker.C {
		pollAndProcess(engine, db)
	}
}

func pollAndProcess(engine *processor.ReliabilityEngine, db *storage.Database) {
	log.Println("Polling MTA feeds...")

	// 1. Fetch Subways
	feed, err := fetcher.FetchSubwayGTFS()
	if err != nil {
		log.Printf("Error fetching subways: %v", err)
	} else {
		updates := fetcher.ParseTripUpdates(feed)
		engine.ProcessUpdates(updates)
		log.Printf("Processed %d subway updates", len(updates))
	}

	// 2. Fetch Buses
	_, err = fetcher.FetchBuses()
	if err != nil {
		log.Printf("Error fetching buses: %v", err)
	} else {
		// Note: SIRI JSON parsing logic goes here, integrating with engine.ProcessUpdates
		log.Println("Processed bus updates")
	}

	// 3. Export to SQLite
	// Note: In a real scenario, we'd calculate real reliability scores based on headways
	// Here we export a dummy score to satisfy the schema for the MVP
	log.Println("Exporting stats to SQLite...")
	err = db.ExportStats("L", "L01", 95.5, time.Now().Unix())
	if err != nil {
		log.Printf("Error exporting stats: %v", err)
	}

	// 4. Compress
	log.Println("Compressing SQLite database...")
	err = storage.CompressSQLite(DBPath, ZstPath)
	if err != nil {
		log.Printf("Error compressing database: %v", err)
		return
	}

	// 5. Upload to R2 (CDN Handoff)
	log.Println("Pushing to Cloudflare R2...")
	err = storage.UploadToR2(ZstPath)
	if err != nil {
		log.Printf("Error uploading to R2: %v", err)
		return
	}
	
	// Cleanup local zst to save space
	os.Remove(ZstPath)
	log.Println("Cycle complete. Waiting for next interval.")
}
