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

Built as a **pure native iOS application** under the **Sleepy Hermes** paradigm (originally named during the React Native era, now fully realized in Swift). The project uses `xcodegen` for a clean, reproducible Xcode workspace, entirely bypassing CocoaPods and legacy React Native bridging constraints.

### Core Stack

| Technology | Role |
| --- | --- |
| **Swift (iOS 17+)** | Core language. Takes full advantage of modern Swift concurrency (`async/await`, `Task`). |
| **SwiftUI** | UI framework. Drives the declarative, reactive interface. |
| **MapLibre Native** | Map engine — vector tiles, custom raster layers, Data-Driven Styling. |
| **H3 (swift-h3)** | Native Swift Package wrapper for the Uber H3 spatial indexing C-library. Used for `latLngToCell` conversions at Resolution 11. |
| **GRDB.swift** | SQLite toolkit for Swift. Runs in WAL mode with `WITHOUT ROWID` optimizations for microsecond-fast spatial queries and highly concurrent background writes. |
| **CLLocationUpdate** | iOS 17's modern background location stream, kept alive by `CLBackgroundActivitySession`. |

### Architectural Highlights

* **Pure Native Background Engine:** All background location processing runs in pure native Swift using `CLLocationUpdate.liveUpdates()` in a detached `Task`. This prevents iOS watchdog terminations and dramatically reduces battery drain.
* **Concurrent SQLite (GRDB):** The database operates in WAL mode using `DatabasePool`, enabling simultaneous background writes (logging hexes) and foreground reads (UI rendering) with zero lock contention.
* **Reactive Observation:** The SwiftUI interface binds directly to the database via `@Observable` stores and GRDB's `ValueObservation`, ensuring the UI instantaneously reflects newly discovered territory.
* **Battery & Drift Optimization:** CPU remains asleep until physical movement occurs. An implied speed filter ($\Delta d / \Delta t \leq 12$ m/s) aggressively discards urban canyon GPS multipath noise before it touches the H3 conversion step.
* **Clean Project Generation:** The Xcode project is generated deterministically via `xcodegen`, eliminating merge conflicts in `.pbxproj` files and providing seamless Swift Package Manager integration.

---

## 📍 Current Status

The project has fully completed the **Pure Native iOS Migration**. All legacy JavaScript/React Native dependencies have been removed in favor of a clean Swift/SwiftUI architecture (`DeriveeNative/`).

| Phase | Status |
| --- | --- |
| **Legacy React Native Iterations** | ✅ Archived |
| **Native Migration: H3 & Project Setup** | ✅ Done |
| **Native Migration: GRDB Database Layer** | ✅ Done |
| **Native Migration: Ambient Tracking Engine** | ✅ Done |
| **SwiftUI Rendering & Polish** | Planned |

Full details in [`ROADMAP.MD`](ROADMAP.MD).

---

## 🚀 Getting Started

### Prerequisites

* macOS with Xcode 15+
* Homebrew (to install `xcodegen`)
* MapTiler API Key (for base tiles)

### Installation

1. **Clone the repository:**
   ```bash
   git clone https://github.com/walshkang/derivee.git
   cd derivee
   ```

2. **Install XcodeGen:**
   ```bash
   brew install xcodegen
   ```

3. **Generate the Xcode Project:**
   ```bash
   cd DeriveeNative
   xcodegen generate
   ```

4. **Open the Project:**
   ```bash
   open Derivee.xcodeproj
   ```
   > ⚠️ Xcode will automatically resolve the Swift Package Manager dependencies (H3 and GRDB).

5. **Run on device:**
   Select your physical iPhone target in Xcode and press `Cmd + R` to build and run. (Recommended for accurate background GPS and MapLibre fog rendering performance).

---

## 📁 Repository Structure

```
derivee/
├── DeriveeNative/          # Pure Native iOS Swift Application
│   ├── Derivee/            # Application Source Code
│   │   ├── AmbientTrackingEngine.swift # Background location tracking
│   │   ├── SpatialDatabaseManager.swift# GRDB SQLite manager
│   │   ├── SpatialStore.swift          # Observable UI store
│   │   ├── ContentView.swift           # Root SwiftUI view
│   │   └── Info.plist                  # Permissions & Config
│   ├── project.yml         # XcodeGen configuration
│   └── Derivee.xcodeproj   # Generated Xcode Project
├── observer/               # Go daemon for GTFS-RT ingestion & historical sparklines
├── transit-web/            # Standalone transit timetable web app (W11 spinoff)
├── archive/                # Shipped wave documentation archive
├── docs/                   # Architecture blueprints & design language specs
│   ├── architecture.md     # Full technical specification
│   └── design.md           # UI blueprint, screen specs, visual identity
├── ROADMAP.MD              # Development roadmap & wave tracking
└── AGENTS.MD               # AI agent operational rules & constraints
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