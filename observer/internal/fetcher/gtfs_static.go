package fetcher

import (
	"archive/zip"
	"bytes"
	"encoding/csv"
	"fmt"
	"io"
	"log"
	"net/http"
	"regexp"
	"strconv"
	"strings"
	"unicode"
)

var (
	directionalTokenRegex = regexp.MustCompile(`(?i)(?:\(\s*)?\b(NB|SB|EB|WB)\b(?:\s*\))?`)
	slashRegex            = regexp.MustCompile(`\s*[/|\\]+\s*`)
	multiSpaceRegex       = regexp.MustCompile(`\s+`)
	ordinalRegex          = regexp.MustCompile(`(?i)^([0-9]+)(ST|ND|RD|TH)$`)
)

// ParseStopName decomposes a raw stop name into a clean intersection name and an isolated routing qualifier.
// Directional bus stop tokens (NB, SB, EB, WB) are isolated using boundary-aware regex so they are classified
// as routing qualifiers instead of binding into numbered street tokens (e.g. preventing "Kent Av & NB 6 St").
func ParseStopName(raw string) (string, string) {
	name := strings.TrimSpace(raw)
	if name == "" {
		return "", ""
	}

	// 1. Isolate directional tokens (NB, SB, EB, WB) using boundary-aware regex
	var qualifier string
	if match := directionalTokenRegex.FindStringSubmatch(name); len(match) > 1 && match[1] != "" {
		qualifier = strings.ToUpper(match[1])
	}

	// Remove the isolated qualifier (and any wrapping parens) from the street text
	cleanedRaw := directionalTokenRegex.ReplaceAllString(name, " ")

	// 2. Normalize slashes or connectors into " & "
	cleanedRaw = slashRegex.ReplaceAllString(cleanedRaw, " & ")

	// 3. Process intersection segments separated by " & "
	segments := strings.Split(cleanedRaw, " & ")
	cleanedSegments := make([]string, 0, len(segments))

	for _, seg := range segments {
		seg = strings.TrimSpace(seg)
		if seg == "" {
			continue
		}
		cleanedSegments = append(cleanedSegments, cleanStreetSegment(seg))
	}

	result := strings.Join(cleanedSegments, " & ")
	result = multiSpaceRegex.ReplaceAllString(result, " ")
	result = strings.TrimSpace(result)

	// Clean up any dangling & or empty parens
	result = strings.TrimPrefix(result, "& ")
	result = strings.TrimSuffix(result, " &")
	result = strings.ReplaceAll(result, "()", "")
	result = strings.TrimSpace(result)

	return result, qualifier
}

// CleanStopName formats a raw stop name into a clean, title-cased intersection format with isolated directional routing qualifiers.
func CleanStopName(raw string) string {
	cleanName, qualifier := ParseStopName(raw)
	if qualifier != "" && !strings.Contains(cleanName, "("+qualifier+")") {
		if cleanName == "" {
			return qualifier
		}
		return fmt.Sprintf("%s (%s)", cleanName, qualifier)
	}
	return cleanName
}

func cleanStreetSegment(seg string) string {
	words := strings.Fields(seg)
	if len(words) == 0 {
		return ""
	}

	cleanedWords := make([]string, 0, len(words))
	for _, w := range words {
		upper := strings.ToUpper(w)
		trimmedUpper := strings.TrimRight(upper, ",.")

		switch trimmedUpper {
		case "&", "+", "@":
			cleanedWords = append(cleanedWords, "&")
		case "ST", "STREET":
			cleanedWords = append(cleanedWords, "St")
		case "AV", "AVE", "AVENUE":
			cleanedWords = append(cleanedWords, "Av")
		case "RD", "ROAD":
			cleanedWords = append(cleanedWords, "Rd")
		case "BLVD", "BOULEVARD":
			cleanedWords = append(cleanedWords, "Blvd")
		case "PL", "PLACE":
			cleanedWords = append(cleanedWords, "Pl")
		case "PKWY", "PARKWAY":
			cleanedWords = append(cleanedWords, "Pkwy")
		case "DR", "DRIVE":
			cleanedWords = append(cleanedWords, "Dr")
		case "LN", "LANE":
			cleanedWords = append(cleanedWords, "Ln")
		case "CT", "COURT":
			cleanedWords = append(cleanedWords, "Ct")
		case "TER", "TERR", "TERRACE":
			cleanedWords = append(cleanedWords, "Ter")
		case "HWY", "HIGHWAY":
			cleanedWords = append(cleanedWords, "Hwy")
		case "EXPY", "EXPRESSWAY":
			cleanedWords = append(cleanedWords, "Expy")
		case "WAY":
			cleanedWords = append(cleanedWords, "Way")
		case "CIR", "CIRCLE":
			cleanedWords = append(cleanedWords, "Cir")
		case "PLZ", "PLAZA":
			cleanedWords = append(cleanedWords, "Plaza")
		case "N":
			cleanedWords = append(cleanedWords, "N")
		case "S":
			cleanedWords = append(cleanedWords, "S")
		case "E":
			cleanedWords = append(cleanedWords, "E")
		case "W":
			cleanedWords = append(cleanedWords, "W")
		case "NORTH":
			cleanedWords = append(cleanedWords, "North")
		case "SOUTH":
			cleanedWords = append(cleanedWords, "South")
		case "EAST":
			cleanedWords = append(cleanedWords, "East")
		case "WEST":
			cleanedWords = append(cleanedWords, "West")
		case "SBS", "MTA", "NYCT", "LIRR", "PATH", "WTC", "FDR", "GWB", "MET", "AMTRAK", "MBTA":
			cleanedWords = append(cleanedWords, trimmedUpper)
		default:
			if m := ordinalRegex.FindStringSubmatch(trimmedUpper); len(m) > 2 {
				cleanedWords = append(cleanedWords, m[1]+strings.ToLower(m[2]))
			} else {
				cleanedWords = append(cleanedWords, toTitleCase(w))
			}
		}
	}
	return strings.Join(cleanedWords, " ")
}

func toTitleCase(w string) string {
	if strings.Contains(w, "-") {
		parts := strings.Split(w, "-")
		cleanedParts := make([]string, len(parts))
		for i, p := range parts {
			cleanedParts[i] = titleCaseSingleWord(p)
		}
		return strings.Join(cleanedParts, "-")
	}
	return titleCaseSingleWord(w)
}

func titleCaseSingleWord(w string) string {
	if len(w) == 0 {
		return ""
	}
	upper := strings.ToUpper(w)
	if strings.HasPrefix(upper, "MC") && len(w) > 2 {
		return "Mc" + strings.ToUpper(string(w[2])) + strings.ToLower(w[3:])
	}
	hasLower := false
	hasUpper := false
	for _, r := range w {
		if unicode.IsLower(r) {
			hasLower = true
		} else if unicode.IsUpper(r) {
			hasUpper = true
		}
	}
	if hasLower && hasUpper {
		return w
	}
	runes := []rune(strings.ToLower(w))
	for i, r := range runes {
		if unicode.IsLetter(r) {
			runes[i] = unicode.ToUpper(r)
			break
		}
	}
	return string(runes)
}

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
			StopName:      CleanStopName(record[stopNameIdx]),
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

