# Dérivée — The Calculus of Your City

> *Unlearn your commute.*

**Dérivée** *(day-ree-vay)* — a double-entendre combining the mathematical *derivative* (the rate of change at a specific point on a curve) with the Situationist *dérive* (an unplanned drift through an urban landscape). This app is literally the intersection: **calculating the rate of change of your physical presence across the city map.**

An ambient, offline-first iOS application that transforms your daily commute and neighborhood walks into a quiet journey of discovery. It rejects the aggressive completionism of traditional mapping games. Instead, it offers a calm, translucent environment — a harness for real life — that teases discovery through a volumetric fog-of-war and provides commuter-grade transit data *only* when you explicitly ask for it.

---

## 🌫 Core Experience

* **The Volumetric Fog:** Unexplored areas are covered by a soft, diffuse, translucent cloud layer. Underneath, major geographic arteries (coastlines, bridges, arterial roads) are faintly visible as nameless vectors, subconsciously luring you to explore.
* **The Vicinity Bubble:** The app heavily utilizes progressive disclosure. Detailed geospatial data (street names, transit stops, bike docks) is only rendered within a dynamic ~200-meter physical radius of your live location.
* **Pristine History:** When you pan the camera to view an area you cleared weeks ago, you see only clean, beautiful satellite terrain. The map gets out of your way.
* **Ghost POIs:** Points of interest and transit nodes do not permanently clutter the map with pins. Once an area is cleared, they become invisible. They are only revealed if you are physically standing in that hex and tap your location to pull up a minimalist data sheet.
* **Exploration Stats:** While the main map abandons gamified HUDs, a dedicated profile screen tracks your macro-level progress (e.g., "Williamsburg: 14% Cleared") and houses a beautiful grid of your discovered Ghost POIs, satisfying the completionist itch without the anxiety.
* **Dynamic Day/Night Cycle:** The interface automatically shifts between Day Mode ("Clear Morning" — parchment whites `#F9F9F6`, graphite fog `#1C1C1E`) and Night Mode ("Midnight Grid" — midnight slate `#12121A`, OLED black fog `#000000`) based on local sunrise and sunset. **Electric Amber (`#FFB300`)** is the universal accent color — used for the live GPS dot, active transit routes, and Ghost POI glows.

## 🚇 Commuter-Grade Transit (Raw GTFS)

Dérivée features a Naver Maps-style transit integration built on a strictly "make it yourself, and make it well" philosophy, bypassing third-party API limits.

1. **Live Protocol Buffers:** Tapping a transit node in your Vicinity Bubble decodes the transit authority's binary GTFS-RT feeds on the fly, delivering crisp, real-time arrival countdowns and dynamic vector route previews.
2. **The Observer Pipeline:** Historical reliability (average headways, arrival sparklines) is powered by a custom, standalone Go (Golang) daemon hosted on a lightweight VPS. This persistent pipeline crunches raw GTFS data 24/7, generates a Zstandard-compressed SQLite delta database (`.sqlite.zst`), and pushes it to Cloudflare R2.
3. **Offline-First Sync:** The mobile app silently fetches this compressed SQLite file every morning, allowing instantaneous, offline rendering of historical charts directly from native memory using `@op-engineering/op-sqlite`'s `ATTACH DATABASE` JSI driver.

---

## 🎨 Design Language

The app follows a strict visual identity defined in [`docs/design.md`](docs/design.md):

* **The Map is the UI.** Edge-to-edge MapLibre canvas with no tab bars, no navigation headers, no persistent HUDs. Two translucent FABs (Recenter + Profile) float over the map using Apple's native `UltraThinMaterial` blur.
* **3-Tier Fog Visibility:** Hidden (dense fog), Explored (dimmed satellite, no labels), and Active (full-color 200m vicinity bubble with street names and Ghost POIs).
* **Ghost POI Lifecycle:** 3-phase system — faint beacon lures in the fog → crisp geometric nodes on proximity unlock → near-invisible archives when you leave.
* **Typography:** SF Pro / Inter for UI text; **SF Mono** exclusively for all quantitative metrics (percentages, headways, H3 IDs). No serif fonts.
* **Gesture Handling:** All interactive elements use `react-native-gesture-handler` exclusively to coexist with MapLibre pan/pinch and `@gorhom/bottom-sheet` gestures. No standard `TouchableOpacity` or `Pressable`.
* **Ambient Tracking:** Always-on, no manual start/stop. The native Swift `CLLocationManager` begins tracking silently on app mount.

---

## 🛠 Tech Stack & Architecture

Built as a **hybrid "Brownfield" architecture** under the **Sleepy Hermes** paradigm. Expo Managed Workflow (CNG / Prebuild) governs UI rendering, navigation, and config plugins. The `ios/` native workspace is **manually managed** for Nitro Module linkage, the H3 C-library bridging header, and the native Swift background service.

### Core Stack

| Package | Version | Role |
| --- | --- | --- |
| `expo` | `~51.0.0` | Core framework — CNG plugin support and UI rendering |
| `react-native` | `0.74.5` | Runtime |
| `@maplibre/maplibre-react-native` | `^10.4.2` | Map engine — vector tiles, custom raster layers, Data-Driven Styling |
| `h3-js` | `^4.5.0` | **Foreground only** — `gridDisk`, geometry unioning, `cellsToMultiPolygon` |
| `h3` (C library) | `v4.x` | **Background only** — native C-library linked via Xcode bridging header for `latLngToCell` at Resolution 11 |
| `@op-engineering/op-sqlite` | `^3.0.0` | JSI-powered SQLite — microsecond synchronous reads for spatial querying |
| `react-native-nitro-modules` | `^0.36.3` | JSI bridging — zero-serialization C++ templates mapping JS types to Swift objects in shared memory |
| `expo-location` | `~17.0.1` | **Foreground only** — permission requests and UI-level location display |
| `zustand` | `^4.5.2` | Lightweight, non-blocking UI state management |
| `protobufjs` | `^8.7.1` | On-the-fly decoding of binary GTFS-RT transit feeds |
| `react-native-reanimated` | `~3.10.1` | Sheet and UI animations |
| `@shopify/flash-list` | `^1.7.2` | 60fps virtualized lists for Exploration Stats |
| `@shopify/react-native-skia` | `1.2.3` | Aspirational — GPX reveal shader animation |
| `fast-xml-parser` | `^5.10.1` | GPX file parsing for workout import |
| `fit-file-parser` | `^4.1.0` | FIT file parsing for workout import |
| `expo-document-picker` | `~12.0.2` | Local file selection for GPX/FIT upload |

> **Removed from stack:** `expo-task-manager` — headless JS background tasks are architecturally banned under Sleepy Hermes. *(Still in `package.json` pending Wave D cleanup.)*

### Architectural Highlights

* **Sleepy Hermes:** All background location processing runs in pure native Swift — the Hermes JS engine sleeps when the app is backgrounded, preventing iOS watchdog terminations (`0x8badf00d`, `0xdead10cc`) and battery drain. See [`docs/architecture.md`](docs/architecture.md) for the full specification.
* **Dual-Thread SQLite:** Two concurrent connections (JS via `@op-engineering/op-sqlite`, Swift via raw C API) share a single `.db` file in WAL mode — enabling simultaneous background writes and foreground reads with zero lock contention.
* **Zero-Congestion Rendering:** An $O(1)$ In-Memory Set Gate drops redundant GPS updates before they hit the bridge. MapLibre Data-Driven Styling (DDS) `['match']` expressions filter fog opacity natively on the GPU — bypassing JSON stringification entirely.
* **Battery & Drift Optimization:** CPU remains asleep until physical movement occurs via hardware-level distance intervals (`distanceFilter: 10m`, deferred updates: `50m`). An implied speed filter ($\Delta d / \Delta t \leq 12$ m/s) aggressively discards urban canyon GPS multipath noise.
* **Nitro Pipeline:** TypeScript spec (`*.nitro.ts`) → `npx nitro-codegen` → generated C++/Swift translation layers (`nitrogen/generated/`) → manual Xcode GUI linkage. Zero-serialization JSI callbacks fire in real-time when the app is foregrounded.

### Brownfield Constraint

The `ios/` native workspace is manually managed. All Nitro Module linkage, H3 C-library imports, bridging header configuration, and Swift implementation files must be added through the **Xcode GUI** — never via scripts or `xcodeproj` manipulation. Always open `ios/Derivee.xcworkspace` (the CocoaPods workspace), not the bare `.xcodeproj`. See [`xcode_linkage_instructions.md`](xcode_linkage_instructions.md) for step-by-step instructions.

---

## 📍 Current Status

The project is mid-transition through the **Sleepy Hermes** architectural migration, replacing all legacy JavaScript-based background tracking with a pure native Swift service.

| Phase | Status |
| --- | --- |
| **Waves 1–14.10** (Expo Managed / JS Background) | ✅ Archived — see [`archive/shipped-waves-archive.md`](archive/shipped-waves-archive.md) |
| **Wave A** — Database Config & Dual-Thread Concurrency | ✅ Done |
| **Wave B** — Nitro Module Scaffolding & Code Generation | 🔧 In Progress (Human: Xcode GUI linkage) |
| **Wave 11.6** — Deploy Go Observer to Oracle Cloud & Seed R2 | ✅ Done (Systemd Active) |
| **Waves C–D** — Swift Background Service & UI Hydration | Planned |
| **Waves E–H** — Design Alignment & Ship Prep | Planned |

Full details in [`ROADMAP.MD`](ROADMAP.MD).

---

## 🚀 Getting Started

### Prerequisites

* Node.js (v18+)
* Yarn or npm
* Ruby / CocoaPods (for iOS Prebuilds)
* Xcode 15+ (for native Swift service and Nitro Module linkage)
* MapTiler API Key (for base tiles)

### Installation

1. **Clone the repository:**
   ```bash
   git clone https://github.com/walshkang/derivee.git
   cd derivee
   ```

2. **Install dependencies:**
   ```bash
   npm install
   ```

3. **Configure environment:**
   Create a `.env` file in the root directory:
   ```env
   EXPO_PUBLIC_MAP_API_KEY=your_maptiler_api_key_here
   ```

4. **Generate Nitro bindings:**
   ```bash
   npx nitro-codegen
   ```
   This generates the C++/Swift translation layers in `nitrogen/generated/`. The generated iOS sources must then be linked manually via the Xcode GUI (see [`xcode_linkage_instructions.md`](xcode_linkage_instructions.md)).

5. **Run Expo Prebuild:**
   ```bash
   npx expo prebuild --clean
   ```

6. **Open Xcode workspace for native linkage:**
   ```
   open ios/Derivee.xcworkspace
   ```
   > ⚠️ Always open `.xcworkspace`, never the bare `.xcodeproj`. Follow the Xcode linkage instructions to import Nitrogen sources, configure the bridging header, and add the Swift background service.

7. **Start the Metro Bundler:**
   ```bash
   npx expo start
   ```

8. **Run on device:**
   Press `i` to open the iOS simulator, or build directly to a tethered iPhone (recommended for accurate background GPS and MapLibre fog rendering performance — per project rules, never trust the Simulator for MapLibre performance).

---

## 📁 Repository Structure

```
derivee/
├── app/                    # Expo Router screens
│   ├── _layout.tsx         # Root navigation layout
│   ├── index.tsx           # Screen 0: Onboarding Gate / Splash
│   ├── map.tsx             # Screen 1: Ambient Map (core loop)
│   ├── stats.tsx           # Screen 3: Exploration Stats & GPX Upload
│   ├── settings.tsx        # Screen 4: Settings & Data Management
│   └── city/               # City-specific routes
├── src/                    # Core application logic
│   ├── components/         # Reusable UI components (TransitBottomSheet, etc.)
│   ├── constants/          # App-wide constants and config values
│   ├── db/                 # Database initialization, migrations, queries
│   ├── hooks/              # React hooks (location, app state, etc.)
│   ├── native/             # Nitro module TypeScript specs & bridge API
│   ├── proto/              # GTFS-RT Protobuf definitions & generated decoders
│   ├── services/           # Location, transit, and sync services
│   ├── store/              # Zustand state management (exploration, transit)
│   └── utils/              # H3 utilities, geo math, helpers
├── ios/                    # Native workspace (manually managed for Nitro/H3/Swift)
├── android/                # Android native project (CNG-managed)
├── nitrogen/               # Generated Nitro Module C++/Swift translation layers
├── modules/                # Local Expo Modules (expo-background-assertion)
├── observer/               # Go daemon for GTFS-RT ingestion & historical sparklines
├── transit-web/            # Standalone transit timetable web app (W11 spinoff)
├── archive/                # Shipped wave documentation archive
├── docs/                   # Architecture blueprints & design language specs
│   ├── architecture.md     # Full technical specification (Sleepy Hermes, SQLite, Nitro)
│   └── design.md           # UI blueprint, screen specs, visual identity
├── scripts/                # Utility & data generation scripts
├── __tests__/              # Unit tests
├── .maestro/               # E2E test flows (Maestro)
├── nitro.json              # Nitro Module configuration
├── ROADMAP.MD              # Development roadmap & wave tracking
├── AGENTS.MD               # AI agent operational rules & constraints
└── xcode_linkage_instructions.md  # Step-by-step Xcode GUI linkage guide
```

---

## 📡 The Observer Daemon Operations Guide

The Observer is a standalone persistent Go (Golang) daemon hosted on an Oracle Cloud VPS (`150.136.171.50`). It polls MTA GTFS-RT Protobuf feeds for both Subways and Buses every 3 minutes. To avoid memory bloat, it securely maintains a localized SQLite database of the massive static GTFS schedules (`static_gtfs.sqlite`). The daemon processes historical arrival reliability against these static schedules, compresses the daily stats table into a SQLite database using Zstandard (`transit_delta.sqlite.zst`), and uploads it to Cloudflare R2 (`fog-of-transit` bucket).

### 1. Connecting to the VPS

Run in your local Mac terminal:
```bash
ssh -i "~/.ssh/observer-vps.key" ubuntu@150.136.171.50
```

---

### 2. Checking Current Running Status

Once connected to the VPS:

* **Check if process is active:**
  ```bash
  ps aux | grep observer_daemon
  # OR via systemd
  sudo systemctl status observer
  ```

* **Check recent log activity:**
  ```bash
  tail -n 20 ~/observer/observer.log
  ```

* **Stream live ingestion logs:**
  ```bash
  tail -f ~/observer/observer.log
  ```

---

### 3. First-Time Setup & Build Instructions

If setting up on a clean/reset VPS or rebuilding after code updates:

1. **Configure Swap Space (1GB)** *(prevents GCC/Go OOM crashes during CGO build)*:
   ```bash
   sudo fallocate -l 1G /swapfile
   sudo chmod 600 /swapfile
   sudo mkswap /swapfile
   sudo swapon /swapfile
   echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
   ```

2. **Install Build Dependencies for SQLite CGO**:
   ```bash
   sudo apt update && sudo apt install -y build-essential
   ```

3. **Navigate & Configure Environment**:
   ```bash
   cd ~/observer
   cat << 'EOF' > .env
   MTA_BUS_API_KEY=your_mta_bus_api_key_here
   AWS_ACCESS_KEY_ID=your_r2_access_key_here
   AWS_SECRET_ACCESS_KEY=your_r2_secret_key_here
   AWS_REGION=auto
   R2_BUCKET_NAME=fog-of-transit
   R2_ENDPOINT=https://your_account_id.r2.cloudflarestorage.com
   EOF
   ```

4. **Tidy Dependencies & Build**:
   ```bash
   go mod tidy
   go build -v -o observer_daemon ./cmd/observer
   ```

---

### 4. Running & Auto-Restart Management

* **Test Execution (Foreground)**:
  ```bash
  ./observer_daemon
  ```

* **Run in Background (Simple `nohup`)**:
  ```bash
  nohup ./observer_daemon > observer.log 2>&1 &
  ```

* **Production Auto-Start via Systemd (Recommended)**:
  Create the service config:
  ```bash
  sudo tee /etc/systemd/system/observer.service > /dev/null << 'EOF'
  [Unit]
  Description=The Observer GTFS Daemon
  After=network.target

  [Service]
  Type=simple
  User=ubuntu
  WorkingDirectory=/home/ubuntu/observer
  ExecStart=/home/ubuntu/observer/observer_daemon
  Restart=always
  RestartSec=10
  StandardOutput=file:/home/ubuntu/observer/observer.log
  StandardError=file:/home/ubuntu/observer/observer.log

  [Install]
  WantedBy=multi-user.target
  EOF
  ```

  Enable and start:
  ```bash
  sudo systemctl daemon-reload
  sudo systemctl enable observer
  sudo systemctl start observer
  ```

---

## 📜 License

*Proprietary - Do not distribute without permission.*