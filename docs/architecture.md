# Fog of Wburg: Architecture & Technical Specification

This document defines the strictly enforced architectural paradigms, library choices, and data flows for **Fog of Wburg**. The application is an offline-first, battery-conscious iOS/Apple Watch app built entirely within the Expo Managed Workflow (Continuous Native Generation).

Our primary technical hurdle is rendering a dynamic, user-generated "fog of war" map. We achieve a buttery 60fps experience by heavily optimizing React Native bridge communications, geometry unioning, and leveraging low-level JSI (JavaScript Interface) memory sharing.

---

## 1. Core Library Stack

Do not deviate from these specific packages. They have been selected to bypass asynchronous bridge bottlenecks and guarantee native-level performance without ejecting from Expo.

| Package Name | Version | Architectural Role |
| --- | --- | --- |
| `expo` | `^51.0.0+` | Core framework. Required for CNG plugin support. |
| `@maplibre/maplibre-react-native` | `^11.3.0+` | Definitive map engine. Supports JSI synchronous GeoJSON updates and 3D terrain. |
| `h3-js` | `^4.1.0` | Emscripten-compiled spatial index logic. Handles all `gridDisk` and geometry union operations. |
| `@op-engineering/op-sqlite` | `^3.0.0` | JSI-powered SQLite engine. Enables microsecond, synchronous read/writes. |
| `expo-location` | `^17.0.0+` | Interfaces with iOS CoreLocation for foreground/background tracking. |
| `expo-task-manager` | `^11.0.0+` | Registers headless background execution tasks. |
| `zustand` | `^4.5.0+` | Lightweight, non-blocking UI state management. |
| `protobufjs` & `gtfs-realtime-bindings` | `latest` | On-the-fly decoding of binary GTFS-RT transit feeds. |

---

## 2. Unidirectional Data Flow Blueprint

The application state flows in a strict, non-blocking sequence to prevent background location updates from freezing the main UI thread.

1. **Hardware:** iOS CoreLocation batches GPS coordinates (every 50 meters).
2. **Background Task:** `expo-location` receives the batch, filters out GPS drift, and calculates implied speed.
3. **Spatial Engine:** `h3-js` converts valid coordinates to Resolution 11 H3 hexes and calculates the buffer radius.
4. **Persistence & Set Gate:** `@op-engineering/op-sqlite` holds the persistent state. On app load, unlocked hexes are cached into a JavaScript `Set`. 
5. **The Micro-Calculation:** When a new coordinate arrives, `h3-js` converts it. We instantly check `Set.has(currentH3Index)`. If true, execution is dropped entirely, keeping the bridge completely silent.
6. **State Update:** If a new hex is discovered, it is inserted into the `Set`, written to SQLite (`INSERT OR IGNORE`), and added to the Zustand store.
7. **Bridge Bypass (DDS):** The array of unlocked H3 IDs is passed to `@maplibre/maplibre-react-native`.
8. **Render:** We use MapLibre Data-Driven Styling (DDS) with a `['match']` expression on `fill-opacity` to instantly hide the discovered hexes, offloading all spatial hole-punching math to the C++ GPU layer.

---

## 3. The Fog Engine (MapLibre Rendering)

Rendering tens of thousands of individual hexagons will cause catastrophic frame drops. The app must utilize an **Inverted Polygon** approach combined with **Dynamic Regional Loading**.

* **Dynamic Regional Loading:** Never generate a worldwide fog polygon. On initialization, generate a 50km x 50km GeoJSON bounding box centered on the user's current GPS coordinate.
* **Temporal Interpolation:** Configure MapLibre `fill-opacity-transition: { duration: 300 }` on the fog mask layer for smooth, organic fog dissolve rather than instant pop-in.
* **Layer Stacking (The 3-Tier Visibility Model):** Achieve the desired aesthetics using standard MapTiler layers beneath the fog mask.
  * **Layer 1 (The Explored Base):** The base MapTiler `streets-v2` vector style. This represents areas the user has previously explored, revealed by holes in the fog layer.
  * **Layer 2 (The Visible Base):** (Deprecated in MVP) Future support for dynamic active area highlighting.
  * **Layer 3 (The Sub-Context):** Faint vectors of major geographic arteries (coastlines, bridges) with zero text labels.
  * **Layer 4 (The Cloud Layer):** The base H3 grid loaded as a static geometry source, acting as the fog.
  * **Layer 5 (The DDS Filter):** We dynamically filter the `fill-opacity` of Layer 4. By passing the array of unlocked H3 IDs into a MapLibre `['match']` expression, we make unlocked hexes fully transparent, revealing the layers beneath.
  * **Layer 6 (The Vicinity Bubble):** Detailed geospatial data (street names, transit nodes, Ghost POIs) rendered strictly within a dynamic 200m radius of the user's live location.


* **Algorithmic Simplification:** The legacy approach of using `h3.cellsToMultiPolygon` to generate a massive GeoJSON with holes is **deprecated**. We strictly use Data-Driven Styling (DDS) to avoid sending heavy JSON strings over the React Native bridge, reducing UI thread starvation.
* **Synchronous Updates:** To prevent UI freezing during large updates, you must enable `withSynchronousUpdate(true)` on the MapLibre `ShapeSource` to bypass `JSON.stringify` serialization.

---

## 4. High-Performance Offline Persistence (SQLite)

The local database must handle continuous, high-frequency spatial lookups while the user is moving. We bypass standard asynchronous wrappers (like WatermelonDB) in favor of the JSI-powered `@op-engineering/op-sqlite`.

* **64-bit Precision Constraint:** H3 indexes are 64-bit integers. JavaScript loses precision on integers this large. All H3 indexes must be stored and passed as 15-character hexadecimal strings (e.g., "8b2a100d213fff").
* **WAL Mode:** Write-Ahead Logging (`PRAGMA journal_mode = WAL;`) allows concurrent readers and writers, ensuring the background location tracker can insert data without blocking the UI map rendering.

**Optimal Schema Implementation:**

```sql
PRAGMA journal_mode = WAL;
PRAGMA synchronous = NORMAL;

CREATE TABLE explored_hexes (
    h3_index TEXT PRIMARY KEY,
    discovered_at INTEGER NOT NULL
) WITHOUT ROWID;

-- Used for the 3-Tier active visibility tracking (reference counting)
CREATE TABLE active_visibility (
    h3_index TEXT PRIMARY KEY,
    reference_count INTEGER NOT NULL
) WITHOUT ROWID;

```

*Note for contributors: The `WITHOUT ROWID` declaration is mandatory. It forces SQLite to use the string `h3_index` directly as the clustered B-Tree index, reducing disk footprint by 30% and maximizing lookup speeds.*

---

## 5. Background Location & Energy Economics

Continuous background tracking will drain the battery and result in App Store rejection if configured incorrectly. Time-based polling is strictly prohibited. The app uses an **ambient tracking model**, automatically requesting permissions and tracking silently upon launch. The explicit goal is for the app to track user progress on the map at all times, even when the screen is off or the app is in the background, without ever requiring the user to press a 'record' button. The architecture relies on OS-level distance filtering to allow the CPU to sleep when the user is stationary.

Configure `expo-location` with the following parameters:

* **`accuracy`**: `Location.Accuracy.Balanced` (Provides ~10-25m accuracy, sufficient for our buffer radius while saving power).
* **`distanceInterval`**: `10` (Only wakes the app when physical movement occurs).
* **`deferredUpdatesDistance`**: `50` (Batches location points in the GPS chip's memory, waking the CPU only once per 50 meters of travel).
* **`pausesLocationUpdatesAutomatically`**: `true` (Allows iOS to shut down the radio if the accelerometer detects zero movement).
* **`activityType`**: `Location.ActivityType.Fitness` (Ensures proper OS prioritization).

**The Implied Speed Filter:**
To prevent GPS multipath errors (urban canyon drift) from artificially unlocking city blocks while the user is stationary indoors, all incoming background coordinates must pass a velocity gate. Calculate the speed between sequential points. If $\Delta d / \Delta t > 12 \text{ m/s}$, the coordinate must be discarded as multipath noise.

---

## 6. The Vicinity Bubble & Transit Pipeline

To support the "ambient explorer" progressive disclosure model, detailed mapping information is decoupled from the global map state and bound strictly to the user's physical presence.

* **Spatial Querying (200m Radius):** Detailed vector layers (street labels, transit nodes, Ghost POIs) are masked by a dynamic 200m radius around the live GPS coordinate. When the user pans away from their location, these elements are suppressed to maintain a pristine map.
* **Unified Transit Decoding (GTFS-RT Protobuf):** Transit nodes act as "Ghost POIs". Upon interaction, the app bypasses third-party aggregators and fetches data directly from the transit authority. The app standardizes on binary Protocol Buffers (`protobufjs`), parsing GTFS-RT feeds for both Subway and Bus nodes uniformly. This eliminates the heavy JSON serialization overhead previously required by the legacy MTA SIRI API. Service Alerts must correctly parse MTA's `informed_entity` structure (handling separate station-level nodes and specific `direction_id` flags).
* **Historical Sync (Multi-Region):** The app silently fetches a highly compressed, statically generated Zstandard SQLite database (e.g., `nyc_transit_delta.sqlite.zst` or `boston_transit_delta.sqlite.zst`) from Cloudflare R2 based on the user's localized GPS bounding box. This file is generated nightly by a scalable, persistent Go (Golang) daemon (which normalizes diverse regional endpoints like MTA's fragmented GTFS-RT/SIRI and MBTA's unified GTFS-RT) and attached synchronously via `@op-engineering/op-sqlite`, allowing instantaneous, offline rendering of transit performance metrics in under 12ms.