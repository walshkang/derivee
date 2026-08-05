# Agent Operational Rules (Pure Native iOS)

## 1. Core Architecture
- **Pure Native Swift:** The project has migrated away from React Native / Expo. The app is a pure native iOS application written in Swift (iOS 17.0+).
- **Project Generation:** The Xcode project is generated using `xcodegen`. Do NOT manually modify `.pbxproj` files or configure Xcode through the GUI. Instead, update `project.yml` and run `xcodegen`.
- **Dependencies:** All dependencies (like `H3` and `GRDB`) are managed exclusively via Swift Package Manager (SPM) defined in `project.yml`. Do NOT use CocoaPods or Carthage.
- **Data Layer:** Use `GRDB.swift` for SQLite interactions. Rely on `DatabasePool` with `WAL` mode and `WITHOUT ROWID` optimizations. Use `@Observable` classes with `ValueObservation` for reactive UI updates.
- **Background Tracking:** The background engine relies on `CLLocationUpdate.liveUpdates()` within a detached `Task` and `CLBackgroundActivitySession` to prevent suspension. Do not use legacy `CLLocationManagerDelegate` methods for live updates.

## 2. Visual & UI Guidelines
- **SwiftUI Exclusively:** All UI must be built with SwiftUI. No UIKit storyboards or `UIViewController` wrappers unless absolutely necessary for complex MapLibre integrations.
- **Map Focus:** The map is the UI. Avoid heavy persistent HUDs, tab bars, or manual "Start/Stop Tracking" buttons.
- **Aesthetics:** Follow the Day/Night cycle guidelines and use native materials (`.ultraThinMaterial`).

## 3. Testing Mandates
- **Staggered Rollout:** Adhere to the staggered testing rollout defined in `ROADMAP.MD` and `context.md`.
- **Unit Tests (Phase 1 & 2):** Isolate core logic (H3 math, database hydration, ambient tracking) from the UI.
- **Snapshot Testing (Phase 3):** Use `swift-snapshot-testing` for SwiftUI views (`StatsView`, `TransitRevealSheet`) to prevent visual regressions during rapid iteration.
- **CI/CD Enforcement (Phase 4):** All tests must run headlessly (`xcodebuild test`) in CI using **GitHub Actions**. Do NOT use Xcode Cloud due to its rigid `.xcodeproj` expectations which conflict with our dynamic `xcodegen` setup. Pull requests failing tests must be blocked.

## 4. Backend & Ecosystem Directives
- **Go Observer Daemon:** Do NOT containerize/Dockerize the Observer daemon. Deploy the raw compiled Go binary directly to the Oracle Cloud ARM instance via `systemd` to avoid virtualized filesystem overhead and maximize SQLite write speeds.
- **Web MVP Brand Sync:** The web app must mirror the iOS aesthetic exactly. Hardcode Day/Night hex colors (`#F9F9F6` / `#12121A`) in MapLibre, use Electric Amber (`#FFB300`) for sparklines, and pure black/white for text contrast.
