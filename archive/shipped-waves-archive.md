
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
