# Dérivée — Architecture Specification

This document details the architectural decisions and internal machinery for the pure native iOS version of Dérivée.

## 1. Core Paradigm: Pure Native Swift

Dérivée is built as a pure native iOS application using **Swift** and **SwiftUI**. We have explicitly moved away from hybrid frameworks (React Native, Expo) and C++ JSI bridging (Nitro Modules) to maximize performance, battery life, and background execution reliability.

### 1.1 Project Generation (XcodeGen)
To prevent `.pbxproj` merge conflicts and maintain a deterministic build environment, the Xcode project is generated using `xcodegen`. 
- **Configuration:** Defined entirely in `project.yml`.
- **Dependencies:** Managed via Swift Package Manager (SPM).
- **No CocoaPods:** The project is entirely free of Ruby-based dependency managers.

---

## 2. The Data Layer: GRDB & SQLite

All geospatial data, exploration history, and transit schedules are stored locally in a SQLite database.

### 2.1 Concurrency & WAL Mode
We use `GRDB.swift` to manage the database connection.
- **DatabasePool:** Enables concurrent reads and writes, crucial for rendering the map on the main thread while the background tracking engine writes new locations.
- **WAL (Write-Ahead Logging):** Configured via `PRAGMA journal_mode = WAL;`.
- **Busy Timeout:** Configured via `PRAGMA busy_timeout = 5000;` to gracefully handle concurrent access without `SQLITE_BUSY` exceptions.

### 2.2 Schema Optimization (`WITHOUT ROWID`)
The `explored_hexes` table tracks all discovered H3 indices.
```sql
CREATE TABLE explored_hexes (
    h3_index TEXT PRIMARY KEY
) WITHOUT ROWID;
```
Because the `h3_index` is the only column and acts as a primary key, `WITHOUT ROWID` clusters the index strings together in the B-Tree, significantly reducing storage size and improving sequential read performance during map hydration.

### 2.3 Reactive Observation
The `SpatialStore` (`@Observable`) acts as the bridge between GRDB and SwiftUI. It uses GRDB's `ValueObservation` to track changes in the `explored_hexes` table and automatically triggers a SwiftUI re-render when new hexes are discovered in the background.

---

## 3. The Ambient Tracking Engine

Background location tracking is handled by the `AmbientTrackingEngine`, designed to be infinitely persistent while minimizing battery drain.

### 3.1 Modern iOS 17 Concurrency
We abandoned legacy `CLLocationManagerDelegate` callbacks in favor of the modern `CLLocationUpdate.liveUpdates()` asynchronous stream.
- The stream runs in a detached `Task` off the main thread.
- Updates are processed serially via `for await update in updates`.

### 3.2 The Watchdog Shield
To prevent iOS from terminating the app when running in the background for extended periods, we instantiate a `CLBackgroundActivitySession`. This tells the OS that the location session is critical and must be preserved.

### 3.3 The Drift Gate (Speed Filter)
To prevent "GPS drift" or multipath errors in urban canyons from unlocking false hexes, an implied speed filter is enforced:
- Speed is calculated as $\Delta d / \Delta t$ using `update.location`.
- If speed exceeds **12 m/s** (approx. 27 mph), the point is discarded.
- This ensures hexes are only unlocked at walking/biking speeds.

---

## 4. Geospatial Hashing (H3)

Dérivée uses Uber's H3 Hexagonal Hierarchical Spatial Index to discretize the world.

### 4.1 Swift-H3 Wrapper
Instead of compiling the raw C library inside the Xcode project using CMake, we use the `swift-h3` SPM community wrapper. This provides a clean, type-safe Swift API for spatial functions.

### 4.2 Resolution Constraints
All hexes are calculated at **Resolution 11**.
- Coordinates are passed to `H3.latLngToCell(latitude:longitude:resolution:)`.
- The resulting 64-bit integer is converted to a 15-character hex string for SQLite insertion.

---

## 5. Map Rendering

### 5.1 MapLibre Native
The visual map is rendered using MapLibre Native.
- Custom vector styles are injected using Data-Driven Styling (DDS).
- The volumetric fog is rendered as a dark overlay, and unlocked hexes are applied via a `fill-opacity` match expression against the `explored_hexes` dataset.
- Because GRDB feeds the UI reactively via `SpatialStore`, MapLibre re-renders the fog layer immediately upon a new background hex discovery without requiring an app restart or manual refresh.

---

## 6. Testing Architecture

Testing in Dérivée follows a staggered, specialized approach to ensure stability across both background execution and UI rendering.

### 6.1 Unit Testing (Phases 1 & 2)
The core engine and raw data components must be tested independently from the UI and background lifecycle.
- **XCTest** is utilized to test the `AmbientTrackingEngine`, `SpatialDatabaseManager`, and background logic.
- **H3 Math & Transit Data:** Dedicated tests isolate spatial hashing math (`swift-h3`) and `transit_delta.sqlite` hydration to ensure data integrity.

### 6.2 Snapshot Testing (Phase 3)
Because Dérivée relies heavily on rich, custom SwiftUI visual elements (like the MapLibre overlays, `ultraThinMaterial` backgrounds, and the Transit Reveal bottom sheet):
- **swift-snapshot-testing** (Point-Free) is used to capture pixel-perfect snapshots of SwiftUI views loaded with mocked `@Observable` data.
- This prevents visual regressions from going unnoticed during rapid AI/agent-driven iterations.

### 6.3 CI/CD Enforcement (Phase 4)
Because the native Xcode project is generated immutably via `xcodegen`:
- **Headless Testing:** All unit and snapshot tests run via `xcodebuild test` exclusively on **GitHub Actions**. We explicitly avoid Xcode Cloud due to its rigid `.xcodeproj` requirements that conflict with our `xcodegen` setup.
- **Fast Deployment:** PRs must pass all tests to merge, enabling a safe and automated pipeline straight to TestFlight.

---

## 7. Ecosystem & Backend Architecture

While the primary mobile client is pure native iOS, the surrounding ecosystem supports offline-first data generation and web accessibility.

### 7.1 Observer Daemon (Go)
To provide users with offline-first historical transit reliability data, a standalone daemon aggregates live GTFS-RT feeds.
- **Deployment:** The Go Observer is compiled as a single, statically linked binary and deployed directly to an Oracle Cloud ARM instance.
- **No Docker:** Containerization is explicitly avoided. Running the raw binary via `systemd` eliminates virtualized filesystem overhead and maximizes SQLite write performance.
- **Output:** A Zstandard-compressed SQLite database (`transit_delta.sqlite.zst`) containing 7-day headways, uploaded nightly to Cloudflare R2 for the mobile client to download.

### 7.2 Web MVP
A standalone web version of the transit map provides a lightweight alternative.
- **Brand Synchronization:** The MapLibre configuration in the web app hardcodes the exact Day/Night iOS hex colors (`#F9F9F6` / `#12121A`) to ensure absolute visual consistency across platforms.
