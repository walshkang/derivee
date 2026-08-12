# Project Context

## Current Status: 🐛 Fog Reliability & Startup Performance (Waves I.1–I.5 Planned)

**The project is a 100% pure native iOS app written in Swift.** We have successfully completed the migration away from React Native / Expo. Waves E through H.1 and W15 Dynamic Island support are fully implemented and verified with unit/snapshot tests.

**Active focus:** Fixing a cold-start fog rendering race condition and a priority inversion hang risk discovered in the `SpatialStore` → `MapView` pipeline and `SpatialDatabaseManager` synchronous reads.

### What Changed

The original architecture relied on React Native, Expo, and later a hybrid JSI/Nitro approach. These were abandoned due to inherent framework limitations, background threading complexity, and poor UI performance. 

The app is now fully native:
* **Project Generation:** Exclusively managed via `xcodegen` (`project.yml`). The `.pbxproj` file is never manually edited.
* **UI Framework:** SwiftUI exclusively. No UIKit storyboards.
* **Data Layer:** `GRDB.swift` handles SQLite interactions with `ValueObservation` driving SwiftUI `@Observable` models.
* **Location Engine:** Ambient tracking uses modern `CLLocationUpdate.liveUpdates()` in a detached `Task` alongside `CLBackgroundActivitySession` to run reliably in the background without legacy delegate methods.

### Key Files Updated

| File | Purpose |
| --- | --- |
| `docs/design.md` | Single source of truth for the native UI blueprint and interaction patterns |
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
| **I.1** | **WI1-FOG-GATE** | **Fog Startup Gate: Synchronize Shape Computation with Map Ready** | Planned |
| **I.2** | **WI2-WINDING** | **Winding Order Audit & Interior Ring Hardening** | Planned |
| **I.3** | **WI3-FOG-TESTS** | **Cold-Start Fog Regression Tests** | ✅ Done (Sandbox Quirks Benched) |
| **I.4** | **WI4-ASYNC-READS** | **Eliminate Main-Thread DB Reads & Configure GRDB QoS** | Planned |
| **I.5** | **WI5-HANG-TESTS** | **Priority Inversion Regression Tests** | Planned |

---

## Testing Rollout

We have adopted a **Split-Target Architecture** testing strategy:
* **`DeriveeCoreTests` (No App Host):** ✅ Completed (Phase 1 & 2). Pure logic tests (GRDB concurrency, H3 math). Runs headlessly.
* **`DeriveeSnapshotTests` (Requires App Host):** ✅ Completed (Phase 3). Automated UI testing (`swift-snapshot-testing`) for SwiftUI views. Boots a simulator in the background.
* **Phase 4 (CI/CD Pipeline):** ✅ Completed. Automated builds run on GitHub Actions using `xcodegen`. We use a fast solo-dev "vibe coding" workflow: pushes are made directly to `main` without PRs, and CI acts as a post-push safety net.

---

## Previous Milestones (Archived)

All previous architectures (Expo Managed, Sleepy Hermes) and their corresponding milestones (Waves 1–14.10, A–D) are deprecated. The core ideas (3-Tier Fog, Ghost POIs, Ambient Tracking) remain, but their JavaScript implementations have been entirely replaced by native Swift equivalents. Detailed prompts and supersession notes for these old waves are archived in `archive/shipped-waves-archive.md`.
