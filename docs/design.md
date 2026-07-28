# design.md: Fog of Wburg

## 1. Core Philosophy & Visual Identity
"Fog of Wburg" is a location-based fog-of-war tracker and transit utility. It relies on standard MapTiler data for base cartography, focusing custom UI purely on fog mechanics, workout tracking, and transit information. The UI is literal, actionable, and strictly utilizes native OS paradigms.

* **Theme:** Light Mode default. Soft whites and light grays.
* **Typography:** OS Native (SF Pro on iOS, Inter on Android). Used strictly for clear labels and data visualization, not decoration.
* **Actionable UI:** No ambiguous navigation. Icons must be paired with explicit text (e.g., a pill button that explicitly reads "Start Tracking").

## 2. The 3-Tier Fog Visibility Logic
The map utilizes a 3-tier state to separate where the user is, where they have been, and what is left to discover. Unlocked H3 hexes (Resolution 11) feature a subtle border outline to define the progression grid.

1.  **Hidden (Unexplored):** A high-blur, translucent dark mask covering the map. No base map details or pins are visible beneath it.
2.  **Explored (Visible but Inactive):** Areas previously cleared but not currently occupied. The map renders in desaturated (grayscale) satellite imagery. H3 hexes display a slight, semi-transparent outline.
3.  **Active (Exposed / Current Vicinity):** The immediate 200m radius around the live GPS location during a tracking session. The map renders in full-color, vibrant satellite imagery. Hex outlines remain visible.

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

### Screen 1: Main Map
The primary interface for viewing progress and recording new geospatial data.
* **UI Elements:** Edge-to-edge MapLibre map. A prominent pill-shaped floating button at the bottom reading "Start Tracking". Top-bar text buttons for "History" (top-left) and "Settings" (top-right).
* **Definition of Done:**
    * MapTiler base layer renders successfully.
    * The 3-tier fog logic correctly masks the map based on the user's SQLite database of unlocked hexes.
    * Subtle hex outlines render exclusively inside Explored and Active zones.
    * Tapping "Start Tracking" initiates background GPS polling, toggles the button text to "Stop Tracking", and actively unlocks new hexes in real-time.

### Screen 2: Transit Details (Bottom Sheet)
A utility view that appears only when interacting with a transit pin.
* **UI Elements:** A native bottom sheet sliding up over the map (utilizing standard native blurring). Displays the station/stop name and a list of upcoming departures.
* **Definition of Done:**
    * Sheet triggers instantly upon tapping a Subway or Bus pin.
    * Real-time GTFS countdowns (e.g., "3 min", "8 min") populate accurately for the selected stop.
    * The sheet can be dismissed by swiping down or tapping the map outside the modal.

### Screen 3: History & Uploads
A straightforward list of past activity and the interface for importing historical `.gpx` and `.fit` files locally.
* **UI Elements:** A full-screen list view. A prominent "Upload Previous Workouts" button at the top. Top-level stats showing total hexes cleared. A chronological list of past tracking sessions and uploaded routes.
* **Definition of Done:**
    * Displays a summarized metric of total area/hexes unlocked.
    * Allows the user to select local files via `expo-document-picker`.
    * **Processing Constraints (Crucial for JS Thread):** Uses `fast-xml-parser` (for GPX) or a lightweight FIT decoder to parse files locally. The parsing loop *must* be chunked (e.g., using `setTimeout` or `requestAnimationFrame` every 1,000 points) to prevent UI freezing. Coordinate arrays must be downsampled (e.g., checking >10m deltas) before passing to `h3-js`.
    * Deduped hex arrays are saved using bulk/batch SQLite inserts.
    * Processing an upload successfully updates the main map's Explored fog state.
    * Tapping a past session list item highlights that specific route path on the map.

### Screen 4: Settings
Standard application preferences and account management.
* **UI Elements:** A standard native list grouping toggles and permissions.
* **Definition of Done:**
    * Includes functional toggles for Background Location permissions and Push Notifications.
    * Includes a destructive button to clear local cache/data or reset the map/SQLite database entirely.