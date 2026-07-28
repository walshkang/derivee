# Project Context

## Current Status: Wave 14 (W14-UI-STATS) In Progress / Debugging
The neighborhood progression tracking and statistics system UI is built, but we are actively working through issues on the Statistics screen (`app/stats.tsx`).

### Key Milestones Completed:
1. **Data Pipeline & GIS Water Subtraction (`W14-DATA-NEIGHBORHOODS`)**:
   - Created `scripts/generate_neighborhood_db.py` to calculate neighborhood hex counts while excluding water bodies (using NYC Open Data GIS boundaries & Turf.js / Shapely boolean difference).
   - Generated pre-populated `assets/neighborhood.sqlite` attached dynamically in `src/db/database.ts`.

2. **Contextual Stat Bar & UI Polish (`W14-UI-STATS`)**:
   - Implemented `ContextualStatPill` (`src/components/ContextualStatPill.tsx`) with a high-contrast light-mode glassmorphic appearance (`rgba(255, 255, 255, 0.95)`, `#e2e8f0` border, `zIndex: 100`) that stands out clearly over map fog.
   - Built the full Statistics & Records Screen (`app/stats.tsx`) featuring unlocked hex metrics, city-wide percentage, NYC neighborhood leaderboard dropdown, workout GPX/FIT file importer, past workout list, and offline privacy exporter.

### ⚠️ Open Issue / Active Focus:
- **Stats Page Navigation & Database Lifecycle (`app/stats.tsx`)**:
  - We are still struggling with touch interaction/navigation and OP-SQLite connection host function errors (`[OP-SQLite] DB is not open`) when opening the stats screen on iOS runtime.
  - Next debugging priority: Resolve OP-SQLite singleton connection persistence across Expo Router screen transitions and isolate any native MapView/ScrollView gesture conflicts on `app/stats.tsx`.

**Next Planned Wave:**
- **Wave 15 (`W15-DYNAMIC-ISLAND`)**: Add iOS Dynamic Island / Live Activities support for ambient neighborhood progression tracking.
