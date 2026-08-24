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

// GTFSStop holds static stop location details
type GTFSStop struct {
	StopID        string
	StopName      string
	StopLat       float64
	StopLon       float64
	LocationType  int
	ParentStation string
}

// FetchAndParseStaticGTFS downloads a GTFS zip and extracts stop_times.txt and stops.txt, streaming to the provided callbacks
func FetchAndParseStaticGTFS(
	zipURL string,
	insertStopTimes func([]ScheduledStopTime) error,
	insertStops func([]GTFSStop) error,
) error {
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
		if file.Name == "stop_times.txt" && insertStopTimes != nil {
			log.Printf("Parsing stop_times.txt from %s...", zipURL)
			if err := parseStopTimesToDB(file, insertStopTimes); err != nil {
				log.Printf("Warning: failed to parse stop_times.txt: %v", err)
			}
		} else if file.Name == "stops.txt" && insertStops != nil {
			log.Printf("Parsing stops.txt from %s...", zipURL)
			if err := parseStopsToDB(file, insertStops); err != nil {
				log.Printf("Warning: failed to parse stops.txt: %v", err)
			}
		}
	}

	log.Printf("Successfully processed static GTFS archive.")
	return nil
}

func parseStopTimesToDB(file *zip.File, insertBatch func([]ScheduledStopTime) error) error {
	f, err := file.Open()
	if err != nil {
		return err
	}
	defer f.Close()

	reader := csv.NewReader(f)
	reader.FieldsPerRecord = -1
	// Read header
	headers, err := reader.Read()
	if err != nil {
		return err
	}

	// Find column indices
	var tripIDIdx, stopIDIdx, arrivalTimeIdx int = -1, -1, -1
	for i, h := range headers {
		switch strings.TrimSpace(h) {
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

		if len(record) <= tripIDIdx || len(record) <= stopIDIdx || len(record) <= arrivalTimeIdx {
			continue
		}

		tripID := strings.TrimSpace(record[tripIDIdx])
		stopID := strings.TrimSpace(record[stopIDIdx])
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

func parseStopsToDB(file *zip.File, insertBatch func([]GTFSStop) error) error {
	f, err := file.Open()
	if err != nil {
		return err
	}
	defer f.Close()

	reader := csv.NewReader(f)
	reader.FieldsPerRecord = -1

	headers, err := reader.Read()
	if err != nil {
		return err
	}

	stopIDIdx, stopNameIdx, stopLatIdx, stopLonIdx, locTypeIdx, parentStationIdx := -1, -1, -1, -1, -1, -1
	for i, h := range headers {
		switch strings.TrimSpace(h) {
		case "stop_id":
			stopIDIdx = i
		case "stop_name":
			stopNameIdx = i
		case "stop_lat":
			stopLatIdx = i
		case "stop_lon":
			stopLonIdx = i
		case "location_type":
			locTypeIdx = i
		case "parent_station":
			parentStationIdx = i
		}
	}

	if stopIDIdx == -1 || stopNameIdx == -1 || stopLatIdx == -1 || stopLonIdx == -1 {
		return fmt.Errorf("missing required columns in stops.txt")
	}

	const BatchSize = 5000
	var batch []GTFSStop
	totalRows := 0

	for {
		record, err := reader.Read()
		if err == io.EOF {
			break
		}
		if err != nil {
			continue
		}

		if len(record) <= stopIDIdx || len(record) <= stopNameIdx || len(record) <= stopLatIdx || len(record) <= stopLonIdx {
			continue
		}

		lat, _ := strconv.ParseFloat(strings.TrimSpace(record[stopLatIdx]), 64)
		lon, _ := strconv.ParseFloat(strings.TrimSpace(record[stopLonIdx]), 64)

		locType := 0
		if locTypeIdx != -1 && locTypeIdx < len(record) && strings.TrimSpace(record[locTypeIdx]) != "" {
			locType, _ = strconv.Atoi(strings.TrimSpace(record[locTypeIdx]))
		}

		parentStation := ""
		if parentStationIdx != -1 && parentStationIdx < len(record) {
			parentStation = strings.TrimSpace(record[parentStationIdx])
		}

		batch = append(batch, GTFSStop{
			StopID:        strings.TrimSpace(record[stopIDIdx]),
			StopName:      strings.TrimSpace(record[stopNameIdx]),
			StopLat:       lat,
			StopLon:       lon,
			LocationType:  locType,
			ParentStation: parentStation,
		})

		if len(batch) >= BatchSize {
			if err := insertBatch(batch); err != nil {
				log.Printf("Error inserting stops batch: %v", err)
			}
			totalRows += len(batch)
			batch = batch[:0]
		}
	}

	if len(batch) > 0 {
		if err := insertBatch(batch); err != nil {
			log.Printf("Error inserting final stops batch: %v", err)
		}
		totalRows += len(batch)
	}

	log.Printf("Parsed %d stop records.", totalRows)
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

