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
| **4** | **TEST-PHASE4** | **CI/CD Pipeline (GitHub Actions)** | **M** | ✅ Done |

### 🎨 Design Alignment & Ship

| Wave | Task ID | Title | Size | Status |
|:---:|:---:|:---|:---:|:---:|
| **11.6** | **W11.6-DEVOPS** | **Deploy Go Observer to Oracle Cloud & Seed R2** | **M** | ✅ Done |
| **11.8** | **W11.8-WEB-FIXES** | **Transit Web MVP Bugfixes & Polish** | **M** | ✅ Done |
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
| **I.3** | **WI3-FOG-TESTS** | **Cold-Start Fog Regression Tests** | **S** | ✅ Done |
| **I.3a** | **WI3a-LIVE-FOG** | **Fix Live Fog Update Starvation (`.background` → `.userInitiated`)** | **XS** | ✅ Done |
| **I.4** | **WI4-ASYNC-READS** | **Eliminate Main-Thread DB Reads & Configure GRDB QoS** | **M** | ✅ Done |
| **I.5** | **WI5-HANG-TESTS** | **Priority Inversion Regression Tests** | **S** | ✅ Done |
| **I.6** | **WI6-TRACK-STOP** | **Fix Ambient Tracking Stop Lifecycle (Live Activity + Persistence)** | **S** | ✅ Done |
| **I.7** | **WI7-LA-CLEANUP** | **Clean up Orphaned Live Activities (Dynamic Island) on App Force-Quit / Cold Start** | **S** | ✅ Done |
| **I.8** | **WI8-OBS-DIAG** | **GRDB ValueObservation Diagnostic Instrumentation: Add `deinit` log to `SpatialStore`, pool `ObjectIdentifier` logs to `SpatialStore.startObservation` + `AmbientTrackingEngine.processLocation` + `SpatialDatabaseManager.init`. Logging only — zero logic changes. Build on physical iPhone, walk until hex insert, read logs to confirm observation alive + pool identity match.** | **XS** | ✅ Done |
| **I.9** | **WI9-OBS-FIX** | **GRDB ValueObservation Pipeline Hardening: Diagnostic testing revealed a silent `ValueObservation` failure in GRDB. An isolated minimal test confirmed that even when `insertDiscoveredHex` successfully writes to the `DatabasePool` (changesCount > 0), the `onChange` closure never fires for the update. Root cause hypotheses: (1) `ATTACH DATABASE` confusing region tracking, (2) Raw SQL `String.fetchAll` missing updates compared to `TableRecord`, (3) `.withoutRowID` table tracking limitations. Next Steps: Fix the observation query (e.g., use standard `TableRecord` or verify `.observing(DatabaseRegion(table: "explored_hexes"))` syntax for GRDB 6.29.3) so the minimal test passes, then apply to `SpatialStore` and fix `generateH3Hexes` non-determinism.** | **S** | ✅ Done |
| **I.10a** | **WI10a-PIPELINE-LOGS** | **Add 6-stage diagnostic logging to the live hex unlock pipeline via `PipelineLogger` (stdout + `os.Logger` + `Documents/pipeline_debug.log`). Enabled `UIFileSharingEnabled` & `LSSupportsOpeningDocumentsInPlace` for iOS Files App access during untethered field testing. [S1] `resumeTrackingIfNeeded` entry + `isTrackingEnabled`. [S2] `processLocation` entry + hex string + timestamp + speed. [S3] `insertDiscoveredHex` result (`isNew`). [S4] `onChange` hex count + Thread. [S5] `recomputeFogShape` cancellation checkpoints. [S6] `updateExploredHexes` shape presence + interior polygon count.** | **XS** | ✅ Done |
| **I.10b** | **WI10b-ONDEVICE-WALK** | **🧑‍💻 Human-only task (no agent). Build I.10a on physical iPhone. Force-close the app. Reopen. Walk across 3+ hex boundaries untethered. Open iOS **Files** app → **On My iPhone** → **Dérivée** → AirDrop `pipeline_debug.log` (or copy console logs). Paste logs into a new conversation for I.10c to interpret.** | **XS** | ✅ Done |
| **I.10c** | **WI10c-LOG-INTERPRET** | **Read the on-device logs from I.10b (`pipeline_debug.log`) and identify which pipeline stage breaks. Decision tree: If S2 never fires → `CLLocationUpdate.liveUpdates()` warm-up delay. If S2 fires but S3 shows `isNew=false` → `INSERT OR IGNORE` dedup (user still on same hex). If S3 shows `isNew=true` but S4 doesn't fire → GRDB `ValueObservation` issue. If S4 fires but S5 shows `cancelled=true` → `recomputeFogShape` cancellation race. If S5 completes but S6 doesn't fire → SwiftUI `@Observable` → `UIViewRepresentable` bridge issue. File findings and the targeted fix as I.11.** | **XS** | ✅ Done |

### 🚀 Exploration, Performance & Map Customization (Wave J — Post-Debugging)

> [!NOTE]
> **Execution Cadence:** Wave J sub-waves execute in strict sequential order (J.2 → J.8). Each targets a distinct architectural layer; building and verifying independently prevents cascading style/shader regressions on the 120Hz render loop.

| Wave | Task ID | Title | Size | Status |
|:---:|:---:|:---|:---:|:---:|
| **J.1** | **WJ1-CAMERA-BOUNDS** | **Camera Clamping, 2D Top-Down Lock & Rubber-Band Damping:** Lock camera strictly to 2D top-down view (`pitch = 0`, `mapView.allowsTilting = false`). Reject `.gestureTilt` and `pitch > 0` in `shouldChangeFrom:to:reason:` delegate. Asynchronous `.easeOut` boundary rollback for rubber-band stretch. Enable full-zoom 2D building footprints (`z = 13..24`) and disable 3D fill-extrusions to ensure 1:1 geographic sync with Fog of War. | **S** | ✅ Done |
| **J.2** | **WJ2-PERF-OPTIMIZATION** | **120Hz Spatial Unioning & Render Optimization:** Full Res-11 dissolution via `cellsToLinkedMultiPolygon` in `Task.detached(priority: .userInitiated)`. Traverses `LinkedGeoPolygon` cluster outer boundary loops (`first`), reverses vertices for CW winding order, and injects as interior holes in bounding box `MLNPolygon` (>85% vertex reduction), targeting <1.5ms `@MainActor` shape assignment. | **M** | ✅ Done |
| **J.3** | **WJ3-FOG-POI-MASKING** | **Dual-Model Vector Tile POI Masking (Pure Separation):** Commercial/retail POIs in MapTiler base vector tiles suppressed via GPU `mgl_distanceFrom:(userPoint) <= 200` predicate. Interactive stations, ghost POIs, and permanent landmark pins rendered exclusively via native SQLite-backed `poiSourceId` runtime layer. | **S** | ✅ Done |
| **J.4** | **WJ4-BASEMAP-SWITCHER** | **Bundled Composite Style Basemap Switcher:** Local `composite_style.json` in app bundle with shared `maptiler_streets` vector source and pure Light Mode themes (Standard Exploration `#F9F9F6` and Transit Navigation `#FFFFFF`). Runtime key injection. Crossfade themes via `MLNTransition(duration: 0.6)` layer opacity/color transitions on GPU — zero style destruction, zero source unmounting. | **M** | ✅ Done |
| **J.5** | **WJ5-CUSTOMIZATION-SETTINGS** | **Zero-Geometry Customization Settings (Screen 3 + `@AppStorage`):** Fog opacity slider (`0.40`–`0.98`, auto-adapting 40% in Transit mode and 85% in Day mode) and hex/boundary borders via `MLNLineStyleLayer` attached directly to existing `fog-source` in `SettingsView`. `@AppStorage` persistence with `MLNTransition(duration: 0)` fragment shader updates — no polygon recomputation or DB queries. | **S** | ✅ Done |
| **J.6** | **WJ6-TRANSIT-NODE-TRACKING** | **Hybrid SwiftProtobuf Transit Sheet & Local Shape Fallback:** SPM `swift-protobuf` + pre-compiled `gtfs-realtime.pb.swift` models. Sheet-scoped 15s polling for live arrivals (cancelled on dismiss). Physical track/route geometries sourced from pre-hydrated local `derivee_transit.sqlite`. Dual-layer high-contrast route rendering (6px silver casing + 4px agency color). | **M** | ✅ Done |
| **J.7** | **WJ7-POI-GAMIFICATION** | **Dual-Sensory Discovery Loop & Categorized Milestone Journal:** Instant `UIImpactFeedbackGenerator(.light)` on GRDB insert + transient expanding `MLNCircleStyleLayer` pulse (0→80px, 1.2s fade) on the map. Screen 3 Exploration Journal with on-demand asynchronous GRDB aggregation (`dbWriter.read`) for categorized milestone progress cards (Transit Hubs, Neighborhoods, Landmarks). | **M** | ✅ Done |
| **J.8** | **WJ8-APERTURE-BRANDING** | **Unified Crystalline Aperture Rollout (AppIcon, FAB, Milestones & Live Activity):** (1) Generate Day/Night/iOS 18 Tinted `AppIcon.appiconset` vector assets. (2) Replace `person.crop.circle` in `ProfileFAB` with Variation A aperture micro-glyph in `.ultraThinMaterial`. (3) Upgrade Screen 0 Onboarding Gate with centered pulsing vector aperture during SQLite hydration. (4) Upgrade Screen 3 Exploration Journal with high-negative-space milestone cards and settings build signature. (5) Polish `TrackingLiveActivity` Dynamic Island compact leading micro-glyph and trailing distance metrics. (6) Style 120Hz native MapLibre compass needle in top-left matching brand identity. | **M** | ✅ Done |
| **J.9** | **WJ9-LIFECYCLE-HARDENING** | **Dynamic Island & Location Lifecycle Hardening on Force-Close:** Add `UIApplication.willTerminateNotification` observer in `AmbientTrackingEngine` to synchronously invalidate `CLBackgroundActivitySession` and end active `Activity<TrackingAttributes>`. Add rolling 2-minute `staleDate` fail-safe on `ActivityContent` and intra-hex distance heartbeat refresh. | **XS** | ✅ Done |
| **J.10** | **WJ10-DYNAMIC-ISLAND-CONTRACT** | **Decoupled Ambient Tracking & Dynamic Island Lifecycle Contract:** (1) Decouple Live Activity from mandatory background tracking with `@AppStorage("isLiveActivityEnabled")` sub-toggle under Settings > Tracking. (2) Shorten rolling `staleDate` to 45s so Dynamic Island auto-dismisses if app is killed. (3) Clean up all orphaned activities before requesting new ones. (4) Wire `derivee://progress` deep link via `.onOpenURL` to trigger map recenter and aperture pulse glow. (5) Comprehensive unit tests for toggle and lifecycle contracts. | **S** | ✅ Done |
| **J.11** | **WJ11-FOG-ISLANDS** | **Closed Loop Fog Islands via FogGeometry Composite Shapes:** Traverse interior `LinkedGeoLoop.next` holes within `LinkedGeoPolygon` clusters to extract unvisited center island polygons, reversing vertex coordinates for clockwise outer winding. Construct composite `MLNShapeCollection` containing the main bounding box polygon with interior cutout holes plus disjoint interior fog island polygons, accurately preserving unexplored city blocks encircled by closed-loop walks. | **S** | ✅ Done |
| **J.12** | **WJ12-LOCATION-FILTER** | **Multi-Stage Cold Start Location Filter & Contextual Drift Gate:** Implement `ColdStartLocationFilter` replacing raw speed gating with Rayleigh horizontal uncertainty bounding ($\le 25\text{m}$ for H3 Res 11), cache staleness check ($\le 5\text{s}$), instant unlock for high-accuracy fixes ($\le 12\text{m}$), 3.0-second stationary dwell fallback ($12\text{m} < \text{hAcc} \le 25\text{m}$), and subway emergence discontinuity classifier ($\Delta t \ge 15\text{s}$). Resets baseline velocity jumps without dropping subway arrival emergence fixes. | **M** | ✅ Done |
| **J.13** | **WJ13-THOROUGHFARES-BUS-LENS** | **MTA Subway Thoroughfares Under Fog & Nearby Bus Quick Lens:** (1) Pre-bundle full NYC subway line geometries (`MtaSubwayNetworkData`) as an ambient orienting sub-context beneath the fog of war with day/night adaptive casings. (2) Floating frosted-glass `NearbyBusesCapsule` quick lens with 400m spatial SQLite queries, real-time Protobuf bus arrival deserialization, and Settings toggle (`showNearbyBusesLens`). | **M** | ✅ Done |
| **J.14** | **WJ14-LOCATION-BRIDGE** | **MapLibre Location Bridge & Decoupled UI GPS Resolution:** (1) Bi-directional `currentUserLocation` binding from `MapView` to `ContentView` bridging live MapLibre GPS updates to the HUD. (2) Decouple immediate UI location updates in `AmbientTrackingEngine` from strict multi-fix cold-start/drift filter gates. (3) Eliminate cold-start City Hall queries on appear; implement deferred auto-scan upon acquiring first valid GPS fix. (4) 150m walking drift auto-refresh with manual refresh (↻) support and cold-start loading status. | **S** | ✅ Done |
| **J.15** | **WJ15-STATION-MARKER-TOGGLE** | **Subway Station Marker Style Pipeline & Sub-Fog Bullets Layer:** (1) Wire `SubwayStationMarkerStyle` (`Explored Only`, `All Stations`, `Hidden`) from Settings through `POIMaskManager.resolvePhase`. (2) Add `subway-station-bullets-layer` beneath the fog mask for subtle orienting sub-context in `All Stations` mode with theme-adaptive styling. (3) Lower `archiveLayer.minimumZoomLevel` to `11.0` and polish 4.5pt circle styling. (4) Add tap-to-inspect interactivity for archive and sub-fog bullets to open `TransitRevealSheet`. (5) Unit tests in `POIMaskingTests` and `CustomizationSettingsTests`. | **S** | ✅ Done |
| **J.16** | **WJ16-SPARKLINE-CONTRAST** | **Transit Sparkline Readability & Arrival Contrast Fix:** (1) Switch arrival countdown minutes in `TransitRevealSheet` from `Color(hex: "#FFB300")` to `.primary` for WCAG AA contrast in Day Mode — LIVE badge stays amber (status signal, not body text). (2) Replace `"7 Days Ago"` / `"Today"` X-axis labels in `TransitSparklineView` with dynamic abbreviated day names + short dates (e.g., `"Thu 8/14"` → `"Wed 8/20"`) computed backwards from a `referenceDate: Date = Date()` init parameter. (3) Add today's headway value as a small numeric label near the trailing glowing dot. (4) Keep 48pt chart height, existing avg header badge, existing dashed midline. (5) Pin `referenceDate` in `TransitRevealSheetTests` snapshot to avoid daily CI drift. **Explicitly out of scope:** NearbyBusesCapsule (contrast acceptable), adaptive color token system (overkill), tap-to-timetable affordance (no timetable to open), formal Y-axis labels (chart too compact), min/max annotations (collision risk at adjacent data points). | **S** | ✅ Done |

### 🐛 Post-Wave J Field Fixes & UX Polish (Wave K)

> [!NOTE]
> **Field testing results.** Issues discovered during hands-on testing after Wave J completion. P0 items block core interactivity; P1 items affect data correctness; P2/P3 items are polish and architectural planning.

| Wave | Task ID | Title | Size | Status |
|:---:|:---:|:---|:---:|:---:|
| **K.1** | **WK1-TAP-TARGETS** | **Invisible 44pt Transit POI Tap Targets (Visual Size Preserved):** Widen `visibleFeatures` hit-test from single-point query to `CGRect(x: p.x-22, y: p.y-22, width: 44, height: 44)` tolerance box with closest-feature distance tiebreaking. Preserve refined `4.5pt` archive circle radii and sub-fog bullet styling — zero visual changes. Applies to `activeLayerId`, `archiveLayerId`, `subwayStationBulletsLayerId`, and `nearbyBusStopsLayerId` layers in `MapView.Coordinator.handleMapTap`. | **S** | ✅ Done |
| **K.2** | **WK2-RELIABILITY-PICKER** | **Dual-Input Reliability Inspector (Passive Matrix + Day/Hour Menu):** Add compact `Menu`-based Day and Hour selectors below `ReliabilityHeatmapCanvas` as the primary entry point to `TransitMatrixInspectorView`. Keep the 24×7 Canvas as a passive high-density visual overview with optional crosshair highlight on touch. Each picker selection opens the inspector sheet with the corresponding `HourlyReliabilityRecord`. Eliminates reliance on 5.2pt-tall cell tap targets. | **S** | ✅ Done |
| **K.3** | **WK3-MULTI-ROUTE-SHEET** | **Multi-Route Transit Sheet for Co-Located Lines (R/W, N/Q, B/D/F/M):** (1) Expand `StopDetails` to carry `routeIds: [String]` for all lines serving the station. (2) Render stacked horizontal line badge circles in the sheet header (e.g., `[N] [Q] [R] [W]`). (3) **Live Arrivals:** Unified chronological stream across all sibling routes from shared GTFS-RT feed, with individual line badges per arrival row. (4) **Full Timetable:** Add horizontal route pill selector strip (`[All] [R] [W]`) to filter `DepartureMatrixView` by specific line. Ensure `TransitRealtimeService.parseFeedMessage` does not filter out sibling `tripRouteId` values. | **M** | ✅ Done |
| **K.4** | **WK4-BUS-TERMINAL-NAMES** | **Bus Terminal Name Resolution via Multi-Tier SQLite Hierarchical Lookup:** In `fetchStopDetails`, implement 3-tier name resolution: (1) Primary `stop_name` from `transit.stops WHERE stop_id = ?`. (2) If empty/generic, join `parent_station` and pull parent `stop_name` (`SELECT stop_name FROM transit.stops WHERE stop_id = (SELECT parent_station ...)`). (3) Offline cross-street intersection fallback from local spatial DB if both tiers fail. Verify `derivee_transit.sqlite` hydration pipeline populates terminal-level `stop_name` and `parent_station` columns correctly. | **S** | ✅ Done |
| **K.5** | **WK5-DIRECTION-GREYING** | **Grey Out Unavailable Direction in Full Timetable:** In `DepartureMatrixView`, check `timetableSchedule` for records in each `directionId`. If a direction has zero scheduled departures, render its segmented control tab as `.disabled(true)` with `.opacity(0.35)` and `(No Service)` label suffix. Auto-select the valid direction on appear. Prevent user selection of empty direction tabs. | **XS** | ✅ Done |
| **K.6** | **WK6-EDGE-HARDENING-AND-MULTI-CITY-RFC** | **Immediate Camera Edge Hardening & Multi-City Architecture RFC:** (1) **Immediate fix:** Tighten `CameraBounds.rubberBandMargin` from `0.35` (~38km) to `0.05` (~5km) with fast `.easeOut` rollback damping, making edge-peeking past the fog shadow impossible. Zero performance cost (single float constant change). (2) **Architecture RFC:** Author `docs/multi-city.md` specifying: GPS-triggered city detection via `CLGeocoder.reverseGeocodeLocation`, user prompt flow ("Exploring [City]? Download Transit Pack"), Cloudflare R2 city pack bundle format (`transit.sqlite` + `subway.geojson` + `city_config.json`), dynamic `CameraBounds` loading from active city pack, and `ATTACH DATABASE` mounting strategy for per-city transit databases. **Implementation deferred to Wave L.** | **M** | ✅ Done |
| **K.7** | **WK7-PAST-DEPARTURES-FILTER** | **Filter Departed Trains & Multi-Hour Timetable Live Reconciliation:** (1) **Absolute-Minute Live Reconciler:** Replace flawed `(currentMinute + arr.minutes) % 60` modulo math in `DepartureMatrixView.reconciledRecords` with absolute minutes-from-midnight 1-to-1 matching across active and upcoming hours (current hour + next 1–2 hours, $\pm 10\text{m}$ tolerance), eliminating cross-hour wrapping bugs where a 12:03 train attached a `37m` badge to an 11:03 past departure. (2) **Past Departure Dimming:** Visually dim departed schedule pills (`hour < currentHour` or `hour == currentHour && minute < currentMinute`) with `.opacity(0.35)` and disabled styling. (3) **Delay-Aware Liveness:** Delayed departures with past scheduled times remain active in the timetable with live $\Delta t$ and delay badges (`+Xm`) until their estimated live arrival time passes ($t_{\text{estimated}} < t_{\text{now}}$). (4) **30s Boarding Grace Period & Live Pruning:** In `TransitRealtimeService.parseFeedMessage` and `TransitRevealSheet`, maintain trains at platform as `0m / Boarding` for 30s ($0 \le \text{elapsed} < 30\text{s}$), then immediately purge ($\text{diffSec} < -30\text{s}$). (5) **Dynamic Live Pill Injection:** Dynamically insert unmatched ad-hoc GTFS-RT arrivals into their corresponding hour row with amber live borders. (6) Comprehensive unit and snapshot tests in `TransitRevealSheetTests`. | **S** | ✅ Done |
| **K.8** | **WK8-BUS-FALLBACK-HEADWAYS** | **Bus-Aware Headway & Directional Fallback Realism (B32 & One-Way Corridors):** (1) Map B32 terminals (*Long Island City - Queens Plaza* NB / *Williamsburg Bridge Plaza* SB) and Williamsburg bus routes in `TransitRealtimeService.resolveBusDestination`. (2) In `SpatialDatabaseManager.generateFallbackTimetable`, distinguish bus routes from subways: replace 3m rush-hour bursts (12–16 dep/hr) with realistic 15–30m bus headways (2–3 dep/hr for local routes, 4–7 dep/hr for SBS/trunks). (3) Add one-way corridor detection for Kent Av / Wythe Av in `generateFallbackAvailableDirections` to eliminate phantom reverse-direction departures on one-way streets. (4) Align `generateFallbackHeadways` (15–25m) and `generateFallbackHourlyReliability` with bus metrics. | **S** | ✅ Done |

### 🌍 Multi-City Architecture (Wave L)

> [!NOTE]
> **Gated on:** Wave K.6 (`docs/multi-city.md` RFC) shipped. Wave L is architected across **4 parallel execution tracks** (Tracks A, B, C, D) that can be developed concurrently across sub-agents / developers.
> - **Track A (Tooling/Backend):** Go / Python CLI & GIS data compilers (independent of Xcode).
> - **Track B (Storage/Core):** iOS GRDB SQLite hot-swap barrier, dynamic bounds, and H3 coordinate routing.
> - **Track C (UI/UX):** SwiftUI prompt sheets, city selector, settings storage manager, and timetable bitmask navigators.
> - **Track D (Cartography):** MapLibre dynamic GeoJSON loaders, multi-modal casing styles, and fog cache handshake.
> 
> First non-NYC target city: **Boston (MBTA)** with static multi-modal GTFS (Subway, Green Line LRT, Silver Line BRT, Harbor Ferries). Multi-city asset distribution is engineered for 100% free-tier compliance across Cloudflare R2 and Oracle Cloud up to 100+ metros (see [docs/multi-city.md §7.3](file:///Volumes/T7ssd/derivee/docs/multi-city.md#73-free-tier-capacity--100-city-scaling-analysis)).

#### Track A: Data & GIS Compilation Tooling (Go / CLI / Offline)
| Wave | Task ID | Title | Size | Status |
|:---:|:---:|:---|:---:|:---:|
| **L-A.1** | **WLA1-GTFS-COMPACTION** | **Static GTFS 14-Day Calendar Compactor, Station Resolution & Pre-Compiled Statistics:** (1) Implement `scheduled_hourly_patterns` schema in `transit.sqlite` with `service_mask uint16` ($\pm 7\text{d}$ rolling window relative to compilation anchor $T_0$, bit 7 = today), `baseline_days_of_week uint8` (7-bit fallback for stale packs), `minute_offsets` string, and single `idx_patterns_lookup` index, shrinking DB size from 110MB to **3.8MB uncompressed** (<1.2MB .zst, 0.12ms fetch latency). (2) Build `stop_resolution` table (`WITHOUT ROWID`) with reflexive transitive closure across GTFS `stops.txt` parent-child hierarchy for $\mathcal{O}(1)$ platform disambiguation and reverse lookup. (3) Universal build-time distance-based linear interpolation for `timepoint = 0` and headway expansion (`frequencies.txt`). (4) **Pre-compiled query optimizer statistics:** Observer runs `PRAGMA analysis_limit = 1000; ANALYZE; PRAGMA optimize(0x10000); VACUUM;` embedding `sqlite_stat1` into distributed `transit.sqlite` before Zstandard compression. (5) Define `city_config.json` schema and `cities.json` remote manifest format. (6) Package default bundled NYC pack (`city-nyc.pack.zst`). | **M** | ✅ Done |
| **L-A.2** | **WLA2-ARC-TOPOLOGY** | **Planar Arc-Topology Visvalingam-Whyatt Simplification Engine:** (1) Build topology graph from GTFS `shapes.txt` locking junction nodes ($A = \infty$) at route intersections and terminals. (2) Simplify each Arc via iterative elimination of smallest effective triangle area with mode-adaptive thresholds ($\approx 10^{-9}\text{ deg}^2$ subway, $5 \times 10^{-9}$ LRT, $10^{-8}$ ferry, $5 \times 10^{-8}$ commuter rail), guaranteeing zero Z-fighting across overlapping routes in MapLibre. (3) Emit normalized `transit-lines.geojson` for bundled NYC pack. | **M** | ✅ Done |
| **L-A.3** | **WLA3-GIS-BRIDGES** | **GIS OSM Pedestrian Bridge Preservation Pipeline:** (1) Implement boolean geographic subtraction script: $\text{Walkable\_Mask} = (\text{Neighborhood} \setminus \text{Water}) \cup \text{Pedestrian\_Bridges}$. (2) Query OpenStreetMap for pedestrian-accessible bridges (`bridge=yes` with `highway=footway | cycleway | pedestrian | primary/secondary with sidewalk`) and re-add them after water subtraction to ensure 100% completion is possible for waterfront neighborhoods. | **S** | ✅ Done |
| **L-A.4** | **WLA4-BOSTON-MBTA-PACK** | **First Non-NYC Multi-Modal Pack: Boston (MBTA) & OCI Ingestion:** (1) Ingest MBTA static GTFS via Observer with 3-tier delta checking. (2) Build `transit.sqlite` (Subway Red/Orange/Blue + Green Line LRT `frequencies.txt` expansion + Silver Line BRT + Charlestown/Hingham Ferries). (3) Build `stop_resolution` and pre-compile `sqlite_stat1`. (4) Generate `transit-lines.geojson` via Arc-Topology engine. (5) Author `city_config.json` for Boston metro envelope with structured `realtimeEndpoints` for MBTA multi-feed (subway, bus, Green Line, ferry). (6) OSM bridge ingestion (Longfellow, Harvard, Zakim). (7) Package `city-bos.pack.zst`, upload to Cloudflare R2, update `cities.json` manifest. | **M** | ✅ Done |

#### Track B: iOS Core Storage & Spatial Engine (Swift / GRDB / H3)
| Wave | Task ID | Title | Size | Status |
|:---:|:---:|:---|:---:|:---:|
| **L-B.1** | **WLB1-CITY-PACK-MANAGER** | **`CityPackManager` & Zstd Unpacking Engine:** Implement `CityPackManager` in Swift: Zstandard decompression via native `libcompression`, atomic extraction to `~/Documents/CityPacks/{slug}/`, integrity verification via SHA-256 hash, remote `cities.json` manifest fetcher, and first-launch unpack of bundled `city-nyc.pack.zst` (<200ms, zero network dependency). | **M** | ✅ Done |
| **L-B.2** | **WLB2-DYNAMIC-BOUNDS-MIGRATION** | **Dynamic Camera Bounds, Schema Migration & Land-Only Water Fog:** (1) Refactor `CameraBounds` to load bounds dynamically from active `CityConfig`. (2) Create per-city hex tables (`explored_hexes_{slug}`) in `SpatialDatabaseManager`. (3) Zero-downtime schema migration: `ALTER TABLE explored_hexes RENAME TO explored_hexes_nyc;` on upgrade. (4) Wire `SpatialStore` to read from active city's hex table via dynamic table name. (5) Dynamic fog bounding polygon from `activeConfig.bounds`. (6) **Strict Land-Only Fog Policy** with quiet water gliding: GPS puck glides over dark water during ferry crossings, clearing fog at piers and landmass only. | **M** | ✅ Done |
| **L-B.3** | **WLB3-TRANSIT-HOT-SWAP** | **Coordinated Two-Phase Transit DB Hot-Swap & Coordinate-Routed Tracking:** (1) Implement **Coordinated Two-Phase Barrier**: Phase 1 (`prepareForCitySwap`) cancels `TransitRealtimeService` feed polling, pauses `NearbyBusesCapsule` spatial scans, auto-dismisses `TransitRevealSheet`. Phase 2 invokes `dbPool.releaseMemory()` to drain prepared statements across reader connections, then executes `DETACH DATABASE transit` + `ATTACH DATABASE` inside serial GRDB `dbWriter.writeWithoutTransaction` write barrier, preventing iOS `0xdead10cc` background termination. (2) Post-swap `PRAGMA transit.optimize;` to warm optimizer stats. (3) **Coordinate-routed background tracking:** live GPS fixes route to the correct `explored_hexes_{slug}` table based on bounding-box math regardless of which city is actively viewed in the UI. | **M** | ✅ Done |

#### Track C: SwiftUI UI & Experience Components (SwiftUI / State)
| Wave | Task ID | Title | Size | Status |
|:---:|:---:|:---|:---:|:---:|
| **L-C.1** | **WLC1-CITY-PROMPT-SHEET** | **GPS City Detection, Download Prompt Sheet & Silent Auto-Switch Toast:** (1) Fast offline bounding-box check against cached `cities.json` + `CLGeocoder` fallback for ambiguous zones. (2) Non-blocking `CityDownloadPromptSheet` bottom sheet with byte counter progress, `[ Download Now ]` / `[ Not Now ]`, and 7-day nag snooze. (3) Silent auto-switch 3s toast for installed packs (*"Welcome to Boston • Switched active city"*). (4) Fallback ambient tracking for declined/offline cities under generic fog envelope. | **M** | ✅ Done |
| **L-C.2** | **WLC2-CITY-SELECTOR-STATS** | **Screen 3 Multi-City Selector & All Metros Summary:** (1) Screen 3 frosted-glass menu pill (`[ 🟢 NYC ▾ ]`) with per-city stats, leaderboard, and journal milestones. (2) "All Metros Summary" lifetime totals mode. (3) "View on Map" city switch action. (4) Smart multi-city GPX import with bounding-box auto-partitioning into `explored_hexes_{slug}` in a single SQLite transaction. | **M** | ✅ Done |
| **L-C.3** | **WLC3-STORAGE-MANAGER** | **`Settings > Cities & Storage` Manager:** (1) Installed vs available cities breakdown. (2) Transparent disk footprint breakdown (compressed download vs uncompressed on-disk size). (3) Update available badges when newer timetables publish to R2. (4) **Decoupled deletion:** deletes static assets (`~/Documents/CityPacks/{slug}/`) while permanently preserving `explored_hexes_{slug}` in SQLite. (5) NYC Core Metro deletion protection. (6) Dynamic agency attributions from `city_config.json`. | **M** | ✅ Done |
| **L-C.4** | **WLC4-TIMETABLE-RECONCILER** | **$\pm 7$ Day Timetable Navigation, Circular Distance Reconciler & ScheduleRelationship Badges:** (1) Bitwise future day evaluation in `DepartureMatrixView` via `(service_mask & (1 << day_offset)) != 0` (<0.12ms). (2) **Circular Modular Distance Matching** for live GTFS-RT Protobuf arrivals across midnight boundaries ($\tau = 10\text{m}$ rail/ferry, $\tau = 15\text{m}$ bus). (3) Past days show Observed Reality Replay from `stop_events` (or honest scheduled fallback with banner). (4) **GTFS-RT `ScheduleRelationship` Visual Treatments:** In-situ rendering for `CANCELED` (0.4 opacity strikethrough + red badge), `ADDED` (bold + accent badge), `UNSCHEDULED` (italic + LIVE pulse), `DUPLICATED` (merged). | **M** | ✅ Done |

#### Track D: MapLibre Cartography Layer (Swift / MapLibre Native)
| Wave | Task ID | Title | Size | Status |
|:---:|:---:|:---|:---:|:---:|
| **L-D.1** | **WLD1-GEOJSON-LOADER** | **Dynamic `MLNShapeSource` Multi-Modal Transit Loader:** (1) Retire static `MtaSubwayNetworkData.swift`. (2) Implement dynamic `MLNShapeSource` line loader in `MapView.Coordinator` reading `transit-lines.geojson` from the active city pack. | **M** | ✅ Done |
| **L-D.2** | **WLD2-MODAL-STYLING** | **4-Tier Extended GTFS (HVT) Modal Cartography & Badging:** (1) Modal normalization into 4 visual styling priorities: Subway & PATH (6px light silver casing + 4px line), Light Rail (4px line + dashed casing), BRT/Bus capillary lens ($z \ge 14.5$), Maritime Ferry (2.5pt dashed cyan line over water with pier landing pins). (2) Multi-modal capsule badging in `TransitRevealSheet` data-driven from `transit.routes`. | **S** | ✅ Done |
| **L-D.3** | **WLD3-FOG-CACHE-HANDSHAKE** | **MapLibre Fog Mesh Cache Invalidation & Viewport Handshake:** Assign newly initialized `MLNShapeCollectionFeature` with updated coordinate arrays on city switch (preventing GPU mesh reuse), coordinated synchronously on `@MainActor` with camera transition (`mapView.setCenter`) to eliminate intermediate rendering glitches. | **S** | ✅ Done |

### 🧭 Navigation Ergonomics & Realtime Ground Truth (Wave M)

> [!NOTE]
> **Post-Wave L Field Hardening.** Resolves realtime status fidelity at trip terminals, sheet scroll priority conflicts, ambient dismissal inconsistencies, and unifies spatial orientation controls into a bottom-right cluster.

| Wave | Task ID | Title | Size | Status |
|:---:|:---:|:---|:---:|:---:|
| **M.1** | **WM1-TERMINUS-DWELL** | **GTFS-RT Vehicle Stop Status & Terminus Dwell Ground Truth:** Cross-reference `VehiclePosition.VehicleStopStatus` (`STOPPED_AT`, `INCOMING_AT`, `IN_TRANSIT_TO`) and initial stop sequence in `TransitRealtimeService`. Render dwelling vehicles at initial origin terminal as `"At Terminus"` / `"Scheduled"` instead of active `"x stops away"` until the vehicle physically transitions to `IN_TRANSIT_TO` or passes sequence 1. | **S** | ✅ Done |
| **M.2** | **WM2-SHEET-SCROLL-PRIORITY** | **Sheet Scroll Interaction & Hour Picker Gesture Disambiguation:** Apply `.presentationContentInteraction(.scrolls)` and `.scrollBounceBehavior(.basedOnSize)` to `TransitMatrixInspectorView`, `TripLedgerView`, and inspector sub-sheets. Prevent native bottom sheet interactive drag-to-dismiss from intercepting vertical swipes on scrollable reliability metrics and timetable views. | **XS** | ✅ Done |
| **M.3** | **WM3-AMBIENT-MAP-DISMISSAL** | **Ambient Map Dismissal Contract ("Map is the UI" for Overlays):** In `MapView.Coordinator.handleMapTap`, handle ambient taps outside transit POI features (`closest == nil`) by collapsing active floating lenses (`NearbyBusesCapsule`) and dismissing transient toast banners. Auto-collapse quick lens capsules on map gesture pan/drag (`mapViewRegionWillChange`). | **S** | ✅ Done |
| **M.4** | **WM4-ORIENTATION-CLUSTER** | **Bottom-Right Navigation Orientation Cluster:** Relocate native MapLibre compass needle to `.bottomRight` directly stacked above the 50×50 `RecenterFAB` (`x: 20pt`, `y: 102pt + safeAreaInsets.bottom`). Preserves 120Hz native bearing animation, auto-fade when North-Up, and tap-to-reorient with brand-aligned `ApertureCompassNeedle`. | **XS** | ✅ Done |

### 🏙️ Multi-City Pack Hardening & Global Fog Architecture (Wave M.5)

> [!NOTE]
> **Field Audit & Experience Polish.** Resolves fog bounding box rectangular cutoffs with a global world mask, eliminates single-city neighborhood data leakage during remote city switching, compiles and attaches per-city neighborhood exploration boundaries, deep-links city management navigation, and streamlines 1-tap city pack downloads with reactive state synchronization.
>
> **Modular Agent Scope:** Each sub-wave is self-contained with dedicated test coverage to allow isolated agent auditing.

| Wave | Task ID | Title | Size | Status |
|:---:|:---:|:---|:---:|:---:|
| **M.5.1** | **WM5.1-GLOBAL-FOG** | **Global World Fog Mask Architecture (World Polygon & Seamless Apertures):** Replace localized 30km×30km per-city bounding box with a global world outer polygon `[(-85.0511, -179.999), (85.0511, -179.999), (85.0511, 179.999), (-85.0511, 179.999), (-85.0511, -179.999)]` in CW winding order. Explored hexes anywhere on earth dissolve into interior aperture cutouts with golden illuminated borders. Eliminates artificial rectangular fog edges and border lines across city margins. | **S** | ✅ Done |
| **M.5.2** | **WM5.2-CITY-SWITCH-NAV** | **Multi-City Navigation & Center Coordinate Disambiguation:** Ensure switching active city (or tapping "View on Map") targets `config.center.coordinate` (e.g. Boston Common `42.3601, -71.0589`) instead of clamped out-of-bounds coordinates. Graceful empty state handling for cities without compiled neighborhood boundaries. | **S** | ✅ Done |
| **M.5.3** | **WM5.3-MANAGE-CITIES-DEEPLINK** | **"Manage Cities" Deep-Link & Direct Storage Navigation:** Update "Manage Cities..." in `CitySelectorPill` to navigate directly to `CitiesStorageManagerView` (or deep-link via `ScrollViewReader` with `#citiesStorage` anchor in `SettingsView`) instead of landing on top of general Settings. | **XS** | ✅ Done |
| **M.5.4** | **WM5.4-CITY-CATALOG-DISCOVERY** | **City Pack Cloud Catalog Discovery, 1-Tap Download & State Sync:** Add 1-tap download buttons with live progress on uninstalled cards in `AllMetrosSummaryView` and "Available to Download" menu items in `CitySelectorPill`. Call `CityDetectionService.markCityInstalled` upon download completion in `CitiesStorageManagerView` for instant state synchronization across all selectors. Add "Switch Active Metro" button in `CitiesStorageManagerView`. | **S** | ✅ Done |
| **M.5.5** | **WM5.5-MULTI-CITY-NEIGHBORHOODS** | **Multi-City Neighborhood GIS Compiler, Pack Bundling & Dynamic Attachment:** (1) Ingest Boston neighborhood boundaries via `scripts/generate_neighborhood_stats.py` with boolean water clipping & bridge preservation (`Walkable_Mask = (Neighborhood \ Water) ∪ Bridges`). (2) Package `neighborhood.sqlite` (or embed `neighborhood_stats` / `neighborhood_hexes` tables into `transit.sqlite`) in `city-{slug}.pack.zst`. (3) Wire `SpatialDatabaseManager` to dynamically mount active city neighborhood data during the two-phase swap barrier. (4) Render live per-city neighborhood exploration progression in `StatsView`. | **M** | ✅ Done |


### 🚀 On-Device Multimodal Routing & Reliability Engine (Wave N)

> [!NOTE]
> **Gated on:** Wave M (field hardening) complete. Wave N introduces an **on-device C++ Hybrid RAPTOR routing engine** with Swift interop, ULTRA precomputed transfer shortcuts, real-time GBFS micro-mobility integration, Observer historical slot profiling, 120Hz immediate-mode Canvas, and multimodal cognitive UX architecture.
>
> **Parallel Execution:** Wave N is architected across **4 parallel tracks** (A, B, C, D) that can be developed concurrently:
> - **Track A (Observer / Go / CLI):** OSM PBF extraction, ULTRA shortcut precomputation, RAPTOR binary compilation, Service Alerts ingestion & 15-min origin dispatch slot profiling.
> - **Track B (C++ Engine / Swift):** Swift-C++ interop scaffold, Hybrid RAPTOR core algorithm (0–45m real-time active trains + frequency expansion beyond), dynamic disruption bitmask, Pareto evaluation.
> - **Track C (Dynamic Data / GRDB):** GBFS station sync service & multi-modal dock gating, `service_disruptions` & `trip_slot_profiles` integration, circular midnight delay math.
> - **Track D (SwiftUI / Canvas / Multimodal UX):** Predictive route comparison cards with confidence bands, Train Inspector sheet, Smart Zoom station badges, 120Hz Canvas, and Doc 14 UX tightening (3-tier GTFS-RT confidence, subterranean exit mapping, train car positioning, landmark walking guidance, dynamic GBFS dock gating, 15%/50%/90% bottom sheet ergonomics).

#### Track A: Observer Data Compilers & Extraction (Go / Python)
| Wave | Task ID | Title | Size | Status |
|:---:|:---:|:---|:---:|:---:|
| **N-A.1** | **WNA1-OSM-EXTRACTOR** | **Go Observer OSM PBF Quantized Graph Extractor:** Stream PBF nodes/ways with `github.com/qedus/osmpbf`. Quantize coordinates to fixed-point `int32` ($\times 10^7$). Strip OSM metadata. Extract walkable/cycleable network into compact adjacency list with `EdgeFlags` (bitmask for Walkable, Wheelchair, Steps, Elevator). Emit `walk_graph.bin` (<25 MB). | **M** | ✅ Done |
| **N-A.2** | **WNA2-ULTRA-SHORTCUTS** | **ULTRA Transfer Shortcut Precomputer:** Bounded one-to-many Dijkstra over quantized walk graph ($d_{\max} = 1.2\text{km}$). Compute Pareto-optimal transfer shortcuts between transit stops. Output Compressed Sparse Row (CSR) `ultra_transfers.csr` (`stop_offsets uint32`, `target_stop uint32`, `distance_m uint16`, `flags uint8`). | **L** | ✅ Done |
| **N-A.3** | **WNA3-RAPTOR-COMPILER** | **Binary RAPTOR Timetable Compiler (`timetable.bin`):** Compile GTFS static into zero-copy AoS packed timetable binary: `StopTime` (12B), `Trip` (8B), `Route` (12B), `Stop` (20B), `Transfer` (8B). 128-byte header with magic `0x44525631` (`DRV1`), 16 KiB page-aligned sections. Total NYC MTA footprint ~17.58 MB. | **M** | ✅ Done |
| **N-A.4** | **WNA4-ALERTS-SLOTS** | **Observer Historical Profiling & GTFS-RT Service Alerts Ingestion:** (1) Service Alerts ingestion storing disruption intervals with route/stop bitmasks. (2) 15-minute origin dispatch slot profiling calculating scheduled headway ($SWT$), observed headway ($AWT$), excess wait time ($EWT$), and on-time performance ($OTP$) over rolling 168h windows. Output `trip_slot_profiles` table. | **M** | ✅ Done |
| **N-A.5** | **WNA5-CITY-PACK-V2** | **City Pack v2 Format Extension:** Update city pack directory structure to include `timetable.bin`, `ultra_transfers.csr`, `walk_graph.bin` alongside existing `transit.sqlite` and `transit-lines.geojson`. Bump `city_config.json` version to `2`. Regenerate and upload NYC + Boston packs to R2. | **M** | ✅ Done |
| **N-A.6** | **WNA6-WALK-GRAPH-CSR** | **Offline Walk Graph CSR Compiler & R-Tree Spatial Index:** Precompute pedestrian walk graph into forward CSR layout (`walk_offsets.bin` + `walk_edges.bin`) and FlatGeobuf/packed R-Tree (`walk_rtree.bin`) in Go Observer. Zero heap allocation during Dijkstra exploration. | **M** | ✅ Done |

#### Track B: On-Device C++ Routing Core & Swift Interop (C++20 / Swift)
| Wave | Task ID | Title | Size | Status |
|:---:|:---:|:---|:---:|:---:|
| **N-B.1** | **WNB1-CPP-INTEROP-SCAFFOLD** | **Swift C++20 Interop Scaffold & Memory-Mapped Timetable Reader:** Create `DeriveeCore` framework target with C++20 standard (`-cxx-interoperability-mode=default`). Zero-copy `mmap` loader for `timetable.bin` and `ultra_transfers.csr` validating 128-byte headers. Native Swift wrapper types with direct C++ struct access. | **M** | ✅ Done |
| **N-B.2** | **WNB2-HYBRID-RAPTOR-CORE** | **Hybrid RAPTOR Core Algorithm:** Standard McRAPTOR round-based Pareto exploration ($K \le 4$ rounds). 0–45 min lookahead: scan live active vehicle positions with Euclidean modulo delay arithmetic. 45+ min lookahead: expand frequency intervals from `scheduled_hourly_patterns`. Scan CSR `ultra_transfers` during round relaxation. Bounded runtime: <15ms on Apple Silicon. | **L** | ✅ Done |
| **N-B.3** | **WNB3-DISRUPTION-BITMASK** | **Dynamic Disruption Masking:** Apply active GTFS-RT service disruptions as bitmasks over routes/trips during RAPTOR route scanning. Instant skip for canceled trips (`ScheduleRelationship.CANCELED`) or suspended route segments with zero timetable re-allocation. | **S** | ✅ Done |
| **N-B.4** | **WNB4-PARETO-OPTIMIZATION** | **4D Pareto Optimization & Profile Evaluator:** Multi-criteria journey evaluation across 4 dimensions: (1) Arrival time $\tau$, (2) Number of transfers $k$, (3) Total walking/biking distance $d_{\text{walk}}$, (4) Journey Reliability Score $JRS = \sum \log(1 + EWT_i)$. Return non-dominated Pareto frontier journeys to Swift. | **M** | ✅ Done |
| **N-B.5** | **WNB5-BOUNDED-WALK-ROUTER** | **Bounded One-to-Many Walk Router:** Bounded A* / Dijkstra over quantized walk graph for initial (origin $\to$ nearby stops, $r \le 800\text{m}$) and final (destination stops $\to$ target, $r \le 800\text{m}$) transfer legs. Prune search with Euclidean distance heuristic. Budget: <3ms execution. | **M** | ✅ Done |
| **N-B.6** | **WNB6-SWIFT-ROUTING-BRIDGE** | **`RoutingEngineBridge` & Journey Planner Actor:** `@Observable` Swift actor managing C++ engine lifecycle, thread-safe background execution at `.userInitiated` priority, and translating Pareto result journeys into rich `JourneyItinerary` Swift models. | **M** | ✅ Done |
| **N-B.7** | **WNB7-ENERGY-EVALUATOR** | **Micro-Climate & Thermal Comfort Energy Weighting ($\text{PET}$ Model):** Integrate building shadow polygons and tree canopy cover into walking edge weights. Dynamic summer shaded vs winter sunlit route options. | **S** | ✅ Done |

#### Track C: Dynamic Data Layer (Swift / GRDB)
| Wave | Task ID | Title | Size | Status |
|:---:|:---:|:---|:---:|:---:|
| **N-C.1** | **WNC1-GBFS-SYNC** | **`GBFSSyncService` & Multi-Modal Dock Validation:** Implement `GBFSSyncService` with `Task`-based 30s async polling. Ephemeral `gbfs_cache.sqlite` (`DatabaseQueue`, `.userInitiated` QoS). Dynamic 3-tier dock availability gating product ($G(e) = g_{\text{pick}} \cdot g_{\text{drop}}$): $>3$ low risk, 1–2 moderate risk (pre-arm secondary fallback dock), 0 high risk (auto-reroute to dock within 3m walk). Staleness gate: 600s. | **M** | ✅ Done |
| **N-C.2** | **WNC2-RELIABILITY-ENGINE** | **`TransitDatabaseEngine` & Slot/Disruption Queries:** Implement async GRDB queries for `service_disruptions` (time-bounded calendar work) and `trip_slot_profiles` (15-min origin dispatch stats). Aggregates $SWT$, $AWT$, $EWT$, and $OTP$ over 168-hour rolling windows. | **M** | ✅ Done |
| **N-C.3** | **WNC3-CIRCULAR-TIME** | **`GTFSMidnightResolver` & Euclidean Modulo Circular Distance:** Implement `euclideanModulo(a, n) = (a % n + n) % n` for non-negative modular arithmetic. `calculateSignedCircularDelay` mapping GTFS-RT timestamps to signed $[-720, +720]$ minute offsets on the 1,440-minute clock face. `GTFSRealtimeStreamProcessor` actor for processing `StopTimeUpdate` payloads with midnight-safe delay computation. | **S** | ✅ Done |

#### Track D: UI, Visualization & Multimodal UX (SwiftUI / Canvas / Metal)
| Wave | Task ID | Title | Size | Status |
|:---:|:---:|:---|:---:|:---:|
| **N-D.1** | **WND1-DEPARTURE-CANVAS** | **120Hz Immediate-Mode `DepartureMatrixCanvas`:** Metal-backed `Canvas(rendersAsynchronously: true)` + `.drawingGroup()`. Flat contiguous `[Float]` buffer (4,320 elements: $24\text{h} \times 60\text{m} \times 3$ percentiles). Index stride: $\text{Offset}(h, m, p) = (h \times 60 + m) \times 3 + p$. Direct RGBA interpolation avoiding SwiftUI modifier chains. Target: 0.8ms–1.9ms per frame (< 8.33ms 120Hz budget). | **M** | ✅ Done |
| **N-D.2** | **WND2-ROUTE-CARDS** | **Predictive Route Comparison Cards, 3-Tier Confidence Badges & Multi-Profile Selector:** `JourneyItinerary` result cards showing arrival time with P10–P90 confidence intervals, 3-tier GTFS-RT confidence badges (`Verified` live pulsing dot, `Estimated` stale tag, `Static` schedule fallback), total cost/distance/time summaries per mode, transfer count badges, walking/biking effort, and inline disruption callouts. Multi-profile selector (`[Most Reliable]`, `[Fastest]`, `[Fewest Transfers]`, `[Step-Free]`, `[Multi-Modal Bike + Rail]`). | **M** | ✅ Done |
| **N-D.3** | **WND3-CONFIDENCE-BANDS** | **P10/P50/P90 Confidence Interval Visualization:** Render percentile wait-time bands from `[Float]` buffer using `Canvas` or `Path`-based area fills. Statistical variance disutility coloring: narrow bands (reliable, green tint) vs wide bands (unreliable, amber/red tint). Tap-to-inspect detail overlay. | **S** | ✅ Done |
| **N-D.4** | **WND4-TRAIN-INSPECTOR-SMART-ZOOM** | **Deep Train Inspector, Car Exit Badges & Smart Zoom Station Bullets:** (1) Train Inspector sub-sheet on tapping live arrival row (Track Thermometer, GTFS-RT `occupancy_status` / crowd fallback, 15-min slot regularity card, map synchronizer). (2) Platform train car recommendation badges (`Board near front/middle/rear car` for transfer & egress alignment) and deterministic subterranean exit codes (e.g. `Exit 4B - NW Corner 42nd & Broadway`). (3) Smart Zoom MapLibre station symbol layer resolving discrete route bullets (`[4][5][6]` vs `[6]`) at $z \ge 14.5$. | **M** | ✅ Done |
| **N-D.5** | **WND5-THUMB-ZONE-DETENTS** | **Standardized 3-Tier Bottom Sheet Ergonomics & One-Handed Thumb Zone:** Standardize navigation sheets across 3 ergonomic detents: `15%` (Collapsed Peek for next upcoming step), `50%` (Half-Screen Step-by-Step Guidance), and `90%` (Full-Screen Expanded Timetable / Alternatives). Floating hero map viewport preservation. Primary action buttons (`Start Journey`, `Reroute`, `Unlock Bike`) anchored strictly in lower-third thumb zone. | **S** | ✅ Done |
| **N-D.6** | **WND6-LANDMARK-WALKING-DIRECTIONS** | **Landmark-Anchored Walking Guidance & Microclimate Shaded Routes:** Replace numerical distance-only prompts ("turn in 300ft") with 3–5 salient visual landmark anchors per walking route ("Turn left after the red brick pharmacy"). Multi-attribute cost weighting factoring urban tree canopy cover and building shadow vectors ($\text{PET}$ cost model) for shaded cool walking routes. | **M** | ✅ Done |
| **N-D.6.1** | **WND6.1-NATURAL-GUIDANCE-BLOCKS-LIGHTS** | **Natural Guidance Intermediate Reminders (City Blocks & Traffic Signals):** Add natural intermediate route reminders inspired by Apple/Google Maps Natural Guidance: replace raw numerical metrics with city block counts ("In 3 blocks, turn left...", "In 5 blocks...") and intersection/traffic signal framing ("At the next light, turn left...", "After the next light, bear right...", "Continue straight for 4 blocks past the park"). Dynamically transition guidance text across foresight, approach, and imminent decision zones during active walking navigation. | **S** | Planned |
| **N-D.7** | **WND7-GBFS-DOCK-GATING-UI** | **Dynamic GBFS Dock Gating, E-Bike Battery SOC Overlays & Cycling Ergonomics:** Real-time 3-tier dock availability gating badges (>3 low risk, 1–2 moderate fallback pre-armed, 0 auto-reroute to nearest dock within 3m walk). E-bike state-of-charge (SOC %) overlays and usable range radiuses. Expanded 56×56pt touch targets and high-contrast WCAG AAA cycling HUD (0.5s glance window). | **M** | Planned |
| **N-D.8** | **WND8-LIVE-DYNAMIC-RECOVERY** | **Live Dynamic Recovery & Multimodal Live Activity / Dynamic Island:** Automated missed-connection detection via live GPS vs platform departure timestamps. Instant 1-tap recovery card suggesting alternate bus/bike/walk legs. Native iOS Live Activity and Dynamic Island trip progress tracking with transfer countdowns, step transitions, and subterranean exit guidance. | **M** | Planned |

### 🔮 Wave O: MetalFogEngine & GPU Spatial Rendering Pipeline

> [!NOTE]
> **Wave O Architecture:** Upgrades the fog rendering pipeline from MapLibre CPU geometry generation (`cellsToLinkedMultiPolygon` shape assignment) to a direct, hardware-accelerated **Metal in-pipeline custom style layer (`MLNCustomStyleLayer`)**. Built strictly on Research Docs 05–09 in [`docs/research/`](file:///Volumes/T7ssd/derivee/docs/research/).
>
> **Core Constraints & Invariants:**
> - **Zero-Lag VSync:** EPSG:3857 $\rightarrow$ Metal NDC Relative-to-Center (RTC) projection with 0-frame latency (Doc 05).
> - **GPU Memory Cap:** Open-addressing GPU hash table in shared `MTLBuffer` strictly $< 10\text{ MB}$ VRAM (Doc 06).
> - **Compositing & Label Legibility:** In-pipeline injection below `MLNSymbolStyleLayer` preserving text legibility (Doc 07).
> - **Anti-Aliasing & Glow:** 4-vertex full-screen quad fragment shader with screen-space derivative AA (`dfdx`/`dfdy`) and single-pass Electric Amber (`#FFB300`) analytical glow (Doc 09).
> - **Performance Target:** Headless 120 FPS CADisplayLink telemetry, $\text{P99} \le 8.33\text{ms}$, 0% CPU geometry time, $\text{RMSD} < 0.001$ visual parity (Doc 08).

| Wave | Task ID | Title | Size | Status |
|:---:|:---:|:---|:---:|:---:|
| **O.1** | **WO1-CAMERA-PROJECTION** | **Web Mercator to Metal NDC RTC Projection & VSync Engine (Doc 05):** Implement `MapProjectionMath` translating EPSG:3857 coordinates to Metal Normalized Device Coordinates (NDC) using Relative-to-Center (RTC) precision offsets ($S(z) = 512 \cdot 2^z$) mitigating float32 jitter at $z \ge 18$. Zero-lag CADisplayLink camera synchronization with MapLibre viewport. | **M** | Planned |
| **O.2** | **WO2-GPU-SPATIAL-HASH** | **Open-Addressing GPU Spatial Hash Table in `MTLBuffer` (Doc 06):** 16-byte aligned `H3HashSlot` and 64-byte `H3HashTableHeader` in shared `MTLBuffer` (<4.26 MB VRAM for 100k hexes, <10 MB budget). In-shader bitwise parent LOD aggregation (Res 11 $\rightarrow$ Res 10/9/8). `.storageModeShared` zero-copy CPU pointer writes. | **L** | Planned |
| **O.3** | **WO3-LAYER-INJECTION** | **In-Pipeline `MLNCustomStyleLayer` Metal Injection & Label Occlusion (Doc 07):** Direct `id<MTLRenderCommandEncoder>` reuse within MapLibre render pipeline. Z-index insertion below `MLNSymbolStyleLayer` preserving station/street label legibility with zero auxiliary texture overhead. | **M** | Planned |
| **O.4** | **WO4-MSL-QUAD-SHADERS** | **MSL Full-Screen Quad Fragment Pipeline, Derivative AA & Analytical Amber Glow (Doc 09):** 4-vertex full-screen quad vertex shader ($O(1)$ vertex load). Screen-space partial derivatives (`dfdx`, `dfdy`) for constant 1.0–1.5px boundary anti-aliasing across $z0 \dots z18$. Single-pass analytical Hermite glow ($I_{\text{glow}}(C)$) in Electric Amber (`#FFB300`) executing in $<0.3\text{ms}$ on Apple Silicon. | **M** | Planned |
| **O.5** | **WO5-120HZ-TELEMETRY** | **Empirical 120 FPS CADisplayLink Telemetry Suite & Visual Parity Tests (Doc 08):** Automated headless XCTest telemetry suite verifying locked $\ge 118\text{ FPS}$ (P99 $\le 8.33\text{ms}$), 0% CPU geometry time ($\le 0.05\text{ms}$ uniform write), and $\text{RMSD} < 0.001$ visual parity against MapLibre polygon reference. | **M** | Planned |

### Post-Ship (Completed Post-Launch Waves)

| Wave | Task ID | Title | Size | Status |
|:---:|:---:|:---|:---:|:---:|
| **11.7a** | **W11.7a-HEATMAP** | **24 × 7 Station Reliability Heatmap Matrix:** Replace `TransitSparklineView` with an immediate-mode SwiftUI `Canvas` rendering 168 cells ($24 \times 7$) in <1.2ms. Universal 6-tier Cividis CVD-safe colormap (`#00224E` → `#FDEA45`) mapping $OTP\%$. $51\text{pt} \times 44\text{pt}$ cell touch target math (Apple HIG). Tapping a cell opens Tier 2 inspector sheet displaying SF Mono readouts for $OTP\%$, Median Delay $\tilde{D}$, $P90$, Headway Variance $\sigma^2_{\Delta t}$, and $EWT$. **Gated on:** `stop_reliability_hourly` populated with $\ge 7$ days of data (or verified via deterministic test fixtures in `DeriveeTests`). | **M** | ✅ Done |
| **11.7b** | **W11.7b-DEPARTURES** | **Hour × Minute Departure Matrix & Timetable Inspector:** Add `[ Live Arrivals | Full Timetable ]` segmented control to `TransitRevealSheet` (Screen 2). Full 24-hour departure timetable with dynamic horizontal minute pills (`02, 08, 15, 22...`), line-colored branch/express badges, first/last departure boundary markers, real-time $\Delta t$ countdown overlays with pulsing dot, and alert delay badges (`+4m`). **Gated on:** `stop_events` actively populated + `W11.7a-HEATMAP` shipped. | **L** | ✅ Done |
| **11.7c** | **W11.7c-LIVE-PULSE** | **Live Transit Feed Radar Pulse & Instant Refresh Control:** (1) `LiveStatusBadge` with Electric Amber (`#FFB300`) breathing core dot + expanding radar ping (`1.0 → 1.8` scale) and graceful dimmed fallback to `SCHEDULED` when offline. (2) `CircularRefreshButton` with smooth 15s progress ring arc and $360^\circ$ spin animation on tap. (3) Generational polling loop cancellation preventing double-polling bursts on manual refresh. (4) Light haptic feedback (`UIImpactFeedbackGenerator`). (5) Unit and snapshot tests in `TransitRevealSheetTests`. | **S** | ✅ Done |
| — | W15-DYNAMIC-ISLAND | Dynamic Island Support for Stat Bar | S | ✅ Done |

---

## Testing Strategy & Rollout

Broadening the overall testing strategy across upcoming waves. We are adopting a **staggered approach** to ensure a solid foundation before building further UI:

### Phase 1–3: Complete ✅

All core engine, spatial math, transit hydration, snapshot, and live observation tests are implemented and passing across 9 test files (34 tests total, 0 skips). Test architecture uses cooperative polling (`while` loop + `RunLoop.current.run` + `Task.sleep`) for all `@Observable` assertions — legacy `XCTestExpectation` and `withObservationTracking` are banned.

All live `ValueObservation` → `recomputeFogShape()` reactivity tests (`SpatialStoreFogTests.swift` and `GRDBObservationTests.swift`) are actively verified and passing in CI.

### Phase 4: CI/CD Pipeline (Complete ✅)

The GitHub Actions CI/CD pipeline is active on `main`. The project embraces a solo "vibe coding" workflow: commits are pushed directly to `main` without Pull Requests, and the CI acts as a post-push safety net to prevent regressions, rather than a strict pre-merge blocker.

> [!WARNING]
> **CI Safety: `XCTSkip` Convention.** All sandbox-limited tests must use explicit `throw XCTSkip("Reason")`. The `disabled_` prefix convention is banned — if a future agent renames a test to "fix the gap," it will hang CI indefinitely. The `XCTSkip` convention is enforced and verified (see `SpatialStoreFogTests.swift:131`).
