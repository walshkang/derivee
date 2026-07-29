# Fog of Wburg — Unified Roadmap

This document is the single source of truth for all planned development waves.

> [!IMPORTANT]
> **Agent Roadmap Maintenance Protocol**:
> 1. When completing a task, update its status in the **Master Status Table** from `Planned` to `✅ Done`.
> 2. Move the completed task's detailed prompt out of this file and append it to `archive/shipped-waves-archive.md`.
> 3. Keep this file lean to minimize context bloat.

> [!WARNING]
> **Architectural Transition in Progress.** All pre-Wave-A development (Waves 1–14.10) was completed under the original Expo Managed / JS-background architecture. Those waves are archived in `archive/shipped-waves-archive.md`. Waves that relied on JavaScript background execution (W4-TRACK, W14.5-BACKGROUND, W14.6, W14.7, W14.8) are marked as **🔄 Superseded** — their functionality is replaced by the Sleepy Hermes Transition (Wave A–D).

---

## Master Status Table

### Completed Waves (Pre-Sleepy Hermes — Archived)

| Wave | Task ID | Title | Status |
|:---:|:---:|:---|:---:|
| 1 | W1-INIT | Expo Scaffold & Zustand State | ✅ Archived |
| 1 | W1-NAV | Navigation Shell & Splash Screen | ✅ Archived |
| 2 | W2-DB | op-sqlite JSI Initialization & WAL Mode | ✅ Archived |
| 2 | W2-H3 | h3-js Core Logic & Grid Conversions | ✅ Archived |
| 3 | W3-MAP | MapLibre Engine & 3D Terrain Base | ✅ Archived |
| 3 | W3-FOG | 50km Bounding Box & Inverted Polygon | ✅ Archived |
| 4 | W4-TRACK | expo-location Background Service & Batching | 🔄 Superseded → Wave C |
| 4 | W4-DRIFT | Implied Speed Filter & Geometry Unioning | 🔄 Superseded → Wave C |
| 5 | W5-POI | Gamification & POI Integration | ✅ Archived |
| 6 | W6-POLISH | Performance & App Store Launch | ✅ Archived |
| 7 | W7-AMBIENT | Vicinity Bubble & Ghost POI Logic | ✅ Archived |
| 8 | W8-TRANSIT | Live GTFS-RT Decoding & Transit Bottom-Sheet | ✅ Archived |
| 8.1 | W8.1-TRANSIT-REFACTOR | Dual-Format Transit Parser (JSON + PB) & API Keys | ✅ Archived |
| 9 | W9-OBSERVER | Headless Observer Tool & CDN Handoff | ✅ Archived |
| 10 | W10-HISTORIAN | GPX/HealthKit Import & Macro-Reveal Animation | ✅ Archived |
| 11 | W11-TIMETABLE | Standalone Transit App (Web/Spinoff) & Headway Matrix | ✅ Archived |
| 11.5 | W11.5-MVP-POLISH | Light Mode UI Refactor & MVP Launch | ✅ Archived |
| 13 | W13-FOG-TIERS | 3-Tier Fog State & Reference Counting | ✅ Archived |
| 13 | W13-FOG-STYLE | MapLibre Dual-Layer & Temporal Interpolation | ✅ Archived |
| 13 | W13-AMBIENT-TRACKING | Ambient Tracking & Start Button Removal | ✅ Archived |
| 14 | W14-DATA-NEIGHBORHOODS | Neighborhood Denominators & Water Subtraction | ✅ Archived |
| 14 | W14-UI-STATS | Progression Stats UI: Contextual Pill & Archive Screen | ✅ Archived |
| 14.5 | W14.5-BACKGROUND | Local Expo Module for iOS Background Assertions | 🔄 Superseded → Wave C |
| 14.5 | W14.5-DB-MIGRATE | SQLite geojson_cache & Splash Screen Gate | ✅ Archived |
| 14.5 | W14.5-STORE | AppState Delta-Buffer & Zustand Refactor | 🔄 Superseded → Wave D |
| 14.5 | W14.5-RENDER | MapLibre Native Array Concatenation (Remove Turf) | ✅ Archived |
| 14.6 | W14.6-BATTERY-HOTFIX | Bridge & Polling Optimization Patch | 🔄 Superseded → Wave A/D |
| 14.7 | W14.7-LOCATION-AUDIT | Stop the Bleeding: expo-location Audit | 🔄 Superseded → Wave C |
| 14.8 | W14.8-SET-GATE | Unblock the Thread: In-Memory Set Gate | 🔄 Superseded → Wave D |
| 14.9 | W14.9-DDS-FOG | DDS Refactor: MapLibre Data-Driven Styling | ✅ Archived |
| 14.10 | W14.10-STATS-UI | Fix UI Bottlenecks: FlashList & Bottom Sheet | ✅ Archived |

### 🚀 Sleepy Hermes Transition (Active)

| Wave | Task ID | Title | Size | Status |
|:---:|:---:|:---|:---:|:---:|
| **A** | **WA-DB-CONCURRENCY** | **Database Config & Dual-Thread Concurrency** | **M** | Planned |
| **B** | **WB-NITRO-SCAFFOLD** | **Nitro Module Scaffolding & Code Generation** | **M** | Planned |
| **C** | **WC-SWIFT-SERVICE** | **Swift Background Service & Baseband Economics** | **L** | Planned |
| **D** | **WD-UI-HYDRATION** | **UI Synchronization & Foreground Hydration** | **M** | Planned |

### Post-Sleepy-Hermes (Deferred)

| Wave | Task ID | Title | Size | Status |
|:---:|:---:|:---|:---:|:---:|
| — | W11.6-DEVOPS | Deploy New Go Observer to Oracle Cloud | M | Deferred |
| — | W11.7-UI-MATRIX | Build Headway Matrix (Timetable) UI | L | Deferred |
| — | W12-BOSTON | Multi-City Expansion: MBTA | L | Deferred |
| — | W15-DYNAMIC-ISLAND | Dynamic Island Support for Stat Bar | S | Deferred |

---

## Wave A — Database Configuration & Dual-Thread Concurrency [Planned]

**Task ID:** `WA-DB-CONCURRENCY`
**Depends on:** Native iOS workspace materialized (CNG prebuild committed).

### Goal
Establish the foundational shared persistence layer for the Sleepy Hermes architecture. Configure the SQLite database for **dual-thread concurrent access** — one connection from the Swift C-API (background writes) and one from `@op-engineering/op-sqlite` JSI (foreground reads) — targeting the exact same physical `.db` file.

### Agent Directives

1. **Verify JS-side WAL configuration:**
   * Confirm that the existing `@op-engineering/op-sqlite` initialization in `src/db/database.ts` executes `PRAGMA journal_mode = WAL;` on connection open.
   * Confirm the `explored_hexes` and `active_visibility` tables use `WITHOUT ROWID`.
   * Confirm `PRAGMA synchronous = NORMAL;` is set.

2. **Document the Swift-side database file path resolution:**
   * The Swift background service must resolve the database path via `FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)`, ensuring intermediate directories are created, and appending the same `.db` filename used by `@op-engineering/op-sqlite`.
   * Produce a clear reference document (or inline comment specification) showing the exact path both connections must align on.

3. **Document the Swift `sqlite3_open_v2` flag configuration:**
   * `SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX`
   * Document the `defer sqlite3_close(db)` cleanup pattern for failed initialization.

4. **Document the Swift-side PRAGMA sequence:**
   * `PRAGMA journal_mode = WAL;`
   * `PRAGMA synchronous = NORMAL;`

5. **Document the prepared statement lifecycle:**
   * `sqlite3_prepare_v2` at initialization with `INSERT OR IGNORE INTO explored_hexes (h3_index, discovered_at) VALUES (?, ?)`
   * Per-coordinate cycle: `sqlite3_bind_text` → `sqlite3_step` → `sqlite3_reset`
   * `sqlite3_finalize` on service teardown.

6. **Schema migration guard:**
   * Ensure the JS-side migration logic handles the case where the Swift background service may have already created the database file and tables before the user ever launches the foreground app.

### Verification
* Confirm `PRAGMA journal_mode;` returns `wal` on both connections (document how to verify from each side).
* Confirm the `explored_hexes` table schema matches between JS and Swift expectations.
* No application code is written in this wave — output is configuration verification and reference documentation for Waves B/C.

---

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

---

## Wave C — Swift Background Service & Baseband Economics [Planned]

**Task ID:** `WC-SWIFT-SERVICE`
**Depends on:** Wave B (Nitro scaffolding + Xcode GUI linkage completed by human).

### Goal
Implement the core native Swift background service (`HybridTracker.swift`) that independently manages hardware location requests, executes drift filtering, calculates H3 spatial indices via C-interop, and persists data to SQLite — all without waking the Hermes JavaScript engine.

### Agent Directives

1. **`HybridTracker.swift` — Core class:**
   * Declare `final class HybridTracker` conforming to the generated `HybridTrackingSpec` protocol.
   * Hold persistent references to:
     * `CLLocationManager` (configured for background updates)
     * SQLite `OpaquePointer` (C-API connection)
     * Optional Nitro callback closure

2. **CLLocationManager configuration:**
   * `distanceFilter = 10` (meters)
   * `allowsBackgroundLocationUpdates = true`
   * `pausesLocationUpdatesAutomatically = true`
   * Deferred updates at 50-meter threshold.
   * `activityType = .fitness`

3. **`locationManager(_:didUpdateLocations:)` delegate:**
   * Wrap entire processing block in `beginBackgroundTask` / `endBackgroundTask`.
   * For each coordinate in the batch:
     * **Drift Gate:** Calculate $\Delta d / \Delta t$. If $> 12$ m/s, discard.
     * **H3 C-interop:** Call `latLngToCell` at Resolution 11.
     * **String conversion:** Cast 64-bit integer → 15-character hex string immediately.
     * **Database write:** Bind to prepared statement → `sqlite3_step` → `sqlite3_reset`.
     * **Foreground callback:** If app state is active, invoke stored Nitro callback with new H3 string.

4. **Resource lifecycle:**
   * `sqlite3_finalize` on prepared statement during teardown.
   * `sqlite3_close` on the connection pointer.
   * `CLLocationManager` delegate set to `nil`.

### Verification
* Xcode project builds successfully with the new Swift file.
* `CLLocationManager` delegate is configured with correct distance filtering parameters.
* H3 indices are verified as 15-character hex strings (not raw integers) before database insertion.
* Background task assertions are correctly paired (begin/end).

---

## Wave D — UI Synchronization & Foreground Hydration [Planned]

**Task ID:** `WD-UI-HYDRATION`
**Depends on:** Wave C (Swift background service compiles and runs).

### Goal
Wire the React Native foreground to seamlessly hydrate from the shared SQLite database upon app resume. Implement the Nitro real-time callback integration and the $O(1)$ In-Memory Set Gate to prevent bridge starvation.

### Agent Directives

1. **Nitro module initialization (`src/native/trackingBridge.ts`):**
   * Import the `HybridTracker` Nitro module.
   * Expose a clean TypeScript API for the React Native layer to call `startTracking()`, `stopTracking()`, and `addListener()`.

2. **AppState lifecycle hydration (`src/hooks/useAppStateHydration.ts`):**
   * Listen for `AppState` transition from `"background"` → `"active"`.
   * On transition: execute a synchronous `SELECT` via `@op-engineering/op-sqlite` to pull the delta of newly discovered H3 hexes since the last known timestamp.
   * Feed results through the In-Memory Set Gate before updating Zustand.

3. **$O(1)$ In-Memory Set Gate (refactor `src/store/useExplorationStore.ts`):**
   * On app boot: query all unlocked H3 IDs synchronously from `@op-engineering/op-sqlite` → load into a JavaScript `Set`.
   * Gate function: `Set.has(h3Index)`
     * `true` → drop execution silently (no Zustand update, no bridge payload).
     * `false` → add to Set, write to Zustand, update MapLibre DDS `['match']` expression.

4. **Nitro real-time callback integration:**
   * In the main map component, register a Nitro listener callback on mount.
   * When the callback fires with a new H3 string:
     * Pass through the Set Gate.
     * If new: add to Set, update Zustand, trigger MapLibre DDS update via `withSynchronousUpdate(true)`.
   * Unregister the listener on unmount.

5. **Remove deprecated background JS dependencies:**
   * Remove `expo-task-manager` from `package.json` if still present.
   * Remove any `TaskManager.defineTask()` or `Location.startLocationUpdatesAsync()` calls.
   * Remove the local Expo Module for background assertions (superseded by Wave C's native integration).

### Verification
* App foregrounds after background exploration and correctly displays newly unlocked hexes.
* MapLibre maintains 60fps during hydration (no bridge starvation).
* `Set.has()` correctly gates redundant updates (verify via console logging in dev).
* `expo-task-manager` is fully removed from the dependency tree.