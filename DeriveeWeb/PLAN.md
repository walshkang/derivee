# Phased Implementation Plan: Dérivée Web

This plan breaks down the development of Dérivée Web into testable milestones, matching the vision outlined in the README. Each phase concludes with a concrete validation step on an iPhone.

```mermaid
flowchart TD
    M1[M1: PWA Shell] --> M2[M2: Pack Distribution]
    M2 --> M3[M3: Offline Routing]
    M2 --> M4[M4: Offline Maps]
    M3 --> M5[M5: Realtime Overlay]
    M4 --> M5
    M3 --> M6[M6: Fog Sync & Invites]
```

## M1: PWA Shell
**Goal:** Build the installable offline-first shell (Preact/Vite) that caches its own assets but defers data pack loading.
**Concrete Build Steps:**
1. Setup Vite with `vite-plugin-pwa` for Workbox Service Worker generation.
2. Build UI shell (header, search bar placeholder, map container placeholder).
3. Self-host essential map assets: `fonts/Noto Sans Regular/0-255.pbf` and `sprites/dark.png`.
4. Configure `manifest.webmanifest` with `display: standalone` and `apple-touch-icon` (180x180).
5. Implement "Add to Home Screen" onboarding modal for iOS Safari.
**Test Procedure:**
- Serve via local network or Cloudflare Pages.
- Open in iOS Safari, add to Home Screen.
- Turn on Airplane Mode, force-close the app, and reopen it.
**Done Criteria:** The app opens instantly offline with a clean shell and no "Network Required" Safari errors.

## M2: Pack Distribution
**Goal:** Authenticate the user and securely download, decompress, and unpack the 28 MB city pack directly into OPFS.
**Concrete Build Steps:**
1. Deploy Cloudflare Worker (`derivee-api`) with `aws4fetch` presigned URL generation and Access Email OTP.
2. Configure R2 `fog-of-transit` bucket CORS.
3. Build a foreground Web Worker (`pack-installer.worker.ts`) using `@bokuweb/zstd-wasm` and `nanotar`.
4. Implement download flow: `GET /api/pack-url` -> Stream R2 -> Decompress -> Tar slice -> Write to OPFS (`navigator.storage.getDirectory()`).
5. Use Screen Wake Lock API (`navigator.wakeLock.request('screen')`) during the process.
**Test Procedure:**
- Install app on iPhone, login via Email OTP.
- Monitor the foreground progress bar as it downloads 28 MB and writes ~70 MB of files to OPFS.
- Turn on Airplane Mode.
**Done Criteria:** Files (`walk_graph.bin`, `timetable.bin`, `nyc-basemap.pmtiles`) are verified in OPFS via Web Inspector, and app state updates to "Pack Installed".

## M3: Offline Routing
**Goal:** Integrate the C++ RAPTOR and A* engine via WebAssembly to compute trips 100% offline.
**Concrete Build Steps:**
1. Compile `DeriveeCore` to WASM using `emcc` with flags: `-std=c++20 -O3 -flto -fno-rtti -fwasm-exceptions -sWASM=1 -sFILESYSTEM=0 -sINITIAL_MEMORY=134217728 -sALLOW_MEMORY_GROWTH=1 -sMAXIMUM_MEMORY=536870912 -sMALLOC="dlmalloc"`.
2. Implement C-ABI bridge with `_allocate_aligned` (using `posix_memalign(64)`).
3. Build `routing.worker.ts` to read binaries from OPFS via `FileSystemSyncAccessHandle` and pass pointers to the WASM heap.
4. Wire up origin/destination search UI to send `postMessage` queries to the worker.
**Test Procedure:**
- On iPhone (Airplane mode), select two locations (e.g., Union Square to Barclays Center).
- Execute the search.
**Done Criteria:** Query returns a valid transit itinerary (walk -> subway -> walk) in under 50ms.

## M4: Offline Maps
**Goal:** Render the NYC vector basemap offline using PMTiles and MapLibre.
**Concrete Build Steps:**
1. Generate `nyc-basemap.pmtiles` (~22 MB) using `pmtiles extract`.
2. Integrate `maplibre-gl` and the `pmtiles` JS library.
3. Register the custom protocol and load the PMTiles file from OPFS using `pmtiles.FileSource`.
4. Apply custom dark/fog styling (pruned to ~25 layers) and render transit routes (GeoJSON) from the M3 itinerary.
**Test Procedure:**
- On iPhone (Airplane mode), search a route.
- Pan and zoom the map along the route.
**Done Criteria:** MapLibre renders the vector tiles smoothly at 60fps with zero network requests, using local glyphs and sprites.

## M5: Realtime Overlay
**Goal:** Overlay live delays and vehicle positions when the device has connectivity.
**Concrete Build Steps:**
1. Implement network state listeners (`window.addEventListener('online'/'offline')`).
2. When online, directly fetch GTFS-RT protobufs from `api-endpoint.mta.info`.
3. Fetch daily reliability deltas (`transit_delta.sqlite.zst`) via `GET /api/delta` on the Worker.
4. Pass delay updates to the routing WASM worker to adjust timetables dynamically.
**Test Procedure:**
- On iPhone, disable Airplane Mode.
- Verify status badge switches from `[Sched]` to `[Live]`.
- Check itinerary for realtime delay adjustments.
**Done Criteria:** App gracefully transitions between scheduled and realtime data without blocking the UI.

## M6: Fog Sync & Invites
**Goal:** Synchronize explored territory across a trusted group of friends.
**Concrete Build Steps:**
1. Configure Cloudflare D1 with `user_fog` schema.
2. Add `POST /api/sync` and `GET /api/sync` to the Worker for atomic upserts.
3. Track visited H3 hexes in client IndexedDB.
4. Debounce and upload discovered hexes when online.
5. Add friends' emails to Cloudflare Access allowlist.
**Test Procedure:**
- Two iPhones logged in with different allowed emails.
- Explore an area on iPhone A, observe sync to Cloudflare D1.
- Open iPhone B, observe fog-of-war map update with iPhone A's exploration (if shared vision is enabled) or personal sync state.
**Done Criteria:** H3 hex state persists across sessions and devices via D1 synchronization.
