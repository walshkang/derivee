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

## 📜 License

*Proprietary - Do not distribute without permission.*