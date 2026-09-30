import { useEffect } from 'preact/hooks';

interface InstallModalProps {
  isOpen: boolean;
  onClose: () => void;
}

export function InstallModal({ isOpen, onClose }: InstallModalProps) {
  useEffect(() => {
    if (!isOpen) return;

    const handleKeyDown = (e: KeyboardEvent) => {
      if (e.key === 'Escape') {
        onClose();
      }
    };

    window.addEventListener('keydown', handleKeyDown);
    return () => {
      window.removeEventListener('keydown', handleKeyDown);
    };
  }, [isOpen, onClose]);

  if (!isOpen) return null;

  return (
    <div class="modal-backdrop ios-coachmark-backdrop" onClick={onClose} role="presentation">
      <div
        class="install-modal-card ios-coachmark-card"
        onClick={(e) => e.stopPropagation()}
        role="dialog"
        aria-modal="true"
        aria-labelledby="install-modal-title"
        aria-describedby="install-modal-intro"
      >
        <div class="modal-header">
          <div class="modal-badge">
            <span class="modal-badge-dot" />
            <span>Add to Home Screen</span>
          </div>
          <button
            type="button"
            class="modal-close-btn"
            onClick={onClose}
            aria-label="Close installation instructions"
          >
            ✕
          </button>
        </div>

        <h3 id="install-modal-title" class="modal-title">
          Install Dérivée for Offline Navigation
        </h3>

        <p id="install-modal-intro" class="modal-intro">
          iOS Safari requires saving to your Home Screen for full offline subway routing and permanent offline storage:
        </p>

        <ol class="install-steps-list">
          <li class="install-step-item">
            <div class="step-num">1</div>
            <div class="step-body">
              <span class="step-text">Tap the <strong>Share</strong> button</span>
              <span class="step-sub">In the bottom Safari toolbar (or top bar on iPad)</span>
            </div>
            <div class="step-icon-badge" aria-hidden="true">
              <svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" stroke-width="2">
                <path d="M4 12v8a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2v-8" stroke-linecap="round" stroke-linejoin="round" />
                <polyline points="16 6 12 2 8 6" stroke-linecap="round" stroke-linejoin="round" />
                <line x1="12" y1="2" x2="12" y2="15" stroke-linecap="round" stroke-linejoin="round" />
              </svg>
            </div>
          </li>

          <li class="install-step-item">
            <div class="step-num">2</div>
            <div class="step-body">
              <span class="step-text">Scroll and tap <strong>Add to Home Screen</strong></span>
              <span class="step-sub">Look for the square icon with a plus sign</span>
            </div>
            <div class="step-icon-badge" aria-hidden="true">
              <svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" stroke-width="2">
                <rect x="3" y="3" width="18" height="18" rx="4" stroke-linecap="round" stroke-linejoin="round" />
                <line x1="12" y1="8" x2="12" y2="16" stroke-linecap="round" stroke-linejoin="round" />
                <line x1="8" y1="12" x2="16" y2="12" stroke-linecap="round" stroke-linejoin="round" />
              </svg>
            </div>
          </li>

          <li class="install-step-item">
            <div class="step-num">3</div>
            <div class="step-body">
              <span class="step-text">Tap <strong>Add</strong> in the top-right corner</span>
              <span class="step-sub">Launches full screen with instant offline subway maps</span>
            </div>
            <div class="step-icon-badge" aria-hidden="true">
              <span class="step-tag-add">Add</span>
            </div>
          </li>
        </ol>

        <div class="modal-footer-note">
          <svg viewBox="0 0 20 20" width="14" height="14" fill="none" stroke="currentColor" stroke-width="1.5" aria-hidden="true">
            <circle cx="10" cy="10" r="9" />
            <line x1="10" y1="9" x2="10" y2="14" stroke-linecap="round" />
            <circle cx="10" cy="6" r="0.75" fill="currentColor" />
          </svg>
          <span>
            Home Screen apps are exempt from iOS Safari’s 7-day cache purge and run 100% offline in subway tunnels.
          </span>
        </div>

        <button type="button" class="modal-dismiss-action" onClick={onClose}>
          Got it
        </button>

        {/* Coachmark pointer indicator towards bottom Safari toolbar */}
        <div class="coachmark-pointer-arrow" aria-hidden="true">
          <svg viewBox="0 0 24 16" width="24" height="16" fill="currentColor">
            <polygon points="12,16 2,0 22,0" />
          </svg>
        </div>
      </div>
    </div>
  );
}
