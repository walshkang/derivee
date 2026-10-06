interface OfflineStatusPillProps {
  isOnline: boolean;
}

export function OfflineStatusPill({ isOnline }: OfflineStatusPillProps) {
  return (
    <div
      class={`status-pill ${isOnline ? 'status-pill-online' : 'status-pill-offline'}`}
      role="status"
      aria-live="polite"
      aria-label={isOnline ? 'Application is online' : 'Application is offline'}
    >
      <span class="status-indicator-dot" />
      <span class="status-label">{isOnline ? 'Online' : 'Offline'}</span>
    </div>
  );
}
