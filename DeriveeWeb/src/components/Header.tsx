import { OfflineStatusPill } from './OfflineStatusPill';

interface HeaderProps {
  isOnline: boolean;
  isStandalone: boolean;
  onOpenInstallModal: () => void;
}

export function Header({ isOnline, isStandalone, onOpenInstallModal }: HeaderProps) {
  return (
    <header class="app-header">
      <div class="header-branding">
        <div class="logo-mark" aria-hidden="true">
          <svg viewBox="0 0 32 32" width="24" height="24" fill="none">
            <circle cx="16" cy="16" r="14" stroke="#1e293b" stroke-width="1.5" />
            <path
              d="M13 8h4.5a6.5 6.5 0 0 1 0 13H13V8z"
              stroke="#38bdf8"
              stroke-width="2"
              stroke-linecap="round"
              stroke-linejoin="round"
            />
            <polygon points="16,10 16,16 14.5,16" fill="#06b6d4" />
            <polygon points="16,10 17.5,16 16,16" fill="#e0f2fe" />
            <circle cx="16" cy="16" r="2" fill="#f59e0b" />
          </svg>
        </div>
        <div class="header-titles">
          <h1 class="app-title">Dérivée</h1>
          <span class="app-subtitle">NYC</span>
        </div>
      </div>

      <div class="header-actions">
        <OfflineStatusPill isOnline={isOnline} />

        {!isStandalone && (
          <button
            type="button"
            class="install-trigger-btn"
            onClick={onOpenInstallModal}
            title="Add to Home Screen"
            aria-label="Add to Home Screen instructions"
          >
            <svg
              viewBox="0 0 20 20"
              width="15"
              height="15"
              fill="none"
              stroke="currentColor"
              stroke-width="1.75"
              aria-hidden="true"
            >
              <path d="M10 2v10m0 0l-3-3m3 3l3-3M3 14v2a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2v-2" stroke-linecap="round" stroke-linejoin="round" />
            </svg>
            <span class="install-trigger-text">Install</span>
          </button>
        )}
      </div>
    </header>
  );
}
