# Fog of Wburg: The Ambient Explorer

> A mindful, offline-first iOS application that transforms your daily commute and neighborhood walks into an ambient journey of discovery.

**Fog of Wburg** is a harness for real life. Inspired by the progressive disclosure of *Zelda: Breath of the Wild* and the utility of *Google Maps*, it gamifies real-world exploration using an H3-powered "fog of war." However, it abandons the aggressive completionism of traditional mapping games. Instead, it offers a calming, translucent environment that teases discovery and provides commuter-grade transit data *only* when you explicitly ask for it.

---

## 🌫 Core Experience

* **The Volumetric Fog:** Unexplored areas are covered by a soft, diffuse, translucent cloud layer. Underneath, major geographic arteries (coastlines, bridges, arterial roads) are faintly visible as nameless vectors, subconsciously luring you to explore.
* **The Vicinity Bubble:** The app heavily utilizes progressive disclosure. Detailed geospatial data (street names, transit stops, bike docks) is only rendered within a dynamic ~200-meter physical radius of your live location.
* **Pristine History:** When you pan the camera to view an area you cleared weeks ago, you see only clean, beautiful satellite terrain. The map gets out of your way.
* **Ghost POIs:** Points of interest and transit nodes do not permanently clutter the map with pins. Once an area is cleared, they become invisible. They are only revealed if you are physically standing in that hex and tap your location to pull up a minimalist data sheet.
* **The Archive (Soft Completionism):** While the main map abandons gamified HUDs, a dedicated profile screen tracks your macro-level progress (e.g., "Williamsburg: 14% Cleared") and houses a beautiful grid of your discovered Ghost POIs, satisfying the completionist itch without the anxiety.

## 🚇 Commuter-Grade Transit (Raw GTFS)

Fog of Wburg features a Naver Maps-style transit integration built on a strictly "make it yourself, and make it well" philosophy, bypassing third-party API limits.

1. **Live Protocol Buffers:** Tapping a transit node in your Vicinity Bubble decodes the transit authority's binary GTFS-RT feeds on the fly, delivering crisp, real-time arrival countdowns and dynamic vector route previews.
2. **The Observer Pipeline:** Historical reliability (average headways, arrival sparklines) is powered by a custom, standalone Go (Golang) daemon hosted on a lightweight VPS. This persistent pipeline crunches raw GTFS data 24/7, generates a Zstandard-compressed SQLite delta database (`.sqlite.zst`), and pushes it to Cloudflare R2.
3. **Offline-First Sync:** The mobile app silently fetches this compressed SQLite file every morning, allowing instantaneous, offline rendering of historical charts directly from native memory using `@op-engineering/op-sqlite`'s `ATTACH DATABASE` JSI driver.

---

## 🛠 Tech Stack & Architecture

Built with an AI-driven "vibe coding" approach, relying strictly on Expo Prebuild (Continuous Native Generation) to completely eliminate manual Xcode management.

* **Framework:** React Native + Expo (Managed Workflow)
* **Map Engine:** `@rnmapbox/maps` (MapLibre vector tiles, 3D terrain, custom raster layers)
* **Spatial Indexing:** Uber's H3 Grid System via `h3-js` (Resolution 11)
* **Local Database:** `@op-engineering/op-sqlite` (Blazing fast C++ synchronous SQLite for instant spatial querying)
* **Location Services:** `expo-location` (Foreground/Background distance-interval tracking)
* **Transit Decoding:** `protobufjs` + `gtfs-realtime-bindings`

**Technical Highlights:**
* **Synchronous Rendering:** Utilizes MapLibre's JSI bindings (`withSynchronousUpdate`) and background geometry unioning (`h3.cellsToMultiPolygon`) to bypass the React Native bridge, rendering tens of thousands of hexagonal holes at 60fps.
* **Battery & Drift Optimization:** CPU remains asleep until physical movement occurs via hardware-level distance intervals (`deferredUpdatesDistance`). An implied speed filter (< 12 m/s) aggressively discards urban canyon GPS multipath noise.

## 🚀 Getting Started

### Prerequisites

* Node.js (v18+)
* Yarn or npm
* Expo CLI (`npm install -g expo-cli`)
* Ruby / Cocoapods (for iOS Prebuilds)
* MapTiler or Mapbox API Key (for base tiles)

### Installation

1. **Clone the repository:**
```bash
git clone https://github.com/your-username/fog-of-wburg.git
cd fog-of-wburg
```

2. **Install dependencies:**
```bash
yarn install
```

3. **Configure Environment:**
Create a `.env` file in the root directory and add your MapLibre-compatible tile provider key:
```env
EXPO_PUBLIC_MAP_API_KEY=your_api_key_here
```

4. **Run Expo Prebuild (Crucial step for native modules):**
```bash
npx expo prebuild --clean
```

5. **Start the Metro Bundler:**
```bash
npx expo start
```

6. **Run on Device/Simulator:**
Press `i` to open the iOS simulator, or build directly to a tethered iPhone (recommended for accurate background GPS and MapLibre testing).

---

## 📁 Repository Structure (Upcoming)

* `/app` - The Expo React Native mobile application.
* `/components` - UI overlays, the Vicinity Bubble elements, bottom-sheets.
* `/core` - The H3 engine, location tracking hooks, MapLibre layer stack.
* `/db` - SQLite schema, queries, and spatial point-in-polygon checks.
* `/observer` - The standalone Go (Golang) persistent daemon for GTFS-RT ingestion and historical sparkline generation.
* `/docs` - Architecture blueprints, design language specs, and feature roadmaps.

---

## 📡 The Observer Daemon Operations Guide

The Observer is a standalone persistent Go (Golang) daemon hosted on an Oracle Cloud VPS (`150.136.171.50`). It polls MTA GTFS-RT Protobuf feeds and MTA Bus Time SIRI endpoints every 3 minutes, processes historical arrival reliability, compresses a SQLite database with Zstandard (`transit_delta.sqlite.zst`), and uploads it to Cloudflare R2 (`fog-of-transit` bucket).

### 1. Connecting to the VPS

Run in your local Mac terminal:
```bash
ssh -i "/Users/walsh.kang/Library/CloudStorage/GoogleDrive-wkang1281@gmail.com/My Drive/000. Notes/ssh-key-2026-07-27.key" ubuntu@150.136.171.50
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
   MTA_BUS_API_KEY=your_bus_api_key_here
   AWS_ACCESS_KEY_ID=37d7e340802ca1d87f284a56e634e0d3
   AWS_SECRET_ACCESS_KEY=9cf72ffebc4d4efcad7dc88b8966ce51969e9daaac4986a7aa37eb66be461f53
   AWS_REGION=auto
   R2_BUCKET_NAME=fog-of-transit
   R2_ENDPOINT=https://8de9ca6847d3179692f9b59ff2b46b8d.r2.cloudflarestorage.com
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