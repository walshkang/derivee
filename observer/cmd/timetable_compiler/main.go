package main

import (
	"archive/zip"
	"bytes"
	"flag"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"time"

	"observer/internal/gtfs"
	"observer/internal/raptor"
)

func main() {
	gtfsSources := flag.String("gtfs", "", "Comma-separated GTFS zip URLs or local file paths (required)")
	outPath := flag.String("out", "timetable.bin", "Path to output timetable.bin file")
	anchorDateStr := flag.String("anchor", "", "Optional anchor date YYYY-MM-DD (defaults to today UTC)")
	validate := flag.Bool("validate", true, "Validate output binary after compilation")
	stats := flag.Bool("stats", true, "Print detailed timetable statistics")
	flag.Parse()

	if *gtfsSources == "" {
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
	log.Printf("[timetable_compiler] Compilation Anchor Date T0: %s", anchorDate.Format("2006-01-02"))

	// 2. Ingest GTFS Feeds
	mergedDataset := gtfs.NewDataset(anchorDate)
	sources := strings.Split(*gtfsSources, ",")

	for _, src := range sources {
		src = strings.TrimSpace(src)
		if src == "" {
			continue
		}

		var zipBytes []byte
		if strings.HasPrefix(src, "http://") || strings.HasPrefix(src, "https://") {
			log.Printf("[timetable_compiler] Downloading GTFS feed from %s...", src)
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
			log.Printf("[timetable_compiler] Reading local GTFS feed from %s...", src)
			data, err := os.ReadFile(src)
			if err != nil {
				log.Fatalf("Failed to read local GTFS file %s: %v", src, err)
			}
			zipBytes = data
		}

		ds, err := gtfs.ParseGTFSArchive(bytes.NewReader(zipBytes), int64(len(zipBytes)), anchorDate)
		if err != nil {
			log.Fatalf("Failed to parse GTFS feed %s: %v", src, err)
		}

		mergeDatasets(mergedDataset, ds)
	}

	log.Printf("[timetable_compiler] Ingested GTFS totals: %d stops, %d routes, %d trips, %d stop_time series, %d calendars",
		len(mergedDataset.Stops), len(mergedDataset.Routes), len(mergedDataset.Trips),
		len(mergedDataset.StopTimes), len(mergedDataset.Calendars))

	// 3. Compile RAPTOR Timetable
	compileStart := time.Now()
	log.Printf("[timetable_compiler] Compiling RAPTOR Route Patterns and Stochastic Weights...")
	tt, err := raptor.CompileTimetable(mergedDataset, anchorDate)
	if err != nil {
		log.Fatalf("Failed to compile timetable: %v", err)
	}
	compileDuration := time.Since(compileStart)
	log.Printf("[timetable_compiler] Timetable compiled in %v: %d stops, %d route patterns, %d trips, %d stop times, %d transfers",
		compileDuration, len(tt.Stops), len(tt.Routes), len(tt.Trips), len(tt.StopTimes), len(tt.Transfers))

	// 4. Serialize to Binary
	if err := os.MkdirAll(filepath.Dir(*outPath), 0755); err != nil && filepath.Dir(*outPath) != "." {
		log.Fatalf("Failed to create output directory: %v", err)
	}

	log.Printf("[timetable_compiler] Serializing binary timetable to %s...", *outPath)
	header, err := raptor.WriteTimetableFile(tt, *outPath)
	if err != nil {
		log.Fatalf("Failed to write timetable binary: %v", err)
	}

	fileSizeMB := float64(header.FileSize) / (1024.0 * 1024.0)
	log.Printf("[timetable_compiler] ✅ Wrote %d bytes (%.2f MB) to %s (Checksum XXH64: 0x%016X)",
		header.FileSize, fileSizeMB, *outPath, header.ChecksumXXH64)

	// 5. Validation
	if *validate {
		log.Printf("[timetable_compiler] Validating generated binary %s...", *outPath)
		f, err := os.Open(*outPath)
		if err != nil {
			log.Fatalf("Failed to open output file for validation: %v", err)
		}
		defer f.Close()

		fi, err := f.Stat()
		if err != nil {
			log.Fatalf("Failed to stat output file: %v", err)
		}

		view, err := raptor.ReadTimetable(f, fi.Size())
		if err != nil {
			log.Fatalf("Binary validation failed: %v", err)
		}

		if len(view.Stops) != len(tt.Stops) || len(view.Routes) != len(tt.Routes) || len(view.Trips) != len(tt.Trips) {
			log.Fatalf("Validation element count mismatch!")
		}
		log.Printf("[timetable_compiler] ✅ Validation passed: All %d sections verified with matching xxHash64 checksum.", header.NumSections)
	}

	// 6. Statistics
	if *stats {
		fmt.Println("\n================ RAPTOR Timetable Summary ================")
		fmt.Printf("  Binary File:             %s\n", *outPath)
		fmt.Printf("  Binary File Size:        %.3f MB (%d bytes)\n", fileSizeMB, header.FileSize)
		fmt.Printf("  Header Size:             %d bytes (TOC Sections: %d)\n", header.HeaderSize, header.NumSections)
		fmt.Printf("  Payload Checksum XXH64:  0x%016X\n", header.ChecksumXXH64)
		fmt.Printf("  Stops:                   %d\n", len(tt.Stops))
		fmt.Printf("  Route Patterns:          %d\n", len(tt.Routes))
		fmt.Printf("  Trips:                   %d\n", len(tt.Trips))
		fmt.Printf("  Stop Times:              %d\n", len(tt.StopTimes))
		fmt.Printf("  Intra Transfers:         %d\n", len(tt.Transfers))
		fmt.Printf("  Route-Stops Array:       %d entries\n", len(tt.RouteStops))
		fmt.Printf("  Stop-Routes Index:       %d entries\n", len(tt.StopRoutes))
		fmt.Printf("  Stochastic Weights:      %d slots (168 slots/route)\n", len(tt.StochasticWeights))
		fmt.Println("==========================================================")
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

func createDummyZip() []byte {
	buf := new(bytes.Buffer)
	zw := zip.NewWriter(buf)
	zw.Close()
	return buf.Bytes()
}
