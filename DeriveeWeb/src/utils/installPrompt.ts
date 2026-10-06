/**
 * Utility functions for PWA installation detection and prompt flows.
 * Handles iOS Add to Home Screen detection vs native beforeinstallprompt platforms.
 */

export const IOS_INSTALL_DISMISSED_KEY = 'derivee_ios_install_dismissed';

export interface StandaloneDetectionEnv {
  navigatorObj?: {
    standalone?: boolean;
    userAgent?: string;
    platform?: string;
    maxTouchPoints?: number;
  };
  matchMediaFn?: (query: string) => { matches: boolean };
}

/**
 * Detects if the web app is running in standalone mode (already installed).
 * Checks iOS navigator.standalone, display-mode: standalone, fullscreen, and minimal-ui.
 */
export function checkIsStandalone(env?: StandaloneDetectionEnv): boolean {
  const nav = env?.navigatorObj ?? (typeof window !== 'undefined' ? window.navigator : undefined);
  const mm = env?.matchMediaFn ?? (typeof window !== 'undefined' && typeof window.matchMedia === 'function' ? window.matchMedia.bind(window) : undefined);

  if ((nav as unknown as { standalone?: boolean })?.standalone === true) {
    return true;
  }

  if (mm) {
    if (mm('(display-mode: standalone)').matches) return true;
    if (mm('(display-mode: fullscreen)').matches) return true;
    if (mm('(display-mode: minimal-ui)').matches) return true;
  }

  return false;
}

/**
 * Detects if the current environment is an iOS device (iPhone, iPad, iPod, or iPadOS).
 */
export function checkIsIOS(env?: StandaloneDetectionEnv): boolean {
  const nav = env?.navigatorObj ?? (typeof window !== 'undefined' ? window.navigator : undefined);
  if (!nav) return false;

  const ua = nav.userAgent || '';
  if (/iPad|iPhone|iPod/.test(ua)) {
    return true;
  }

  // iPadOS on MacIntel (Safari reports platform MacIntel with multi-touch)
  if (nav.platform === 'MacIntel' && (nav.maxTouchPoints || 0) > 1) {
    return true;
  }

  return false;
}

/**
 * Determines whether the iOS "Add to Home Screen" coachmark should be shown.
 * Invariant: NEVER show in standalone mode or on platforms with real install prompts.
 */
export function shouldShowIOSCoachmark(params: {
  isIOS: boolean;
  isStandalone: boolean;
  hasNativePromptSupport: boolean;
}): boolean {
  if (params.isStandalone) {
    return false;
  }
  if (params.hasNativePromptSupport) {
    return false;
  }
  return params.isIOS;
}

/**
 * Checks if the iOS coachmark was previously dismissed by the user.
 * Safe against private browsing storage exceptions.
 */
export function isIOSCoachmarkDismissed(storage?: Storage): boolean {
  try {
    const s = storage ?? (typeof window !== 'undefined' ? window.localStorage : undefined);
    return s?.getItem(IOS_INSTALL_DISMISSED_KEY) === 'true';
  } catch {
    return false;
  }
}

/**
 * Persists the user's dismissal of the iOS install coachmark.
 * Safe against private browsing storage exceptions.
 */
export function setIOSCoachmarkDismissed(storage?: Storage): void {
  try {
    const s = storage ?? (typeof window !== 'undefined' ? window.localStorage : undefined);
    s?.setItem(IOS_INSTALL_DISMISSED_KEY, 'true');
  } catch {
    // Gracefully ignore storage write failures in private browsing
  }
}
