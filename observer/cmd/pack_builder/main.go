package main

import (
	"archive/zip"
	"bytes"
	"context"
	"flag"
	"io"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"time"

	"observer/internal/builder"
	"observer/internal/fetcher"
	"observer/internal/gtfs"
	"observer/internal/pack"
	"observer/internal/raptor"
	"observer/internal/storage"
	"observer/internal/ultra"
	"observer/internal/walk"
)

func main() {
	configPath := flag.String("config", "", "Path to city_config.json (required)")
	gtfsSources := flag.String("gtfs", "", "Comma-separated GTFS zip URLs or file paths (required)")
	geojsonPath := flag.String("geojson", "", "Path to transit-lines.geojson (optional: auto-generated via Arc-Topology if omitted)")
	emitGeoJSONPath := flag.String("emit-geojson", "", "Optional path to export generated transit-lines.geojson")
	outputPath := flag.String("out", "", "Output path for city-{slug}.pack.zst (required)")
	manifestPath := flag.String("manifest", "", "Optional path to cities.json to update with new pack entry")
	anchorDateStr := flag.String("anchor", "", "Optional anchor date YYYY-MM-DD (defaults to today UTC)")
	keepDBPath := flag.String("keep-db", "", "Optional path to save intermediate uncompressed transit.sqlite")
	buildTimetable := flag.Bool("build-timetable", false, "Compile timetable.bin and bundle in pack")
	emitTimetablePath := flag.String("emit-timetable", "", "Optional path to export generated timetable.bin")
	walkGraphPath := flag.String("walk-graph", "", "Path to walk_graph.bin (optional, required if building ULTRA transfers)")
	buildUltra := flag.Bool("build-ultra", false, "Precompute ultra_transfers.csr and bundle in pack")
	emitUltraPath := flag.String("emit-ultra", "", "Optional path to export generated ultra_transfers.csr")
	deltaCheck := flag.Bool("delta-check", false, "Enable 3-tier delta checking to skip compilation if feeds are unchanged")
	deltaStatePath := flag.String("delta-state", ".feed_state.json", "Path to delta checker state file")
	uploadR2 := flag.Bool("upload-r2", false, "Upload built pack and manifest to Cloudflare R2")
	forceBuild := flag.Bool("force", false, "Force compilation even if delta check indicates no change")
	flag.Parse()

	if *configPath == "" || *gtfsSources == "" || *outputPath == "" {
		flag.Usage()
		os.Exit(1)
	}

	// 1. Resolve Anchor Date
	anchorDate := time.Now().UTC().Truncate(24 * time.Hour)
	if *anchorDateStr != "" {
		parsed, err := time.Parse("2006-01-02", *anchorDateStr)
		if err != nil {
			log.Fatalf("Invalid anchor date format %s: %v", *anchorDateStr, err)
		}
		anchorDate = parsed.UTC().Truncate(24 * time.Hour)
	}
	log.Printf("Compilation Anchor Date T0: %s", anchorDate.Format("2006-01-02"))

	// 2. Load and Validate City Config
	cfg, err := pack.LoadCityConfig(*configPath)
	if err != nil {
		log.Fatalf("Failed to load city config: %v", err)
	}
	log.Printf("Loaded config for metro: %s (%s)", cfg.DisplayName, cfg.Slug)

	// 3. Ingest GTFS Sources (with optional 3-tier delta checking)
	var deltaChecker *fetcher.DeltaChecker
	if *deltaCheck {
		dc, err := fetcher.NewDeltaChecker(*deltaStatePath, nil)
		if err != nil {
			log.Printf("Warning: failed to initialize DeltaChecker: %v", err)
		} else {
			deltaChecker = dc
		}
	}

	mergedDataset := gtfs.NewDataset(anchorDate)
	sources := strings.Split(*gtfsSources, ",")
	anyFeedModified := false
	ctx := context.Background()

	for _, src := range sources {
		src = strings.TrimSpace(src)
		if src == "" {
			continue
		}

		var zipBytes []byte
		var modified bool = true

		if deltaChecker != nil {
			data, mod, err := deltaChecker.CheckAndFetch(ctx, src)
			if err != nil {
				log.Fatalf("Delta check failed for %s: %v", src, err)
			}
			modified = mod
			zipBytes = data
		} else {
			if strings.HasPrefix(src, "http://") || strings.HasPrefix(src, "https://") {
				log.Printf("Downloading GTFS feed from %s...", src)
				resp, err := http.Get(src)
				if err != nil {
					log.Fatalf("Failed to download GTFS from %s: %v", src, err)
				}
				data, err := io.ReadAll(resp.Body)
				resp.Body.Close()
				if err != nil {
					log.Fatalf("Failed to read response body from %s: %v", src, err)
				}
				zipBytes = data
			} else {
				log.Printf("Reading local GTFS feed from %s...", src)
				data, err := os.ReadFile(src)
				if err != nil {
					log.Fatalf("Failed to read local GTFS file %s: %v", src, err)
				}
				zipBytes = data
			}
		}

		if modified {
			anyFeedModified = true
		}

		if len(zipBytes) == 0 {
			// In case 304 was returned and deltaChecker returned nil bytes, read local copy if available
			if feedState, exists := deltaChecker.GetFeedState(src); exists && feedState.ContentHash != "" {
				log.Printf("Feed %s unchanged (hash: %s).", src, feedState.ContentHash[:12])
			}
		} else {
			ds, err := gtfs.ParseGTFSArchive(bytes.NewReader(zipBytes), int64(len(zipBytes)), anchorDate)
			if err != nil {
				log.Fatalf("Failed to parse GTFS feed %s: %v", src, err)
			}

			// Merge datasets
			mergeDatasets(mergedDataset, ds)
		}
	}

	// Check if pack can be skipped
	if *deltaCheck && !anyFeedModified && !*forceBuild {
		if _, err := os.Stat(*outputPath); err == nil {
			log.Printf("All feeds unchanged and pack already exists at %s. Skipping build.", *outputPath)
			return
		}
	}

	log.Printf("Merged GTFS totals: %d agencies, %d routes, %d stops, %d trips, %d stop_time series, %d calendars, %d calendar_date overrides, %d frequency rules",
		len(mergedDataset.Agencies), len(mergedDataset.Routes), len(mergedDataset.Stops), len(mergedDataset.Trips),
		len(mergedDataset.StopTimes), len(mergedDataset.Calendars), len(mergedDataset.CalendarDates), len(mergedDataset.Frequencies))

	// 4. Compute Stop Route Associations
	stopRoutes := make(map[string]map[string]bool)
	for tripID, trip := range mergedDataset.Trips {
		if stList, ok := mergedDataset.StopTimes[tripID]; ok {
			for _, st := range stList {
				if _, ok := stopRoutes[st.StopID]; !ok {
					stopRoutes[st.StopID] = make(map[string]bool)
				}
				stopRoutes[st.StopID][trip.RouteID] = true
			}
		}
	}
	stopRoutesList := make(map[string][]string)
	for stopID, rMap := range stopRoutes {
		rList := make([]string, 0, len(rMap))
		for rID := range rMap {
			rList = append(rList, rID)
		}
		stopRoutesList[stopID] = rList
	}

	// 5. Pre-compile Stop Resolution Closure (Rules 1-4)
	log.Println("Pre-compiling reflexive transitive closure for stop resolution...")
	resolutions := gtfs.BuildStopResolutionClosure(mergedDataset.Stops)
	log.Printf("Generated %d stop_resolution rows (WITHOUT ROWID)", len(resolutions))

	// 6. Compact Timetable into Scheduled Hourly Patterns
	log.Println("Compacting schedule into scheduled_hourly_patterns (14-day calendar unrolling)...")
	patterns := gtfs.CompactDataset(mergedDataset)
	log.Printf("Generated %d scheduled_hourly_patterns rows", len(patterns))

	// 7. Create and Populate SQLite Transit Database
	tempDir, err := os.MkdirTemp("", "transit_pack_*")
	if err != nil {
		log.Fatalf("Failed to create temp dir: %v", err)
	}
	defer os.RemoveAll(tempDir)

	dbPath := filepath.Join(tempDir, "transit.sqlite")
	db, err := builder.InitTransitDB(dbPath)
	if err != nil {
		log.Fatalf("Failed to init transit DB: %v", err)
	}

	log.Println("Populating transit tables...")
	if err := builder.BulkInsertRoutes(db, mergedDataset.Routes); err != nil {
		log.Fatalf("BulkInsertRoutes failed: %v", err)
	}
	if err := builder.BulkInsertStops(db, mergedDataset.Stops, stopRoutesList); err != nil {
		log.Fatalf("BulkInsertStops failed: %v", err)
	}
	if err := builder.BulkInsertStopResolution(db, resolutions); err != nil {
		log.Fatalf("BulkInsertStopResolution failed: %v", err)
	}
	if err := builder.BulkInsertPatterns(db, patterns); err != nil {
		log.Fatalf("BulkInsertPatterns failed: %v", err)
	}

	// 8. Run Query Optimizer and ANALYZE
	log.Println("Running PRAGMA optimizer and ANALYZE to embed sqlite_stat1...")
	if err := builder.OptimizeDatabase(db); err != nil {
		log.Fatalf("OptimizeDatabase failed: %v", err)
	}
	db.Close()

	if *keepDBPath != "" {
		if err := copyFile(dbPath, *keepDBPath); err != nil {
			log.Printf("Warning: Failed to keep DB at %s: %v", *keepDBPath, err)
		} else {
			log.Printf("Saved uncompressed database to %s", *keepDBPath)
		}
	}

	// 9. Resolve / Generate Transit Lines GeoJSON
	actualGeoJSONPath := *geojsonPath
	if actualGeoJSONPath == "" || *emitGeoJSONPath != "" {
		log.Println("Generating normalized transit-lines.geojson via Planar Arc-Topology Simplification Engine...")
		fc, rawGeoJSON, err := gtfs.GenerateTransitLinesGeoJSON(mergedDataset)
		if err != nil {
			log.Fatalf("GenerateTransitLinesGeoJSON failed: %v", err)
		}
		log.Printf("Generated %d route features with 0 Z-fighting", len(fc.Features))

		if actualGeoJSONPath == "" {
			generatedPath := filepath.Join(tempDir, "transit-lines.geojson")
			if err := os.WriteFile(generatedPath, rawGeoJSON, 0644); err != nil {
				log.Fatalf("Failed to write temporary geojson: %v", err)
			}
			actualGeoJSONPath = generatedPath
		}

		if *emitGeoJSONPath != "" {
			if err := os.WriteFile(*emitGeoJSONPath, rawGeoJSON, 0644); err != nil {
				log.Fatalf("Failed to export geojson to %s: %v", *emitGeoJSONPath, err)
			}
			log.Printf("Exported transit lines GeoJSON to %s", *emitGeoJSONPath)
		}
	}

	// 10. Optional Timetable Compilation
	extraAssets := make(map[string]string)
	if *buildTimetable || *emitTimetablePath != "" {
		log.Println("Compiling RAPTOR timetable.bin with stochastic weights...")
		tt, err := raptor.CompileTimetable(mergedDataset, anchorDate)
		if err != nil {
			log.Fatalf("Failed to compile RAPTOR timetable: %v", err)
		}
		timetablePath := filepath.Join(tempDir, "timetable.bin")
		header, err := raptor.WriteTimetableFile(tt, timetablePath)
		if err != nil {
			log.Fatalf("Failed to write timetable.bin: %v", err)
		}
		log.Printf("Generated timetable.bin: %d bytes (%.2f MB, Checksum XXH64: 0x%016X)",
			header.FileSize, float64(header.FileSize)/(1024*1024), header.ChecksumXXH64)

		if *buildTimetable {
			extraAssets["timetable.bin"] = timetablePath
		}
		if *emitTimetablePath != "" {
			if err := copyFile(timetablePath, *emitTimetablePath); err != nil {
				log.Printf("Warning: Failed to export timetable to %s: %v", *emitTimetablePath, err)
			} else {
				log.Printf("Exported timetable.bin to %s", *emitTimetablePath)
			}
		}
	}

	// 10b. Optional ULTRA Transfer Shortcut Precomputation
	if *buildUltra || *emitUltraPath != "" {
		if *walkGraphPath == "" {
			log.Fatalf("--walk-graph is required when --build-ultra or --emit-ultra is specified")
		}
		log.Printf("Reading walk graph from %s for ULTRA precomputation...", *walkGraphPath)
		fWalk, err := os.Open(*walkGraphPath)
		if err != nil {
			log.Fatalf("Failed to open walk graph %s: %v", *walkGraphPath, err)
		}
		fiWalk, err := fWalk.Stat()
		if err != nil {
			log.Fatalf("Failed to stat walk graph %s: %v", *walkGraphPath, err)
		}
		walkView, err := walk.ReadWalkGraph(fWalk, fiWalk.Size())
		fWalk.Close()
		if err != nil {
			log.Fatalf("Failed to parse walk graph: %v", err)
		}

		// Ensure timetable is compiled
		tt, err := raptor.CompileTimetable(mergedDataset, anchorDate)
		if err != nil {
			log.Fatalf("Failed to compile timetable for ULTRA: %v", err)
		}

		compiledWalk := &walk.CompiledWalkGraph{
			Nodes: walkView.Nodes,
			Edges: walkView.Edges,
		}

		ultraPath := filepath.Join(tempDir, "ultra_transfers.csr")
		cfg := ultra.DefaultPrecomputeConfig()
		cfg.TempDir = tempDir

		log.Println("Precomputing ULTRA transfer shortcuts (< 35 MB RSS)...")
		stats, err := ultra.PrecomputeUltraTransfers(compiledWalk, tt, ultraPath, cfg)
		if err != nil {
			log.Fatalf("ULTRA precomputation failed: %v", err)
		}
		log.Printf("Generated ultra_transfers.csr: %d shortcuts (%.2f MB)", stats.TotalShortcuts, float64(stats.OutputSizeBytes)/(1024*1024))

		if *buildUltra {
			extraAssets["ultra_transfers.csr"] = ultraPath
		}
		if *emitUltraPath != "" {
			if err := copyFile(ultraPath, *emitUltraPath); err != nil {
				log.Printf("Warning: Failed to export ultra transfers to %s: %v", *emitUltraPath, err)
			} else {
				log.Printf("Exported ultra_transfers.csr to %s", *emitUltraPath)
			}
		}
	}

	// 11. Package into .pack.zst
	log.Printf("Packaging city pack to %s...", *outputPath)
	if err := os.MkdirAll(filepath.Dir(*outputPath), 0755); err != nil {
		log.Fatalf("Failed to create output directory: %v", err)
	}

	manifestEntry, err := pack.CreateCityPackWithAssets(*configPath, dbPath, actualGeoJSONPath, extraAssets, *outputPath)
	if err != nil {
		log.Fatalf("Failed to create city pack: %v", err)
	}

	// 12. Verify Pack
	if err := pack.VerifyCityPack(*outputPath); err != nil {
		log.Fatalf("Pack verification failed: %v", err)
	}

	log.Printf("✅ Pack build successful!")
	log.Printf("  Slug:               %s", manifestEntry.Slug)
	log.Printf("  Uncompressed Size:  %.2f MB (%d bytes)", float64(manifestEntry.UncompressedSizeBytes)/(1024*1024), manifestEntry.UncompressedSizeBytes)
	log.Printf("  Compressed Size:    %.2f MB (%d bytes)", float64(manifestEntry.CompressedSizeBytes)/(1024*1024), manifestEntry.CompressedSizeBytes)
	log.Printf("  SHA-256 Hash:       %s", manifestEntry.SHA256)

	// 12. Update manifest if requested
	if *manifestPath != "" {
		updateManifest(*manifestPath, manifestEntry)
	}

	// 13. Upload to Cloudflare R2 if requested
	if *uploadR2 {
		log.Printf("Uploading %s to Cloudflare R2...", *outputPath)
		packKey := filepath.Base(*outputPath)
		if err := storage.UploadFileToR2(*outputPath, packKey, "application/zstd"); err != nil {
			log.Fatalf("Failed to upload pack to R2: %v", err)
		}
		log.Printf("✅ Uploaded %s to R2", packKey)

		if *manifestPath != "" {
			log.Printf("Uploading updated manifest %s to Cloudflare R2...", *manifestPath)
			if err := storage.UploadFileToR2(*manifestPath, "cities.json", "application/json"); err != nil {
				log.Fatalf("Failed to upload manifest to R2: %v", err)
			}
			log.Printf("✅ Uploaded cities.json to R2")
		}
	}
}

func mergeDatasets(target, src *gtfs.Dataset) {
	for k, v := range src.Agencies {
		target.Agencies[k] = v
	}
	for k, v := range src.Routes {
		target.Routes[k] = v
	}
	for k, v := range src.Stops {
		target.Stops[k] = v
	}
	for k, v := range src.Trips {
		target.Trips[k] = v
	}
	for k, v := range src.StopTimes {
		target.StopTimes[k] = v
	}
	for k, v := range src.Shapes {
		target.Shapes[k] = v
	}
	for k, v := range src.Calendars {
		target.Calendars[k] = v
	}
	for k, v := range src.CalendarDates {
		target.CalendarDates[k] = append(target.CalendarDates[k], v...)
	}
	for k, v := range src.Frequencies {
		target.Frequencies[k] = append(target.Frequencies[k], v...)
	}
}

func updateManifest(manifestPath string, newEntry *pack.CityManifestEntry) {
	var manifest pack.CitiesManifest
	if _, err := os.Stat(manifestPath); err == nil {
		loaded, err := pack.LoadCitiesManifest(manifestPath)
		if err == nil {
			manifest = *loaded
		}
	}

	if manifest.Version == 0 {
		manifest.Version = 1
	}
	manifest.LastUpdated = time.Now().UTC().Format(time.RFC3339)

	found := false
	for i, c := range manifest.Cities {
		if c.Slug == newEntry.Slug {
			manifest.Cities[i] = *newEntry
			found = true
			break
		}
	}
	if !found {
		manifest.Cities = append(manifest.Cities, *newEntry)
	}

	if err := pack.SaveCitiesManifest(&manifest, manifestPath); err != nil {
		log.Printf("Warning: Failed to update manifest at %s: %v", manifestPath, err)
	} else {
		log.Printf("Updated manifest at %s", manifestPath)
	}
}

func copyFile(src, dst string) error {
	in, err := os.Open(src)
	if err != nil {
		return err
	}
	defer in.Close()

	out, err := os.Create(dst)
	if err != nil {
		return err
	}
	defer out.Close()

	_, err = io.Copy(out, in)
	return err
}

func createDummyZip() []byte {
	buf := new(bytes.Buffer)
	zw := zip.NewWriter(buf)
	zw.Close()
	return buf.Bytes()
}
