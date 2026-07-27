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
| **8.1** | **W8.1-TRANSIT-REFACTOR** | **Dual-Format Transit Parser (JSON + PB) & API Keys** | **M** | ✅ Done |
| **9** | **W9-OBSERVER** | **Headless Observer Tool & CDN Handoff** | **M** | Planned |
| **10** | **W10-HISTORIAN** | **GPX/HealthKit Import & Macro-Reveal Animation** | **L** | Planned |
| **11** | **W11-SPARKLINE** | **Standalone Transit App (Web/Spinoff)** | **L** | Planned |
| **12** | **W12-BOSTON** | **Multi-City Expansion: MBTA** | **L** | Planned |

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

## Wave 8.1 — Transit Parser Refactor (✅ Completed)
*Task W8.1-TRANSIT-REFACTOR shipped. Prompt archived in `archive/shipped-waves-archive.md`.*

---

## Wave 9 — The Observer Backend (W9-OBSERVER)

* **The Goal:** Build the "make it yourself, and make it well" persistent backend architecture for historical transit reliability.
* **Agent Directives:**
  * This task occurs *outside* the Expo app. The agent must build a standalone Go (Golang) persistent daemon hosted on a low-cost VPS.
  * The daemon must poll both the fragmented **MTA GTFS-RT Protobuf feeds** (for subways) and the **MTA Bus Time SIRI API (JSON)** (for buses) every 3 minutes, acting as a unifier to normalize both real-time data streams.
  * When parsing Service Alerts, the daemon must strictly adhere to the MTA's `informed_entity` format: iterating through separate station-level entities and applying `direction_id` filters.
  * Calculate rolling 7-day averages and reliability percentages to assemble the historical sparkline data in memory.
  * Output a single, unified Zstandard-compressed SQLite delta database (`transit_delta.sqlite.zst`) and push it to Cloudflare R2 (CDN).
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
  * Support live navigation and future planned routes based on the fusion of live GTFS/SIRI data and historical sparkline patterns.
  * Ensure the frontend parser is capable of handling both binary Protobufs (subways) and JSON (buses), and correctly displays direction-specific service alerts (using MTA's `direction_id` structure).

---

## Wave 12 — Multi-City Expansion: Boston (W12-BOSTON)

* **The Goal:** Prove the scalability of the architecture by expanding transit coverage to the MBTA system.
* **Agent Directives:**
  * **W12-OBSERVER:** Refactor the Go daemon to support regional configuration profiles. It will poll the unified MBTA Protobuf endpoints (`TripUpdates.pb`, `Alerts.pb`, `VehiclePositions.pb`) alongside the NYC feeds, and normalize them into the Zstandard SQLite format.
  * **W12-APP:** Implement automatic region detection in the Expo app based on the user's GPS bounding box (querying the Boston SQLite file if the user's H3 index falls within Massachusetts).
  * **W12-UI:** Expand the Transit bottom-sheet to visually support MBTA-specific experimental fields, such as "Crowding / Occupancy" indicators and "Prediction Uncertainty" warnings.