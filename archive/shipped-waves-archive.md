
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
