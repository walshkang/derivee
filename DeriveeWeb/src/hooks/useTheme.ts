import { useState, useEffect, useCallback } from 'preact/hooks';
import {
  getStoredTheme,
  setStoredTheme,
  resolveTheme,
  applyTheme,
  onSystemThemeChange,
  type ThemeSetting,
  type ResolvedTheme,
} from '../utils/theme';

export function useTheme() {
  const [theme, setThemeState] = useState<ThemeSetting>(() => getStoredTheme());
  const [resolvedTheme, setResolvedTheme] = useState<ResolvedTheme>(() => {
    const initialStored = getStoredTheme();
    return resolveTheme(initialStored);
  });

  useEffect(() => {
    const nextResolved = resolveTheme(theme);
    setResolvedTheme(nextResolved);
    applyTheme(nextResolved);

    if (theme === 'system') {
      const unsub = onSystemThemeChange((sys) => {
        setResolvedTheme(sys);
        applyTheme(sys);
      });
      return unsub;
    }
  }, [theme]);

  const setTheme = useCallback((next: ThemeSetting) => {
    setThemeState(next);
    setStoredTheme(next);
    const nextResolved = resolveTheme(next);
    setResolvedTheme(nextResolved);
    applyTheme(nextResolved);
  }, []);

  return { theme, resolvedTheme, setTheme };
}
