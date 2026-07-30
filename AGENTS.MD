# AGENTS.md — Project-Level Instructions for AI Sessions ("Dérivée")

## 🤖 AI Session Startup & Operational Rules

* **Framework Constraint**: This project uses a **hybrid "Brownfield" architecture** under the **Sleepy Hermes** paradigm. Expo Managed Workflow (CNG / Prebuild) governs UI rendering, navigation, and config plugins. The `ios/` native workspace is **manually managed** for Nitro Module linkage, the H3 C-library bridging header, and the native Swift background service. All other native configurations (permissions, app icons, splash) must still be handled via `app.json` config plugins.
* **Environment Execution**: Always use `python3` for any auxiliary scripts, and standard npm/yarn/pnpm commands for Expo runtime management.
* **Strict Adherence**: Adhere strictly to the locked-in library versions and patterns defined in `architecture.md` and `design.md`. Do not introduce alternative libraries (e.g., do not swap `@maplibre/maplibre-react-native` for `@rnmapbox/maps`, and do not use asynchronous storage wrappers instead of `@op-engineering/op-sqlite`).

---

## ⛔ Sleepy Hermes — Forbidden Patterns

The following patterns are **absolutely prohibited** under the Sleepy Hermes architecture. Violating these rules will cause iOS watchdog terminations (`0x8badf00d`, `0xdead10cc`), catastrophic battery drain, and bridge congestion.

* **React Native Headless JS**: **Never** use React Native's `HeadlessJsTaskService` or any equivalent mechanism to run JavaScript in the background. The Hermes engine must be permitted to sleep.
* **`react-native-background-actions`**: **Never** install or reference this library. It wraps HeadlessJS and is fundamentally incompatible with Sleepy Hermes.
* **`expo-task-manager` for background location**: **Never** use `TaskManager.defineTask()` or `Location.startLocationUpdatesAsync()` for background tracking. These execute JavaScript in the background, violating the core paradigm.
* **Time-based background polling**: **Never** implement `setInterval`, `setTimeout`, or any timer-based mechanism for background GPS coordinate acquisition. Background tracking must use hardware-level distance filtering via the native Swift `CLLocationManager` (`distanceFilter: 10`, deferred updates: `50m`).
* **Background JavaScript execution of any kind**: All background spatial hashing, drift mitigation, and database persistence runs exclusively in the **pure native Swift layer**. The JS thread must remain completely dormant when the app is backgrounded.

---

## 🔧 Xcode GUI Linkage Protocol

The project operates under a **Brownfield constraint** that prohibits programmatic modifications to native project files for Nitro/H3 integration.

* **NEVER script or programmatically alter `ios/*.pbxproj`**: All Nitro Module linkage, H3 C-library header imports, bridging header configuration, and Swift implementation file additions must be performed **exclusively through the Xcode Graphical User Interface** by the human developer.
* **Agent responsibility**: When a task requires native file changes (adding a new Swift file, importing generated Nitrogen sources, updating the bridging header), the agent must produce **clear, step-by-step Xcode GUI instructions** for the human developer to execute manually. Never attempt to automate these steps via shell commands, `sed`, `ruby`, or `xcodeproj` scripts.
* **Workspace, not project**: Always instruct the human to open `ios/Derivee.xcworkspace` (the CocoaPods workspace), **not** the bare `.xcodeproj`.
* **"Create groups" not "Create folder references"**: When importing files into Xcode, always instruct selection of "Create groups" to ensure the Swift compiler properly indexes the files.

---

## 🎨 UI & Ambient Explorer Constraints

* **Progressive Disclosure strictly enforced**: The map is the UI. **Never** build heavy, persistent HUDs (like constant "Distance Traveled" widgets overlaying the screen).
* **Ambient Tracking**: The app uses an always-on, ambient tracking model. Never build manual 'Start/Stop Tracking' UI elements. Tracking begins silently via the native Swift `CLLocationManager` on open.
* **Aesthetics**: Dynamic Day/Night Cycle based on local First Light (Sunrise) and Last Light (Sunset). Day Mode uses soft parchment whites (`#F9F9F6`) and matte graphite fog (`#1C1C1E`). Night Mode uses deep midnight slate (`#12121A`) and OLED black fog (`#000000`). The universal accent color is **Electric Amber (`#FFB300`)** — used for the live GPS dot, active transit routes, and Ghost POI glows. Typography uses SF Pro / Inter for UI text; **SF Mono** exclusively for all quantitative metrics (percentages, headways, H3 IDs). Apple's native `UltraThinMaterial` (Light/Dark variant) for floating elements. Avoid serif fonts; strictly use modern geometric sans-serif.
* **Ghost POIs**: **Never** implement permanent map pins or markers for Points of Interest or Transit nodes. They must be completely invisible in cleared hexes.

---

## 🗺️ Map Rendering & Architecture Guardrails

### 1. Dynamic Regional Loading (No Worldwide Polygons)

* **Memory Protection**: **Never** attempt to generate a single GeoJSON polygon covering the entire Earth to act as the fog.
* **Rule**: Always generate a localized 50km x 50km bounding box centered on the user's current GPS coordinate upon initialization.

### 2. The 6-Layer Stack (3-Tier Visibility)

When configuring `@maplibre/maplibre-react-native`, you must strictly adhere to this exact Z-index stacking order to achieve desaturation natively:

* **Layer 1 (The Explored Base)**: `RasterLayer` rendering satellite imagery permanently dimmed (`rasterSaturation: -1.0`, reduced brightness).
* **Layer 2 (The Visible Base)**: Full-color satellite `RasterLayer` identical to Layer 1, but masked strictly by the user's active line-of-sight polygon.
* **Layer 3 (The Sub-Context)**: Faint vectors (major arteries/coastlines) with zero text labels.
* **Layer 4 (The Cloud Layer)**: The 50km bounding box rendered as a soft, translucent polygon with a high blur radius and `fill-opacity-transition: { duration: 300 }`.
* **Layer 5 (The Holes)**: Unlocked H3 hexes (both Explored and Visible) configured as inner rings to punch through Layer 4.
* **Layer 6 (The Vicinity Bubble)**: The active 200m radius rendering street names and Ghost POIs.

### 3. Vicinity Bubble & PiP Checks

* **Interaction Rule**: Because POIs are invisible ("Ghosts"), interactions are handled via a Geospatial Point-in-Polygon (PiP) check.
* **Rule**: When a user taps the map, calculate the coordinate, ensure they are within physical proximity, and query `@op-engineering/op-sqlite` synchronously to trigger the bottom sheet.

### 4. Bridge Congestion Prevention & Data-Driven Styling

* **JSI Updates**: **Always** enable `withSynchronousUpdate(true)` on any `ShapeSource` to bypass JSON stringification penalties over the React Native bridge.
* **In-Memory Set Gate**: Maintain a local JavaScript `Set` of unlocked H3 string IDs. On every Nitro callback or AppState hydration, perform an $O(1)$ lookup (`Set.has(currentH3Index)`). If the user is in an already-cleared area, do absolutely nothing (drop execution) to keep the bridge silent.
* **Geometry Worker (DDS)**: **Never** use `h3.cellsToMultiPolygon` or heavy GeoJSON stringification for hole-punching (this is a deprecated legacy approach). Instead, use MapLibre Data-Driven Styling (DDS). Treat the fog as a static base grid and dynamically filter the `fill-opacity` by passing the array of unlocked IDs into a `['match']` expression.
* **UI Thread Protection**: Secondary screens (like Stats) should use lightweight representations or virtualized lists (`@shopify/flash-list`) and `InteractionManager` rather than triggering heavy multi-polygon math.

---

## 🚇 Transit & Local Data Pipeline

* **No Live APIs for History**: **Never** attempt to calculate historical transit headways by polling live APIs on the mobile client. Historical sparkline data is strictly fetched once daily as a static Zstandard-compressed SQLite delta database (`.sqlite.zst`) generated by our Go-based persistent daemon (The Observer).
* **On-Thread Decoding**: When a user taps a transit node, decode the binary `protobufjs` GTFS-RT feeds natively on the JS thread for real-time countdowns.

---

## 💾 Core Technical Guardrails (Data & Tracking)

### 1. H3 Index Precision & Data Types

* **String Enforcement**: H3 indices are 64-bit integers. **Always** store, transmit, and process H3 indices as 15-character hexadecimal strings (e.g., `"8b2a100d213fff"`). Never cast them to raw numbers.
* **Swift-Side Mandate**: All H3 64-bit integer calculations performed in the native Swift layer (via the H3 C-library `latLngToCell`) **must** be immediately converted to 15-character hexadecimal strings **before** database insertion. The ECMAScript standard represents all numbers as double-precision 64-bit floats, which can only safely represent exact integers up to $2^{53} - 1$. If a raw 64-bit integer is inserted into SQLite by Swift and later read by the JS `@op-engineering/op-sqlite` connection, **catastrophic precision truncation** will permanently corrupt the spatial grid.

### 2. Local Persistence & SQLite Directives

* **Dual-Connection Model**: The application maintains **two concurrent SQLite connections** to the same physical `.db` file — one via `@op-engineering/op-sqlite` (JS/JSI, foreground reads) and one via the raw SQLite C API (Swift, background writes). Both must be configured for WAL mode.
* **Synchronous JSI Driver**: Use `@op-engineering/op-sqlite` exclusively for all foreground JavaScript data persistence and reads.
* **Native C-API Driver**: Use `sqlite3_open_v2` with `SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX` for the Swift background connection. Use prepared statements (`sqlite3_prepare_v2`) exclusively.
* **Schema Mandates**: Any SQLite table containing H3 data **must** initialize with `PRAGMA journal_mode = WAL;` and include the `WITHOUT ROWID` clause to enforce direct clustered B-Tree indexing on the string primary key.

### 3. Background Battery & Location Rules

* **No Polling**: Time-based GPS polling is prohibited. Background location tracking uses hardware-level distance filtering (`distanceFilter: 10`, deferred updates: `50m`) via the native Swift `CLLocationManager`.
* **Drift Gate**: All background coordinate updates must pass an Implied Speed filter ($\Delta d / \Delta t \le 12 \text{ m/s}$) to discard multipath noise before hitting the H3 grid.
* **Background Task Assertions**: Every background location processing block must be wrapped in `beginBackgroundTask` / `endBackgroundTask` to prevent iOS watchdog termination. Failure to release the task identifier will result in `0x8badf00d`.

---

## 📋 Roadmap Execution & Protocol

When executing tasks from `ROADMAP.MD`:

1. **Atomic Scoping**: Focus entirely on the assigned Task ID. Do not bleed into subsequent waves.
2. **Verification**: Run local tests, prebuild checks, or type-checking to verify the implementation.
3. **Roadmap Hygiene**:
* Once verified, update the task status in the **Master Status Table** from `Planned` to `✅ Done`.
* Move the completed task's detailed prompt block out of `roadmap.md` and append it to `archive/shipped-waves-archive.md`.

---

## 🧪 Testing & Verification Rules

### 1. Mocking Native JSI, Nitro, & Map Modules (Jest)
Because we use `@op-engineering/op-sqlite` (JSI-based), `react-native-nitro-modules`, and `@maplibre/maplibre-react-native`, standard Node.js/Jest unit tests will crash if not mocked.
- **Rule**: Provide robust manual mocks when writing unit tests for store logic or utility functions. The JSI engine and Nitro bindings do not exist in the standard Jest environment.

### 2. H3 Precision Sanity Checks
JavaScript loses precision on 64-bit integers. It's very easy to accidentally cast an H3 index to a Number during serialization.
- **Rule**: All tests validating H3 utility functions or database operations must explicitly assert that inputs and outputs are strictly strings (`typeof === 'string'`). Add regression tests using `Number.MAX_SAFE_INTEGER` boundaries to ensure no silent truncation occurs.

### 3. Background Service Testing
The Swift `CLLocationManager` background service cannot be unit-tested in a standard Jest environment.
- **Rule**: When writing tests for the "Velocity Gate" (Implied Speed Filter), decouple the coordinate math from the native listener. Write pure functions for calculating distance/time so they can be unit-tested without needing the native location emitter context.
- **Rule**: For testing the Nitro callback flow, mock the `HybridTracker` interface and verify that Zustand store updates fire correctly when the mock invokes the registered callback.

### 4. Native Build Verification
In the Brownfield architecture, native behavior changes require verifying both Expo CNG and the manual Xcode workspace.
- **Rule**: After Expo config plugin changes, run `npx expo prebuild --clean` to verify `Info.plist` / `AndroidManifest.xml` generate correctly.
- **Rule**: After manual Xcode changes (Nitro linkage, bridging header updates), verify the native build compiles successfully via `xcodebuild` or the Xcode GUI.

### 5. E2E and Performance Profiling
Since the biggest risk is frame drops during the MapLibre fog rendering, unit tests are insufficient for performance guarantees.
- **Rule**: UI and map performance verification should be done on a physical device or via an E2E framework (like Maestro). Never trust the iOS Simulator/Android Emulator performance for MapLibre fog rendering.