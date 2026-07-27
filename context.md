# Project Context

## Current Status: Wave 9 (W9-OBSERVER)
The Observer backend (the Golang daemon) codebase is completely written and stored in the `observer/` directory. The Expo app is also fully integrated to fetch and attach the resulting SQLite database (`src/services/syncService.ts`).

**Pending Action:**
The VPS deployment is currently blocked because the Oracle Cloud instance became completely unresponsive (hard locked/OOM crashed) during the first build attempt. 

**Next Steps to see it running:**
1. Hard-reset the Oracle Cloud VPS from the Oracle Web Console.
2. SSH into the VPS: `ssh -i "/Users/walsh.kang/Library/CloudStorage/GoogleDrive-wkang1281@gmail.com/My Drive/000. Notes/ssh-key-2026-07-27.key" ubuntu@150.136.171.50`
3. Add a 1GB swap file so it doesn't crash during the build:
   ```bash
   sudo fallocate -l 1G /swapfile
   sudo chmod 600 /swapfile
   sudo mkswap /swapfile
   sudo swapon /swapfile
   ```
4. Build and start the daemon:
   ```bash
   cd ~/observer
   go build -o observer_daemon ./cmd/observer
   ./observer_daemon
   ```
