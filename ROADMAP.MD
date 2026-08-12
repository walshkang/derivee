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
| **I.3** | **WI3-FOG-TESTS** | **Cold-Start Fog Regression Tests** | **S** | ✅ Done (1 `XCTSkip`) |
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

## Testing Strategy & Rollout

Broadening the overall testing strategy across upcoming waves. We are adopting a **staggered approach** to ensure a solid foundation before building further UI:

### Phase 1–3: Complete ✅

All core engine, spatial math, transit hydration, and snapshot tests are implemented and passing across 9 test files (33 tests total). Test architecture uses cooperative polling (`while` loop + `RunLoop.current.run` + `Task.sleep`) for all `@Observable` assertions — legacy `XCTestExpectation` and `withObservationTracking` are banned.

**One `XCTSkip`:** `testNewlyDiscoveredHexTriggersFogShapeUpdate` in `SpatialStoreFogTests.swift` — the only test covering live `ValueObservation` → `recomputeFogShape()` reactivity. Skipped because GRDB's `ValueObservation` dispatch sources are not reliably deliverable in the XCTest sandbox. This is the riskiest untested path. Manual testing on-device remains the only validation for this pipeline.

### Phase 4: CI/CD Pipeline — see TEST-PHASE4 prompt below.

> [!WARNING]
> **CI Safety: `XCTSkip` Convention.** All sandbox-limited tests must use explicit `throw XCTSkip("Reason")`. The `disabled_` prefix convention is banned — if a future agent renames a test to "fix the gap," it will hang CI indefinitely. The `XCTSkip` convention is enforced and verified (see `SpatialStoreFogTests.swift:131`).

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

