# Dérivée — UI Blueprint & Screen Specification

This document is the **single authoritative reference** for all visual design, screen hierarchy, interaction patterns, and UI acceptance criteria. If a screen, component, or animation is not defined here, an agent **must not** invent it.

For backend data flows, native constraints, and library stacks, see [architecture.md](file:///Volumes/T7ssd/derivee/docs/architecture.md).

---

## 1. Core Philosophy & Visual Identity

### 1.0 Brand Manifesto & Naming Architecture

* **The Name:** **Dérivée** *(Pronounced: day-ree-vay)*
* **The Meaning:** A double-entendre combining the mathematical derivative (rate of change / instantaneous calculation) with the Situationist *dérive* (an unplanned, exploratory drift through a city). The app is literally the intersection of these two ideas: **calculating the rate of change of your physical presence across the city map.**
* **The Tagline:** *Unlearn your commute.*
* **Brand Persona:** Calm, intelligent, utilitarian, and understated. It is a quiet harness for real life — it gets out of your way, respects your attention span, and never behaves like an obnoxious fitness tracker or a noisy arcade game.

"Dérivée" is an ambient, offline-first location explorer and transit utility. The map **is** the app. All controls, floating sheets, and metrics exist only to serve the map without cluttering it.

### 1.1 The Dynamic Environmental Shift (Day/Night Cycle)

The interface automatically transitions between Light and Dark modes based on local **First Light (Sunrise)** and **Last Light (Sunset)** calculated via the background GPS coordinate, eliminating screen glare on dark street corners or inside subway cars.

* **Day Mode (First Light to Last Light — "Clear Morning"):**
  * **Base Map:** Soft parchment whites (`#F9F9F6`) and clean muted light grays.
  * **The Fog (Layer 4):** Inky, matte graphite clouds (`#1C1C1E`) with high translucency. Major geographic arteries (coastlines, rivers, arterial bridges) are faintly visible beneath as subtle, unlabelled vectors, acting as natural lures.
  * **UI Materials:** Apple's native `.ultraThinMaterial` (Light). Text and icons rendered in high-contrast pure black (`#000000`).

* **Night Mode (Last Light to First Light — "Midnight Grid"):**
  * **Base Map:** Deep midnight slate (`#12121A`).
  * **The Fog (Layer 4):** Pure OLED Black (`#000000`) with a heavy cloud-like blur mask, absorbing light while cleared hexes provide subtle illumination.
  * **UI Materials:** Apple's native `.ultraThinMaterial` (Dark). Text and icons rendered in clean, crisp white (`#FFFFFF`).

* **The Universal Accent Color (`#FFB300` — Electric Amber):**
  * Shared across both modes. Used strictly for the live GPS indicator dot, active transit vector routes, and glowing "Ghost POIs" in the fog. It mimics the aesthetic of vintage LED transit arrival boards.

### 1.2 Typography & Micro-Interference

* **Primary System Font:** OS Native only — **SF Pro**. Clean, neutral sans-serif used exclusively for labels, UI titles, and menus. **No serif fonts. No decorative type.**
* **The Math Font:** Native **SF Mono**. Every numerical metric — neighborhood completion percentages, subway arrival headways ($\Delta t$), or H3 hex IDs — is rendered in monospace. This subtle visual cue highlights the heavy mathematical precision of the SQLite and H3 engines running underneath.

### 1.3 Tone of Voice

* **Actionable, transparent, and direct.**
* *Avoid:* Flowery gaming jargon ("The Archive", "Cartography", "Conquer Territory").
* *Embrace:* Clear utility naming ("Exploration Stats", "Neighborhood Data", "Import Workout").

### 1.4 Visual System Summary

* **Iconography:** Geometric, high negative-space SVG glyphs. No text inside icons. No branded teardrop pins.
* **Gesture Integration:** Strictly utilizes native SwiftUI gesture modifiers (`.onTapGesture`, `Button`) to guarantee seamless coexistence with MapLibre pan/pinch gestures and native presentation sheets.

---

## 2. The 3-Tier Fog Visibility Logic

The map uses a 3-tier state to separate where the user **is**, where they **have been**, and what remains **hidden**. Unlocked H3 hexes (Resolution 11) feature a subtle border outline to define the progression grid.

| Tier | Name | Visual Treatment |
|:---|:---|:---|
| **Hidden** | Unexplored | Matte graphite clouds (Day: `#1C1C1E`) or OLED Black (Night: `#000000`) with high-blur translucency (`fill-opacity-transition: { duration: 300 }`). No base map details, pins, or labels visible beneath. |
| **Explored** | Cleared but Inactive | Base MapTiler `streets-v2` style rendered through a permanently dimmed raster layer (`rasterSaturation: -1.0`). H3 hex outlines display as faint, semi-transparent borders. **No POI markers or labels.** |
| **Active** | Current Vicinity (200m) | Full-color, unmasked satellite/street rendering within a 200m radius of the user's live GPS position. Street names, building footprints, and Ghost POI nodes render here and **only** here. |

> **Strict Rule:** If a map element (pin, label, text, POI) is outside the 200m Active Vicinity Bubble, it **must** be hidden. No exceptions.

### 2.1 Zoom Level Framework

Standard cartographic data (streets, parks, travel direction) is handled entirely by MapTiler. Custom data overlays are **strictly limited** to Transit nodes (Subway Entrances and Bus Stops).

| Zoom Level | Map Focus | Visible Custom Elements |
|:---|:---|:---|
| **0–11** | City / Region | Fog layer dominates. Base map geography visible. No custom pins or text. |
| **12–14** | Neighborhood | Unlocked hex outlines appear. Major arterial roads and neighborhood names render via MapTiler. |
| **15–16** | Street Level | MapTiler street names and travel directions fade in. Subway Ghost POI nodes become visible within Active and Explored zones. |
| **17+** | Granular Detail | Bus stop Ghost POI nodes fade in. Building footprints and exact street geometries fully visible in exposed areas. |

### 2.2 The 6-Layer Rendering Stack

The MapLibre layer stack **must** follow this exact Z-index order. See [architecture.md §8](file:///Volumes/T7ssd/derivee/docs/architecture.md) for implementation specifics.

| Z-Index | Layer Name | Purpose |
|:---|:---|:---|
| 1 | The Explored Base | `RasterLayer` — satellite imagery permanently dimmed (`rasterSaturation: -1.0`, reduced brightness). |
| 2 | The Visible Base | Full-color satellite `RasterLayer`, masked strictly by the user's active line-of-sight polygon. |
| 3 | The Sub-Context | Faint vectors (major arteries, coastlines) with zero text labels. |
| 4 | The Cloud Layer | The 50km bounding box fog polygon. Soft, translucent, high blur radius. `fill-opacity-transition: { duration: 300 }`. |
| 5 | The Holes (DDS) | Unlocked H3 hexes (Explored + Active) filtered via MapLibre `['match']` expression on `fill-opacity`. |
| 6 | The Vicinity Bubble | Active 200m radius rendering street names, transit nodes, and Ghost POI geometry. |

---

## 3. App Screen Hierarchy & Flows

The app has exactly **five** screens. If a screen is not enumerated below, the agent **must not** build it.

```
┌──────────────────────────────────────────────────────────┐
│  Screen 0: Onboarding Gate  (first launch only)          │
│  ┌────────────────────────────────────────────────────┐  │
│  │  Hydration check → download tiles + transit delta  │  │
│  └──────────────────┬─────────────────────────────────┘  │
│                     │ fade out                           │
│  ┌──────────────────▼─────────────────────────────────┐  │
│  │  Screen 1: Ambient Map  (the core loop)            │  │
│  │  ┌─────────────┐     ┌──────────────┐              │  │
│  │  │ Recenter FAB│     │ Profile FAB  │──┐           │  │
│  │  └─────────────┘     └──────────────┘  │           │  │
│  │                                        │           │  │
│  │  [ tap Ghost POI ] ──► Screen 2        │           │  │
│  └────────────────────────────────────────┼───────────┘  │
│                                           │              │
│  ┌────────────────────────────────────────▼───────────┐  │
│  │  Screen 3: Exploration Stats  (Stats & GPX Upload)  │  │
│  └────────────────────────────────────────────────────┘  │
│                                                          │
│  ┌────────────────────────────────────────────────────┐  │
│  │  Screen 4: Settings  (permissions & data reset)    │  │
│  └────────────────────────────────────────────────────┘  │
│                                                          │
│  Screen 2: Transit Reveal  (bottom sheet overlay)        │
└──────────────────────────────────────────────────────────┘
```

---

### Screen 0: The Onboarding Gate (First Launch Only)

**Trigger:** User opens the app for the very first time.

**State Logic:** On launch, query the local `GRDB` database for the hydration completion flag (a row in a `meta` table). Do **not** use UserDefaults for this critical state.

**UI Elements:**
* A full-screen, branded loading lock screen with an atmospheric fog background animation and a subtle pulsing logo.
* A translucent progress indicator showing download state.
* **No interactive buttons.** No map is mounted.

**Actions:**
1. If offline: display a single-line prompt ("Connect to the internet to set up Dérivée"). Poll for connectivity; resume automatically when restored.
2. If online: silently download the MapLibre offline tile region (50km radius centered on device location) and the `transit_delta.sqlite.zst` file from Cloudflare R2.
3. On completion: write the hydration flag to `meta` table.

**Transition:** Once hydration is complete, the lock screen fades out over 400ms, revealing Screen 1.

**Definition of Done:**
- [ ] Hydration flag is stored in GRDB, not UserDefaults.
- [ ] Offline tile region downloads successfully for the 50km bounding box.
- [ ] Transit delta file decompresses and attaches to the local database.
- [ ] No map is rendered until hydration is verified complete.
- [ ] Subsequent launches skip this screen entirely (direct to Screen 1).

---

### Screen 1: The Ambient Map (The Core Loop)

**Trigger:** Default state after onboarding. This is where the user spends 95% of their time.

**UI Elements:**
* **Edge-to-edge MapLibre map.** No tab bars, no navigation headers, no persistent HUDs.
* **The Fog Layer:** Dark, volumetric masking polygon (see §2 3-Tier logic).
* **The User Marker:** A native-feeling, smoothly interpolating Electric Amber (`#FFB300`) pulsing dot. Must use MapLibre's built-in user location layer with custom styling — not a custom SwiftUI view overlaid on the map.
* **Ghost POI Nodes:** Transit beacons visible **only** within the 200m Active Vicinity Bubble. Rendered as unbranded, glowing geometric nodes (dots, diamonds) — never as traditional teardrop map pins or icons with text labels.
* **Floating Action Buttons (FABs):** Two minimalist, translucent circular buttons floating over the map:
  * **Recenter FAB** (bottom-right): Re-centers the camera on the user's current GPS position with a smooth 300ms ease animation.
  * **Profile FAB** (top-right): Navigates to Screen 3 (Exploration Stats). Styled with `UltraThinMaterial` blur and a subtle shadow.

**Ambient Tracking:** Tracking begins silently and automatically via the native Swift `AmbientTrackingEngine` the moment Screen 1 mounts. There is **no** manual "Start/Stop Tracking" button. The app is always tracking.

**Interactions:**
* **Tap Ghost POI:** Triggers a geospatial Point-in-Polygon (PiP) check. If the user is within physical proximity (200m), query `GRDB` synchronously and open Screen 2 (Transit Reveal native `.sheet`).
* **Tap Recenter FAB:** Smooth camera animation to user location.
* **Tap Profile FAB:** Navigate to Screen 3.
* **Long-press map:** Reserved for future use. No action.

**Definition of Done:**
- [ ] MapTiler base layer renders at 60fps.
- [ ] The 3-tier fog logic correctly masks the map based on the SQLite database of unlocked hexes.
- [ ] Hex outlines render exclusively inside Explored and Active zones.
- [ ] Tracking begins ambiently on mount — no start button exists anywhere.
- [ ] Ghost POI nodes appear only within the 200m Vicinity Bubble.
- [ ] Ghost POI nodes are geometric shapes (dots/diamonds), not teardrop pins, with zero text labels.
- [ ] FABs use SwiftUI `.ultraThinMaterial` for native iOS frosted glass styling.
- [ ] FABs use native SwiftUI buttons/gestures.
- [ ] PiP check on tap correctly gates transit sheet opening to physical proximity.

---

### Screen 2: The Transit Reveal (Bottom Sheet)

**Trigger:** User taps a Subway or Bus Ghost POI node within their 200m Vicinity Bubble.

**UI Elements:**
* A native iOS-style bottom sheet (via SwiftUI `.sheet`) slides up over the map.
* **Station/Stop Name:** Large, bold SF Pro heading.
* **Real-Time Arrivals:** GTFS-RT countdown list (e.g., "L train → Manhattan — 3 min", "8 min").
* **Historical Reliability Sparkline:** A compact 7-day sparkline chart showing headway reliability, queried locally from the SQLite transit delta database in < 12ms.

**Map Interaction (Ephemeral Route Line):**
When this sheet opens, a temporary GeoJSON `LineLayer` is injected at the **top** of the MapLibre layer stack, tracing the entire transit route across the map — cutting visually through the fog. This line:
* Uses a vibrant, semi-transparent stroke matching the transit line's official color (e.g., MTA L train gray).
* Animates in with a 200ms fade.
* Is **immediately unmounted** when the sheet is dismissed — no persistent route artifacts.

**Dismissal:**
* Swiping the sheet down.
* Tapping the map outside the sheet.
* Both actions instantly unmount the ephemeral route line, snapping the map back to the localized 200m view.

**Definition of Done:**
- [ ] Sheet triggers instantly upon tapping a Subway or Bus Ghost POI node (only when within 200m proximity).
- [ ] Real-time GTFS-RT countdowns populate accurately for the selected stop.
- [ ] Historical sparkline renders from local SQLite data in < 12ms.
- [ ] Ephemeral route `LineLayer` injects on open and unmounts on dismiss with no stale artifacts.
- [ ] Sheet is dismissible via swipe-down and map tap.
- [ ] Uses native SwiftUI `.sheet(presentationDetents: ...)` modifier.

---

### Screen 3: Exploration Stats (Stats & GPX Upload)

**Trigger:** User taps the Profile FAB on the Ambient Map. Navigates to the Exploration Stats screen.

**UI Elements:**
A clean, native list view using SwiftUI `List` or `LazyVStack` for guaranteed 120fps scrolling.

* **Macro Metrics Header:**
  * Total hexes unlocked (absolute count).
  * Overall city exploration percentage.
  * A simple, native horizontal progress bar (not a heavy custom chart).

* **Neighborhood Leaderboard:**
  * A vertical list of neighborhoods (e.g., Williamsburg, Greenpoint) sorted by completion percentage, highest first.
  * Each row shows: neighborhood name, completion percentage, and a lightweight inline progress bar.
  * Percentage calculated as `(cleared_hexes_in_poly / total_hexes_in_poly) * 100` — where `total_hexes_in_poly` excludes water polygons and preserves bridge hexes (see §5).
  * Tapping a neighborhood pans the background map (Screen 1) to that neighborhood's centroid coordinates.

* **GPX/FIT Upload:**
  * A prominent "Upload Previous Workouts" button.
  * Triggers SwiftUI `.fileImporter` for local `.gpx` or `.fit` file selection.
  * Processing: Native `XMLParser` (GPX) or lightweight FIT decoder. Parsing is chunked to prevent UI freezing, coordinate arrays downsampled (>10m deltas), and deduped hexes saved via bulk SQLite inserts.
  * On successful processing, the fog state on Screen 1 updates immediately.

**Thread Yielding Rule:** The SwiftUI `List` should render smoothly. Complex data processing must occur off the main thread (`Task.detached`) before updating the `@Observable` store, preventing frame drops.

**Definition of Done:**
- [ ] Queries the local SQLite database, grouping unlocked H3 hexes by neighborhood boundaries.
- [ ] Uses SwiftUI native `List` or lazy stacks.
- [ ] Heavy processing yields the main actor.
- [ ] Tapping a neighborhood pans Screen 1's map camera to that neighborhood.
- [ ] GPX/FIT upload processes chunked, does not freeze the UI.
- [ ] Upload results correctly update the fog state on Screen 1.
- [ ] Uses native iOS list styling — clean typography, simple progress bars. No heavy custom charts.

---

### Screen 4: Settings

**Trigger:** Accessible from Screen 3 (Archive) via a gear icon or list item.

**UI Elements:**
A standard native grouped list of toggles and actions.

* **Background Location Toggle:** Controls the native `AmbientTrackingEngine` directly. Shows the current permission state.
* **Push Notification Toggle:** Standard notification permission control.
* **Data Management:**
  * "Clear Local Cache" — purges cached tiles and transit data (re-triggers Onboarding Gate on next launch).
  * "Reset Exploration Data" — destructive action with a confirmation dialog. Drops all unlocked hexes from SQLite and resets the in-memory state.

**Definition of Done:**
- [ ] Background Location toggle correctly invokes tracking state changes on the `AmbientTrackingEngine`.
- [ ] Destructive "Reset" action requires explicit user confirmation before executing.
- [ ] Clearing cache correctly re-triggers the Onboarding Gate flow.
- [ ] All toggles use native SwiftUI components.

---

## 4. Ghost POI Lifecycle

Ghost POIs are the primary discovery mechanic. They follow a strict 3-phase lifecycle:

### Phase 1 — The Lure (Hidden Territory)

* **Visibility:** Rendered as soft, anonymous beacons hovering **above** the dark fog layer — visible to the user through the fog as faint, pulsing glows.
* **Information:** Zero. No text labels, no icons, no identification. Pure ambient intrigue.
* **Purpose:** Signal to the user that something exists in unexplored territory, encouraging physical movement.

### Phase 2 — The Unlocking (Active Vicinity)

* **Trigger:** The user's GPS buffer physically intersects the hex containing the Ghost POI, placing it within the 200m Active Vicinity Bubble.
* **Visual Transition:** The faint beacon resolves into a crisp geometric node (dot for bus stops, diamond for subway entrances) with a subtle "reveal" scale animation (0→1 over 200ms, ease-out).
* **Interaction:** Tappable. Triggers the Transit Reveal bottom sheet (Screen 2).
* **Discovery Modal:** On first encounter with a previously unseen POI, a lightweight toast notification slides in from the top with contextual data (station name, fun fact). Auto-dismisses after 3 seconds.

### Phase 3 — The Archive (Explored Territory)

* **Visibility:** Once the user leaves the Active Vicinity, the node **fades to near-invisibility**. It does **not** render as a permanent, traditional map pin.
* **Constraint (from AGENTS.MD):** Ghost POIs in Explored (non-Active) hexes must be **completely invisible at zoom levels ≤ 16**. At zoom 17+, they may render as ultra-faint, desaturated geometric marks (opacity ≤ 0.15) to preserve the clean, fog-dominant aesthetic.
* **Interaction:** Not tappable when outside the Active Vicinity. The PiP proximity check gates all interactions.

---

## 5. Component Interaction & Animation Rules

All animations must feel native, organic, and performant. No cheap web-style transitions (no `ease-in-out` on opacity alone, no jarring `translateY` snaps).

### 5.1 The GPX Reveal Animation

When a user uploads a heavy GPX file containing hundreds of new hexes, the bridge recalculation must be visually masked behind a satisfying reveal animation.

* **Feel:** Like morning fog burning off the coast — smooth, warm, directional dissolve.
* **Execution:** A sweeping radial wipe or dissolve mask animating outward from the user's current position across the newly unlocked hexes, running at 60fps on the UI thread.
* **Duration:** 1.5–2.5 seconds depending on the geographic spread of the upload.
* **Implementation:** Use MapLibre's native `fill-opacity-transition` with a staggered delay per hex cluster (sorted by distance from the user's position). The fog literally "melts away" from the user outward.

> [!NOTE]
> **Design Aspiration — Metal Enhancement:** For a more dramatic volumetric sunburst effect, SwiftUI `.colorEffect` with a custom Metal shader could be introduced to render a shader-based dissolve mask. This capability is **not currently in the locked stack** (see [architecture.md §2](file:///Volumes/T7ssd/derivee/docs/architecture.md)). If adopted, it must be formally added to the Core Library Stack table. Until then, use the MapLibre-native approach above.

### 5.2 Bottom Sheet Transitions

* **Entry:** Native SwiftUI `.spring` animation (e.g., `.spring(response: 0.3, dampingFraction: 0.8, blendDuration: 0)`). No bounce.
* **Exit:** Smooth deceleration swipe-to-dismiss. Route line unmounts at the exact frame the sheet reaches its dismissed position.
* **Backdrop:** Dim the map slightly (`opacity: 0.3` dark overlay) when the sheet is at its expanded snap point, creating focus hierarchy.

### 5.3 FAB Interactions

* **Idle State:** Semi-transparent (`opacity: 0.7`), blurred background via `UltraThinMaterial`.
* **Press State:** Instant haptic feedback (`impactLight`). Scale down to `0.92` over 100ms, then spring back.
* **Active State (Recenter):** When the map is already centered on the user, the Recenter FAB shows a filled variant. When the user pans away, it transitions to an outlined variant over 200ms.

### 5.4 User Location Marker

* **Rendering:** MapLibre's native user location layer. Not a React component.
* **Pulse:** Concentric ring animation radiating outward at 1.5-second intervals, fading from `opacity: 0.4` → `0`.
* **Heading Indicator:** A subtle directional cone when the device compass is active.

### 5.5 Hex Unlock Animation

When a new hex is discovered in real-time (via Nitro callback during active use):
* The hex's fog region transitions from opaque → transparent using MapLibre's `fill-opacity-transition: { duration: 300 }`.
* A soft glow ring (single pulse) emanates from the user's position, confirming the unlock.
* **No sound effects. No confetti. No modal popups.** The reveal is ambient and organic.

---

## 6. Dynamic Island & Live Activities (Deferred — Wave 15)

Progression stats must eventually be accessible **outside** the app while the user walks with their phone locked.

* **Delivery:** A native Swift module pushes exploration progress to the iOS Dynamic Island and Lock Screen Live Activities (e.g., "5 hexes unlocked this walk").
* **Update Frequency:** Batched — update the Live Activity only when a new hex cluster (≥ 3 hexes) is unlocked, not on every individual hex. This prevents excessive UI refreshes.
* **Scope:** This is explicitly deferred to **Wave 15** (see [ROADMAP.MD](file:///Volumes/T7ssd/derivee/ROADMAP.MD)). Agents **must not** implement this until Wave 15 is active.

---

## 7. Strict UI/UX Guardrails

These rules are **non-negotiable**. Violating any guardrail constitutes a failed implementation.

| # | Rule | Rationale |
|:---|:---|:---|
| G1 | **No Clutter:** Any map element outside the 200m Vicinity Bubble must be hidden. | Progressive disclosure. The map is the UI. |
| G2 | **No Text on Map Nodes:** POI icons are geometric shapes with high negative space. Zero text or lettering inside icons. | Visual noise reduction. |
| G3 | **No Permanent POI Pins:** Ghost POIs in Explored territory must be invisible at zoom ≤ 16 and near-invisible (opacity ≤ 0.15) at zoom 17+. | Per AGENTS.MD: "Never implement permanent map pins for POIs." |
| G4 | **No Manual Tracking Controls:** No "Start/Stop Tracking" buttons. Tracking is ambient and automatic. | Per AGENTS.MD: "Never build manual Start/Stop Tracking UI elements." |
| G5 | **No Heavy Persistent HUDs:** No persistent dashboard widgets, distance counters, or speed readouts overlaying the map. | Per AGENTS.MD: "Never build heavy, persistent HUDs." |
| G6 | **Native UI Components Only:** All touchable elements use native SwiftUI buttons and gestures. | Prevents gesture conflicts with MapLibre and bottom sheets. |
| G7 | **Thread Yielding for Lists:** Complex lists (Neighborhood Stats, Session History) must process data in background tasks before binding to `@Observable` UI. | Prevents frame drops during screen transitions. |
| G8 | **No Serif Fonts:** Strictly modern geometric sans-serif (SF Pro / Inter). | Design system consistency. |
| G9 | **Dynamic Day/Night Cycle:** Interface automatically shifts between Day Mode ("Clear Morning" — parchment whites, graphite fog) and Night Mode ("Midnight Grid" — midnight slate, OLED black fog) based on local First Light / Last Light. **Electric Amber (`#FFB300`)** is the universal accent color across both modes. | Brand identity: Dérivée calculates the rate of change of your presence across the city — the environment shifts with you. |
| G10 | **Screen Enumeration is Exhaustive:** Screens 0–4 are the only screens. Agents must not invent additional screens, modals, or navigation flows not defined in §3. | Prevents scope creep and hallucinated features. |

---

## 8. The "Backend" (Data Layer) — Progression Stats

To support exploration percentages in Screen 3 (Exploration Stats) and any future contextual displays, the local database must maintain:

### 8.1 The Denominator Problem

The app knows what the user **has** explored but needs to know the **total size** of each container to calculate a percentage.

### 8.2 Neighborhood Lookup Table

A static `neighborhood_stats` table seeded into the local SQLite database maps each neighborhood to its total explorable hex count.

```sql
CREATE TABLE neighborhood_stats (
    neighborhood_name TEXT PRIMARY KEY,
    total_hexes INTEGER NOT NULL,
    centroid_lat REAL NOT NULL,
    centroid_lng REAL NOT NULL
) WITHOUT ROWID;
```

### 8.3 The Denominator Masking Logic (Landmass & Bridges Only)

The `total_hexes` value must represent **only physically walkable/cyclable territory:**

1. **Water Subtraction:** Before generating H3 hexes for a neighborhood, the static generation script performs a boolean geographic subtraction: `(Neighborhood_Polygon) MINUS (Water_Polygons) = Walkable_Polygon` using OSM or Natural Earth water data.
2. **Bridge Preservation:** Pedestrian/cycling bridges (Williamsburg Bridge, pedestrian overpasses) are physically suspended over water but are valid exploration zones. Known bridge geometries are re-added to the `Walkable_Polygon` before the H3 polyfill calculates the final hex count.
3. **Output:** The integer saved to `neighborhood_stats.total_hexes` represents only landmass and bridge hexes.

### 8.4 Current Progress Calculation

This is entirely local state driven by SwiftUI `@Observable`:
* The store tracks the continuous delta of newly unlocked hexes (sourced from GRDB `ValueObservation`).
* Progress percentage is computed as: `(cleared_hexes_in_neighborhood / total_hexes_in_neighborhood) * 100`.
* A fast, thread-safe Set validation ensures this comparison is instantaneous for real-time rendering.