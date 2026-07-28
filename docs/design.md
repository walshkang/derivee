# design.md: Fog of Wburg

## 1. Core Philosophy & Visual Identity
"Fog of Wburg" is a location-based fog-of-war tracker and transit utility. It relies on standard MapTiler data for base cartography, focusing custom UI purely on fog mechanics, workout tracking, and transit information. The UI is literal, actionable, and strictly utilizes native OS paradigms.

* **Theme:** Light Mode default. Soft whites and light grays.
* **Typography:** OS Native (SF Pro on iOS, Inter on Android). Used strictly for clear labels and data visualization, not decoration.
* **Actionable UI:** No ambiguous navigation. Icons must be paired with explicit text.

## 2. The 3-Tier Fog Visibility Logic
The map utilizes a 3-tier state to separate where the user is, where they have been, and what is left to discover. Unlocked H3 hexes (Resolution 11) feature a subtle border outline to define the progression grid.

1.  **Hidden (Unexplored):** A high-blur, translucent dark mask covering the map. No base map details or pins are visible beneath it.
2.  **Explored (Visible but Inactive):** Areas previously cleared but not currently occupied. The map renders using the base MapTiler `streets-v2` style. H3 hexes display a slight, semi-transparent outline.
3.  **Active (Exposed / Current Vicinity):** The immediate 200m radius around the live GPS location during a tracking session. The map renders using the base MapTiler `streets-v2` style, unmasked. Hex outlines remain visible.

## 3. Zoom Reveal & Pin Logic
We trust MapTiler to handle standard map geography (streets, travel direction, parks). Our custom data overlay is strictly limited to Transit.

* **Allowed Custom Pins:** Subway Entrances and Bus Stops.

### Zoom Level Framework
| Zoom Level | Map Focus | Visible Elements |
| :--- | :--- | :--- |
| **0 – 11** | City / Region | Fog layer dominates. Base map geography is visible. No pins or heavy text. |
| **12 – 14** | Neighborhood | Unlocked hex outlines appear. Major arterial roads and neighborhood names render via MapTiler. |
| **15 – 16** | Street Level | MapTiler street names and travel directions fade in. Subway pins become visible in Active and Explored zones. |
| **17+** | Granular Detail | Bus stop pins fade in. Building footprints and exact street geometries are fully visible in exposed areas. |

## 4. Screen Framework & Definitions of Done (DoD)
The app uses a standard, intentional session model. Screens have literal names and explicit purposes.

### Screen 0: Splash / Loading Screen
A transient loading screen to establish the app's visual identity before transitioning to the map.
* **UI Elements:** An atmospheric fog background animation, a subtle pulsing logo, and the title 'Fog of Williamsburg'. No interactive buttons.
* **Definition of Done:**
    * Automatically transitions to the Main Map after a short delay (e.g. 2 seconds).
    * Handles any necessary initial data loading or permission checks transparently.

### Screen 1: Main Map
The primary interface for viewing progress and recording new geospatial data.
* **UI Elements:** Edge-to-edge MapLibre map. Top-bar text buttons for "History" (top-left) and "Settings" (top-right).

**UI Element: The Contextual Stat Pill (Progressive Disclosure)**
To maintain the pristine, map-first aesthetic, exploration stats are NOT displayed in a permanent, heavy dashboard. Instead, they utilize a lightweight, floating "pill" overlaid on the map.

* **Location:** Top-center of the map, floating over the fog (styled with a frosted glass/blur effect).
* **Behavior:** The pill is dynamic and context-aware based on the user's current GPS location.
* **Content States:**
  * *Idle / Explored Area:* When stationary or moving through already-cleared territory, it shows macro progress. (e.g., "📍 Williamsburg • 14% Explored").
  * *Active Discovery:* When the user enters unexplored fog and begins clearing new hexes, the pill smoothly transitions to highlight real-time momentum. (e.g., "🔥 42 New Hexes Unlocked Today"). Because tracking is always ambiently on, this state triggers automatically upon new hex discovery.

* **Definition of Done (Screen 1 & Stat Pill):**
    * MapTiler base layer renders successfully.
    * The 3-tier fog logic correctly masks the map based on the user's SQLite database of unlocked hexes.
    * Subtle hex outlines render exclusively inside Explored and Active zones.
    * Tracking begins silently and ambiently upon app launch and continues tracking progress on the map at all times, even when the screen is off or the app is in the background. There is no manual 'record' or 'start' button.
    * The stat pill uses `@react-native-community/blur` for a native iOS frosted glass background.
    * Typography is small, native (SF Pro), and highly legible.
    * The pill queries the local SQLite `neighborhood_stats` table to calculate the percentage `(cleared_hexes_in_poly / total_hexes_in_poly) * 100`.
    * The stat updates performantly without locking the UI thread (debounced or updated via a React `useTransition`).

### Screen 2: Transit Details (Bottom Sheet)
A utility view that appears only when interacting with a transit pin.
* **UI Elements:** A native bottom sheet sliding up over the map (utilizing standard native blurring). Displays the station/stop name and a list of upcoming departures.
* **Definition of Done:**
    * Sheet triggers instantly upon tapping a Subway or Bus pin.
    * Real-time GTFS countdowns (e.g., "3 min", "8 min") populate accurately for the selected stop.
    * The sheet can be dismissed by swiping down or tapping the map outside the modal.

### Screen 3: The Archive (Macro-Stats & History)
This screen is the dedicated space for heavy metrics. Since the user actively navigated here, we can drop the "progressive disclosure" rules and show them their complete geographic dominance.

* **UI Elements:**
  * **The City-Wide Matrix:** A clean, horizontal scroll of cards or a grid showing top-level city completion (e.g., "New York City: 4.2% Complete").
  * **Neighborhood Leaderboard:** A vertical, native list breaking down the user's progress by neighborhood, sorted by highest completion percentage. (e.g., "1. Williamsburg - 42%", "2. Greenpoint - 18%").
  * **Session History:** A chronological list of past tracking sessions and uploaded `.gpx` routes, showing the specific number of hexes unlocked per session.
  * A prominent "Upload Previous Workouts" button at the top (or accessible via this view).

* **Definition of Done:**
    * Queries the local SQLite database grouping unlocked H3 hexes by their assigned neighborhood boundaries.
    * Uses standard iOS native list UI (avoid heavy custom graphs; rely on clean typography and simple native progress bars).
    * Tapping a specific neighborhood pans the background map to that neighborhood's coordinates.
    * Allows the user to select local `.gpx` or `.fit` files via `expo-document-picker`.
    * **Processing Constraints:** Uses `fast-xml-parser` (for GPX) or a lightweight FIT decoder. Parsing must be chunked to prevent UI freezing, coordinate arrays downsampled (>10m deltas), and deduped hexes saved via bulk SQLite inserts.
    * Processing an upload successfully updates the main map's Explored fog state.

### Screen 4: Settings
Standard application preferences and account management.
* **UI Elements:** A standard native list grouping toggles and permissions.
* **Definition of Done:**
    * Includes functional toggles for Background Location permissions and Push Notifications.
    * Includes a destructive button to clear local cache/data or reset the map/SQLite database entirely.

## 5. The "Backend" (Data Layer) Work - Progression Stats

To support the progression stats shown in the Contextual Stat Pill and The Archive, the local database must be updated:

1. **The Denominator Problem:** Right now, the app only knows what you *have* explored. To calculate a percentage, it needs to know the total size of the container.
2. **Neighborhood Lookup:** You will need to seed your local SQLite database with a static lookup table (e.g., `neighborhood_stats`). It could map a neighborhood name ("Williamsburg") to its bounding polygon or simply to its total H3 Resolution 11 hex count (e.g., "Williamsburg = 14,200 total hexes").
3. **Current Session:** This is entirely front-end/local state. Your Zustand store just needs to track `sessionUnlockedHexes` and compare it against the current neighborhood's total.
4. **The Denominator Masking Logic (Landmass & Bridges Only):** To ensure the "Total Hexes" denominator is actually achievable by a pedestrian or cyclist, the static generation script must strictly exclude open water.
    * **The Operation:** Before generating the H3 hexes for a neighborhood, the script must take the neighborhood's bounding polygon and perform a boolean geographic subtraction using standard OSM (OpenStreetMap) or Natural Earth water polygons. `(Neighborhood_Polygon) MINUS (Water_Polygons) = Walkable_Polygon`.
    * **The Bridge Exception:** Bridges (e.g., Williamsburg Bridge, pedestrian overpasses) are physically suspended over water but are valid exploration zones. The script must ensure that known pedestrian/cycling bridge geometries are re-added or preserved in the `Walkable_Polygon` before the H3 polyfill operation calculates the final hex count.
    * **The Output:** The final integer saved to `neighborhood_stats.total_hexes` must represent only landmass and bridge hexes.