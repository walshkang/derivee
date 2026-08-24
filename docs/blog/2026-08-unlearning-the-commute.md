# Unlearning the Commute: Building a 120Hz Native Fog of War for NYC

Every transit app wants to hurry you along. They flash red countdown timers, optimize routes for speed, and treat the city as dead space between subway stops. Fitness trackers do the opposite: they guilt-trip you with calorie rings, popup trophies, and noisy badges.

I wanted something different: an ambient, offline-first companion that treats exploration as an ongoing drift. The premise of Dérivée is simple: the entire city starts shrouded in a dense Fog of War. As you walk, cycle, or take the train, you uncover H3 hexagonal cells across the map. There are no "Start Tracking" buttons, no persistent dashboard widgets, and no social feeds. The map is the entire interface.

Moving from that concept to a 120fps native iOS app revealed three distinct engineering challenges:
1. Keeping background location tracking alive without draining the battery.
2. Rendering continuous multi-polygon fog cutouts on the GPU without frame drops.
3. Aligning with autonomous AI coding agents by treating decision requests as cheap.

---

## 1. Phone Resources & Background Survival

### Taming the GPS Pipeline
Background location on modern iOS is a minefield. Legacy delegate methods (`CLLocationManagerDelegate`) often suffer from lifecycle drops or excessive wakeups. In Dérivée, tracking runs on iOS 17's asynchronous `CLLocationUpdate.liveUpdates()` stream inside a detached task, guarded by a `CLBackgroundActivitySession`:

```swift
final class AmbientTrackingEngine: @unchecked Sendable {
    private var backgroundSession: CLBackgroundActivitySession?

    func startTracking() {
        backgroundSession = CLBackgroundActivitySession()
        Task.detached(priority: .userInitiated) { [weak self] in
            for await update in CLLocationUpdate.liveUpdates() {
                guard let location = update.location else { continue }
                await self?.processLocation(location)
            }
        }
    }
}
```

### The Cold-Start & Rayleigh Noise Gate
Raw GPS fixes in dense urban canyons (like Midtown Manhattan) can bounce 80 meters horizontally in seconds. If fed directly into spatial hashing, you unlock street blocks you never visited.

Rather than relying on naive speed thresholds, Dérivée routes fixes through `ColdStartLocationFilter`:
* **Staleness check:** Fixes older than 5.0 seconds are dropped immediately.
* **Rayleigh uncertainty bound:** Rejects any fix where `horizontalAccuracy` exceeds 25.0 meters (the radius of an Uber H3 Resolution 11 hexagon is ~28m).
* **Instant high-accuracy unlock:** Fixes with $\le 12.0\text{m}$ accuracy unlock the initial hex immediately at $t=0$.
* **Stationary dwell fallback:** Intermediate fixes ($12.0\text{m} < \text{hAcc} \le 25.0\text{m}$) unlock automatically after 3.0 seconds if the device remains stationary, or resolve immediately upon continuous walking.
* **Subway emergence classifier:** When emerging from underground transit, coordinates jump drastically. If the temporal gap $\Delta t \ge 15.0\text{s}$, the filter classifies the jump as a legitimate transit emergence, resetting the velocity baseline without discarding the fix.

### SQLite Concurrency Without Priority Inversion
Exploration state is stored locally using `GRDB.swift` in Write-Ahead Logging (`WAL`) mode. Background GPS writes occur continuously while the main thread reads map state at 120Hz.

A common failure mode in mobile SQLite setups is priority inversion: if a background task writes with low Quality-of-Service (`.background`), GRDB wait queues can block a high-priority main-thread read. We resolved this by explicitly configuring GRDB's dispatch queue QoS to `.userInitiated` and mandating asynchronous database reads (`try await dbWriter.read`) across all data-layer interfaces:

```swift
var config = Configuration()
config.qos = .userInitiated
config.busyMode = .timeout(5.0)
let dbPool = try DatabasePool(path: dbPath, configuration: config)
```

---

## 2. 120Hz Fog Cartography: Spatial Unioning and Closed-Loop Islands

### The Triangulation Bottleneck ($O(N^2)$ to $O(N \log N)$)
Dérivée renders fog as an inverted bounding polygon overlaying MapLibre Native. The explored areas are holes punched through this bounding box.

Early prototypes passed individual H3 hexagons as distinct interior polygon rings. As the player explored hundreds of cells, MapLibre's underlying `earcut.hpp` triangulation engine degraded exponentially. Triangulating thousands of disconnected micro-holes on every tracking update stalled the main thread, causing frame drops and battery drain.

The fix was moving polygon dissolution off the UI thread into C/Swift H3 (`cellsToLinkedMultiPolygon`). By dissolving contiguous hex clusters into single macro-polygons before passing them to MapLibre, vertex counts dropped by over 85%:

```
[Raw Disconnected H3 Hexagons] 
            │
            ▼  (cellsToLinkedMultiPolygon in Task.detached)
[Dissolved Macro-Cluster Outer Loops] 
            │
            ▼  (Reversed Winding Order -> CCW Holes)
[Master Bounding Box MLNPolygon] -> MapLibre GPU Pipeline (<1.5ms MainActor commit)
```

### Closed-Loop Fog Islands
When a user walks in a complete circle around a city block or Central Park, the outer boundary forms a hole in the fog, but the unexplored center remains hidden.

`FogPolygonMath.cellsToFogGeometry` parses H3's `LinkedGeoPolygon` cluster hierarchy. The primary loop (`loop.pointee.first`) forms the outer cutout, while interior child loops (`loop.pointee.next`) are reversed to clockwise winding to produce disjoint interior fog islands. The resulting `MLNShapeCollection` correctly keeps unvisited courtyards and block interiors shrouded.

```
┌──────────────────────────────────────────────────────────┐
│ Outer Bounding Box (Clockwise - Solid Fog)               │
│    ┌────────────────────────────────────────────────┐    │
│    │ Dissolved Outer Walk Loop (CCW - Cleared Hole) │    │
│    │    ┌──────────────────────────────────────┐    │    │
│    │    │ Interior Block (Clockwise - Island)  │    │    │
│    │    └──────────────────────────────────────┘    │    │
│    └────────────────────────────────────────────────┘    │
└──────────────────────────────────────────────────────────┘
```

### Ambient Transit Context
Traditional maps bury transit networks under commercial POI pins. Dérivée flips this hierarchy:
* **The 200m Active Bubble:** Commercial labels and street names only fade in within 200m of the user's physical position.
* **Subway Thoroughfares Under Fog:** Complete MTA track geometries render beneath the fog layer. Unexplored sections provide orienting sub-context, while explored sections glow vibrantly in official MTA line colors (e.g. `#EE352E` for 1/2/3, `#00933C` for 4/5/6, `#FF6319` for B/D/F/M).
* **Nearby Buses Lens:** A floating frosted-glass capsule executes spatial SQLite queries within 400m and parses GTFS-RT Protobuf streams directly, giving live arrival countdowns without battery-draining continuous background network polling.

---

## 3. Engineering with Autonomous Agents: The 3-Pillar Assurance Harness

Building a high-performance spatial iOS app as a solo engineer was accelerated by treating AI coding agents not as passive code autocomplete, but as an autonomous engineering partner bound by a rigorous assurance harness.

Moving from "vibe coding" to high-assurance software engineering requires a deliberate workflow. Drawing inspiration from pioneers in the agent-first engineering community—such as **Matt Pocock's** concept of "grilling" (inverting the agent-human dynamic to resolve architectural branches before writing code)—we structured our human-agent collaboration around three core pillars:

```
┌────────────────────────────────────────────────────────────────────────┐
│                   3-PILLAR AGENT ASSURANCE HARNESS                     │
├─────────────────────────┬──────────────────────────┬───────────────────┤
│  1. Machine-Executable  │   2. Active Decision     │    3. Tiered      │
│      Specifications     │      Interrogation       │   Deterministic   │
│  (Living Contracts)     │   ("Grill the Human")    │   Verification    │
├─────────────────────────┼──────────────────────────┼───────────────────┤
│ • AGENTS.md constraints │ • Low-cost question gates│ • Headless Core   │
│ • diagrams.md topology  │ • Edge-case stress tests │ • Snapshot UI     │
│ • architecture.md data  │ • No unstated assumptions│ • Post-Push CI    │
└─────────────────────────┴──────────────────────────┴───────────────────┘
```

### Pillar 1: Executable Specifications as Living Contracts
When autonomous agents fail, the root cause is rarely syntax—it is architectural drift. Agents default to isolated local optimizations, inventing ad-hoc state managers or conflicting data models if unconstrained.

To prevent drift, we established strict living specifications as single sources of truth:
* **`AGENTS.md`:** Codified non-negotiable operational rules (e.g., mandatory `.userInitiated` QoS for GRDB reads, `CLLocationUpdate.liveUpdates()` over legacy delegates, immutable `xcodegen` project files).
* **`diagrams.md` & `architecture.md`:** Documented class ownership, thread boundaries, and database topologies in explicit ASCII and Markdown schemas.

By pointing agents to these machine-readable boundaries before every task, we eliminated hallucinations around dependencies, concurrency models, and project structure.

### Pillar 2: Active Decision Interrogation ("Grill the Human")
In typical AI workflows, when an agent encounters ambiguity, it makes an unstated assumption. In a systems-heavy codebase (such as coordinate winding conventions in MapLibre or thread priority in SQLite locks), a wrong assumption can cost hours of release-mode debugging.

We inverted this dynamic using the **"Grill the Human"** pattern:
1. **Decision requests are cheap:** Pausing to ask the human a structured, multiple-choice architectural question costs 15 seconds. Debugging an inverted coordinate polygon bug in production costs days.
2. **Stress-testing the edge cases:** Before synthesizing code, the agent is instructed to interrogate boundary conditions (e.g., *"If a user enters the subway at 8th Ave and exits at 1st Ave, should the location filter drop that 2km jump or classify it as a transit emergence?"*).
3. **Aligning before writing:** Code is only generated once human and agent reach explicit consensus on the decision branch.

### Pillar 3: Tiered Deterministic Verification
To enable rapid direct-to-main iteration without breaking production builds, we decoupled verification into strict tiers:
* **`DeriveeCoreTests` (Headless & Fast):** Tests SQLite transactions, H3 spatial math, and GPS noise rejection without booting an iOS simulator. Runs in milliseconds, providing an immediate sub-second feedback loop for agent iterations.
* **`DeriveeSnapshotTests` (Visual UI Harness):** Uses `swift-snapshot-testing` hosted on a simulator to assert pixel-perfect SwiftUI layouts across Day and Night modes, preventing visual regressions.
* **Continuous Integration Safety Net:** Automated GitHub Actions workflows run the test matrix post-push, creating an unyielding safety net for rapid commits.

---

## Reflections & The Learning Curve

As an engineer preparing to advise enterprises on AI adoption and systems architecture, building Dérivée reinforced both the immense power and current boundaries of agentic software development:

### What Worked Exceptionally Well
* **Systems Translation:** Translating complex mathematical concepts (like H3 multi-polygon hierarchies and Rayleigh noise distribution) into optimized Swift/C code was drastically accelerated by pairing with agents under strict algorithmic constraints.
* **Zero Architectural Drift:** Maintaining living specification files kept multi-agent sessions strictly aligned across weeks of development.

### Where Challenges Remain (What We're Still Learning)
* **Imperative GPU/UI Bridges:** Bridging declarative SwiftUI state with imperative MapLibre OpenGL render lifecycles still requires deep human architectural intervention; agents naturally struggle with low-level graphic render loop synchronization without explicit guidance.
* **Algorithmic Default Traps:** Without explicit performance constraints, agents frequently propose naive $O(N^2)$ solutions (like raw un-dissolved polygon arrays). Human domain expertise remains essential to steer agents toward scalable data structures.

> [!TIP]
> **Enterprise Takeaway:** For enterprise engineering organizations, the bottleneck in AI adoption is not the LLM's raw coding capability—it is the **harness**. Investing in living architecture contracts, automated test tiers, and structured interrogation protocols transforms AI from a risky gimmick into a reliable, enterprise-grade engineering multiplier.

---

## What's Next & Join the Conversation

Dérivée is currently running in closed field testing across New York City. The transition from hybrid prototypes to pure native Swift unlocked 120fps ProMotion fluidity, sub-millisecond database queries, and all-day ambient background tracking.

The project source, architectural specifications, and test harnesses are open for exploration on GitHub:
👉 **[github.com/walshkang/derivee](https://github.com/walshkang/derivee)**

*I'm continuously learning and refining these agentic engineering patterns. How is your team structuring verification harnesses and specifications for autonomous coding agents? I'd love to connect, trade notes, and learn from your experiences.*
