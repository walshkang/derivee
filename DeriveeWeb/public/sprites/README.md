# Self-Hosted Map Sprites (Placeholder for M4)

This directory is reserved for offline map sprite sheets and transit line icons used by MapLibre GL.

## Why Self-Hosted?
Per Dérivée Web Architecture Decision Record 4 and iOS Safari offline constraints:
- MapLibre GL requires sprite sheets for rendering POI icons, transit shields, and subway route bullets offline.
- Self-hosting sprite PNGs and JSON metadata in the PWA app shell guarantees that visual map markers and station bullets render reliably underground with zero network requests.

## M4 Provisioning:
In Milestone 4 (Offline Maps), provide:
- `sprites/dark.png` (high-DPI sprite sheet matching the dark atmospheric theme)
- `sprites/dark.json` (sprite coordinate index)
- `@2x` variants for Apple Retina displays

Large sprite sheets will be populated in Milestone 4.
