import { useEffect, useState, useRef } from 'preact/hooks';
import {
  checkIsStandalone,
  checkIsIOS,
  shouldShowIOSCoachmark,
  isIOSCoachmarkDismissed,
  setIOSCoachmarkDismissed,
} from '../utils/installPrompt';

export interface BeforeInstallPromptEvent extends Event {
  readonly platforms: string[];
  readonly userChoice: Promise<{
    outcome: 'accepted' | 'dismissed';
    platform: string;
  }>;
  prompt(): Promise<void>;
}

export interface IOSInstallState {
  isIOS: boolean;
  isStandalone: boolean;
  canPromptNative: boolean;
  canShowIOSCoachmark: boolean;
  isOpen: boolean;
  openModal: () => void;
  closeModal: () => void;
  promptInstall: () => Promise<void>;
}

export function useIsIOSInstallable(): IOSInstallState {
  const [isIOS, setIsIOS] = useState<boolean>(false);
  const [isStandalone, setIsStandalone] = useState<boolean>(false);
  const [canPromptNative, setCanPromptNative] = useState<boolean>(false);
  const [isOpen, setIsOpen] = useState<boolean>(false);
  const deferredPromptRef = useRef<BeforeInstallPromptEvent | null>(null);

  useEffect(() => {
    if (typeof window === 'undefined' || typeof navigator === 'undefined') return;

    // Detect standalone mode (already installed PWA)
    const standaloneMode = checkIsStandalone();
    setIsStandalone(standaloneMode);

    // Detect iOS devices (iPhone, iPad, iPod, iPadOS on MacIntel)
    const iosDevice = checkIsIOS();
    setIsIOS(iosDevice);

    // Listen for standard beforeinstallprompt on supported platforms (Android / Chrome / Edge)
    const handleBeforeInstallPrompt = (e: Event) => {
      // Prevent browser default mini-infobar on mobile Chrome
      e.preventDefault();
      deferredPromptRef.current = e as BeforeInstallPromptEvent;
      setCanPromptNative(true);
    };

    window.addEventListener('beforeinstallprompt', handleBeforeInstallPrompt);

    // Auto-prompt iOS coachmark only if on iOS Safari, NOT standalone, and not previously dismissed
    if (iosDevice && !standaloneMode) {
      const previouslyDismissed = isIOSCoachmarkDismissed();
      if (!previouslyDismissed) {
        setIsOpen(true);
      }
    }

    return () => {
      window.removeEventListener('beforeinstallprompt', handleBeforeInstallPrompt);
    };
  }, []);

  const openModal = () => setIsOpen(true);

  const closeModal = () => {
    setIsOpen(false);
    setIOSCoachmarkDismissed();
  };

  const promptInstall = async () => {
    if (deferredPromptRef.current) {
      try {
        await deferredPromptRef.current.prompt();
        const choice = await deferredPromptRef.current.userChoice;
        if (choice.outcome === 'accepted') {
          deferredPromptRef.current = null;
          setCanPromptNative(false);
        }
      } catch {
        // Safe to ignore prompt errors
      }
    } else if (isIOS && !isStandalone) {
      setIsOpen(true);
    }
  };

  const canShowCoachmark = shouldShowIOSCoachmark({
    isIOS,
    isStandalone,
    hasNativePromptSupport: canPromptNative,
  });

  return {
    isIOS,
    isStandalone,
    canPromptNative,
    canShowIOSCoachmark: canShowCoachmark,
    isOpen: isOpen && canShowCoachmark,
    openModal,
    closeModal,
    promptInstall,
  };
}
