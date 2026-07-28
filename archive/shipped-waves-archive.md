# Shipped Waves Archive — Fog of Wburg

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
