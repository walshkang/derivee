# Project Context

## Current Status: 🐛 Fog Reliability & On-Device Walk Testing (Wave I.10b Ready)

**The project is a 100% pure native iOS app written in Swift.** We have successfully completed the migration away from React Native / Expo. Waves E through H.1, W15 Dynamic Island support, and Waves I.1–I.10a are fully implemented and verified with 100% passing unit/snapshot tests (35 tests, 0 skips).

**Active focus:** Ready for Wave I.10b (untethered on-device field walk to capture 6-stage telemetry via `pipeline_debug.log`).

### What Changed

The original architecture relied on React Native, Expo, and later a hybrid JSI/Nitro approach. These were abandoned due to inherent framework limitations, background threading complexity, and poor UI performance. 

The app is now fully native:
* **Project Generation:** Exclusively managed via `xcodegen` (`project.yml`). The `.pbxproj` file is never manually edited.
* **UI Framework:** SwiftUI exclusively. No UIKit storyboards.
* **Data Layer:** `GRDB.swift` handles SQLite interactions with `ValueObservation` driving SwiftUI `@Observable` models.
* **Location Engine:** Ambient tracking uses modern `CLLocationUpdate.liveUpdates()` in a detached `Task` alongside `CLBackgroundActivitySession` to run reliably in the background without legacy delegate methods. A unified `LocationProvider` protocol supports both `LiveLocationProvider` and `GPXLocationProvider` for simulated playback and workout ingestion.
* **Telemetry & Field Diagnostics:** `PipelineLogger` streams real-time telemetry across stdout, `os.Logger`, and `Documents/pipeline_debug.log`, accessible via the iOS Files app.

### Key Files Updated

| File | Purpose |
| --- | --- |
| `docs/design.md` | Single source of truth for the native UI blueprint and interaction patterns |
| `docs/diagrams.md` | Single source of truth for UML class diagrams, reactive pipeline sequence, and architectural isomorphisms |
| `AGENTS.md` | AI guardrails: pure native Swift mandates, xcodegen requirements, and UI guidelines |
| `ROADMAP.MD` | Master status for current waves and shipped history |
| `archive/shipped-waves-archive.md` | Preserved history of the old Expo / React Native waves |

---

## Current Wave Status

| Wave | Task ID | Title | Status |
|:---:|:---:|:---|:---:|
| **N.1-3** | **WN-NATIVE** | **Pure Native Foundation (xcodegen, GRDB, Tracking)** | ✅ Done |
| **E** | **WE-ONBOARDING** | **Onboarding Gate & First-Launch Infrastructure** | ✅ Done |
| **F** | **WF-MAP-OVERHAUL** | **Map UI Overhaul & Ghost POI Lifecycle** | ✅ Done |
| **G** | **WG-TRANSIT-REVEAL** | **Transit Reveal Enhancements** | ✅ Done |
| **H** | **WH-SHIP** | **Polish, Stats and Profile Rewire & Ship Prep** | ✅ Done |
| **H.1** | **WH.1-PANNING** | **Stats UI: Neighborhood Map Panning** | ✅ Done |
| **15** | **W15-DYNAMIC-ISLAND** | **Dynamic Island & Live Activities** | ✅ Done |
| **I.1** | **WI1-FOG-GATE** | **Fog Startup Gate: Synchronize Shape Computation with Map Ready** | ✅ Done |
| **I.2** | **WI2-WINDING** | **Winding Order Audit & Interior Ring Hardening** | ✅ Done |
| **I.3** | **WI3-FOG-TESTS** | **Cold-Start Fog Regression Tests** | ✅ Done |
| **I.3a** | **WI3a-LIVE-FOG** | **Fix Live Fog Update Starvation (`.background` → `.userInitiated`)** | ✅ Done |
| **I.4** | **WI4-ASYNC-READS** | **Eliminate Main-Thread DB Reads & Configure GRDB QoS** | ✅ Done |
| **I.5** | **WI5-HANG-TESTS** | **Priority Inversion Regression Tests** | ✅ Done |
| **I.6** | **WI6-TRACK-STOP** | **Fix Ambient Tracking Stop Lifecycle (Live Activity + Persistence)** | ✅ Done |
| **I.7** | **WI7-LA-CLEANUP** | **Clean up Orphaned Live Activities on App Cold Start** | ✅ Done |
| **I.8** | **WI8-OBS-DIAG** | **GRDB ValueObservation Diagnostic Instrumentation** | ✅ Done |
| **I.9** | **WI9-OBS-FIX** | **GRDB ValueObservation Pipeline Hardening & Schema Fix** | ✅ Done |
| **I.10a** | **WI10a-PIPELINE-LOGS** | **6-Stage Diagnostic Pipeline Logging & Files App Export** | ✅ Done |
| **I.10b** | **WI10b-ONDEVICE-WALK** | **On-Device Untethered Walk (3+ Hexes)** | Planned (Ready) |
| **I.10c** | **WI10c-LOG-INTERPRET** | **Diagnostic Log Interpretation & Targeted Fix** | Blocked on I.10b |
| **J.1** | **WJ1-CAMERA-BOUNDS** | **Map Camera Bounds & Fog Viewport Clamping** | Planned |
| **J.2** | **WJ2-PERF-OPTIMIZATION** | **Map & Render Performance Optimization** | Planned |
| **J.3** | **WJ3-FOG-POI-MASKING** | **MapLibre Style POI & Label Masking Under Fog** | Planned |
| **J.4** | **WJ4-BASEMAP-SWITCHER** | **Map Base Layer Switcher (Dark / Transit / Standard)** | Planned |
| **J.5** | **WJ5-CUSTOMIZATION-SETTINGS** | **Visual Customization Settings (Opacity, Hex Size, Theme)** | Planned |
| **J.6** | **WJ6-TRANSIT-NODE-TRACKING** | **Dedicated Transit Node View & Live Tracking** | Planned |
| **J.7** | **WJ7-POI-GAMIFICATION** | **Enhanced Gamification & POI Discovery Milestones** | Planned |

---

## Testing Rollout

We have adopted a **Split-Target Architecture** testing strategy:
* **`DeriveeCoreTests` (No App Host):** ✅ Completed (Phase 1 & 2). Pure logic tests (GRDB concurrency, H3 math). Runs headlessly.
* **`DeriveeSnapshotTests` (Requires App Host):** ✅ Completed (Phase 3). Automated UI testing (`swift-snapshot-testing`) for SwiftUI views. Boots a simulator in the background.
* **Phase 4 (CI/CD Pipeline):** ✅ Completed. Automated builds run on GitHub Actions using `xcodegen`. We use a fast solo-dev "vibe coding" workflow: pushes are made directly to `main` without PRs, and CI acts as a post-push safety net.

---

## Previous Milestones (Archived)

All previous architectures (Expo Managed, Sleepy Hermes) and their corresponding milestones (Waves 1–14.10, A–D) are deprecated. The core ideas (3-Tier Fog, Ghost POIs, Ambient Tracking) remain, but their JavaScript implementations have been entirely replaced by native Swift equivalents. Detailed prompts and supersession notes for these old waves are archived in `archive/shipped-waves-archive.md`.
