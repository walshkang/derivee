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
| **9** | **W9-OBSERVER** | **Headless Observer Tool & CDN Handoff** | **M** | ✅ Done |
| **10** | **W10-HISTORIAN** | **GPX/HealthKit Import & Macro-Reveal Animation** | **L** | ✅ Done |
| **11** | **W11-TIMETABLE** | **Standalone Transit App (Web/Spinoff) & Headway Matrix** | **L** | ✅ Done |
| **11.5** | **W11.5-MVP-POLISH** | **Light Mode UI Refactor & MVP Launch** | **S** | ✅ Done |
| **12** | **W12-BOSTON** | **Multi-City Expansion: MBTA (Post-MVP)** | **L** | Planned |
| **13** | **W13-FOG-TIERS** | **3-Tier Fog State & Reference Counting (Post-MVP)** | **M** | ✅ Done |
| **13** | **W13-FOG-STYLE** | **MapLibre Dual-Layer & Temporal Interpolation (Post-MVP)** | **S** | ✅ Done |

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

## Wave 9 — The Observer Backend (✅ Completed)
*Task W9-OBSERVER shipped. Prompt archived in `archive/shipped-waves-archive.md`.*

---

## Wave 10 — The Historian Flow (✅ Completed)
*Task W10-HISTORIAN shipped. Prompt archived in `archive/shipped-waves-archive.md`.*

---

## Wave 11 — Standalone Transit Navigation Expansion (✅ Completed)
*Task W11-TIMETABLE shipped. Prompt archived in `archive/shipped-waves-archive.md`.*

---

## Wave 11.5 — MVP Launch & UI Polish (✅ Completed)
*Task W11.5-MVP-POLISH shipped. UI converted to Light Mode default.*

---

## Wave 12 — Multi-City Expansion: Boston (W12-BOSTON) [Post-MVP]

* **The Goal:** Prove the scalability of the architecture by expanding transit coverage to the MBTA system.
* **Agent Directives:**
  * **W12-OBSERVER:** Refactor the Go daemon to support regional configuration profiles. It will poll the unified MBTA Protobuf endpoints (`TripUpdates.pb`, `Alerts.pb`, `VehiclePositions.pb`) alongside the NYC feeds, and normalize them into the Zstandard SQLite format.
  * **W12-APP:** Implement automatic region detection in the Expo app based on the user's GPS bounding box (querying the Boston SQLite file if the user's H3 index falls within Massachusetts).
  * **W12-UI:** Expand the Transit bottom-sheet to visually support MBTA-specific experimental fields, such as "Crowding / Occupancy" indicators and "Prediction Uncertainty" warnings.

---

## Wave 13 — Advanced MapLibre Rendering & Fog Enhancements (✅ Completed)
*Tasks W13-FOG-TIERS & W13-FOG-STYLE shipped. Prompts archived in `archive/shipped-waves-archive.md`.*