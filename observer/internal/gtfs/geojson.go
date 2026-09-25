package gtfs

import (
	"encoding/json"
	"fmt"
	"math"
	"sort"
	"strconv"
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

// GeoJSONRouteProperties defines the styling, corridor, and modal properties expected by MapLibre & Swift
type GeoJSONRouteProperties struct {
	RouteID        string   `json:"route_id"`
	RouteShortName string   `json:"route_short_name"`
	RouteName      string   `json:"route_name"`
	CasingColorHex string   `json:"casing_color_hex"`
	CasingColor    string   `json:"casing_color"`
	RouteType      int      `json:"route_type"`
	ModalClass     int      `json:"modal_class"`

	// Additive Wave V Parallel Corridor & Dedup Keys
	TrunkColor     string   `json:"trunk_color"`
	TrunkColorHex  string   `json:"trunk_color_hex"`
	CorridorID     string   `json:"corridor_id"`
	BundleSize     int      `json:"bundle_size"`
	BundleIndex    int      `json:"bundle_index"`
	CompositeKey   string   `json:"composite_key"`
	Routes         []string `json:"routes"`

	// Wave V.3+V.4 Casing & Sorting & Badging Keys
	CasingWidthZ11 float64  `json:"casing_width_z11"`
	CasingWidth    float64  `json:"casing_width"`
	CasingWidthZ17 float64  `json:"casing_width_z17"`
	SortKey        int      `json:"sort_key"`
	ArcLengthM     float64  `json:"arc_length_m"`
	IsExpress      bool     `json:"is_express"`

	// Wave V.2b Parallel Offset Properties
	DeltaOffset    float64  `json:"delta_offset"`

	// Wave V.5 Station Platform Capsule Properties
	FeatureType    string   `json:"feature_type,omitempty"`
	StationName    string   `json:"station_name,omitempty"`
	StopID         string   `json:"stop_id,omitempty"`
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

	// 6. Build Inverted Index: ArcID -> map[routeID]Route
	arcRoutes := make(map[int]map[string]Route)
	for routeID, shapesMap := range routeShapes {
		route := ds.Routes[routeID]
		for shapeID := range shapesMap {
			for _, arcRef := range graph.ShapeArcs[shapeID] {
				if arcRoutes[arcRef.ArcID] == nil {
					arcRoutes[arcRef.ArcID] = make(map[string]Route)
				}
				arcRoutes[arcRef.ArcID][routeID] = route
			}
		}
	}

	// 7. Emit Consolidated Corridor Ribbon Features (INV-CORR-01, INV-CORR-02, INV-CORR-03)
	// Sort Arc IDs for deterministic GeoJSON output
	sortedArcIDs := make([]int, 0, len(graph.Arcs))
	for _, arc := range graph.Arcs {
		if len(arcRoutes[arc.ID]) > 0 {
			sortedArcIDs = append(sortedArcIDs, arc.ID)
		}
	}
	sort.Ints(sortedArcIDs)

	var features []GeoJSONFeature
	arcBundles := make(map[int][]*TrunkBundle)

	for _, arcID := range sortedArcIDs {
		pts := simplifiedArcs[arcID]
		if len(pts) < 2 {
			continue
		}

		// Convert points to coordinates slice
		// Note: arc.Points and simplifiedArcs are already canonically oriented (INV-CORR-03)
		coords := make([][2]float64, len(pts))
		for i, p := range pts {
			coords[i] = [2]float64{p.Lon, p.Lat}
		}

		// Collect unique routes traversing this arc
		routeMap := arcRoutes[arcID]
		routesList := make([]Route, 0, len(routeMap))
		for _, r := range routeMap {
			routesList = append(routesList, r)
		}

		// Consolidate into Trunk Bundles (INV-CORR-01, INV-CORR-02)
		bundles, err := ConsolidateCorridorBundles(routesList, DefaultColorDistance)
		if err != nil {
			return nil, nil, fmt.Errorf("arc %d bundle consolidation failed: %w", arcID, err)
		}
		arcBundles[arcID] = bundles

		corridorID := fmt.Sprintf("corridor_arc_%d", arcID)
		arcLength := CalculateArcLengthM(pts)
		isExpress := arcLength >= 800.0

		for _, b := range bundles {
			lead := b.LeadRoute
			routeName := lead.RouteLongName
			if routeName == "" {
				routeName = lead.RouteShortName
			}
			routeShortName := strings.Join(b.RouteNames, ", ")

			casingColor := "#FFFFFF"
			casingWidthZ11, casingWidthZ14, casingWidthZ17 := CalculateCasingWidths(b.BundleSize)
			sortKey := ModalPriority(b.ModalClass)*1000 + CalculateHexHue(b.TrunkColor)

			deltaOffsetPt := 0.0
			featureCoords := coords

			if b.BundleSize > 1 {
				deltaOffsetPt = (float64(b.BundleIndex) - float64(b.BundleSize-1)/2.0) * 3.5
				offsetDistM := CalculateBundleOffsetDistance(b.BundleIndex, b.BundleSize, DefaultOffsetOptions)
				if math.Abs(offsetDistM) > 1e-6 {
					offsetPts, err := OffsetPolyline(pts, offsetDistM, DefaultOffsetOptions)
					if err == nil && len(offsetPts) >= 2 {
						clippedPts := ClipSwallowtails(offsetPts, pts, offsetDistM)
						if len(clippedPts) >= 2 {
							// Ensure canonical orientation along longitudinal axis (INV-CORR-03)
							startKey := ToPointKey(clippedPts[0])
							endKey := ToPointKey(clippedPts[len(clippedPts)-1])
							if !LessPointKey(startKey, endKey) && startKey != endKey {
								// Reverse to preserve canonical orientation
								for i, j := 0, len(clippedPts)-1; i < j; i, j = i+1, j-1 {
									clippedPts[i], clippedPts[j] = clippedPts[j], clippedPts[i]
								}
							}
							c := make([][2]float64, len(clippedPts))
							for i, p := range clippedPts {
								c[i] = [2]float64{p.Lon, p.Lat}
							}
							featureCoords = c
						}
					}
				}
			}

			props := GeoJSONRouteProperties{
				RouteID:        lead.RouteID,
				RouteShortName: routeShortName,
				RouteName:      routeName,
				CasingColorHex: casingColor,
				CasingColor:    casingColor,
				RouteType:      lead.RouteType,
				ModalClass:     b.ModalClass,

				TrunkColor:     b.TrunkColor,
				TrunkColorHex:  b.TrunkColor,
				CorridorID:     corridorID,
				BundleSize:     b.BundleSize,
				BundleIndex:    b.BundleIndex,
				CompositeKey:   b.CompositeKey,
				Routes:         b.RouteNames,

				CasingWidthZ11: casingWidthZ11,
				CasingWidth:    casingWidthZ14,
				CasingWidthZ17: casingWidthZ17,
				SortKey:        sortKey,
				ArcLengthM:     arcLength,
				IsExpress:      isExpress,
				DeltaOffset:    deltaOffsetPt,
			}

			features = append(features, GeoJSONFeature{
				Type:       "Feature",
				Properties: props,
				Geometry: GeoJSONGeometry{
					Type:        "LineString",
					Coordinates: featureCoords,
				},
			})
		}
	}

	// 8. Pre-compute Station Platform Capsules for Bundled Corridors (K >= 2)
	capsules, err := GeneratePlatformCapsules(ds, simplifiedArcs, arcBundles, DefaultPlatformCapsuleOptions)
	if err != nil {
		return nil, nil, fmt.Errorf("failed to generate platform capsules: %w", err)
	}
	features = append(features, capsules...)

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

	switch cleanID {
	case "123":
		return "#EE352E"
	case "456":
		return "#00933C"
	case "7":
		return "#B933AD"
	case "ACE":
		return "#0039A6"
	case "BDFM":
		return "#FF6319"
	case "G":
		return "#6CBE45"
	case "JZ":
		return "#996633"
	case "L":
		return "#A7A9AC"
	case "NQRW":
		return "#FCCC0A"
	case "S":
		return "#808183"
	case "SIR":
		return "#0039A6"
	}

	firstToken := cleanShort
	if idx := strings.Index(firstToken, ","); idx != -1 {
		firstToken = strings.TrimSpace(firstToken[:idx])
	}

	// NYC Subway Line Colors
	switch firstToken {
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
	case "S":
		return "#808183"
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

// CalculateArcLengthM calculates geodesic polyline distance in meters along points
func CalculateArcLengthM(pts []Point2D) float64 {
	if len(pts) < 2 {
		return 0.0
	}
	var total float64
	for i := 0; i < len(pts)-1; i++ {
		total += CalculateHaversineDistance(pts[i].Lat, pts[i].Lon, pts[i+1].Lat, pts[i+1].Lon)
	}
	return total
}

// CalculateCasingWidths returns zoom-indexed casing widths (z11, z14, z17) for bundle size K
func CalculateCasingWidths(bundleSize int) (float64, float64, float64) {
	switch bundleSize {
	case 1:
		return 2.5, 4.5, 8.1
	case 2:
		return 4.0, 7.5, 13.6
	case 3:
		return 5.5, 10.5, 19.1
	default:
		return 2.5, 4.5, 8.1
	}
}

// ModalPriority maps GTFS modal class to deterministic sorting priority
func ModalPriority(modalClass int) int {
	switch modalClass {
	case ModalClassSubway:
		return 10
	case ModalClassLRT:
		return 8
	case ModalClassFerry:
		return 5
	case ModalClassBus:
		return 2
	default:
		return 1
	}
}

// CalculateHexHue computes the HSV hue angle (0-359) from a hex color string
func CalculateHexHue(hex string) int {
	hex = strings.TrimPrefix(strings.TrimSpace(hex), "#")
	if len(hex) != 6 {
		return 0
	}
	rVal, err1 := strconv.ParseUint(hex[0:2], 16, 8)
	gVal, err2 := strconv.ParseUint(hex[2:4], 16, 8)
	bVal, err3 := strconv.ParseUint(hex[4:6], 16, 8)
	if err1 != nil || err2 != nil || err3 != nil {
		return 0
	}
	r := float64(rVal) / 255.0
	g := float64(gVal) / 255.0
	b := float64(bVal) / 255.0

	maxVal := math.Max(r, math.Max(g, b))
	minVal := math.Min(r, math.Min(g, b))
	delta := maxVal - minVal

	if delta == 0 {
		return 0
	}

	var hue float64
	if maxVal == r {
		hue = (g - b) / delta
		if hue < 0 {
			hue += 6.0
		}
	} else if maxVal == g {
		hue = 2.0 + (b - r) / delta
	} else {
		hue = 4.0 + (r - g) / delta
	}
	hue *= 60.0
	return int(math.Round(hue)) % 360
}

