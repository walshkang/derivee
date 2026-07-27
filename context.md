# Project Context

## Current Status: Wave 11 (W11-TIMETABLE)
The Observer backend (the Golang daemon) codebase has been completely upgraded to handle both Subways and Buses using unified GTFS-RT Protobuf feeds. The massive static GTFS schedules have been shifted to a local SQLite database (`static_gtfs.sqlite`), entirely resolving the OOM (Out-of-Memory) crashes on the VPS. 

**Next Steps:**
1. Deploy the new Observer codebase to the Oracle Cloud VPS and ensure the cron/systemd service is active.
2. The Expo app (`src/services/syncService.ts`) is fully integrated to fetch and attach the resulting SQLite database. We now need to build the frontend UI (Headway Matrix / Timetable) to query and render the historical sparklines from `transit_delta.sqlite.zst`.
