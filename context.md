# Project Context

## Current Status: 🚧 Architectural Migration — Sleepy Hermes Transition (Wave A–D)

**Feature development is frozen.** The project is executing a critical architectural migration from a pure **Expo Managed / JS-background** architecture to a hybrid **"Brownfield" Sleepy Hermes** paradigm.

### What Changed

The original architecture relied on `expo-task-manager` and `expo-location` to execute JavaScript in the background for ambient location tracking. This caused:

* **iOS watchdog terminations** (`0x8badf00d`, `0xdead10cc`) — the OS kills apps that run JS (with Hermes GC sweeps, bridge serialization, and React state reconciliations) while backgrounded.
* **Catastrophic battery drain** — background JS execution keeps the CPU awake far beyond what hardware-level GPS batching requires.
* **Bridge congestion** — rapid background-to-foreground bridge crossings caused micro-stutters below 60fps.

### The Sleepy Hermes Paradigm

All background location processing now runs in a **pure native Swift layer**:

* **Background:** Swift `CLLocationManager` → Drift Gate → H3 C-library → SQLite C-API (WAL mode). Hermes sleeps.
* **Foreground:** `AppState` resume → `@op-engineering/op-sqlite` delta hydration → $O(1)$ In-Memory Set Gate → Zustand → MapLibre DDS. Hermes wakes.
* **Bridge:** `react-native-nitro-modules` (JSI) — zero-serialization callbacks between Swift and JS.

### Key Files Updated

| File | Purpose |
| --- | --- |
| `docs/architecture.md` | Full Sleepy Hermes architecture specification |
| `AGENTS.md` | AI guardrails: forbidden patterns, Xcode protocol, H3 string mandate |
| `ROADMAP.MD` | Fresh roadmap with Wave A–D, old waves archived |
| `archive/shipped-waves-archive.md` | Superseded waves preserved with rationale |

---

## 🔨 Immediate Next Step (Human Developer)

**Prepare the Xcode workspace for manual GUI linkage.**

The native iOS workspace has been materialized via `npx expo prebuild --clean` and committed on branch `feature/brownfield-sleepy-hermes`. The next physical step (before any code waves can execute) is:

1. Open `ios/Derivee.xcworkspace` in Xcode.
2. Verify the project builds cleanly with the CNG-generated native code.
3. Once Wave B (Nitro Scaffolding) generates the `nitrogen/generated/ios/` directory, import it via the Xcode GUI (drag into Project Navigator → "Create groups" → check target membership).
4. Create `HybridTracker.swift` via Xcode New File → Swift File.
5. Accept the bridging header prompt → add `#import "h3api.h"` and `#import <sqlite3.h>`.
6. Integrate the H3 C-library headers into the project search paths.

> These steps **cannot** be automated by the AI agent — they require the Xcode GUI.

---

## Migration Wave Status

| Wave | Task ID | Title | Status |
|:---:|:---:|:---|:---:|
| **A** | WA-DB-CONCURRENCY | Database Config & Dual-Thread Concurrency | ✅ Done |
| **B** | WB-NITRO-SCAFFOLD | Nitro Module Scaffolding & Code Generation | 🔧 In Progress (Human: Xcode Linkage) |
| **C** | WC-SWIFT-SERVICE | Swift Background Service & Baseband Economics | Blocked (needs Xcode GUI linkage from Wave B) |
| **D** | WD-UI-HYDRATION | UI Synchronization & Foreground Hydration | Blocked (needs Wave C) |

---

## Previous Milestones (Pre-Sleepy Hermes)

All waves 1–14.10 were completed under the original Expo Managed architecture. Key accomplishments preserved:

* MapLibre fog rendering engine with DDS (Data-Driven Styling)
* Neighborhood progression tracking and statistics UI
* GTFS-RT transit pipeline with Go Observer backend
* GPX/HealthKit import with macro-reveal animation
* Multi-city transit data architecture (NYC + Boston scaffolding)

Detailed prompts and supersession notes are in `archive/shipped-waves-archive.md`.
