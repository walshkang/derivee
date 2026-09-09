package fetcher

import (
	"encoding/csv"
	"fmt"
	"io"
	"net/http"
	"os"
	"strconv"
	"strings"
)

const (
	// DefaultMTAStationsURL is the official MTA developer portal endpoint for Stations.csv
	DefaultMTAStationsURL = "http://web.mta.info/developers/data/nyct/subway/Stations.csv"
)

// MTAStationRecord represents a row parsed from MTA Stations.csv / Complexes.csv
type MTAStationRecord struct {
	StationID    int64
	ComplexID    int64
	GTFSStopID   string
	Division     string
	Line         string
	StopName     string
	Borough      string
	Latitude     float64
	Longitude    float64
	DaytimeRoutes string
}

// MTAComplexLookup contains pre-indexed lookups from MTA Stations.csv
type MTAComplexLookup struct {
	StopToComplexID map[string]int64
	ComplexNames    map[int64]string
	ComplexBoroughs map[int64]string
	ComplexCoords   map[int64][2]float64
	Records         []MTAStationRecord
}

// ParseMTAStationsCSV parses an MTA Stations.csv stream from an io.Reader
func ParseMTAStationsCSV(r io.Reader) (*MTAComplexLookup, error) {
	reader := csv.NewReader(r)
	header, err := reader.Read()
	if err != nil {
		return nil, fmt.Errorf("failed to read Stations.csv header: %w", err)
	}

	colMap := make(map[string]int)
	for i, col := range header {
		colMap[strings.TrimSpace(col)] = i
	}

	stationIDCol, hasStationID := colMap["Station ID"]
	complexIDCol, hasComplexID := colMap["Complex ID"]
	gtfsCol, hasGTFS := colMap["GTFS Stop ID"]
	nameCol, hasName := colMap["Stop Name"]
	boroughCol, hasBorough := colMap["Borough"]
	latCol, hasLat := colMap["GTFS Latitude"]
	lonCol, hasLon := colMap["GTFS Longitude"]
	routesCol, _ := colMap["Daytime Routes"]

	if !hasStationID || !hasComplexID || !hasGTFS || !hasName || !hasLat || !hasLon {
		return nil, fmt.Errorf("Stations.csv missing required headers (Station ID, Complex ID, GTFS Stop ID, Stop Name, GTFS Latitude, GTFS Longitude)")
	}

	lookup := &MTAComplexLookup{
		StopToComplexID: make(map[string]int64),
		ComplexNames:    make(map[int64]string),
		ComplexBoroughs: make(map[int64]string),
		ComplexCoords:   make(map[int64][2]float64),
		Records:         make([]MTAStationRecord, 0),
	}

	complexCoordSums := make(map[int64][3]float64) // [sumLat, sumLon, count]

	for {
		row, err := reader.Read()
		if err == io.EOF {
			break
		}
		if err != nil {
			continue
		}

		stationID, _ := strconv.ParseInt(strings.TrimSpace(row[stationIDCol]), 10, 64)
		complexID, _ := strconv.ParseInt(strings.TrimSpace(row[complexIDCol]), 10, 64)
		gtfsID := strings.TrimSpace(row[gtfsCol])
		stopName := strings.TrimSpace(row[nameCol])
		borough := ""
		if hasBorough && boroughCol < len(row) {
			borough = normalizeBorough(strings.TrimSpace(row[boroughCol]))
		}
		lat, _ := strconv.ParseFloat(strings.TrimSpace(row[latCol]), 64)
		lon, _ := strconv.ParseFloat(strings.TrimSpace(row[lonCol]), 64)
		routes := ""
		if routesCol < len(row) {
			routes = strings.TrimSpace(row[routesCol])
		}

		if gtfsID == "" || complexID == 0 {
			continue
		}

		rec := MTAStationRecord{
			StationID:     stationID,
			ComplexID:     complexID,
			GTFSStopID:    gtfsID,
			StopName:      stopName,
			Borough:       borough,
			Latitude:      lat,
			Longitude:     lon,
			DaytimeRoutes: routes,
		}
		lookup.Records = append(lookup.Records, rec)

		// Map GTFS stop ID to complex ID
		lookup.StopToComplexID[gtfsID] = complexID
		lookup.StopToComplexID[strings.ToUpper(gtfsID)] = complexID

		// Aggregate complex metadata
		if _, exists := lookup.ComplexNames[complexID]; !exists {
			lookup.ComplexNames[complexID] = stopName
			lookup.ComplexBoroughs[complexID] = borough
		}

		sums := complexCoordSums[complexID]
		sums[0] += lat
		sums[1] += lon
		sums[2] += 1.0
		complexCoordSums[complexID] = sums
	}

	// Compute average coordinates per complex centroid
	for cid, sums := range complexCoordSums {
		if sums[2] > 0 {
			lookup.ComplexCoords[cid] = [2]float64{sums[0] / sums[2], sums[1] / sums[2]}
		}
	}

	return lookup, nil
}

// LoadMTAStationsFromFile loads Stations.csv from a local file path
func LoadMTAStationsFromFile(filePath string) (*MTAComplexLookup, error) {
	f, err := os.Open(filePath)
	if err != nil {
		return nil, fmt.Errorf("failed to open Stations.csv at %s: %w", filePath, err)
	}
	defer f.Close()
	return ParseMTAStationsCSV(f)
}

// FetchMTAStations fetches and parses Stations.csv from the official remote MTA endpoint
func FetchMTAStations(url string) (*MTAComplexLookup, error) {
	if url == "" {
		url = DefaultMTAStationsURL
	}
	resp, err := http.Get(url)
	if err != nil {
		return nil, fmt.Errorf("failed to fetch Stations.csv from %s: %w", url, err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("failed to fetch Stations.csv: HTTP status %d", resp.StatusCode)
	}

	return ParseMTAStationsCSV(resp.Body)
}

func normalizeBorough(raw string) string {
	switch strings.ToUpper(raw) {
	case "M", "MANHATTAN":
		return "Manhattan"
	case "BK", "B", "BROOKLYN":
		return "Brooklyn"
	case "Q", "QUEENS":
		return "Queens"
	case "BX", "BRONX":
		return "Bronx"
	case "SI", "STATEN ISLAND":
		return "Staten Island"
	default:
		return raw
	}
}
