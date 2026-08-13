# Dérivée — Architecture Specification

This document details the architectural decisions and internal machinery for the pure native iOS version of Dérivée.

## 1. Core Paradigm: Pure Native Swift

Dérivée is built as a pure native iOS application using **Swift** and **SwiftUI**. We have explicitly moved away from hybrid frameworks (React Native, Expo) and C++ JSI bridging (Nitro Modules) to maximize performance, battery life, and background execution reliability.

### 1.1 Project Generation (XcodeGen)
To prevent `.pbxproj` merge conflicts and maintain a deterministic build environment, the Xcode project is generated using `xcodegen`. 
- **Configuration:** Defined entirely in `project.yml`.
- **Dependencies:** Managed via Swift Package Manager (SPM).
- **No CocoaPods:** The project is entirely free of Ruby-based dependency managers.

---

## 2. The Data Layer: GRDB & SQLite

All geospatial data, exploration history, and transit schedules are stored locally in a SQLite database.

### 2.1 Concurrency & WAL Mode
We use `GRDB.swift` to manage the database connection.
- **DatabasePool:** Enables concurrent reads and writes, crucial for rendering the map on the main thread while the background tracking engine writes new locations.
- **WAL (Write-Ahead Logging):** Configured via `PRAGMA journal_mode = WAL;`.
- **Busy Timeout:** Configured via `PRAGMA busy_timeout = 5000;` to gracefully handle concurrent access without `SQLITE_BUSY` exceptions.
- **QoS Configuration:** `Configuration.qos` is set to `.userInitiated` to prevent priority inversion. Without this, GRDB's internal `Pool` barrier and wait queues default to `.default` QoS, causing the main thread (`User-Interactive`) to hang on `Pool.get()` when background writes hold connections.

### 2.2 Schema & Region Tracking
The `explored_hexes` table tracks all discovered H3 indices.
```sql
CREATE TABLE explored_hexes (
    h3_index TEXT PRIMARY KEY
);
```
Standard SQLite ROWID tables ensure that SQLite update hooks and GRDB `ValueObservation` region tracking reliably detect every row insertion across threads.

### 2.3 Reactive Observation
The `SpatialStore` (`@Observable`) acts as the bridge between GRDB and SwiftUI. It uses GRDB's `ValueObservation` with `ExploredHex: TableRecord, FetchableRecord` to track changes in the `explored_hexes` table. When new hexes are written by the background `AmbientTrackingEngine`, `ValueObservation` fires `onChange`, which calls `recomputeFogShape()` inside a `Task.detached(priority: .userInitiated)`. The resulting `MLNPolygon` is set on `currentFogShape` on `MainActor`, which SwiftUI observes via `@Observable`, triggering `MapView.updateUIView()` to push the new shape into the MapLibre fog source.

### 2.4 Async Read Mandate
All `SpatialDatabaseManager` read methods exposed to callers **must** use `async`/`await` (`try await dbWriter.read`). Synchronous `dbWriter.read { }` calls on the main thread cause priority inversion hangs when the background `AmbientTrackingEngine` holds a pool connection. The only acceptable synchronous reads are internal to GRDB's `ValueObservation` callbacks, which manage their own threading.

---

## 3. The Ambient Tracking Engine

Background location tracking is handled by the `AmbientTrackingEngine`, designed to be infinitely persistent while minimizing battery drain.

### 3.1 Modern iOS 17 Concurrency
We abandoned legacy `CLLocationManagerDelegate` callbacks in favor of the modern `CLLocationUpdate.liveUpdates()` asynchronous stream.
- The stream runs in a detached `Task` off the main thread.
- Updates are processed serially via `for await update in updates`.

### 3.2 The Watchdog Shield
To prevent iOS from terminating the app when running in the background for extended periods, we instantiate a `CLBackgroundActivitySession`. This tells the OS that the location session is critical and must be preserved.

### 3.3 The Drift Gate (Speed Filter)
To prevent "GPS drift" or multipath errors in urban canyons from unlocking false hexes, an implied speed filter is enforced:
- Speed is calculated as $\Delta d / \Delta t$ using `update.location`.
- If speed exceeds **12 m/s** (approx. 27 mph), the point is discarded.
- This ensures hexes are only unlocked at walking/biking speeds.

### 3.4 Pipeline Diagnostic Logging & Untethered Field Testing
To diagnose real-world GPS and fog update lifecycle events on physical devices disconnected from Xcode:
- `PipelineLogger` multiplexes all 6 stages of pipeline telemetry (`[S1]` through `[S6]`) across stdout, Apple Unified Logging (`os.Logger`), and a persistent sandbox file (`Documents/pipeline_debug.log`).
- `UIFileSharingEnabled` and `LSSupportsOpeningDocumentsInPlace` are enabled in `project.yml` so users can inspect or AirDrop `pipeline_debug.log` straight from the iOS Files app after field walks.

---

## 4. Geospatial Hashing (H3)

Dérivée uses Uber's H3 Hexagonal Hierarchical Spatial Index to discretize the world.

### 4.1 Swift-H3 Wrapper
Instead of compiling the raw C library inside the Xcode project using CMake, we use the `swift-h3` SPM community wrapper. This provides a clean, type-safe Swift API for spatial functions.

### 4.2 Resolution Constraints
All hexes are calculated at **Resolution 11**.
- Coordinates are passed to `H3.latLngToCell(latitude:longitude:resolution:)`.
- The resulting 64-bit integer is converted to a 15-character hex string for SQLite insertion.

---

## 5. Map Rendering

### 5.1 MapLibre Native
The visual map is rendered using MapLibre Native.
- Custom vector styles are injected using Data-Driven Styling (DDS).
- The volumetric fog is rendered as a dark overlay. The `fog-source` (`MLNShapeSource`) holds a single `MLNPolygon` whose exterior ring is a 50km bounding box and whose interior rings are hex-shaped holes. `SpatialStore.currentFogShape` is passed through `ContentView` → `MapView.fogShape` → `Coordinator.updateExploredHexes()`, which sets `fogSource.shape = validShape` to update the map.
- The full reactive chain is: `insertDiscoveredHex()` → GRDB `ValueObservation` fires → `recomputeFogShape()` at `.userInitiated` priority → `currentFogShape` set on `MainActor` → SwiftUI detects `@Observable` change → `updateUIView()` → MapLibre source update. This renders new hex holes in real-time without app restart.

### 5.2 Fog Computation Priority
All `recomputeFogShape()` invocations run inside `Task.detached(priority: .userInitiated)`. This applies to both the initial cold-start computation and all subsequent live updates triggered by `ValueObservation`.
- **Why not `.background`:** iOS aggressively deprioritizes `.background` QoS tasks while the app is in the foreground. A `.background` priority fog recomputation gets queued but may not execute for seconds or minutes, causing the `MainActor.run` block (which sets `currentFogShape`) to never fire. This manifests as hexes appearing uncovered only after app restart. This was the root cause of the live-update starvation bug fixed in the `.background` → `.userInitiated` priority change.
- **Why `.userInitiated` and not synchronous:** The polygon math (building `MLNPolygon` interior rings from H3 boundaries) completes in <1ms for typical hex counts, but running it off the main thread avoids any risk of jank at high hex counts (1000+).

### 5.3 Fog Startup Synchronization
On cold start, three systems race: `SpatialStore` fog computation, MapLibre style loading, and the first GPS fix. The architecture enforces:
- **Map Ready Handshake:** A `isMapStyleLoaded` flag in the `MapView.Coordinator` ensures the computed fog shape is applied as soon as both the style and the shape are ready. If the shape is ready first, it's applied when the style loads. If the style loads first, it's applied when the shape arrives via the next `updateUIView` cycle.
- **Bounding Box Jitter:** The initial fog source uses slightly offset coordinates from the `recomputeFogShape()` output to prevent MapLibre's shape cache from ignoring the first computed update.

### 5.3 Polygon Winding Order Convention
The fog polygon follows the MapLibre Native (iOS) convention:
- **Exterior ring (50km bounding box):** Clockwise winding.
- **Interior rings (hex holes):** Winding order is verified empirically per MapLibre version (see Wave I.2 audit). H3's `cellToBoundary` returns counterclockwise coordinates; these are reversed if required by the current MapLibre build.
- A permanent comment in `SpatialStore.recomputeFogShape()` documents the verified convention.

---

## 6. Testing Architecture

Testing in Dérivée follows a staggered, specialized approach to ensure stability across both background execution and UI rendering.

### 6.1 Unit Testing (Phases 1 & 2)
The core engine and raw data components must be tested independently from the UI and background lifecycle.
- **XCTest** is utilized to test the `AmbientTrackingEngine`, `SpatialDatabaseManager`, and background logic.
- **Concurrency & Observation:** Legacy `XCTestExpectation` and `withObservationTracking` are strictly avoided when asserting on asynchronous GRDB `@Observable` state changes, as they freeze the `@MainActor` and starve GCD dispatch sources. Instead, tests use **cooperative polling** (`try await Task.sleep`) in a `while` loop to repeatedly yield the thread until the state resolves.
- **H3 Math & Transit Data:** Dedicated tests isolate spatial hashing math (`swift-h3`) and `transit_delta.sqlite` hydration to ensure data integrity.

### 6.2 Snapshot Testing (Phase 3)
Because Dérivée relies heavily on rich, custom SwiftUI visual elements (like the MapLibre overlays, `ultraThinMaterial` backgrounds, and the Transit Reveal bottom sheet) and strict spatial geometries:
- **UI Snapshots:** **swift-snapshot-testing** (Point-Free) is used to capture pixel-perfect snapshots of SwiftUI views loaded with mocked `@Observable` data. This prevents visual regressions from going unnoticed during rapid AI/agent-driven iterations.
- **Geometry Snapshots:** The `.dump` strategy is used to serialize and assert the exact memory structures of complex spatial types (like `MLNPolygon`). This acts as a structural lock against accidental modifications to coordinate math and winding orders, which simple count assertions (`XCTAssertEqual(count, 4)`) would fail to catch.

### 6.3 CI/CD Enforcement (Phase 4)
Because the native Xcode project is generated immutably via `xcodegen`:
- **Headless Testing:** All unit and snapshot tests run via `xcodebuild test` exclusively on **GitHub Actions**. We explicitly avoid Xcode Cloud due to its rigid `.xcodeproj` requirements that conflict with our `xcodegen` setup.
- **Fast Post-Push CI:** We embrace a solo-dev "vibe coding" workflow: commits are pushed directly to `main` without requiring PRs, and GitHub Actions acts as an automated safety net to catch regressions immediately.

---

## 7. Ecosystem & Backend Architecture

While the primary mobile client is pure native iOS, the surrounding ecosystem supports offline-first data generation and web accessibility.

### 7.1 Observer Daemon (Go)
To provide users with offline-first historical transit reliability data, a standalone daemon aggregates live GTFS-RT feeds.
- **Deployment:** The Go Observer is compiled as a single, statically linked binary and deployed directly to an Oracle Cloud ARM instance.
- **No Docker:** Containerization is explicitly avoided. Running the raw binary via `systemd` eliminates virtualized filesystem overhead and maximizes SQLite write performance.
- **Output:** A Zstandard-compressed SQLite database (`transit_delta.sqlite.zst`) containing 7-day headways, uploaded nightly to Cloudflare R2 for the mobile client to download.

### 7.2 Web MVP
A standalone web version of the transit map provides a lightweight alternative.
- **Brand Synchronization:** The MapLibre configuration in the web app hardcodes the exact Day/Night iOS hex colors (`#F9F9F6` / `#12121A`) to ensure absolute visual consistency across platforms.

---

## 8. Exploration, Customization & Performance Architecture (Wave J)

This section defines the implementation parameters and algorithmic constraints established by targeted deep research to sustain a 120Hz ProMotion budget (<8.33ms/frame) while executing continuous geospatial processing:

### 8.1 Camera Bounding & Viewport Clamping (`WJ1-CAMERA-BOUNDS`)
- **Prohibited Approaches:**
  - *`MLNMapView.setCameraTargetBounds` / `restrictedCoordinateBounds`:* Banned. Acts as a hard wall at the Metal layer, abruptly halting momentum and causing violent jitter / lockups during high-velocity pinch-to-zoom near boundaries.
  - *`UIGestureRecognizerDelegate` Swizzling:* Banned. Disrupts MapLibre's internal gesture decay and velocity interpolation algorithms.
- **Mandated Implementation:** Intercept camera changes via `MLNMapViewDelegate.mapView(_:shouldChangeFrom:to:reason:)`.
  - Mathematically evaluate if the projected `newCamera.centerCoordinate` falls outside the active `MLNCoordinateBounds`.
  - For gesture reasons (`.gesturePan`, `.gesturePinch`), allow temporary rubber-band overflow during continuous touch, then asynchronously animate a smooth corrective rollback using `mapView.setCamera(correctedCamera, withDuration: 0.4, animationTimingFunction: .easeOut)`.

### 8.2 The Spatial Unioning Imperative for 120Hz ProMotion (`WJ2-PERF-OPTIMIZATION`)
- **The Bottleneck:** Passing raw, un-dissolved H3 hexagons as individual interior rings to `MLNPolygon` causes MapLibre's underlying `earcut.hpp` triangulation to degrade from $O(N \log N)$ to $O(N^2)$. Pushing thousands of disconnected micro-holes freezes the `@MainActor` render loop and causes severe thermal throttling.
- **Mandated Implementation:**
  - Preprocess the active hex set using Uber H3's `cellsToMultiPolygon` / `H3Engine.dissolveToBoundaries` in a `Task.detached(priority: .userInitiated)`.
  - Dissolves shared internal edges of contiguous hex clusters into single macro-polygon boundaries, reducing vertex counts by >85%.
  - Enforce counter-clockwise winding order on interior rings (`points.reversed()`) to match MapLibre's clockwise exterior ring convention.
- **Performance Budgets (Xcode Instruments):**
  - Time Profiler: `@MainActor` execution of `shapeSource.shape = fogPolygon` must complete in **< 1.5ms**.
  - Metal System Trace: Geometry allocation must remain flat without triangulation pipeline spikes.
  - Core Animation: Commit times must consistently align with the 120Hz VSync interval (8.33ms).

### 8.3 Vector Tile POI Masking via `mgl_distanceFrom:` (`WJ3-FOG-POI-MASKING`)
- **Prohibited Approaches:**
  - *Layer Z-Ordering Alone:* Ineffective. High-contrast text halos and bold geometries still bleed through 0.85 opacity fog.
  - *Dynamic `['within', polygon]` Expressions:* Banned. Evaluating complex multi-polygon geometries against every vector tile feature on map pan saturates the CPU.
- **Mandated Implementation:**
  - Suppress unrevealed POIs using MapLibre's GPU-accelerated `mgl_distanceFrom:` expression tied to the user's active `CLLocationCoordinate2D`.
  - Apply `mgl_distanceFrom:(userPoint) <= 200` predicate filters to target symbol layers (`poi_label`, `transit_stop_label`, `park_label`, `place_label`).
  - Set `textIgnoresPlacement = true` and `textAllowsOverlap = true` to prevent hidden labels from altering visible layout collisions.

### 8.4 The Unified Composite Style Pattern (`WJ4-BASEMAP-SWITCHER`)
- **Prohibited Approach:** Swapping `MLNMapView.styleURL` at runtime. Banned because destroying `MLNStyle` tears down all runtime data sources (`MLNShapeSource`, fog geometry) and causes a multi-second freeze while re-hydrating.
- **Mandated Implementation:** Load a single **Unified Composite Style** JSON containing all base vectors, dark mode styling, and transit network layers.
  - Transition themes (Standard Day, Night, Transit) by interpolating layer properties (`fillColorTransition`, `lineOpacityTransition`) using `MLNTransition(duration: 0.6)` directly on the GPU.

### 8.5 Direct SwiftProtobuf GTFS-RT Ingestion (`WJ6-TRANSIT-NODE-TRACKING`)
- **Mandated Implementation:** Ingest binary `.pb` vehicle position and trip update feeds directly via `SwiftProtobuf` (`TransitRealtime_FeedMessage(serializedData:)`), completely avoiding JSON conversion overhead.
  - Map entities directly into lightweight Swift coordinate dictionaries and immediately release the `FeedMessage` buffer.
  - Render ephemeral route overlays using a dual-layer approach (6px light casing + 4px route line) so dark transit lines remain legible over dark fog.

### 8.6 Zero-Geometry Customization Parameterization (`WJ5-CUSTOMIZATION-SETTINGS`)
- Changing user preferences (fog opacity `0.60` to `0.98`, hex borders) must **never** trigger polygon recomputation or database queries.
- Update `fogLayer.fillOpacity` directly via `NSExpression(forConstantValue: targetOpacity)` with `fillOpacityTransition = MLNTransition(duration: 0)` for immediate 120Hz slider responsiveness.


