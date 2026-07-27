# Fog of Wburg — Unified Roadmap

This document is the single source of truth for all planned development waves. 

> [!IMPORTANT]
> **Agent Roadmap Maintenance Protocol**:
> 1. When completing a task, update its status in the **Master Status Table** from `Planned` to `✅ Done`.
> 2. Move the completed task's detailed prompt out of this file and append it to `archive/shipped-waves-archive.md`.
> 3. Keep this file lean to minimize context bloat.

## Master Status Table

| Wave | Task ID | Title | Size | Status |
|:---:|:---:|:---|:---:|:---:|
| **1** | **W1-INIT** | **Expo Scaffold & Zustand State** | **S** | ✅ Done |
| **1** | **W1-NAV** | **Navigation Shell & Splash Screen** | **M** | ✅ Done |
| **2** | **W2-DB** | **op-sqlite JSI Initialization & WAL Mode** | **M** | ✅ Done |
| **2** | **W2-H3** | **h3-js Core Logic & Grid Conversions** | **S** | ✅ Done |
| **3** | **W3-MAP** | **MapLibre Engine & 3D Terrain Base** | **L** | ✅ Done |
| **3** | **W3-FOG** | **50km Bounding Box & Inverted Polygon** | **L** | ✅ Done |
| **4** | **W4-TRACK** | **expo-location Background Service & Batching** | **M** | ✅ Done |
| **4** | **W4-DRIFT** | **Implied Speed Filter & Geometry Unioning** | **M** | ✅ Done |
| **5** | **W5-POI** | **Gamification & POI Integration** | **M** | ✅ Done |
| **6** | **W6-POLISH** | **Performance & App Store Launch** | **S** | ✅ Done |
| **7** | **W7-AMBIENT** | **Vicinity Bubble & Ghost POI Logic** | **M** | ✅ Done |
| **8** | **W8-TRANSIT** | **Live GTFS-RT Decoding & Transit Bottom-Sheet** | **L** | ✅ Done |
| **9** | **W9-OBSERVER** | **Headless Observer Tool & CDN Handoff** | **M** | Planned |
| **10** | **W10-HISTORIAN** | **GPX/HealthKit Import & Macro-Reveal Animation** | **L** | Planned |
| **11** | **W11-SPARKLINE** | **Standalone Transit App (Web/Spinoff)** | **L** | Planned |

---

## Wave 1 — Foundation & UI Shell (✅ Completed)
*Tasks W1-INIT & W1-NAV shipped. Prompts archived in `archive/shipped-waves-archive.md`.*

---

## Wave 2 — Core DB & Spatial Engine (✅ Completed)
*Tasks W2-DB & W2-H3 shipped. Prompts archived in `archive/shipped-waves-archive.md`.*

---

## Wave 3 — The Fog Rendering Engine (✅ Completed)
*Tasks W3-MAP & W3-FOG shipped. Prompts archived in `archive/shipped-waves-archive.md`.*

---

## Wave 4 — Background Location & Anti-Drift (✅ Completed)
*Tasks W4-TRACK & W4-DRIFT shipped. Prompts archived in `archive/shipped-waves-archive.md`.*

---

## Wave 5 — Gamification (✅ Completed)
*Task W5-POI shipped. Prompt archived in `archive/shipped-waves-archive.md`.*

---

## Wave 6 — Polish & Launch (✅ Completed)
*Task W6-POLISH shipped. Prompt archived in `archive/shipped-waves-archive.md`.*

---

## Wave 7 — The Ambient UI (✅ Completed)
*Task W7-AMBIENT shipped. Prompt archived in `archive/shipped-waves-archive.md`.*

---

## Wave 8 — Raw Transit Pipeline (✅ Completed)
*Task W8-TRANSIT shipped. Prompt archived in `archive/shipped-waves-archive.md`.*

---

## Wave 9 — The Observer Backend (W9-OBSERVER)

* **The Goal:** Build the "make it yourself, and make it well" persistent backend architecture for historical transit reliability.
* **Agent Directives:**
  * This task occurs *outside* the Expo app. The agent must build a standalone Go (Golang) persistent daemon hosted on a low-cost VPS to ingest raw GTFS-RT Protobuf feeds every 3 minutes.
  * Calculate rolling 7-day averages and reliability percentages to assemble the historical sparkline data in memory.
  * Output a Zstandard-compressed SQLite delta database (`transit_delta.sqlite.zst`) and push it to Cloudflare R2 (CDN).
  * Update the Expo app to silently fetch and synchronously attach this SQLite delta file every morning via `@op-engineering/op-sqlite`.

---

## Wave 10 — The Historian Flow (W10-HISTORIAN)

* **The Goal:** Solve the "cold start" problem for new users.
* **Agent Directives:**
  * Build the UI in the Settings/Archive screen to accept passive uploads from Apple HealthKit, Strava, or raw GPX/FIT files.
  * Build the massive visual payoff: an animation that instantly vanishes huge swaths of the fog across the city once the historical data is processed into H3 hexes.

---

## Wave 11 — Standalone Transit Navigation Expansion (W11-SPARKLINE)

* **The Goal:** Leverage the historical sparkline data and live GTFS pipeline to build a lightweight, dedicated transit tracking and navigation app (potentially web-based).
* **Agent Directives:**
  * Build a spinoff/standalone interface (web browser or lightweight companion app) dedicated purely to transit routing, reliability, and tracking.
  * Utilize the Go Observer's historical sparkline data to provide predictive "historical reliability" scores for routes.
  * Implement user alerts/notifications for upcoming trains and buses (e.g., "10 min away").
  * Support live navigation and future planned routes based on the fusion of live GTFS data and historical sparkline patterns.