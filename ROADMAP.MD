# Dérivée — Unified Roadmap

This document is the single source of truth for all planned development waves.

> [!IMPORTANT]
> **Agent Roadmap Maintenance Protocol**:
> 1. When completing a task, update its status in the **Master Status Table** from `Planned` to `✅ Done`.
> 2. Move the completed task's detailed prompt out of this file and append it to `archive/shipped-waves-archive.md`.
> 3. Keep this file lean to minimize context bloat.

> [!WARNING]
> **Architectural Transition in Progress.** All pre-Wave-A development (Waves 1–14.10) was completed under the original Expo Managed / JS-background architecture. Those waves are archived in `archive/shipped-waves-archive.md`. Waves that relied on JavaScript background execution (W4-TRACK, W14.5-BACKGROUND, W14.6, W14.7, W14.8) are marked as **🔄 Superseded** — their functionality is replaced by the Sleepy Hermes Transition (Wave A–D). Waves E–H align the UI to the updated `docs/design.md` specification and prepare for App Store submission.

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
| 14 | W14-UI-STATS | Progression Stats UI: Contextual Pill & Stats and Profile Screen | ✅ Archived |
| 14.5 | W14.5-BACKGROUND | Local Expo Module for iOS Background Assertions | 🔄 Superseded → Wave C |
| 14.5 | W14.5-DB-MIGRATE | SQLite geojson_cache & Splash Screen Gate | ✅ Archived |
| 14.5 | W14.5-STORE | AppState Delta-Buffer & Zustand Refactor | 🔄 Superseded → Wave D |
| 14.5 | W14.5-RENDER | MapLibre Native Array Concatenation (Remove Turf) | ✅ Archived |
| 14.6 | W14.6-BATTERY-HOTFIX | Bridge & Polling Optimization Patch | 🔄 Superseded → Wave A/D |
| 14.7 | W14.7-LOCATION-AUDIT | Stop the Bleeding: expo-location Audit | 🔄 Superseded → Wave C |
| 14.8 | W14.8-SET-GATE | Unblock the Thread: In-Memory Set Gate | 🔄 Superseded → Wave D |
| 14.9 | W14.9-DDS-FOG | DDS Refactor: MapLibre Data-Driven Styling | ✅ Archived |
| 14.10 | W14.10-STATS-UI | Fix UI Bottlenecks: FlashList & Bottom Sheet | ✅ Archived |

### 🚀 Pure Native iOS Migration (Complete)

The project has fully abandoned the hybrid React Native / Expo architecture. All tracking, database, and UI logic is now executed natively in Swift within the `DeriveeNative/` folder.

| Wave | Task ID | Title | Size | Status |
|:---:|:---:|:---|:---:|:---:|
| **N.1** | **WN1-XCODEGEN** | **Pure Native Project Setup (xcodegen + H3)** | **M** | ✅ Done |
| **N.2** | **WN2-GRDB** | **GRDB SQLite Manager & Observable Store** | **M** | ✅ Done |
| **N.3** | **WN3-TRACKING** | **Ambient Tracking Engine (liveUpdates + Shield)** | **L** | ✅ Done |

### 🧪 Testing & CI/CD Rollout

| Phase | Task ID | Title | Size | Status |
|:---:|:---:|:---|:---:|:---:|
| **1** | **TEST-PHASE1** | **Core Engine Unit Tests (Background & SQLite)** | **M** | ✅ Done |
| **2** | **TEST-PHASE2** | **Spatial Math & Transit Hydration Unit Tests** | **S** | ✅ Done |
| **3** | **TEST-PHASE3** | **Automated UI / Snapshot Testing** | **M** | ✅ Done |
| **4** | **TEST-PHASE4** | **CI/CD Pipeline (GitHub Actions)** | **M** | Planned (Start of Wave H) |

### 🎨 Design Alignment & Ship

| Wave | Task ID | Title | Size | Status |
|:---:|:---:|:---|:---:|:---:|
| **11.6** | **W11.6-DEVOPS** | **Deploy Go Observer to Oracle Cloud & Seed R2** | **M** | ✅ Done |
| **11.8** | **W11.8-WEB-FIXES** | **Transit Web MVP Bugfixes & Polish** | **M** | Planned |
| **E** | **WE-ONBOARDING** | **Onboarding Gate & First-Launch Infrastructure** | **M** | ✅ Done |
| **F.1** | **WF1-FAB** | **Map UI: Floating Action Buttons** | **S** | ✅ Done |
| **F.2** | **WF2-TOAST** | **Discovery Toast Overlay** | **S** | ✅ Done |
| **F.3** | **WF3-POI-LIFECYCLE** | **Ghost POI 3-Phase Lifecycle** | **M** | ✅ Done |
| **F.4** | **WF4-HEX-ANIMATION** | **Ambient Hex Unlock Animation** | **S** | ✅ Done |
| **G** | **WG-TRANSIT-REVEAL** | **Transit Reveal Enhancements** | **S** | ✅ Done |
| **H** | **WH-SHIP** | **Polish, Stats and Profile Rewire & Ship Prep** | **M** | ✅ Done |
| **H.1** | **WH.1-PANNING** | **Stats UI: Neighborhood Map Panning** | **S** | ✅ Done |

### 🐛 Fog Reliability & Startup Performance (Cold-Start Fix)

| Wave | Task ID | Title | Size | Status |
|:---:|:---:|:---|:---:|:---:|
| **I.1** | **WI1-FOG-GATE** | **Fog Startup Gate: Synchronize Shape Computation with Map Ready** | **M** | ✅ Done |
| **I.2** | **WI2-WINDING** | **Winding Order Audit & Interior Ring Hardening** | **S** | ✅ Done |
| **I.3** | **WI3-FOG-TESTS** | **Cold-Start Fog Regression Tests** | **S** | ✅ Done (Sandbox Quirks Benched) |
| **I.3a** | **WI3a-LIVE-FOG** | **Fix Live Fog Update Starvation (`.background` → `.userInitiated`)** | **XS** | ✅ Done |
| **I.4** | **WI4-ASYNC-READS** | **Eliminate Main-Thread DB Reads & Configure GRDB QoS** | **M** | ✅ Done |
| **I.5** | **WI5-HANG-TESTS** | **Priority Inversion Regression Tests** | **S** | ✅ Done |
| **I.6** | **WI6-TRACK-STOP** | **Fix Ambient Tracking Stop Lifecycle (Live Activity + Persistence)** | **S** | ✅ Done |

### Post-Ship (Deferred)

| Wave | Task ID | Title | Size | Status |
|:---:|:---:|:---|:---:|:---:|
| — | W11.7-UI-MATRIX | Build Headway Matrix (Timetable) UI | L | Deferred |
| — | W12-BOSTON | Multi-City Expansion: MBTA | L | Deferred |
| — | W15-DYNAMIC-ISLAND | Dynamic Island Support for Stat Bar | S | ✅ Done |

---



## Wave 11.6 — Deploy Go Observer to Oracle Cloud & Seed R2 [Planned]

**Task ID:** `W11.6-DEVOPS`
**Depends on:** Wave D complete. Observer tool already built (W9-OBSERVER).

### Goal
Deploy the Go-based Observer daemon to Oracle Cloud infrastructure and establish the automated nightly pipeline that generates Zstandard-compressed SQLite transit delta files and uploads them to Cloudflare R2. This must be operational **before** Wave E, which depends on downloading the transit delta on first launch.

### Agent Directives

1. **Oracle Cloud deployment:**
   * **Do not use Docker:** Compile the Go daemon into a single, statically linked binary to maximize SQLite write speeds on ARM.
   * Deploy directly to the existing Oracle Cloud Free Tier instance (IP: 150.136.171.50).
   * Configure `systemd` for automatic restart and process supervision.

2. **Nightly pipeline:**
   * Cron job: Execute the Observer's GTFS static + GTFS-RT aggregation at 03:00 UTC daily.
   * Output: `nyc_transit_delta.sqlite.zst` — a Zstandard-compressed SQLite database containing 7-day historical headway data.
   * Upload to Cloudflare R2 bucket with a deterministic key path (e.g., `deltas/nyc/latest.sqlite.zst`).

3. **R2 bucket configuration:**
   * Create the Cloudflare R2 bucket if not already provisioned.
   * Configure public read access (or signed URL generation) for the mobile client to fetch the delta.
   * Set appropriate cache headers (`Cache-Control: max-age=86400`).

4. **Health monitoring:**
   * Basic health check endpoint or log-based alerting if the nightly job fails.
   * Ensure the delta file timestamp is verifiable by the mobile client to prevent stale data.

### Verification
* Observer daemon runs continuously on Oracle Cloud without manual intervention.
* `nyc_transit_delta.sqlite.zst` is present and fresh (< 24 hours old) on the R2 bucket.
* The file is publicly fetchable from the mobile client's network context.
* File decompresses cleanly and contains valid SQLite with the expected schema.

---

## Wave 11.8 — Transit Web MVP Bugfixes & Polish [Planned]

**Task ID:** `W11.8-WEB-FIXES`
**Depends on:** Wave 11.5 (Transit Web MVP Launch).

### Goal
Address immediate visual and functional bugs in the `transit-web` spinoff to ensure the MVP is stable, visually polished, and matches the fidelity of the official MTA maps. This wave also includes minor lingering mobile UI polish.

### Agent Directives

1. **Map Color & Stop Matching:**
   * [x] Fix the `stop_id` to route matching logic so that all subway stops (e.g. the ones rendering as purple defaults) correctly inherit their official MTA route colors and properly pull live arrival times.
2. **Map Design & Routing Fidelity:**
   * [ ] Take inspiration from the latest MTA subway map: show all individual lines on the map rather than merged trunks.
   * [ ] Render multiple parallel lines for shared corridors (e.g. 3 distinct green lines for the 4/5/6 to visually indicate transfer stations).
   * [ ] Ensure bridges carrying multiple services (e.g., Williamsburg bridge) render with all respective colors (Orange for M, Brown for J/Z).
3. **Web MVP Brand Synchronization:**
   * [ ] **Map Style:** Hardcode the exact Dérivée Day/Night hex codes (`#F9F9F6` for parchment white / `#12121A` for midnight slate) into the Web MVP's MapLibre style configuration to mirror the iOS app.
   * [x] Update the real-time arrivals text in the bottom sheet to display proper directionality (e.g., "Manhattan-bound", "Uptown").
   * [ ] **Arrivals Contrast:** Fix contrast by using standard high-contrast pure black/white for textual arrival times.
   * [ ] **Sparkline Colors:** Strictly use the brand's Electric Amber (`#FFB300`) for the historical reliability sparkline, avoiding arbitrary library default colors.
4. **Historical Data Validation:**
   * [x] Ensure historical reliability sparklines accurately load real SQLite data for both subways and buses from the Observer daemon, rather than falling back to dummy/empty states.
5. **Bus Map Clutter Reduction:**
   * [ ] Optimize the bus map view by implementing dynamic zoom-based loading.
   * [ ] Only render bus stops that are within the current view window at a close zoom level, or filter to only display the busiest nodes at macro zoom levels.
6. **Mobile UI Polish (iOS):**
   * [ ] **The Transit Reveal Dissolve:** Update `TransitRevealSheet` dismissal logic to add a 200ms opacity fade out to the ephemeral MapLibre `LineLayer` (the train route). This prevents the layer from unmounting instantly, ensuring it dissolves gracefully to match the spring physics of the SwiftUI bottom sheet.

### Verification
* All subway nodes match their official colors and fetch live data correctly.
* Parallel subway lines are visible on shared corridors.
* Arrivals text is legible in Light Mode and includes direction strings.
* Sparklines render real data from `transit_delta.sqlite`.
* Bus view remains performant and legible at all zoom levels.

---

## Testing Strategy & Rollout

Broadening the overall testing strategy across upcoming waves. We are adopting a **staggered approach** to ensure a solid foundation before building further UI:

### Phase 1: The Core Engine (Current Plan)
**Status:** Ready for Execution.

**Why it's perfect:** It isolates the most volatile, battery-draining, and logic-heavy part of the app (Background Location + SQLite concurrency) and proves it works deterministically without needing physical hardware.

### Phase 2: Pure Spatial & Data Unit Tests
**Status:** Completed.
The testing wave isolates raw H3 spatial math (Resolution 11), coordinate round-tripping, MapLibre interior hole CW winding order, and GRDB transit database hydration testing.
Once Phase 1 is merged, the next testing wave isolates the raw math and data hydration, completely separate from the tracking engine. Wave G relies heavily on this transit data and spatial math.

* **H3 Boundary Tests:** Feed known edge-case coordinates (e.g., coordinates exactly on the boundary of two hexes, or coordinates over water) into the `swift-h3` wrapper. Assert that the resulting 15-character hex string exactly matches the expected output.
* **Transit Hydration Tests:** Write a test that takes a mocked, ultra-small `transit_delta.sqlite` file, runs the `SpatialDatabaseManager` attachment logic, and asserts that the `transit.stops` table successfully merges.

### Phase 3: Automated UI / Snapshot Testing
**Timing:** Implement **DURING** Wave G and **BEFORE** Wave H.
As more gamified elements are added (like the Skia "Morning Sun" reveal or Transit Bottom Sheets), visual regressions become the biggest risk from AI agents.

* **The Strategy:** Implement a **Split-Target Architecture** utilizing `swift-snapshot-testing` for visual UI only.
* **How it works:**
  1. **`DeriveeCoreTests` (No App Host):** Validates pure logic (GRDB concurrency, H3 math). Runs headlessly in milliseconds.
  2. **`DeriveeSnapshotTests` (Requires App Host):** Validates SwiftUI layouts. Boots an iPhone simulator in the background. Tests render SwiftUI views (`StatsView`, `TransitRevealSheet`) with mocked `@Observable` state, taking a literal screenshot. This guarantees the aesthetic is never compromised by an agent accidentally modifying padding, `.opacity()`, or ZStack orders.
* **Important Constraint:** Do NOT use snapshot `.dump` diffing for MapLibre objects like `MLNPolygon`. Keep pure native data assertions (e.g. `interiorPolygons?.count`) for the fog math.

### Phase 4: CI/CD Pipeline (The "Fast Deployment" Engine)
**Timing:** Set up at the **START** of Wave H.
To actually achieve "fast deployment," these tests cannot just live on the local machine. Because the project uses `xcodegen` and pure Swift, the CI/CD setup is incredibly clean.

* **The Strategy:** Set up GitHub Actions (avoid Xcode Cloud due to its rigid `.xcodeproj` expectations which conflict with our dynamic `xcodegen` setup).
* **The Workflow:** 
  1. Push a branch generated by an AI agent.
  2. The CI server checks out the code and runs `xcodegen` to generate the `.xcodeproj`.
  3. It runs `xcodebuild test` on both the headless core target and the simulator-backed snapshot target.
  4. If either logic or visual regressions are found, the pull request is blocked. If it's green, it auto-merges or deploys to TestFlight.

> [!WARNING]
> **CI Safety: Benched Tests.** Before Phase 4 goes live, any test using the `disabled_` prefix convention (e.g., `disabled_testNewlyDiscoveredHexTriggersFogShapeUpdate` in `SpatialStoreFogTests.swift`) must be either **fixed and re-enabled** or converted to use explicit `throw XCTSkip("Reason")`. The `disabled_` prefix is a fragile naming convention — if a future agent renames the test to "fix the gap," it will hang CI indefinitely due to the `withObservationTracking` runloop starvation issue. `XCTSkip` is the CI-safe alternative.

---

---

## Wave I.1 — Fog Startup Gate: Synchronize Shape Computation with Map Ready [Planned]

**Task ID:** `WI1-FOG-GATE`
**Depends on:** None. This is a critical bugfix wave.

### Problem Statement

After a force-quit and cold relaunch, the user's previously explored hexes (including the current hex) are not visible — the fog layer renders as a solid opaque polygon with zero holes. The fog only corrects itself when the *next* database write (new hex discovery) triggers a `ValueObservation` cycle. This makes the app feel broken on every cold start.

**Root Cause:** Three systems boot concurrently with no synchronization:
1. `SpatialStore.init()` starts `ValueObservation` → fires `recomputeFogShape()` on `Task.detached(priority: .background)`.
2. MapLibre's `didFinishLoading` fires on the main thread and calls `updateExploredHexes()` with `spatialStore.currentFogShape`.
3. If `recomputeFogShape()` hasn't finished yet, `currentFogShape` is `nil` → the fog source keeps its initial solid polygon. There is no retry mechanism.

### Agent Directives

1. **Elevate initial fog computation priority:**
   * In `SpatialStore.recomputeFogShape()`, change the initial `Task.detached(priority:)` from `.background` to `.userInitiated` **only for the first computation** (when `previousCount == 0`). Subsequent recomputations can remain `.background`. The first fog render must beat MapLibre's style load.

2. **Add a "map ready" handshake in `MapView.Coordinator`:**
   * Add a `var isMapStyleLoaded: Bool = false` flag to the Coordinator.
   * In `didFinishLoading`: set the flag to `true`, then call `updateExploredHexes()`. If `currentFogShape` is `nil` at this point, the flag ensures the next `updateUIView` call will apply the shape.
   * In `updateExploredHexes()`: remove the early `guard` that silently returns when `shape` is `nil`. Instead, if `shape` is `nil` **and** the map style is loaded, log a diagnostic message ("⚠️ Fog shape not yet ready, will apply on next update").

3. **Add a deferred apply in `updateUIView`:**
   * In the existing `updateExploredHexes()` call path within `updateUIView`, ensure that if `isMapStyleLoaded == true` and `shape` transitions from `nil` → non-nil, the fog source is updated immediately. The current code already does this implicitly via SwiftUI's `@Observable` tracking, but add a `print` log to confirm the path is exercised on cold start: `"✅ Deferred fog shape applied (\(innerRings) holes)"`.

4. **Ensure the initial fog source in `setupLayers` uses a jittered bounding box:**
   * The initial fog polygon created in `setupLayers()` currently uses static coordinates `(41.5, -74.5)` etc. Change these to include a small static offset (e.g., `41.500001, -74.500001`) so they never exactly match the `recomputeFogShape()` jittered bounds. This prevents MapLibre from caching the first shape and ignoring the computed replacement.

5. **Do NOT change the fog opacity value** (`0.3`). Do NOT change the exterior bounding box dimensions. Do NOT modify the H3 resolution or any database schema.

### Files to Modify

* `DeriveeNative/Derivee/SpatialStore.swift` — priority elevation for first computation.
* `DeriveeNative/Derivee/MapView.swift` — `isMapStyleLoaded` flag, deferred apply logic, jittered initial bounds.

### Verification

1. Build and run the app on a physical device.
2. Walk around to accumulate ≥5 explored hexes.
3. Force-quit the app (swipe up from app switcher).
4. Relaunch the app.
5. **Expected:** The fog layer renders with all previously explored hexes visible as holes **immediately** when the map finishes loading — no delay, no solid fog flash.
6. Check Xcode console for: `"✅ Deferred fog shape applied"` log confirming the handshake path was exercised.
7. Verify that real-time hex unlocking still works (walk to a new hex → fog melts away with the 300ms transition).

---

## Wave I.2 — Winding Order Audit & Interior Ring Hardening [Done]

**Task ID:** `WI2-WINDING`
**Depends on:** Wave I.1 (the fog startup gate must be in place first so the winding order fix is testable on cold start).

### Problem Statement

The fog polygon construction in `SpatialStore.recomputeFogShape()` uses **clockwise** winding for both the exterior ring and interior rings (holes). The H3 boundary coordinates are explicitly reversed at line 101 (`coords.reverse()`), flipping them from CCW → CW. However, the GeoJSON/MapLibre convention for polygon holes is ambiguous across platforms:

* **GeoJSON RFC 7946:** Exterior = CCW, Holes = CW.
* **MapLibre Native (iOS):** Historically tolerant of both conventions, but documentation recommends exterior = CW, holes = CCW.

The current code may be working by accident. This wave audits and hardens the winding order to eliminate a class of silent rendering bugs.

### Agent Directives

1. **Audit the current winding behavior:**
   * Add temporary diagnostic logging inside `recomputeFogShape()` that prints the winding order of the first interior ring (compute the signed area — positive = CW, negative = CCW). Log: `"🔍 Interior ring winding: CW"` or `"🔍 Interior ring winding: CCW"`.
   * Build and run. Record which winding order is currently producing visible holes.

2. **Test the opposite winding order:**
   * Remove the `coords.reverse()` call on the interior rings (leaving them as H3's default CCW).
   * Build and run. Observe whether the holes still render correctly.
   * **If holes disappear:** The current CW winding is correct for this MapLibre version. Restore `.reverse()` and add a permanent comment:
     ```swift
     // VERIFIED: MapLibre Native (iOS) requires CW winding for interior polygon rings.
     // Tested in Wave I.2. Do NOT change without re-testing fog rendering.
     ```
   * **If holes still render:** CCW is also accepted. Prefer the convention that matches GeoJSON RFC 7946 (exterior CCW, holes CW) and document accordingly.

3. **Standardize the exterior ring:**
   * Verify the exterior bounding box coordinates are wound in the correct direction for the chosen convention. Add a permanent comment documenting the verified order.

4. **Remove the diagnostic logging** added in step 1 after verification. Leave only the permanent convention comments.

5. **Do NOT change** the bounding box dimensions, the H3 resolution, the fog opacity, or any database schema.

### Files to Modify

* `DeriveeNative/Derivee/SpatialStore.swift` — winding order audit, comments, and potential `.reverse()` change.

### Verification

1. Build and run on a physical device with ≥5 previously explored hexes.
2. Confirm all hex holes render correctly in the fog layer.
3. Force-quit and relaunch — holes still visible on cold start (depends on I.1).
4. Verify the permanent winding order comments are present in the code.
5. Ensure no diagnostic print statements remain in the final commit.

---

## Wave I.3 — Cold-Start Fog Regression Tests & Observation Deadlocks [Done — Partial]

> [!WARNING]
> **Status: ✅ Done (1 test benched).** 3 of 4 specified tests pass. `GRDBObservationTests.swift` was successfully migrated to cooperative polling and passes. However, `SpatialStoreFogTests.swift` still uses `withObservationTracking` in its `waitForFogShape` helper (contradicting the cooperative polling mandate in `docs/architecture.md`). This works for the 3 "init → first shape" tests because the shape resolves before runloop starvation, but hangs on the live reactivity test.
>
> **Benched test:** `disabled_testNewlyDiscoveredHexTriggersFogShapeUpdate` — the only test validating the **ValueObservation → recomputeFogShape() → currentFogShape** live update pipeline. It verifies that inserting a new hex after init causes the fog polygon to reactively update (3 → 4 interior rings). This is prefixed with `disabled_` so XCTest skips it.
>
> **Root cause:** The `waitForFogShape` helper wraps `withObservationTracking` inside `withCheckedThrowingContinuation`. For the "wait for *second* observation delivery" scenario, this parks the main thread and starves GRDB's GCD dispatch sources — exactly the deadlock pattern the original WI3 warning predicted.
>
> **Resolution path:** WI5 absorbs un-benching this test by porting the `GRDBObservationTests` cooperative polling pattern (`while` loop + `RunLoop.current.run` + `Task.sleep`) into the `waitForFogShape` helper. See WI5 directive 6.

> [!NOTE]
> **I.3a Fix (WI3a-LIVE-FOG):** During I.3 investigation, a separate live-update starvation bug was identified and fixed. `SpatialStore.liveUpdatePriority` defaulted to `.background`, causing iOS to starve all non-initial `recomputeFogShape()` tasks while the app was in the foreground. Hexes would only appear uncovered after app restart. **Fix:** Changed `liveUpdatePriority` default from `.background` to `.userInitiated` (one-line change in `SpatialStore.swift:30`). A new test `testColdStartFogShapeInitializationWithDefaultPriority` validates the default priority path. See `AGENTS.MD` and `docs/architecture.md` §5.2 for updated rules.

**Task ID:** `WI3-FOG-TESTS`
**Depends on:** Wave I.1 and I.2 (the fixes must be in place to write meaningful assertions).

### Problem Statement

The cold-start fog bug was not caught by the existing test suite because there are no tests covering the `SpatialStore` → `MapView` fog rendering pipeline. Without regression tests, future refactors (e.g., changing task priorities, modifying the `ValueObservation` query, or updating MapLibre) could silently reintroduce the race condition. Furthermore, the test suite itself must be fortified against XCTest Swift Concurrency deadlocks to ensure CI reliability.

### Agent Directives

1. **Test: `SpatialStore` produces a non-nil fog shape on init with existing hexes:**
   * Create a new test file: `DeriveeNative/DeriveeTests/SpatialStoreFogTests.swift` (if not already existing).
   * Set up an **in-memory** `SpatialDatabaseManager` (using the existing `inMemory: Bool` init parameter).
   * Pre-insert 5 hex indices into `explored_hexes` via direct SQL.
   * Initialize a `SpatialStore` with this database manager. Ensure `observationScheduler` is set to `.main` (as the main thread is no longer being parked).
   * **Do NOT use `XCTestExpectation` or `withObservationTracking`.** These freeze the simulator's dispatch sources and cause priority inversions with GRDB in Swift Concurrency.
   * **Use Cooperative Polling:** Create an `async` `while` loop that checks `store.currentFogShape`, then yields the thread with `try await Task.sleep(nanoseconds: 10_000_000)` (10ms) until a timeout (e.g., 4.0s) is reached.
   * Once the shape is resolved, assert it is an `MLNPolygon` with `interiorPolygons` count of exactly 5.
   * **Constraint:** Retain this pure native data assertion. Do NOT replace it with a `swift-snapshot-testing` `.dump` assertion. MapLibre memory blob diffs are too flaky.

2. **Test: Interior ring count matches explored hex count:**
   * Pre-insert 1, 10, and 50 hexes (three separate test cases or a parameterized test).
   * For each, wait for `currentFogShape` and assert `interiorPolygons?.count == expectedCount`.

3. **Test: Newly inserted hex triggers fog shape update:**
   * Initialize `SpatialStore` with 3 pre-existing hexes. Wait for `currentFogShape`.
   * Insert a 4th hex via `SpatialDatabaseManager.insertDiscoveredHex()`.
   * Wait for `currentFogShape` to update (the `interiorPolygons` count should change from 3 to 4).
   * Assert the count is 4.

4. **Test: `recomputeFogShape` produces valid coordinate bounds:**
   * After fog shape computation, inspect the exterior ring coordinates of the resulting `MLNPolygon`.
   * Assert all coordinates fall within the expected 50km bounding box (latitude 40.0–41.5, longitude -74.5–-73.0, with minor jitter tolerance of 0.0001).

5. **Do NOT test MapLibre rendering directly** — that is a snapshot/UI test concern (Phase 3). These tests validate only the data pipeline: DB → `ValueObservation` → `recomputeFogShape()` → `currentFogShape` property.

6. **Do NOT modify any production source files** in this wave. Only add test files.

### Files to Create

* `DeriveeNative/DeriveeTests/SpatialStoreFogTests.swift`

### Verification

1. Run `xcodebuild test` — all new tests pass.
2. Temporarily break the fog pipeline (e.g., comment out `recomputeFogShape()` call) → tests fail. Restore.
3. Ensure existing tests still pass (no regressions).

---


## Wave I.5 — Priority Inversion Regression Tests [Done]

**Task ID:** `WI5-HANG-TESTS`
**Depends on:** Wave I.4 (the async conversions must be in place to write meaningful assertions).

### Problem Statement

Without tests enforcing that database reads are never called synchronously on the main thread, future agents could reintroduce the priority inversion by adding a quick `dbWriter.read` call in a SwiftUI view body or `.onAppear` block.

Additionally, WI3's benched `disabled_testNewlyDiscoveredHexTriggersFogShapeUpdate` test — the only test covering live `ValueObservation` reactivity in the fog pipeline — must be un-benched. The observation delivery path is the more dangerous race surface: the read-side async guards (directives 1–4 below) protect against explicit `dbWriter.read` calls, but they cannot catch priority inversions in GRDB's internal `ValueObservation` dispatch. The benched test is the only gate for that.

### Agent Directives

1. **Test: `isHydrationComplete` does not block the calling thread:**
   * Create a new test file: `DeriveeNative/DeriveeTests/DatabaseQoSTests.swift`.
   * Set up an in-memory `SpatialDatabaseManager`.
   * Call `isHydrationComplete()` and assert it returns via `async`/`await` — i.e., confirm the method signature is `async throws -> Bool`. If the method were synchronous, this test would fail to compile, acting as a compile-time guard.

2. **Test: `fetchStopDetails` does not block the calling thread:**
   * Call `fetchStopDetails(for: "test_stop")` via `await` and assert it returns a valid `StopDetails` (even if fallback data).
   * Confirm the method signature is `async throws -> StopDetails`.

3. **Test: `fetchHeadwayData` does not block the calling thread:**
   * Call `fetchHeadwayData(for: "test_stop")` via `await` and assert it returns a non-empty `[Double]` array.
   * Confirm the method signature is `async throws -> [Double]`.

4. **Test: `fetchNeighborhoodName` does not block the calling thread:**
   * Call `fetchNeighborhoodName(for: "8b2a100d2c9ffff")` via `await` and assert it returns `String?`.
   * Confirm the method signature is `async throws -> String?`.

5. **Test: GRDB Configuration QoS is set:**
   * This is a structural test. Inspect the `SpatialDatabaseManager` to verify that `configuration.qos` is explicitly set. Since `Configuration` is private, the simplest approach is a code-level assertion:
     * Add a computed property to `SpatialDatabaseManager`: `var configuredQoS: DispatchQoS { ... }` that exposes the configured QoS for testing.
     * Assert `configuredQoS == .userInitiated`.
   * **Alternative (if exposing internals is undesirable):** Write a grep-based test or simply include a comment-only assertion in the test file that documents the expectation, paired with a CI grep check.

6. **Un-bench WI3's reactive fog test (Step 0 — do this FIRST):**
   * Rewrite the `waitForFogShape` helper in `SpatialStoreFogTests.swift` to use **cooperative polling** instead of `withObservationTracking` + `withCheckedThrowingContinuation`. The correct pattern already exists in `GRDBObservationTests.swift` (lines 27–34): a `while` loop that checks the state, runs `RunLoop.current.run(mode:before:)` for 10ms, then yields with `try await Task.sleep(nanoseconds: 10_000_000)`.
   * Remove the `disabled_` prefix from `disabled_testNewlyDiscoveredHexTriggersFogShapeUpdate`, re-enabling it.
   * Verify it passes via `xcodebuild test`. If it still hangs even with cooperative polling, convert it to `throw XCTSkip("ValueObservation delivery not testable in sandbox — see WI3 analysis")` so CI handles it safely.
   * This also reconciles `docs/architecture.md` line 108, which claims tests use cooperative polling while the actual `waitForFogShape` helper contradicts that.

7. **Do NOT modify any production source files** in this wave beyond the minimal `configuredQoS` test hook if needed. Only add/modify test files.

### Files to Create

* `DeriveeNative/DeriveeTests/DatabaseQoSTests.swift`

### Files to Modify (minimal)

* `DeriveeNative/Derivee/SpatialDatabaseManager.swift` — only if adding the `configuredQoS` test hook (one computed property).

### Verification

1. Run `xcodebuild test` — all new tests pass.
2. Temporarily change `isHydrationComplete` back to a synchronous signature → test fails to compile. Restore.
3. Temporarily remove `configuration.qos = .userInitiated` → QoS test fails. Restore.
4. Ensure existing tests still pass (no regressions).

---

## Wave I.6 — Fix Ambient Tracking Stop Lifecycle [Complete]

**Task ID:** `WI6-TRACK-STOP`
**Depends on:** Wave N.3 (Ambient Tracking Engine) complete.

### Goal

Fix three cascading bugs that occur when a user toggles Ambient Tracking OFF in Settings:

1. **Dynamic Island / Live Activity persists** — The "Tracking Walk" Live Activity remains in the Dynamic Island and lock screen after the user stops tracking.
2. **Location arrow icon lingers** — After stopping tracking and backgrounding/exiting the app, the iOS status bar still shows the location indicator.
3. **Tracking auto-restarts on relaunch** — When re-opening the app after stopping tracking, the Settings toggle shows Ambient Tracking is ON again.

### Root Causes

1. **Live Activity uses `.default` dismissal policy** (`AmbientTrackingEngine.swift` line ~107). `.default` lets iOS keep the activity visible for up to 4 hours. Must use `.immediate`.
2. **`CLLocationManager.allowsBackgroundLocationUpdates` is set to `true` in `init()` and never reset to `false` on stop.** The `CLBackgroundActivitySession` invalidation is also asynchronous, so iOS can hold onto the location entitlement if the user backgrounds the app during the cleanup window.
3. **`MapView.makeUIView()` unconditionally calls `startTracking()`** (line ~40). There is zero persistence of the user's tracking preference — `isTracking` is a purely in-memory `@Published` property that defaults to `false`. Every app relaunch creates a fresh `AmbientTrackingEngine`, and the map immediately force-starts it.

### Agent Directives

#### 1. Persist tracking state with `@AppStorage`

* Add `@AppStorage("isTrackingEnabled") var isTrackingEnabled = false` to `AmbientTrackingEngine`.
* Default is **`false`** — tracking must be explicitly opted into by the user (required for App Store compliance with background location guidelines).
* The existing in-memory `@Published var isTracking` should reflect the live runtime state (engine is actively running). The persisted `isTrackingEnabled` reflects the **user's intent** (should tracking resume on next launch).
* On `startTracking()`: set `isTrackingEnabled = true`.
* On `stopTracking()`: set `isTrackingEnabled = false`.

#### 2. Create `resumeTrackingIfNeeded()` method

* **Do NOT start tracking inside `AmbientTrackingEngine.init()`.** Triggering hardware side-effects (CoreLocation) inside an initializer is an anti-pattern.
* Add a new method to `AmbientTrackingEngine`:
  ```swift
  func resumeTrackingIfNeeded() {
      guard isTrackingEnabled, !isTracking else { return }
      startTracking()
  }
  ```
* Call `resumeTrackingIfNeeded()` from `MapView.makeUIView()` instead of the current unconditional `startTracking()` call.

#### 3. Make `stopTracking()` async

* Change the signature to `func stopTracking() async`.
* The synchronous fire-and-forget `Task { await activity.end(...) }` pattern creates a race condition: if the user taps stop and immediately backgrounds the app, iOS suspends threads before the detached cleanup completes, leaving the Live Activity orphaned.
* Implement in this exact order:
  ```swift
  func stopTracking() async {
      // 1. Cancel the update stream and await its completion
      updatesTask?.cancel()
      _ = await updatesTask?.result
      updatesTask = nil

      // 2. Invalidate the background session
      backgroundSession?.invalidate()
      backgroundSession = nil

      // 3. Await the Live Activity end with immediate dismissal
      if let activity = currentActivity {
          let state = TrackingAttributes.ContentState(
              hexesCleared: sessionHexCount,
              activeNeighborhood: nil
          )
          await activity.end(
              ActivityContent(state: state, staleDate: nil),
              dismissalPolicy: .immediate
          )
      }
      currentActivity = nil

      // 4. Clean up Location Manager
      locationManager.allowsBackgroundLocationUpdates = false

      // 5. Reset stale state
      lastLocation = nil
      lastSavedHex = nil

      // 6. Update persisted + runtime state
      isTrackingEnabled = false
      isTracking = false
  }
  ```

#### 4. Move `allowsBackgroundLocationUpdates` to `startTracking()`

* Remove `locationManager.allowsBackgroundLocationUpdates = true` from `init()`.
* Add it to `startTracking()`, right before creating the `CLBackgroundActivitySession`.
* This ensures the background flag is only active while tracking is actually running.

#### 5. Update `SettingsView` caller

* The "Pause Tracking" destructive button action must wrap the call in a `Task`:
  ```swift
  Button("Pause Tracking", role: .destructive) {
      Task {
          await trackingEngine.stopTracking()
      }
  }
  ```

#### 6. Wire up onboarding opt-in (if not already present)

* When the user completes onboarding (`OnboardingView`), present a "Start Exploring" button.
* Tapping it sets `isTrackingEnabled = true`, calls `startTracking()`, and triggers the iOS location permission prompt.
* This makes tracking a conscious, user-initiated action — required for App Store review.

### Files to Modify

* `DeriveeNative/Derivee/AmbientTrackingEngine.swift` — Add `@AppStorage`, `resumeTrackingIfNeeded()`, make `stopTracking()` async, fix dismissal policy, move `allowsBackgroundLocationUpdates`, reset stale state.
* `DeriveeNative/Derivee/MapView.swift` — Replace unconditional `startTracking()` with `resumeTrackingIfNeeded()`.
* `DeriveeNative/Derivee/SettingsView.swift` — Wrap `stopTracking()` call in `Task { await ... }`.
* `DeriveeNative/Derivee/OnboardingView.swift` — Add explicit "Start Exploring" opt-in that enables tracking.

### Verification

1. **Toggle off → Dynamic Island disappears within 1 second.**
2. **Toggle off → exit app → no location arrow in status bar.**
3. **Toggle off → exit app → reopen → Settings shows tracking OFF.**
4. **Toggle on → exit app → reopen → tracking resumes automatically.**
5. **Fresh install → first launch → tracking does NOT auto-start.** User must complete onboarding and tap "Start Exploring."
6. **Existing unit tests still pass** (`xcodebuild test`).
7. **`TrackingEngineTests` updated** to cover `resumeTrackingIfNeeded()` logic (starts only when persisted preference is true).
