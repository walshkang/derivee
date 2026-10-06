import { OfflineStatusPill } from './OfflineStatusPill';

interface HeaderProps {
  isOnline: boolean;
  isStandalone: boolean;
  canInstall?: boolean;
  onTriggerInstall: () => void;
}

export function Header({ isOnline, isStandalone, canInstall = false, onTriggerInstall }: HeaderProps) {
  // Never show install button in standalone mode or when platform cannot install
  const showInstallBtn = !isStandalone && canInstall;

  return (
    <header class="app-header">
      <div class="header-branding">
        <div class="logo-mark" aria-hidden="true">
          <svg viewBox="0 0 32 32" width="20" height="20" fill="none" class="brand-aperture-glyph">
            <path
              d="M 16,3 L 20,5.5 L 24,3 L 28,5.5 L 28,10.5 L 31.5,12.5 L 31.5,17.5 L 31.5,22.5 L 28,24.5 L 28,29.5 L 24,32 L 20,29.5 L 16,32 L 12,29.5 L 8,32 L 4,29.5 L 4,24.5 L 0.5,22.5 L 0.5,17.5 L 0.5,12.5 L 4,10.5 L 4,5.5 L 8,3 L 12,5.5 Z"
              stroke="rgba(241, 245, 249, 0.85)"
              stroke-width="1.75"
              stroke-linejoin="round"
            />
            <circle cx="16" cy="17.5" r="3.2" fill="#FFB300" />
          </svg>
        </div>
        <div class="header-titles">
          <h1 class="app-title">Dérivée</h1>
          <span class="app-subtitle">NYC</span>
        </div>
      </div>

      <div class="header-actions">
        <OfflineStatusPill isOnline={isOnline} />

        {showInstallBtn && (
          <button
            type="button"
            class="install-trigger-btn"
            onClick={onTriggerInstall}
            title="Add to Home Screen"
            aria-label="Add Dérivée to Home Screen"
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
