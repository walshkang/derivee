package main

import (
	"log"
	"os"
	"os/signal"
	"syscall"
	"time"

	"observer/internal/fetcher"
	"observer/internal/processor"
	"observer/internal/storage"

	"github.com/joho/godotenv"
)

const (
	DefaultPollInterval = 3 * time.Minute
	DBPath              = "transit_delta.sqlite"
	ZstPath             = "transit_delta.sqlite.zst"
	StaticDBPath        = "static_gtfs.sqlite"
	MTASubwayStaticURL  = "http://web.mta.info/developers/data/nyct/subway/google_transit.zip"
	MTABusStaticURL     = "http://web.mta.info/developers/data/busco/google_transit.zip"
)

func main() {
	// Load environment variables from .env file
	if err := godotenv.Load(); err != nil {
		log.Println("No .env file found, relying on system environment variables")
	}

	pollInterval := DefaultPollInterval
	if intervalStr := os.Getenv("POLL_INTERVAL"); intervalStr != "" {
		if d, err := time.ParseDuration(intervalStr); err == nil && d >= 10*time.Second {
			pollInterval = d
			log.Printf("Using configured poll interval: %v", pollInterval)
		}
	}

	var durationLimit time.Duration
	if durStr := os.Getenv("OBSERVER_DURATION"); durStr != "" {
		if d, err := time.ParseDuration(durStr); err == nil && d > 0 {
			durationLimit = d
			log.Printf("Observer will run for duration: %v", durationLimit)
		}
	}

	// 1. Setup Delta SQLite Database
	db, err := storage.InitDB(DBPath)
	if err != nil {
		log.Fatalf("Failed to initialize delta database: %v", err)
	}
	defer db.Close()

	// 2. Setup Static SQLite Database
	staticDB, err := storage.InitStaticDB(StaticDBPath)
	if err != nil {
		log.Fatalf("Failed to initialize static GTFS database: %v", err)
	}
	defer staticDB.Close()

	// 3. Load GTFS Static Schedules & Stops into Static DB if needed
	staticCount, _ := staticDB.CountScheduledStops()
	if staticCount == 0 || os.Getenv("RELOAD_STATIC") == "true" {
		log.Printf("Static schedule has %d entries (or RELOAD_STATIC set). Reloading static GTFS...", staticCount)
		if staticCount > 0 {
			if err := staticDB.ClearScheduledStops(); err != nil {
				log.Printf("Warning: failed to clear static stops: %v", err)
			}
		}

		log.Println("Loading Subway Static Schedule & Stops...")
		if err := fetcher.FetchAndParseStaticGTFS(MTASubwayStaticURL, staticDB.BulkInsertStopTimes, staticDB.BulkInsertStops); err != nil {
			log.Printf("Warning: Failed to load subway static GTFS. Error: %v", err)
		} else {
			log.Println("Syncing subway static stops into delta database...")
			if err := db.SyncStopsFromStatic(staticDB); err != nil {
				log.Printf("Warning: Failed to sync subway stops to delta DB: %v", err)
			}
		}

		log.Println("Loading Bus Static Schedule & Stops...")
		if err := fetcher.FetchAndParseStaticGTFS(MTABusStaticURL, staticDB.BulkInsertStopTimes, staticDB.BulkInsertStops); err != nil {
			log.Printf("Warning: Failed to load bus static GTFS. Error: %v", err)
		} else {
			log.Println("Syncing bus static stops into delta database...")
			if err := db.SyncStopsFromStatic(staticDB); err != nil {
				log.Printf("Warning: Failed to sync bus stops to delta DB: %v", err)
			}
		}
	} else {
		log.Printf("Static GTFS database already populated with %d scheduled stops. Ready.", staticCount)
	}

	// 4. Initialize Stop Event Engine with SQLite Backend
	engine := processor.NewStopEventEngine(staticDB)

	log.Printf("Starting The Observer daemon (Poll interval: %v)...", pollInterval)

	sigChan := make(chan os.Signal, 1)
	signal.Notify(sigChan, os.Interrupt, syscall.SIGTERM)

	var stopTimer <-chan time.Time
	if durationLimit > 0 {
		stopTimer = time.After(durationLimit)
	}

	ticker := time.NewTicker(pollInterval)
	defer ticker.Stop()

	// Initial run before ticker
	pollAndProcess(engine, db, staticDB)

	for {
		select {
		case <-sigChan:
			log.Println("Received termination signal. Observer shutting down gracefully...")
			return
		case <-stopTimer:
			log.Printf("Configured duration of %v reached. Observer shutting down gracefully...", durationLimit)
			return
		case <-ticker.C:
			pollAndProcess(engine, db, staticDB)
		}
	}
}

func pollAndProcess(engine *processor.StopEventEngine, db *storage.Database, staticDB *storage.StaticDatabase) {
	log.Println("Polling MTA feeds...")

	// 1. Fetch Subways
	subwayFeed, err := fetcher.FetchSubwayGTFS()
	if err != nil {
		log.Printf("Error fetching subways: %v", err)
	} else {
		updates := fetcher.ParseTripUpdates(subwayFeed)
		engine.ProcessUpdates(updates)
		log.Printf("Processed %d subway updates", len(updates))
	}

	// 2. Fetch Buses (GTFS-RT)
	busFeed, err := fetcher.FetchBusGTFS()
	if err != nil {
		log.Printf("Error fetching buses: %v", err)
	} else {
		updates := fetcher.ParseTripUpdates(busFeed)
		engine.ProcessUpdates(updates)
		log.Printf("Processed %d bus updates", len(updates))
	}

	// 3. Drain and insert newly finalized stop events
	events := engine.DrainEvents()
	if len(events) > 0 {
		log.Printf("Inserting %d completed stop events...", len(events))
		err = db.InsertEvents(events)
		if err != nil {
			log.Printf("Error inserting events: %v", err)
		}
	} else {
		log.Println("No completed stop events this cycle.")
	}

	// 4. Aggregate hourly percentiles & EWT
	log.Println("Aggregating historical percentiles...")
	err = db.AggregateDailyStats()
	if err != nil {
		log.Printf("Error aggregating stats: %v", err)
	}

	// 5. Ensure stops table is populated in delta DB before export
	if err := db.SyncStopsFromStatic(staticDB); err != nil {
		log.Printf("Warning: Failed to sync stops into delta DB: %v", err)
	}

	// 6. Compress
	log.Println("Compressing SQLite database...")
	err = storage.CompressSQLite(DBPath, ZstPath)
	if err != nil {
		log.Printf("Error compressing database: %v", err)
		return
	}

	// 7. Upload to R2 (CDN Handoff)
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

