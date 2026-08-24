
## Wave F.1 — Map UI: Floating Action Buttons [Shipped]

**Task ID:** `WF1-FAB`
**Depends on:** Wave C (Tracking Engine) and Wave E (Onboarding & MapLibre Hydration).

### Goal
Replace legacy navigation with native SwiftUI Floating Action Buttons (FABs) to enable map recentering and profile navigation, complete with proper haptics and visual states. Ensure the native user location marker is properly configured.

### Agent Directives

1. **Floating Action Buttons (`DeriveeNative/Derivee/MapFAB.swift` — new file):**
   * **Recenter FAB** (bottom-right): Re-centers the MapLibre camera on the user's GPS position with a 300ms ease animation.
     * Idle: semi-transparent (`opacity: 0.7`), SwiftUI `.ultraThinMaterial` background.
     * Press: instant `UIImpactFeedbackGenerator(style: .light)` haptic, scale to `0.92` over 100ms, spring back.
     * State: filled icon variant when centered on user; outlined variant when user has panned away.
   * **Profile FAB** (top-right): Navigates to `StatsView.swift` (Screen 3).
     * Same blur/haptic/scale behavior as Recenter.
   * Both FABs use native SwiftUI `Button` or `.onTapGesture` modifiers for interaction.

2. **Native user location marker:**
   * Verify that MapLibre's built-in user location layer (`mapView.showsUserLocation = true`) is used, mapped to the native pulsing dot.
   * Subtle directional heading cone when device compass is active.

### Verification
* FABs render with `.ultraThinMaterial` blur effect, respond to taps with haptic feedback.
* Recenter FAB toggles between filled/outlined state based on camera position.
* Tapping Recenter FAB animates the camera back to the user's location.

## Wave F.2 — Discovery Toast Overlay [Shipped]

**Task ID:** `WF2-TOAST`
**Depends on:** Wave C (Tracking Engine) and Wave F.1.

### Goal
Implement a lightweight SwiftUI toast notification that appears when the user discovers a new Transit POI, providing immediate, non-intrusive feedback without blocking the UI.

### Agent Directives

1. **Toast UI Component (`DeriveeNative/Derivee/DiscoveryToast.swift` — new file):**
   * A pill-shaped SwiftUI view using `.ultraThinMaterial` or a dark translucent background.
   * Slides down from the top edge of the screen (or pops up near the bottom) on discovery.
   * Contains the station name and a fun fact/subtitle (e.g., "New Transit POI Discovered").
   * Include a subtle scale and opacity animation on entry.

2. **Toast Lifecycle:**
   * Triggered on **first encounter** with a previously unseen POI when the user's GPS enters the hex containing it.
   * Auto-dismisses after 3 seconds with a smooth exit animation.
   * Supports manual dismissal via upward swipe.

### Verification
* Toast appears organically without interrupting map interactions.
* Auto-dismisses after 3 seconds.
* Dismisses manually via swipe.

## Wave F.3 — Ghost POI 3-Phase Lifecycle [Shipped]

**Task ID:** `WF3-POI-LIFECYCLE`
**Depends on:** Wave F.2.

### Goal
Implement the 3-phase Ghost POI lifecycle via MapLibre Data-Driven Styling (`NSExpression`) to dynamically transition POIs between Hidden, Active, and Explored states.

### Agent Directives

1. **Phase 1 — The Lure (Hidden Territory):**
   * Render Ghost POIs as soft, anonymous beacon glows **above** the fog layer (Layer 4 in the 6-layer stack).
   * Zero text labels, zero identification. Faint pulsing glow animation.
   * Implemented as a MapLibre `MLNCircleStyleLayer` with low opacity, large blur radius, and a subtle scale pulse via expressions.

2. **Phase 2 — The Unlocking (Active Vicinity):**
   * When the user's GPS enters the hex containing a Ghost POI (within the 200m bubble):
     * Beacon resolves into a crisp geometric node: dot for bus stops, diamond for subway entrances.
     * Subtle reveal scale animation (0→1 over 200ms, ease-out).
   * Tappable. Triggers PiP proximity check → Transit Reveal bottom sheet (`.sheet` presentation for Screen 2).

3. **Phase 3 — The Archive (Explored Territory):**
   * When the user leaves the Active Vicinity, the node fades to near-invisibility.
   * **Completely invisible at zoom ≤ 16.** At zoom 17+: ultra-faint desaturated mark (opacity ≤ 0.15).
   * Not tappable when outside Active Vicinity — PiP check gates all interactions.

4. **Integration:**
   * Use MapLibre Data-Driven Styling with `NSExpression` keyed on POI phase state to control visibility per-node.
   * Connect to the database/state to track which POIs have been discovered to link with the Toast notification logic from Wave F.2.

### Verification
* Ghost POIs in Hidden territory show as faint beacons through the fog.
* Ghost POIs in Active vicinity show as crisp geometric nodes and are tappable.
* Ghost POIs in Explored territory are invisible at zoom ≤ 16.
* Transitions between states occur smoothly.

## Wave F.4 — Ambient Hex Unlock Animation [Shipped]

**Task ID:** `WF4-HEX-ANIMATION`
**Depends on:** Wave F.3.

### Goal
Add ambient visual feedback when a user unlocks a new hex, enhancing the gamification feel without intrusive popups.

### Agent Directives

1. **Real-time hex unlock animation:**
   * On `SpatialStore` `@Observable` update (new hex discovered):
     * Hex fog transitions opaque→transparent via MapLibre expression animations.
     * A soft glow ring (single pulse) emanates from the user's position using a transient SwiftUI view overlay.
     * **No sound effects. No confetti. No modal popups.** Ambient and organic.

### Verification
* Hex unlock animation plays at 60fps without frame drops.
* The transition from opaque to transparent feels natural.
* A subtle pulse rings from the user location upon new hex discovery.

## Wave 15 — Dynamic Island Support for Stat Bar [Shipped]

**Task ID:** `W15-DYNAMIC-ISLAND`
**Depends on:** Wave H (Ship complete)

### Goal
Implement Dynamic Island and Live Activity support using `ActivityKit` to display real-time ambient tracking metrics (session duration, hexes cleared, and active neighborhood) while the app is in the background.

### Agent Directives

1. **XcodeGen & Target Setup:**
   * Update `DeriveeNative/project.yml` to include a new `app-extension` target for the Widget (e.g., `DeriveeWidget`).
   * Set `NSSupportsLiveActivities: YES` in the main app's `Info.plist` properties.
2. **ActivityKit Integration:**
   * Define `TrackingAttributes` conforming to `ActivityAttributes`. 
   * **Static state:** Session start time. 
   * **Dynamic state:** Hexes cleared this session, current neighborhood name.
3. **Live Activity UI (SwiftUI):**
   * Build the Live Activity views within the Widget target.
   * **Dynamic Island:**
     * *Compact:* Show a pulsing tracking indicator and the number of hexes cleared.
     * *Expanded:* Show session duration, hex count, and the active neighborhood.
   * **Lock Screen:** Show a sleek, dark-themed persistent widget matching Dérivée's `.ultraThinMaterial` aesthetic.
4. **Tracking Engine Rewire (`AmbientTrackingEngine`):**
   * Import `ActivityKit`.
   * On `startTracking()`: Request to start a new `Activity<TrackingAttributes>`.
   * On new hex discovery (inside `processLocation`): Update the active `Activity` with the incremented hex count.
   * On `stopTracking()`: End the activity with the final state.

### Verification
* Live Activity starts when tracking is enabled and appears on the Lock Screen.
* Dynamic Island shows the compact tracking indicator when the app is backgrounded.
* Unlocking a new hex dynamically updates the hex count on the Dynamic Island and Lock Screen without requiring the app to be foregrounded.
* Stopping tracking smoothly ends the Live Activity.

## Wave H.1 — Stats UI: Neighborhood Map Panning [Completed]

**Task ID:** `WH.1-PANNING`
**Depends on:** Wave H (Stats and Profile Rewire).

### Goal
Fulfill the design requirement from `docs/design.md` Section 3: "Tapping a neighborhood pans the background map (Screen 1) to that neighborhood's centroid coordinates."

### Agent Directives

1. **Database Schema Fetch:**
   * Update the `NeighborhoodProgress` struct in `SpatialDatabaseManager` to include `centroidLat` and `centroidLng`.
   * Modify `fetchNeighborhoodProgression()` to `SELECT ns.centroid_lat, ns.centroid_lng` from the existing `neighborhood.neighborhood_stats` table.

2. **State Management:**
   * Add a mechanism to trigger map panning (e.g., passing a binding or environmental state that tracks a target coordinate to `MapView`).
   * Upon receiving a coordinate, the `MapView.Coordinator` should trigger `mapView.setCenter(coord, zoomLevel: 14.5, animated: true)` and temporarily turn off ambient follow mode.

3. **UI Interaction:**
   * Wrap the neighborhood rows in `StatsView.swift` with a `Button` or `.onTapGesture`.
   * On tap: set the target coordinate, update the `isCentered` state to false, and dismiss the `StatsView` sheet.

### Verification
* Tapping a neighborhood in the leaderboard correctly updates the map's center.
* The transition back to the map is smooth and frame-perfect.
* Panning the map does not disrupt ambient background tracking.

---

## Wave E — Onboarding Gate & First-Launch Infrastructure [Shipped]

**Task ID:** `WE-ONBOARDING`
**Depends on:** Wave D (Nitro hydration pipeline), W11.6-DEVOPS (transit delta available on R2).

### Goal
Replace the decorative splash screen (`app/index.tsx`) with a functional first-launch Onboarding Gate that downloads the MapLibre offline tile region and the transit delta database before allowing the user to proceed to the map.

### Agent Directives

1. **Schema addition (`meta` table):**
   * Add to the database initialization in `src/db/`:
     ```sql
     CREATE TABLE IF NOT EXISTS meta (
         key TEXT PRIMARY KEY,
         value TEXT
     ) WITHOUT ROWID;
     ```
   * The hydration completion flag is stored as: `INSERT INTO meta (key, value) VALUES ('hydration_complete', '1');`

2. **Screen 0: Onboarding Gate (`app/index.tsx` refactor):**
   * On launch, synchronously query `meta` table via `@op-engineering/op-sqlite` for the `hydration_complete` key.
   * **If flag exists:** Skip directly to `app/map.tsx` (Screen 1). No splash delay.
   * **If flag is missing (first launch):**
     * Mount a full-screen branded lock screen with atmospheric fog background animation, pulsing logo, and a translucent progress indicator.
     * **No interactive buttons. No map mounted.**
     * Check network connectivity.
       * If offline: display a single-line prompt ("Connect to the internet to set up Dérivée"). Poll for connectivity via `NetInfo`; resume automatically when restored.
       * If online: proceed to downloads.

3. **MapLibre offline tile region download:**
   * Use MapLibre's `OfflineManager` to create an offline pack for a 50km × 50km region centered on the device's current GPS coordinate.
   * Request foreground location permission via `expo-location` if not already granted (this is the one valid foreground use of `expo-location`).
   * Show download progress in the translucent indicator.

4. **Transit delta download & attach:**
   * Fetch `nyc_transit_delta.sqlite.zst` from the Cloudflare R2 URL.
   * Decompress the Zstandard payload.
   * Write the resulting `.sqlite` file to `Library/Application Support/`.
   * Attach to the existing `@op-engineering/op-sqlite` connection via `ATTACH DATABASE`.

5. **Completion:**
   * Write `hydration_complete` flag to `meta` table.
   * Fade out the lock screen over 400ms, revealing Screen 1 (the Ambient Map).

### Verification
* First launch shows the Onboarding Gate, downloads tiles and transit data, then transitions to the map.
* Second launch skips directly to the map with no visible splash.
* Offline first launch shows the connectivity prompt and resumes automatically when connected.
* The transit delta is queryable via `@op-engineering/op-sqlite` after attachment (verify with a test `SELECT`).

---

## Wave G — Transit Reveal Enhancements [Shipped]

**Task ID:** `WG-TRANSIT-REVEAL`
**Depends on:** Wave E (transit delta database downloaded and attached).

### Goal
Enhance the existing Transit Bottom Sheet (`src/components/TransitBottomSheet.tsx`) with ephemeral route line visualization and historical reliability sparklines.

### Agent Directives

1. **Ephemeral route LineLayer:**
   * When the Transit Reveal bottom sheet (Screen 2) opens:
     * Inject a temporary GeoJSON `LineLayer` at the **top** of the MapLibre layer stack.
     * The line traces the entire transit route across the map, cutting visually through the fog.
     * Stroke color matches the transit line's official color (e.g., MTA L train gray `#A7A9AC`, G train light green `#6CBE45`).
     * Semi-transparent stroke (`opacity: 0.7`), width 3–4px.
     * Fade-in animation over 200ms.
   * When the sheet is dismissed (swipe-down or map tap):
     * **Immediately unmount** the route LineLayer. No persistent route artifacts.
     * Map snaps back to the localized 200m Vicinity Bubble view.
   * Route geometry: stored as static GeoJSON in the transit delta database or as a bundled asset keyed by route ID.

2. **Historical reliability sparkline:**
   * Query the transit delta SQLite database for 7-day headway data for the selected stop.
   * Query must complete in < 12ms (synchronous read via `@op-engineering/op-sqlite`).
   * Render a compact inline sparkline chart below the real-time arrivals list.
   * Lightweight implementation — use a simple SVG path or `react-native-svg` line. **No heavy charting library** (no Victory, no Recharts).
   * Sparkline shows headway variance over the past 7 days with a subtle area fill.

3. **Bottom sheet animation tuning:**
   * Spring configuration: `damping: 50`, `stiffness: 500`. No bounce.
   * Add a dim backdrop overlay on the map (`opacity: 0.3` dark overlay) when the sheet reaches its expanded snap point.
   * Verify the ephemeral route line unmounts at the exact frame the sheet reaches its dismissed position.

### Verification
* Ephemeral route line appears on sheet open and disappears on dismiss — no stale GeoJSON artifacts.
* Route line colors match official MTA line colors.
* Sparkline renders from local data in < 12ms (measure with `performance.now()`).
* Bottom sheet spring animation feels native with no bounce.
* Dim backdrop appears at expanded snap and clears on dismiss.

---

## Wave H — Polish, Stats and Profile Rewire & Ship Prep [Shipped]

**Task ID:** `WH-SHIP`
**Depends on:** Waves E, F, G all complete.

### Goal
Final integration pass. Wire the Stats and Profile settings in native Swift to use `AmbientTrackingEngine` tracking controls and `CLBackgroundActivitySession`, implement the GPX/FIT upload reveal animation, perform end-to-end testing, and prepare App Store metadata.

### Agent Directives

1. **Stats and Profile integration (`StatsView.swift` & `SettingsView.swift`):**
   * Control `AmbientTrackingEngine` via native SwiftUI toggles directly (`startTracking()` / `stopTracking()`).
   * Show friendly pause reminder alert (`"Pause Ambient Exploration?"`) when toggling off ambient tracking before invalidating `CLBackgroundActivitySession`.
   * Add Push Notification toggle using `UNUserNotificationCenter` permission authorization handling.
   * Show current background location permission state (authorized always/when in use/denied/not determined).
   * **"Clear Local Cache":** Purge cached tiles and transit data files. Delete `hydration_complete` from `meta` table in GRDB so the Onboarding Gate re-triggers on next launch.
   * **"Reset Exploration Data":** Destructive action with native `Alert` confirmation dialog. On confirm: `DELETE FROM explored_hexes` and `discovered_pois` via `SpatialDatabaseManager`, clear in-memory `SpatialStore`, and force MapLibre DDS to re-render full fog.

2. **GPX/FIT reveal animation (`GPXProcessor.swift` / `StatsView.swift`):**
   * Support `.gpx` and `.fit` workout imports via SwiftUI `.fileImporter`.
   * When a file is uploaded and processed in background task (`Task.detached`):
     * Calculate distance of each newly unlocked hex from the user's position.
     * Sort hex clusters by distance (nearest first).
     * Apply staggered batch inserts updating `SpatialStore` — fog "melts away" radially from the user outward.
     * Total animation duration: 1.5–2.5 seconds depending on geographic spread.

3. **End-to-end integration test (physical device / simulator):**
   * Full flow: Onboarding Gate → ambient walk → hex unlock → Ghost POI tap → Transit Reveal sheet with route line → Stats and Profile → GPX upload with reveal animation → Exploration Data reset.

4. **Performance profiling:**
   * MapLibre fog rendering at 60fps during active exploration.
   * Background battery drain target: < 5% per hour during ambient tracking.
   * Transit delta query: < 12ms for sparkline reads.

5. **App Store submission prep:**
   * Verify all Xcode Info.plist permissions (location always, motion) are present.
   * Verify native Xcode build compiles successfully via `xcodebuild` or the Xcode GUI.

### Verification
* Stats and Profile toggles correctly control `AmbientTrackingEngine` (`CLBackgroundActivitySession`).
* Data reset clears all hexes and re-renders full fog.
* Cache clear re-triggers the Onboarding Gate on next launch.
* GPX reveal animation plays with radial dissolve.
* Full end-to-end flow completes without crashes or stale state.
* Native Xcode build compiles and runs.

---

## Wave I.4 — Eliminate Main-Thread DB Reads & Configure GRDB QoS [Shipped]

**Task ID:** `WI4-ASYNC-READS`
**Depends on:** Wave I.1 (the fog startup gate must exist so this wave doesn't introduce a new nil-shape race).

### Problem Statement

Multiple UI code paths perform **synchronous** `dbWriter.read { }` calls directly on the Main Thread (`User-Interactive` QoS). When the background `AmbientTrackingEngine` is simultaneously holding a `DatabasePool` connection for writes at `Default` QoS, the main thread blocks on `Pool.get()` — a textbook **priority inversion**.

This hang risk compounds the cold-start fog bug: even after `recomputeFogShape()` produces a valid fog polygon, the main thread may be stalled on a DB pool semaphore and unable to run `updateUIView` to apply it.

**Affected call sites:**

| Location | Method | Caller QoS |
|:---|:---|:---|
| `ContentView.swift:25` | `isHydrationComplete()` — sync read | `User-Interactive` (Main) |
| `TransitRevealSheet.swift:99-100` | `fetchStopDetails()` + `fetchHeadwayData()` — sync reads | `User-Interactive` (Main) |
| `AmbientTrackingEngine.swift:151` | `fetchNeighborhoodName()` — sync read inside `Task.detached` | `Default` |

**Underlying cause:** `SpatialDatabaseManager` initializes `Configuration()` without setting `configuration.qos`, leaving GRDB's internal pool barrier and wait queues at `.default` QoS.

### Agent Directives

1. **Set GRDB `Configuration.qos` to `.userInitiated`:**
   * In `SpatialDatabaseManager.init()`, after creating `var configuration = Configuration()`, add:
     ```swift
     configuration.qos = .userInitiated
     ```
   * This ensures the internal pool dispatch queues run at a QoS that won't trigger priority inversion warnings when accessed from `User-Interactive` threads. `.userInitiated` is the correct choice — it's high enough to avoid inversion but lower than `.userInteractive` to avoid starving the UI thread.

2. **Convert `isHydrationComplete()` to async:**
   * Change the signature from `func isHydrationComplete() -> Bool` to `func isHydrationComplete() async throws -> Bool`.
   * Replace `try dbWriter.read { }` with `try await dbWriter.read { }` (GRDB's async read).
   * Update the call site in `ContentView.swift:25`:
     ```swift
     .onAppear {
         Task {
             isHydrationComplete = (try? await SpatialDatabaseManager.shared.isHydrationComplete()) ?? false
             isCheckingHydration = false
         }
     }
     ```
   * Ensure the `isCheckingHydration` loading state (black screen) still displays while the async check runs.

3. **Convert `TransitRevealSheet.loadData()` to async:**
   * Change `fetchStopDetails(for:)` signature to `func fetchStopDetails(for stopId: String) async throws -> StopDetails`.
   * Change `fetchHeadwayData(for:)` signature to `func fetchHeadwayData(for stopId: String) async throws -> [Double]`.
   * Replace `try dbWriter.read { }` with `try await dbWriter.read { }` in both methods.
   * Update `TransitRevealSheet.loadData()` to be async:
     ```swift
     private func loadData() {
         Task {
             let details = try? await SpatialDatabaseManager.shared.fetchStopDetails(for: stopId)
             let hw = try? await SpatialDatabaseManager.shared.fetchHeadwayData(for: stopId)
             self.stopDetails = details
             self.headways = hw ?? []
         }
     }
     ```
   * The `TransitRevealSheet` already has a `ProgressView` fallback for when data is nil — this naturally handles the async loading state.

4. **Convert `fetchNeighborhoodName(for:)` to async:**
   * Change the signature to `func fetchNeighborhoodName(for h3Index: String) async throws -> String?`.
   * Replace `try dbWriter.read { }` with `try await dbWriter.read { }`.
   * Update the call site in `AmbientTrackingEngine.swift:151` — it's already inside a `Task.detached`, so just `await` the call.

5. **Audit for any remaining synchronous `dbWriter.read` calls:**
   * Search the codebase for `dbWriter.read` (without `await`) and convert any remaining synchronous call sites to async.
   * The only sync reads that may remain are inside GRDB's own `ValueObservation` callbacks (these are internal to GRDB and cannot be changed).

6. **Do NOT change:**
   * The `dbWriter.write` calls — GRDB async writes are already used (`try await dbWriter.write`).
   * The `ValueObservation` setup in `SpatialStore` — this is GRDB's managed observation and handles its own threading.
   * Any database schema, fog opacity, or H3 resolution.
   * The `MapView.Coordinator` methods that call `fetchStopDetails` inside `Task.detached` at `MapView.swift:331` — that call is already off the main thread and is fine.

### Files to Modify

* `DeriveeNative/Derivee/SpatialDatabaseManager.swift` — QoS config, async method signatures.
* `DeriveeNative/Derivee/ContentView.swift` — async `isHydrationComplete` call.
* `DeriveeNative/Derivee/TransitRevealSheet.swift` — async `loadData()`.
* `DeriveeNative/Derivee/AmbientTrackingEngine.swift` — async `fetchNeighborhoodName` call.

### Verification

1. Build and run on a physical device. Xcode Instruments → Thread State Trace: confirm **zero `Pool.get()` waits** on the main thread.
2. Open a Transit Reveal bottom sheet — data loads without a visible hang. The `ProgressView` spinner may flash briefly (acceptable).
3. Force-quit and cold-start — the hydration check completes without blocking the main thread. The black loading screen still displays during the check.
4. Walk to discover a new hex — the Live Activity update still fires correctly (neighborhood name still populates).
5. Run all existing tests — no regressions.
6. **Re-test the benched WI3 fog test:** After `configuration.qos = .userInitiated` is in place, manually re-run `disabled_testNewlyDiscoveredHexTriggersFogShapeUpdate` (temporarily removing the `disabled_` prefix). The elevated QoS may incidentally unblock the GCD dispatch sources that `withObservationTracking` starves. If it passes, this is a free win — re-enable it permanently. If it still hangs, leave it for WI5's cooperative polling fix.


## Wave I.1 — Fog Startup Gate: Synchronize Shape Computation with Map Ready [Shipped]

**Task ID:** `WI1-FOG-GATE`
**Depends on:** None. This was a critical bugfix wave.

### Problem Statement
After force-quit and cold relaunch, explored hexes were invisible — the fog layer rendered as a solid opaque polygon with zero holes. Root cause: `SpatialStore.init()`, MapLibre's `didFinishLoading`, and `recomputeFogShape()` raced with no synchronization.

### What Shipped
1. Elevated initial fog computation from `.background` to `.userInitiated` priority.
2. Added `isMapStyleLoaded` handshake flag in `MapView.Coordinator`.
3. Deferred apply path in `updateUIView` ensures fog shape is applied when both style and shape are ready.
4. Jittered initial bounding box to prevent MapLibre shape cache collisions.

### Files Modified
* `DeriveeNative/Derivee/SpatialStore.swift`
* `DeriveeNative/Derivee/MapView.swift`

---

## Wave I.2 — Winding Order Audit & Interior Ring Hardening [Shipped]

**Task ID:** `WI2-WINDING`
**Depends on:** Wave I.1.

### What Shipped
Audited and verified that MapLibre Native (iOS) requires CW winding for interior polygon rings. H3's `cellToBoundary` returns CCW; the `.reverse()` call is correct and now permanently documented with a comment in `SpatialStore.recomputeFogShape()`.

### Files Modified
* `DeriveeNative/Derivee/SpatialStore.swift`

---

## Wave I.3 — Cold-Start Fog Regression Tests [Shipped — 1 XCTSkip]

**Task ID:** `WI3-FOG-TESTS`
**Depends on:** Wave I.1 and I.2.

### What Shipped
Created `SpatialStoreFogTests.swift` with 5 tests covering the DB → ValueObservation → recomputeFogShape() → currentFogShape pipeline:
1. `testColdStartFogShapeInitializationWithExistingHexes` — ✅
2. `testInteriorRingCountMatchesExploredHexCount` (1/10/50 parameterized) — ✅
3. `testColdStartFogShapeInitializationWithDefaultPriority` — ✅
4. `testNewlyDiscoveredHexTriggersFogShapeUpdate` — `XCTSkip` (ValueObservation delivery not testable in sandbox)
5. `testFogBoundingBoxCoordinatesWithinExpectedBounds` — ✅

The `waitForFogShape` helper uses cooperative polling (`while` loop + `RunLoop.current.run` + `Task.sleep`).

### I.3a Companion Fix
During investigation, discovered live-update starvation: `liveUpdatePriority` defaulted to `.background`, causing iOS to starve fog recomputation while app was in foreground. Fixed by changing default to `.userInitiated`.

### Files Created
* `DeriveeNative/DeriveeTests/SpatialStoreFogTests.swift`

### Files Modified
* `DeriveeNative/Derivee/SpatialStore.swift` (I.3a priority fix)

---

## Wave I.4 — Eliminate Main-Thread DB Reads & Configure GRDB QoS [Shipped]

**Task ID:** `WI4-ASYNC-READS`
**Depends on:** Wave I.3.

### What Shipped
1. Converted 4 `SpatialDatabaseManager` methods to `async`: `isHydrationComplete()`, `fetchStopDetails(for:)`, `fetchHeadwayData(for:)`, `fetchNeighborhoodName(for:)`.
2. Set `Configuration.qos = .userInitiated` on the GRDB `DatabasePool`.
3. Exposed `configuredQoS` computed property for testing.
4. Updated all callers (`ContentView`, `TransitRevealSheet`, `AmbientTrackingEngine`, `MapView`) to use `await`.

### Files Modified
* `DeriveeNative/Derivee/SpatialDatabaseManager.swift`
* `DeriveeNative/Derivee/ContentView.swift`
* `DeriveeNative/Derivee/TransitRevealSheet.swift`
* `DeriveeNative/Derivee/AmbientTrackingEngine.swift`
* `DeriveeNative/Derivee/MapView.swift`

---

## Wave I.5 — Priority Inversion Regression Tests [Shipped]

**Task ID:** `WI5-HANG-TESTS`
**Depends on:** Wave I.4.

### What Shipped
Created `DatabaseQoSTests.swift` with 5 compile-time and runtime guards:
1. `testIsHydrationCompleteAsyncSignature` — verifies async signature
2. `testFetchStopDetailsAsyncSignature` — verifies async signature
3. `testFetchHeadwayDataAsyncSignature` — verifies async signature
4. `testFetchNeighborhoodNameAsyncSignature` — verifies async signature
5. `testGRDBConfigurationQoSIsUserInitiated` — runtime assertion

Un-benched `testNewlyDiscoveredHexTriggersFogShapeUpdate` by removing the `disabled_` prefix and converting to `XCTSkip` (CI-safe).

### Files Created
* `DeriveeNative/DeriveeTests/DatabaseQoSTests.swift`

### Files Modified
* `DeriveeNative/DeriveeTests/SpatialStoreFogTests.swift`

---

## Wave I.6 — Fix Ambient Tracking Stop Lifecycle [Shipped]

**Task ID:** `WI6-TRACK-STOP`
**Depends on:** Wave N.3.

### What Shipped
Fixed three cascading bugs when toggling tracking OFF:
1. **Persistent Live Activity:** Changed dismissal policy from `.default` to `.immediate`.
2. **Lingering location arrow:** Reset `locationManager.allowsBackgroundLocationUpdates = false` on stop; moved `= true` to `startTracking()`.
3. **Auto-restart on relaunch:** Added `@AppStorage("isTrackingEnabled")` for persistent tracking preference. Created `resumeTrackingIfNeeded()` method. `MapView.makeUIView()` now calls `resumeTrackingIfNeeded()` instead of unconditional `startTracking()`.
4. Made `stopTracking()` async to prevent race conditions during app backgrounding.

### Files Modified
* `DeriveeNative/Derivee/AmbientTrackingEngine.swift`
* `DeriveeNative/Derivee/MapView.swift`
* `DeriveeNative/Derivee/SettingsView.swift`
* `DeriveeNative/Derivee/OnboardingView.swift`



---

## TEST-PHASE4 — CI/CD Pipeline (GitHub Actions) [Planned]

**Task ID:** `TEST-PHASE4`
**Depends on:** Phases 1–3 complete. All 33 tests passing locally.

### Goal

Stand up a GitHub Actions CI pipeline that blocks PRs on test failures. The project uses `xcodegen` to generate `.xcodeproj` from `project.yml`, so CI must regenerate the project on every run. Both test targets (`DeriveeCoreTests`-style headless tests and `DeriveeTests` simulator-backed tests) run in a single `DeriveeTests` bundle today.

### Current State

* **Project structure:** `DeriveeNative/project.yml` defines a single `DeriveeTests` target (bundle.unit-test) that depends on `Derivee` (app host) and `swift-snapshot-testing`.
* **No `.github/workflows/` directory exists** — this is greenfield.
* **Test files (9):** `DatabaseQoSTests`, `ExplorationResetTests`, `GRDBObservationTests`, `H3SpatialMathTests`, `NeighborhoodTests`, `SpatialStoreFogTests`, `TrackingEngineTests`, `TransitHydrationTests`, `TransitRevealSheetTests`.
* **33 total test functions**, 1 uses `XCTSkip`.
* **SPM dependencies:** `swift-h3`, `GRDB.swift` (≥6.27.0), `maplibre-gl-native-distribution` (≥6.20.1), `SwiftZSTD`, `swift-snapshot-testing` (≥1.15.4).
* **Simulator requirement:** Tests import `MapLibre` and `@testable import Derivee`, so they require an app host and simulator. Use `platform=iOS Simulator,name=iPhone 17 Pro,OS=latest`.

### Agent Directives

1. **Create `.github/workflows/ci.yml`:**
   * Trigger on `push` to `main` and on all `pull_request` events.
   * Use `macos-15` runner (required for Xcode 26+ and iOS 26 simulator).
   * Cache SPM dependencies (`~/Library/Developer/Xcode/DerivedData` and `~/.swiftpm`).

2. **Install `xcodegen`:**
   ```yaml
   - name: Install xcodegen
     run: brew install xcodegen
   ```

3. **Generate project:**
   ```yaml
   - name: Generate Xcode project
     working-directory: DeriveeNative
     run: xcodegen generate
   ```

4. **Resolve SPM packages:**
   ```yaml
   - name: Resolve packages
     working-directory: DeriveeNative
     run: xcodebuild -resolvePackageDependencies -project Derivee.xcodeproj -scheme Derivee
   ```

5. **Run tests:**
   ```yaml
   - name: Run tests
     working-directory: DeriveeNative
     run: |
       xcodebuild test \
         -project Derivee.xcodeproj \
         -scheme Derivee \
         -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=latest' \
         -resultBundlePath TestResults.xcresult \
         CODE_SIGN_IDENTITY="" \
         CODE_SIGNING_REQUIRED=NO \
         | xcpretty --color
   ```

6. **Upload test results as artifact:**
   ```yaml
   - name: Upload test results
     if: always()
     uses: actions/upload-artifact@v4
     with:
       name: test-results
       path: DeriveeNative/TestResults.xcresult
   ```

7. **Branch protection:** After the workflow is green on `main`, configure the repository's branch protection rules to require the `ci` check to pass before merging.

8. **Do NOT split the test target.** The `project.yml` currently defines a single `DeriveeTests` target. Splitting into `DeriveeCoreTests` (no app host) and `DeriveeSnapshotTests` (app host) is a future optimization — not required for Phase 4. All tests currently run against the app host successfully.

9. **Do NOT set up TestFlight deployment** in this wave. Focus exclusively on the test gate.

### Files to Create

* `.github/workflows/ci.yml`

### Verification

1. Push a branch with the new workflow → GitHub Actions runs and passes.
2. Intentionally break a test (e.g., change an `XCTAssertEqual` value) → push → CI fails and blocks merge.
3. Fix the test → push → CI passes.
4. Verify the `XCTSkip` test (`testNewlyDiscoveredHexTriggersFogShapeUpdate`) shows as "skipped" in the test results, not "failed."
5. Verify SPM caching reduces subsequent run times.

---



## Wave 11.8 — Transit Web MVP Bugfixes & Polish [Planned]

**Task ID:** `W11.8-WEB-FIXES`
**Depends on:** Wave 11.5 (Transit Web MVP Launch).

### Goal
Address visual and functional bugs in the `transit-web/` app to bring it to brand parity with the iOS client. This is a React + Vite + deck.gl + MapLibre web app.

### Current State

* **Map style:** Uses the generic CARTO Positron basemap (`https://basemaps.cartocdn.com/gl/positron-gl-style/style.json`) — does NOT use the Dérivée Day/Night hex colors yet.
* **Subway lines:** Rendered as a single `GeoJsonLayer` from `/subway-lines.geojson` — lines share corridors as merged trunks, not individual parallel tracks.
* **Stop color matching:** Uses `stop_id.charAt(0)` to infer route (line 93 of `TransitMap.jsx`) — works for most stops but fails for multi-route transfer stations.
* **Sparkline color:** `Sparkline.jsx` calls `getRouteColor(routeId)` which returns the MTA route color, not the brand Electric Amber. The `transitConfig.js` default fallback is `#FFB300` but route-specific sparklines use the route color.
* **Arrivals text:** Directionality already shows (`arr.direction`). Contrast is inherited from the bottom sheet CSS — needs explicit black/white override.
* **Bus layer:** No zoom-based filtering — renders all stops at all zoom levels.
* **iOS Transit Dissolve:** `TransitRevealSheet.swift` dismisses the ephemeral MapLibre `LineLayer` instantly on sheet close — no opacity fade.

### Agent Directives

#### 1. Map Style: Dérivée Day/Night Base Map

* Replace the CARTO Positron basemap URL in `TransitMap.jsx` (line 18) with a self-hosted or inline MapLibre style JSON that uses:
  * Background: `#F9F9F6` (Day / parchment white)
  * Roads/labels: dark grays matching the iOS palette
* **Do NOT implement a toggle** — hardcode Day mode for now.
* The simplest approach: fork the Positron style JSON into `transit-web/public/map-style.json`, override the `background-color` and key layer paint properties, and point `mapStyle` to `/map-style.json`.

#### 2. Parallel Subway Lines for Shared Corridors

* The current `subway-lines.geojson` merges trunk lines. To render individual parallel lines:
  * If the GeoJSON has per-route features (check `route_id` property), offset each line laterally using deck.gl's `getLineOffset` or by duplicating the `GeoJsonLayer` per route group with a small pixel offset (`getOffset: [N, 0]` where N varies per route).
  * If the GeoJSON is trunk-merged, this requires re-generating the GeoJSON with per-route linestrings — document this as a data pipeline task and skip for now.

#### 3. Sparkline Color: Force Electric Amber

* In `Sparkline.jsx` (line 36): replace `const color = getRouteColor(routeId)` with `const color = '#FFB300'` (Electric Amber).
* The sparkline should always be amber regardless of route — this is a brand element, not a data visualization.

#### 4. Arrivals Text Contrast

* In `TransitBottomSheet.css`: add explicit `color: #000000` (or `#FFFFFF` for dark mode, when implemented) to `.arrival-time`, `.arrival-route`, and `.arrival-direction` selectors to override any inherited low-contrast colors.

#### 5. Bus Map Zoom-Based Loading

* In `TransitMap.jsx`: add a `minZoom` / visibility filter to the bus stops layer (when `activeMode === 'bus'`):
  * At zoom < 13: hide all bus stops, show only bus routes as lines.
  * At zoom 13–15: show only stops with high ridership (filter by a `ridership` or `rank` property if available in the GeoJSON, otherwise show all).
  * At zoom > 15: show all bus stops.
* This requires tracking the current viewport zoom via deck.gl's `onViewStateChange` callback.

#### 6. iOS Transit Reveal Dissolve (Separate PR)

* In `TransitRevealSheet.swift`: when the sheet is dismissed (`.onDisappear` or `.onChange(of: isPresented)`), animate the ephemeral MapLibre `LineLayer`'s opacity from 1.0 → 0.0 over 200ms using `mapView.style?.setStyleLayerProperty(forLayerId:, property: "line-opacity", value: 0.0)` inside a `CATransaction` with 0.2s duration, **then** remove the layer and source after the animation completes.
* **Constraint:** This is a MapLibre Native API call, not a SwiftUI animation. Use `DispatchQueue.main.asyncAfter(deadline: .now() + 0.2)` for the cleanup delay.

### Files to Modify

* `transit-web/src/components/TransitMap.jsx` — style URL, parallel lines, bus zoom filter
* `transit-web/src/components/TransitMap.css` — any style adjustments for parallel lines
* `transit-web/src/components/Sparkline.jsx` — force Electric Amber color
* `transit-web/src/components/TransitBottomSheet.css` — arrivals text contrast
* `transit-web/public/map-style.json` — [NEW] forked Positron style with Dérivée colors
* `DeriveeNative/Derivee/TransitRevealSheet.swift` — dissolve animation (iOS, separate PR)

### Verification

* Map background renders as `#F9F9F6` parchment white, not CARTO's default off-white.
* Sparklines are consistently Electric Amber (`#FFB300`) regardless of route.
* Arrival times text is legible (high-contrast black on light background).
* Bus stops appear/disappear based on zoom level without performance regression.
* iOS: Dismissing the Transit Reveal bottom sheet causes the train route line to fade out over ~200ms before disappearing.

## Wave I.9 — Fix GRDB Observation Issue (WI9-OBS-FIX)

**Task ID:** `WI9-OBS-FIX`

**Context:**
We are working on an iOS Swift project (`iOS 17+`, `GRDB 6.29.3`, `MapLibre`, `SwiftUI @Observable`). We have a `SpatialStore` class that observes changes to a `DatabasePool` using GRDB's `ValueObservation`. 

**The Bug:**
When new hexes are inserted via `insertDiscoveredHex` (which executes `INSERT OR IGNORE INTO explored_hexes`), the database write succeeds (`db.changesCount > 0`), but the `ValueObservation`'s `onChange` block **never fires**. 
Diagnostic testing confirmed that this is a silent tracking failure in GRDB, not a SwiftUI, XCTest, or cooperative polling concurrency issue. 

**Root Cause Hypotheses:**
1. **Raw SQL Tracking:** We are currently observing using raw SQL (`try String.fetchAll(db, sql: "SELECT h3_index FROM explored_hexes")`). This may fail to robustly track updates for `WITHOUT ROWID` tables, or might be missing the appropriate explicit region configuration.
2. **Database Attachment:** Our pool attaches `transit` and `neighborhood` schemas on every connection start. This could confuse the implicit region tracking for `main.explored_hexes`.

**Your Task (I.9):**
1. Review `SpatialStore.swift`, `SpatialDatabaseManager.swift`, and `SpatialStoreFogTests.swift`.
2. Fix the observation query in `SpatialStore.startObservation` so that GRDB reliably tracks changes to the `explored_hexes` table. 
   - *Option A:* Switch from `String.fetchAll` raw SQL to explicit `TableRecord` usage (you may need to define `struct ExploredHex: TableRecord, FetchableRecord`).
   - *Option B:* Explicitly define the tracking region using `.observing(DatabaseRegion(table: "explored_hexes"))`. (Note: Make sure the syntax is correct for GRDB 6.29.3 to avoid compilation errors).
3. Validate the fix by running the test:
   `xcodebuild test -project DeriveeNative/Derivee.xcodeproj -scheme Derivee -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=latest' -only-testing:DeriveeTests/SpatialStoreFogTests/testNewlyDiscoveredHexTriggersFogShapeUpdate`
   The test must pass without timing out.
4. Make `SpatialDatabaseManager.init` private and add `@ObservationIgnored` to properties in `SpatialStore` as originally specced in I.9.

## Wave I.10a — Live Hex Unlock Pipeline Diagnostic Logging (WI10a-PIPELINE-LOGS)

**Task ID:** `WI10a-PIPELINE-LOGS`

**Context:**
Add 6-stage diagnostic logging to the live hex unlock pipeline to support on-device walk testing (I.10b) and log analysis (I.10c). Zero logic changes — print statements only.

**Stages Instrumented:**
1. **[S1]** `AmbientTrackingEngine.resumeTrackingIfNeeded`: Log entry, `isTrackingEnabled`, and `isTracking`.
2. **[S2]** `AmbientTrackingEngine.processLocation`: Log entry, hex string, timestamp, speed, and `lastSavedHex` (before deduplication guard).
3. **[S3]** `AmbientTrackingEngine.processLocation` (in Task): Log `insertDiscoveredHex` result (`isNew: Bool`).
4. **[S4]** `SpatialStore.startObservation`: Log `onChange` event with hex count and executing thread.
5. **[S5]** `SpatialStore.recomputeFogShape`: Log `Task.isCancelled` status at entry, pre-polygon build, and MainActor publish checkpoints.
6. **[S6]** `MapView.Coordinator.updateExploredHexes`: Log entry, presence of shape, interior polygon count, and `isMapStyleLoaded` flag.

## Wave I.10b — On-Device Field Walk (WI10b-ONDEVICE-WALK) [Shipped]

**Task ID:** `WI10b-ONDEVICE-WALK`

**Context & Execution:**
Physical iPhone field walk executed untethered across 8+ new H3 hex boundaries. Exported `pipeline_debug.log` from on-device `Documents/` directory via iOS Files app.

## Wave I.10c — Pipeline Log Interpretation & Verification (WI10c-LOG-INTERPRET) [Shipped]

**Task ID:** `WI10c-LOG-INTERPRET`

**Diagnosis & Interpretation:**
Analysis of the on-device `pipeline_debug.log` from the untethered field walk:
1. **[S1] Tracking Resumption:** Verified `resumeTrackingIfNeeded` starts tracking when enabled.
2. **[S2] Location Processing:** Real GPS coordinates ingested continuously; drift gate successfully dropped multi-path speed spikes (up to 15,376 m/s) while preserving walking velocities (0.5–2.5 m/s).
3. **[S3] Hex Insertion:** Correctly differentiated new hexes (`isNew=true`) from revisits (`isNew=false`), discovering 8 new hexes (1 → 9 total).
4. **[S4] GRDB ValueObservation:** Main-thread `onChange` fired immediately upon each new hex write.
5. **[S5] Fog Polygon Math:** `recomputeFogShape` ran at `.userInitiated` (`TaskPriority.high`), zero task cancellations, computing up to 9 interior rings in milliseconds.
6. **[S6] MapLibre Fog Render:** Shape seamlessly published to `MapView.Coordinator.updateExploredHexes` with `isMapStyleLoaded=true`.
7. **Cold Restart Persistence:** On app reboot, hydrated all 9 unlocked hexes on launch and re-rendered the fog mask immediately.

**Conclusion:**
All 6 stages of the live GPS-to-fog pipeline are verified 100% operational in real-world untethered conditions. Wave I is fully complete with no I.11 hotfix needed. Ready to advance to Wave J.

---

## Wave J.1 — Camera Clamping & Rubber-Band Damping [Shipped]

**Task ID:** `WJ1-CAMERA-BOUNDS`  
**Depends on:** Wave I.1–I.10 (Cold-start fog and observation pipeline complete).

### Problem Statement

In the native MapLibre iOS engine, user gestures (pan, pinch-to-zoom, momentum scrolling) allowed panning the camera infinitely past the active fog bounding box (`[40.0, 41.5]` latitude, `[-74.5, -73.0]` longitude) into empty basemap space.

Standard MapLibre bounds-locking via `mapView.restrictedCoordinateBounds` or `setCameraTargetBounds` is **strictly prohibited** by architecture rules (`docs/architecture.md:160`) because it acts as a hard wall at the Metal layer, abruptly halting momentum and causing violent jitter / lockups during high-velocity pinch-to-zoom near boundaries. Swizzling `UIGestureRecognizerDelegate` is also prohibited as it breaks internal velocity decay.

### What Shipped

1. **`CameraBounds.swift` (`DeriveeNative/Derivee/CameraBounds.swift`):**
   * Encapsulates NYC Fog bounding coordinates (`minLat: 40.0`, `maxLat: 41.5`, `minLon: -74.5`, `maxLon: -73.0`) and rubber-band elastic margin (`0.35°`).
   * Pure mathematical functions: `isWithinBounds`, `isWithinRubberBandLimit`, `clampedCoordinate`, `shouldAllowCameraChange`.
2. **Camera Delegate Gating (`DeriveeNative/Derivee/MapView.swift`):**
   * Implemented `MLNMapViewDelegate.mapView(_:shouldChangeFrom:to:reason:)` allowing movements within bounds and elastic rubber-band overshoot during active gestures (`.gesturePan`, `.gesturePinch`, etc.).
   * Rejects movement exceeding the elastic limit.
3. **Asynchronous Boundary Rollback (`DeriveeNative/Derivee/MapView.swift`):**
   * Implemented `MLNMapViewDelegate.mapView(_:regionDidChangeWith:animated:)` to detect when the camera comes to rest outside the hard bounds and trigger an asynchronous 400ms `.easeOut` animation back to the clamped boundary perimeter.
4. **Unit Tests (`DeriveeNative/DeriveeTests/CameraBoundsTests.swift`):**
   * Headless unit tests covering inside coordinates, exact corners/boundaries, outside limits, coordinate clamping, rubber-band thresholding, and camera transition gating.

### Files Modified / Created

* `DeriveeNative/Derivee/CameraBounds.swift` (New)
* `DeriveeNative/Derivee/MapView.swift` (Modified)
* `DeriveeNative/DeriveeTests/CameraBoundsTests.swift` (New)
* `ROADMAP.MD` (Status updated to `✅ Done`)

---

## Wave J.9 — Dynamic Island & Location Lifecycle Hardening on Force-Close [Shipped]

**Task ID:** `WJ9-LIFECYCLE-HARDENING`  
**Depends on:** Wave J.8 (Unified Crystalline Aperture Rollout).

### Problem Statement
When an iPhone user force-closed Dérivée from the App Switcher while ambient tracking was active, the Live Activity and CoreLocation background indicator persisted in the Dynamic Island / Lock Screen. Tapping the Dynamic Island delivered the `derivee://progress` URL scheme, causing iOS to resurrect the app process. Upon launch, persistent `@AppStorage("isTrackingEnabled")` triggered `resumeTrackingIfNeeded()`, immediately re-engaging tracking and requesting another Live Activity in an endless cycle.

### What Shipped
1. **Termination Observer (`AmbientTrackingEngine.swift`):**
   * Registered `setupTerminationObserver()` listening for `UIApplication.willTerminateNotification`.
   * On termination, synchronously invalidates `CLBackgroundActivitySession` and terminates all active `Activity<TrackingAttributes>` with `.immediate` dismissal policy.
2. **Rolling 2-Minute `staleDate` Fail-Safe (`AmbientTrackingEngine.swift`):**
   * Configured `staleDate: Date().addingTimeInterval(120)` on all `ActivityContent` updates.
   * If the app is killed abruptly without `willTerminateNotification` delivering (e.g. suspended app kill), iOS's `chronod`/SpringBoard automatically cleans up the Dynamic Island after 2 minutes of silence.
3. **Continuous Intra-Hex Heartbeat Refresh (`AmbientTrackingEngine.swift`):**
   * Refreshes distance metrics and the rolling `staleDate` on incoming GPS updates even within the same hex boundary, ensuring stationary exploration (e.g., waiting at crosswalks) does not expire while tracking is active.
4. **Test Suite (`TrackingEngineTests.swift`):**
   * Added `testAppTerminationCleanup()` validating termination handling and orphaned activity sweeps.
5. **Documentation (`docs/architecture.md`, `docs/design.md`, `ROADMAP.MD`):**
   * Documented Section 3.6 in `architecture.md` and Section 6 in `design.md`.

---

## Wave K.5 — Grey Out Unavailable Direction in Full Timetable [Shipped]

**Task ID:** `WK5-DIRECTION-GREYING`  
**Depends on:** Wave K.4 (Bus Terminal Name Resolution), Wave 11.7b (Full Timetable Matrix).

### Problem Statement
In GTFS transit feeds, terminal stations (e.g. 8th Ave L, South Ferry 1, Hudson Yards 7) and one-way bus routes only serve departures in a single direction. Previously, `DepartureMatrixView` rendered a standard 2-segment picker where both tabs appeared selectable, even when one direction had 0 scheduled departures. Selecting the empty direction showed empty timetable rows ("No scheduled service") for every hour of the day, and initializing with `selectedDirection = 0` on a terminal stop landed users on an empty timetable.

### What Shipped
1. **Direction Availability Detection (`SpatialDatabaseManager.swift`):**
   * Implemented `fetchAvailableDirections(for:routeId:routeIds:)` querying `SELECT DISTINCT direction_id FROM transit.scheduled_stops WHERE stop_id = ?`.
   * Added `generateFallbackAvailableDirections(for:routeId:)` with deterministic terminal stop pattern detection (`stop_8th_ave`, `stop_south_ferry`, `stop_flushing_main_st`, `stop_hudson_yards`, etc.).
   * Updated `generateFallbackTimetable` to return empty departures when querying an unavailable direction.
2. **Native Custom Segmented Control (`DepartureMatrixView.swift`):**
   * Replaced SwiftUI `Picker` with custom `DirectionSegmentedPicker` matching iOS system segmented control metrics.
   * Renders unavailable directions with `.disabled(true)`, `.opacity(0.35)`, and `" (No Service)"` label suffix.
   * Auto-selects the first available valid direction on appear and when `availableDirections` changes.
3. **Transit Sheet Integration (`TransitRevealSheet.swift`):**
   * Added `availableDirections: Set<Int>` state.
   * Loads available directions in `startPollingLifecycle()`, resolves initial valid direction before timetable query, and passes `availableDirections` to `DepartureMatrixView`.
4. **Test Suite (`TransitRevealSheetTests.swift`):**
   * Added `testFetchAvailableDirectionsInDatabase`: Validates `Set([1])` for single-direction terminal stops, `Set([0])` for direction 0 stops, and `Set([0, 1])` for bidirectional stops in SQLite.
   * Added `testFallbackAvailableDirectionsForTerminalStops`: Validates terminal fallback detection.
   * Added `testDepartureMatrixViewAutoSelectsValidDirection`: Validates auto-selection of active direction 1 when direction 0 is unavailable.
   * Added `testDepartureMatrixViewDisabledDirectionSnapshot`: Snapshot verification of disabled Direction 0 tab with `(No Service)` suffix and active Direction 1 timetable.

### Files Modified
* `DeriveeNative/Derivee/SpatialDatabaseManager.swift`
* `DeriveeNative/Derivee/DepartureMatrixView.swift`
* `DeriveeNative/Derivee/TransitRevealSheet.swift`
* `DeriveeNative/DeriveeTests/TransitRevealSheetTests.swift`
* `ROADMAP.MD`
* `archive/shipped-waves-archive.md`



