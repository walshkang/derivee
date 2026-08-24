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
| **J.4** | **WJ4-BASEMAP-SWITCHER** | **Bundled Composite Style Basemap Switcher:** Local `composite_style.json` in app bundle with shared `maptiler_streets` vector source and dedicated theme layer groups (Day, Night, OLED, Transit). Runtime key injection. Crossfade themes via `MLNTransition(duration: 0.6)` layer opacity/color transitions on GPU — zero style destruction, zero source unmounting. | **M** | ✅ Done |
| **J.5** | **WJ5-CUSTOMIZATION-SETTINGS** | **Zero-Geometry Customization Settings (Screen 3 + `@AppStorage`):** Fog opacity slider (`0.60`–`0.98`) and hex/boundary borders via `MLNLineStyleLayer` attached directly to existing `fog-source` in `SettingsView`. `@AppStorage` persistence with `MLNTransition(duration: 0)` fragment shader updates — no polygon recomputation or DB queries. | **S** | ✅ Done |
| **J.6** | **WJ6-TRANSIT-NODE-TRACKING** | **Hybrid SwiftProtobuf Transit Sheet & Local Shape Fallback:** SPM `swift-protobuf` + pre-compiled `gtfs-realtime.pb.swift` models. Sheet-scoped 15s polling for live arrivals (cancelled on dismiss). Physical track/route geometries sourced from pre-hydrated local `derivee_transit.sqlite`. Dual-layer high-contrast route rendering (6px silver casing + 4px agency color). | **M** | ✅ Done |
| **J.7** | **WJ7-POI-GAMIFICATION** | **Dual-Sensory Discovery Loop & Categorized Milestone Journal:** Instant `UIImpactFeedbackGenerator(.light)` on GRDB insert + transient expanding `MLNCircleStyleLayer` pulse (0→80px, 1.2s fade) on the map. Screen 3 Exploration Journal with on-demand asynchronous GRDB aggregation (`dbWriter.read`) for categorized milestone progress cards (Transit Hubs, Neighborhoods, Landmarks). | **M** | ✅ Done |
| **J.8** | **WJ8-APERTURE-BRANDING** | **Unified Crystalline Aperture Rollout (AppIcon, FAB, Milestones & Live Activity):** (1) Generate Day/Night/iOS 18 Tinted `AppIcon.appiconset` vector assets. (2) Replace `person.crop.circle` in `ProfileFAB` with Variation A aperture micro-glyph in `.ultraThinMaterial`. (3) Upgrade Screen 0 Onboarding Gate with centered pulsing vector aperture during SQLite hydration. (4) Upgrade Screen 3 Exploration Journal with high-negative-space milestone cards and settings build signature. (5) Polish `TrackingLiveActivity` Dynamic Island compact leading micro-glyph and trailing distance metrics. (6) Style 120Hz native MapLibre compass needle in top-left matching brand identity. | **M** | ✅ Done |
| **J.9** | **WJ9-LIFECYCLE-HARDENING** | **Dynamic Island & Location Lifecycle Hardening on Force-Close:** Add `UIApplication.willTerminateNotification` observer in `AmbientTrackingEngine` to synchronously invalidate `CLBackgroundActivitySession` and end active `Activity<TrackingAttributes>`. Add rolling 2-minute `staleDate` fail-safe on `ActivityContent` and intra-hex distance heartbeat refresh. | **XS** | ✅ Done |
| **J.10** | **WJ10-DYNAMIC-ISLAND-CONTRACT** | **Decoupled Ambient Tracking & Dynamic Island Lifecycle Contract:** (1) Decouple Live Activity from mandatory background tracking with `@AppStorage("isLiveActivityEnabled")` sub-toggle under Settings > Tracking. (2) Shorten rolling `staleDate` to 45s so Dynamic Island auto-dismisses if app is killed. (3) Clean up all orphaned activities before requesting new ones. (4) Wire `derivee://progress` deep link via `.onOpenURL` to trigger map recenter and aperture pulse glow. (5) Comprehensive unit tests for toggle and lifecycle contracts. | **S** | ✅ Done |
| **J.11** | **WJ11-FOG-ISLANDS** | **Closed Loop Fog Islands via FogGeometry Composite Shapes:** Traverse interior `LinkedGeoLoop.next` holes within `LinkedGeoPolygon` clusters to extract unvisited center island polygons, reversing vertex coordinates for clockwise outer winding. Construct composite `MLNShapeCollection` containing the main bounding box polygon with interior cutout holes plus disjoint interior fog island polygons, accurately preserving unexplored city blocks encircled by closed-loop walks. | **S** | ✅ Done |
| **J.12** | **WJ12-LOCATION-FILTER** | **Multi-Stage Cold Start Location Filter & Contextual Drift Gate:** Implement `ColdStartLocationFilter` replacing raw speed gating with Rayleigh horizontal uncertainty bounding ($\le 25\text{m}$ for H3 Res 11), cache staleness check ($\le 5\text{s}$), 2-fix warmup state machine, and subway emergence discontinuity classifier ($\Delta t \ge 15\text{s}$). Resets baseline velocity jumps without dropping subway arrival emergence fixes. | **M** | ✅ Done |
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
| **K.5** | **WK5-DIRECTION-GREYING** | **Grey Out Unavailable Direction in Full Timetable:** In `DepartureMatrixView`, check `timetableSchedule` for records in each `directionId`. If a direction has zero scheduled departures, render its segmented control tab as `.disabled(true)` with `.opacity(0.35)` and `(No Service)` label suffix. Auto-select the valid direction on appear. Prevent user selection of empty direction tabs. | **XS** | Planned |
| **K.6** | **WK6-EDGE-HARDENING-AND-MULTI-CITY-RFC** | **Immediate Camera Edge Hardening & Multi-City Architecture RFC:** (1) **Immediate fix:** Tighten `CameraBounds.rubberBandMargin` from `0.35` (~38km) to `0.05` (~5km) with fast `.easeOut` rollback damping, making edge-peeking past the fog shadow impossible. Zero performance cost (single float constant change). (2) **Architecture RFC:** Author `docs/multi-city.md` specifying: GPS-triggered city detection via `CLGeocoder.reverseGeocodeLocation`, user prompt flow ("Exploring [City]? Download Transit Pack"), Cloudflare R2 city pack bundle format (`transit.sqlite` + `subway.geojson` + `city_config.json`), dynamic `CameraBounds` loading from active city pack, and `ATTACH DATABASE` mounting strategy for per-city transit databases. **Implementation deferred to Wave L.** | **M** | Planned |
| **K.7** | **WK7-PAST-DEPARTURES-FILTER** | **Filter Departed Trains & Multi-Hour Timetable Live Reconciliation:** (1) **Absolute-Minute Live Reconciler:** Replace flawed `(currentMinute + arr.minutes) % 60` modulo math in `DepartureMatrixView.reconciledRecords` with absolute minutes-from-midnight 1-to-1 matching across active and upcoming hours (current hour + next 1–2 hours, $\pm 10\text{m}$ tolerance), eliminating cross-hour wrapping bugs where a 12:03 train attached a `37m` badge to an 11:03 past departure. (2) **Past Departure Dimming:** Visually dim departed schedule pills (`hour < currentHour` or `hour == currentHour && minute < currentMinute`) with `.opacity(0.35)` and disabled styling. (3) **Delay-Aware Liveness:** Delayed departures with past scheduled times remain active in the timetable with live $\Delta t$ and delay badges (`+Xm`) until their estimated live arrival time passes ($t_{\text{estimated}} < t_{\text{now}}$). (4) **30s Boarding Grace Period & Live Pruning:** In `TransitRealtimeService.parseFeedMessage` and `TransitRevealSheet`, maintain trains at platform as `0m / Boarding` for 30s ($0 \le \text{elapsed} < 30\text{s}$), then immediately purge ($\text{diffSec} < -30\text{s}$). (5) **Dynamic Live Pill Injection:** Dynamically insert unmatched ad-hoc GTFS-RT arrivals into their corresponding hour row with amber live borders. (6) Comprehensive unit and snapshot tests in `TransitRevealSheetTests`. | **S** | Planned |

### 🌍 Multi-City Architecture (Wave L)

> [!NOTE]
> **Gated on:** Wave K.6 (`docs/multi-city.md` RFC) shipped. Each sub-wave executes sequentially. First non-NYC target city: **Boston (MBTA)** with static GTFS only (no live Observer reliability data).

| Wave | Task ID | Title | Size | Status |
|:---:|:---:|:---|:---:|:---:|
| **L.1** | **WL1-CITY-PACK-INFRA** | **City Pack Infrastructure & R2 Manifest:** (1) Define `city_config.json` schema: display name, slug, bounding box (4 coords), center coordinate, camera defaults (zoom/bearing), transit agency feed URLs, version hash. (2) Create `cities.json` manifest on Cloudflare R2 listing all available city packs with slug, display name, region, compressed size, and version. (3) Implement `CityPackManager` in Swift: Zstandard decompression via `libcompression`, atomic write to `~/Documents/CityPacks/{slug}/`, integrity verification via SHA-256 hash. (4) NYC ships as default bundled city pack — zero download required for existing users. | **M** | Deferred |
| **L.2** | **WL2-DYNAMIC-BOUNDS-FOG** | **Dynamic Camera Bounds & Per-City Fog:** (1) Refactor `CameraBounds` from hardcoded NYC constants to read `minLatitude/maxLatitude/minLongitude/maxLongitude` from the active `city_config.json`. (2) Create per-city hex tables (`explored_hexes_{slug}`) in `SpatialDatabaseManager`. (3) Wire `SpatialStore` to read from the active city's hex table via dynamic table name. (4) Generate fog bounding polygon from active city config bounds. (5) Ensure city-switch triggers full `recomputeFogShape()` with new bounds. | **M** | Deferred |
| **L.3** | **WL3-TRANSIT-HOT-SWAP** | **Transit DB Hot-Swap via ATTACH/DETACH:** (1) On city change, execute `DETACH DATABASE transit` followed by `ATTACH DATABASE '<city_pack_path>/transit.sqlite' AS transit`. (2) All existing `transit.*` queries (`fetchStopDetails`, `fetchStopEvents`, `fetchHeadwayData`, etc.) work unchanged. (3) Graceful empty-state when no transit pack installed: tapping a POI shows "Transit data not downloaded for this city" with download CTA. (4) Verify GRDB `ValueObservation` survives `DETACH`/`ATTACH` cycle without observation death. | **S** | Deferred |
| **L.4** | **WL4-GEOJSON-SUBWAY-LOADER** | **Dynamic GeoJSON Transit Network Loader & NYC Migration:** (1) Retire `MtaSubwayNetworkData.swift` (hardcoded Swift geometry struct). (2) Move NYC subway geometry into bundled city pack as `transit-lines.geojson`. (3) Implement dynamic `MLNShapeSource` loading: read GeoJSON from active city pack, parse route colors and line names from feature properties, inject into `subwayLinesSourceId` and casing layer. (4) Day/Night adaptive casing colors driven by theme, line colors from GeoJSON properties. (5) One code path for all cities — adding a city = adding a GeoJSON file to the pack. | **M** | Deferred |
| **L.5** | **WL5-CITY-DETECTION-UX** | **GPS City Detection & Download Prompt Sheet:** (1) On first valid GPS fix, `CLGeocoder.reverseGeocodeLocation` resolves city name. If no matching city pack installed, present download prompt. (2) Non-blocking bottom sheet: "It looks like you're exploring [City]. Download transit & map data? (≈38MB)" with `[Download Now]` and `[Not Now]`. (3) Download progress bar with byte counter and success checkmark animation. (4) If declined, dismiss sheet; re-prompt on next launch in that city. Subtle Settings badge for pending downloads. (5) >50km significant location change re-triggers detection in background. (6) Settings > Cities manager: list installed packs, download new ones, delete unused packs, view storage usage. | **M** | Deferred |
| **L.6** | **WL6-BOSTON-MBTA-PACK** | **First Non-NYC City Pack: Boston (MBTA):** (1) Download MBTA static GTFS from `https://cdn.mbta.com/MBTA_GTFS.zip`. (2) Build `transit.sqlite` via Observer's static GTFS hydration pipeline (stops, routes, stop_times). (3) Generate `transit-lines.geojson` from MBTA `shapes.txt` with T line colors. (4) Author `city_config.json` for Boston metro bounding box. (5) Package as `city-bos.pack.zst` and upload to R2. (6) Update `cities.json` manifest. (7) End-to-end field validation: install on device in NYC, fly/simulate to Boston, verify detection → prompt → download → fog swap → transit sheet. **No live Observer reliability data — static timetables only.** | **M** | Deferred |

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
