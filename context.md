# Project Context

## Current Status: 🚧 Design Alignment & Ship (Waves F–H)

**The project is now a 100% pure native iOS app written in Swift.** We have successfully completed the migration away from React Native / Expo (including the abandoned "Sleepy Hermes" hybrid architecture). The focus is now on implementing the final UI/UX polish according to `docs/design.md` and preparing for App Store submission.

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
| `ROADMAP.MD` | Master status for current waves (F–H) and shipped history |
| `archive/shipped-waves-archive.md` | Preserved history of the old Expo / React Native waves |

---

## 🔨 Immediate Next Step

**Wave F Debugging: Systematic Map Restoration**

We are currently debugging why the native MapLibre map is not visible. To avoid haphazard changes, we are executing a systematic 3-phase debugging plan:

**Phase 1: Base Map & Network Isolation**
*   **Root Cause Identified:** `Secrets.swift` uses a placeholder `"YOUR_MAPTILER_KEY"`. MapLibre's style fetch fails with network errors (401/403), which prevents `mapView(_:didFinishLoading:)` from firing. Since our custom layers (fog, POIs) are injected *after* the style loads, a failed style fetch means absolutely nothing renders.
*   **Action:** Provide a valid MapTiler key (or swap to a public debug style temporarily) to confirm base satellite tiles load successfully.

**Phase 2: Fog Mask Validation**
*   **Root Cause Identified:** The fog mask covers the entire map with high opacity. If the geometry for the holes (explored hexes) is malformed or delayed, the mask will blanket the screen opaquely.
*   **Action:** Once the base map loads, temporarily lower fog opacity to 0.5. Verify `spatialStore.currentFogShape` successfully applies interior rings to cut holes in the fog layer. 

**Phase 3: POI Layer & Database Binding**
*   **Root Cause Identified:** POIs rely on precise coordinate math and layer ordering above the fog mask.
*   **Action:** Verify POIs are rendering and responding to distance changes (Lure, Active, Archive phases) as the simulated location updates.

---

## Current Wave Status

| Wave | Task ID | Title | Status |
|:---:|:---:|:---|:---:|
| **N.1-3** | **WN-NATIVE** | **Pure Native Foundation (xcodegen, GRDB, Tracking)** | ✅ Done |
| **E** | **WE-ONBOARDING** | **Onboarding Gate & First-Launch Infrastructure** | ✅ Done |
| **F** | **WF-MAP-OVERHAUL** | **Map UI Overhaul & Ghost POI Lifecycle** | Planned |
| **G** | **WG-TRANSIT-REVEAL** | **Transit Reveal Enhancements** | Planned |
| **H** | **WH-SHIP** | **Polish, Settings Rewire & Ship Prep** | Planned |

---

## Previous Milestones (Archived)

All previous architectures (Expo Managed, Sleepy Hermes) and their corresponding milestones (Waves 1–14.10, A–D) are deprecated. The core ideas (3-Tier Fog, Ghost POIs, Ambient Tracking) remain, but their JavaScript implementations have been entirely replaced by native Swift equivalents. Detailed prompts and supersession notes for these old waves are archived in `archive/shipped-waves-archive.md`.
