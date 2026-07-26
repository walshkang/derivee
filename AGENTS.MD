# AGENTS.md — Project-Level Instructions for AI Sessions ("Fog of Wburg")

## 🤖 AI Session Startup & Operational Rules
- **Framework Constraint**: This project relies strictly on **Expo Managed Workflow (Continuous Native Generation / Prebuild)**. **Never** suggest, configure, or manually alter files inside the `ios/` or `android/` native directories directly. All native configurations must be handled via `app.json` config plugins.
- **Environment Execution**: Always use `python3` for any auxiliary scripts, and standard npm/yarn/pnpm commands for Expo runtime management.
- **Strict Adherence**: Adhere strictly to the locked-in library versions and patterns defined in `architecture.md` and `design.md`. Do not introduce alternative libraries (e.g., do not swap `@maplibre/maplibre-react-native` for `@rnmapbox/maps`, and do not use asynchronous storage wrappers instead of `@op-engineering/op-sqlite`).

---

## 🛠️ Core Technical Guardrails

### 1. H3 Index Precision & Data Types
- **String Enforcement**: H3 indices are 64-bit integers that exceed JavaScript's safe integer limit (`2^53 - 1`). 
- **Rule**: **Always** store, transmit, and process H3 indices as 15-character hexadecimal strings (e.g., `"8b2a100d213fff"`). Never cast them to raw JavaScript numbers.

### 2. Map Performance & Bridge Bypass
- **Bridge Congestion Prevention**: When passing updated inverted polygon geometries to MapLibre, **always** enable `withSynchronousUpdate(true)` on the `ShapeSource` to leverage JSI memory sharing and bypass JSON stringification penalties over the React Native bridge.
- **Geometry Unioning**: Never push raw, un-merged arrays of thousands of discrete H3 hexagonal holes to the map layer. Periodic background workers must execute `h3.cellsToMultiPolygon` to dissolve internal vertices and maintain optimal topology for MapLibre's `earcut.hpp` triangulator.

### 3. Local Persistence & SQLite Directives
- **Synchronous JSI Driver**: Use `@op-engineering/op-sqlite` exclusively for all local data persistence.
- **Schema Mandates**: Any SQLite table containing H3 data **must** initialize with Write-Ahead Logging (`PRAGMA journal_mode = WAL;`) and include the `WITHOUT ROWID` clause to enforce direct clustered B-Tree indexing on the string primary key.

### 4. Background Battery & Location Rules
- **No Polling**: Time-based GPS polling is strictly prohibited. Location tracking must use hardware-level distance filtering (`distanceInterval: 10`, `deferredUpdatesDistance: 50`) via `expo-location`.
- **Drift Gate**: All incoming background coordinate updates must pass an Implied Speed filter ($\Delta d / \Delta t \le 12 \text{ m/s}$) to discard urban canyon multipath noise before hitting the H3 grid engine.

---

## 📋 Roadmap Execution & Protocol

When executing tasks from `roadmap.md`:
1. **Atomic Scoping**: Focus entirely on the assigned Task ID. Do not bleed into subsequent waves.
2. **Verification**: Run local tests, prebuild checks, or type-checking to verify the implementation before marking complete.
3. **Roadmap Hygiene**: 
   - Once a task is successfully verified, update its status in the **Master Status Table** inside `roadmap.md` from `Planned` to `✅ Done`.
   - Move the completed task's detailed prompt block out of `roadmap.md` and append it to `archive/shipped-waves-archive.md`.

---

## 🧪 Testing & Verification Rules

### 1. Mocking Native JSI & Map Modules (Jest)
Because we use `@op-engineering/op-sqlite` (JSI-based) and `@maplibre/maplibre-react-native`, standard Node.js/Jest unit tests will crash if not mocked.
- **Rule**: Provide robust manual mocks when writing unit tests for store logic or utility functions. The JSI engine does not exist in the standard Jest environment.

### 2. H3 Precision Sanity Checks
JavaScript loses precision on 64-bit integers. It's very easy to accidentally cast an H3 index to a Number during serialization.
- **Rule**: All tests validating H3 utility functions or database operations must explicitly assert that inputs and outputs are strictly strings (`typeof === 'string'`). Add regression tests using `Number.MAX_SAFE_INTEGER` boundaries to ensure no silent truncation occurs.

### 3. Background Task Emulation
Testing `expo-task-manager` and `expo-location` background listeners via unit tests is problematic.
- **Rule**: When writing tests for the "Velocity Gate" (Implied Speed Filter), decouple the coordinate math from the Expo listener. Write pure functions for calculating distance/time so they can be unit-tested without needing the Expo location emitter context.

### 4. Continuous Native Generation (CNG) Prebuild Checks
In an Expo Managed workflow, native behavior changes (e.g. background location permissions) happen via `app.json` config plugins.
- **Rule**: Testing native configuration changes requires verifying the prebuild. Always run `npx expo prebuild --clean` to ensure the iOS/Android folders generate successfully and the `Info.plist`/`AndroidManifest.xml` contain the correct values.

### 5. E2E and Performance Profiling
Since the biggest risk is frame drops during the `h3.cellsToMultiPolygon` merge step, unit tests are insufficient for performance guarantees.
- **Rule**: UI and map performance verification should be done on a physical device or via an E2E framework (like Maestro). Never trust the iOS Simulator/Android Emulator performance for MapLibre fog rendering.