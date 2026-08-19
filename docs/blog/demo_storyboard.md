# Dérivée Demo Video Storyboard & Script
## High-Production Architecture & Performance Showcase

- **Target Duration:** 60–75 seconds
- **Format:** 9:16 Vertical Video (iPhone 17 Pro, 1206x2622 / 1080x1920) or 16:9 Landscape with Telemetry Sidebar
- **Audio Tone:** Atmospheric lo-fi / ambient modular synth with crisp UI haptic sound design
- **Production Concept:** High-aesthetic native iOS showcase paired with real-time systems telemetry HUD overlays to demonstrate low-level spatial engineering, sub-millisecond database concurrency, and 120Hz GPU pipelines.

---

## Scene Breakdown & Telemetry Direction

### Scene 1: Cold Start & Ambient Fog Cartography (00:00 – 00:10)
- **Visual:** Clean app cold start. MapLibre Native renders immediately in Night Mode (Midnight Slate `#12121A` basemap with deep OLED black fog layer over NYC). Full MTA subway track casings are subtly visible beneath the fog mask.
- **Action:** Smooth pan across Lower Manhattan. The Electric Amber (`#FFB300`) live GPS puck pulses with subtle radial breathing.
- **HUD Metric Badges (Top-Left Overlay):**
  - `[⚡ Cold Start: <320ms]`
  - `[📍 GPS Gate: Rayleigh Bound ≤25m]`
- **On-Screen Text Overlay:** *"Unlearn the Commute. Ambient Fog of War for NYC."*
- **Voiceover / Captions:** *"Every transit app rushes you through the city. Dérivée is built for the drift. The entire metropolis begins shrouded in an ambient Fog of War."*

---

### Scene 2: Live Walk & 120Hz Spatial Polygon Dissolution (00:10 – 00:24)
- **Visual:** Live GPX walk simulation active along 8th Avenue towards 14th Street.
- **Action:** As the user location puck traverses the avenue, Res-11 hexagonal apertures dissolve cleanly from the fog mask (300ms cubic bezier transition). Contiguous cells union seamlessly into smooth macro-polygons without interior seam artifacts.
- **Detail:** Street names, building footprints, and ghost beacons fade in exclusively within the 200m Active Vicinity Bubble.
- **HUD Metric Badges (Top-Left Overlay):**
  - `[📐 C/H3 Polygon Dissolution: <1.5ms MainActor Commit]`
  - `[🚀 ProMotion: 120 FPS Locked]`
  - `[🛑 Vertex Reduction: -85% vs Naive Triangulation]`
- **On-Screen Text Overlay:** *"120Hz Spatial Unioning • Offline C/H3 Res-11 ($O(N \log N)$)"*
- **Voiceover / Captions:** *"As you walk, your path uncovers Resolution 11 H3 hexagons in real time. Contiguous cells dissolve off-thread into single macro-polygons, keeping MapLibre GPU rendering locked at 120Hz."*

---

### Scene 3: Subway Transit Reveal & Headway Analytics (00:24 – 00:38)
- **Visual:** User approaches the 14th St / 8th Ave station complex. Glowing diamond Ghost POI beacon resolves into an interactive station disc.
- **Action:** Tap the station marker. Screen 2 (`TransitRevealSheet`) springs up over the bottom third of the map (`.ultraThinMaterial`). Live A/C/E and L train countdowns display alongside a 7-day historical headway sparkline. Behind the sheet, the full L-line route lights up across the map in high-contrast dual-layer stroke.
- **HUD Metric Badges (Top-Left Overlay):**
  - `[💾 Local SQLite WAL Read: <8ms (QoS: .userInitiated)]`
  - `[📡 Protobuf GTFS-RT Parse: Direct Stream]`
  - `[🔒 Concurrency: Zero Main-Thread Lock]`
- **On-Screen Text Overlay:** *"Sub-10ms Local SQLite • Direct Protobuf GTFS-RT"*
- **Voiceover / Captions:** *"Within 200 meters, transit nodes reveal themselves through the fog. Tapping any station queries local SQLite headways and live GTFS-RT Protobuf streams in under 10 milliseconds."*

---

### Scene 4: Nearby Buses Lens & Exploration Journal (00:38 – 00:52)
- **Visual:** Dismiss transit sheet (ephemeral route dissolves smoothly in 200ms).
- **Action:** Tap the floating frosted-glass `NearbyBusesCapsule` in the bottom-left corner to reveal live M14A-SBS arrival countdowns within 400m. Then tap the top-right Aperture FAB to navigate to Screen 3 (`ExplorationJournalView`).
- **Detail:** Smoothly scroll through the Neighborhood Progress Leaderboard (West Village, Chelsea, Greenwich Village completion bars and unlocked hex statistics).
- **HUD Metric Badges (Top-Left Overlay):**
  - `[🔋 Background Engine: Zero Continuous Polling]`
  - `[📊 Spatial Bounding Query: R-Tree H3 Filter]`
- **On-Screen Text Overlay:** *"Spatial SQLite Exploration Journal • Zero Battery Drain"*
- **Voiceover / Captions:** *"Nearby bus lenses provide immediate arrival context without continuous background battery drain. The Exploration Journal tracks discovery progress across NYC neighborhoods and boroughs."*

---

### Scene 5: Solar Light Environmental Shift & Shader Tuning (00:52 – 01:04)
- **Visual:** In Settings, toggle between Day Mode (Parchment White `#F9F9F6`) and OLED Midnight Slate (`#12121A`).
- **Action:** Adjust the Fog Opacity slider. The map shader updates instantaneously at 120Hz with zero frame drop or polygon recomputation.
- **HUD Metric Badges (Top-Left Overlay):**
  - `[☀️ Day/Night: Solar Ephemeris Calculation]`
  - `[🎨 Shader Uniform: Zero Geometry Rebuild]`
- **On-Screen Text Overlay:** *"Dynamic Environmental Shift • Native Swift & SwiftUI"*
- **Voiceover / Captions:** *"The interface shifts dynamically between Day Parchment and Midnight Slate based on local solar ephemeris, while shader updates adjust opacity instantly without geometry recomputation."*

---

### Scene 6: Outro & Architectural Summary (01:04 – 01:14)
- **Visual:** Zoom out to show the unlocked pathways cutting through the dark NYC fog across the entire skyline.
- **On-Screen Text Overlay:**
  ```
  Dérivée — Pure Native iOS (iOS 17+)
  Built with the 3-Pillar Autonomous Agent Harness
  github.com/walshkang/derivee
  ```
- **Voiceover / Captions:** *"Dérivée: Unlearn your commute. Built purely in native Swift with autonomous AI engineering harnesses. Open source on GitHub."*
