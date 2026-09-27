# Dérivée Web — offline-first HTML transit app for NYC

**Status:** research phase (started 2026-09-27). Not yet prototyped.

## Vision
The best HTML transit app we can build from what we already own: a PWA that
downloads the v2 city pack once, then plans real walk+transit trips **fully
offline** in the browser via a WebAssembly build of our C++ RAPTOR engine —
with realtime departures overlaid when online, and fog-of-war that syncs
through a friend-gated Cloudflare Worker.

Audience: Walsh + friends. iPhone-first (Safari PWA constraints drive
architecture decisions).

## Assets we own (inputs)
- `DeriveeNative/Derivee/city-nyc.pack.zst` — v2 pack (v3.0.0, 28 MB):
  `walk_graph.bin` (1.33M nodes / 3.27M edges, 47 MB), `timetable.bin`
  (RAPTOR, 6.9 MB), `ultra_transfers.csr` (81,566 shortcuts), `transit.sqlite`,
  `transit-lines.geojson`, `city_config.json`.
- C++ engine: `DeriveeNative/DeriveeCore/src/RaptorEngine.cpp`,
  `BoundedAStarRouter.cpp` (+ bridge). Compiles to WASM via Emscripten.
- Observer pipeline → daily reliability deltas → Cloudflare R2
  (`fog-of-transit` bucket). MTA GTFS-RT is public/keyless.
- Binary formats: 232-byte MasterHeader (timetable, walk graph), 32-byte
  BinaryHeader (ULTRA CSR); magic/version/endian/file-size validated at
  install (see `CityPackManager.validateBinaryAsset`).

## Architecture sketch (to be validated by research)
1. **PWA shell** — installable, service worker, app shell cached.
2. **Pack pipeline** — Cloudflare Worker issues short-lived presigned R2 URLs
   (gated by Cloudflare Access email allowlist); browser downloads pack once,
   decompresses zstd (WASM), unpacks tar, stores in Cache Storage / IndexedDB.
3. **Routing** — Emscripten build of RaptorEngine + walk router; binaries
   loaded into WASM linear memory; queries run fully offline.
4. **Maps** — PMTiles single-file vector tiles + MapLibre GL, cached offline.
5. **Online overlay** — GTFS-RT fetched direct from MTA when connected;
   reliability deltas via the Worker-gated pipeline.
6. **Sync** — fog-of-war in IndexedDB; Worker-mediated sync, per-user
   namespaced, rate-limited. No client-held R2/D1 credentials, ever.

## Testable milestones
- [ ] M1: PWA shell installable on iPhone, opens offline (app shell only).
- [ ] M2: Pack downloads through the gated Worker, unpacks in-browser.
- [ ] M3: Offline trip query in-browser (WASM RAPTOR): A→B with no network.
- [ ] M4: Offline vector map renders under the route.
- [ ] M5: Realtime departures overlay when online.
- [ ] M6: Friend invites via Cloudflare Access; fog-of-war syncs.

## Research notes (shareable with implementation agents)
- `research/pwa-offline.md` — service workers, Cache Storage, iOS Safari PWA limits.
- `research/wasm-routing.md` — Emscripten, large-asset WASM memory, zstd/tar in browser.
- `research/offline-maps.md` — PMTiles + MapLibre, NYC extract generation.
- `research/cloudflare-private-distribution.md` — R2 presigned URLs, Workers, Access, rate limits.
