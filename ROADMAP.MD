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
| **1** | **TEST-PHASE1** | **Core Engine Unit Tests (Background & SQLite)** | **M** | 🚧 In Progress |
| **2** | **TEST-PHASE2** | **Spatial Math & Transit Hydration Unit Tests** | **S** | Planned (Before Wave G) |
| **3** | **TEST-PHASE3** | **Automated UI / Snapshot Testing** | **M** | Planned (During Wave G) |
| **4** | **TEST-PHASE4** | **CI/CD Pipeline (Xcode Cloud / Actions)** | **M** | Planned (Start of Wave H) |

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
| **G** | **WG-TRANSIT-REVEAL** | **Transit Reveal Enhancements** | **S** | Planned |
| **H** | **WH-SHIP** | **Polish, Settings Rewire & Ship Prep** | **M** | Planned |

### Post-Ship (Deferred)

| Wave | Task ID | Title | Size | Status |
|:---:|:---:|:---|:---:|:---:|
| — | W11.7-UI-MATRIX | Build Headway Matrix (Timetable) UI | L | Deferred |
| — | W12-BOSTON | Multi-City Expansion: MBTA | L | Deferred |
| — | W15-DYNAMIC-ISLAND | Dynamic Island Support for Stat Bar | S | Deferred |

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

## Wave 11.8 — Transit Web MVP Bugfixes & Polish [Planned]

**Task ID:** `W11.8-WEB-FIXES`
**Depends on:** Wave 11.5 (Transit Web MVP Launch).

### Goal
Address immediate visual and functional bugs in the `transit-web` spinoff to ensure the MVP is stable, visually polished, and matches the fidelity of the official MTA maps.

### Agent Directives

1. **Map Color & Stop Matching:**
   * [x] Fix the `stop_id` to route matching logic so that all subway stops (e.g. the ones rendering as purple defaults) correctly inherit their official MTA route colors and properly pull live arrival times.
2. **Map Design & Routing Fidelity:**
   * [ ] Take inspiration from the latest MTA subway map: show all individual lines on the map rather than merged trunks.
   * [ ] Render multiple parallel lines for shared corridors (e.g. 3 distinct green lines for the 4/5/6 to visually indicate transfer stations).
   * [ ] Ensure bridges carrying multiple services (e.g., Williamsburg bridge) render with all respective colors (Orange for M, Brown for J/Z).
3. **Arrivals UI Contrast & Direction:**
   * [x] Update the real-time arrivals text in the bottom sheet to display proper directionality (e.g., "Manhattan-bound", "Uptown").
   * [ ] Fix the color contrast for the arrivals text (the current Electric Amber `#FFB300` is unreadable against the light mode background).
4. **Historical Data Validation:**
   * [x] Ensure historical reliability sparklines accurately load real SQLite data for both subways and buses from the Observer daemon, rather than falling back to dummy/empty states.
5. **Bus Map Clutter Reduction:**
   * [ ] Optimize the bus map view by implementing dynamic zoom-based loading.
   * [ ] Only render bus stops that are within the current view window at a close zoom level, or filter to only display the busiest nodes at macro zoom levels.

### Verification
* All subway nodes match their official colors and fetch live data correctly.
* Parallel subway lines are visible on shared corridors.
* Arrivals text is legible in Light Mode and includes direction strings.
* Sparklines render real data from `transit_delta.sqlite`.
* Bus view remains performant and legible at all zoom levels.

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

---

## Testing Strategy & Rollout

Broadening the overall testing strategy across upcoming waves. We are adopting a **staggered approach** to ensure a solid foundation before building further UI:

### Phase 1: The Core Engine (Current Plan)
**Status:** Ready for Execution.

**Why it's perfect:** It isolates the most volatile, battery-draining, and logic-heavy part of the app (Background Location + SQLite concurrency) and proves it works deterministically without needing physical hardware.

### Phase 2: Pure Spatial & Data Unit Tests (The Next Wave)
**Timing:** MUST be completed **BEFORE** Wave G.
Once Phase 1 is merged, the next testing wave isolates the raw math and data hydration, completely separate from the tracking engine. Wave G relies heavily on this transit data and spatial math.

* **H3 Boundary Tests:** Feed known edge-case coordinates (e.g., coordinates exactly on the boundary of two hexes, or coordinates over water) into the `swift-h3` wrapper. Assert that the resulting 15-character hex string exactly matches the expected output.
* **Transit Hydration Tests:** Write a test that takes a mocked, ultra-small `transit_delta.sqlite` file, runs the `SpatialDatabaseManager` attachment logic, and asserts that the `transit.stops` table successfully merges.

### Phase 3: Automated UI / Snapshot Testing
**Timing:** Implement **DURING** Wave G and **BEFORE** Wave H.
As more gamified elements are added (like the Skia "Morning Sun" reveal or Transit Bottom Sheets), visual regressions become the biggest risk.

* **The Strategy:** Introduce `swift-snapshot-testing` (by Point-Free).
* **How it works:** Write tests that render SwiftUI views (`StatsView`, `TransitRevealSheet`) with mocked `@Observable` state, and the test takes a literal screenshot. If a future AI agent accidentally changes a padding value or deletes the `.ultraThinMaterial` background, the test fails and blocks the deployment.

### Phase 4: CI/CD Pipeline (The "Fast Deployment" Engine)
**Timing:** Set up at the **START** of Wave H.
To actually achieve "fast deployment," these tests cannot just live on the local machine. Because the project uses `xcodegen` and pure Swift, the CI/CD setup is incredibly clean.

* **The Strategy:** Set up GitHub Actions or Xcode Cloud.
* **The Workflow:** 
  1. Push a branch generated by an AI agent.
  2. The CI server checks out the code and runs `xcodegen` to generate the `.xcodeproj`.
  3. It runs `xcodebuild test` headlessly.
  4. If the Drift Gate tests or POI tests fail, the pull request is blocked. If it's green, it auto-merges or deploys to TestFlight.