# Dérivée Demo Video Recording Script & Storyboard
## Manual Video Recording Guide (5-Hex Automated Walk + Manual UI Exploration)

- **Target Duration:** ~60–75 seconds
- **Format:** 9:16 Vertical Video (iPhone 17 Pro, 1206×2622) or 16:9 Landscape
- **Workflow:** The GPX walk runs automatically for ~20 seconds (5 hexes), then holds position so you can perform all UI interactions at your own pace.

---

## Storyboard & Action Script

```
+---------------------------------------------------------------------------------------+
|  00:00 - 00:05 | Scene 1: Cold Start & Ambient Fog Cartography                        |
|  00:05 - 00:25 | Scene 2: 20s Automated Walk (5 Hex Unlocks along CPW / 8th Ave)      |
|  00:25 - 00:40 | Scene 3: Tap Subway Station -> Transit Sheet & Live Headways          |
|  00:40 - 00:52 | Scene 4: Tap Bus Capsule -> Open Exploration Journal & Stats         |
|  00:52 - 01:04 | Scene 5: Settings FAB -> Toggle Day/Night & Fog Opacity Slider        |
|  01:04 - 01:15 | Scene 6: Outro -> Zoom Out to Full NYC Skyline & Finish Recording    |
+---------------------------------------------------------------------------------------+
```

---

### Scene 1: Cold Start & Ambient Fog (00:00 – 00:05)
- **Visual:** Dérivée opens cleanly in Day Mode (Parchment White `#F9F9F6`) centered at Columbus Circle. OLED dark fog blankets the surrounding city.
- **Your Action on Screen:** Hold still or do a slight micro-pan across Columbus Circle / Central Park South.
- **Spoken Voiceover / Subtitle:**
  > *"Every transit app rushes you through the city. Dérivée is built for the drift. The entire metropolis begins shrouded in an ambient Fog of War."*

---

### Scene 2: Live Walk & 120Hz Spatial Polygon Dissolution (00:05 – 00:25)
- **Visual:** The Amber GPS puck moves north along Central Park West / 8th Ave.
- **Automatic Automation:** The script feeds 15 waypoints (~260m across 5 H3 Res-11 hexes).
- **Your Action on Screen:** Keep your eyes / pointer relaxed as the camera follows the GPS puck. Watch the Res-11 hexagonal apertures dissolve cleanly from the fog mask and union into single smooth polygon cutouts.
- **Spoken Voiceover / Subtitle:**
  > *"As you walk, your path uncovers Resolution 11 H3 hexagons in real time. Contiguous cells dissolve off-thread into unified polygons, keeping MapLibre GPU rendering locked at 120Hz."*

---

### Scene 3: Subway Transit Reveal & Headway Analytics (00:25 – 00:40)
- **Visual:** The walk finishes and holds at the 5th hex destination.
- **Your Action on Screen:**
  1. Tap the **59th St – Columbus Circle** (or nearest) subway station disc on the map.
  2. The `.ultraThinMaterial` **`TransitRevealSheet`** springs up over the bottom third of the screen.
  3. Scroll down slightly on the sheet to reveal the live train arrivals and historical headway frequency breakdown.
- **Spoken Voiceover / Subtitle:**
  > *"Within your active vicinity bubble, transit hubs reveal themselves through the fog. Tapping any station queries local SQLite headways and live GTFS-RT Protobuf streams in under 10 milliseconds."*

---

### Scene 4: Nearby Buses Lens & Exploration Journal (00:40 – 00:52)
- **Visual:** Transit sheet is dismissed.
- **Your Action on Screen:**
  1. Swipe down or tap outside to dismiss the Transit Sheet.
  2. Tap the floating frosted-glass **Bus Capsule** in the bottom corner to show active bus line arrivals.
  3. Tap the **Journal / Stats button** to present the **`ExplorationJournalView`**.
  4. Scroll through the Neighborhood Discovery Leaderboard (showing discovered hex count, % coverage of Manhattan / Upper West Side).
- **Spoken Voiceover / Subtitle:**
  > *"Nearby bus lenses provide immediate arrival context without continuous background polling, while the local SQLite Exploration Journal tracks discovery progress across NYC neighborhoods."*

---

### Scene 5: Day / Night Basemap & Shader Tuning (00:52 – 01:04)
- **Visual:** App settings interface.
- **Your Action on Screen:**
  1. Tap the **Profile / Settings FAB**.
  2. Toggle between **Day Mode** (Parchment `#F9F9F6`) and **Night Mode** (Midnight Slate `#12121A`).
  3. Drag the **Fog Opacity slider** back and forth (demonstrating instant MapLibre GPU shader response with zero geometry rebuilds).
- **Spoken Voiceover / Subtitle:**
  > *"The interface shifts dynamically between Day Parchment and Midnight Slate based on solar ephemeris, while shader updates adjust opacity instantly without geometry recomputation."*

---

### Scene 6: Outro & Architectural Summary (01:04 – 01:15)
- **Visual:** Full NYC overview with uncovered pathways glowing through the dark fog.
- **Your Action on Screen:**
  1. Dismiss Settings.
  2. Two-finger pinch / zoom out until the full Manhattan and Brooklyn skyline is visible.
  3. Settle for 2 seconds on the broad map view.
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
