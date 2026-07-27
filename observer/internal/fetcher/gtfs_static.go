package fetcher

import (
	"archive/zip"
	"bytes"
	"encoding/csv"
	"fmt"
	"io"
	"log"
	"net/http"
	"strconv"
	"strings"
)

// ScheduledStopTime holds a parsed static record
type ScheduledStopTime struct {
	TripID      string
	StopID      string
	ArrivalTime int
}

// FetchAndParseStaticGTFS downloads a GTFS zip and extracts stop_times.txt, streaming to the provided callback
func FetchAndParseStaticGTFS(zipURL string, insertBatch func([]ScheduledStopTime) error) error {
	log.Printf("Downloading static GTFS from %s", zipURL)
	resp, err := http.Get(zipURL)
	if err != nil {
		return fmt.Errorf("failed to download GTFS zip: %w", err)
	}
	defer resp.Body.Close()

	bodyBytes, err := io.ReadAll(resp.Body)
	if err != nil {
		return fmt.Errorf("failed to read GTFS zip body: %w", err)
	}

	zipReader, err := zip.NewReader(bytes.NewReader(bodyBytes), int64(len(bodyBytes)))
	if err != nil {
		return fmt.Errorf("failed to create zip reader: %w", err)
	}

	for _, file := range zipReader.File {
		if file.Name == "stop_times.txt" {
			log.Printf("Parsing stop_times.txt from %s...", zipURL)
			err = parseStopTimesToDB(file, insertBatch)
			if err != nil {
				return fmt.Errorf("failed to parse stop_times.txt: %w", err)
			}
			break
		}
	}

	log.Printf("Successfully parsed static GTFS.")
	return nil
}

func parseStopTimesToDB(file *zip.File, insertBatch func([]ScheduledStopTime) error) error {
	f, err := file.Open()
	if err != nil {
		return err
	}
	defer f.Close()

	reader := csv.NewReader(f)
	// Read header
	headers, err := reader.Read()
	if err != nil {
		return err
	}

	// Find column indices
	var tripIDIdx, stopIDIdx, arrivalTimeIdx int = -1, -1, -1
	for i, h := range headers {
		switch h {
		case "trip_id":
			tripIDIdx = i
		case "stop_id":
			stopIDIdx = i
		case "arrival_time":
			arrivalTimeIdx = i
		}
	}

	if tripIDIdx == -1 || stopIDIdx == -1 || arrivalTimeIdx == -1 {
		return fmt.Errorf("missing required columns in stop_times.txt")
	}

	const BatchSize = 10000
	var batch []ScheduledStopTime
	totalRows := 0

	for {
		record, err := reader.Read()
		if err == io.EOF {
			break
		}
		if err != nil {
			continue // skip bad lines
		}

		tripID := record[tripIDIdx]
		stopID := record[stopIDIdx]
		arrivalTime := parseTime(record[arrivalTimeIdx])

		batch = append(batch, ScheduledStopTime{
			TripID:      tripID,
			StopID:      stopID,
			ArrivalTime: arrivalTime,
		})

		if len(batch) >= BatchSize {
			if err := insertBatch(batch); err != nil {
				log.Printf("Error inserting batch: %v", err)
			}
			totalRows += len(batch)
			batch = batch[:0] // clear batch
		}
	}

	// Insert remainder
	if len(batch) > 0 {
		if err := insertBatch(batch); err != nil {
			log.Printf("Error inserting final batch: %v", err)
		}
		totalRows += len(batch)
	}

	log.Printf("Parsed %d stop_time records.", totalRows)
	return nil
}

// parseTime converts HH:MM:SS to seconds past midnight. Can handle HH > 23.
func parseTime(t string) int {
	parts := strings.Split(t, ":")
	if len(parts) != 3 {
		return 0
	}
	
	h, _ := strconv.Atoi(strings.TrimSpace(parts[0]))
	m, _ := strconv.Atoi(strings.TrimSpace(parts[1]))
	s, _ := strconv.Atoi(strings.TrimSpace(parts[2]))
	
	return h*3600 + m*60 + s
}
