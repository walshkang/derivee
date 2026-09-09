package conflation

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"math"
	"regexp"
	"strconv"
	"strings"

	"github.com/qedus/osmpbf"

	"observer/internal/gtfs"
)

// GeoJSONFeatureCollection represents a GeoJSON FeatureCollection
type GeoJSONFeatureCollection struct {
	Type     string           `json:"type"`
	Features []GeoJSONFeature `json:"features"`
}

// GeoJSONFeature represents a single spatial feature conforming to station_shapes.geojson (Doc 15 §2)
type GeoJSONFeature struct {
	Type       string                 `json:"type"`
	ID         string                 `json:"id"`
	Geometry   GeoJSONGeometry        `json:"geometry"`
	Properties map[string]interface{} `json:"properties"`
}

// GeoJSONGeometry represents geometry payload
type GeoJSONGeometry struct {
	Type        string      `json:"type"`
	Coordinates interface{} `json:"coordinates"`
}

// BoundingBox defines an optional geographic bounding box filter
type BoundingBox struct {
	MinLat, MinLon, MaxLat, MaxLon float64
}

func (b BoundingBox) Contains(lat, lon float64) bool {
	if b.MinLat == 0 && b.MaxLat == 0 && b.MinLon == 0 && b.MaxLon == 0 {
		return true
	}
	return lat >= b.MinLat && lat <= b.MaxLat && lon >= b.MinLon && lon <= b.MaxLon
}

// Truncates coordinate precision to 6 decimal places (~0.11m accuracy)
func RoundCoordinate(val float64) float64 {
	return math.Round(val*1e6) / 1e6
}

// ParseLevels expands OSM level and repeat_on values into normalized float slices (Doc 15 §2)
func ParseLevels(levelStr, repeatOnStr string) []float64 {
	levelSet := make(map[float64]struct{})

	parseToken := func(token string) {
		token = strings.TrimSpace(token)
		if token == "" {
			return
		}

		rangeRegex := regexp.MustCompile(`^(-?\d+(?:\.\d+)?)-(-?\d+(?:\.\d+)?)$`)
		matches := rangeRegex.FindStringSubmatch(token)
		if len(matches) == 3 {
			start, err1 := strconv.ParseFloat(matches[1], 64)
			end, err2 := strconv.ParseFloat(matches[2], 64)
			if err1 == nil && err2 == nil {
				if start > end {
					start, end = end, start
				}
				for v := start; v <= end; v += 1.0 {
					levelSet[v] = struct{}{}
				}
				return
			}
		}

		if val, err := strconv.ParseFloat(token, 64); err == nil {
			levelSet[val] = struct{}{}
		}
	}

	for _, token := range strings.Split(levelStr, ";") {
		parseToken(token)
	}
	for _, token := range strings.Split(repeatOnStr, ";") {
		parseToken(token)
	}

	if len(levelSet) == 0 {
		return []float64{0.0}
	}

	result := make([]float64, 0, len(levelSet))
	for lvl := range levelSet {
		result = append(result, lvl)
	}
	return result
}

// ResolveGTFSComplex associates geometry centroid with the nearest GTFS station complex within maxDistMeters (Doc 15 & 16)
func ResolveGTFSComplex(lat, lon float64, complexes []gtfs.Complex, maxDistMeters float64) int64 {
	var matchedID int64 = 0
	minDist := maxDistMeters

	for _, c := range complexes {
		d := gtfs.CalculateHaversineDistance(lat, lon, c.Latitude, c.Longitude)
		if d < minDist {
			minDist = d
			matchedID = c.ComplexID
		}
	}
	return matchedID
}

// ConcourseConflator performs 3-pass extraction and 400m spatial conflation against GTFS station complexes
type ConcourseConflator struct {
	Complexes     []gtfs.Complex
	MaxDistMeters float64
	BBox          BoundingBox
}

// NewConcourseConflator creates a ConcourseConflator with given complexes and distance threshold
func NewConcourseConflator(complexes []gtfs.Complex, maxDistMeters float64, bbox BoundingBox) *ConcourseConflator {
	if maxDistMeters <= 0 {
		maxDistMeters = 400.0
	}
	return &ConcourseConflator{
		Complexes:     complexes,
		MaxDistMeters: maxDistMeters,
		BBox:          bbox,
	}
}

type candidateWay struct {
	id      int64
	nodeIDs []int64
	tags    map[string]string
}

// ConflateFromSeeker extracts multi-level pedestrian infrastructure from an OSM PBF stream
// and conflates geometries with GTFS station complexes within 400m.
func (c *ConcourseConflator) ConflateFromSeeker(ctx context.Context, seeker io.ReadSeeker) (*GeoJSONFeatureCollection, error) {
	// -------------------------------------------------------------
	// PASS 1: Scan Ways to catalog required Node IDs and transit tags
	// -------------------------------------------------------------
	if _, err := seeker.Seek(0, io.SeekStart); err != nil {
		return nil, fmt.Errorf("failed to seek stream for Pass 1: %w", err)
	}

	decoderP1 := osmpbf.NewDecoder(seeker)
	requiredNodes := make(map[int64]struct{})
	var cachedWays []candidateWay

	for {
		if err := ctx.Err(); err != nil {
			return nil, err
		}

		v, err := decoderP1.Decode()
		if err == io.EOF {
			break
		}
		if err != nil {
			return nil, fmt.Errorf("PBF decode error in Pass 1: %w", err)
		}

		if way, ok := v.(*osmpbf.Way); ok {
			t := way.Tags
			isPlatform := t["railway"] == "platform" || t["public_transport"] == "platform"
			isVertical := t["highway"] == "steps" || t["highway"] == "elevator"
			isIndoorArea := t["indoor"] == "area" || t["indoor"] == "corridor" || t["indoor"] == "room"
			isTunnelPath := (t["highway"] == "footway" || t["highway"] == "pedestrian") &&
				(t["tunnel"] == "yes" || t["indoor"] == "yes")

			if isPlatform || isVertical || isIndoorArea || isTunnelPath {
				cw := candidateWay{
					id:      way.ID,
					nodeIDs: way.NodeIDs,
					tags:    way.Tags,
				}
				for _, nid := range way.NodeIDs {
					requiredNodes[nid] = struct{}{}
				}
				cachedWays = append(cachedWays, cw)
			}
		}
	}

	// -------------------------------------------------------------
	// PASS 2: Hydrate node coordinates and extract standalone point nodes
	// -------------------------------------------------------------
	if _, err := seeker.Seek(0, io.SeekStart); err != nil {
		return nil, fmt.Errorf("failed to seek stream for Pass 2: %w", err)
	}

	decoderP2 := osmpbf.NewDecoder(seeker)
	type Coordinate struct {
		lat, lon float64
	}
	coordPool := make(map[int64]Coordinate, len(requiredNodes))
	var pointFeatures []GeoJSONFeature

	for {
		if err := ctx.Err(); err != nil {
			return nil, err
		}

		v, err := decoderP2.Decode()
		if err == io.EOF {
			break
		}
		if err != nil {
			return nil, fmt.Errorf("PBF decode error in Pass 2: %w", err)
		}

		if node, ok := v.(*osmpbf.Node); ok {
			if !c.BBox.Contains(node.Lat, node.Lon) {
				continue
			}

			if _, needed := requiredNodes[node.ID]; needed {
				coordPool[node.ID] = Coordinate{
					lat: RoundCoordinate(node.Lat),
					lon: RoundCoordinate(node.Lon),
				}
			}

			t := node.Tags
			isEntrance := t["railway"] == "subway_entrance" || t["entrance"] != ""
			isElevator := t["highway"] == "elevator" || t["amenity"] == "elevator"
			isFareGate := t["barrier"] == "fare_gate" || t["barrier"] == "turnstile"

			if isEntrance || isElevator || isFareGate {
				fType := "portal"
				if t["railway"] == "subway_entrance" {
					fType = "subway_entrance"
				} else if isElevator {
					fType = "elevator"
				} else if isFareGate {
					fType = "fare_gate"
				}

				accessible := t["wheelchair"] == "yes" || isElevator
				slices := ParseLevels(t["level"], t["repeat_on"])
				complexID := ResolveGTFSComplex(node.Lat, node.Lon, c.Complexes, c.MaxDistMeters)

				for _, lvl := range slices {
					feat := GeoJSONFeature{
						Type: "Feature",
						ID:   fmt.Sprintf("node/%d/lvl_%.1f", node.ID, lvl),
						Geometry: GeoJSONGeometry{
							Type:        "Point",
							Coordinates: []float64{RoundCoordinate(node.Lon), RoundCoordinate(node.Lat)},
						},
						Properties: map[string]interface{}{
							"complex_id":      complexID,
							"level":           lvl,
							"ordinal":         int(math.Round(lvl)),
							"level_name":      t["level:ref"],
							"feature_type":    fType,
							"accessible":      accessible,
							"wheelchair_desc": t["wheelchair"],
							"ref":             t["ref"],
							"name":            t["name"],
						},
					}
					pointFeatures = append(pointFeatures, feat)
				}
			}
		}
	}

	// -------------------------------------------------------------
	// PASS 3: Assemble Way Geometries with Discrete Planar Slicing
	// -------------------------------------------------------------
	var wayFeatures []GeoJSONFeature

	for _, cw := range cachedWays {
		t := cw.tags
		coords := make([][]float64, 0, len(cw.nodeIDs))
		var latSum, lonSum float64

		for _, nid := range cw.nodeIDs {
			if pt, exists := coordPool[nid]; exists {
				coords = append(coords, []float64{pt.lon, pt.lat})
				latSum += pt.lat
				lonSum += pt.lon
			}
		}

		if len(coords) < 2 {
			continue
		}

		cLat := latSum / float64(len(coords))
		cLon := lonSum / float64(len(coords))

		if !c.BBox.Contains(cLat, cLon) {
			continue
		}

		complexID := ResolveGTFSComplex(cLat, cLon, c.Complexes, c.MaxDistMeters)

		fType := "corridor"
		if t["railway"] == "platform" || t["public_transport"] == "platform" {
			fType = "platform"
		} else if t["highway"] == "steps" {
			if t["conveying"] == "yes" || t["escalator"] == "yes" {
				fType = "escalator"
			} else {
				fType = "steps"
			}
		} else if t["highway"] == "elevator" || t["amenity"] == "elevator" {
			fType = "elevator"
		} else if t["indoor"] == "area" {
			fType = "mezzanine"
		} else if t["indoor"] == "room" {
			fType = "room"
		}

		accessible := t["wheelchair"] == "yes" || fType == "elevator"
		if fType == "steps" {
			accessible = false
		}

		isClosed := len(coords) >= 4 &&
			coords[0][0] == coords[len(coords)-1][0] &&
			coords[0][1] == coords[len(coords)-1][1]

		slices := ParseLevels(t["level"], t["repeat_on"])

		for _, lvl := range slices {
			var geom GeoJSONGeometry
			if isClosed && (fType == "platform" || fType == "mezzanine" || fType == "room") {
				geom = GeoJSONGeometry{
					Type:        "Polygon",
					Coordinates: [][][]float64{coords},
				}
			} else {
				geom = GeoJSONGeometry{
					Type:        "LineString",
					Coordinates: coords,
				}
			}

			circulationDir := "bidirectional"
			if fType == "steps" || fType == "escalator" {
				if len(slices) > 1 {
					if lvl == slices[0] {
						circulationDir = "up"
					} else {
						circulationDir = "down"
					}
				}
			}

			feat := GeoJSONFeature{
				Type: "Feature",
				ID:   fmt.Sprintf("way/%d/lvl_%.1f", cw.id, lvl),
				Geometry: geom,
				Properties: map[string]interface{}{
					"complex_id":            complexID,
					"level":                 lvl,
					"ordinal":               int(math.Round(lvl)),
					"level_name":            t["level:ref"],
					"feature_type":          fType,
					"accessible":            accessible,
					"wheelchair_desc":       t["wheelchair"],
					"ref":                   t["ref"],
					"name":                  t["name"],
					"circulation_direction": circulationDir,
					"connects_levels":       slices,
				},
			}
			wayFeatures = append(wayFeatures, feat)
		}
	}

	collection := &GeoJSONFeatureCollection{
		Type:     "FeatureCollection",
		Features: append(pointFeatures, wayFeatures...),
	}

	return collection, nil
}

// SerializeGeoJSON writes the feature collection formatted as JSON
func SerializeGeoJSON(fc *GeoJSONFeatureCollection, w io.Writer) error {
	enc := json.NewEncoder(w)
	enc.SetIndent("", "  ")
	return enc.Encode(fc)
}
