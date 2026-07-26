# Shipped Waves Archive — Fog of Wburg

This archive contains detailed task prompts for completed development waves.

---

## Wave 1 — Foundation & UI Shell

### Task Prompt: W1-INIT — Expo Scaffold & Zustand State
**Goal**: Initialize the raw Expo environment and set up the global state manager.
1. Initialize a new Expo SDK 51+ project (Managed Workflow) using TypeScript.
2. Install `zustand` and create a global store (`store/useExplorationStore.ts`).
3. The store should track: `isExploring` (boolean), `currentLocation` (lat/lng | null), and `unlockedHexes` (array of strings).
4. Configure absolute imports in `tsconfig.json` (e.g., `@/*` maps to `./src/*`).

### Task Prompt: W1-NAV — Navigation Shell & Splash Screen
**Goal**: Build the routing architecture and "The Awakening" splash screen.
1. Install Expo Router.
2. Create the Splash Screen (`app/index.tsx`) with a dark, atmospheric background (simulating the fog) and a central logo.
3. Build the main layout shell that transitions from the Splash Screen to `app/(tabs)/map.tsx` (The Cartographer's Desk) and `app/(tabs)/archive.tsx` (The Archive).
4. Do not build the actual map yet; just place a placeholder `<View>` where MapLibre will eventually go.

---

## Wave 2 — Core DB & Spatial Engine

### Task Prompt: W2-DB — op-sqlite JSI Initialization & WAL Mode
**Goal**: Configure the high-speed local persistence layer.
1. Configure `@op-engineering/op-sqlite`.
2. Create the `explored_hexes` schema using `WITHOUT ROWID` and `h3_index` as the string primary key.
3. Enable `PRAGMA journal_mode = WAL;` and `PRAGMA synchronous = NORMAL;`.
4. Create helper functions for inserting hexes (`INSERT OR IGNORE`) and querying all unlocked hexes.
