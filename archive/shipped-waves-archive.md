
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
