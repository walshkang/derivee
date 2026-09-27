import { useEffect, useState } from 'preact/hooks';

const DISMISSED_KEY = 'derivee_ios_install_dismissed';

export interface IOSInstallState {
  isIOS: boolean;
  isStandalone: boolean;
  isOpen: boolean;
  openModal: () => void;
  closeModal: () => void;
}

export function useIsIOSInstallable(): IOSInstallState {
  const [isIOS, setIsIOS] = useState<boolean>(false);
  const [isStandalone, setIsStandalone] = useState<boolean>(false);
  const [isOpen, setIsOpen] = useState<boolean>(false);

  useEffect(() => {
    if (typeof window === 'undefined' || typeof navigator === 'undefined') return;

    // Detect standalone mode (already installed PWA)
    const isStandaloneMode =
      (window.navigator as unknown as { standalone?: boolean }).standalone === true ||
      window.matchMedia('(display-mode: standalone)').matches ||
      window.matchMedia('(display-mode: fullscreen)').matches;

    setIsStandalone(isStandaloneMode);

    // Detect iOS devices (iPhone, iPad, iPod, iPadOS on MacIntel)
    const ua = navigator.userAgent;
    const isIOSDevice =
      /iPad|iPhone|iPod/.test(ua) ||
      (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);

    setIsIOS(isIOSDevice);

    // Auto-prompt only if on iOS Safari, not standalone, and not previously dismissed
    if (isIOSDevice && !isStandaloneMode) {
      const previouslyDismissed = localStorage.getItem(DISMISSED_KEY);
      if (!previouslyDismissed) {
        setIsOpen(true);
      }
    }
  }, []);

  const openModal = () => setIsOpen(true);

  const closeModal = () => {
    setIsOpen(false);
    try {
      localStorage.setItem(DISMISSED_KEY, 'true');
    } catch {
      // Storage unavailable in private browsing
    }
  };

  return {
    isIOS,
    isStandalone,
    isOpen,
    openModal,
    closeModal
  };
}
