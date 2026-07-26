# 🌫️ Fog of Wburg

**Fog of Wburg** is an offline-first iOS (and eventual Apple Watch) application built entirely within the Expo Managed Workflow. It gamifies real-world exploration by applying a permanent "fog of war" mechanic to a real-world map, heavily inspired by games like *Civilization VI*.

This project utilizes an AI-first "vibe coding" approach, prioritizing nimble development without manual Xcode management.

---

## 🗺️ Core Features

* **Real-World Exploration:** The world starts shrouded in a dark, stylistic fog. Active physical movement dynamically burns away the fog to reveal high-resolution 3D terrain and satellite imagery. Once a hexagon is cleared, it is unlocked forever.
* **Smart Unlocking (Buffer Radius):** Fog clearing is dictated by a buffer radius around the user's GPS coordinates. This allows users to clear city blocks, private residences, and buildings entirely from public sidewalks, preventing accidental trespassing.
* **Gamified Waypoints:** Open-source Points of Interest (POIs) act as soft, glowing beacons in the fog to lure users to unexplored areas. Upon discovery, they trigger a reward modal and transform into unobtrusive pins embedded in the base layer.
* **Privacy-First & Offline:** Unlocked regions are stored locally on the device using a high-performance SQLite database. There is no creepy 24/7 server tracking.
* **Battery-Conscious Tracking:** Location tracking operates in the background via a Foreground Service only during an active "Expedition." By utilizing hardware-level distance intervals rather than time-based polling, the application naturally idles when the user is stationary.

---

## 🛠️ The Tech Stack (Expo CNG)

To achieve native-level performance and microsecond memory sharing without ejecting from Expo, this architecture strictly relies on the following stack:

* **Framework:** Expo SDK 51+ (Continuous Native Generation).
* **Map Engine:** `@maplibre/maplibre-react-native` (Bypasses proprietary Mapbox fees; supports JSI synchronous updates and 3D Raster DEM).
* **Grid System:** `h3-js` (Uber's H3 spatial index, compiled via Emscripten for blazingly fast JS-thread execution). Target Resolution: 11.
* **Persistence:** `@op-engineering/op-sqlite` (JSI-powered SQLite engine for synchronous, non-blocking read/writes).
* **Location Services:** `expo-location` combined with `expo-task-manager`.
* **State Management:** `zustand`.

---

## 🏗️ Architecture & Rendering Pipeline

Rendering tens of thousands of unlocked hexagons simultaneously requires strict memory management and bridge-bypass techniques.

### Dynamic Regional Loading

To prevent out-of-memory crashes, the app **never** generates a worldwide fog layer. Upon initialization, it generates a lightweight 50km x 50km GeoJSON bounding box centered on the user's current coordinate. If the user leaves this metropolitan boundary, the old box is dropped and a new one is generated.

### The Inverted Polygon Stack

Instead of rendering individual hexagonal tiles, the app punches transparent holes through the dark 50km fog layer. Map layers are stacked from bottom to top:

1. **Layer 1 (The Reward):** High-resolution satellite imagery + 3D Terrain extrusion.
2. **Layer 2 (The Blocker):** The 50km dark GeoJSON polygon (the Fog).
3. **Layer 3 (The Holes):** The user's unlocked H3 hexagons, added as "inner rings" to punch holes in Layer 2.
4. **Layer 4 (The Guide):** Vector boundaries (coastlines, streets, labels) rendered *above* the fog for navigational context.

### Algorithmic Simplification & Bridge Bypass

Map engines use the Earcut algorithm to triangulate polygons. Processing thousands of individual hexagonal holes degrades performance to $O(N^2)$.

* **Geometry Worker:** Before updating the map, adjacent unlocked hexagons are periodically merged using `h3.cellsToMultiPolygon` to drastically reduce vertex counts.
* **Synchronous Execution:** We enable `withSynchronousUpdate(true)` on the MapLibre `ShapeSource` to bypass the React Native asynchronous bridge and `JSON.stringify` serialization, sharing memory directly between the Hermes engine and C++.

---

## 💾 Local Persistence Strategy

The application executes high-frequency spatial lookups continuously while the user moves. The `@op-engineering/op-sqlite` database is configured for raw speed:

* **Data Type Strictness:** H3 indexes are 64-bit integers that exceed standard JavaScript memory limits. They are strictly stored and passed as 15-character hexadecimal strings.
* **Write-Ahead Logging (WAL):** Enabled via `PRAGMA journal_mode = WAL;` to allow concurrent background tracking writes and UI-thread reads without database locking.
* **Clustered Indexing:** The primary table utilizes the `WITHOUT ROWID` declaration, forcing SQLite to use the H3 index string directly as the B-Tree index. This guarantees $O(\log N)$ or near $O(1)$ lookup speeds and reduces device footprint by 30%.

---

## 🔋 Battery Optimization & Drift Mitigation

Background location tracking is meticulously configured to preserve user battery and comply with iOS App Store guidelines:

* **Distance over Time:** `distanceInterval` is set to 10 meters. The CPU remains asleep until physical movement occurs.
* **Hardware Batching:** `deferredUpdatesDistance` is set to 50 meters, holding coordinates in the GPS chip's silicon memory and waking the primary CPU only once per batch.
* **Implied Speed Filter (Drift Gate):** To prevent urban canyon GPS multipath errors from artificially unlocking city blocks, all coordinates pass through a velocity gate. Any jump yielding an implied speed of $> 12 \text{ m/s}$ is immediately discarded as multipath noise.