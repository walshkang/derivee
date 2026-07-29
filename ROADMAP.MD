# Fog of Wburg — Unified Roadmap

This document is the single source of truth for all planned development waves. 

> [!IMPORTANT]
> **Agent Roadmap Maintenance Protocol**:
> 1. When completing a task, update its status in the **Master Status Table** from `Planned` to `✅ Done`.
> 2. Move the completed task's detailed prompt out of this file and append it to `archive/shipped-waves-archive.md`.
> 3. Keep this file lean to minimize context bloat.

## Master Status Table

| Wave | Task ID | Title | Size | Status |
|:---:|:---:|:---|:---:|:---:|
| **1** | **W1-INIT** | **Expo Scaffold & Zustand State** | **S** | ✅ Done |
| **1** | **W1-NAV** | **Navigation Shell & Splash Screen** | **M** | ✅ Done |
| **2** | **W2-DB** | **op-sqlite JSI Initialization & WAL Mode** | **M** | ✅ Done |
| **2** | **W2-H3** | **h3-js Core Logic & Grid Conversions** | **S** | ✅ Done |
| **3** | **W3-MAP** | **MapLibre Engine & 3D Terrain Base** | **L** | ✅ Done |
| **3** | **W3-FOG** | **50km Bounding Box & Inverted Polygon** | **L** | ✅ Done |
| **4** | **W4-TRACK** | **expo-location Background Service & Batching** | **M** | ✅ Done |
| **4** | **W4-DRIFT** | **Implied Speed Filter & Geometry Unioning** | **M** | ✅ Done |
| **5** | **W5-POI** | **Gamification & POI Integration** | **M** | ✅ Done |
| **6** | **W6-POLISH** | **Performance & App Store Launch** | **S** | ✅ Done |
| **7** | **W7-AMBIENT** | **Vicinity Bubble & Ghost POI Logic** | **M** | ✅ Done |
| **8** | **W8-TRANSIT** | **Live GTFS-RT Decoding & Transit Bottom-Sheet** | **L** | ✅ Done |
| **8.1** | **W8.1-TRANSIT-REFACTOR** | **Dual-Format Transit Parser (JSON + PB) & API Keys** | **M** | ✅ Done |
| **9** | **W9-OBSERVER** | **Headless Observer Tool & CDN Handoff** | **M** | ✅ Done |
| **10** | **W10-HISTORIAN** | **GPX/HealthKit Import & Macro-Reveal Animation** | **L** | ✅ Done |
| **11** | **W11-TIMETABLE** | **Standalone Transit App (Web/Spinoff) & Headway Matrix** | **L** | ✅ Done |
| **11.5** | **W11.5-MVP-POLISH** | **Light Mode UI Refactor & MVP Launch** | **S** | ✅ Done |
| **12** | **W12-BOSTON** | **Multi-City Expansion: MBTA (Post-MVP)** | **L** | Planned |
| **13** | **W13-FOG-TIERS** | **3-Tier Fog State & Reference Counting (Post-MVP)** | **M** | ✅ Done |
| **13** | **W13-FOG-STYLE** | **MapLibre Dual-Layer & Temporal Interpolation (Post-MVP)** | **S** | ✅ Done |
| **13** | **W13-AMBIENT-TRACKING** | **Ambient Tracking & Start Button Removal** | **S** | ✅ Done |
| **14** | **W14-DATA-NEIGHBORHOODS** | **Neighborhood Denominators & Water Subtraction** | **M** | ✅ Done |
| **14** | **W14-UI-STATS** | **Progression Stats UI: Contextual Pill & Archive Screen** | **M** | ✅ Done |
| **14.5** | **W14.5-BACKGROUND** | **Local Expo Module for iOS Background Assertions** | **S** | ✅ Done |
| **14.5** | **W14.5-DB-MIGRATE** | **SQLite geojson_cache & Splash Screen Gate** | **M** | ✅ Done |
| **14.5** | **W14.5-STORE** | **AppState Delta-Buffer & Zustand Refactor** | **M** | ✅ Done |
| **14.5** | **W14.5-RENDER** | **MapLibre Native Array Concatenation (Remove Turf)** | **M** | ✅ Done |
| **14.6** | **W14.6-BATTERY-HOTFIX** | **Bridge & Polling Optimization Patch** | **M** | ✅ Done |
| **14.7** | **W14.7-LOCATION-AUDIT** | **Stop the Bleeding: expo-location Audit** | **S** | Planned |
| **14.8** | **W14.8-SET-GATE** | **Unblock the Thread: In-Memory Set Gate** | **M** | Planned |
| **14.9** | **W14.9-DDS-FOG** | **DDS Refactor: MapLibre Data-Driven Styling** | **L** | Planned |
| **14.10** | **W14.10-STATS-UI** | **Fix UI Bottlenecks: FlashList & Bottom Sheet** | **M** | Planned |
| **15** | **W15-DYNAMIC-ISLAND** | **Dynamic Island Support for Stat Bar** | **S** | Planned |

---

## Wave 1 — Foundation & UI Shell (✅ Completed)
*Tasks W1-INIT & W1-NAV shipped. Prompts archived in `archive/shipped-waves-archive.md`.*

---

## Wave 2 — Core DB & Spatial Engine (✅ Completed)
*Tasks W2-DB & W2-H3 shipped. Prompts archived in `archive/shipped-waves-archive.md`.*

---

## Wave 3 — The Fog Rendering Engine (✅ Completed)
*Tasks W3-MAP & W3-FOG shipped. Prompts archived in `archive/shipped-waves-archive.md`.*

---

## Wave 4 — Background Location & Anti-Drift (✅ Completed)
*Tasks W4-TRACK & W4-DRIFT shipped. Prompts archived in `archive/shipped-waves-archive.md`.*

---

## Wave 5 — Gamification (✅ Completed)
*Task W5-POI shipped. Prompt archived in `archive/shipped-waves-archive.md`.*

---

## Wave 6 — Polish & Launch (✅ Completed)
*Task W6-POLISH shipped. Prompt archived in `archive/shipped-waves-archive.md`.*

---

## Wave 7 — The Ambient UI (✅ Completed)
*Task W7-AMBIENT shipped. Prompt archived in `archive/shipped-waves-archive.md`.*

---

## Wave 8 — Raw Transit Pipeline (✅ Completed)
*Task W8-TRANSIT shipped. Prompt archived in `archive/shipped-waves-archive.md`.*

---

## Wave 8.1 — Transit Parser Refactor (✅ Completed)
*Task W8.1-TRANSIT-REFACTOR shipped. Prompt archived in `archive/shipped-waves-archive.md`.*

---

## Wave 9 — The Observer Backend (✅ Completed)
*Task W9-OBSERVER shipped. Prompt archived in `archive/shipped-waves-archive.md`.*

---

## Wave 10 — The Historian Flow (✅ Completed)
*Task W10-HISTORIAN shipped. Prompt archived in `archive/shipped-waves-archive.md`.*

---

## Wave 11 — Standalone Transit Navigation Expansion (✅ Completed)
*Task W11-TIMETABLE shipped. Prompt archived in `archive/shipped-waves-archive.md`.*

---

## Wave 11.5 — MVP Launch & UI Polish (✅ Completed)
*Task W11.5-MVP-POLISH shipped. UI converted to Light Mode default.*

---

## Wave 12 — Multi-City Expansion: Boston (W12-BOSTON) [Post-MVP]

* **The Goal:** Prove the scalability of the architecture by expanding transit coverage to the MBTA system.
* **Agent Directives:**
  * **W12-OBSERVER:** Refactor the Go daemon to support regional configuration profiles. It will poll the unified MBTA Protobuf endpoints (`TripUpdates.pb`, `Alerts.pb`, `VehiclePositions.pb`) alongside the NYC feeds, and normalize them into the Zstandard SQLite format.
  * **W12-APP:** Implement automatic region detection in the Expo app based on the user's GPS bounding box (querying the Boston SQLite file if the user's H3 index falls within Massachusetts).
  * **W12-UI:** Expand the Transit bottom-sheet to visually support MBTA-specific experimental fields, such as "Crowding / Occupancy" indicators and "Prediction Uncertainty" warnings.

---

## Wave 13 — Advanced MapLibre Rendering & Fog Enhancements (✅ Completed)
*Tasks W13-FOG-TIERS & W13-FOG-STYLE shipped. Prompts archived in `archive/shipped-waves-archive.md`.*

---

## Wave 14 — Progression Stats & Neighborhood Denominators (In Progress / Active Focus)
*Tasks W14-DATA-NEIGHBORHOODS & W14-UI-STATS implemented; currently debugging native Stats page interactions.*
* **W14-DATA-NEIGHBORHOODS**: Integrated static `neighborhood.sqlite` DB generated via GIS water-subtraction scripts (`scripts/generate_neighborhood_db.py`).
* **W14-UI-STATS**: Shipped floating high-contrast light-mode `ContextualStatPill` (`src/components/ContextualStatPill.tsx`) and full Statistics & History Screen (`app/stats.tsx`).
* ⚠️ **Active Focus**: Investigating OP-SQLite database connection state and touch interaction flow on `app/stats.tsx`.

---

## Wave 14.5 — The Delta-Buffer Architecture (Active Focus)
*A massive architectural refactor to guarantee buttery smooth 60fps rendering for power users exceeding 10,000 unlocked hexes, utilizing native MapLibre topologies and deferred background calculations.*

* **W14.5-BACKGROUND** (✅ Completed): Local Swift bindings for `beginBackgroundTask` / `endBackgroundTask` iOS Watchdog assertion.
* **W14.5-DB-MIGRATE** (✅ Completed): Introduce the `geojson_cache` table to `@op-engineering/op-sqlite` and Splash Screen Migration Gate in `app/_layout.tsx`.
* **W14.5-STORE** (✅ Completed): Refactor `useExplorationStore` to manage `historicalHexes` vs `activeBufferHexes`. Hook into the React Native `AppState` to execute `commitActiveBuffer()` when the user locks their phone, leveraging the W14.5-BACKGROUND task assertion.
* **W14.5-RENDER** (✅ Completed): Completely strip `@turf/mask` from `fogGeoJSON.ts`. Configure the GeoJSON generator to natively concatenate the exterior bounding box and all interior hex holes into a single massive array that MapLibre earcut can consume efficiently.

---

## Wave 14.6 — Battery & Bridge Optimization Hotfix (✅ Completed)
*Task W14.6-BATTERY-HOTFIX shipped. Prompt archived in `archive/shipped-waves-archive.md`.*

---

## Wave 14.7 — Stop the Bleeding (Location Audit) [Planned]

* **Goal**: Eliminate redundant OS wakeups caused by time-based GPS polling.
* **Agent Directives**:
  * Inspect the `expo-location` background task initialization (e.g., `startLocationUpdatesAsync`).
  * Ensure the configuration object strictly uses `distanceInterval: 10` (meters) and `deferredUpdatesDistance: 50` (meters).
  * Confirm that `timeInterval` is completely removed or commented out.
  * Verify that `pausesLocationUpdatesAutomatically` is set to `true` and `activityType` is set to `Location.ActivityType.Fitness`.

---

## Wave 14.8 — Unblock the Main Thread (In-Memory Set Gate) [Planned]

* **Goal**: Implement an $O(1)$ JS-side gatekeeper to prevent redundant SQLite queries and MapLibre bridge transfers when the user is stationary or in already-explored territory.
* **Agent Directives**:
  * On app initialization, query `@op-engineering/op-sqlite` to fetch all historically unlocked H3 string IDs. Load these into a standard JavaScript `Set` (e.g., `const unlockedHexes = new Set(dbResults)`).
  * In the background location callback, after converting the raw GPS coordinate to an H3 index, immediately check `unlockedHexes.has(currentH3Index)`.
  * If the Set returns `true`, **drop execution entirely**. Do not call Zustand, do not query SQLite, and do not update MapLibre.
  * If the Set returns `false`, add the new index to the Set, fire the SQLite `INSERT`, and update the Zustand state array to trigger a single bridge transfer to MapLibre.

---

## Wave 14.9 — The Fog Engine DDS Refactor [Planned]

* **Goal**: Deprecate JS-thread hole-punching (`h3.cellsToMultiPolygon`) and offload fog rendering to the native GPU using MapLibre Data-Driven Styling.
* **Agent Directives**:
  * Strip out `@turf/mask` and `cellsToMultiPolygon` from the fog geometry generation utilities.
  * Update the MapLibre component to render a static geometry base (e.g., a static grid of H3 hex polygons covering the 50km bounding box).
  * Configure the fog layer's `fill-opacity` using a MapLibre `['match']` expression. Pass the Zustand array of unlocked H3 IDs to set their opacity to `0.0`, rendering them transparent and revealing the map below.
  * Ensure `withSynchronousUpdate(true)` is applied to the data source to bypass bridge serialization bottlenecks.

---

## Wave 14.10 — Stats Screen UI Bottlenecks [Planned]

* **Goal**: Resolve unresponsive touches and callback leaks in `app/stats.tsx` caused by rendering heavy lists inside a gesture-based bottom sheet.
* **Agent Directives**:
  * Refactor the Neighborhood Stats list to use `@shopify/flash-list` instead of standard `ScrollView` or `FlatList`.
  * Because this list lives inside a Gorhom Bottom Sheet, wrap the `FlashList` in a `<BottomSheetScrollView>` or ensure gesture handler imports are strictly from `react-native-gesture-handler`.
  * Wrap individual row items in `React.memo` to prevent redundant re-renders.
  * Utilize `InteractionManager.runAfterInteractions` to defer the mounting of the heavy list data until the bottom-sheet opening animation has fully completed.

---

## Wave 15 — System Integrations [Planned]

* **W15-DYNAMIC-ISLAND**: Add Dynamic Island / Live Activities support for the contextual stat bar so progression is visible outside the app.