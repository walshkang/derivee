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

**Kick off Wave F: Map UI Overhaul & Ghost POI Lifecycle**

With the native foundation (Waves N.1–N.3) and Onboarding (Wave E) complete, the next objective is aligning the core map view with the `design.md` specifications.

Next steps for the agent:
1. Implement native SwiftUI Floating Action Buttons (FABs) over the map.
2. Build the 3-phase Ghost POI lifecycle natively using MapLibre data-driven styling.
3. Ensure ambient hex unlock animations trigger smoothly via GRDB observations.

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
