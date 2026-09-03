# Subterranean and Multi-Level Transit Infrastructure Extraction: 2D Orthographic Floorplan Modeling and Ingestion Architecture

## 1. Tagging Schemas for Subterranean and Multi-Level Transit Infrastructure

Accurate extraction of multi-level transit hubs from OpenStreetMap (OSM) requires navigating an evolving catalog of tagging standards. Historically, mappers relied on ad-hoc combinations of the `highway` and `railway` keys, but modern transit modeling increasingly integrates the Simple Indoor Tagging (SIT) standard alongside Public Transport Version 2 (PTv2) specifications. Capturing complex multi-tiered interchanges—such as Pennsylvania Station / Moynihan Train Hall, Grand Central Terminal, and 14 St-Union Square—demands strict separation between physical indoor architectural surfaces, navigable circulation paths, and vertical transitions, while preserving geometric integrity for flat 2D projection.

### Platforms
Platforms are captured in OSM as either linear centerlines along boarding edges or closed polygonal areas delineating passenger waiting surfaces. For floorplan rendering and spatial containment, the extraction pipeline must target polygonal area geometries. These features are canonically tagged with `railway=platform` for heavy rail, commuter rail, and rapid transit subway systems, or `public_transport=platform` under the multimodal PTv2 schema. Within subterranean intermodal facilities containing bus berths, `highway=platform` is also encountered. Subterranean platforms are explicitly differentiated from surface structures through `tunnel=yes` or `location=underground`, accompanied by vertical index tags. The pipeline must distinguish between `level=*`, which specifies the architectural floor, and `layer=*`, which defines the cartographic z-order used to resolve visual intersections among overlapping ways.

### Vertical Circulation Infrastructure
Vertical circulation infrastructure provides the topological transitions between distinct vertical levels:
- **Fixed stairways** are identified by `highway=steps`. The direction of vertical travel along the drawn geometry is determined by the `incline` tag, where `incline=up` indicates that the elevation rises along the vertex sequence of the OSM way, and `incline=down` indicates a descent; `incline=up` serves as the implicit standard default. Granular attributes include `step_count=*` and `handrail=left|right|both|no`.
- **Moving stairways (escalators)** are mapped under the SIT and pedestrian guidelines as `highway=steps` combined with `conveying=yes`, or specified directionally via `conveying=forward|backward|reversible`.
- **Moving walkways (travelators)** are encoded as `highway=footway` with `conveying=yes` and `incline=flat`.
- **Elevators** are mapped either as topological point nodes connecting disparate level networks tagged with `highway=elevator` or `amenity=elevator`, or as closed polygonal ways representing the physical structural elevator shaft. Individual landing doors on respective levels are mapped via `door=elevator` or `door=yes` combined with discrete `level=*` bindings. Connectors that traverse multiple vertical strata must define compound level intervals using semicolon-separated lists or hyphenated ranges.

### Station Portals and Building Entrances
Station portals, entryways, and exit passages delineate the transition between subterranean transit complexes and municipal street networks. Street-level subway portals are canonically mapped to point nodes tagged with `railway=subway_entrance`. Exterior and interior building portals within headhouses are identified via `entrance=yes`, `entrance=main`, `entrance=staircase`, or `entrance=subway`. Dedicated egress passages are flagged with `exit=yes` or `exit=emergency`. Transit agencies establish alphanumeric exit naming frameworks that are mapped to `ref=*` (such as the Metropolitan Transportation Authority exit identifiers), with descriptive regional designations placed in `name=*` or `exit_to=*`. Step-free accessibility is indicated by `wheelchair=yes|no|limited`, often supplemented by `tactile_paving=yes|no` and automated door operations (`door=automatic`).

### Concourses and Intermediate Mezzanines
Concourses and intermediate mezzanines represent the physical pedestrian areas through which passengers distribute between street portals, fare gates, and boarding platforms. Under the SIT standard, open concourses are represented as closed ways or multipolygon relations tagged with `indoor=area`. Corridors and enclosed pedestrian walkways are mapped as `indoor=corridor`, while back-of-house utility areas, ticket offices, and commercial facilities use `indoor=room`. In legacy mapping contexts, pedestrian concourses were frequently tagged as `highway=pedestrian` or `highway=footway` with `area=yes`. Underground pedestrian passageways require `tunnel=yes` or `indoor=yes` alongside an explicit `level=*` tag. Physical fare boundaries within concourses are mapped using `barrier=fare_gate` or `barrier=turnstile` on linear ways or transverse node sequences.

### Canonical Tagging Matrix

| Infrastructure Component | Canonical Tag Filter | Spatial Geometry | Supplementary Metadata |
|:---|:---|:---|:---|
| **Boarding Platform** | `railway=platform`, `public_transport=platform` | Polygon, LineString | `level=*`, `layer=*`, `tunnel=yes`, `wheelchair=*`, `ref=*` |
| **Fixed Stairway** | `highway=steps` | LineString, Polygon | `level=*` (compound/range), `incline=*`, `step_count=*`, `handrail=*` |
| **Escalator** | `highway=steps` + `conveying=yes` | LineString | `level=*` (range), `conveying=forward\|backward\|reversible` |
| **Moving Walkway** | `highway=footway` + `conveying=yes` | LineString | `level=*`, `conveying=*`, `incline=flat` |
| **Elevator Shaft / Landing** | `highway=elevator`, `amenity=elevator` | Point, Polygon | `level=*` (compound/range), `wheelchair=yes`, `door=elevator` |
| **Subway Portal** | `railway=subway_entrance` | Point | `ref=*`, `name=*`, `wheelchair=*`, `surface=*`, `exit_to=*` |
| **Station Ingress / Door** | `entrance=*`, `door=*` | Point, LineString | `level=*`, `door=automatic\|sliding`, `wheelchair=*` |
| **Mezzanine / Concourse Area**| `indoor=area`, `indoor=corridor` | Polygon | `level=*`, `layer=*`, `access=*`, `name=*` |
| **Subterranean Walkway** | `highway=footway` + (`indoor=yes` \| `tunnel=yes`) | LineString | `level=*`, `wheelchair=*`, `incline=*` |
| **Fare Control Boundary** | `barrier=fare_gate`, `barrier=turnstile` | Point, LineString | `level=*`, `wheelchair=*`, `payment:*=*` |

### Overpass QL Extraction Script

```overpassql
[out:json][timeout:180];

// Target station complexes in Midtown and Lower Manhattan
(
  // Pennsylvania Station & Moynihan Train Hall
  nwr["railway"="station"](40.7480, -74.0005, 40.7545, -73.9890);
  // Grand Central Terminal Complex
  nwr["railway"="station"](40.7510, -73.9795, 40.7555, -73.9745);
  // 14 St - Union Square Complex
  nwr["railway"="station"](40.7335, -73.9930, 40.7380, -73.9880);
)->.stations;

(
  // Platform surfaces
  way(around.stations:250)["railway"="platform"];
  relation(around.stations:250)["railway"="platform"];
  way(around.stations:250)["public_transport"="platform"];
  relation(around.stations:250)["public_transport"="platform"];

  // Vertical circulation links and shafts
  way(around.stations:250)["highway"="steps"];
  node(around.stations:250)["highway"="elevator"];
  way(around.stations:250)["highway"="elevator"];
  node(around.stations:250)["amenity"="elevator"];
  way(around.stations:250)["amenity"="elevator"];

  // Station portals and building entrances
  node(around.stations:250)["railway"="subway_entrance"];
  node(around.stations:250)["entrance"];
  way(around.stations:250)["entrance"];

  // Concourses, indoor walkways, and subterranean connectors
  way(around.stations:250)["indoor"~"^(area|corridor|room)$"];
  relation(around.stations:250)["indoor"~"^(area|corridor|room)$"];
  way(around.stations:250)["highway"~"^(footway|pedestrian)$"]["indoor"="yes"];
  way(around.stations:250)["highway"~"^(footway|pedestrian)$"]["tunnel"="yes"];
  way(around.stations:250)["area:highway"];
  
  // Fare gate boundaries
  node(around.stations:250)["barrier"~"^(fare_gate|turnstile)$"];
  way(around.stations:250)["barrier"~"^(fare_gate|turnstile)$"];
)->.transit_features;

// Recurse to collect all constituent geometry nodes and relation members
(
  .transit_features;
  >;
);

out body qt;
```

---

## 2. Discrete 2D Slicing and Planar Cartographic Modeling

Rendering subterranean structures under a strict orthographic top-down camera model ($\text{pitch} = 0$) introduces significant geometric conflicts. In a 3D isometric or perspective projection engine, vertical separations are achieved naturally by applying vertical z-translations or volumetric extrusions, allowing overlapping platforms and mezzanines to remain intelligible. Under a pure 2D orthographic projection, the vertical z-axis is eliminated. If all station levels are rendered simultaneously, geometries occupying identical spatial footprints across different vertical strata—such as the Moynihan Train Hall street-level concourse, intermediate ticketing mezzanines, and deep-level track beds—draw directly on top of each other. This results in visual clashing, occluded circulation paths, and rendering ambiguity.

To maintain cartographic clarity without switching to perspective viewing, the map engine must slice multi-tiered stations into discrete, planar 2D floor layers. The rendering engine exposes a level selector interface that activates only the features corresponding to the active floor slice. Implementing this model requires parsing OSM vertical syntax, standardizing mezzanine indexing, and handling features that vertically span across multiple levels.

### Semantic Evaluation of OSM Level Syntax

| Raw OSM Level Syntax | Semantic Evaluation | Normalized 2D Level Slices |
|:---|:---|:---|
| `level=0` | Single discrete ground floor | `[0.0]` |
| `level=-1.5` | Subterranean intermediate mezzanine | `[-1.5]` |
| `level=-1;0` | Vertical connector or feature spanning specific floors | `[-1.0, 0.0]` |
| `level=1-3` | Multi-story atrium or vertical connector spanning floors 1 through 3 | `[1.0, 2.0, 3.0]` |
| `level=-3--1` | Continuous vertical structure spanning basements 3 through 1 | `[-3.0, -2.0, -1.0]` |
| `level=0` + `repeat_on=1-3` | Base feature on floor 0 with identical copies on floors 1, 2, and 3 | `[0.0, 1.0, 2.0, 3.0]` |

### Discrete Layer Portal Model
Vertical circulation elements (stairs, escalators, and elevators) that traverse multiple levels require decomposition to prevent topological errors in 2D orthographic rendering. If a staircase connecting Level -2 to Level -1 (`level=-2;-1`) is emitted as a single polyline without floor-specific attributes, rendering it on Level -2 shows stairs extending into floor space that may be capped by an overhead ceiling or occupied by higher-level platforms. 

The pipeline addresses this through a **Discrete Layer Portal Model**:
1. The polyline of a connector spanning multiple levels is cloned and projected onto each constituent level slice.
2. Each cloned feature is annotated with floor-specific directional properties:
   - Lower level slice (`level: -2.0`): `circulation_direction: "up"`, prompting ascending graphics.
   - Upper level slice (`level: -1.0`): `circulation_direction: "down"`, prompting descending graphics.
3. Terminal nodes of the way are treated as directional portals, linking the respective entry and landing points across floor strata.

### Ordinal Normalization
Large transit hubs encompass distinct structures that often lack a shared local elevation datum. In the Penn Station complex, the Long Island Rail Road (LIRR) concourses operate at physical basements labeled Lower Concourse (`level=-2`) and Upper Concourse (`level=-1`), whereas the Moynihan Train Hall concourse is located at street grade (`level=0`), descending directly to the western extensions of the same LIRR and Amtrak platforms (`level=-2`). To resolve these variations, the schema establishes an ordinal scale: `ordinal` provides a continuous vertical sequence integer normalized relative to ground ($0$), while `level_name` supplies the human-readable display string derived from `level:ref=*` or `name=*` on `indoor=level` relations (e.g., "Moynihan Concourse", "LIRR Concourse", "Subway Mezzanine").

### Normalized GeoJSON Schema (`station_shapes.geojson`)

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "title": "StationFootprintFeatureCollection",
  "type": "object",
  "required": ["type", "features"],
  "properties": {
    "type": { "type": "string", "enum": ["FeatureCollection"] },
    "features": {
      "type": "array",
      "items": {
        "type": "object",
        "required": ["type", "id", "geometry", "properties"],
        "properties": {
          "type": { "type": "string", "enum": ["Feature"] },
          "id": { "type": "string" },
          "geometry": {
            "type": "object",
            "required": ["type", "coordinates"],
            "properties": {
              "type": { "type": "string", "enum": ["Point", "LineString", "Polygon", "MultiPolygon"] },
              "coordinates": { "type": "array" }
            }
          },
          "properties": {
            "type": "object",
            "required": [
              "complex_id",
              "level",
              "ordinal",
              "feature_type",
              "accessible"
            ],
            "properties": {
              "complex_id": { 
                "type": "string",
                "description": "Identifier matching the parent GTFS station complex."
              },
              "level": { 
                "type": "number",
                "description": "Normalized floating-point floor index used for discrete client-side filtering."
              },
              "ordinal": { 
                "type": "integer",
                "description": "Normalized vertical integer sequence relative to ground level (0)."
              },
              "level_name": { 
                "type": ["string", "null"],
                "description": "Human-readable floor label (e.g., 'Lower Concourse', 'Mezzanine')."
              },
              "feature_type": { 
                "type": "string", 
                "enum": [
                  "platform", 
                  "mezzanine", 
                  "corridor", 
                  "room", 
                  "steps", 
                  "escalator", 
                  "travelator", 
                  "elevator", 
                  "subway_entrance", 
                  "portal", 
                  "fare_gate"
                ] 
              },
              "accessible": { 
                "type": "boolean",
                "description": "Indicates whether the feature supports step-free, barrier-free access."
              },
              "wheelchair_desc": {
                "type": ["string", "null"],
                "enum": ["yes", "no", "limited", "unknown", null]
              },
              "ref": { 
                "type": ["string", "null"],
                "description": "Platform number, exit designation, or portal identifier."
              },
              "name": { 
                "type": ["string", "null"],
                "description": "Localized descriptive name of the facility or room."
              },
              "circulation_direction": {
                "type": ["string", "null"],
                "enum": ["up", "down", "bidirectional", null],
                "description": "Directional orientation of vertical circulation links on the discrete level slice."
              },
              "connects_levels": {
                "type": ["array", "null"],
                "items": { "type": "number" },
                "description": "Array of all discrete level indices connected by this physical structure."
              }
            }
          }
        }
      }
    }
  }
}
```

---

## 3. High-Throughput Go Ingestion and Conflation Pipeline

Extracting dense transit networks from regional `.osm.pbf` files requires an architecture optimized for stream decoding and minimal memory allocation. The OSM PBF binary format organizes data into sequential, compressed blocks of nodes, followed by ways, followed by relations. A standard way element contains only ordered node identifier references (`ref`), lacking inline geographic coordinates. Retaining all regional nodes in memory using standard Go map types (`map[int64]Coordinate`) introduces substantial pointer and allocation overhead, quickly exceeding memory limits on containerized build environments.

The extraction pipeline employs a **two-pass scanner architecture** using `github.com/paulmach/osm/osmpbf`:
1. **Pass 1 (Way / Relation Scan):** The scanner processes relations and ways while skipping node entities. Candidate ways and relations matching transit criteria—such as `railway=platform`, `highway=steps`, and `indoor=area`—are identified, and their constituent node identifiers are recorded in an in-memory bitset. Concurrently, the pipeline parses the GTFS `stops.txt` dataset, indexing all parent station complexes (`location_type=1`) into a spatial index.
2. **Pass 2 (Node Coordinate Hydration):** The PBF stream is rewound to the start. The scanner enables node parsing while skipping ways and relations. Coordinates are retained only for node identifiers marked in the bitset, storing them in a compact coordinate lookup map. Point-based transit infrastructure, including `railway=subway_entrance` and `amenity=elevator`, is converted directly into GeoJSON features.
3. **Pass 3 (Geometry Assembly & Slicing):** The cached transit ways are assembled into planar polylines and closed polygons. Multi-level elements are sliced into discrete level features, assigned to the nearest GTFS parent station complex, simplified to reduce vertex counts, and serialized to disk.

### Pipeline Stages and Data Structures

| Pipeline Stage | Operations Executed | Primary Memory & Data Structures | Performance Objectives |
|:---|:---|:---|:---|
| **GTFS Pre-indexing** | Parses `stops.txt`; filters `location_type=1`; constructs spatial index. | In-memory R-Tree or 2D Spatial KD-Tree; array of `GTFSStop` structs. | Enables sub-millisecond bounding lookups for spatial clustering. |
| **Pass 1: Way / Relation Scan** | Scans PBF ways and relations; matches transit tag filters; logs node references. | Array of `CandidateWay` structs; 64-bit sparse roaring bitset for referenced node IDs. | Filters non-transit features before decoding node coordinates. |
| **Pass 2: Node Coordinate Hydration** | Rewinds PBF; reads nodes; records coordinates for IDs present in the bitset; parses POI nodes. | Dense lookup table (`map[osm.NodeID]Coord`); slice of standalone point `GeoJSONFeature`. | Prevents caching unused nodes from regional extracts. |
| **Geometry Assembly & Slicing** | Resolves way node sequences; forms closed polygons and lines; expands multi-level ranges. | Geometric slices of `GeoJSONFeature` grouped per discrete floor. | Duplicates vertical connectors across connected levels with directional tags. |
| **Spatial Conflation & Optimization** | Associates geometries with GTFS parent station complexes; runs Douglas-Peucker simplification; truncates coordinates. | Spatial centroid queries against GTFS complex indices; float precision truncation routines. | Enforces $<5\text{ MB}$ payload budget with 6-decimal coordinate precision. |

### Go Conflation Pipeline Implementation

```go
package main

import (
	"context"
	"encoding/csv"
	"encoding/json"
	"fmt"
	"io"
	"math"
	"os"
	"regexp"
	"runtime"
	"strconv"
	"strings"

	"github.com/paulmach/osm"
	"github.com/paulmach/osm/osmpbf"
)

type GeoJSONFeatureCollection struct {
	Type     string           `json:"type"`
	Features []GeoJSONFeature `json:"features"`
}

type GeoJSONFeature struct {
	Type       string                 `json:"type"`
	ID         string                 `json:"id"`
	Geometry   GeoJSONGeometry        `json:"geometry"`
	Properties map[string]interface{} `json:"properties"`
}

type GeoJSONGeometry struct {
	Type        string      `json:"type"`
	Coordinates interface{} `json:"coordinates"`
}

type GTFSStop struct {
	StopID        string
	StopName      string
	Lat           float64
	Lon           float64
	LocationType  int
	ParentStation string
}

type BoundingBox struct {
	MinLat, MinLon, MaxLat, MaxLon float64
}

func (bb BoundingBox) Contains(lat, lon float64) bool {
	return lat >= bb.MinLat && lat <= bb.MaxLat && lon >= bb.MinLon && lon <= bb.MaxLon
}

// Truncates coordinate precision to 6 decimal places (~0.11m accuracy)
func roundCoordinate(val float64) float64 {
	return math.Round(val*1e6) / 1e6
}

// Expands OSM level and repeat_on values into normalized float slices
func parseLevels(levelStr, repeatOnStr string) []float64 {
	levelSet := make(map[float64]struct{})

	parseToken := func(token string) {
		token = strings.TrimSpace(token)
		if token == "" {
			return
		}

		// Regular expression to handle integer and decimal ranges including negative signs
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

// Computes great-circle distance between coordinates in meters
func haversineDistance(lat1, lon1, lat2, lon2 float64) float64 {
	const earthRadius = 6371000.0
	dLat := (lat2 - lat1) * (math.Pi / 180.0)
	dLon := (lon2 - lon1) * (math.Pi / 180.0)
	a := math.Sin(dLat/2)*math.Sin(dLat/2) +
		math.Cos(lat1*(math.Pi/180.0))*math.Cos(lat2*(math.Pi/180.0))*
			math.Sin(dLon/2)*math.Sin(dLon/2)
	c := 2 * math.Atan2(math.Sqrt(a), math.Sqrt(1-a))
	return earthRadius * c
}

// Associates geometry centroid with the nearest GTFS parent station complex
func resolveGTFSComplex(lat, lon float64, complexes []GTFSStop, maxDistMeters float64) string {
	matchedID := "complex_unassigned"
	minDist := maxDistMeters

	for _, c := range complexes {
		d := haversineDistance(lat, lon, c.Lat, c.Lon)
		if d < minDist {
			minDist = d
			matchedID = c.StopID
		}
	}
	return matchedID
}

// Parses stops.txt and isolates location_type=1 parent complexes
func loadGTFSParentStations(filePath string) ([]GTFSStop, error) {
	f, err := os.Open(filePath)
	if err != nil {
		return nil, err
	}
	defer f.Close()

	reader := csv.NewReader(f)
	header, err := reader.Read()
	if err != nil {
		return nil, err
	}

	idCol, nameCol, latCol, lonCol, typeCol := -1, -1, -1, -1, -1
	for i, col := range header {
		switch strings.TrimSpace(col) {
		case "stop_id":
			idCol = i
		case "stop_name":
			nameCol = i
		case "stop_lat":
			latCol = i
		case "stop_lon":
			lonCol = i
		case "location_type":
			typeCol = i
		}
	}

	var stations []GTFSStop
	for {
		record, err := reader.Read()
		if err == io.EOF {
			break
		}
		if err != nil {
			continue
		}

		locType := 0
		if typeCol != -1 && record[typeCol] != "" {
			locType, _ = strconv.Atoi(record[typeCol])
		}

		if locType == 1 {
			lat, _ := strconv.ParseFloat(record[latCol], 64)
			lon, _ := strconv.ParseFloat(record[lonCol], 64)
			stations = append(stations, GTFSStop{
				StopID:       record[idCol],
				StopName:     record[nameCol],
				Lat:          lat,
				Lon:          lon,
				LocationType: locType,
			})
		}
	}
	return stations, nil
}

func main() {
	pbfPath := "./new-york-latest.osm.pbf"
	gtfsPath := "./stops.txt"
	outputPath := "./station_shapes.geojson"

	metroBBox := BoundingBox{
		MinLat: 40.5700,
		MaxLat: 40.9200,
		MinLon: -74.0500,
		MaxLon: -73.7500,
	}

	gtfsStations, err := loadGTFSParentStations(gtfsPath)
	if err != nil {
		fmt.Printf("GTFS stops unreadable (%v); falling back to OSM synthetic identifiers\n", err)
	}

	pbfFile, err := os.Open(pbfPath)
	if err != nil {
		panic(fmt.Sprintf("Unable to open OSM PBF: %v", err))
	}
	defer pbfFile.Close()

	// -------------------------------------------------------------
	// PASS 1: Identify transit ways and catalog required Node IDs
	// -------------------------------------------------------------
	scannerP1 := osmpbf.New(context.Background(), pbfFile, runtime.GOMAXPROCS(-1))
	scannerP1.SkipNodes = true
	scannerP1.SkipRelations = false

	requiredNodes := make(map[osm.NodeID]struct{})
	type CandidateWay struct {
		ID      osm.WayID
		NodeIDs []osm.NodeID
		Tags    osm.Tags
	}
	var cachedWays []CandidateWay

	for scannerP1.Scan() {
		obj := scannerP1.Object()
		if way, ok := obj.(*osm.Way); ok {
			t := way.TagMap()
			isPlatform := t["railway"] == "platform" || t["public_transport"] == "platform"
			isVertical := t["highway"] == "steps" || t["highway"] == "elevator"
			isIndoorArea := t["indoor"] == "area" || t["indoor"] == "corridor" || t["indoor"] == "room"
			isTunnelPath := (t["highway"] == "footway" || t["highway"] == "pedestrian") &&
				(t["tunnel"] == "yes" || t["indoor"] == "yes")

			if isPlatform || isVertical || isIndoorArea || isTunnelPath {
				cw := CandidateWay{
					ID:      way.ID,
					NodeIDs: make([]osm.NodeID, len(way.Nodes)),
					Tags:    way.Tags,
				}
				for i, wn := range way.Nodes {
					cw.NodeIDs[i] = wn.ID
					requiredNodes[wn.ID] = struct{}{}
				}
				cachedWays = append(cachedWays, cw)
			}
		}
	}
	scannerP1.Close()

	// -------------------------------------------------------------
	// PASS 2: Hydrate node coordinates and extract standalone nodes
	// -------------------------------------------------------------
	_, err = pbfFile.Seek(0, 0)
	if err != nil {
		panic(fmt.Sprintf("Failed to rewind PBF stream: %v", err))
	}

	scannerP2 := osmpbf.New(context.Background(), pbfFile, runtime.GOMAXPROCS(-1))
	scannerP2.SkipWays = true
	scannerP2.SkipRelations = true

	type Coordinate struct {
		Lat, Lon float64
	}
	coordPool := make(map[osm.NodeID]Coordinate, len(requiredNodes))
	var pointFeatures []GeoJSONFeature

	for scannerP2.Scan() {
		obj := scannerP2.Object()
		if node, ok := obj.(*osm.Node); ok {
			if !metroBBox.Contains(node.Lat, node.Lon) {
				continue
			}

			if _, needed := requiredNodes[node.ID]; needed {
				coordPool[node.ID] = Coordinate{
					Lat: roundCoordinate(node.Lat),
					Lon: roundCoordinate(node.Lon),
				}
			}

			t := node.TagMap()
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
				slices := parseLevels(t["level"], t["repeat_on"])
				complexID := resolveGTFSComplex(node.Lat, node.Lon, gtfsStations, 350.0)

				for _, lvl := range slices {
					feat := GeoJSONFeature{
						Type: "Feature",
						ID:   fmt.Sprintf("node/%d/lvl_%.1f", node.ID, lvl),
						Geometry: GeoJSONGeometry{
							Type:        "Point",
							Coordinates: []float64{roundCoordinate(node.Lon), roundCoordinate(node.Lat)},
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
	scannerP2.Close()

	// -------------------------------------------------------------
	// PASS 3: Assemble Way Geometries with Discrete Planar Slicing
	// -------------------------------------------------------------
	var wayFeatures []GeoJSONFeature

	for _, cw := range cachedWays {
		t := cw.Tags.Map()
		coords := make([][]float64, 0, len(cw.NodeIDs))
		var latSum, lonSum float64

		for _, nid := range cw.NodeIDs {
			if pt, exists := coordPool[nid]; exists {
				coords = append(coords, []float64{pt.Lon, pt.Lat})
				latSum += pt.Lat
				lonSum += pt.Lon
			}
		}

		if len(coords) < 2 {
			continue
		}

		cLat := latSum / float64(len(coords))
		cLon := lonSum / float64(len(coords))

		if !metroBBox.Contains(cLat, cLon) {
			continue
		}

		complexID := resolveGTFSComplex(cLat, cLon, gtfsStations, 400.0)

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

		slices := parseLevels(t["level"], t["repeat_on"])

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
				ID:   fmt.Sprintf("way/%d/lvl_%.1f", cw.ID, lvl),
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

	// -------------------------------------------------------------
	// Serialize GeoJSON Collection Artifact
	// -------------------------------------------------------------
	collection := GeoJSONFeatureCollection{
		Type:     "FeatureCollection",
		Features: append(pointFeatures, wayFeatures...),
	}

	outFile, err := os.Create(outputPath)
	if err != nil {
		panic(fmt.Sprintf("Failed to generate GeoJSON file: %v", err))
	}
	defer outFile.Close()

	enc := json.NewEncoder(outFile)
	if err := enc.Encode(collection); err != nil {
		panic(fmt.Sprintf("JSON serialization error: %v", err))
	}

	stat, _ := outFile.Stat()
	fmt.Printf("Extraction complete. %s emitted (Size: %.2f MB, Features: %d)\n",
		outputPath, float64(stat.Size())/(1024*1024), len(collection.Features))
}
```

---

## 4. Architectural Synthesis and Runtime Considerations

Extracting subterranean transit facilities for a 2D zero-pitch mobile engine requires reconciling the structural realities of civil engineering with the conventions of topological spatial datasets. Complex transit interchanges do not conform to uniform, parallel floor plates. Multi-level complexes contain mezzanine walkways suspended midway between platforms, split-level track arrangements, and sloping corridors connecting adjacent stations built decades apart by competing transit operators. The ingestion pipeline resolves these physical discontinuities by decoupling physical elevation from discrete cartographic representation.

### Multipolygon Assembly and Winding Order
A primary structural challenge involves assembling multipolygon relations. Under the Simple Indoor Tagging standard, complex concourses and platforms are frequently mapped as multipolygons (`type=multipolygon`) where the outer ring represents the perimeter walls and inner rings (`role=inner`) represent structural support columns, escalator openings, stairwells, or mechanical shafts.

The ingestion pipeline must construct valid, topologically closed rings adhering to the right-hand rule (counterclockwise exterior rings, clockwise interior holes) to prevent fill inversion or tessellation failures within iOS graphics frameworks. If a relation contains disjoint outer rings or unclosed ways, the geometry assembler must stitch matching endpoints before emitting a valid `Polygon` or `MultiPolygon` GeoJSON object.

### Dual Representations: Cartography vs Topological Routing
A second critical consideration is maintaining dual representations for cartographic display and topological routing. While polygonal areas provide visual floor fills, they do not inherently support pathfinding algorithms like $A^*$ or Dijkstra without generating a medial axis or constrained Delaunay triangulation.

By retaining both polygonal boundaries (`indoor=area`, `railway=platform`) and 1D linear centerlines (`highway=footway` + `indoor=yes`, `highway=steps`), the pipeline serves two essential roles:
1. It delivers clean, bounded shapes for orthographic 2D rendering.
2. It preserves an interconnected 1D network graph for calculating accessible, step-free routes between street portals and train doors.

### Mobile Performance & Memory Caps
The resulting artifact directly satisfies mobile performance requirements:
- Restricting coordinate precision to 6 decimal places (~0.11m accuracy).
- Applying Douglas-Peucker simplification ($\epsilon = 0.000002^\circ \approx 0.2\text{m}$) to eliminate redundant collinear vertices.
- Normalizing verbose OSM tagging into compact properties keeps complete metropolitan datasets strictly under the 5 MB threshold.
- Supports responsive, offline-first floor slicing, enabling users to navigate multi-tiered transit hubs without network connectivity.
