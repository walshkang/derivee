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

### 1.0.1 Unified Iconography & Logo System: The Crystalline Aperture

* **Primary Mark:** A stepped 7-hex H3 aperture punching through a matte graphite / OLED black fog layer to reveal high-contrast cartography beneath, anchored by an Electric Amber (`#FFB300`) live coordinate node.
* **Philosophy Alignment:** The mark serves as an understated system signature and progression symbol. It avoids over-saturation, preserves cartographic utility, and respects Dérivée’s *"quiet harness"* persona.

#### System Placements & Placement Boundaries

| Surface | Visual Element | Treatment |
|:---|:---|:---|
| **App Store & Home Screen** | `AppIcon.appiconset` | **3 Adaptive Variants:**<br>• *Light Mode:* Soft Parchment base (`#F9F9F6`) under Graphite fog (`#1C1C1E`) with Electric Amber node.<br>• *Dark Mode:* Midnight Slate base (`#12121A`) under OLED black (`#000000`) with glowing Amber aperture rim.<br>• *iOS 18 Tinted:* Dedicated high-contrast monochrome alpha stencil. |
| **Screen 0 (Onboarding Gate)** | Splash Hydration Gate | Centered full-vector Crystalline Aperture with subtly pulsing Amber node during SQLite hydration. |
| **Screen 1 (Ambient Map)** | Stats FAB (Top-Right) | Houses **Variation A (Micro-Glyph)** in `.primary` over `.ultraThinMaterial` (replaces generic `person.crop.circle`). |
| **Screen 1 (Ambient Map)** | Live GPS Puck & Heading | **Pure Utilitarian:** Native Electric Amber pulsing coordinate dot + heading cone. **No brand badge overlays on the live puck.** |
| **Screen 1 (Ambient Map)** | Hex Unlock Animation | Stepped hex wave expansion (1.0 → 3.5 scale, 1.2s ease-out opacity fade `0.8` → `0.0`) + light haptic (`UIImpactFeedbackGenerator(.light)`). |
| **Screen 2 (Transit Reveal)** | Bottom Sheet & Sparklines | **Pure Legibility:** Fast, un-watermarked 7-day headway sparkline canvas. |
| **Screen 3 (Stats & Milestones)** | Hero Metric & Milestone Cards | Standalone high-negative-space aperture rings framing category artwork (Transit tracks, Street grids, Landmark diamonds). **No medieval shield containers.** |
| **Screen 3 (Settings Section)** | System Signature | Flat monochrome etched aperture + build signature at bottom of settings. |
| **Dynamic Island & WidgetKit** | Live Activities | 16×16px aperture micro-glyph leading + SF Mono hex delta trailing + walk timer & distance covered. Zero internal diagnostic telemetry. |

#### SVG Asset Specifications

1. **Variation A: The Micro-Glyph (FABs, Dynamic Island & Navigation)**
```xml
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 32 32" width="100%" height="100%">
  <path d="
    M 16,3 
    L 20,5.5 L 24,3 L 28,5.5 L 28,10.5 L 31.5,12.5 L 31.5,17.5 L 31.5,22.5 L 28,24.5 L 28,29.5 L 24,32 
    L 20,29.5 L 16,32 L 12,29.5 L 8,32 L 4,29.5 L 4,24.5 L 0.5,22.5 L 0.5,17.5 L 0.5,12.5 L 4,10.5 
    L 4,5.5 L 8,3 L 12,5.5 Z" 
    fill="none" 
    stroke="currentColor" 
    stroke-width="2" 
    stroke-linejoin="round" />
  <circle cx="16" cy="17.5" r="3.2" fill="#FFB300" />
</svg>
```

2. **Variation B: Dark Mode Environmental Shift (App Icon / Splash Gate)**
```xml
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512" width="100%" height="100%">
  <defs>
    <clipPath id="squircleDark">
      <rect width="512" height="512" rx="115" ry="115" />
    </clipPath>
    <pattern id="darkModeMapPattern" patternUnits="userSpaceOnUse" width="128" height="128">
      <rect width="128" height="128" fill="#12121A" />
      <path d="M 0 64 Q 64 50, 128 64" fill="none" stroke="#252538" stroke-width="2.5" />
      <path d="M 64 0 Q 75 64, 64 128" fill="none" stroke="#252538" stroke-width="2.5" />
      <path d="M 20 0 L 108 128" fill="none" stroke="#1A1A26" stroke-width="1.2" />
      <path d="M 0 115 C 30 110, 60 125, 128 118" fill="none" stroke="#182232" stroke-width="3" />
    </pattern>
    <radialGradient id="nightGlow" cx="50%" cy="50%" r="50%">
      <stop offset="0%" stop-color="#FFB300" stop-opacity="0.3" />
      <stop offset="100%" stop-color="#FFB300" stop-opacity="0" />
    </radialGradient>
  </defs>
  <g clip-path="url(#squircleDark)">
    <rect width="512" height="512" fill="#09090D" />
    <g stroke="#181822" stroke-width="1.5" fill="none" opacity="0.4">
      <polygon points="256,56 312,88 312,152 256,184 200,152 200,88" />
      <polygon points="368,120 424,152 424,216 368,248 312,216 312,152" />
      <polygon points="144,120 200,152 200,216 144,248 88,216 88,152" />
      <polygon points="368,248 424,280 424,344 368,376 312,344 312,280" />
      <polygon points="144,248 200,280 200,344 144,376 88,344 88,280" />
      <polygon points="256,312 312,344 312,408 256,440 200,408 200,344" />
    </g>
    <path d="
      M 256,104 
      L 300,129 L 344,104 L 388,129 L 388,180 L 432,205 L 432,256 L 432,307 L 388,332 L 388,383 L 344,408 
      L 300,383 L 256,408 L 212,383 L 168,408 L 124,383 L 124,332 L 80,307 L 80,256 L 80,205 L 124,180 
      L 124,129 L 168,104 L 212,129 Z" 
      fill="url(#darkModeMapPattern)" 
      stroke="#FFB300" 
      stroke-width="1.5" 
      stroke-opacity="0.6" />
    <circle cx="256" cy="256" r="64" fill="url(#nightGlow)" />
    <circle cx="256" cy="256" r="32" fill="none" stroke="#FFB300" stroke-width="1.5" stroke-dasharray="2 3" opacity="0.8" />
    <circle cx="256" cy="256" r="14" fill="#FFB300" />
    <circle cx="256" cy="256" r="14" fill="none" stroke="#FFFFFF" stroke-width="2.5" />
  </g>
</svg>
```

3. **Variation C: Standalone Milestone Apertures (Screen 3 Journal)**
```xml
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 120 120" width="100%" height="100%">
  <path d="
    M 60,20 
    L 70,26 L 80,20 L 90,26 L 90,38 L 100,44 L 100,56 L 100,68 L 90,74 L 90,86 L 80,92 
    L 70,86 L 60,92 L 50,86 L 40,92 L 30,86 L 30,74 L 20,68 L 20,56 L 20,44 L 30,38 
    L 30,26 L 40,20 L 50,26 Z" 
    fill="none" 
    stroke="currentColor" 
    stroke-width="2" 
    stroke-linejoin="round" />
  <polygon points="60,47 68,55 60,63 52,55" fill="#FFB300" />
  <circle cx="60" cy="55" r="2" fill="#FFFFFF" />
</svg>
```

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
  * Shared across both modes. Used for the live GPS indicator dot, boundary borders, exploration milestone glows, and active vicinity bubbles.
* **Transit & Subway Network Palette (Official Line Colors):**
  * Subway lines and route polylines are rendered in their true official MTA colors (e.g. Red `#EE352E` for 1/2/3, Green `#00933C` for 4/5/6, Purple `#B933AD` for 7, Blue `#0039A6` for A/C/E, Orange `#FF6319` for B/D/F/M, Lime `#6CBE45` for G, Brown `#996633` for J/Z, Silver `#A7A9AC` for L, Yellow `#FCCC0A` for N/Q/R/W) across map tracks, ephemeral route overlays, and station reliability sparklines.

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

> [!IMPORTANT]
> **Cold-Start Fog Contract:** On app launch after a force-quit, the Cloud Layer (Z-Index 4) must render with all previously explored hex holes visible **immediately** when the map finishes loading. The `SpatialStore` fog polygon computation must complete before or synchronize with MapLibre's `didFinishLoading` callback. A solid, hole-less fog flash on cold start is a rendering bug. See [architecture.md §5.2](file:///Volumes/T7ssd/derivee/docs/architecture.md) for the synchronization mechanism.

---

## 3. App Screen Hierarchy & Flows

The app has exactly **four** screens. If a screen is not enumerated below, the agent **must not** build it.

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
│  │  Screen 3: Stats and Profile                       │  │
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
* **Subway Thoroughfares (Ambient Sub-Context):** Complete NYC subway lines rendered beneath the fog layer with day/night adaptive casings. Explored sections glow vibrantly in true MTA line colors, while unexplored sections act as orienting sub-context under the fog.
* **Nearby Buses Quick Lens (`NearbyBusesCapsule`):** A floating frosted-glass capsule in the bottom-left of the HUD providing on-demand transit discovery within 400m:
  * **Dynamic Badge Counter:** Displays the number of nearby bus stops; refreshes automatically when walking drift exceeds 150m.
  * **Expanded Quick Card:** Lists up to 3 nearest stops with line capsules (e.g. `M15-SBS`, `B62`), walk distances (in meters), and directions.
  * **Live Protobuf Integration:** Tapping any bus stop opens Screen 2 (Transit Reveal) with live arrivals and destination details.
  * **Manual Refresh (↻):** Allows instant on-demand rescan. Displays *"Acquiring GPS position..."* during cold startup until GPS fix is locked.
* **Camera Model (Strict 2D Orthographic Top-Down):** The camera is hard-locked to nadir view (`pitch = 0.0`). Two-finger tilt gestures are disabled (`allowsTilting = false`), and `CameraBounds.shouldAllowCameraChange` rejects any `.gestureTilt` or `pitch > 0` transition. Buildings render as crisp flat 2D footprints across all close zoom levels ($z = 13..24$), eliminating 3D perspective distortion, depth-buffer z-fighting, or building extrusions clipping through the ground-level Fog of War polygon.

**Ambient Tracking:** Tracking begins silently and automatically via the native Swift `AmbientTrackingEngine` the moment Screen 1 mounts. There is **no** manual "Start/Stop Tracking" button. The app is always tracking.

**Interactions:**
* **Tap Ghost POI or Bus Stop:** Triggers a geospatial Point-in-Polygon (PiP) check or quick lens selection, opening Screen 2 (Transit Reveal native `.sheet`).
* **Tap Nearby Buses Capsule:** Expands the quick discovery card or triggers an immediate rescan.
* **Tap Recenter FAB:** Smooth camera animation to user location (enforcing `pitch: 0.0`).
* **Pan & Zoom:** Smooth 2D panning and pinch-to-zoom bounded by the NYC envelope ($40.0^\circ\text{N} \le \text{lat} \le 41.5^\circ\text{N}$, $-74.5^\circ\text{W} \le \text{lon} \le -73.0^\circ\text{W}$) with $0.35^\circ$ elastic rubber-band margin and automatic `.easeOut` rollback.
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
* Fades out with a 200ms opacity transition when the sheet is dismissed, rather than unmounting instantly, to dissolve gracefully matching the SwiftUI spring physics.

**Dismissal:**
* Swiping the sheet down.
* Tapping the map outside the sheet.
* Both actions trigger the 200ms fade-out of the ephemeral route line, snapping the map back to the localized 200m view.

**Definition of Done:**
- [ ] Sheet triggers instantly upon tapping a Subway or Bus Ghost POI node (only when within 200m proximity).
- [ ] Real-time GTFS-RT countdowns populate accurately for the selected stop.
- [ ] Historical sparkline renders from local SQLite data in < 12ms.
- [ ] Ephemeral route `LineLayer` injects on open and unmounts on dismiss with no stale artifacts.
- [ ] Sheet is dismissible via swipe-down and map tap.
- [ ] Uses native SwiftUI `.sheet(presentationDetents: ...)` modifier.

---

### Screen 3: Stats and Profile

**Trigger:** User taps the Profile FAB on the Ambient Map. Navigates to the Stats and Profile screen.

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

* **Settings & Data Management (Bottom Section):**
  * **Ambient Tracking Toggle & Dynamic Island Control:** Controls the native `AmbientTrackingEngine` directly (`CLBackgroundActivitySession`). Toggling off ambient tracking invalidates the background location session to immediately release the Dynamic Island location indicator.
  * **Friendly Tracking Pause Reminder:** When the user toggles off Ambient Tracking, present a native confirmation alert:
    * **Title:** `"Pause Ambient Exploration?"`
    * **Message:** `"Pausing tracking will stop discovering new hexes while your screen is off or the app is closed. Remember to re-enable tracking before your next drift."`
    * **Actions:** `"Pause Tracking"` (confirms pause and invalidates `CLBackgroundActivitySession`) and `"Keep Tracking On"` (cancels pause request, keeping tracking active).
  * **Push Notification Toggle:** Standard notification permission control.
  * **Clear Local Cache:** Purges cached tiles and transit data (re-triggers Onboarding Gate on next launch).
  * **Reset Exploration Data:** Destructive action with a confirmation dialog. Drops all unlocked hexes from SQLite and resets the in-memory state.

**Thread Yielding Rule:** The SwiftUI `List` should render smoothly. Complex data processing must occur off the main thread (`Task.detached`) before updating the `@Observable` store, preventing frame drops.

**Definition of Done:**
- [ ] Queries the local SQLite database, grouping unlocked H3 hexes by neighborhood boundaries.
- [ ] Uses SwiftUI native `List` or lazy stacks.
- [ ] Heavy processing yields the main actor.
- [ ] Tapping a neighborhood pans Screen 1's map camera to that neighborhood.
- [ ] GPX/FIT upload processes chunked, does not freeze the UI.
- [ ] Upload results correctly update the fog state on Screen 1.
- [ ] Settings toggles (Background Location, Push Notifications) correctly invoke native handlers.
- [ ] Toggling off Ambient Tracking in Settings presents a friendly reminder alert before stopping tracking and releasing `CLBackgroundActivitySession`.
- [ ] Destructive "Reset" action requires explicit user confirmation before executing.
- [ ] Clearing cache correctly re-triggers the Onboarding Gate flow.
- [ ] Uses native iOS list styling — clean typography, simple progress bars. No heavy custom charts.

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

### Phase 3 — Explored Territory

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
* **Exit:** Smooth deceleration swipe-to-dismiss. The ephemeral route `LineLayer` must fade out with a 200ms opacity transition so it dissolves gracefully (matching the bottom sheet's spring physics) rather than unmounting instantly.
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

## 6. Dynamic Island & Live Activities (Wave J.10)

Progression stats are accessible **outside** the app while the user walks with their phone locked.

* **Delivery:** A native Swift module pushes exploration progress to the iOS Dynamic Island and Lock Screen Live Activities (e.g., "5 hexes unlocked this walk").
* **Decoupled Settings Control:** Independent `Dynamic Island Glance` sub-toggle under Settings > Tracking allows users to choose between silent ambient tracking and visible Dynamic Island HUD.
* **Contextual Routing (Deep Linking):** Tapping the Dynamic Island or Live Activity passes a deep link (`derivee://progress`) to the app. Tapping dismisses active sheets, recenters the MapLibre viewport to the user coordinates, and triggers an aperture pulse glow.
* **Lifecycle & Termination Hardening:**
  * **Graceful Termination:** Listens for `UIApplication.willTerminateNotification` to immediately invalidate `CLBackgroundActivitySession` and dismiss active Live Activities with `.immediate` dismissal policy.
  * **Fail-Safe Expiry:** Employs a rolling 45-second `staleDate` on `ActivityContent`. If the app is killed abruptly (`SIGKILL`) while suspended in the background, the Dynamic Island automatically clears within 45 seconds of inactivity.
  * **Heartbeat Refresh:** Location updates refresh distance metrics and the rolling 45s `staleDate` so stationary pauses at crosswalks do not trigger premature expiration while tracking.

---

## 7. Strict UI/UX Guardrails

These rules are **non-negotiable**. Violating any guardrail constitutes a failed implementation.

| # | Rule | Rationale |
|:---|:---|:---|
| G1 | **No Clutter:** Any map element outside the 200m Vicinity Bubble must be hidden. | Progressive disclosure. The map is the UI. |
| G2 | **No Text on Map Nodes:** POI icons are geometric shapes with high negative space. Zero text or lettering inside icons. | Visual noise reduction. |
| G3 | **No Permanent POI Pins:** Ghost POIs in Explored territory must be invisible at zoom ≤ 16 and near-invisible (opacity ≤ 0.15) at zoom 17+. | Per AGENTS.MD: "Never implement permanent map pins for POIs." |
| G4 | **No Map HUD Tracking Controls:** No "Start/Stop Tracking" buttons on the ambient map. Tracking is ambient and automatic, with pause/stop toggles restricted exclusively to Settings (Screen 3) along with a friendly reminder alert. | Per AGENTS.MD: "Never build manual Start/Stop Tracking UI elements on the main map interface." |
| G5 | **No Heavy Persistent HUDs:** No persistent dashboard widgets, distance counters, or speed readouts overlaying the map. | Per AGENTS.MD: "Never build heavy, persistent HUDs." |
| G6 | **Native UI Components Only:** All touchable elements use native SwiftUI buttons and gestures. | Prevents gesture conflicts with MapLibre and bottom sheets. |
| G7 | **Thread Yielding for Lists:** Complex lists (Neighborhood Stats, Session History) must process data in background tasks before binding to `@Observable` UI. | Prevents frame drops during screen transitions. |
| G8 | **No Serif Fonts:** Strictly modern geometric sans-serif (SF Pro / Inter). | Design system consistency. |
| G9 | **Dynamic Day/Night Cycle:** Interface automatically shifts between Day Mode ("Clear Morning" — parchment whites, graphite fog) and Night Mode ("Midnight Grid" — midnight slate, OLED black fog) based on local First Light / Last Light. **Electric Amber (`#FFB300`)** is the universal accent color across both modes. | Brand identity: Dérivée calculates the rate of change of your presence across the city — the environment shifts with you. |
| G10 | **Screen Enumeration is Exhaustive:** Screens 0–3 are the only screens. Agents must not invent additional screens, modals, or navigation flows not defined in §3. | Prevents scope creep and hallucinated features. |

---

## 8. The "Backend" (Data Layer) — Progression Stats

To support exploration percentages in Screen 3 (Stats and Profile) and any future contextual displays, the local database must maintain:

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

---

## 9. Exploration Polish, Customization & Gamification (Wave J)

This section defines visual and interaction standards for upcoming Wave J features. Sub-waves execute in **strict sequential order** (J.2 → J.7):

### 9.1 Camera Viewport Clamping & Rubber-Band Damping (`WJ1-CAMERA-BOUNDS`)
* **Camera Bounds:** The map camera must not be allowed to pan infinitely past the active fog bounding box. The viewport is constrained to the bounding envelope of the fog canvas.
* **Physics & Resistance:** During pan/pinch gestures near the perimeter, temporary overflow is allowed with gentle resistance. On gesture release, an asynchronous 400ms `.easeOut` animation smoothly restores the camera center to the boundary edge without jarring halts or gesture lockups.

### 9.2 Dual-Model POI & Vector Tile Masking Under Fog (`WJ3-FOG-POI-MASKING`)
* **Explorability Protection:** Underlying MapTiler vector POIs (restaurants, retail shops, parks, commercial labels) must be completely invisible underneath unexplored fog.
* **Commercial/Retail POIs (Ephemeral 200m Vicinity Bubble):** Base MapTiler commercial and park symbol layers (`poi_label`, `park_label`) are governed by a GPU-accelerated 200m distance predicate (`mgl_distanceFrom:(userPoint) <= 200`). Commercial labels and POI markers fade in smoothly only when the user is physically within the 200m progressive disclosure bubble, and fade out upon departure.
* **Transit Stations & Landmarks (Native Runtime Layer):** Interactive subway/bus stations and curated historic landmarks are rendered exclusively via Dérivée's custom SQLite-backed `poiSourceId` runtime layer. Any station or landmark in `explored_hexes` remains permanently visible across sessions as a permanent spatial anchor.

### 9.3 Map Base Layer & Bundled Composite Style Switching (`WJ4-BASEMAP-SWITCHER`)
* **Available Styles:**
  1. *Standard Day/Night:* Parchment White (`#F9F9F6`) / Midnight Slate (`#12121A`).
  2. *Ultra Dark (OLED Minimalist):* Deep `#000000` / `#0A0A10` base for maximum contrast and battery conservation.
  3. *Transit Network Overlay:* Emphasizes subway, heavy rail, and bus route paths with official agency line colors.
* **Delivery:** All layer definitions for all themes are bundled in a single local `composite_style.json` shipped in the iOS app bundle with a shared `maptiler_streets` vector source. The MapTiler API key is injected at runtime — zero remote style endpoint dependency.
* **Zero-Freeze Transition:** Executed entirely via GPU layer property interpolation (`fillColorTransition`, `lineOpacityTransition`, `backgroundColorTransition`) using `MLNTransition(duration: 0.6)`. Zero style destruction, zero `MLNShapeSource` unmounting, zero data source re-hydration.

### 9.4 Visual Customization Settings (`WJ5-CUSTOMIZATION-SETTINGS`)
* **Location:** Dedicated "Map Aesthetics & Exploration" section in `SettingsView` (Screen 3). The primary map screen remains free of settings controls, consistent with the "map is the UI" philosophy.
* **Persistence:** All preferences stored via `@AppStorage` keys for instant reactivity and cross-launch persistence.
* **Controls:**
  * **Fog Opacity Slider:** Variable alpha (`0.60` to `0.98`) updating fragment shaders in real-time (`fillOpacityTransition = MLNTransition(duration: 0)`).
  * **Hex / Boundary Styling:** Toggle subtle hex grid border lines and boundary highlights via an `MLNLineStyleLayer` attached directly to the existing `fog-source` geometry (`fillOpacityTransition = MLNTransition(duration: 0)`).
  * **Basemap Theme Picker:** Selection of Day, Night, OLED Ultra Dark, or Transit Network theme, triggering the GPU crossfade defined in §9.3.

### 9.5 Hybrid Transit Node Tracking View (`WJ6-TRANSIT-NODE-TRACKING`)
* When the user taps an active transit node in Screen 2:
  * **Presentation Ergonomics:** Native SwiftUI `.sheet` with `presentationDetents([.fraction(0.3), .large])` snapping to the bottom third.
  * **High-Contrast Route Geometry:** Temporary dual-layer route rendering (6px light silver casing underneath a 4px agency-colored line) to prevent dark MTA colors from disappearing into the fog. Route shapes sourced from pre-hydrated local `derivee_transit.sqlite` — no geo-payload downloads over cellular.
  * **Real-Time Data:** Direct SwiftProtobuf binary `.pb` GTFS-RT feed ingestion via `apple/swift-protobuf` for sub-second dynamic $\Delta t$ arrival countdowns and historical headway sparklines. Polling runs every 15s in a detached `Task` strictly scoped to sheet presentation, cancelling immediately on dismiss.
  * **Instant Teardown:** Dismissing the sheet instantly strips the temporary route layer with zero residual artifacts.

### 9.6 Minimalist Discovery Loop & Haptic Choreography (`WJ7-POI-GAMIFICATION`)
* **Dual-Sensory Feedback:**
  * *Haptics:* `UIImpactFeedbackGenerator(style: .light)` fires immediately upon successful GRDB database insertion of a newly discovered hex.
  * *Transient Pulse:* Unlocked hex triggers an ephemeral `MLNCircleStyleLayer` expanding from radius 0 to 80 with a 1.2s opacity fade (`0.8` to `0.0`), auto-removed on completion.
* **Exploration Journal:** Screen 3 houses categorized milestone cards (Transit Hubs, Neighborhoods, Historic Landmarks) with discovery timestamps and badge progression computed on-demand via asynchronous GRDB reads (`dbWriter.read`), keeping the primary map completely free of gamified clutter.