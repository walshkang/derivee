import type { InstalledPackState } from '../types/pack';
import { formatBuildInfo } from '../utils/buildInfo';

interface SystemInfoDrawerProps {
  isOnline: boolean;
  packState?: InstalledPackState | null;
  onOpenTransitPack?: () => void;
}

export function SystemInfoDrawer({ isOnline, packState, onOpenTransitPack }: SystemInfoDrawerProps) {
  const isInstalled = Boolean(packState?.isInstalled);
  const buildInfo = formatBuildInfo();

  return (
    <footer class="system-footer-drawer">
      <div class="footer-status-pill">
        <span class="footer-dot" />
        <span class="footer-title">Dérivée Shell v0.1.0</span>
      </div>

      <div class="footer-meta-items">
        <div class="footer-meta-item">
          <span class="meta-dot online-dot" />
          <span>Shell: Cached Offline</span>
        </div>
        <button
          type="button"
          class="footer-meta-item footer-clickable-item"
          onClick={onOpenTransitPack}
          title={isInstalled ? 'Manage transit pack' : 'Open pack installer'}
        >
          <span class={`meta-dot ${isInstalled ? 'online-dot' : 'standby-dot'}`} />
          <span>Transit pack: {isInstalled ? `NYC v${packState?.version} (Installed)` : 'Not Installed'}</span>
        </button>
        <div class="footer-meta-item">
          <span class={`meta-dot ${isOnline ? 'online-dot' : 'offline-dot'}`} />
          <span>Network: {isOnline ? 'Connected' : 'Offline'}</span>
        </div>
        <div class="footer-meta-item footer-build-item" title={`Build: ${buildInfo}`}>
          <span class="meta-dot standby-dot" />
          <span>Build: <span class="footer-build-hash">{buildInfo}</span></span>
        </div>
      </div>
    </footer>
  );
}

