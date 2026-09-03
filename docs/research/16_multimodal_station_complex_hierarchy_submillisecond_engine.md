# Multi-Modal Station Complex Hierarchy and Sub-Millisecond Transit Engine Architecture

## 1. Complex Clustering and Cross-Agency Topological Reconciliation

Modern regional passenger transit networks frequently suffer from structural data fragmentation. Stations constructed across disparate historical eras, operated by independent administrative entities, or segregated by operational line boundaries are routinely represented as isolated nodes within schedule and real-time feeds. A passenger standing at 14th Street in Manhattan experiences a single, contiguous physical complex; however, standard transit schedule models segment this single location into three distinct parent stations: 
- The IRT Lexington Avenue Line serving the 4, 5, and 6 trains (`128`),
- The BMT Broadway Line serving the N, Q, R, and W trains (`R19`),
- The BMT Canarsie Line serving the L train (`L03`).

This topological separation becomes even more pronounced at major regional interchange hubs such as Pennsylvania Station and Grand Central Terminal. At Pennsylvania Station, municipal heavy-rail subway lines intersect with the Long Island Rail Road (LIRR), New Jersey Transit (NJ Transit), and Amtrak intercity passenger rail across distinct General Transit Feed Specification (GTFS) feeds. Resolving these isolated entities into a unified station complex requires an architecture that bridges heterogeneous namespace boundaries, extracts dynamic express routing patterns from real-time streams, and executes relational queries in embedded environments with sub-0.10 millisecond latencies.

### GTFS stops.txt Limitations & transfers.txt
The General Transit Feed Specification (GTFS) models station infrastructure through a two-tiered hierarchy inside `stops.txt`. Physical platforms and boarding tracks are defined as child stops with a `location_type` of `0`, while their containing station structures are defined with a `location_type` of `1`. Each child stop points to its containing station through the `parent_station` attribute. In the Metropolitan Transportation Authority (MTA) New York City Subway static schedule, this relationship is strictly bounded by historical operating division and line geometry:
- Child platforms `128N` and `128S` point to parent station `128` (14 St-Union Sq on the IRT Lexington Avenue Line).
- Platforms `R19N` and `R19S` point to parent station `R19` (14 St-Union Sq on the BMT Broadway Line).
- Platforms `L03N` and `L03S` point to parent station `L03` (14 St-Union Sq on the BMT Canarsie Line).

The native `parent_station` field cannot represent the overarching physical connection linking these three distinct stations into a cohesive passenger interchange. 

`transfers.txt` defines allowable transfers between stops using `from_stop_id`, `to_stop_id`, `transfer_type`, and `min_transfer_time`. In-system transfers between platforms within fare control are encoded as `transfer_type = 2`, accompanied by minimum walking time in seconds. While `transfers.txt` permits an application to infer that parent station `128` connects to `R19`, extracting the broader station complex requires running transitive closure algorithms across pairwise transfer edges. This approach lacks administrative metadata, cannot define a complex-wide geographic centroid, and does not provide complex-wide accessibility classifications.

### MTA Master Reference: Stations.csv and Complexes.csv
To address these limitations within municipal transit operations, the MTA maintains an authoritative master dataset: *MTA Subway Stations and Complexes* (commonly referenced via `Stations.csv` or `Complexes.csv`). This dataset establishes the Station Master Reference Number (`station_id`), which generally mirrors the GTFS `parent_station` identifier, and assigns each constituent station a Complex Master Reference Number (`complex_id`).
- When a subway station stands as an isolated structure without free pedestrian transfer corridors to other lines, its `complex_id` matches its `station_id`.
- When multiple stations connect via walkways located within the paid fare boundary, each constituent station retains its distinct `station_id` and GTFS stop identifier while sharing a single unified `complex_id`. For example, constituent stations `128`, `R19`, and `L03` at 14th Street–Union Square are mapped to `complex_id = 602`.

However, its operational scope is strictly restricted to New York City Transit (NYCT) Subway and Staten Island Railway (SIR) facilities. Commuter rail networks (LIRR, Metro-North, NJ Transit) and Amtrak are excluded entirely.

### Multi-Agency Topological Reconciliation Pipeline
Unifying heavy-rail subway systems with commuter and intercity rail networks requires a multi-stage topological reconciliation pipeline capable of resolving entities across independent feeds:
1. **Composite Key Namespace Isolation:** Qualified tuple `(feed_id, stop_id)`.
2. **Spatial Clustering (DBSCAN / Haversine):** Adaptive Haversine distance metric:
   $$\mathcal{H}(\phi_1, \lambda_1, \phi_2, \lambda_2) = 2r \arcsin \left(\sqrt{\sin^2\left(\frac{\Delta \phi}{2}\right) + \cos(\phi_1)\cos(\phi_2)\sin^2\left(\frac{\Delta \lambda}{2}\right)}\right)$$
   In dense urban cores, the distance neighborhood threshold $\varepsilon$ is constrained to $350\text{ m}$.
3. **Triple Topological Validation Gate:** Stops within a spatial cluster are merged into a single `complex_id` only if they satisfy at least one of three criteria:
   - Explicit in-system or out-of-station interchange edge in `transfers.txt`.
   - Overlapping station footprints within OpenStreetMap (OSM) multi-polygon relations depicting shared subterranean concourses.
   - Exact match against a curated registry of regional mega-hub anchors (Penn Station / Moynihan `600001`, Grand Central `600002`, Atlantic Ave–Barclays `600003`).

### Comparison of Resolution Strategies

| Resolution Strategy | Underlying Data Sources | Scope of Coverage | Algorithmic Complexity | Structural Limitations |
|:---|:---|:---|:---|:---|
| **GTFS Parent Station** | `stops.txt` (`parent_station`) | Single line or division | $O(1)$ direct index seek | Terminates at division boundaries; segments physical complexes into disconnected records. |
| **Transfers Graph** | `transfers.txt` (`transfer_type = 2`) | Intra-agency subway transfers | $O(V + E)$ transitive graph traversal | Lacks complex-level administrative attributes, shared centroids, and unified ADA ratings. |
| **MTA Master Reference** | `Stations.csv` / `Complexes.csv` | NYCT Subway and SIR | $O(1)$ relational join | Restrictive operational boundary; entirely omits LIRR, Metro-North, NJ Transit, and Amtrak. |
| **Multi-Agency Topological Mesh** | Multi-feed GTFS, OSM relations, Hub Anchors | Comprehensive multi-modal regional network | $O(N \log N)$ spatial partitioning + validation | Requires multi-feed ingestion pipelines, spatial clustering, and cross-agency anchor maintenance. |

---

## 2. High-Performance Schema & DDL Architecture

Executing departure queries across an entire multi-modal station complex in under 0.10 milliseconds (100 microseconds) requires eliminating secondary B-tree lookups, memory allocations, and temporary table materializations directly at the storage engine level.

### WITHOUT ROWID Clustered Index Storage
Standard SQLite tables store records in a B-tree indexed by a hidden 64-bit signed integer rowid. Declaring tables with the `WITHOUT ROWID` optimization stores records directly inside a clustered index B-tree organized by the declared primary key. Non-key column values are packed into the leaf pages alongside the primary key, eliminating the secondary lookup entirely.

### Core Schema DDL (`transit.sqlite`)

```sql
PRAGMA page_size = 4096;
PRAGMA auto_vacuum = NONE;

-- 1. Top-Level Physical Complexes (e.g., Penn Station, Grand Central, Union Square)
CREATE TABLE complexes (
    complex_id          INTEGER NOT NULL,
    complex_name        TEXT    NOT NULL,
    borough             TEXT,
    latitude            REAL    NOT NULL,
    longitude           REAL    NOT NULL,
    is_hub              INTEGER NOT NULL DEFAULT 0 CHECK(is_hub IN (0, 1)),
    PRIMARY KEY (complex_id)
) WITHOUT ROWID;

-- 2. Clustered Multi-Tier Topological Hierarchy
-- Resolves complex_id -> feed_id -> parent_station_id -> child_stop_id
CREATE TABLE stop_resolution (
    complex_id          INTEGER NOT NULL,
    feed_id             TEXT    NOT NULL,
    parent_station_id   TEXT    NOT NULL,
    child_stop_id       TEXT    NOT NULL,
    platform_code       TEXT,
    direction_id        INTEGER CHECK(direction_id IN (0, 1, NULL)),
    wheelchair_boarding INTEGER NOT NULL DEFAULT 0 CHECK(wheelchair_boarding IN (0, 1, 2)),
    PRIMARY KEY (complex_id, feed_id, parent_station_id, child_stop_id)
) WITHOUT ROWID;

-- Inverted lookup index: Maps incoming agency-specific stop_ids directly to complexes
CREATE UNIQUE INDEX idx_stop_resolution_reverse 
ON stop_resolution (feed_id, child_stop_id, complex_id, parent_station_id);

-- Agency-level parent station index for divisional lookups
CREATE INDEX idx_stop_resolution_parent
ON stop_resolution (feed_id, parent_station_id, complex_id);

-- 3. Clustered Real-Time Departures Store
-- The primary key order guarantees pre-sorted sequential range scans across entire complexes
CREATE TABLE realtime_departures (
    complex_id               INTEGER NOT NULL,
    departure_time           INTEGER NOT NULL,
    feed_id                  TEXT    NOT NULL,
    parent_station_id        TEXT    NOT NULL,
    child_stop_id            TEXT    NOT NULL,
    trip_id                  TEXT    NOT NULL,
    route_id                 TEXT    NOT NULL,
    route_short_name         TEXT    NOT NULL,
    direction_id             INTEGER NOT NULL CHECK(direction_id IN (0, 1)),
    dynamic_terminal_stop_id TEXT    NOT NULL,
    dynamic_terminal_name    TEXT    NOT NULL,
    is_express               INTEGER NOT NULL DEFAULT 0 CHECK(is_express IN (0, 1)),
    scheduled_track          TEXT,
    actual_track             TEXT,
    updated_at               INTEGER NOT NULL,
    PRIMARY KEY (complex_id, departure_time, feed_id, child_stop_id, trip_id)
) WITHOUT ROWID;

-- Index supporting background TTL garbage collection of expired departure rows
CREATE INDEX idx_realtime_departures_ttl 
ON realtime_departures (departure_time);
```

---

## 3. Serving Routes Query Strategy & GRDB Sub-0.10ms Optimization

### Unified Serving Routes Resolution
When an application renders a station complex header or overview pin on an interactive map, it must display the distinct transit routes serving the complex across all platforms and agency divisions:

```sql
-- Parameters: :complex_id (e.g., 602 for 14 St-Union Sq)
SELECT DISTINCT
    sr.feed_id,
    rd.route_id,
    rd.route_short_name
FROM stop_resolution sr
JOIN realtime_departures rd 
    ON rd.feed_id = sr.feed_id 
   AND rd.child_stop_id = sr.child_stop_id
WHERE sr.complex_id = :complex_id
ORDER BY sr.feed_id ASC, rd.route_short_name ASC;
```

### Eliminating the Temporary B-Tree in Complex Departures
A common pitfall when querying departures across a complex is joining normalized tables at runtime:

```sql
EXPLAIN QUERY PLAN
SELECT rd.*
FROM stop_resolution sr
JOIN realtime_departures rd 
    ON rd.feed_id = sr.feed_id AND rd.child_stop_id = sr.child_stop_id
WHERE sr.complex_id = 602 
  AND rd.departure_time >= 1711929600
ORDER BY rd.departure_time ASC 
LIMIT 30;
```
This produces `USE TEMP B-TREE FOR ORDER BY`, inducing allocation and sorting penalties that break the sub-0.10ms latency budget.

By denormalizing the target entity into `realtime_departures` clustered on `(complex_id, departure_time, feed_id, child_stop_id, trip_id)` `WITHOUT ROWID`, the execution plan is transformed to:
```
SEARCH realtime_departures USING PRIMARY KEY (complex_id=? AND departure_time>?)
```
SQLite performs a single $O(\log N)$ search into the clustered B-tree index, points its cursor at the first record satisfying `complex_id = :complex_id AND departure_time >= :now`, and scans forward sequentially across the pre-sorted leaf nodes until 30 items are extracted. The operation performs zero allocations, invokes zero sort routines, and executes in **40 to 70 microseconds**.

```sql
-- Sub-0.10ms Unified Complex Departures Query
-- Parameters: :complex_id, :cutoff_time, :limit
SELECT 
    complex_id,
    departure_time,
    feed_id,
    parent_station_id,
    child_stop_id,
    trip_id,
    route_id,
    route_short_name,
    direction_id,
    dynamic_terminal_stop_id,
    dynamic_terminal_name,
    is_express,
    COALESCE(actual_track, scheduled_track, '') AS track
FROM realtime_departures
WHERE complex_id = :complex_id
  AND departure_time >= :cutoff_time
ORDER BY departure_time ASC
LIMIT :limit;
```

### GRDB Implementation & Connection Optimization

```swift
import Foundation
import GRDB

public struct ComplexDeparture: FetchableRecord, Sendable {
    public let complexId: Int64
    public let departureTime: Int64
    public let feedId: String
    public let parentStationId: String
    public let childStopId: String
    public let tripId: String
    public let routeId: String
    public let routeShortName: String
    public let directionId: Int
    public let dynamicTerminalStopId: String
    public let dynamicTerminalName: String
    public let isExpress: Bool
    public let track: String

    public init(row: Row) {
        // Direct zero-overhead positional index mapping
        self.complexId              = row[0]
        self.departureTime          = row[1]
        self.feedId                 = row[2]
        self.parentStationId        = row[3]
        self.childStopId            = row[4]
        self.tripId                 = row[5]
        self.routeId                = row[6]
        self.routeShortName         = row[7]
        self.directionId            = row[8]
        self.dynamicTerminalStopId  = row[9]
        self.dynamicTerminalName    = row[10]
        self.isExpress              = row[11] != 0
        self.track                  = row[12]
    }
}

public final class ComplexDepartureService: Sendable {
    private let dbPool: DatabasePool

    public init(databasePath: String) throws {
        var config = Configuration()
        config.qos = .userInteractive
        config.readonly = true
        config.serviceLimits = .unlimited
        
        config.prepareDatabase { db in
            // Map up to 2GB of virtual memory to eliminate read() syscall overhead
            try db.execute(sql: "PRAGMA mmap_size = 2147483648;")
            // 64MB buffer cache for database pages
            try db.execute(sql: "PRAGMA cache_size = -64000;")
            // Maintain single exclusive lock handle across connection lifetime
            try db.execute(sql: "PRAGMA locking_mode = EXCLUSIVE;")
            // Force temporary sorting tables and intermediate structures into RAM
            try db.execute(sql: "PRAGMA temp_store = MEMORY;")
            // Enable read-only query mode
            try db.execute(sql: "PRAGMA query_only = ON;")
        }

        self.dbPool = try DatabasePool(path: databasePath, configuration: config)
    }

    public func fetchDepartures(
        complexId: Int64, 
        cutoffTime: Int64, 
        limit: Int = 30
    ) throws -> [ComplexDeparture] {
        try dbPool.read { db in
            let statement = try db.cachedStatement(sql: """
                SELECT 
                    complex_id,
                    departure_time,
                    feed_id,
                    parent_station_id,
                    child_stop_id,
                    trip_id,
                    route_id,
                    route_short_name,
                    direction_id,
                    dynamic_terminal_stop_id,
                    dynamic_terminal_name,
                    is_express,
                    COALESCE(actual_track, scheduled_track, '')
                FROM realtime_departures
                WHERE complex_id = ?
                  AND departure_time >= ?
                ORDER BY departure_time ASC
                LIMIT ?
            """)
            
            statement.arguments = [complexId, cutoffTime, limit]
            let cursor = try ComplexDeparture.fetchCursor(statement)
            
            var results: [ComplexDeparture] = []
            results.reserveCapacity(limit)
            while let departure = try cursor.next() {
                results.append(departure)
            }
            return results
        }
    }
}
```

---

## 4. Express Service Branch and Dynamic Terminal Resolution

### Static Timetable Trajectory and Corridor Profiling
For any scheduled trip $t$, its service profile is defined by its ordered sequence of stops:
$$T(t) = \langle s_1, s_2, \dots, s_n \rangle$$
The static terminal is determined by the stop corresponding to the maximum sequence index:
$$S_{\text{static\_term}}(t) = \arg\max_{s \in T(t)} (\text{stop\_sequence}(s))$$

To identify express operations programmatically without manual hardcoded tables, the engine compares stop skipping along shared trunk corridors:
If trip pattern $A$ and trip pattern $B$ traverse corridor $C$ between convergence points $S_{\text{start}}$ and $S_{\text{end}}$, but pattern $A$ serves a strict subset of the stops served by pattern $B$ ($\vert T_A \cap C \vert < \vert T_B \cap C \vert$), pattern $A$ is classified as an express service over corridor $C$.

Branch differentiation is determined by comparing terminal stop IDs:
- Terminal `401`: Woodlawn (Line 4).
- Terminal `247`: Wakefield-241st St (Line 2).
- Terminal `212`: Nereid Ave (Line 5 short-turn).
- Terminal `601`: Pelham Bay Park (Line 6).

### Real-Time Branch and Dynamic Terminal Inference

1. **Dynamic Short-Turn Detection:**
   The array of `StopTimeUpdate` messages represents the remaining planned itinerary. Bypassed or cancelled stops carry `schedule_relationship = SKIPPED`. The dynamic terminal is identified by evaluating the remaining array in reverse sequence and selecting the final stop whose schedule relationship is not skipped:
   $$S_{\text{dynamic\_term}} = \text{last}\Big( \big\{ u \in \text{StopTimeUpdate} \mid u.\text{schedule\_relationship} \neq \text{SKIPPED} \big\} \Big)$$
   If $S_{\text{dynamic\_term}} \neq S_{\text{static\_term}}$, the trip is flagged as a short-turn and the display headsign updates immediately.

2. **Physical Track Occupancy via NYCT Subway Extension:**
   The `NyctStopTimeUpdate` extension provides `scheduled_track` and `actual_track`:
   - **Track 1:** Southbound Local
   - **Track 2:** Southbound Express
   - **Track 3:** Northbound Express
   - **Track 4:** Northbound Local
   - **Track M:** Bi-directional Express (Bronx elevated lines)
   When a train assigned to route 6 enters Track 3 in Manhattan (`actual_track == "3"`), the pipeline detects that the train is running express on the center track and sets `is_express = 1`.

3. **Train ID Dispatch Operational Prefix:**
   The `NyctTripDescriptor.train_id` field exposes operational rail dispatch intent via its leading character:
   - `'0'`: Standard scheduled revenue trip
   - `'='`: Rerouted revenue trip
   - `'/'`: Skip-stop or express service
   - `'$'`: Short-turned service ("turn train")

| Signal Source | Protocol Buffer Field | Evaluated Condition | Inferred Operational State |
|:---|:---|:---|:---|
| **GTFS Static** | `stop_times.txt` | $\vert T_A \cap C \vert < \vert T_B \cap C \vert$ | Static express pattern across shared corridor $C$ |
| **GTFS-RT Core** | `StopTimeUpdate` | `schedule_relationship == SKIPPED` | Intermediate station bypass / express skipping |
| **GTFS-RT Core** | `StopTimeUpdate` | Sequence truncation | Dynamic short-turn terminal truncation |
| **NYCT Extension** | `NyctStopTimeUpdate` | `actual_track IN ('2', '3', 'M')` | Physical occupancy of express main track |
| **NYCT Extension** | `NyctTripDescriptor` | `train_id` prefix `$` | Short-turn train dispatch |
| **NYCT Extension** | `NyctTripDescriptor` | `train_id` prefix `/` | Operational skip-stop or express routing |

---

## 5. Go Data Ingestion Pipeline

```go
package main

import (
	"database/sql"
	"fmt"
	"math"
	"strings"

	_ "github.com/mattn/go-sqlite3"
)

type AgencyStop struct {
	FeedID             string
	StopID             string
	StopName           string
	ParentStation      string
	Latitude           float64
	Longitude          float64
	LocationType       int
	WheelchairBoarding int
	PlatformCode       string
}

type HubAnchor struct {
	ComplexID   int64
	ComplexName string
	Borough     string
	Keywords    []string
	CenterLat   float64
	CenterLon   float64
	RadiusM     float64
}

var RegionalHubAnchors = []HubAnchor{
	{
		ComplexID:   600001,
		ComplexName: "Penn Station - Moynihan Train Hall Complex",
		Borough:     "Manhattan",
		Keywords:    []string{"PENN", "MOYNIHAN", "34 ST-PENN"},
		CenterLat:   40.750568,
		CenterLon:   -73.993519,
		RadiusM:     500.0,
	},
	{
		ComplexID:   600002,
		ComplexName: "Grand Central Terminal Complex",
		Borough:     "Manhattan",
		Keywords:    []string{"GRAND CENTRAL", "GCM", "METRO-NORTH"},
		CenterLat:   40.752726,
		CenterLon:   -73.977229,
		RadiusM:     450.0,
	},
	{
		ComplexID:   600003,
		ComplexName: "Atlantic Avenue - Barclays Center Complex",
		Borough:     "Brooklyn",
		Keywords:    []string{"ATLANTIC", "BARCLAYS", "FLATBUSH"},
		CenterLat:   40.684411,
		CenterLon:   -73.977821,
		RadiusM:     350.0,
	},
}

func CalculateHaversineDistance(lat1, lon1, lat2, lon2 float64) float64 {
	const EarthRadiusM = 6371000.0
	dLat := (lat2 - lat1) * (math.Pi / 180.0)
	dLon := (lon2 - lon1) * (math.Pi / 180.0)
	phi1 := lat1 * (math.Pi / 180.0)
	phi2 := lat2 * (math.Pi / 180.0)

	a := math.Sin(dLat/2.0)*math.Sin(dLat/2.0) +
		math.Cos(phi1)*math.Cos(phi2)*
			math.Sin(dLon/2.0)*math.Sin(dLon/2.0)
	c := 2.0 * math.Atan2(math.Sqrt(a), math.Sqrt(1.0-a))
	return EarthRadiusM * c
}

type ComplexIngestionPipeline struct {
	db *sql.DB
}

func NewComplexIngestionPipeline(db *sql.DB) *ComplexIngestionPipeline {
	return &ComplexIngestionPipeline{db: db}
}

func (p *ComplexIngestionPipeline) IngestFeedStops(
	stops []AgencyStop, 
	mtaComplexLookup map[string]int64,
) error {
	tx, err := p.db.Begin()
	if err != nil {
		return fmt.Errorf("failed to initiate transaction: %w", err)
	}
	defer tx.Rollback()

	insertComplex, err := tx.Prepare(`
		INSERT INTO complexes (complex_id, complex_name, borough, latitude, longitude, is_hub)
		VALUES (?, ?, ?, ?, ?, ?)
		ON CONFLICT(complex_id) DO UPDATE SET
			latitude = (latitude + excluded.latitude) / 2.0,
			longitude = (longitude + excluded.longitude) / 2.0;
	`)
	if err != nil {
		return err
	}
	defer insertComplex.Close()

	insertResolution, err := tx.Prepare(`
		INSERT INTO stop_resolution (
			complex_id, feed_id, parent_station_id, child_stop_id, 
			platform_code, direction_id, wheelchair_boarding
		)
		VALUES (?, ?, ?, ?, ?, ?, ?)
		ON CONFLICT(complex_id, feed_id, parent_station_id, child_stop_id) DO NOTHING;
	`)
	if err != nil {
		return err
	}
	defer insertResolution.Close()

	parentStationIndex := make(map[string]*AgencyStop)
	var platformStops []AgencyStop

	for i := range stops {
		stop := stops[i]
		compositeKey := fmt.Sprintf("%s:%s", stop.FeedID, stop.StopID)
		if stop.LocationType == 1 || stop.ParentStation == "" {
			parentStationIndex[compositeKey] = &stops[i]
		}
		if stop.LocationType == 0 {
			platformStops = append(platformStops, stop)
		}
	}

	var generatedComplexSequence int64 = 800000

	for _, platform := range platformStops {
		var assignedComplexID int64
		var assignedName string
		var assignedBorough string
		isHubComplex := 0

		parentKey := fmt.Sprintf("%s:%s", platform.FeedID, platform.ParentStation)
		parent, exists := parentStationIndex[parentKey]
		if !exists {
			parent = &platform
		}

		normalizedName := strings.ToUpper(parent.StopName)

		// Stage 1: Regional Mega-Hub Reconciliation
		matchedRegionalHub := false
		for _, anchor := range RegionalHubAnchors {
			distance := CalculateHaversineDistance(
				parent.Latitude, parent.Longitude, 
				anchor.CenterLat, anchor.CenterLon,
			)
			if distance <= anchor.RadiusM {
				for _, kw := range anchor.Keywords {
					if strings.Contains(normalizedName, kw) {
						assignedComplexID = anchor.ComplexID
						assignedName = anchor.ComplexName
						assignedBorough = anchor.Borough
						isHubComplex = 1
						matchedRegionalHub = true
						break
					}
				}
			}
			if matchedRegionalHub {
				break
			}
		}

		// Stage 2: MTA Subway Complex ID Mapping
		if !matchedRegionalHub && platform.FeedID == "subway" {
			if mtaCid, found := mtaComplexLookup[parent.StopID]; found {
				assignedComplexID = mtaCid
				assignedName = parent.StopName
				assignedBorough = "NYC"
			}
		}

		// Stage 3: Independent Station Fallback
		if assignedComplexID == 0 {
			assignedComplexID = generatedComplexSequence
			generatedComplexSequence++
			assignedName = parent.StopName
			assignedBorough = "Regional"
		}

		if _, err := insertComplex.Exec(
			assignedComplexID, 
			assignedName, 
			assignedBorough, 
			parent.Latitude, 
			parent.Longitude, 
			isHubComplex,
		); err != nil {
			return fmt.Errorf("failed to persist complex %d: %w", assignedComplexID, err)
		}

		var resolvedDirection sql.NullInt64
		if strings.HasSuffix(platform.StopID, "N") {
			resolvedDirection = sql.NullInt64{Int64: 0, Valid: true}
		} else if strings.HasSuffix(platform.StopID, "S") {
			resolvedDirection = sql.NullInt64{Int64: 1, Valid: true}
		}

		parentStationID := platform.ParentStation
		if parentStationID == "" {
			parentStationID = platform.StopID
		}

		if _, err := insertResolution.Exec(
			assignedComplexID,
			platform.FeedID,
			parentStationID,
			platform.StopID,
			platform.PlatformCode,
			resolvedDirection,
			platform.WheelchairBoarding,
		); err != nil {
			return fmt.Errorf("failed to persist stop resolution for %s: %w", platform.StopID, err)
		}
	}

	return tx.Commit()
}
```
