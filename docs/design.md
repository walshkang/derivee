# `design.md`: Fog of Wburg

## 1. Core Philosophy: The Ambient Explorer

"Fog of Wburg" is not a traditional, heavy cartography app, nor is it an aggressive completionist game. It is a mindful **harness for real life**. The core objective is informative discovery.

Inspired by *Zelda: Breath of the Wild* and the minimalism of modern *Google Maps*, the app relies heavily on **progressive disclosure**. Information is only offered when physically relevant or explicitly asked for. The UI gets out of the way, encouraging the user to look up at the real world.

---

## 2. Visual Identity

The aesthetic abandons dark, rigid, parchment-style mapping in favor of a fluid, airy, and native modern mobile experience.

* **Theme:** Light Mode default. The app should feel like a clear morning.
* **Color Palette:** Soft whites, light grays, and diffuse frosted-glass translucency (utilizing native OS blurring like Expo's `UltraThinMaterial`).
* **Typography:** Clean, modern geometric sans-serif (e.g., *SF Pro* on iOS, *Inter* on Android). Fonts are used strictly for high-legibility data visualization, never for heavy UI framing.
* **UI Layout:** The map *is* the UI. Buttons and stats float gently over the map, utilizing high negative space. Elements remain practically invisible until needed.

---

## 3. Map Layers & The "Cloud" Mechanic

The "fog of war" is no longer a punishing binary blackout; it utilizes a volumetric, 3-Tier visibility model (Unexplored, Explored, Visible) that sparks curiosity while maintaining a pristine map.

### The Layer Stack (Bottom to Top)

1. **The Explored Base:** High-resolution satellite imagery permanently desaturated (grayscale) and dimmed. This layer represents areas the user has previously cleared but is not currently occupying.
2. **The Visible Base:** Full-color, vibrant satellite imagery, revealed strictly inside the user's active, reference-counted line of sight.
3. **The Sub-Context (The Tease):** Faint vectors of major geographic arteries—coastlines, bridges, and primary arterial roads. Rendered with low opacity and **zero text labels**. This provides a subconscious lure to explore.
4. **The Cloud Layer (The Fog):** A regional mask (pitch black where Unexplored) rendered as a soft, translucent layer with a high blur radius, feeling diffuse and 3D.
5. **The Holes (The Cleared Path):** Unlocked H3 hexes (both Explored and Visible) punch through the Cloud Layer, revealing the pristine bases and sub-context below. MapLibre's `fill-opacity-transition` ensures new holes dissolve smoothly over 300ms rather than instantly popping into view.

---

## 4. The Vicinity Bubble (Dynamic Context)

To ensure the map never becomes a cluttered utility clone, detailed geospatial data only exists precisely where the user is physically standing.

* **The Active Radius:** A tight physical radius (e.g., 200 meters) anchored to the user's live GPS ping.
* **Progressive Disclosure:** Inside this bubble, crisp vector data appears: street names, unbranded geometric nodes for transit stops, and bike-share racks.
* **Pristine History:** When the user pans the camera away from their live location to view an area cleared weeks ago, they see only clean satellite terrain. Heavy map data is strictly localized to the user's current physical presence.

---

## 5. Interaction Model: Ghost POIs

We do not use permanent map pins for Points of Interest (POIs) or historical landmarks, preserving a pristine visual state.

* **The Lure:** Inside the fog, an unexplored POI may emit a soft, diffuse glow, providing a nameless target.
* **The Ghost (Cleared State):** Once a hex is unlocked, the POI becomes completely invisible.
* **The Reveal:** If a user is physically standing inside that cleared hex and intentionally taps their location, a clean bottom-sheet modal slides up, revealing the location's history or utility.

---

## 6. Transit Integration (The Naver Maps Approach)

Transit nodes (subway entrances, bus stops) are integrated as Ghost POIs. When a user taps a minimalist transit node inside their Vicinity Bubble, the app pulls from raw GTFS feeds to provide an elite, commuter-grade tool.

### The Transit Bottom-Sheet

* **Live Arrivals:** Crisp, bold typography displaying real-time countdowns (e.g., "3 min", "8 min") decoded directly from the transit authority's GTFS-RT Protocol Buffers.
* **Route Previews:** A dynamic, colored vector line traces the vehicle's upcoming path onto the map for instant spatial context.
* **Service Alerts:** Subtle, highly visible text warnings for reroutes or delays.
* **Historical Reliability (Sparklines):** A small, elegant sparkline chart or text summary showing average headway and historical arrival reliability over the past 7 days (powered by The Observer: a custom Go daemon that generates lightweight Zstandard-compressed SQLite nightly builds).

---

## 7. Core User Flows & Screens

Because "The map *is* the UI", we eliminate heavy HUDs, intrusive gamified modals, and session-based "Start/Stop" buttons. The app is designed to open instantly to ambient utility.

### Screen 0: The Dissolve (Splash Screen)
* **Visuals:** The app opens to a completely frosted, blurred screen (representing the Cloud layer). 
* **Animation:** The frost fluidly dissolves or "wipes" away, centering smoothly onto the user's live physical location and their crisp Vicinity Bubble.

### Screen 1: The Ambient View (Main Map)
* **Visuals:** Full-screen edge-to-edge map. No heavy headers or footers. The frosted Cloud layer covers everything outside the user's 200m Vicinity Bubble (and any previously cleared history).
* **Controls:** 
  * A floating, minimalist "Locate Me" FAB (Floating Action Button).
  * A subtle, floating Profile/Archive icon (top corner).
  * A subtle Settings icon.
* **Absence of HUD:** No aggressive "Distance Traveled" or "Time Elapsed" widgets covering the screen. It is just you and the geography. 

### Screen 2: The Reveal (Bottom Sheet)
* **Trigger:** The user taps their current location when standing on a Ghost POI or Transit Node.
* **Visuals:** A clean, native iOS/Android bottom-sheet slides up over the bottom third of the map with a frosted glass backdrop (`UltraThinMaterial`).
* **Content:** Real-time transit countdowns (Naver Maps style) or historical lore about the unlocked Ghost POI.
* **Interaction:** Swiping down instantly dismisses it, returning the user to the pristine map. No clunky "Dismiss" buttons required.

### Screen 3: The Archive (Profile & Memory)
* **Trigger:** Tapping the Profile icon.
* **Visuals:** A full-screen modal with a soft, translucent frosted background.
* **Content:** 
  * **Macro-Level Metrics:** Total "Area Uncovered" (measured in square kilometers or hex count) alongside a satisfying **Percentage Complete** for their current neighborhood or city (e.g., "Williamsburg: 14% Cleared"). This retains the addictive completionist hook while still feeling premium.
  * **The Collection:** A clean, chronological list or masonry grid of discovered Ghost POIs.

### Screen 4: Preferences (Settings)
* **Visuals:** Clean, native list UI.
* **Content:** Toggles for the Transit Layer, Apple HealthKit/Fitness sync, Background Location permissions, and perhaps a slider to adjust the opacity of the "Cloud" layer.