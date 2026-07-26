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
| **1** | **W1-NAV** | **Navigation Shell & Splash Screen** | **M** | Planned |
| **2** | **W2-DB** | **op-sqlite JSI Initialization & WAL Mode** | **M** | Planned |
| **2** | **W2-H3** | **h3-js Core Logic & Grid Conversions** | **S** | Planned |
| **3** | **W3-MAP** | **MapLibre Engine & 3D Terrain Base** | **L** | Planned |
| **3** | **W3-FOG** | **50km Bounding Box & Inverted Polygon** | **L** | Planned |
| **4** | **W4-TRACK** | **expo-location Background Service & Batching** | **M** | Planned |
| **4** | **W4-DRIFT** | **Implied Speed Filter & Geometry Unioning** | **M** | Planned |
| **5** | **W5-POI** | **Gamification & POI Integration** | **M** | Planned |
| **6** | **W6-POLISH** | **Performance & App Store Launch** | **S** | Planned |

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

---

## Wave 5 — Gamification

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