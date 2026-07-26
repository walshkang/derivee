# design.md - Fog of Wburg

## 1. Product Vision & Brand Identity

**The Core Loop:** Fog of Wburg is an iOS application (and eventual Apple Watch app) designed to encourage real-world exploration by applying a permanent "fog of war" mechanic to a physical map. The concept operates as a hybrid of a fitness tracker and a location-based game—essentially "Strava meets Civilization VI".

**Aesthetic Direction:**

* 
**Vibe:** The visual language should evoke real-life cartography and board games like Catan or Civilization VI.


* 
**Base Map:** High-resolution satellite and terrain imagery should be used to ground the experience in reality.


* 
**3D Elements:** Explored areas should reveal simple 3D isometric buildings beneath the fog to provide geographic context.


* 
**The Fog:** Unexplored areas are shrouded in a dark, atmospheric, semi-transparent stylistic fog.


* **Macro-Map View:** When a user zooms all the way out, individual 10-meter hexes dissolve into aggregated, glowing regional polygons to showcase broader geographic coverage.

---

## 2. Core User Flows & Screens

### Screen 0: The Awakening (Startup / Splash Screen)

**Visuals:**

* A minimalist, atmospheric opening where the screen is entirely covered in the dark fog layer.
* The "Fog of Wburg" logo sits dead center.
* **Animation:** The fog fluidly "burns away" from the center outward, seamlessly transitioning the user directly into the map.

**Under the Hood:**

* Prompts for Location Permissions on the very first launch.


* Generates the localized 50km x 50km GeoJSON fog bounding box so it is ready to render immediately.



### Screen 1: The Cartographer's Desk (Main Home Screen)

**Visuals:**

* A full-screen map interface.


* Unexplored areas are covered by the dark fog layer.


* Fully explored areas are highly saturated, showcasing 3D buildings and satellite terrain.



**Actions & Controls:**

* A prominent, large primary action button labeled "Start Exploring".


* An icon to center the camera on the user's current location.


* A toggle menu to switch map layers.



### Screen 2: Active Expedition (Live Tracking HUD)

**Visuals:**

* The map is actively locked and centered on the user's location indicator.


* As the user physically moves, the fog dynamically "burns away" or lifts in a buffer radius around them.



**Metrics & Controls:**

* A translucent overlay positioned at the top or bottom of the screen.


* Real-time statistics displayed on the overlay: Time Elapsed, Distance Traveled, and New Hexes Unlocked.


* Control buttons to Pause or Stop the active exploration.



### Screen 3: Discovery Modal (Waypoint Unlocked)

**Visuals:**

* A gamified pop-up that momentarily interrupts the HUD when a user walks into a Point of Interest (POI) hexagon.


* A rewarding, celebratory aesthetic featuring a stylized badge or icon.



**Content & Actions:**

* Header text reading: "You Discovered: [POI Name]".


* A brief fun fact or historic detail about the location.


* Buttons to "Dismiss", "Read More", or "Save to Favorites".



### Screen 4: The Archive (Profile & Stats)

**Visuals:**

* A clean dashboard displaying the user's overall exploration progress.



**Content & Actions:**

* Micro-Level Metrics (Zoomed In): Neighborhood completion metrics (e.g., "Williamsburg: 14% Uncovered") and total hex count.


* Macro-Level Metrics (Zoomed Out): Dynamically shifts to global stats (e.g., "Cities Visited: 12", "Countries Explored: 3").
* A scrollable list or gallery of previously Discovered POIs.



### Screen 5: The Cartographer's Tools (Settings & Customization)

**Visuals:**

* A clean configuration menu accessed via a gear icon.

**Content & Actions:**

* **HUD Customization:** Toggles to check/uncheck metrics on the active overlay.
* **Waypoint Behavior:** Toggles to control "Auto-Trigger Modal" vs. "Quiet Discovery" banners.
* **Map Preferences:** Sliders to adjust fog opacity or toggle 3D buildings to save battery.
* 
**Integrations:** Controls to manage Apple HealthKit, Strava, and data exports.



### Screen 6: Feature Unlocked (The Local Scanner)

**Visuals:**

* A celebratory interstitial screen that pops up after completing a set number of expeditions.

**Content & Actions:**

* Body text explaining the user can now see live transit options like subways and bike share availability in their immediate vicinity.


* Transit icons subtle pulse within the live GPS buffer radius on the map.

---

## 3. Specialized User Flows

### Flow 1: The Historian (Data Import Journey)

**User Experience:**

* Accessed via the Settings screen, allowing a user to passively upload historical activity from another fitness app or a GPX/FIT file.


* Displays a loading state reading "Consulting the archives..." while calculating the H3 grid system.
* **The Payoff:** The user is returned to the map where a massive, satisfying animation plays as huge swaths of fog instantly vanish across their city.

---

## 4. The Waypoint Lifecycle (Gamification)

Points of Interest (POIs) such as historic restaurants, museums, and landmarks follow a strict three-phase visual lifecycle based on the user's exploration state.

**Phase 1: The Lure (In Fog)**

* 
**Visual Treatment:** A soft, glowing, anonymous beacon rendering directly above the dark fog layer.


* 
**User Experience:** Provides a distinct micro-goal and visual target in an unexplored zone. No name is shown to preserve the mystery.



**Phase 2: The Unlocking (Triggered)**

* 
**Visual Treatment:** The fog permanently burns away as the user's GPS buffer radius intersects the hexagon containing the POI.


* 
**User Experience:** Triggers the gamified Discovery Modal to present the fun fact and unlocked benefits.



**Phase 3: The Archive (Cleared)**

* 
**Visual Treatment:** The beacon permanently transforms into a subtle, faint pin embedded seamlessly into the base map layer.


* 
**User Experience:** Unobtrusive design ensures the pin does not clutter the cleared satellite map. Users can tap the pin to review the location's lore at any time.