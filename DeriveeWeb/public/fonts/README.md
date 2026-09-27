# Self-Hosted Map Font Glyphs (Placeholder for M4)

This directory is reserved for self-hosted font glyph PBF files (e.g. `Noto Sans Regular/0-255.pbf`) used by MapLibre GL for offline vector basemap rendering.

## Why Self-Hosted?
Per Dérivée Web Architecture Decision Record 4 and iOS Safari offline constraints:
- In offline mode (airplane mode or underground MTA subway stations), MapLibre GL cannot fetch font glyphs from remote CDNs.
- Storing glyphs in the PWA app shell ensures zero network dependencies when rendering street, subway station, and neighborhood labels on the vector basemap.

## M4 Provisioning:
In Milestone 4 (Offline Maps), generate or copy the required PBF ranges:
- `fonts/Noto Sans Regular/{start}-{end}.pbf`
- `fonts/Noto Sans Bold/{start}-{end}.pbf`

Large binary glyph sets will be populated in Milestone 4.
