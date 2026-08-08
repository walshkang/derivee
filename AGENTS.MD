# Agent Operational Rules (Pure Native iOS)

## 1. Core Architecture
- **Pure Native Swift:** The project has migrated away from React Native / Expo. The app is a pure native iOS application written in Swift (iOS 17.0+).
- **Project Generation:** The Xcode project is generated using `xcodegen`. Do NOT manually modify `.pbxproj` files or configure Xcode through the GUI. Instead, update `project.yml` and run `xcodegen`.
- **Dependencies:** All dependencies (like `H3` and `GRDB`) are managed exclusively via Swift Package Manager (SPM) defined in `project.yml`. Do NOT use CocoaPods or Carthage.
- **Data Layer:** Use `GRDB.swift` for SQLite interactions. Rely on `DatabasePool` with `WAL` mode and `WITHOUT ROWID` optimizations. Use `@Observable` classes with `ValueObservation` for reactive UI updates.
- **Async DB Reads (No Main-Thread Blocking):** All `SpatialDatabaseManager` read methods (`fetchStopDetails`, `fetchHeadwayData`, `isHydrationComplete`, `fetchNeighborhoodName`) **must** use `async`/`await` (`try await dbWriter.read`). **Never** perform synchronous `dbWriter.read { }` on the main thread — this causes priority inversion hangs when the background tracking engine holds a pool connection. The GRDB `Configuration.qos` must be set to `.userInitiated`.
- **Fog Startup Synchronization:** The `SpatialStore` fog polygon computation (`recomputeFogShape`) and MapLibre's `didFinishLoading` callback race on cold start. The initial fog computation must run at `.userInitiated` priority (not `.background`) to beat the style load. A "map ready" handshake flag in the `MapView.Coordinator` must ensure the fog shape is applied as soon as both the style and the shape are ready.
- **Background Tracking:** The background engine relies on `CLLocationUpdate.liveUpdates()` within a detached `Task` and `CLBackgroundActivitySession` to prevent suspension. Do not use legacy `CLLocationManagerDelegate` methods for live updates.

## 2. Visual & UI Guidelines
- **SwiftUI Exclusively:** All UI must be built with SwiftUI. No UIKit storyboards or `UIViewController` wrappers unless absolutely necessary for complex MapLibre integrations.
- **Map Focus:** The map is the UI. Avoid heavy persistent HUDs, tab bars, or manual "Start/Stop Tracking" buttons.
- **Aesthetics:** Follow the Day/Night cycle guidelines and use native materials (`.ultraThinMaterial`).

## 3. Testing Mandates
- **Split-Target Architecture:**
  - **`DeriveeCoreTests` (No App Host):** Tests core logic (GRDB SQLite transactions, Uber H3 spatial math, multipath GPS noise rejection, multi-threading deadlocks). Runs in milliseconds, completely headlessly without a simulator. Cooperative Task yield testing should be restricted purely to these core database logic tests.
  - **`DeriveeSnapshotTests` (Requires App Host):** Tests SwiftUI layouts (`StatsView`, `TransitRevealSheet`, Day/Night color accuracy) using `swift-snapshot-testing`. Boots an iPhone simulator in the background on GitHub Actions to prevent visual UI regressions from agent vibe-coding.
- **Data vs Snapshot Assertions:** Use `swift-snapshot-testing` exclusively for SwiftUI visual layers. Keep pure native data assertions (e.g. `interiorPolygons?.count`) for the MapLibre Fog Polygon Math—do not use snapshot/dump diffing for MapLibre structural objects or OpenGL renders.
- **CI/CD Enforcement (Phase 4):** Both test targets must run in CI using **GitHub Actions**. Do NOT use Xcode Cloud due to its rigid `.xcodeproj` expectations which conflict with our dynamic `xcodegen` setup. Pull requests failing tests must be blocked.

## 4. Backend & Ecosystem Directives
- **Go Observer Daemon:** Do NOT containerize/Dockerize the Observer daemon. Deploy the raw compiled Go binary directly to the Oracle Cloud ARM instance via `systemd` to avoid virtualized filesystem overhead and maximize SQLite write speeds.
- **Web MVP Brand Sync:** The web app must mirror the iOS aesthetic exactly. Hardcode Day/Night hex colors (`#F9F9F6` / `#12121A`) in MapLibre, use Electric Amber (`#FFB300`) for sparklines, and pure black/white for text contrast.
