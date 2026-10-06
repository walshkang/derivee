# M2 Implementation Plan: Dérivée Web Pack Installer & Same-Origin Distribution

**Date:** 2026-09-27  
**Author:** AI Agent (Antigravity)  
**Milestone:** M2 (Pack Distribution)  
**Target URL:** `https://derivee-api.walsh-8de.workers.dev`  

---

## 1. Executive Summary & Goals

The objective of Milestone 2 (M2) is to deliver end-to-end city pack distribution and storage for Dérivée Web on iOS Safari and desktop browsers:
1. **Authenticated Session Handling:** Integrate Cloudflare Access Email OTP authentication via `/api/me`. Present a polished sign-in screen when unauthenticated that redirects top-level to `/` for OTP challenge.
2. **Foreground Pack Streaming & Decompression:** Download `city-nyc.pack.zst` (~29.7 MB) directly from the Cloudflare Worker via `GET /api/pack`, stream bytes with live progress, decompress via `@bokuweb/zstd-wasm`, parse tar archive via `nanotar`, and write files to the Origin Private File System (OPFS).
3. **Screen Wake Lock:** Prevent iOS Safari from sleeping during the ~15–30s download and decompression pipeline using `navigator.wakeLock.request('screen')`.
4. **T.1b Integrity Verification:** Mirror `DeriveeNative/Derivee/CityPackManager.swift` validation checks in JavaScript to verify MasterHeader (232B, magic, version, endian, file size), BinaryHeader (32B), and SQLite magic headers before finalizing installation. On mismatch, delete partial files and present a retry UI.
5. **Persistent Launch State:** Cache pack installation metadata in `localStorage` and verify that all 6 files physically exist in OPFS on every application launch.
6. **Same-Origin Worker Serving:** Host the PWA static assets directly from `derivee-api` using Cloudflare Workers Static Assets (`env.ASSETS`), ensuring `CF_Authorization` (`HttpOnly, SameSite=Lax`) is sent reliably on same-origin subrequests.

---

## 2. Real Pack File List (Ground Truth Inspection)

Direct inspection of `city-nyc.pack.zst` (29,688,421 bytes) from R2 bucket `fog-of-transit`:

| File Name | Size (Bytes) | Format & Validation |
| :--- | :--- | :--- |
| `city_config.json` | 3,401 | JSON configuration (`version: 3`, `slug: "nyc"`, routing & transit metadata) |
| `transit.sqlite` | 9,744,384 | SQLite 3 database (`SQLite format 3\0`, size >= 4,096 bytes) |
| `transit-lines.geojson` | 407,221 | GeoJSON FeatureCollection with subway and transit geometries |
| `ultra_transfers.csr` | 582,906 | BinaryHeader (32B header: magic `0x554C5452` "ULTR", version `1`) |
| `timetable.bin` | 7,184,128 | MasterHeader (232B header: magic `0x31565244` "DRV1", version `1`, endian `0x01020304`, file_size `7184128`) |
| `walk_graph.bin` | 47,426,176 | MasterHeader (232B header: magic `0x4B4C4157` "WALK", version `1`, endian `0x01020304`, file_size `47426176`) |

**Total uncompressed footprint:** 65,348,216 bytes (~65.3 MB).

> [!NOTE]  
> **Deviation from Stale PLAN.md:** `PLAN.md` line 41 mentioned `nyc-basemap.pmtiles` as part of M2 pack verification. Inspection of the real archive confirms `pmtiles` is NOT part of `city-nyc.pack.zst`; per PLAN.md §M4, `nyc-basemap.pmtiles` is generated/extracted in Milestone 4. The M2 installer operates strictly on the 6 real files above.

---

## 3. OPFS Directory & Storage Layout

Using `navigator.storage.getDirectory()`:

```
[OPFS Root]
└── nyc/
    ├── city_config.json        (3.4 KB)
    ├── transit.sqlite          (9.7 MB)
    ├── transit-lines.geojson   (407 KB)
    ├── ultra_transfers.csr     (582 KB)
    ├── timetable.bin           (7.2 MB)
    └── walk_graph.bin          (47.4 MB)
```

- **Folder scoping:** Files are stored under the city slug `nyc/`. This matches the native iOS layout (`CityPacks/{slug}/`) and allows multi-city scaling without naming collisions.
- **Write abstraction:** Files are written using `createWritable()` with fallback to `createSyncAccessHandle()` to guarantee compatibility with all Safari iOS versions.
- **Cleanup on error:** If decompression or integrity checks fail, the staging files or `nyc/` folder are recursively purged via `root.removeEntry('nyc', { recursive: true })`.

---

## 4. Ground Truth Integrity Validation (T.1b Swift Mirror)

**Cited Source:** `DeriveeNative/Derivee/CityPackManager.swift` lines 73–92 and 592–666.

The TypeScript validation utility `packIntegrity.ts` mirrors the exact Swift assertions:
1. **`transit.sqlite`:**
   - Physical size >= 4,096 bytes.
   - First 16 bytes match ASCII `SQLite format 3\0` (`[0x53, 0x51, 0x4C, 0x69, 0x74, 0x65, 0x20, 0x66, 0x6F, 0x72, 0x6D, 0x61, 0x74, 0x20, 0x33, 0x00]`).
2. **`timetable.bin` (MasterHeader):**
   - Physical size >= 232 bytes.
   - Header size field at byte offset 12 == 232 (`uint32` little-endian).
   - Magic at offset 0 == `0x31565244` ("DRV1" in ASCII little-endian).
   - Schema version at offset 4 == 1.
   - Endianness marker at offset 8 == `0x01020304`.
   - File size at offset 16 (`uint64` little-endian) matches physical byte length.
3. **`walk_graph.bin` (MasterHeader):**
   - Physical size >= 232 bytes.
   - Header size at offset 12 == 232.
   - Magic at offset 0 == `0x4B4C4157` ("WALK" in ASCII little-endian).
   - Schema version at offset 4 == 1.
   - Endianness marker at offset 8 == `0x01020304`.
   - File size at offset 16 matches physical byte length.
4. **`ultra_transfers.csr` (BinaryHeader):**
   - Physical size >= 32 bytes.
   - Magic at offset 0 == `0x554C5452` ("ULTR" in ASCII little-endian).
   - Version at offset 4 == 1.
5. **`city_config.json`:**
   - Valid JSON, slug == "nyc", version >= 2 (observed: 3).

---

## 5. Same-Origin Serving via Cloudflare Worker

### Architectural Challenge
Cloudflare Access sets `CF_Authorization` as an `HttpOnly, SameSite=Lax` cookie on the application domain. When the PWA was served from `*.pages.dev`, cross-site fetch subrequests to `*.workers.dev` withheld the `SameSite=Lax` cookie, resulting in HTTP 401.

### Solution: Worker Static Assets (`env.ASSETS`)
1. Configure `wrangler.toml`:
   ```toml
   [assets]
   directory = "../../dist"
   binding = "ASSETS"
   not_found_handling = "single-page-application"
   ```
2. Update Worker `fetch`:
   - `/api/*` -> API routing (`/api/me`, `/api/health`, `/api/pack`).
   - All other requests -> `env.ASSETS.fetch(request)`.
3. Add `https://derivee-api.walsh-8de.workers.dev` to `ALLOWED_ORIGINS` in `index.ts`.
4. Workbox Service Worker:
   - Precache application shell including `.wasm`.
   - Set `navigateFallbackDenylist: [/^\/api/]` to prevent `/api/*` routes from being intercepted by Workbox.

---

## 6. Files to Create and Modify

1. **`DeriveeWeb/workers/derivee-api/src/index.ts`**
   - Add `GET /api/me` returning `{ email: userEmail }` or `401`.
   - Route non-`/api/*` requests to `env.ASSETS.fetch(request)`.
   - Add `https://derivee-api.walsh-8de.workers.dev` to allowed origins.
2. **`DeriveeWeb/workers/derivee-api/wrangler.toml`**
   - Add `[assets]` configuration pointing to `../../dist` with `single-page-application` handling.
3. **`DeriveeWeb/package.json`**
   - Install `@bokuweb/zstd-wasm` and `nanotar`.
4. **`DeriveeWeb/vite.config.ts`**
   - Ensure wasm is precached (`globPatterns`), add `navigateFallbackDenylist: [/^\/api/]`.
5. **`DeriveeWeb/src/types/pack.ts`**
   - Message protocols between main thread and `pack-installer.worker.ts`.
   - Status, progress, and metadata interfaces.
6. **`DeriveeWeb/src/utils/packIntegrity.ts`**
   - Binary header inspection, SQLite check, and JSON schema verification.
7. **`DeriveeWeb/src/utils/opfs.ts`**
   - OPFS file reading, writing, directory listing, and verification routines.
8. **`DeriveeWeb/src/workers/pack-installer.worker.ts`**
   - Web Worker executing the fetch stream, progress tracking, decompression, tar parsing, writing to OPFS, and integrity verification.
9. **`DeriveeWeb/src/components/PackInstaller.tsx`**
   - Complete installer UI:
     - Unauthenticated: "Sign In" screen with beta message and navigation to `/`.
     - Ready to install: "Download NYC Pack (~30 MB)" action.
     - Installing: Live progress bar, stages (download, decompress, write, verify), byte counters.
     - Installed: Pack details (version 3, size breakdown, file list, install timestamp, reinstall option).
     - Error: clear error messages (401, 429, integrity, network) with retry action.
10. **`DeriveeWeb/src/components/SystemInfoDrawer.tsx` & `MapPlaceholder.tsx`**
    - Connect to active pack status.
11. **`DeriveeWeb/src/App.tsx`**
    - Coordinate auth check, pack verification on launch, and render installer.
12. **`DeriveeWeb/PLAN.md` & `README.md`**
    - Update documentation with the shipped same-origin architecture and direct R2 streaming.
13. **`DeriveeWeb/m2-test-procedure.md`**
    - Step-by-step verification instructions for Walsh on an iPhone.
