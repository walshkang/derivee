package gtfs

import (
	"encoding/json"
	"fmt"
	"sort"
	"strings"
)

// GeoJSONFeatureCollection represents a standard GeoJSON FeatureCollection
type GeoJSONFeatureCollection struct {
	Type     string           `json:"type"`
	Features []GeoJSONFeature `json:"features"`
}

// GeoJSONFeature represents a single route feature in transit-lines.geojson
type GeoJSONFeature struct {
	Type       string                 `json:"type"`
	Properties GeoJSONRouteProperties `json:"properties"`
	Geometry   GeoJSONGeometry        `json:"geometry"`
}

// GeoJSONRouteProperties defines the styling and modal properties expected by MapLibre & Swift
type GeoJSONRouteProperties struct {
	RouteID        string `json:"route_id"`
	RouteShortName string `json:"route_short_name"`
	RouteName      string `json:"route_name"`
	ColorHex       string `json:"color_hex"`
	Color          string `json:"color"`
	CasingColorHex string `json:"casing_color_hex"`
	RouteType      int    `json:"route_type"`
	ModalClass     int    `json:"modal_class"`
}

// GeoJSONGeometry represents LineString or MultiLineString geometry
type GeoJSONGeometry struct {
	Type        string      `json:"type"`
	Coordinates interface{} `json:"coordinates"` // [][2]float64 for LineString, [][][2]float64 for MultiLineString
}

// GenerateTransitLinesGeoJSON processes a GTFS Dataset and compiles a normalized, zero-Z-fighting transit-lines.geojson
func GenerateTransitLinesGeoJSON(ds *Dataset) (*GeoJSONFeatureCollection, []byte, error) {
	// 1. Filter routes: Exclude buses (ModalClassBus = 2). Include Subway, LRT, Ferry.
	// Map route_id -> shapes used by that route
	routeShapes := make(map[string]map[string]bool)
	for _, trip := range ds.Trips {
		if trip.ShapeID == "" {
			continue
		}
		route, ok := ds.Routes[trip.RouteID]
		if !ok {
			continue
		}
		modalClass := ResolveModalClass(route.RouteType)
		if modalClass == ModalClassBus && !isBRTRoute(route) {
			continue // Standard capillary bus routes excluded; BRT corridors preserved
		}
		if _, hasShape := ds.Shapes[trip.ShapeID]; !hasShape {
			continue
		}

		if routeShapes[route.RouteID] == nil {
			routeShapes[route.RouteID] = make(map[string]bool)
		}
		routeShapes[route.RouteID][trip.ShapeID] = true
	}

	// 2. Collect all active shapes for the topology graph
	activeShapes := make(map[string][]ShapePoint)
	for _, shapesMap := range routeShapes {
		for shapeID := range shapesMap {
			activeShapes[shapeID] = ds.Shapes[shapeID]
		}
	}

	if len(activeShapes) == 0 {
		fc := &GeoJSONFeatureCollection{
			Type:     "FeatureCollection",
			Features: []GeoJSONFeature{},
		}
		raw, err := json.Marshal(fc)
		return fc, raw, err
	}

	// 3. Build Planar Arc-Topology Graph
	graph := BuildTopologyGraph(activeShapes)

	// 4. Determine mode-adaptive thresholds per canonical Arc
	// If multiple routes share an Arc, use the minimum (most conservative) threshold to preserve full fidelity
	arcMinThreshold := make(map[int]float64)
	for routeID, shapesMap := range routeShapes {
		route := ds.Routes[routeID]
		thresh := ThresholdForRoute(route)

		for shapeID := range shapesMap {
			for _, arcRef := range graph.ShapeArcs[shapeID] {
				curr, exists := arcMinThreshold[arcRef.ArcID]
				if !exists || thresh < curr {
					arcMinThreshold[arcRef.ArcID] = thresh
				}
			}
		}
	}

	// 5. Simplify all Canonical Arcs once
	simplifiedArcs := SimplifyGraph(graph, ThresholdSubway, arcMinThreshold)

	// 6. Reassemble Route Geometries from Simplified Arcs
	// Sort route IDs for deterministic GeoJSON output
	sortedRouteIDs := make([]string, 0, len(routeShapes))
	for rID := range routeShapes {
		sortedRouteIDs = append(sortedRouteIDs, rID)
	}
	sort.Strings(sortedRouteIDs)

	var features []GeoJSONFeature

	for _, routeID := range sortedRouteIDs {
		route := ds.Routes[routeID]
		modalClass := ResolveModalClass(route.RouteType)

		color := ResolveRouteColor(route)
		casingColor := "#FFFFFF"
		if modalClass == ModalClassLRT {
			casingColor = "#FFFFFF"
		}

		routeName := route.RouteLongName
		if routeName == "" {
			routeName = route.RouteShortName
		}

		// Reassemble all shapes for this route
		var routeLines [][][2]float64
		seenShapeSignatures := make(map[string]bool)

		// Sort shape IDs for determinism
		shapeIDs := make([]string, 0, len(routeShapes[routeID]))
		for sID := range routeShapes[routeID] {
			shapeIDs = append(shapeIDs, sID)
		}
		sort.Strings(shapeIDs)

		for _, shapeID := range shapeIDs {
			arcRefs := graph.ShapeArcs[shapeID]
			if len(arcRefs) == 0 {
				continue
			}

			var shapeCoords [][2]float64
			for _, ref := range arcRefs {
				pts := simplifiedArcs[ref.ArcID]
				if len(pts) == 0 {
					continue
				}

				if ref.Reversed {
					// Add points in reverse
					for j := len(pts) - 1; j >= 0; j-- {
						p := pts[j]
						coord := [2]float64{p.Lon, p.Lat}
						if len(shapeCoords) == 0 || shapeCoords[len(shapeCoords)-1] != coord {
							shapeCoords = append(shapeCoords, coord)
						}
					}
				} else {
					// Add points forward
					for _, p := range pts {
						coord := [2]float64{p.Lon, p.Lat}
						if len(shapeCoords) == 0 || shapeCoords[len(shapeCoords)-1] != coord {
							shapeCoords = append(shapeCoords, coord)
						}
					}
				}
			}

			if len(shapeCoords) >= 2 {
				// Deduplicate identical polylines
				sig := fmt.Sprintf("%v-%v-%d", shapeCoords[0], shapeCoords[len(shapeCoords)-1], len(shapeCoords))
				if !seenShapeSignatures[sig] {
					seenShapeSignatures[sig] = true
					routeLines = append(routeLines, shapeCoords)
				}
			}
		}

		if len(routeLines) == 0 {
			continue
		}

		props := GeoJSONRouteProperties{
			RouteID:        route.RouteID,
			RouteShortName: route.RouteShortName,
			RouteName:      routeName,
			ColorHex:       color,
			Color:          color,
			CasingColorHex: casingColor,
			RouteType:      route.RouteType,
			ModalClass:     modalClass,
		}

		var geom GeoJSONGeometry
		if len(routeLines) == 1 {
			geom = GeoJSONGeometry{
				Type:        "LineString",
				Coordinates: routeLines[0],
			}
		} else {
			geom = GeoJSONGeometry{
				Type:        "MultiLineString",
				Coordinates: routeLines,
			}
		}

		features = append(features, GeoJSONFeature{
			Type:       "Feature",
			Properties: props,
			Geometry:   geom,
		})
	}

	fc := &GeoJSONFeatureCollection{
		Type:     "FeatureCollection",
		Features: features,
	}

	rawBytes, err := json.Marshal(fc)
	if err != nil {
		return nil, nil, fmt.Errorf("failed to marshal transit GeoJSON: %w", err)
	}

	return fc, rawBytes, nil
}

// isBRTRoute identifies Bus Rapid Transit trunk corridors that should be included in transit-lines.geojson
func isBRTRoute(route Route) bool {
	rID := strings.ToUpper(strings.TrimSpace(route.RouteID))
	sName := strings.ToUpper(strings.TrimSpace(route.RouteShortName))
	lName := strings.ToUpper(strings.TrimSpace(route.RouteLongName))

	// Extended GTFS BRT
	if route.RouteType == 702 {
		return true
	}
	// Boston MBTA Silver Line
	if strings.HasPrefix(rID, "SL") || strings.HasPrefix(sName, "SL") || strings.Contains(lName, "SILVER LINE") {
		return true
	}
	// NYC Select Bus Service
	if strings.Contains(rID, "SBS") || strings.Contains(sName, "SBS") || strings.Contains(lName, "+ SELECT BUS") {
		return true
	}
	return false
}

// ResolveRouteColor returns the formatted hex color for a Route, falling back to brand modal defaults
func ResolveRouteColor(route Route) string {
	color := strings.TrimSpace(route.RouteColor)
	if color != "" {
		if !strings.HasPrefix(color, "#") {
			color = "#" + color
		}
		return color
	}

	cleanID := strings.ToUpper(strings.TrimSpace(route.RouteID))
	cleanShort := strings.ToUpper(strings.TrimSpace(route.RouteShortName))

	// Boston MBTA Trunk Colors
	switch cleanID {
	case "RED":
		return "#DA291C"
	case "ORANGE":
		return "#ED8B00"
	case "BLUE":
		return "#003DA5"
	case "GREEN-B", "GREEN-C", "GREEN-D", "GREEN-E", "GREEN_B", "GREEN_C", "GREEN_D", "GREEN_E":
		return "#00843D"
	case "MATTAPAN":
		return "#DA291C"
	case "SL1", "SL2", "SL3", "SL4", "SL5", "SLW":
		return "#7C878E"
	case "BOAT-F4", "BOAT-F1", "BOAT-F2H", "F4", "F1", "F2H":
		return "#00A3E0"
	}

	switch cleanShort {
	case "RED":
		return "#DA291C"
	case "ORANGE":
		return "#ED8B00"
	case "BLUE":
		return "#003DA5"
	case "GREEN-B", "GREEN-C", "GREEN-D", "GREEN-E", "B", "C", "D", "E":
		if strings.Contains(cleanID, "GREEN") {
			return "#00843D"
		}
	case "SL1", "SL2", "SL3", "SL4", "SL5", "SLW":
		return "#7C878E"
	case "F4", "F1", "F2H":
		return "#00A3E0"
	}

	// NYC Subway Line Colors
	switch cleanShort {
	case "1", "2", "3":
		return "#EE352E"
	case "4", "5", "6", "6X":
		return "#00933C"
	case "7", "7X":
		return "#B933AD"
	case "A", "C", "E":
		return "#0039A6"
	case "B", "D", "F", "FX", "M":
		return "#FF6319"
	case "G":
		return "#6CBE45"
	case "J", "Z":
		return "#996633"
	case "L":
		return "#A7A9AC"
	case "N", "Q", "R", "W":
		return "#FCCC0A"
	case "SIR":
		return "#0039A6"
	}

	modalClass := ResolveModalClass(route.RouteType)
	switch modalClass {
	case ModalClassFerry:
		return "#00A3E0"
	case ModalClassLRT:
		return "#00843D"
	case ModalClassBus:
		return "#7C878E"
	default:
		return "#FFB300" // Electric Amber
	}
}

