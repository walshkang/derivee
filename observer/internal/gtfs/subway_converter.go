package gtfs

import (
	"encoding/json"
	"fmt"
	"strings"
	"time"
)

// LegacySubwayGeoJSON represents GeoJSON features from subway network
type LegacySubwayGeoJSON struct {
	Type     string `json:"type"`
	Features []struct {
		Properties struct {
			RouteGroup     string   `json:"route_group"`
			RouteName      string   `json:"route_name"`
			ColorHex       string   `json:"color_hex"`
			Color          string   `json:"color"`
			CasingColorHex string   `json:"casing_color_hex"`
			Routes         []string `json:"routes"`
		} `json:"properties"`
		Geometry struct {
			Type        string      `json:"type"`
			Coordinates interface{} `json:"coordinates"`
		} `json:"geometry"`
	} `json:"features"`
}

func parseLineCoords(raw interface{}) ([][2]float64, bool) {
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

		color := feat.Properties.ColorHex
		if color == "" {
			color = feat.Properties.Color
		}

		route := Route{
			RouteID:        leadID,
			AgencyID:       "MTA",
			RouteShortName: shortName,
			RouteLongName:  feat.Properties.RouteName,
			RouteType:      1, // Subway
			RouteColor:     strings.TrimPrefix(color, "#"),
		}
		ds.Routes[leadID] = route

		var lines [][][2]float64
		if feat.Geometry.Type == "LineString" {
			if line, ok := parseLineCoords(feat.Geometry.Coordinates); ok {
				lines = append(lines, line)
			}
		} else {
			// MultiLineString
			if multi, ok := feat.Geometry.Coordinates.([]interface{}); ok {
				for _, rawLine := range multi {
					if line, ok := parseLineCoords(rawLine); ok {
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
