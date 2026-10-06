# Milestone 2 (M2) Pack Distribution: iOS Safari Phone Test Procedure

**Target Device:** iPhone (iOS 16+) with Safari or Standalone PWA  
**Canonical PWA & API URL:** `https://derivee-api.walsh-8de.workers.dev`  
**Cloudflare Access Allowlist Identity:** `wkang1281@gmail.com`  
**Milestone Done Criteria:** 29.7 MB Zstandard city pack streams through Cloudflare Access, decompresses to ~65.3 MB, unpacks into OPFS, passes binary integrity validation, and opens 100% offline in Airplane Mode.

---

## Pre-Flight Check

1. Ensure your iPhone has an active network connection (Wi-Fi or Cellular).
2. Ensure you have access to email `wkang1281@gmail.com` to receive the Cloudflare Access One-Time PIN (OTP).

---

## Step 1: Initial Navigation & Cloudflare Access Authentication

1. Open **Safari** on your iPhone.
2. Navigate to:  
   `https://derivee-api.walsh-8de.workers.dev`
3. Cloudflare Access edge will intercept the request and display the Email OTP login screen.
4. Enter your email address: `wkang1281@gmail.com` and tap **Send Code**.
5. Check your email for the 6-digit Cloudflare Access PIN.
6. Enter the PIN and submit.
7. Safari lands on the **Dérivée Web PWA Shell**.
   - Cloudflare sets the `CF_Authorization` cookie (`HttpOnly, SameSite=Lax`) on `derivee-api.walsh-8de.workers.dev`.
   - Because the PWA shell and API are hosted **same-origin**, subsequent API requests seamlessly include this session cookie.

---

## Step 2: Installer Interface Verification

1. Examine the application shell:
   - Header: **Dérivée NYC**, status pill: `Online`.
   - Pack installer panel displays:
     - Title: **Install NYC Transit Data**
     - Description: Explains offline transit routing graph, timetables, and station geometries.
     - Specification grid:
       - Download Size: `~29.7 MB (zstd)`
       - Unpacked Size: `~65.3 MB (OPFS)`
       - Storage Engine: `Origin Private FS`
       - Authenticated As: `wkang1281@gmail.com`
     - Action button: **Download NYC Pack (~30 MB)**.
   - Footer drawer displays:
     - `Shell: Cached Offline` (green dot)
     - `Pack: Not Installed` (amber dot)
     - `Network: Connected` (green dot)

---

## Step 3: Foreground Download & Unpack Pipeline

1. Tap the prominent **Download NYC Pack (~30 MB)** button.
2. Observe the Screen Wake Lock indicator:
   - Status badge shows: `🔒 Screen kept awake` (or fallback warning if OS blocked wake lock).
3. Monitor the live progress bar through its stages:
   - **Stage 1 (Downloading):** Live byte counter streams from 0 to ~29.7 MB (`X.X MB / 29.7 MB (Y%)`).
   - **Stage 2 (Decompressing Archive):** `@bokuweb/zstd-wasm` decompressing the Zstandard byte stream into memory.
   - **Stage 3 (Writing to OPFS):** Files written counter (`1 of 6`, `2 of 6`, ... `6 of 6`) indicating file names:
     - `city_config.json`
     - `transit.sqlite`
     - `transit-lines.geojson`
     - `ultra_transfers.csr`
     - `timetable.bin`
     - `walk_graph.bin`
   - **Stage 4 (Verifying Integrity):** JS integrity checks mirror `CityPackManager.swift`:
     - MasterHeader: 232-byte header size, magic `0x31565244` (`DRV1`) on `timetable.bin`, magic `0x4B4C4157` (`WALK`) on `walk_graph.bin`, endianness `0x01020304`, file size matching physical size.
     - BinaryHeader: 32-byte header size, magic `0x554C5452` (`ULTR`) on `ultra_transfers.csr`.
     - SQLite: size >= 4096 bytes, `SQLite format 3\0` magic on `transit.sqlite`.
     - Schemas: valid JSON and GeoJSON on `city_config.json` and `transit-lines.geojson`.

---

## Step 4: Confirm Installed State

1. Once verification passes, observe the UI update:
   - Green badge: **Pack Installed**
   - Pack title: **New York City (v3)**
   - Season label: **Summer 2026 Timetable**
   - Total OPFS Size: **~65.3 MB**
   - Files Verified: **6 / 6**
   - Table of verified files with checkmarks and individual sizes:
     - `city_config.json` (~3.4 KB)
     - `transit.sqlite` (~9.7 MB)
     - `transit-lines.geojson` (~407 KB)
     - `ultra_transfers.csr` (~582 KB)
     - `timetable.bin` (~7.2 MB)
     - `walk_graph.bin` (~47.4 MB)
   - Footer drawer updates to: `Pack: NYC v3 (Installed)` with green dot.
   - Center map placeholder card updates to: `Cartography Standby` / `Pack Installed (OPFS)` / `Ready for C++ RAPTOR engine (M3)`.

---

## Step 5: Airplane Mode Offline Launch & Persistence Verification

1. Swipe down iOS Control Center and enable **Airplane Mode** (turn OFF Wi-Fi and Cellular).
2. Force-close Safari:
   - Swipe up from the bottom of the iPhone screen to open App Switcher.
   - Swipe Safari up and off the screen to terminate its process completely.
3. Open Safari again (or tap Dérivée from your iOS Home Screen if installed).
4. Reopen or navigate to:  
   `https://derivee-api.walsh-8de.workers.dev`
5. **Expected Result:**
   - App shell loads instantly from Service Worker Cache Storage without any Safari network error.
   - Header shows: status pill `Offline` (amber).
   - On launch, the app inspects OPFS directly and verifies that all 6 files physically exist on disk.
   - Pack status immediately reports: **Pack Installed** (v3, 65.3 MB verified).
   - Footer drawer reports: `Pack: NYC v3 (Installed)` (green) and `Network: Offline` (amber).

---

## Step 6 (Optional): Safari Web Inspector Storage Verification

If debugging via Mac:
1. Connect iPhone to Mac with USB cable.
2. In macOS Safari: **Develop** -> **[Your iPhone Name]** -> **`derivee-api.walsh-8de.workers.dev`**.
3. Open the **Storage** tab -> **Origin Private File System**.
4. Confirm folder `/nyc/` is visible and contains all 6 files with exact sizes.
