import type { InstalledPackState } from '../types/pack';

interface SystemInfoDrawerProps {
  isOnline: boolean;
  packState?: InstalledPackState | null;
}

export function SystemInfoDrawer({ isOnline, packState }: SystemInfoDrawerProps) {
  const isInstalled = Boolean(packState?.isInstalled);

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
        <div class="footer-meta-item">
          <span class={`meta-dot ${isInstalled ? 'online-dot' : 'standby-dot'}`} />
          <span>Pack: {isInstalled ? `NYC v${packState?.version} (Installed)` : 'Not Installed'}</span>
        </div>
        <div class="footer-meta-item">
          <span class={`meta-dot ${isOnline ? 'online-dot' : 'offline-dot'}`} />
          <span>Network: {isOnline ? 'Connected' : 'Offline'}</span>
        </div>
      </div>
    </footer>
  );
}
