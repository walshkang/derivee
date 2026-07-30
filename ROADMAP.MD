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
| A | WA-DB-CONCURRENCY | Database Config & Dual-Thread Concurrency | M | ✅ Done |
| B | WB-NITRO-SCAFFOLD | Nitro Module Scaffolding & Code Generation | M | 🔧 In Progress (Human: Xcode Linkage) |
| **C** | **WC-SWIFT-SERVICE** | **Swift Background Service & Baseband Economics** | **L** | Planned |
| **D** | **WD-UI-HYDRATION** | **UI Synchronization, Foreground Hydration & Legacy Cleanup** | **L** | Planned |

### 🎨 Design Alignment & Ship

| Wave | Task ID | Title | Size | Status |
|:---:|:---:|:---|:---:|:---:|
| **11.6** | **W11.6-DEVOPS** | **Deploy Go Observer to Oracle Cloud & Seed R2** | **M** | Planned |
| **E** | **WE-ONBOARDING** | **Onboarding Gate & First-Launch Infrastructure** | **M** | Planned |
| **F** | **WF-MAP-OVERHAUL** | **Map UI Overhaul & Ghost POI Lifecycle** | **L** | Planned |
| **G** | **WG-TRANSIT-REVEAL** | **Transit Reveal Enhancements** | **S** | Planned |
| **H** | **WH-SHIP** | **Polish, Settings Rewire & Ship Prep** | **M** | Planned |

### Post-Ship (Deferred)

| Wave | Task ID | Title | Size | Status |
|:---:|:---:|:---|:---:|:---:|
| — | W11.7-UI-MATRIX | Build Headway Matrix (Timetable) UI | L | Deferred |
| — | W12-BOSTON | Multi-City Expansion: MBTA | L | Deferred |
| — | W15-DYNAMIC-ISLAND | Dynamic Island Support for Stat Bar | S | Deferred |

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

## Wave D — UI Synchronization, Foreground Hydration & Legacy Cleanup [Planned]

**Task ID:** `WD-UI-HYDRATION`
**Depends on:** Wave C (Swift background service compiles and runs).

### Goal
Wire the React Native foreground to seamlessly hydrate from the shared SQLite database upon app resume. Implement the Nitro real-time callback integration and the $O(1)$ In-Memory Set Gate to prevent bridge starvation. **Additionally, perform a full cleanup of all deprecated JS-background code and UI components that were superseded by the Sleepy Hermes transition.**

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
   * **Delete `src/hooks/useBackgroundLocation.ts`** — wraps deprecated `expo-location` background tracking.
   * **Delete `src/services/locationTask.ts`** — uses banned `TaskManager.defineTask()`.
   * **Delete `src/services/locationService.ts`** — deprecated `expo-location` background service.
   * **Delete `src/components/ContextualStatPill.tsx`** — violates design.md Guardrail G5 ("No heavy persistent HUDs"). Remove all imports and references from `app/map.tsx`.
   * Remove legacy top-bar text navigation buttons ("History", "Settings") from `app/map.tsx` — these are replaced by FABs in Wave F.

### Verification
* App foregrounds after background exploration and correctly displays newly unlocked hexes.
* MapLibre maintains 60fps during hydration (no bridge starvation).
* `Set.has()` correctly gates redundant updates (verify via console logging in dev).
* `expo-task-manager` is fully removed from the dependency tree.
* All deleted files have zero remaining import references across the codebase.
* `npx expo prebuild --clean` completes successfully after removals.

---

## Wave 11.6 — Deploy Go Observer to Oracle Cloud & Seed R2 [Planned]

**Task ID:** `W11.6-DEVOPS`
**Depends on:** Wave D complete. Observer tool already built (W9-OBSERVER).

### Goal
Deploy the Go-based Observer daemon to Oracle Cloud infrastructure and establish the automated nightly pipeline that generates Zstandard-compressed SQLite transit delta files and uploads them to Cloudflare R2. This must be operational **before** Wave E, which depends on downloading the transit delta on first launch.

### Agent Directives

1. **Oracle Cloud deployment:**
   * Containerize the Observer daemon (Dockerfile if not already present).
   * Deploy to Oracle Cloud Free Tier (ARM Ampere A1) or equivalent always-on compute.
   * Configure systemd or equivalent process supervisor for automatic restart.

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

## Wave E — Onboarding Gate & First-Launch Infrastructure [Planned]

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

## Wave F — Map UI Overhaul & Ghost POI Lifecycle [Planned]

**Task ID:** `WF-MAP-OVERHAUL`
**Depends on:** Wave D (Nitro callbacks + Set Gate operational for Ghost POI lifecycle transitions and hex unlock animations).

### Goal
Align the core map screen (`app/map.tsx`) with the updated `docs/design.md` specification. Replace legacy navigation with FABs, implement the 3-phase Ghost POI lifecycle, and add ambient hex unlock animations.

### Agent Directives

1. **Floating Action Buttons (`src/components/MapFAB.tsx` — new file):**
   * **Recenter FAB** (bottom-right): Re-centers the MapLibre camera on the user's GPS position with a 300ms ease animation.
     * Idle: semi-transparent (`opacity: 0.7`), `@react-native-community/blur` `UltraThinMaterial` background.
     * Press: instant `impactLight` haptic, scale to `0.92` over 100ms, spring back.
     * State: filled icon variant when centered on user; outlined variant when user has panned away.
   * **Profile FAB** (top-right): Navigates to `app/stats.tsx` (Screen 3).
     * Same blur/haptic/scale behavior as Recenter.
   * Both FABs use `react-native-gesture-handler` exclusively (not `TouchableOpacity`).

2. **Ghost POI 3-Phase Lifecycle (refactor `src/components/` + map layers):**
   * **Phase 1 — The Lure (Hidden Territory):**
     * Render Ghost POIs as soft, anonymous beacon glows **above** the fog layer (Layer 4 in the 6-layer stack).
     * Zero text labels, zero identification. Faint pulsing glow animation.
     * Implemented as a MapLibre `CircleLayer` with low opacity, large blur radius, and a subtle scale pulse via `circleRadius` expression.
   * **Phase 2 — The Unlocking (Active Vicinity):**
     * When the user's GPS enters the hex containing a Ghost POI (within the 200m bubble):
       * Beacon resolves into a crisp geometric node: dot for bus stops, diamond for subway entrances.
       * Subtle reveal scale animation (0→1 over 200ms, ease-out).
       * On **first encounter** with a previously unseen POI: show a lightweight toast notification sliding from the top with the station name and a fun fact. Auto-dismiss after 3 seconds.
     * Tappable. Triggers PiP proximity check → Transit Reveal bottom sheet (Screen 2).
   * **Phase 3 — The Archive (Explored Territory):**
     * When the user leaves the Active Vicinity, the node fades to near-invisibility.
     * **Completely invisible at zoom ≤ 16.** At zoom 17+: ultra-faint desaturated mark (opacity ≤ 0.15).
     * Not tappable when outside Active Vicinity — PiP check gates all interactions.
   * Use MapLibre Data-Driven Styling with `['match']` expressions keyed on POI phase state (stored in the Zustand POI store) to control visibility per-node.

3. **Native user location marker:**
   * Verify that MapLibre's built-in user location layer is used (not a React component overlay).
   * Custom styling: blue pulsing dot with concentric ring animation (1.5s interval, opacity 0.4→0 fade).
   * Subtle directional heading cone when device compass is active.

4. **Real-time hex unlock animation:**
   * On Nitro callback (new hex discovered):
     * Hex fog transitions opaque→transparent via existing `fill-opacity-transition: { duration: 300 }`.
     * A soft glow ring (single pulse) emanates from the user's position.
     * **No sound effects. No confetti. No modal popups.** Ambient and organic.

### Verification
* FABs render with blur effect, respond to gesture-handler taps with haptic feedback.
* Recenter FAB toggles between filled/outlined state based on camera position.
* Ghost POIs in Hidden territory show as faint beacons through the fog.
* Ghost POIs in Active vicinity show as crisp geometric nodes and are tappable.
* Ghost POIs in Explored territory are invisible at zoom ≤ 16.
* Discovery toast appears on first encounter with a new POI, auto-dismisses after 3 seconds.
* Hex unlock animation plays at 60fps without frame drops.
* No legacy top-bar buttons or Contextual Stat Pill remain anywhere in the codebase.

---

## Wave G — Transit Reveal Enhancements [Planned]

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

## Wave H — Polish, Settings Rewire & Ship Prep [Planned]

**Task ID:** `WH-SHIP`
**Depends on:** Waves E, F, G all complete.

### Goal
Final integration pass. Rewire the Settings screen to use Nitro-backed tracking controls, implement the GPX reveal animation, perform end-to-end testing on a physical device, and prepare App Store metadata.

### Agent Directives

1. **Settings screen rewire (`app/settings.tsx`):**
   * Replace all `expo-location` permission toggles with Nitro `startTracking()` / `stopTracking()` calls via `src/native/trackingBridge.ts`.
   * Show the current background location permission state (authorized/denied/undetermined).
   * **"Clear Local Cache":** Purge cached tiles and transit data files. Delete `hydration_complete` from `meta` table so the Onboarding Gate re-triggers on next launch.
   * **"Reset Exploration Data":** Destructive action. Show a native confirmation dialog (`Alert.alert` with destructive button style). On confirm: `DELETE FROM explored_hexes`, clear the in-memory `Set`, reset Zustand store, and force MapLibre DDS to re-render full fog.
   * All toggles and buttons use `react-native-gesture-handler`.

2. **GPX reveal animation (refactor `app/stats.tsx` upload handler):**
   * When a GPX/FIT file is uploaded and processed:
     * Calculate the distance of each newly unlocked hex from the user's current position.
     * Sort hex clusters by distance (nearest first).
     * Apply MapLibre's `fill-opacity-transition` with a staggered delay per cluster — fog "melts away" radially from the user outward.
     * Total animation duration: 1.5–2.5 seconds depending on geographic spread.
     * Must run at 60fps on the UI thread. The heavy bridge recalculation (parsing, deduping, bulk inserts) completes **before** the animation begins.

3. **End-to-end integration test (physical device):**
   * Full flow: Onboarding Gate → ambient walk → hex unlock → Ghost POI tap → Transit Reveal sheet with route line → Archive stats → GPX upload with reveal animation → Settings reset.
   * Verify on a physical iPhone (per AGENTS.MD §5 — never trust Simulator for MapLibre performance).

4. **Performance profiling:**
   * MapLibre fog rendering at 60fps during active exploration.
   * No bridge starvation during AppState hydration (measure with React DevTools profiler).
   * Background battery drain target: < 5% per hour during ambient tracking.
   * Transit delta query: < 12ms for sparkline reads.

5. **App Store submission prep:**
   * Run `npx expo prebuild --clean` — verify `Info.plist` and `AndroidManifest.xml` generate correctly.
   * Verify all Expo config plugin permissions (location always, motion) are present.
   * Prepare App Store metadata: screenshots, description, privacy nutrition labels (Location Always, Local Storage).
   * Verify the native Xcode build compiles successfully via `xcodebuild` or the Xcode GUI.

### Verification
* Settings toggles correctly control Nitro `startTracking()` / `stopTracking()`.
* Data reset clears all hexes and re-renders full fog.
* Cache clear re-triggers the Onboarding Gate on next launch.
* GPX reveal animation plays at 60fps with a satisfying radial dissolve.
* Full end-to-end flow completes without crashes, frame drops, or stale state.
* `npx expo prebuild --clean` succeeds.
* Native Xcode build compiles and runs on a physical device.