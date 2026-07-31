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

## 🔨 Immediate Next Step

**Kick off Wave C.1: Folly Config Plugin**

The previous requirement for "Manual Xcode GUI Linkage" has been **strictly banned** because it violates the `prebuild --clean` lifecycle. All native iOS changes must now be encapsulated inside an Expo Config Plugin (Wave C.1) and a Local Expo Module (Wave C.2) using Clang Module Maps instead of Objective-C bridging headers.

Next steps for the agent:
1. Extract the Folly Ruby regex hacks from `ios/Podfile` into a `withFollyPodfile.js` Config Plugin.
2. Ensure the patches survive `npx expo prebuild --clean`.

---

## Migration Wave Status

| Wave | Task ID | Title | Status |
|:---:|:---:|:---|:---:|
| **A** | WA-DB-CONCURRENCY | Database Config & Dual-Thread Concurrency | ✅ Done |
| **B** | WB-NITRO-SCAFFOLD | Nitro Module Scaffolding & Code Generation | 🔄 Superseded → Wave C.2 |
| **C.1** | WC1-CONFIG-PLUGIN | Folly Config Plugin (Podfile Survival) | Planned |
| **C.2** | WC2-LOCAL-MODULE | Local Expo Module & H3 Module Map | Planned |
| **C.3** | WC3-SWIFT-SERVICE | Swift Background Service & SQLite Concurrency | Planned |
| **D.1** | WD1-UI-HYDRATION | UI Synchronization, AppState Teardown & Legacy Cleanup | Planned |

---

## Previous Milestones (Pre-Sleepy Hermes)

All waves 1–14.10 were completed under the original Expo Managed architecture. Key accomplishments preserved:

* MapLibre fog rendering engine with DDS (Data-Driven Styling)
* Neighborhood progression tracking and statistics UI
* GTFS-RT transit pipeline with Go Observer backend
* GPX/HealthKit import with macro-reveal animation
* Multi-city transit data architecture (NYC + Boston scaffolding)

Detailed prompts and supersession notes are in `archive/shipped-waves-archive.md`.
