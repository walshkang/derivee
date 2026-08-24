# Dérivée Demo Video Recording Script & Storyboard
## Manual Video Recording Guide (5-Hex Automated Walk + Manual UI Exploration)

- **Target Duration:** ~65–75 seconds
- **Format:** 9:16 Vertical Video (iPhone 17e) or 16:9 Landscape
- **Workflow:** The GPX walk runs automatically for ~18 seconds (5 hexes), then holds position so you can perform all UI interactions at your own pace.

---

## Storyboard & Action Script

```
+---------------------------------------------------------------------------------------------------------+
| 00:00 - 00:05 | Scene 1: Cold Start & Ambient Fog Cartography (Day Mode, sub-fog transit line casings)   |
| 00:05 - 00:23 | Scene 2: 18s Automated Walk (5 Res-11 Hex Unlocks & 120Hz GPU Macro-Polygon Dissolution)|
| 00:23 - 00:43 | Scene 3: Tap 59th St Hub -> Multi-Route Badges, Live Arrivals & Full Timetable Matrix   |
| 00:43 - 00:54 | Scene 4: Nearby Buses Lens & Exploration Stats (Neighborhoods & Milestone Cards)        |
| 00:54 - 01:05 | Scene 5: Settings -> Instant GPU Basemap Crossfade & Fragment Shader Fog Opacity Slider |
| 01:05 - 01:15 | Scene 6: Outro -> Zoom Out to Clamped NYC Metropolitan Skyline & Finish                 |
+---------------------------------------------------------------------------------------------------------+
```

---

### Scene 1: Cold Start & Ambient Fog (00:00 – 00:05)
- **Visual:** Dérivée opens cleanly in Day Mode (Parchment White `#F9F9F6`) centered at Columbus Circle. Dark OLED fog blankets Manhattan with subtle MTA subway line casings visible beneath the fog layer as ambient orienting sub-context.
- **Your Action on Screen:** Hold still or do a slight micro-pan across Columbus Circle / Central Park South.
- **Spoken Voiceover / Subtitle:**
  > *"Every transit app rushes you through the city. Dérivée is built for the drift. The entire metropolis begins shrouded in an ambient Fog of War."*

---

### Scene 2: Live Walk & 120Hz Spatial Polygon Dissolution (00:05 – 00:23)
- **Visual:** The Amber GPS puck moves north along Central Park West / 8th Ave.
- **Automatic Automation:** The script feeds 15 waypoints (~260m across 5 H3 Res-11 hexes).
- **Your Action on Screen:** Keep your eyes / pointer relaxed as the camera follows the GPS puck. Watch the Res-11 hexagonal apertures dissolve cleanly from the fog mask and union into single smooth CCW polygon cutouts via `cellsToLinkedMultiPolygon`.
- **Spoken Voiceover / Subtitle:**
  > *"As you walk, your path uncovers Resolution 11 H3 hexagons in real time. Contiguous cells dissolve off-thread into unified polygons, keeping MapLibre GPU rendering locked at 120Hz."*

---

### Scene 3: Subway Transit Hub Reveal & Timetable Matrix (00:23 – 00:43)
- **Visual:** The walk finishes and holds at the 5th hex destination.
- **Your Action on Screen:**
  1. Tap the **59th St – Columbus Circle** (or nearest) subway station disc on the map. The 44pt invisible hit targets ensure a clean first-tap interaction on camera.
  2. The `.ultraThinMaterial` **`TransitRevealSheet`** springs up, showing stacked multi-route line badges (`[A] [B] [C] [D] [1]`) and live arrivals with amber breathing radar pulse dots.
  3. Tap the **`Full Timetable`** segmented tab to reveal the 24-hour departure minute pill matrix with route filter pills (`[All] [A] [B]...`), live delay badges (`+Xm`), and dimmed past departures.
  4. Swipe down or tap outside to dismiss the Transit Sheet.
- **Spoken Voiceover / Subtitle:**
  > *"Within your active vicinity bubble, transit hubs reveal themselves through the fog. Tapping any station queries local SQLite 24-hour timetables, multi-route feeds, and live GTFS-RT Protobuf streams in under 10 milliseconds."*

---

### Scene 4: Nearby Buses Lens & Exploration Stats (00:43 – 00:54)
- **Visual:** Transit sheet is dismissed, main map HUD visible.
- **Your Action on Screen:**
  1. Tap the floating frosted-glass **Nearby Buses Capsule** in the bottom-left to expand active bus stops with resolved parent terminal names.
  2. Tap the top-right **Profile FAB** (crystalline aperture icon) to present **Exploration Stats**.
  3. Browse the **Neighborhoods** leaderboard (showing discovered hex count, % coverage of Manhattan / Upper West Side).
  4. Switch to the **Journal & Milestones** tab to showcase categorized milestone discovery cards (Transit Hubs, Landmarks).
- **Spoken Voiceover / Subtitle:**
  > *"Nearby bus lenses provide immediate arrival context without continuous background polling, while the local SQLite Exploration Journal tracks discovery progress across NYC neighborhoods."*

---

### Scene 5: Settings & Fragment Shader Tuning (00:54 – 01:05)
- **Visual:** Settings interface, pushed from the Exploration Stats gear icon.
- **Your Action on Screen:**
  1. From Exploration Stats, tap the top-right **Gear icon** to push into **Settings**.
  2. Toggle between **Standard Day** (Parchment `#F9F9F6`) and **Transit Network** (Porcelain White `#FFFFFF`), showcasing the instant 600ms GPU basemap crossfade with auto-adapting 40% fog opacity.
  3. Drag the **Fog Opacity slider** (40%–98%) back and forth (demonstrating instant MapLibre GPU fragment shader response with zero geometry rebuilds).
  4. Dismiss back to the map.
- **Spoken Voiceover / Subtitle:**
  > *"The interface transitions instantly between Standard Day exploration and high-contrast Transit Navigation, while fragment shader controls adjust fog density in real-time with zero geometry recomputation."*

---

### Scene 6: Outro & Clamped NYC Skyline (01:05 – 01:15)
- **Visual:** Full NYC overview with uncovered pathways glowing through the dark fog. Tightly clamped camera bounds (~5km rubber-band margin) cleanly retain focus on the metropolitan fog.
- **Your Action on Screen:**
  1. Two-finger pinch / zoom out until the full Manhattan and Brooklyn skyline is visible.
  2. Settle for 2 seconds on the broad map view (the clamped bounds prevent drifting past the fog edge).
- **Spoken Voiceover / Subtitle:**
  > *"Dérivée: Unlearn your commute. Built purely in native Swift with an autonomous AI engineering harness. Open source on GitHub."*

---

## Recording Checklist

1. Run the recording script in your terminal:
   ```bash
   bash docs/blog/record_demo.sh
   ```
2. Switch to the iOS Simulator window and follow Scenes 1 through 6.
3. Once you zoom out (around ~1:10–1:15), switch to your terminal and press **`[ENTER]`** or **`Ctrl + C`**.
4. The finalized video is automatically saved to:
   ```
   docs/blog/derivee_demo_final.mp4
   ```
