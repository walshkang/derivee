interface SystemInfoDrawerProps {
  isOnline: boolean;
}

export function SystemInfoDrawer({ isOnline }: SystemInfoDrawerProps) {
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
          <span class="meta-dot standby-dot" />
          <span>Pack: M2 Standby</span>
        </div>
        <div class="footer-meta-item">
          <span class={`meta-dot ${isOnline ? 'online-dot' : 'offline-dot'}`} />
          <span>Network: {isOnline ? 'Connected' : 'Offline'}</span>
        </div>
      </div>
    </footer>
  );
}
