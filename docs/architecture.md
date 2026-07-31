# Dérivée: Architecture & Technical Specification

This document defines the strictly enforced architectural paradigms, library choices, and data flows for **Dérivée**.

The application is an offline-first, battery-conscious iOS app built as a **hybrid "Brownfield" architecture**. It uses Expo for UI rendering, navigation, and config plugins, while critical background operations execute in a **pure native Swift layer** that bypasses the JavaScript engine entirely.

---

## 1. The Sleepy Hermes Paradigm

### Why Not JavaScript in the Background?

Modern iOS aggressively monitors background CPU cycles. When an application attempts to evaluate JavaScript in the background — complete with Hermes garbage collection sweeps, asynchronous bridge serialization, and React state reconciliations — while the device is locked, the iOS watchdog rapidly terminates the application. These terminations yield:

* **`0x8badf00d`** — Watchdog timeout: the app failed to relinquish CPU within the allotted background window.
* **`0xdead10cc`** — Resource deadlock: the app held file locks or system resources during suspension.

Both are fatal, unrecoverable crashes that destroy the ambient tracking experience.

### The Solution: Sleepy Hermes

The "Sleepy Hermes" paradigm **severs all reliance on background JavaScript execution**. The architecture isolates all background operations to a **pure, native Swift layer**:

* **When the app is backgrounded or the screen is locked:** The Hermes JavaScript engine enters a fully suspended state (sleeps). A highly optimized, low-power **Swift `CLLocationManager`** intercepts hardware location coordinates, executes Uber's H3 spatial hashing algorithms natively via C-library interop, and persists the resulting unlocked hexadecimal grid indices directly to an embedded SQLite database using the raw C API.
* **When the user foregrounds the app:** The JavaScript layer hydrates from the shared SQLite database via `@op-engineering/op-sqlite` (JSI), achieving a buttery 60fps rendering pipeline synchronized with background events through an $O(1)$ In-Memory Set Gate.

**Explicitly banned:** React Native Headless JS, `react-native-background-actions`, `expo-task-manager` for background tracking, and all time-based background polling.

---

## 2. Core Library Stack

Do not deviate from these specific packages. They have been selected to bypass asynchronous bridge bottlenecks and guarantee native-level performance.

| Package Name | Version | Architectural Role |
| --- | --- | --- |
| `expo` | `^51.0.0+` | Core framework. Required for CNG plugin support and UI rendering. |
| `@maplibre/maplibre-react-native` | `^11.3.0+` | Definitive map engine. Supports JSI synchronous GeoJSON updates and 3D terrain. |
| `h3-js` | `^4.1.0` | **Foreground only.** Used for `gridDisk`, geometry unioning, and `cellsToMultiPolygon` operations in the JS thread. |
| `h3` (C library) | `v4.x` | **Background only.** Native C-library linked via Xcode bridging header. Used by Swift for `latLngToCell` at Resolution 11. |
| `@op-engineering/op-sqlite` | `^3.0.0` | JSI-powered SQLite engine. Foreground connection for microsecond synchronous reads. |
| `react-native-nitro-modules` | `latest` | JSI bridging framework. Generates statically typed C++ templates mapping JS types to Swift objects in shared memory. |
| `expo-location` | `^17.0.0+` | **Foreground only.** Handles permission requests and UI-level location display. |
| `zustand` | `^4.5.0+` | Lightweight, non-blocking UI state management. |
| `protobufjs` & `gtfs-realtime-bindings` | `latest` | On-the-fly decoding of binary GTFS-RT transit feeds. |

> **Removed from stack:** `expo-task-manager` — headless JS background tasks are architecturally banned under Sleepy Hermes.

---

## 3. Dual-Thread Data Flow

The application state flows through two completely independent execution threads that share a single SQLite database file.

### Background Thread (Swift — runs while Hermes sleeps)

```
CLLocationManager (hardware batch, distanceFilter: 10m)
  → Drift Gate (Implied Speed Filter: Δd/Δt ≤ 12 m/s)
  → H3 C-library: latLngToCell(lat, lng, resolution: 11)
  → Cast 64-bit integer → 15-character hex string
  → SQLite C-API: INSERT OR IGNORE via prepared statement
  → [If app is foregrounded]: Invoke Nitro callback with new H3 string
  → endBackgroundTask() — release iOS watchdog assertion
```

### Foreground Thread (JS/Hermes — runs when app is visible)

```
AppState "active" event OR Nitro real-time callback
  → @op-engineering/op-sqlite: SELECT delta of new H3 hexes (WAL read, non-blocking)
  → O(1) In-Memory Set Gate: Set.has(h3Index)
    → If true: DROP execution (user in explored territory, bridge stays silent)
    → If false: Add to Set, write to Zustand store
  → MapLibre DDS: Update ['match'] expression on fill-opacity
  → withSynchronousUpdate(true): Pass geometry via JSI shared memory
  → Render at 60fps
```

---

## 4. High-Performance Offline Persistence (Dual-Thread SQLite)

The foundational pillar of the Sleepy Hermes architecture is the **shared persistence layer**. Two separate, concurrent database connections target the **exact same physical `.db` file** on the iOS file system.

### 4.1 File Path Alignment

Both connections **must** resolve to the identical file path:

* **JS side:** `@op-engineering/op-sqlite` provisions its database in `Library/Application Support/`. This directory is hidden from the user, is not purged under memory pressure (unlike `.cachesDirectory`), and is included in iCloud backups.
* **Swift side:** The native service must independently construct this same path using `FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)`, dynamically creating intermediate directories if needed, and appending the target `.db` filename.

> ⚠️ **Failure to align paths** will silently instantiate a duplicate, orphaned database file, breaking the synchronization bridge.

### 4.2 Swift C-API Connection Initialization

The Swift background service interfaces with SQLite using the **raw C API** (`sqlite3_open_v2`), bypassing high-level ORM wrappers. The connection handle (`OpaquePointer`) must be opened with the following bitwise flag triad:

| Flag | Purpose |
| --- | --- |
| `SQLITE_OPEN_READWRITE` | Guarantees the connection can execute `INSERT` operations for newly discovered H3 hexes. |
| `SQLITE_OPEN_CREATE` | Guarantees the file is created if the background service initializes before the user has ever launched the foreground app. |
| `SQLITE_OPEN_FULLMUTEX` | **Critical.** Forces SQLite into serialized mode for this connection. iOS dispatches `CLLocationManager` delegate callbacks across arbitrary GCD threads; the internal mutexes prevent memory corruption from rapid, successive GPS batch updates. |

If `sqlite3_open_v2` fails to return `SQLITE_OK`, the implementation **must** immediately invoke `sqlite3_close` on the pointer via a `defer` block. The SQLite documentation mandates that connection resources are explicitly released regardless of initialization success to prevent memory leakage.

### 4.3 Write-Ahead Logging (WAL) and Lock Mitigation

Traditional SQLite rollback journals acquire an **exclusive, file-level lock** during writes. In a dual-connection architecture, this is fatal: if the user foregrounds the app while the Swift service holds a write lock, the JS thread blocks, causing a frozen UI or a `0xdead10cc` deadlock termination.

**WAL mode eliminates this race condition.** Both connections must execute:

```sql
PRAGMA journal_mode = WAL;
```

WAL mode permits simultaneous readers and writers by appending mutations to a separate `.wal` file. However, this introduces the risk of WAL bloat and checkpoint deadlocks ("Zombie Readers"). To mitigate this:
1. **Background Writes:** The Swift service must use `SQLITE_CHECKPOINT_PASSIVE` during active tracking to prevent thread blocking.
2. **AppState JSI Teardown:** The JS foreground must actively listen to `AppState` transitions to `"inactive"` or `"background"` and explicitly teardown/close the `@op-engineering/op-sqlite` connection to release its read lock.
3. **Defensive Checkpointing:** When the app transitions to the background, the Swift service must wrap a full `SQLITE_CHECKPOINT_RESTART` inside an `@available(iOS 17.0, *) CLBackgroundActivitySession` (with a legacy iOS 15/16 `beginBackgroundTask` fallback) to safely reset the WAL file to byte zero without triggering `0x8badf00d` watchdog terminations.

### 4.4 Configuration Reference Table

| Configuration Parameter | Rationale | Execution Layer |
| --- | --- | --- |
| `PRAGMA journal_mode = WAL;` | Enables concurrent background native writes and foreground JS reads without file locking or deadlock exceptions. | Swift & React Native |
| `PRAGMA synchronous = NORMAL;` | Optimizes disk flush frequency, drastically reducing baseband battery consumption during rapid background traversal. | Swift |
| `SQLITE_OPEN_FULLMUTEX` | Protects the Swift C-API connection pointer from race conditions triggered by unpredictable GCD thread pooling. | Swift |
| `WITHOUT ROWID` | Forces the SQLite B-Tree to cluster directly on the 15-character H3 string, ensuring microsecond read velocities. | Schema Definition |

### 4.5 Prepared Statements for Background Writes

To maximize throughput during the brief background wake window, the Swift service must exclusively use **prepared statements**:

1. **Compile once** at initialization: `sqlite3_prepare_v2` with `INSERT OR IGNORE INTO explored_hexes (h3_index, discovered_at) VALUES (?, ?)`
2. **Per coordinate:** `sqlite3_bind_text` (H3 string) → `sqlite3_step` → `sqlite3_reset`
3. This avoids the cost of re-parsing SQL on every location ping.

### 4.6 Schema

```sql
PRAGMA journal_mode = WAL;
PRAGMA synchronous = NORMAL;

CREATE TABLE explored_hexes (
    h3_index TEXT PRIMARY KEY,
    discovered_at INTEGER NOT NULL
) WITHOUT ROWID;

-- Used for the 3-Tier active visibility tracking (reference counting)
CREATE TABLE active_visibility (
    h3_index TEXT PRIMARY KEY,
    reference_count INTEGER NOT NULL
) WITHOUT ROWID;
```

*The `WITHOUT ROWID` declaration is mandatory. It forces SQLite to use the string `h3_index` directly as the clustered B-Tree index, reducing disk footprint by ~30% and maximizing lookup speeds.*

### 4.7 64-bit Precision Constraint

H3 indices are 64-bit integers. The ECMAScript standard used by Hermes represents all numbers as double-precision 64-bit floats, which can only safely represent exact integers up to $2^{53} - 1$. **All H3 indices must be stored and transmitted as 15-character hexadecimal strings** (e.g., `"8b2a100d213fff"`).

This conversion **must** happen in the Swift layer immediately after the H3 C-library `latLngToCell` call, **before** database insertion. If a raw 64-bit integer is inserted and later read by JS, catastrophic precision truncation will permanently corrupt the spatial grid.

---

## 5. Nitro Modules (JSI Bridging)

### 5.1 Why Nitro?

The legacy React Native bridge serializes all cross-boundary calls through asynchronous JSON. For real-time location callbacks, this serialization overhead is unacceptable. **Nitro Modules** leverage the JavaScript Interface (JSI) to generate statically typed C++ templates that map JavaScript types directly to native Swift objects in **shared memory** — zero serialization, zero bridge crossing.

### 5.2 The `*.nitro.ts` → Nitrogen → Swift Pipeline

1. **TypeScript Specification (`*.nitro.ts`):** Define the contractual interface between JS and Swift, extending the `HybridObject` interface with `{ ios: 'swift' }`. The spec exposes methods to initialize/terminate the background service and register event listener callbacks.
2. **Code Generation (`npx nitrogen`):** The Nitrogen CLI parses the spec and generates a `nitrogen/generated/` directory containing C++ JSI translation layers and Swift protocol definitions (e.g., `HybridTrackingSpec.swift`).
3. **Compile-Time Safety:** If the Swift implementation fails to satisfy the generated protocol signatures, the Xcode build immediately halts — eliminating runtime bridging failures.

### 5.3 The Local Expo Module Encapsulation Strategy

Because the project operates under a **Brownfield constraint** prohibiting programmatic modifications to `ios/*.pbxproj` via shell scripts or `sed`, and because we rely on `npx expo prebuild --clean` (which vaporizes manual Xcode GUI changes), **all custom native linkage must be encapsulated in a Local Expo Module**. 

Furthermore, utilizing an Objective-C bridging header for the pure C H3 library is an architectural anti-pattern in a modular `use_frameworks!` environment.

**The Encapsulation Protocol:**
1. **Module Scaffolding:** Create a localized Expo module (e.g., `modules/hybrid-tracker`) containing an `expo-module.config.json` and a `.podspec`.
2. **Clang Module Map:** The pure C H3 library must be wrapped in a strict Clang Module Map (`module.modulemap` containing `module H3 { header "h3api.h" export * }`).
3. **Nitrogen Generation Target:** Nitrogen JSI bridging files (`HybridTrackingSpec.hpp`, `HybridTrackingSpec.swift`) and the custom Swift implementations must be routed into this local module's directory structure.
4. **Autolinking:** Expo's native autolinker automatically handles target membership, `.pbxproj` injection, and build phase mapping during prebuild, completely abstracting the developer from manual Xcode GUI drag-and-drop.

---

## 6. Background Location & Baseband Economics

Continuous background tracking will drain the battery and trigger OS intervention if configured incorrectly. **Time-based polling is strictly prohibited.** The architecture relies on hardware-level distance filtering to allow the CPU to deep-sleep when the user is stationary.

### 6.1 CLLocationManager Configuration (Swift)

| Property | Value | Rationale |
| --- | --- | --- |
| `distanceFilter` | `10` meters | CPU stays in deep sleep until the low-power GPS coprocessor detects 10m of movement. |
| Deferred updates distance | `50` meters | Location points are stored in the GPS chip's silicon memory. The primary CPU wakes only once per 50m of accumulated travel. |
| `allowsBackgroundLocationUpdates` | `true` | Permits updates while backgrounded. |
| `pausesLocationUpdatesAutomatically` | `true` | iOS shuts down the radio when the accelerometer confirms the user is stationary. |

### 6.2 The Drift Gate (Implied Speed Filter)

Urban environments subject GPS to severe multipath interference — satellite signals bouncing off high-rise structures, erroneously plotting the user's location several blocks away while they are physically stationary. If this noise reaches the H3 engine, it will permanently unlock unearned hexes.

**All incoming coordinates must pass the Implied Speed Filter before processing:**

$$\frac{\Delta d}{\Delta t} \leq 12 \text{ m/s}$$

If the implied speed exceeds 12 m/s (roughly 27 mph — well above pedestrian/cycling speeds), the coordinate is classified as multipath noise and immediately discarded.

### 6.3 Native H3 Spatial Hashing

Coordinates that pass the drift gate are converted to H3 hexadecimal indices using the **C-based H3 library** (not `h3-js`):

1. Invoke `latLngToCell(lat, lng, resolution: 11)` via the Xcode bridging header.
2. **Resolution 11:** The hexagonal apothem (~24m) roughly matches civilian GPS accuracy tolerance, yielding granular tracking without overloading the renderer.
3. **Immediately** cast the 64-bit integer result to a 15-character hexadecimal string in Swift. This is non-negotiable (see §4.7).

### 6.4 Background Task Assertions

To guarantee iOS permits the synchronous database commit during the background wake window:

1. **Start:** Call `beginBackgroundTask(withName:expirationHandler:)` at the start of the location processing block.
2. **End:** Call `endBackgroundTask` with the saved identifier the moment the SQLite transaction concludes.

> ⚠️ **Failure to call `endBackgroundTask`** forces the system to hold the app alive until the background timer expires, at which point iOS issues a `0x8badf00d` watchdog termination.

---

## 7. UI Synchronization & Foreground Hydration

When the user foregrounds the app, Hermes has been sleeping — it is entirely unaware that the SQLite database has mutated. The MapLibre rendering engine must synchronize seamlessly.

### 7.1 Nitro Real-Time Callbacks

When the app is **actively visible** on screen:

1. The React Native layer passes a JS callback closure into the Nitro module's `addListener` method.
2. Nitro converts this into a statically typed Swift closure.
3. When the Swift `CLLocationManager` commits a new hex to SQLite, it checks whether the app is foregrounded.
4. If active, it **directly invokes** the stored closure, passing the new H3 string back into JS in real-time — zero JSON serialization.

### 7.2 AppState Lifecycle Hydration

If the app was suspended during exploration, the real-time callback cannot fire. Instead:

1. The React Native `AppState` API detects the transition from `"background"` → `"active"`.
2. A synchronous read via `@op-engineering/op-sqlite` (JSI) pulls the delta of newly discovered H3 hexes.
3. Because both connections use **WAL mode**, this read executes instantaneously, bypassing any write locks the Swift service might hold.
4. The JS layer updates the Zustand store, ensuring application memory mirrors the physical database.

### 7.3 The $O(1)$ In-Memory Set Gate

Synchronizing the UI requires extreme care to prevent React Native bridge starvation. Passing arrays of 10,000+ hex strings to MapLibre's DDS `['match']` expression on every GPS tick will cause severe micro-stutters and battery drain.

**The Set Gate eliminates this bottleneck:**

1. **On app boot:** The entire historical repository of unlocked H3 string IDs is queried synchronously from `@op-engineering/op-sqlite` and loaded into a standard JavaScript `Set`.
2. **On every Nitro callback or AppState hydration:** Each incoming H3 string is tested against the gate:
   * **`Set.has(h3Index) === true`:** The user is in explored territory. **Drop execution immediately.** No Zustand updates, no geometry unioning, zero bridge payloads to MapLibre.
   * **`Set.has(h3Index) === false`:** New territory discovered. Add to the `Set`, mutate the MapLibre DDS array, trigger geometry operations, and pass the updated data via `withSynchronousUpdate(true)` through JSI shared memory.

This ensures heavy bridge crossings and GPU tessellation operations fire **only** when new spatial territory is physically conquered.

---

## 8. The Fog Engine (MapLibre Rendering)

Rendering tens of thousands of individual hexagons will cause catastrophic frame drops. The app utilizes an **Inverted Polygon** approach with **Dynamic Regional Loading**.

* **Dynamic Regional Loading:** Never generate a worldwide fog polygon. On initialization, generate a 50km × 50km GeoJSON bounding box centered on the user's current GPS coordinate.
* **Temporal Interpolation:** Configure MapLibre `fill-opacity-transition: { duration: 300 }` on the fog mask layer for smooth, organic fog dissolve.
* **Layer Stacking (The 3-Tier Visibility Model):**
  * **Layer 1 (The Explored Base):** `RasterLayer` rendering satellite imagery permanently dimmed (`rasterSaturation: -1.0`, reduced brightness).
  * **Layer 2 (The Visible Base):** Full-color satellite `RasterLayer` masked by the user's active line-of-sight polygon.
  * **Layer 3 (The Sub-Context):** Faint vectors of major geographic arteries (coastlines, bridges) with zero text labels.
  * **Layer 4 (The Cloud Layer):** The base H3 grid loaded as a static geometry source, acting as the fog.
  * **Layer 5 (The DDS Filter):** Dynamically filter `fill-opacity` of Layer 4. Pass the array of unlocked H3 IDs into a MapLibre `['match']` expression, making unlocked hexes transparent.
  * **Layer 6 (The Vicinity Bubble):** Detailed geospatial data (street names, transit nodes, Ghost POIs) rendered within a dynamic 200m radius of the user's live location.

* **Algorithmic Simplification:** The legacy approach of `h3.cellsToMultiPolygon` for hole-punching is **deprecated**. We strictly use Data-Driven Styling (DDS) to avoid sending heavy JSON strings over the bridge.
* **Synchronous Updates:** Enable `withSynchronousUpdate(true)` on `ShapeSource` to bypass `JSON.stringify` serialization.

---

## 9. The Vicinity Bubble & Transit Pipeline

To support the "ambient explorer" progressive disclosure model, detailed mapping information is bound strictly to the user's physical presence.

* **Spatial Querying (200m Radius):** Detailed vector layers (street labels, transit nodes, Ghost POIs) are masked by a dynamic 200m radius around the live GPS coordinate. When the user pans away, these elements are suppressed.
* **Unified Transit Decoding (GTFS-RT Protobuf):** Transit nodes act as "Ghost POIs". Upon interaction, the app fetches data directly from the transit authority using binary Protocol Buffers (`protobufjs`), parsing GTFS-RT feeds uniformly. Service Alerts must correctly parse MTA's `informed_entity` structure (handling station-level nodes and specific `direction_id` flags).
* **Historical Sync (Multi-Region):** The app silently fetches a Zstandard-compressed SQLite database (e.g., `nyc_transit_delta.sqlite.zst`) from Cloudflare R2, generated nightly by a Go daemon (The Observer). This file is attached synchronously via `@op-engineering/op-sqlite`, enabling offline transit performance metrics in under 12ms.

---

## 10. Build System Patches & `use_frameworks!`

The integration of `react-native-nitro-modules` requires CocoaPods to use static frameworks via `use_frameworks! :linkage => :static`. This fundamentally changes how iOS headers are resolved, leading to a known impedance mismatch with React Native's C++ dependencies (specifically `RCT-Folly`).

* **Umbrella Header Cascades:** When `use_frameworks!` is active, CocoaPods generates an umbrella header for `RCT-Folly` that includes platform-incompatible headers (e.g., Linux-specific code, libstdc++ internals, and un-guarded inline headers). 
* **The Post-Install Contract:** The project relies on a Ruby `post_install` hook that explicitly acts as a **targeted deny-list** to strip these incompatible headers from the generated `RCT-Folly-umbrella.h` and inject necessary C++ standards.
* **The `prebuild --clean` Paradox (Config Plugin Mandate):** These Ruby hacks **must not** reside directly in `ios/Podfile`, as they will be permanently vaporized by Expo's Continuous Native Generation. Instead, they must be encapsulated within a Custom Expo Config Plugin (using `@expo/config-plugins` `withDangerousMod`) living in the project root. This ensures the `post_install` loop is re-injected automatically on every prebuild. See `AGENTS.md` for the exact protocol and patch definitions.