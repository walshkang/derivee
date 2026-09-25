package gtfs

import (
	"database/sql"
	"encoding/json"
	"fmt"
	"strings"
	"time"

	_ "github.com/mattn/go-sqlite3"
)

// LegacySubwayGeoJSON represents GeoJSON features from subway network
type LegacySubwayGeoJSON struct {
	Type     string `json:"type"`
	Features []struct {
		Properties struct {
			FeatureType    string   `json:"feature_type"`
			RouteGroup     string   `json:"route_group"`
			RouteName      string   `json:"route_name"`
			ColorHex       string   `json:"color_hex"`
			Color          string   `json:"color"`
			TrunkColorHex  string   `json:"trunk_color_hex"`
			TrunkColor     string   `json:"trunk_color"`
			CasingColorHex string   `json:"casing_color_hex"`
			Routes         []string `json:"routes"`
		} `json:"properties"`
		Geometry struct {
			Type        string      `json:"type"`
			Coordinates interface{} `json:"coordinates"`
		} `json:"geometry"`
	} `json:"features"`
}

func ParseLineCoords(raw interface{}) ([][2]float64, bool) {
	if typed, ok := raw.([][2]float64); ok {
		return typed, true
	}
	slice, ok := raw.([]interface{})
	if !ok {
		return nil, false
	}
	res := make([][2]float64, 0, len(slice))
	for _, item := range slice {
		pt, ok := item.([]interface{})
		if !ok || len(pt) < 2 {
			return nil, false
		}
		lon, ok1 := pt[0].(float64)
		lat, ok2 := pt[1].(float64)
		if !ok1 || !ok2 {
			return nil, false
		}
		res = append(res, [2]float64{lon, lat})
	}
	return res, true
}

// ConvertLegacySubwayToDataset converts either legacy 11-feature GeoJSON or canonical corridor GeoJSON into a GTFS Dataset
func ConvertLegacySubwayToDataset(geoJSONBytes []byte) (*Dataset, error) {
	var legacy LegacySubwayGeoJSON
	if err := json.Unmarshal(geoJSONBytes, &legacy); err != nil {
		return nil, fmt.Errorf("failed to unmarshal legacy GeoJSON: %w", err)
	}

	ds := NewDataset(time.Now())

	// Route name to individual route tokens mapping
	routeTokens := map[string][]string{
		"123":  {"1", "2", "3"},
		"456":  {"4", "5", "6"},
		"7":    {"7"},
		"ACE":  {"A", "C", "E"},
		"BDFM": {"B", "D", "F", "M"},
		"G":    {"G"},
		"JZ":   {"J", "Z"},
		"L":    {"L"},
		"NQRW": {"N", "Q", "R", "W"},
		"S":    {"S"},
		"SIR":  {"SIR"},
	}

	// Primary representative route IDs
	primaryRouteID := map[string]string{
		"123":  "1",
		"456":  "4",
		"7":    "7",
		"ACE":  "A",
		"BDFM": "F",
		"G":    "G",
		"JZ":   "J",
		"L":    "L",
		"NQRW": "N",
		"S":    "GS",
		"SIR":  "SI",
	}

	for featIdx, feat := range legacy.Features {
		if feat.Properties.FeatureType == "platform_capsule" {
			continue
		}

		rg := feat.Properties.RouteGroup
		if rg == "" && len(feat.Properties.Routes) > 0 {
			rg = feat.Properties.Routes[0]
		}
		if rg == "" {
			rg = fmt.Sprintf("line_%d", featIdx)
		}

		leadID := primaryRouteID[rg]
		if leadID == "" {
			leadID = rg
		}

		tokens := routeTokens[rg]
		shortName := strings.Join(tokens, ", ")
		if shortName == "" {
			shortName = rg
		}

		color := feat.Properties.TrunkColorHex
		if color == "" {
			color = feat.Properties.TrunkColor
		}
		if color == "" {
			color = feat.Properties.ColorHex
		}
		if color == "" {
			color = feat.Properties.Color
		}

		cleanColor := strings.ToUpper(strings.TrimPrefix(color, "#"))
		if cleanColor == "" || cleanColor == "FFFFFF" {
			cleanColor = strings.TrimPrefix(ResolveRouteColor(Route{
				RouteID:        leadID,
				RouteShortName: shortName,
				RouteType:      1,
			}), "#")
		}

		route := Route{
			RouteID:        leadID,
			AgencyID:       "MTA",
			RouteShortName: shortName,
			RouteLongName:  feat.Properties.RouteName,
			RouteType:      1, // Subway
			RouteColor:     cleanColor,
		}
		ds.Routes[leadID] = route

		var lines [][][2]float64
		if feat.Geometry.Type == "LineString" {
			if line, ok := ParseLineCoords(feat.Geometry.Coordinates); ok {
				lines = append(lines, line)
			}
		} else {
			// MultiLineString
			if multi, ok := feat.Geometry.Coordinates.([]interface{}); ok {
				for _, rawLine := range multi {
					if line, ok := ParseLineCoords(rawLine); ok {
						lines = append(lines, line)
					}
				}
			}
		}

		// Convert each line into a shape
		for lineIdx, lineCoords := range lines {
			shapeID := fmt.Sprintf("shape_%s_%d_%d", rg, featIdx, lineIdx)
			ds.Trips[shapeID] = Trip{
				TripID:  shapeID,
				RouteID: leadID,
				ShapeID: shapeID,
			}

			shapePoints := make([]ShapePoint, len(lineCoords))
			for ptIdx, coord := range lineCoords {
				shapePoints[ptIdx] = ShapePoint{
					ShapeID:         shapeID,
					ShapePtLon:      coord[0],
					ShapePtLat:      coord[1],
					ShapePtSequence: ptIdx + 1,
				}
			}
			ds.Shapes[shapeID] = shapePoints
		}
	}

	return ds, nil
}

// HydrateStopsFromSQLite populates Dataset.Stops, Dataset.Trips, and Dataset.StopTimes
// from a pre-compiled transit.sqlite database.
func HydrateStopsFromSQLite(ds *Dataset, dbPath string) error {
	db, err := sql.Open("sqlite3", dbPath+"?_journal_mode=OFF&_query_only=1")
	if err != nil {
		return fmt.Errorf("failed to open sqlite database %s: %w", dbPath, err)
	}
	defer db.Close()

	// Hydrate routes from SQLite
	rRows, err := db.Query("SELECT route_id, agency_id, route_short_name, route_long_name, route_type, COALESCE(route_color, '') FROM routes")
	if err == nil {
		routeCount := 0
		for rRows.Next() {
			var r Route
			if err := rRows.Scan(&r.RouteID, &r.AgencyID, &r.RouteShortName, &r.RouteLongName, &r.RouteType, &r.RouteColor); err == nil {
				r.RouteColor = strings.TrimPrefix(r.RouteColor, "#")
				// Preserve existing composite RouteShortName if present (e.g. "A, C, E")
				if existing, exists := ds.Routes[r.RouteID]; exists && strings.Contains(existing.RouteShortName, ",") {
					r.RouteShortName = existing.RouteShortName
				}
				ds.Routes[r.RouteID] = r
				routeCount++
			}
		}
		rRows.Close()
	}

	rows, err := db.Query("SELECT stop_id, stop_name, stop_lat, stop_lon, location_type, routes, parent_station FROM stops")
	if err != nil {
		return fmt.Errorf("failed to query stops from %s: %w", dbPath, err)
	}
	defer rows.Close()

	for rows.Next() {
		var stopID, stopName, routesStr string
		var stopLat, stopLon float64
		var locationType int
		var parentStation sql.NullString

		if err := rows.Scan(&stopID, &stopName, &stopLat, &stopLon, &locationType, &routesStr, &parentStation); err != nil {
			return fmt.Errorf("failed to scan stop row: %w", err)
		}

		pStation := ""
		if parentStation.Valid {
			pStation = parentStation.String
		}

		stop := Stop{
			StopID:        stopID,
			StopName:      stopName,
			StopLat:       stopLat,
			StopLon:       stopLon,
			LocationType:  locationType,
			ParentStation: pStation,
		}
		ds.Stops[stopID] = stop

		// Parse routes string (e.g. ",1,2,3," or "A,C,E")
		trimmed := strings.Trim(routesStr, ",")
		if trimmed != "" {
			parts := strings.Split(trimmed, ",")
			for _, rID := range parts {
				rID = strings.TrimSpace(rID)
				if rID == "" {
					continue
				}
				tripID := fmt.Sprintf("trip_stop_%s_%s", stopID, rID)
				if _, exists := ds.Trips[tripID]; !exists {
					ds.Trips[tripID] = Trip{
						TripID:  tripID,
						RouteID: rID,
					}
				}
				ds.StopTimes[tripID] = append(ds.StopTimes[tripID], StopTime{
					TripID:       tripID,
					StopID:       stopID,
					StopSequence: 1,
				})
			}
		}
	}

	return nil
}

