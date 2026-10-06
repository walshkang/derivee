/**
 * theme.ts
 * Theme state management, persistence, system-preference resolution, and DOM application.
 *
 * Invariants:
 * - Default theme is 'system'.
 * - Persisted in localStorage under 'derivee_theme'.
 * - If set to 'system', dynamically resolves via prefers-color-scheme.
 * - Active theme sets [data-theme="light"] or [data-theme="dark"] on document.documentElement.
 */

export type ThemeSetting = 'system' | 'light' | 'dark';
export type ResolvedTheme = 'light' | 'dark';

export const THEME_STORAGE_KEY = 'derivee_theme';

/**
 * Reads stored theme setting from localStorage.
 * Falls back safely to 'system' if missing, null, or invalid.
 */
export function getStoredTheme(): ThemeSetting {
  try {
    if (typeof localStorage === 'undefined') return 'system';
    const val = localStorage.getItem(THEME_STORAGE_KEY);
    if (val === 'light' || val === 'dark' || val === 'system') {
      return val;
    }
  } catch {
    // localStorage access denied or unavailable
  }
  return 'system';
}

/**
 * Persists theme setting to localStorage.
 */
export function setStoredTheme(theme: ThemeSetting): void {
  try {
    if (typeof localStorage === 'undefined') return;
    localStorage.setItem(THEME_STORAGE_KEY, theme);
  } catch {
    // localStorage access denied or unavailable
  }
}

/**
 * Checks system color scheme preference.
 * Defaults to 'light' if matchMedia is unavailable.
 */
export function getSystemTheme(): ResolvedTheme {
  try {
    if (typeof window !== 'undefined' && typeof window.matchMedia === 'function') {
      const isDark = window.matchMedia('(prefers-color-scheme: dark)').matches;
      return isDark ? 'dark' : 'light';
    }
  } catch {
    // Media query matching failed
  }
  return 'light';
}

/**
 * Resolves a ThemeSetting ('system' | 'light' | 'dark') to an active ResolvedTheme ('light' | 'dark').
 */
export function resolveTheme(theme: ThemeSetting): ResolvedTheme {
  if (theme === 'system') {
    return getSystemTheme();
  }
  return theme;
}

/**
 * Applies the resolved theme to document.documentElement via data-theme attribute.
 */
export function applyTheme(theme: ResolvedTheme): void {
  if (typeof document !== 'undefined' && document.documentElement) {
    document.documentElement.setAttribute('data-theme', theme);
  }
}

/**
 * Subscribes to system color scheme changes.
 * Returns an unsubscribe function.
 */
export function onSystemThemeChange(callback: (theme: ResolvedTheme) => void): () => void {
  if (typeof window === 'undefined' || typeof window.matchMedia !== 'function') {
    return () => {};
  }

  try {
    const mql = window.matchMedia('(prefers-color-scheme: dark)');
    const handler = (e: MediaQueryListEvent | MediaQueryList) => {
      callback(e.matches ? 'dark' : 'light');
    };

    if (typeof mql.addEventListener === 'function') {
      mql.addEventListener('change', handler);
      return () => mql.removeEventListener('change', handler);
    } else if (typeof (mql as any).addListener === 'function') {
      (mql as any).addListener(handler);
      return () => (mql as any).removeListener(handler);
    }
  } catch {
    // Listener setup failed
  }

  return () => {};
}
