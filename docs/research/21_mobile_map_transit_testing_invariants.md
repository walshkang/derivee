# Empirical Invariants & Testing Methodologies in Production Mapping and Real-Time Transit Applications

## 1. Executive Overview & Industry Context

Mobile applications operating at the intersection of cartography, spatial telemetry, and real-time transit (e.g., **Transit App**, **Citymapper**, **Apple Maps**, **Google Maps**, **Uber**, **Lyft**, and **Flighty**) face a distinct class of testing challenges fundamentally different from typical CRUD or content-driven mobile apps. 

In standard mobile applications, views are static projections of deterministic REST/GraphQL endpoints. In spatial transit and navigation apps, views must continuously reconcile two out-of-sync data realities:
1. **The Static Planning Horizon:** High-volume relational schedule databases (GTFS static, OSM street topologies, station complex floorplans, precomputed transfer shortcuts).
2. **The Dynamic Execution Horizon:** High-frequency, noisy, asynchronous telemetry streams (GTFS-RT binary Protobuf, GBFS JSON micro-mobility feeds, GPS CoreLocation fixes, vehicle heading vectors, and service disruption alerts).

When these two horizons collide on constrained mobile hardware (60–120 Hz frame budgets, strict 30 MB Jetsam ceilings, subterranean signal dropouts, and one-handed thumb navigation), minor edge cases manifest as catastrophic commuter trust failures:
- **"Ghost" vehicles** appearing and disappearing.
- **Negative countdown jumping** (an arrival jumping from 2 min $\to$ 5 min $\to$ 1 min $\to$ 4 min).
- **Dead past space** (forcing commuters to scroll past 15 already-elapsed stops to find their current train).
- **Gesture deadlocks** (a swipe intended to scroll a departure timetable accidentally dragging down and dismissing the bottom sheet).
- **Text truncation and row collision** under dynamic text wrapping or multi-line alerts.

This research document analyzes the primary testing strategies, invariant assertions, and QA architectures employed by top transit, mapping, and mobile engineering teams, synthesizing their practices into an exhaustive testing taxonomy for Dérivée.

---

## 2. Transit Telemetry & Data Integrity Testing

### 2.1. The Monotonicity & Anti-Jitter Invariant
In real-time transit tracking (pioneered by *Transit App* and *Flighty*), the single largest driver of commuter anxiety is **ETA stuttering**—where the arrival time oscillates rapidly due to discrete GPS ping latencies or schedule-catchup algorithms.

* **The Invariant:** For any tracked active trip approaching a target station $S$, the predicted arrival timestamp $\tau_{\text{arr}}(t)$ must satisfy monotonic progression with bounded variance:
  $$\Delta \tau = \tau_{\text{arr}}(t_2) - \tau_{\text{arr}}(t_1) \le \epsilon_{\text{catchup}} \quad \text{for } t_2 > t_1$$
* **Industry Testing Methodology:**
  - **Time-Series Fuzzing:** Engineering teams replay recorded GTFS-RT feed sequences through headless state machines to assert that countdown timers never jump backward across midnight boundaries or oscillate rapidly across consecutive polling bursts.
  - **Terminal Dwell Clamping:** Vehicles dwelling at terminal origins with `stop_sequence <= 1` must be clamped to `"At Terminus"` / `"Scheduled"` until the vehicle physically transitions to `IN_TRANSIT_TO` with sequence $\ge 2$, suppressing phantom motion before the run actually begins.
  - **Circular Modular Delay Matching:** Across midnight boundaries ($23:59 \to 00:01$), linear subtraction produces 24-hour phantom delays. Top teams test using Euclidean modulo arithmetic:
    $$\text{delay} = ((t_{\text{live}} - t_{\text{sched}} + 720) \bmod 1440) - 720$$
    Assertions verify that delays are strictly constrained to $[-720, +720]$ minutes without discontinuity.

### 2.2. "Ghost" Vehicle & Stale Stream Invariants
Transit agencies frequently publish orphan trips, canceled runs without explicit cancellation tags, or stale vehicle positions.

* **Industry Testing Methodology:**
  - **ETA Completeness & Stale Gate Assertions:** *Transit App* uses automated "robot" probes comparing agency predictions against actual observed arrivals. On mobile clients, unit tests assert 3-tier confidence degradation:
    1. `Verified` (pulsing indicator): Feed timestamp $< 60\text{s}$ old, vehicle actively reporting AVL.
    2. `Estimated` (stale tag): Feed timestamp $60\text{s} \le \Delta t \le 120\text{s}$, progress mathematically interpolated along track shapes.
    3. `Static Fallback` (dimmed / scheduled): Feed timestamp $> 120\text{s}$ or network timeout; vehicle puck frozen, UI displays scheduled headway (*"Every 4–6 min • Scheduled"*).
  - **Anti-Ghost Movement:** Tests assert that if telemetry drops underground, the client never extrapolates vehicle movement past a terminal or through unconfirmed switch tracks without physical confirmation.

### 2.3. Identity Reconciliation & Headsign Invariants
Real-time feeds often transmit internal dispatch keys (e.g. `TRIP 091850_L..N`, `ROUTE 401`, `BAY RAMP B S51`) rather than customer-facing route and terminal names.

* **Industry Testing Methodology:**
  - **Zero Raw Identifier Invariant:** Automated tests assert that no raw UUIDs, database primary keys, or dispatch noise strings enter user-facing `Text` components.
  - **Headsign-First Resolution:** Teams test a 3-tier resolution cascade:
    1. GTFS-RT `StopTimeUpdate` terminal lookup.
    2. Static timetable `headsign` resolution.
    3. Spatial corridor extrema fallback (projecting stops along the principal axis).
  - **Directional Token Sanitization:** Boundary-aware regex assertions ensure direction tokens (`NB`, `SB`, `EB`, `WB`) are isolated as directional qualifiers rather than corrupting numbered street tokens (e.g. asserting `"Kent Av & North 6th St"`, never `"Kent Av & NB 6 St"`).

---

## 3. Cartographic & Viewport Testing (Mapbox, Apple Maps, Uber, Lyft)

### 3.1. Camera Viewport State Machines & Bounded Framing
Mapping leaders like *Mapbox* and *Uber* formalize camera behavior as strict, deterministic state machines (e.g. `FollowPuckViewportState`, `OverviewViewportState`, `RouteInspectionViewportState`).

* **Industry Testing Methodology:**
  - **Camera Safety Invariants:** When inspecting a route or stop ladder, the camera framing must be mathematically bounded to the convex hull of that specific route. Tests assert that tapping an outer-borough stop (e.g. Staten Island or Queens) can **never** cause the camera to fly across bodies of water to default coordinates (e.g. Midtown Manhattan).
  - **Relative-to-Center (RTC) Precision Assertions:** At high zoom levels ($z \ge 18$), 32-bit single-precision floating point coordinates suffer from visual vertex jitter. Tests assert that Web Mercator coordinates are translated to Metal NDC via Relative-to-Center double-precision offsets, verifying jitter-free rendering across extreme coordinates.
  - **2D Nadir Orthographic Lock:** When combining vector tile cartography with raster/Metal fog masks or subterranean floorplans, any perspective tilt (`pitch > 0`) introduces parallax misalignment between the map surface and spatial masks. Tests assert `pitch == 0.0` across all camera gestures.

### 3.2. Gesture Ownership & Sheet-Map Arbitration
The modern mapping paradigm popularized by *Apple Maps* (iOS 16+ `presentationDetents`) layers interactive bottom sheets directly over a continuous map canvas. This creates severe gesture contention between:
- Vertical list scrolling inside the bottom sheet.
- Interactive sheet drag-to-dismiss or detent resizing.
- Map panning and two-finger pinching beneath or beside the sheet.

* **Industry Testing Methodology:**
  - **`.presentationContentInteraction(.scrolls)` Verification:** Tests assert that scrollable timetables and reliability matrices inside sheets do not yield vertical gestures to sheet dismissal until the scroll view reaches its top boundary (`contentOffset.y <= 0`).
  - **Ambient Map Dismissal Contract:** Tests verify that tapping anywhere on the ambient map outside active interactive POIs automatically dismisses transient lenses (such as nearby bus capsules) and clears temporary selection halos without requiring explicit close buttons.

---

## 4. Modern Mobile Ergonomics & Layout Invariants (Point-Free, Cash App, Apple HIG)

### 4.1. The 0.0s Above-the-Fold Glance Budget
In high-stress commuter environments (running down subway stairs, boarding a closing bus), users operate within a **0.5-second glance window**.

* **The Invariant:** Every interactive sheet, modal, or inspector must answer the user's primary operational question **above the fold within 0.0s of opening**, requiring zero scrolling and zero hunting.
* **Industry Testing Methodology:**
  - **Deterministic Viewport Budget Calculations:** Using headless `UIHostingController` layout measurements at standardized sheet detents (e.g. `.fraction(0.15)` collapsed peek, `.fraction(0.50)` half sheet, `.fraction(0.90)` expanded sheet):
    $$\text{Available Height} = H_{\text{detent}} - H_{\text{header}} - H_{\text{alerts}} - H_{\text{safeArea}}$$
  - Tests assert that the available height strictly accommodates **at least 3 to 4 live arrival rows** at the half detent, ensuring critical arrivals are never hidden beneath the fold.

### 4.2. Dynamic Type & Layout Collision Testing
Text clipping and layout truncation are among the most frequent regressions introduced by AI coding agents and rapid developer refactoring.

* **Industry Testing Methodology:**
  - **Headless Geometry Assertions (`sizeThatFits`):** Top teams (using Point-Free `swift-snapshot-testing` and Cash App `AccessibilitySnapshot`) avoid brittle full-app UI testing by executing headless layout assertions against views configured with extreme environments:
    ```swift
    let view = DepartureMatrixView(...).environment(\.dynamicTypeSize, .accessibility3)
    let size = UIHostingController(rootView: view).sizeThatFits(in: CGSize(width: 393, height: .infinity))
    XCTAssertGreaterThan(size.height, expectedMinimumExpandedHeight)
    ```
  - **Zero Hardcoded Frame Height on Dynamic Containers:** Tests parse the view hierarchy or assert programmatically that outer list rows and cards never specify rigid heights (e.g. `.frame(height: 56)`), which would clip multi-line wrapped departure capsules or localized text. Outer rows must use `.fixedSize(horizontal: false, vertical: true)` and padding.

### 4.3. The 100pt Thumb Zone Invariant (Apple HIG & Ergonomic Reachability)
On modern large-format smartphones (6.1" to 6.9" displays), the top 40% of the screen is outside the comfortable one-handed thumb sweep.

* **The Invariant:** The bottom 100pt of any scrollable container or primary navigation sheet is strictly reserved for high-frequency operational tasks. Administrative, low-frequency actions (GPX file imports, cache clearing, account management) must never monopolize this primary zone.
* **Industry Testing Methodology:**
  - **Visual & Structural Z-Index Audits:** Tests verify that sticky action bars in active guidance (e.g. `ThumbZoneActionBar`) reside in the bottom third, while persistent full-width buttons for rare admin tasks are relegated to secondary Settings views or top navigation bar menus.

---

## 5. Shift-Left Architecture: Replacing Slow Remote CI with Fast Local Gates

### 5.1. The Solo Developer CI Anti-Pattern
In large enterprises (Uber, Lyft), thousands of engineers justify heavy distributed CI systems (BuildBuddy, remote macOS MacStadium farms) running 45-minute validation pipelines. 

For a **solo developer pairing with autonomous coding agents**, remote CI creates catastrophic friction:
- 5–10 minute wait times on GitHub Actions runners.
- Flaky simulator provisioning and OS image mismatches.
- Context switching and runner secret debugging.

### 5.2. The 2-Tier Shift-Left Architecture
Leading mobile architects shift all critical invariant verification **left** onto the local developer machine using two complementary gates:

```
[Agent or Developer Writes SwiftUI Code]
                    │
                    ▼
┌────────────────────────────────────────────────────────┐
│ Gate 1: Fast Sub-Second AST & Regex Filter (< 0.2s)    │
│ Location: .githooks/pre-commit (tracked in git)        │
│ Scope: Staged Swift files only                         │
│ Catches: Raw DB keys in Text(), prohibited .sheet()    │
└────────────────────────────────────────────────────────┘
                    │
                    ▼
┌────────────────────────────────────────────────────────┐
│ Gate 2: Headless Commuter Ergonomics Suite (~10s)      │
│ Location: scripts/verify-ux.sh                         │
│ Scope: DeriveeTests/CommuterErgonomicsTests.swift      │
│ Catches: Dynamic Type clipping, 0.0s fold budgets,     │
│          accordion thresholds, single-anchor Next      │
└────────────────────────────────────────────────────────┘
                    │
                    ▼
[Instant Local Commit & Next Roadmap Task]
```

By decoupling UX invariants from remote cloud runners and running them as headless unit assertions, feedback drops from **600 seconds to 10 seconds** with zero loss of guardrail integrity.

---

## 6. Synthesis: Exhaustive Testing Taxonomy for Dérivée

Cross-referencing the best practices of Transit App, Citymapper, Uber, and Apple Maps yields an exhaustive 4-category testing taxonomy for Dérivée:

| Category | Invariant Dimension | Industry Benchmark Source | Dérivée Test Implementation |
|---|---|---|---|
| **I. Temporal & Telemetry** | Monotonic countdowns, anti-jitter, circular delay math, terminal dwell suppression, headsign cascades. | *Transit App*, *Flighty* | `testFC1_DepartureMatrix_AnchorsToWallClockHourOnInit`, `testFC2_GuidewayHero_DeJargonizesRawTripHashes`, `testDegradedState_GTFSRTFeedTimeout` |
| **II. Cartographic & Spatial** | Bounded camera framing, RTC precision, 2D nadir top-down, ambient map tap dismissal. | *Mapbox*, *Uber*, *Lyft* | `testFC1_GuidewayStopLadder_AutoAnchorsCurrentStation`, `testFC6_MapView_OrientationClusterPositionedInBottomRightThumbSweep` |
| **III. Ergonomics & Layout** | Dynamic Type expansion, zero height clipping, single-anchor badges, unified status tokens. | *Point-Free*, *Cash App*, *Apple HIG* | `testFC3_GuidewayAndSurface_ConsolidatesBoardingAndTrackPill`, `testFC4_HourRowView_DynamicHeightExpansionWithWrappingDepartures` |
| **IV. Navigation & Viewport** | 0.0s above-the-fold glance budget, zero nested sheet stacking, lower-third thumb zone. | *Apple Maps (MapKit)*, *Citymapper* | `testAboveTheFold_Screen2_ThreeToFourArrivalRowsVisibleAtMediumDetent`, `testFC5_TransitRevealSheet_InspectsArrivalInPlaceWithBackChevron`, `testFC6_StatsView_ThumbZoneClearOfAdministrativeButtons` |

This taxonomy forms the definitive specification for [`DeriveeNative/DeriveeTests/CommuterErgonomicsTests.swift`](file:///Volumes/T7ssd/derivee/DeriveeNative/DeriveeTests) and the local verification pipeline.
