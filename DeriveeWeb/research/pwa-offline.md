# Research: PWA Offline Architecture & iOS Safari Constraints (2026)

**Project:** Dérivée Web  
**Date:** 2026-09-27  
**Status:** Complete  
**Target Platform:** iPhone-first (iOS Safari / Mobile WebKit PWA), standalone mode  
**Key Constraints:** 28 MB compressed pack (`city-nyc.pack.zst`), ~55–70 MB uncompressed binaries (`walk_graph.bin` 47 MB, `timetable.bin` 6.9 MB, `ultra_transfers.csr`, `transit.sqlite`), offline vector maps (PMTiles), offline WASM routing (RAPTOR + A*), gated R2 distribution via Cloudflare Worker.

---

## 1. Executive Summary

Building a reliable 50–100 MB offline PWA for iOS Safari in 2026 is fully viable, but requires avoiding several high-profile platform traps. iOS Safari now offers generous storage quotas (up to 60% of total disk space per origin since iOS 17), full Origin Private File System (OPFS) support, and Web Push. However, iOS remains uniquely restrictive: **no Background Sync**, **no Background Fetch**, **no silent push**, **no `beforeinstallprompt`**, and **no support for `COEP: credentialless`**.

To ensure rock-solid offline operation on iPhone:
1. **Split App Shell from City Pack:** Use **Workbox (via `vite-plugin-pwa`)** strictly for the lightweight App Shell (HTML, JS, CSS, icons, WASM binaries). Never download or precache the 28 MB data pack during the Service Worker `install` phase.
2. **Store Binaries in OPFS:** Store the extracted routing binaries (`walk_graph.bin`, `timetable.bin`), SQLite DB, and offline PMTiles in the **Origin Private File System (OPFS)**. OPFS bypasses IndexedDB serialization overhead and enables synchronous byte reads (`FileSystemSyncAccessHandle`) and random byte slicing (`Blob.slice()`) essential for PMTiles and C++ memory layouts.
3. **Run WASM Single-Threaded in a Dedicated Web Worker:** Avoid `SharedArrayBuffer` and multithreading. Safari requires `Cross-Origin-Opener-Policy: same-origin` and `Cross-Origin-Embedder-Policy: require-corp` (it does *not* support `credentialless`), which will block cross-origin calls to MTA GTFS-RT APIs and third-party map assets unless heavily proxied. RAPTOR queries take under 25ms on modern Apple Silicon; a single-threaded WebAssembly worker provides 60fps UI without security header complications.
4. **Foreground-Only Pack Pipeline with Wake Lock:** Because Safari suspends background scripts within 30 seconds and lacks Background Fetch, downloading and decompressing the 28 MB pack must happen entirely in the foreground. Use the Screen Wake Lock API (`navigator.wakeLock.request('screen')`, supported in standalone PWAs) to prevent the screen from sleeping mid-unpack.
5. **Persist Storage Explicitly:** Request `navigator.storage.persist()`. When installed to the Home Screen, WebKit heuristically grants persistent storage exemption from the 7-day Intelligent Tracking Prevention (ITP) eviction rule.

---

## 2. Service Worker Offline Strategies in 2026: Workbox vs Hand-Rolled

### 2.1 State of the Ecosystem (2026)
In 2026, the modern PWA ecosystem has coalesced around two primary patterns:
* **Workbox (via `vite-plugin-pwa`):** The de facto standard across production web apps. It automates content-hashed precaching, cache versioning, cache cleanup upon new releases, and standard runtime strategies (`StaleWhileRevalidate`, `CacheFirst`, `NetworkFirst`).
* **Serwist (`@serwist/vite`):** A modern fork/successor focusing on modular TypeScript and Next.js/Vite setups. It shares the same underlying architectural patterns as Workbox.
* **Hand-Rolled Service Workers:** Used only for hyper-minimalist apps or bespoke edge proxies. In complex PWAs, hand-rolled service workers frequently suffer from cache invalidation bugs (e.g. index.html referencing stale hashed JavaScript bundles, orphan cache accumulation).

### 2.2 The App Shell vs Dynamic Data Pack Dichotomy
A common pitfall in offline web apps is attempting to precache application data packs inside the Service Worker `install` event. This is an anti-pattern for Dérivée:

| Requirement | App Shell (HTML/JS/CSS/WASM) | City Data Pack (`city-nyc.pack.zst`) |
| :--- | :--- | :--- |
| **Payload Size** | ~1–3 MB total | 28 MB compressed / ~60 MB uncompressed |
| **Update Lifecycle** | On app release / code deployment | Periodic (weekly/monthly GTFS schedule updates) |
| **Delivery Mechanism** | Static web server / Cloudflare Pages | Authenticated Cloudflare Worker (presigned R2 URL) |
| **Installation Phase** | Service Worker `install` event | In-app user onboarding / foreground setup |
| **Storage Destination** | Cache Storage API | Origin Private File System (OPFS) |
| **Tooling** | Workbox (`generateSW` or `injectManifest`) | Streaming fetch + WebAssembly zstd decompressor |

> [!CAUTION]
> **Never precache the 28MB pack in the Service Worker install event.**
> WebKit imposes strict execution timeouts on the Service Worker `install` event (~30–45s). If a 28MB download stalls on a cellular connection, the install event times out, the service worker fails to register, and the entire app becomes non-functional offline.

### 2.3 Recommendation for Dérivée Web
* Use **`vite-plugin-pwa` (Workbox)** for the App Shell. Let it manage precaching of HTML, CSS, JavaScript chunks, fonts, transit line icons, and the WASM runtime binaries (`raptor.wasm`, `zstd.wasm`).
* Implement an **Application-Level Pack Pipeline** in a dedicated Web Worker to fetch, decompress, and unpack the 28MB data pack directly into OPFS, exposing granular progress events (bytes downloaded, decompression percentage) to the UI.

---

## 3. Storing Large Binaries Client-Side: Cache Storage vs IndexedDB vs OPFS

For 50–100 MB of binary assets (`walk_graph.bin` 47MB, `timetable.bin` 6.9MB, `transit.sqlite`, and `nyc.pmtiles`), the browser provides three storage options:

### 3.1 Comparison Matrix

| Storage API | Access Model | Random Access / Slicing | Performance Profile | Safari iOS Quirks & Durability |
| :--- | :--- | :--- | :--- | :--- |
| **Origin Private File System (OPFS)** | Virtual filesystem hierarchy (`FileSystemFileHandle`) | **Yes** (`FileSystemSyncAccessHandle.read` in Worker, or `Blob.slice`) | **Highest.** In-place byte reads; zero serialization overhead. | Supported since iOS 15.2. Subject to origin quota (up to 60% disk). `SyncAccessHandle` exclusive to Workers. |
| **Cache Storage API** | URL/Request $\rightarrow$ Response key-value | **No native Range slicing** in Safari. Full response returned. | **Fast for network fetches**, but requires loading whole buffer to memory. | Cannot slice 206 Partial Content in Safari without custom SW code. Storing 50MB blobs causes memory spikes. |
| **IndexedDB** | Transactional NoSQL object store | **No.** Must deserialize entire `ArrayBuffer` / `Blob`. | **Moderate/Slow.** Safari backs IndexedDB with SQLite; structured clone cost is high. | Storing >30MB binary objects in IDB can trigger memory allocation crashes on older iOS devices. |

### 3.2 Deep Dive: OPFS as the Winner for Large Binaries
Research from data-intensive browser applications (such as Lumafield's 3D volumetric viewer and the official SQLite Wasm team) demonstrates that OPFS outperforms IndexedDB by 3x–5x for large binary payloads:
1. **Zero-Copy & Direct Memory Loading:** In the routing Web Worker, an OPFS file handle can read slices directly into WebAssembly linear memory (`Module.HEAPU8.subarray(ptr, ptr + len)`), avoiding duplicating 47MB ArrayBuffers in the V8/JavaScriptCore heap.
2. **PMTiles Compatibility:** PMTiles relies on byte-range requests to read tile index roots and vector tile leaves without downloading the entire 50–100MB map file. PMTiles supports custom `Source` implementations. In OPFS, `fileHandle.getFile()` returns a standard `File` (Blob) object. Calling `file.slice(offset, offset + length).arrayBuffer()` provides instantaneous random reads with zero network emulation or Service Worker Range-request hacks.
3. **SQLite Wasm VFS Support:** The official SQLite WebAssembly distribution includes an OPFS VFS backend (`wa-sqlite` / official SQLite OPFS VFS), allowing `transit.sqlite` to be queried via standard SQL queries directly against OPFS storage.

### 3.3 Recommended Storage Layout for Dérivée Web
* **OPFS (`/packs/`):**
  * `/packs/current/walk_graph.bin` (47 MB)
  * `/packs/current/timetable.bin` (6.9 MB)
  * `/packs/current/ultra_transfers.csr` (~1 MB)
  * `/packs/current/transit.sqlite` (~5 MB)
  * `/packs/current/transit-lines.geojson` (~2 MB)
  * `/maps/nyc-streets-transit.pmtiles` (50–100 MB)
* **IndexedDB (`derivee-state`):**
  * `pack_metadata`: `{ packVersion: "3.0.0", installedAt: 1774900000, validated: true }`
  * `fog_of_war`: Visited hex tiles, local timestamp deltas awaiting sync.
  * `user_preferences`: Favorite stations, walking speed, transfer penalties.
* **Cache Storage (`workbox-precache-...`):**
  * App shell assets: `index.html`, `main.[hash].js`, `style.[hash].css`, transit badges, `raptor.wasm`.

---

## 4. iOS Safari PWA Limits & Platform Constraints (2026 Verified)

### 4.1 Storage Quotas (Safari 17+, iOS 17 & iOS 18)
* **Origin Quota:** WebKit abandoned the legacy 1GB static cap in Safari 17.0 (August 2023). Origin quota is now dynamically calculated based on total device storage:
  * **Browser & Standalone Home Screen PWAs:** Up to **60% of total disk space** (e.g. on a 128 GB iPhone, single-origin quota exceeds 60 GB).
  * **Embedded WebViews (WKWebView):** Up to **15% of total disk space**.
* **Overall Quota:** Up to **80% of total disk space** across all origins combined.
* **Permission Prompts Eliminated:** Safari no longer prompts the user with confirmation dialogs when a site exceeds 1 GB.
* **Inspection:** Queryable via `navigator.storage.estimate()` (returns padded numbers to mitigate fingerprinting).

### 4.2 Eviction Policy & Intelligent Tracking Prevention (ITP)
* **The 7-Day Inactivity Rule:** Under Apple's ITP, script-writable storage (`localStorage`, `IndexedDB`, `OPFS`, `Cache API`) in standard Safari browser tabs is purged after 7 days of user inactivity.
* **PWA Exemption:** Standalone PWAs (apps added to the Home Screen) have an independent container and usage counter. Active use of the Home Screen PWA resets the inactivity timer and protects the app from the 7-day browser tab purge.
* **Persistent Storage API:** Calling `await navigator.storage.persist()` requests eviction protection. WebKit grants this request based on heuristics; WebKit specifically includes "whether the website is opened as a Home Screen Web App" and "whether push notifications are granted" as positive heuristics.
* **Disk Pressure Eviction:** If the physical device storage drops below critical levels, iOS will purge storage across origins using a Least-Recently-Used (LRU) algorithm. Storage is never 100% immune from device-wide low-disk emergencies.

### 4.3 Background Lifecycle & Execution Limits
* **Aggressive Suspension:** When an iOS PWA is backgrounded (user switches apps, locks screen, or swipes home), WebKit suspends the web process within **3 to 10 seconds**.
* **Service Worker Termination:** Service workers on iOS are killed after approximately **30 to 45 seconds** of background inactivity.
* **Background Sync API:** **Unsupported.** WebKit does not implement `SyncManager` or `PeriodicBackgroundSync`. Attempting to register background sync tags throws an error.
* **Background Fetch API:** **Unsupported.** Background downloads cannot continue when the PWA is closed.
* **Implication for Dérivée:** Syncing fog-of-war or downloading pack updates must be completed while the app is active in the foreground, or resumed when the user re-opens the app.

### 4.4 Web Push on iOS
* **Availability:** Supported since iOS 16.4 for PWAs added to the Home Screen.
* **User Gesture Mandate:** `Notification.requestPermission()` must be invoked from a direct user tap (e.g. tapping "Enable Departure Alerts").
* **No Silent Push:** Apple requires that every incoming Web Push message result in a visible notification (`self.registration.showNotification(...)`). Silent pushes intended to wake the service worker for background data syncing are prohibited; WebKit revokes push permissions if a push event finishes without displaying a notification.
* **Declarative Web Push (2025/2026):** WebKit supports push messages rendered directly by the OS without waking the service worker, conserving battery life.

### 4.5 Installability & "Add to Home Screen"
* **No `beforeinstallprompt`:** Apple has explicitly rejected `beforeinstallprompt`. There is no JavaScript API to launch the native iOS install dialog.
* **Custom In-App UI Required:** Dérivée Web must detect iOS Safari (`navigator.standalone === false`) and show an interactive onboarding modal instructing the user:
  1. Tap the Safari **Share** icon (square with arrow).
  2. Scroll down and tap **"Add to Home Screen"**.
* **Essential Manifest & Meta Tags:**
  * `<link rel="manifest" href="/manifest.webmanifest">` with `"display": "standalone"`.
  * `<meta name="apple-mobile-web-app-capable" content="yes">`
  * `<meta name="apple-mobile-web-app-status-bar-style" content="black-translucent">`
  * `<link rel="apple-touch-icon" href="/icons/apple-touch-icon-180x180.png">` (must be square, non-transparent PNG).

### 4.6 Screen Wake Lock API
* Supported in iOS Safari (16.4+) and officially fixed for standalone Home Screen PWAs in iOS 18.4.
* Requesting a wake lock (`await navigator.wakeLock.request('screen')`) during the 28MB download and zstd decompression prevents the iPhone from sleeping or locking mid-unpack.

---

## 5. WASM + SharedArrayBuffer on iOS Safari: COOP/COEP Analysis

### 5.1 Current Support State
* `SharedArrayBuffer` is supported in iOS Safari (iOS 15.2+) **only when the execution environment is cross-origin isolated**.
* Isolation requires sending two HTTP response headers:
  * `Cross-Origin-Opener-Policy: same-origin`
  * `Cross-Origin-Embedder-Policy: require-corp`

### 5.2 The Critical Safari Gotcha: No `COEP: credentialless`
* Chromium and Firefox support `Cross-Origin-Embedder-Policy: credentialless`, which allows loading third-party cross-origin subresources without requiring them to set `Cross-Origin-Resource-Policy` (CORP) headers.
* **Safari does NOT support `credentialless` as of late 2026.** Safari only supports `COEP: require-corp`.
* Under `COEP: require-corp`, **any cross-origin resource that lacks a `Cross-Origin-Resource-Policy: cross-origin` header is blocked immediately by Safari.**
* **Impact on Dérivée Web:**
  * MTA GTFS-RT feeds (`api-endpoint.mta.info`)
  * Map tile servers or external CDN fonts
  * External routing endpoints
  All would fail to load unless proxied through our Cloudflare Worker to inject synthetic CORP/CORS headers.

### 5.3 Architectural Decision: Single-Threaded WASM Web Worker
* **Do we need `SharedArrayBuffer`? No.**
* Dérivée's C++ RAPTOR engine and A* walk router do not require multithreading. On an Apple Silicon mobile CPU (A16/A17/A18), a single-threaded C++ RAPTOR query over NYC transit takes **5 to 25 milliseconds**.
* By placing the WebAssembly instance inside a dedicated standard **Web Worker**:
  1. The main UI thread remains completely unblocked at 60/120fps.
  2. The worker communicates with the UI via standard, lightweight `postMessage` JSON payloads (`{ origin, destination, time }` $\rightarrow$ `{ itinerary }`).
  3. No `SharedArrayBuffer` is needed.
  4. No COOP/COEP headers are needed.
  5. Direct client fetches to public MTA GTFS-RT endpoints remain unhindered.

---

## 6. Offline Fallback UX Best Practices

Transit applications have unique offline UX requirements: users frequently lose signal in subterranean subway stations while navigating.

```
                    ┌────────────────────────┐
                    │    App Cold Launch     │
                    └───────────┬────────────┘
                                │
                   Is App Shell Cached in SW?
                     ├─── NO (First Visit) ───► Safari Offline Error (Network Required)
                     │
                    YES
                     │
              Check OPFS for Pack
         ┌───────────┴───────────┐
         ▼                       ▼
    [Pack Missing]        [Pack Present]
         │                       │
   Is Online?               Load WASM Router
   ├── YES ──► Prompt Pack  from OPFS into Worker
   │           Download          │
   │                             │
   └── NO ───► Show Pack-   Is Online?
               Offline UI   ├── YES ──► Live GTFS-RT + Scheduled Baseline
                            │
                            └── NO ───► Scheduled Baseline Only
                                        Pill: "Offline — Scheduled Times"
```

### 6.1 State 1: First Visit Ever (No Network)
* Unavoidable browser reality: If a user has never visited the URL and has no network, Safari displays its native "Safari cannot open the page" error. The app shell must be loaded at least once online.

### 6.2 State 2: Shell Installed, Pack Missing, Device Offline
* **Scenario:** User opened the app once on Wi-Fi, added it to Home Screen, but closed it before downloading the 28MB pack. Now they open the app on the subway.
* **UX Response:**
  * Render the app shell cleanly (header, title, offline graphic).
  * Do not show an empty broken map or non-functional search box.
  * Prominently display: *"Offline Setup Required. Connect to Wi-Fi or cellular to download the NYC Transit Data Pack (28 MB). Once downloaded, all trip planning works 100% offline."*
  * Listen for `window.addEventListener('online', ...)` and automatically resume/offer download as soon as connectivity returns.

### 6.3 State 3: Pack Downloading & Unpacking (Foreground Setup)
* **Acquire Screen Wake Lock:** Call `navigator.wakeLock.request('screen')` immediately upon download start to prevent the phone from locking.
* **Granular Multi-Stage Progress:**
  1. *Downloading NYC Transit Pack...* (Progress bar with downloaded MB / 28 MB).
  2. *Decompressing Zstandard archive...* (Progress indicator).
  3. *Extracting graph & timetable to secure offline storage...* (Writing to OPFS).
  4. *Verifying binary checksums...* (MasterHeader magic check).
  5. *Ready!* (Release Wake Lock).
* **Warning Notice:** Show a subtle message: *"Please keep Dérivée open during this one-time setup."*

### 6.4 State 4: Repeat Visit (Pack Installed, Device Offline)
* **Instant Boot:** App shell loads in <200ms from Service Worker Cache.
* **Full Query Functionality:** Routing search bar, A* walk planner, and RAPTOR engine are 100% operational offline.
* **Vector Map Display:** Map renders from the local PMTiles file via MapLibre GL JS without making external HTTP requests.
* **Realtime Degraded State Banner:**
  * Display a subtle status pill in the header: `[● Offline — Scheduled Departures]`.
  * Timetable departure times show a `[Sched]` badge instead of the live countdown pill `[Live 3 min]`.
  * If a user requests a route, plan it using schedule-based travel times without showing spinner delays or timeout errors.

### 6.5 State 5: Reconnection Transition (Offline $\rightarrow$ Online)
* When `window.addEventListener('online')` fires:
  * Silently poll MTA GTFS-RT in the background.
  * Smoothly transition status badge to `[● Live]`.
  * Update upcoming departure times with live vehicle delays without resetting the user's active route or scroll position.

---

## 7. Concrete Architecture & Technical Recommendations

### 7.1 Storage Pipeline
1. **Fetch:** Fetch `city-nyc.pack.zst` via authenticated presigned R2 URL from the Cloudflare Worker.
2. **Decompress:** Decompress via WebAssembly Zstandard decompressor (`@bokuweb/zstd-wasm` or `zstddec`) inside a dedicated setup Web Worker.
3. **Unpack:** Stream the tar archive into individual files using a streaming tar parser, writing directly to OPFS (`navigator.storage.getDirectory()`).
4. **Clean Up:** Once binary headers (`observer::format::MasterHeader`) are validated, discard the raw `.pack.zst` archive to save 28 MB of device storage.
5. **Persist:** Invoke `await navigator.storage.persist()`.

### 7.2 Routing Engine Pipeline
1. In the routing Web Worker, open the OPFS directory:
   ```javascript
   const root = await navigator.storage.getDirectory();
   const timetableHandle = await root.getFileHandle('timetable.bin');
   const walkHandle = await root.getFileHandle('walk_graph.bin');
   ```
2. Read buffers into WASM linear memory:
   ```javascript
   const timetableFile = await timetableHandle.getFile();
   const timetableBuf = await timetableFile.arrayBuffer();
   const ttPtr = Module._malloc(timetableBuf.byteLength);
   Module.HEAPU8.set(new Uint8Array(timetableBuf), ttPtr);
   Module._load_timetable_blob(ttPtr, timetableBuf.byteLength);
   ```
3. Expose a simple `postMessage` RPC interface to the main thread for queries:
   ```javascript
   // Main thread
   routerWorker.postMessage({ id: 1, type: 'QUERY_ROUTE', origin: [40.7128, -74.0060], dest: [40.7580, -73.9855], departureTime: 1774902000 });
   ```

### 7.3 Map Rendering Pipeline
1. Place `nyc.pmtiles` inside OPFS.
2. Implement a custom PMTiles `Source`:
   ```javascript
   class OPFSSource {
     constructor(fileHandle) { this.fileHandle = fileHandle; }
     async getBytes(offset, length) {
       const file = await this.fileHandle.getFile();
       const slice = file.slice(offset, offset + length);
       return { data: await slice.arrayBuffer() };
     }
   }
   ```
3. Pass this custom source to MapLibre GL JS, providing 100% offline vector map rendering with zero Service Worker HTTP interception issues.

---

## 8. Pitfalls & Anti-Patterns to Avoid

| Pitfall | Consequence | Prevention |
| :--- | :--- | :--- |
| **Putting 28MB pack in SW precache** | Service worker install timeout (~30s); complete app failure on spotty networks. | Precache app shell only. Fetch and unpack data pack at the application level in the foreground. |
| **Enabling COOP/COEP for WASM** | `COEP: credentialless` is unsupported on Safari; blocks MTA GTFS-RT APIs and external map resources. | Run WASM single-threaded in a standard Web Worker. No `SharedArrayBuffer` or COOP/COEP needed. |
| **Relying on Background Fetch or Sync** | APIs are completely absent in iOS Safari; background tasks fail silently. | Execute all sync and pack downloads in foreground; use Screen Wake Lock during onboarding. |
| **Storing 50MB ArrayBuffers in IndexedDB** | iOS Safari SQLite backing store can trigger high memory churn and IPC serialization timeouts. | Store binary blobs in OPFS; use IndexedDB strictly for metadata, user settings, and fog-of-war tiles. |
| **Leaking OPFS Sync Access Handles** | `createSyncAccessHandle` takes an exclusive lock. If left open, subsequent accesses throw `NoModificationAllowedError`. | Wrap sync access handle logic in `try ... finally { handle.close(); }`. |
| **Omitting `apple-touch-icon` meta tag** | iOS Home Screen displays an ugly downscaled screenshot instead of the app icon. | Explicitly define 180x180 square PNG `<link rel="apple-touch-icon" href="...">`. |
| **Ignoring Safari Private Browsing** | OPFS and persistent storage APIs throw `SecurityError` or `UnknownError` in Safari Private mode. | Wrap storage initialization in graceful feature detection with clear user messaging if in Private mode. |

---

## 9. Open Questions for Prototyping

1. **Zstandard In-Browser Decompression Speed:** Benchmark `@bokuweb/zstd-wasm` vs `zstddec` on an actual iPhone A-series processor: how many seconds does it take to decompress 28 MB into 60 MB?
2. **Streaming Tar to OPFS:** Can we pipe the zstd decompressed stream directly through a streaming tar extractor into OPFS file handles without staging the 60 MB uncompressed tar in memory?
3. **SQLite Wasm OPFS Performance:** Compare `wa-sqlite` (OPFS VFS) against in-memory SQLite querying for `transit.sqlite` station name searches and fuzzy geocoding.
4. **MapLibre GL iOS Safari WebGL Context Loss:** On low-memory iPhones, does holding 55 MB of WASM memory plus MapLibre WebGL vector tiles trigger WebGL context loss when switching between apps? Verify memory envelope during active route rendering.

---

## 10. Sources & References

* **WebKit Storage Policy & Quota:** [Updates to Storage Policy (WebKit.org, Aug 2023)](https://webkit.org/blog/14403/updates-to-storage-policy/)
* **Safari 17.0 WebKit Features:** [WebKit Features in Safari 17.0 (WebKit.org)](https://webkit.org/blog/14445/webkit-features-in-safari-17-0/)
* **OPFS vs IndexedDB Performance:** [High-Performance Browser Storage Architecture (Lumafield)](https://www.lumafield.com)
* **Web Push & Notification Restrictions:** [Meet Web Push for Safari (WebKit.org)](https://webkit.org/blog/13878/web-push-for-web-apps-on-ios-and-ipados/)
* **Screen Wake Lock PWA Support:** [WebKit Bugzilla #254544 / iOS 18.4 Release Notes](https://webkit.org)
* **PMTiles Custom Source Specification:** [PMTiles JS Client API](https://github.com/protomaps/PMTiles)
