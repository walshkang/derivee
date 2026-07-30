# Shipped Waves Archive — Dérivée

This archive contains detailed task prompts for completed development waves.

---

## Wave 1 — Foundation & UI Shell

### Task Prompt: W1-INIT — Expo Scaffold & Zustand State
**Goal**: Initialize the raw Expo environment and set up the global state manager.
1. Initialize a new Expo SDK 51+ project (Managed Workflow) using TypeScript.
2. Install `zustand` and create a global store (`store/useExplorationStore.ts`).
3. The store should track: `isExploring` (boolean), `currentLocation` (lat/lng | null), and `unlockedHexes` (array of strings).
4. Configure absolute imports in `tsconfig.json` (e.g., `@/*` maps to `./src/*`).

### Task Prompt: W1-NAV — Navigation Shell & Splash Screen
**Goal**: Build the routing architecture and "The Awakening" splash screen.
1. Install Expo Router.
2. Create the Splash Screen (`app/index.tsx`) with a dark, atmospheric background (simulating the fog) and a central logo.
3. Build the main layout shell that transitions from the Splash Screen to `app/(tabs)/map.tsx` (The Cartographer's Desk) and `app/(tabs)/archive.tsx` (The Archive).
4. Do not build the actual map yet; just place a placeholder `<View>` where MapLibre will eventually go.

---

## Wave 2 — Core DB & Spatial Engine

### Task Prompt: W2-DB — op-sqlite JSI Initialization & WAL Mode
**Goal**: Configure the high-speed local persistence layer.
1. Configure `@op-engineering/op-sqlite`.
2. Create the `explored_hexes` schema using `WITHOUT ROWID` and `h3_index` as the string primary key.
3. Enable `PRAGMA journal_mode = WAL;` and `PRAGMA synchronous = NORMAL;`.
4. Create helper functions for inserting hexes (`INSERT OR IGNORE`) and querying all unlocked hexes.

### Task Prompt: W2-H3 — h3-js Core Logic & Grid Conversions
**Goal**: Implement the spatial logic for calculating unlocked areas.
1. Create a spatial utility file `utils/h3Utils.ts`.
2. Implement a function to convert a GPS coordinate (lat/lng) to a Resolution 11 H3 index string.
3. Implement a function to calculate a buffer (e.g., k-ring radius) around a given hex to simulate the discovery radius.
4. Integrate with `op-sqlite` to write these newly discovered hexes to the local database.

---

## Wave 3 — The Fog Rendering Engine

### Task Prompt: W3-MAP — MapLibre Engine & 3D Terrain Base
**Goal**: Render the underlying world that users will uncover.
1. Initialize `@maplibre/maplibre-react-native` inside `app/(tabs)/map.tsx`.
2. Configure a Raster DEM Source and 3D terrain extrusion for the base layer.
3. Add high-resolution satellite imagery as the primary visual reward beneath the fog.
4. Ensure the camera follows the user's location with a tilted 3D perspective.

### Task Prompt: W3-FOG — 50km Bounding Box & Inverted Polygon
**Goal**: Implement the inverted polygon stack and punch holes in the fog.
1. Generate a lightweight 50km x 50km GeoJSON bounding box (Layer 2 - The Fog) centered on the user.
2. Add a `ShapeSource` for the fog layer with `withSynchronousUpdate(true)` enabled.
3. Periodically query unlocked hexes from `op-sqlite`, run `h3.cellsToMultiPolygon` in a background worker, and pass the resulting merged geometry as "inner rings" (holes) to the fog layer.
4. Render vector boundaries (Layer 4 - context labels) on top of the fog.

---

## Wave 4 — Background Location & Anti-Drift

### Task Prompt: W4-TRACK — expo-location Background Service & Batching
**Goal**: Set up battery-conscious background tracking.
1. Request Foreground and Background location permissions via `expo-location`.
2. Register a headless background task using `expo-task-manager`.
3. Configure `startLocationUpdatesAsync` with `distanceInterval: 10`, `deferredUpdatesDistance: 50`, and `Location.ActivityType.Fitness`.
4. Connect incoming background coordinates to the H3 buffer calculation and SQLite insertion pipeline.

### Task Prompt: W4-DRIFT — Implied Speed Filter & Geometry Unioning
**Goal**: Prevent GPS drift from artificially unlocking areas and maintain 60fps.
1. Implement the velocity gate inside the background task: discard any coordinate jump yielding an implied speed $> 12 \text{ m/s}$.
2. Optimize the geometry unioning loop: only trigger `h3.cellsToMultiPolygon` when new hexes are actually inserted, rather than on a dumb timer.
3. Verify that the UI main thread does not freeze when the background task fires.

### Task Prompt: W5-POI — Gamification & POI Integration
**Goal**: Lure users to unexplored areas using beacons.
1. Seed the database with local Points of Interest (POIs).
2. Render undiscovered POIs as glowing beacons on the map, visible through the fog.
3. Implement discovery logic: when the user's buffer radius intersects a POI coordinate, trigger a discovery event.
4. Display a reward modal and convert the beacon into a permanent, unobtrusive pin.

---

## Wave 6 — Polish & Launch

### Task Prompt: W6-POLISH — Performance & App Store Launch
**Goal**: Finalize the experience for production.
1. Conduct TestFlight beta testing to monitor real-world battery drain.
2. Fine-tune 3D camera animations and UI transitions.
3. Prepare App Store screenshots and offline-first privacy disclosures.
4. Prepare for V1 release.

---

## Wave 7 — The Ambient UI

### Task Prompt: W7-AMBIENT — Vicinity Bubble & Ghost POI Logic
**Goal**: Strip away the heavy gamified HUDs and implement the progressive disclosure engine.
1. Implement the dynamic 200-meter "Vicinity Bubble" anchored to the user's live GPS ping.
2. Configure MapLibre to only render crisp street names and unbranded transit nodes inside this active radius.
3. Implement the "Ghost POI" lifecycle. Ensure that once an area is cleared, POI pins become invisible on the map.
4. Build the Geospatial Point-in-Polygon (PiP) check so that when a user taps the screen, the app queries `@op-engineering/op-sqlite` to see if they are physically standing on a hidden POI before revealing the bottom-sheet.


---

## Wave 8 — Raw Transit Pipeline

### Task Prompt: W8-TRANSIT — Live GTFS-RT Decoding & Transit Bottom-Sheet
**Goal**: Build the on-device commuter tool without relying on third-party aggregators.
1. Install `protobufjs` and `gtfs-realtime-bindings` to decode the transit authority's binary feeds natively on the JS thread.
2. Build the cleanly formatted, Naver Maps-style bottom sheet displaying live countdowns (e.g., "3 min") and dynamic vector route previews tracing the vehicle's path.

---

## Wave 8.1 — Transit Parser Refactor

### Task Prompt: W8.1-TRANSIT-REFACTOR — Dual-Format Transit Parser (JSON + PB) & API Keys
**Goal**: Upgrade the Expo app's `transitService.ts` to handle fragmented data feeds, API keys, and dual-format parsing.
1. **No UI Changes:** Focus exclusively on the data-fetching layer (`src/services/transitService.ts`).
2. **Constants Mapping:** Create a constants file to map the fragmented MTA subway lines to their specific `api-endpoint.mta.info` URLs, rather than relying on a single global feed.
3. **API Authentication:** Ensure the subway `fetch` requests pass the required `x-api-key` header using keys injected from `.env` (e.g., `EXPO_PUBLIC_MTA_API_KEY`), while bus requests use the `?key=` query parameter for both the MTA SIRI API and OneBusAway REST API.
4. **Dual-Format Decoding:** Refactor the parser to dynamically handle both binary Protobufs (`protobufjs` for subways) and JSON (MTA SIRI API for real-time bus tracking, and OneBusAway REST API for static/discovery bus data).
5. **Protobuf Extensions:** Include and load both the `gtfs-realtime-NYCT.proto` and `gtfs-realtime-service-status.proto` (Mercury) extensions alongside the standard GTFS-realtime proto. This is strictly required to decode MTA-specific `1001` tags:
   * `NyctTripDescriptor` (for `direction`, `is_assigned`) and `NyctStopTimeUpdate` (for `actual_track`).
   * `MercuryAlert` (for `alert_type`, `directionality`, `affected_stations`) and `MercuryEntitySelector` (for `sort_order` / priority).
6. **Station-Level Alerts:** Update the parsing logic to correctly handle the MTA's `informed_entity` structure and the Mercury alert extensions (extracting directional impacts and sorting by severity).

---

## Wave 9 — The Observer Backend

### Task Prompt: W9-OBSERVER — Headless Observer Tool & CDN Handoff
**Goal**: Build the "make it yourself, and make it well" persistent backend architecture for historical transit reliability.
1. **Outside Expo**: This task occurs *outside* the Expo app. Build a standalone Go (Golang) persistent daemon hosted on a low-cost VPS.
2. **Polling**: The daemon must poll both the fragmented **MTA GTFS-RT Protobuf feeds** (for subways) and the **MTA Bus Time SIRI API (JSON)** (for buses) every 3 minutes, acting as a unifier to normalize both real-time data streams.
3. **Alerts & Directions**: When parsing Service Alerts, strictly adhere to the MTA's `informed_entity` format: iterating through separate station-level entities and applying `direction_id` filters.
4. **Historical Processing**: Calculate rolling 7-day averages and reliability percentages to assemble the historical sparkline data in memory.
5. **Ghost Trains**: Implement a strict Time-To-Live (TTL) garbage collector on the active_trips table. If a trip_id goes stale for > 10 minutes without registering an arrival, silently drop it.
6. **CDN Handoff**: Output a single, unified Zstandard-compressed SQLite delta database (`transit_delta.sqlite.zst`) and push it to Cloudflare R2 (CDN).
7. **Client Handoff**: Update the Expo app to silently fetch and synchronously attach this SQLite delta file every morning via `@op-engineering/op-sqlite`.

---

## Wave 10 — The Historian Flow

### Task Prompt: W10-HISTORIAN — GPX/HealthKit Import & Macro-Reveal Animation
**Goal**: Solve the "cold start" problem for new users.
1. Build the UI in the Settings/Archive screen to accept passive uploads from Apple HealthKit, Strava, or raw GPX/FIT files.
2. Build the massive visual payoff: an animation that instantly vanishes huge swaths of the fog across the city once the historical data is processed into H3 hexes.

---

## Wave 11 — Standalone Transit Navigation Expansion

### Task Prompt: W11-TIMETABLE — Standalone Transit App (Web/Spinoff) & Headway Matrix
**Goal**: Leverage the historical data and live GTFS pipeline to build a lightweight, dedicated transit tracking and navigation app (potentially web-based).
1. Build a spinoff/standalone interface (web browser or lightweight companion app) dedicated purely to transit routing, reliability, and tracking.
2. Utilize the Go Observer's historical sparkline data to provide predictive "historical reliability" scores for routes.
3. Implement a Headway Matrix / Historical Timetable view, where each hour is a row and minutes are columns (e.g., `12 | 03 12 30 45 59`), color-coded to denote early vs. late arrivals for any transit mode.
4. Support live navigation and future planned routes based on the fusion of live GTFS/SIRI data and historical patterns.
5. Ensure the frontend parser handles binary Protobufs for both subways and buses, and correctly displays direction-specific service alerts (using MTA's `direction_id` structure).

---

## Wave 13 — Advanced MapLibre Rendering & Fog Enhancements (W13-FOG)

### Task Prompt: W13-FOG — 3-Tier Fog State & MapLibre Dual-Layer
**Goal:** Implement the optimized 3-Tier Fog of War system using native MapLibre capabilities and Positional Delta processing.
1. Update the SQLite database schema to support active sight reference counting (`active_visibility` table).
2. Adapt the state machine to track Unexplored, Explored, and Visible tiers natively, implementing positional delta processing to minimize geometry worker calls.
3. Restructure the MapLibre layers to utilize the dual-raster desaturation technique (Layer 1: Explored Base desaturated, Layer 2: Visible Base color). Add `fill-opacity-transition: { duration: 300 }` to the fog layer for organic temporal dissolve.
4. Re-enable 3D buildings and configure the fog as a 3D volumetric extrusion block to correctly obscure buildings within the unexplored zones.

---

## Wave 14 — Progression Stats & Neighborhood Denominators (W14)

### Task Prompt: W14-DATA-NEIGHBORHOODS & W14-UI-STATS
**Goal:** Bridge the gap between ambient discovery and gamified progression by adding lightweight stats (neighborhood completion percentage).
* **Agent Directives:**
  * **Wave 14-DATA (Data Layer):** Update the SQLite schema to include a `neighborhood_stats` table. Write a script to populate it with total hex counts per neighborhood. **Crucially**, use Turf.js or Shapely (Python) to perform a Boolean Subtraction of water multipolygons from the neighborhood bounds *before* running the H3 polyfill algorithm, ensuring open water is excluded but bridges are preserved in the total denominator.
  * **Wave 14-UI (UI Layer):** Build the floating Contextual Stat Pill on the Main Map (progressive disclosure) and the comprehensive Archive list screen, hooking them up to the new SQLite queries and Zustand session state. Do not mix UI work with Data work in a single session.

---

## Wave 14.5 — The Delta-Buffer Architecture

### Task Prompt: W14.5-DB-MIGRATE — SQLite Cache Table & Splash Screen Gate
**Goal:** Introduce the `geojson_cache` table to `@op-engineering/op-sqlite` and implement the Splash Screen Migration Gate in `app/_layout.tsx` to handle legacy user data backfilling behind the splash screen.
1. Add `geojson_cache` schema with `WITHOUT ROWID` and string primary key `key` to `src/db/database.ts`.
2. Implement schema migrations (`runMigrations`) checking `PRAGMA user_version` and setting `PRAGMA user_version = 1`.
3. Build cache CRUD helpers (`getGeoJSONCache`, `setGeoJSONCache`, `clearGeoJSONCache`) and legacy backfill helper `backfillLegacyGeoJSONCache()`.
4. Update `app/_layout.tsx` with `SplashScreen.preventAutoHideAsync()` and `SplashScreen.hideAsync()` in a fail-safe `finally` block.

### Task Prompt: W14.5-RENDER — MapLibre Native Array Concatenation
**Goal:** Completely strip `@turf/mask` from `fogGeoJSON.ts` and configure the GeoJSON generator to natively concatenate the 50x50km bounding box ring and all interior hex holes into a single array for native MapLibre earcut triangulation.
1. Remove `@turf/mask` and `@turf/bbox-polygon` from `src/utils/fogGeoJSON.ts` and `package.json`.
2. Construct the 50x50km bounding box linear ring (`bboxRing`) directly.
3. Extract and flatten all linear rings returned by `h3.cellsToMultiPolygon(unlockedHexes, true)` into an `innerRings` array.
4. Return a single GeoJSON `Feature<Polygon>` with `coordinates: [bboxRing, ...innerRings]` so MapLibre's native C++ earcut triangulator handles GPU hole clipping natively.
5. Create unit tests in `src/utils/__tests__/fogGeoJSON.test.ts` verifying polygon structure and H3 string type enforcement.

### Task Prompt: W14.6-BATTERY-HOTFIX — Battery & Bridge Optimization Hotfix
**Goal:** A targeted optimization pass to fix critical battery drain and bridge congestion regressions introduced during ambient tracking configuration.
1. **Objective 1 (Foreground Polling):** In `src/services/locationService.ts`, locate the `watchPositionAsync` foreground fallback and completely remove `timeInterval: 3000`. Time-based polling is strictly forbidden.
2. **Objective 2 (Background Sync):** In `src/services/locationTask.ts`, ensure that `handleBackgroundLocationUpdate` actually updates `useExplorationStore.getState().setCurrentLocation(...)` using the most recent valid coordinate before it attempts to trigger `store.updateFogGeoJSON()`.
3. **Objective 3 (Bridge Congestion):** Rip out the custom JS-driven `AnimatedUserLocation` component. Its use of Reanimated `withTiming` to pump `FeatureCollection` JSON over the React Native bridge at 60fps violates the core architecture rules. Replace it in `app/map.tsx` with MapLibre's native `<MapLibreGL.UserLocation visible={true} />` component to achieve zero-bridge-traffic rendering.

---

## Wave 14.7 — Stop the Bleeding (Location Audit)

### Task Prompt: W14.7-LOCATION-AUDIT — Location Audit
**Goal**: Eliminate redundant OS wakeups caused by time-based GPS polling.
1. Inspect the `expo-location` background task initialization (`startLocationUpdatesAsync`) in `src/services/locationService.ts`.
2. Ensure the configuration object strictly uses `distanceInterval: 10` (meters) and `deferredUpdatesDistance: 50` (meters).
3. Confirm that `timeInterval` is completely removed / omitted from background options and foreground watchers.
4. Verify that `pausesUpdatesAutomatically` (or `pausesLocationUpdatesAutomatically`) is set to `true` and `activityType` is set to `Location.ActivityType.Fitness`.
5. Add unit tests in `src/services/__tests__/locationService.test.ts` asserting parameters and the omission of `timeInterval`.

---

## Wave 14.8 — Unblock the Main Thread (In-Memory Set Gate)

### Task Prompt: W14.8-SET-GATE — In-Memory Set Gatekeeper
**Goal**: Implement an $O(1)$ JS-side gatekeeper outside Zustand to prevent redundant SQLite queries and MapLibre bridge transfers when the user is stationary or in already-explored territory.
1. Build a module-scoped Set gatekeeper (`const unlockedHexesSet = new Set<string>();`) outside of Zustand state to intercept location updates without React state/re-render overhead.
2. Implement a race-condition lock (`let isGatekeeperLoaded = false;`) so background GPS ticks are dropped or auto-hydrated until the Set is populated via SQLite on boot.
3. In `processAndStoreLocationHexes`, perform an $O(1)$ membership check (`bufferHexes.every(hex => unlockedHexesSet.has(hex))`). If `true`, drop execution early (`newHexCount: 0`).
4. If `false`, add new hexes to the Set, persist to SQLite, and dispatch Zustand updates for MapLibre Data-Driven Styling (`['match']` expression).

## Wave 14.9 — The Fog Engine DDS Refactor [Planned]

* **Goal**: Deprecate JS-thread hole-punching (`h3.cellsToMultiPolygon`) and offload fog rendering to the native GPU using MapLibre Data-Driven Styling.
* **Agent Directives**:
  * Strip out `@turf/mask` and `cellsToMultiPolygon` from the fog geometry generation utilities.
  * Update the MapLibre component to render a static geometry base (e.g., a static grid of H3 hex polygons covering the 50km bounding box).
  * Configure the fog layer's `fill-opacity` using a MapLibre `['match']` expression. Pass the Zustand array of unlocked H3 IDs to set their opacity to `0.0`, rendering them transparent and revealing the map below.
  * Ensure `withSynchronousUpdate(true)` is applied to the data source to bypass bridge serialization bottlenecks.

## Wave 14.10 — Stats Screen UI Bottlenecks

* **Goal**: Resolve unresponsive touches and callback leaks in `app/stats.tsx` caused by rendering heavy lists inside a gesture-based bottom sheet.
* **Agent Directives**:
  * Refactor the Neighborhood Stats list to use `@shopify/flash-list` instead of standard `ScrollView` or `FlatList`.
  * Because this list lives inside a Gorhom Bottom Sheet, wrap the `FlashList` in a `<BottomSheetScrollView>` or ensure gesture handler imports are strictly from `react-native-gesture-handler`.
  * Wrap individual row items in `React.memo` to prevent redundant re-renders.
  * Utilize `InteractionManager.runAfterInteractions` to defer the mounting of the heavy list data until the bottom-sheet opening animation has fully completed.

---

# 🔄 Superseded Waves — Pre-Sleepy Hermes Architecture

> [!IMPORTANT]
> The waves below were completed under the original **Expo Managed / JS-background** architecture. They have been **architecturally superseded** by the **Sleepy Hermes Transition (Wave A–D)**, which moves all background location processing to a pure native Swift layer. These entries are preserved for historical context only.

---

## Wave 4 — Background Location & Anti-Drift (🔄 Superseded by Wave C)

### Task Prompt: W4-TRACK — expo-location Background Service & Batching
**Goal**: Configure `expo-location` and `expo-task-manager` to handle background GPS coordinate batching using the Expo Managed Workflow.
* **Status**: Originally ✅ Done. Now **superseded** — background tracking is handled by native Swift `CLLocationManager`, not `expo-task-manager`.
* **Reason for supersession**: `expo-task-manager` executes JavaScript in the background, triggering Hermes garbage collection sweeps and bridge serialization. iOS watchdog processes terminate apps that consume excessive background CPU cycles, yielding `0x8badf00d` (watchdog timeout) and `0xdead10cc` (resource deadlock) exception codes.

### Task Prompt: W4-DRIFT — Implied Speed Filter & Geometry Unioning
**Goal**: Implement the Drift Gate (Implied Speed Filter) in JavaScript.
* **Status**: Originally ✅ Done. The **math is preserved** but now executes in the native Swift layer (Wave C), not in a JS background task.

---

## Wave 14.5-BACKGROUND — Local Expo Module for iOS Background Assertions (🔄 Superseded by Wave C)

### Task Prompt: W14.5-BACKGROUND — beginBackgroundTask / endBackgroundTask
**Goal**: Create a local Expo Module providing Swift bindings for `UIApplication.shared.beginBackgroundTask` and `endBackgroundTask` to prevent iOS watchdog termination during background DB commits.
* **Status**: Originally ✅ Done. Now **superseded** — background task assertions are integrated directly into the native Swift `HybridTracker` service (Wave C), eliminating the need for a separate Expo Module wrapper.

---

## Wave 14.5 — The Delta-Buffer Architecture (🔄 Superseded by Wave D)

### Task Prompt: W14.5-STORE — AppState Delta-Buffer & Zustand Refactor
**Goal**: Refactor `useExplorationStore` to manage `historicalHexes` vs `activeBufferHexes` using React Native `AppState` to commit the active buffer when the user locks their phone.
* **Status**: Originally ✅ Done. Now **superseded** — the AppState hydration pattern is redesigned under Sleepy Hermes (Wave D) to pull delta reads from the shared SQLite database populated by the Swift background service, rather than committing a JS-side active buffer.

---

## Wave 14.6 — Battery & Bridge Optimization Hotfix (🔄 Superseded by Wave A/D)

### Task Prompt: W14.6-BATTERY-HOTFIX
**Goal**: Patch bridge congestion and polling overhead caused by the JS-based background location pipeline.
* **Status**: Originally ✅ Done. Now **superseded** — the root cause (JS executing in the background) is eliminated entirely by Sleepy Hermes. Bridge congestion prevention is handled by the $O(1)$ In-Memory Set Gate (Wave D).

---

## Wave 14.7 — Stop the Bleeding: expo-location Audit (🔄 Superseded by Wave C)

### Task Prompt: W14.7-LOCATION-AUDIT
**Goal**: Audit and minimize `expo-location` background wake frequency to reduce battery drain.
* **Status**: Originally ✅ Done. Now **superseded** — `expo-location` is no longer used for background tracking. The native Swift `CLLocationManager` with hardware batching (Wave C) replaces the entire pipeline.

---

## Wave 14.8 — Unblock the Main Thread: In-Memory Set Gate (Partially superseded by Wave D)

### Task Prompt: W14.8-SET-GATE
**Goal**: Implement the $O(1)$ In-Memory `Set` Gate to prevent redundant bridge crossings.
* **Status**: Originally ✅ Done. The **concept is preserved and enhanced** in Wave D, but the trigger mechanism changes from `expo-task-manager` callbacks to Nitro JSI callbacks and AppState delta hydration.

---

## Wave 14.9 — DDS Fog Refactor (Preserved — not superseded)

### Note
**W14.9-DDS-FOG** remains valid under Sleepy Hermes. The MapLibre Data-Driven Styling approach is unchanged; only the *source* of hex data shifts from JS background processing to Swift-side database writes hydrated on foreground.

---

## Planned Waves Deferred Pending Sleepy Hermes Completion

* **W11.6-DEVOPS**: Deploy New Go Observer to Oracle Cloud — Deferred, unrelated to Sleepy Hermes.
* **W11.7-UI-MATRIX**: Build Headway Matrix (Timetable) UI — Deferred, unrelated to Sleepy Hermes.
* **W12-BOSTON**: Multi-City Expansion: MBTA — Post-MVP, deferred.
* **W15-DYNAMIC-ISLAND**: Dynamic Island Support — Deferred until Sleepy Hermes stabilizes.

---

## Wave A — Database Configuration & Dual-Thread Concurrency

### Task Prompt: WA-DB-CONCURRENCY
**Goal**: Establish the foundational shared persistence layer for the Sleepy Hermes architecture. Configure the SQLite database for **dual-thread concurrent access** — one connection from the Swift C-API (background writes) and one from `@op-engineering/op-sqlite` JSI (foreground reads) — targeting the exact same physical `.db` file.

### Implementation Specifications

#### 1. Database File Path Resolution
The Swift background service must resolve the database path identically to how `@op-engineering/op-sqlite` computes it. `op-sqlite` on iOS places the DB in the Application Support directory.
To align exactly with `@op-engineering/op-sqlite`'s default path for `fog_of_wburg.db`, Swift should resolve it via:

```swift
let fileManager = FileManager.default
guard let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
try? fileManager.createDirectory(at: appSupportURL, withIntermediateDirectories: true, attributes: nil)
let dbURL = appSupportURL.appendingPathComponent("fog_of_wburg.db")
let dbPath = dbURL.path
```

#### 2. Connection Flags (`sqlite3_open_v2`)
The Swift connection must open the database with read/write access, create it if missing, and enable full mutex for thread safety.

```swift
var db: OpaquePointer?
let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
if sqlite3_open_v2(dbPath, &db, flags, nil) != SQLITE_OK { sqlite3_close(db); db = nil }
```

#### 3. PRAGMA Sequence
Immediately upon opening the connection in Swift:
```swift
sqlite3_exec(db, "PRAGMA journal_mode = WAL;", nil, nil, nil)
sqlite3_exec(db, "PRAGMA synchronous = NORMAL;", nil, nil, nil)
```

#### 4. Prepared Statement Lifecycle
**Compilation:**
```swift
let insertQuery = "INSERT OR IGNORE INTO explored_hexes (h3_index, discovered_at) VALUES (?, ?);"
var insertStmt: OpaquePointer?
if sqlite3_prepare_v2(db, insertQuery, -1, &insertStmt, nil) != SQLITE_OK { /* Error */ }
```
**Execution:**
```swift
sqlite3_bind_text(insertStmt, 1, h3HexCString, -1, nil)
let timestamp = Int64(Date().timeIntervalSince1970 * 1000)
sqlite3_bind_int64(insertStmt, 2, timestamp)
if sqlite3_step(insertStmt) == SQLITE_DONE { /* Success */ }
sqlite3_reset(insertStmt)
sqlite3_clear_bindings(insertStmt)
```
**Teardown:**
```swift
sqlite3_finalize(insertStmt)
sqlite3_close(db)
```

## Wave B — Nitro Module Scaffolding & Code Generation [Planned]

**Task ID:** `WB-NITRO-SCAFFOLD`
**Depends on:** Wave A (database configuration documented).

### Goal
Define the TypeScript specification for the `HybridTracker` Nitro Module and execute the Nitrogen code generation pipeline. Produce step-by-step Xcode GUI linkage instructions for the human developer.

### Agent Directives

1. **Create the Nitro TypeScript specification (`src/native/TrackingService.nitro.ts`):**
   * Extend `HybridObject` with `{ ios: 'swift' }`.
   * Expose methods:
     * `startTracking(): void` — Initialize the native `CLLocationManager` and SQLite connection.
     * `stopTracking(): void` — Terminate the background service and release resources.
     * `addListener(callback: (h3Index: string) => void): void` — Register a JS callback for real-time foreground notifications when new hexes are discovered.
     * `removeListener(): void` — Unregister the callback.
     * `getDiscoveredHexesSince(timestamp: number): string[]` — Synchronous delta query for AppState hydration.

2. **Run the Nitrogen code generator:**
   * Execute `npx nitrogen` to generate the `nitrogen/generated/` directory containing C++ JSI translation layers and the `HybridTrackingSpec.swift` protocol.

3. **Produce Xcode GUI linkage instructions:**
   * Step-by-step instructions for the human developer to:
     1. Open `ios/FogOfWburg.xcworkspace`.
     2. Drag `nitrogen/generated/ios/` into the Xcode Project Navigator under the main app target.
     3. Verify target membership and "Create groups" selection.
     4. Create `HybridTracker.swift` via Xcode New File dialog.
     5. Accept the bridging header prompt and add `#import "h3api.h"` and `#import <sqlite3.h>`.
   * These instructions must be written as a standalone reference document.

### Verification
* `npx nitrogen` completes without errors.
* Generated `nitrogen/generated/ios/` directory contains `HybridTrackingSpec.swift` with the expected method signatures.
* Linkage instructions are clear enough for a developer unfamiliar with Xcode to follow.
