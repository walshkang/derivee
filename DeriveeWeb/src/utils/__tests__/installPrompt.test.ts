import { describe, it } from 'node:test';
import assert from 'node:assert';
import {
  checkIsStandalone,
  checkIsIOS,
  shouldShowIOSCoachmark,
  isIOSCoachmarkDismissed,
  setIOSCoachmarkDismissed,
  IOS_INSTALL_DISMISSED_KEY,
} from '../installPrompt.ts';

describe('PWA Install Detection & Coachmark Rules', () => {
  describe('checkIsStandalone', () => {
    it('returns true when navigator.standalone is true (iOS WebKit standalone)', () => {
      const isStandalone = checkIsStandalone({
        navigatorObj: { standalone: true },
      });
      assert.strictEqual(isStandalone, true);
    });

    it('returns true when display-mode: standalone matches', () => {
      const isStandalone = checkIsStandalone({
        navigatorObj: { standalone: false },
        matchMediaFn: (query: string) => ({
          matches: query === '(display-mode: standalone)',
        }),
      });
      assert.strictEqual(isStandalone, true);
    });

    it('returns true when display-mode: fullscreen matches', () => {
      const isStandalone = checkIsStandalone({
        matchMediaFn: (query: string) => ({
          matches: query === '(display-mode: fullscreen)',
        }),
      });
      assert.strictEqual(isStandalone, true);
    });

    it('returns true when display-mode: minimal-ui matches', () => {
      const isStandalone = checkIsStandalone({
        matchMediaFn: (query: string) => ({
          matches: query === '(display-mode: minimal-ui)',
        }),
      });
      assert.strictEqual(isStandalone, true);
    });

    it('returns false for standard browser tab where no standalone mode matches (negative case)', () => {
      const isStandalone = checkIsStandalone({
        navigatorObj: { standalone: false },
        matchMediaFn: () => ({ matches: false }),
      });
      assert.strictEqual(isStandalone, false);
    });

    it('returns false gracefully when navigator and matchMedia are undefined (negative case)', () => {
      const isStandalone = checkIsStandalone({
        navigatorObj: undefined,
        matchMediaFn: undefined,
      });
      assert.strictEqual(isStandalone, false);
    });
  });

  describe('checkIsIOS', () => {
    it('returns true for iPhone userAgent', () => {
      const isIOS = checkIsIOS({
        navigatorObj: {
          userAgent: 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_4 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148 Safari/604.1',
        },
      });
      assert.strictEqual(isIOS, true);
    });

    it('returns true for iPad userAgent', () => {
      const isIOS = checkIsIOS({
        navigatorObj: {
          userAgent: 'Mozilla/5.0 (iPad; CPU OS 16_5 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148 Safari/604.1',
        },
      });
      assert.strictEqual(isIOS, true);
    });

    it('returns true for iPod userAgent', () => {
      const isIOS = checkIsIOS({
        navigatorObj: {
          userAgent: 'Mozilla/5.0 (iPod touch; CPU iPhone OS 14_0 like Mac OS X) AppleWebKit/605.1.15',
        },
      });
      assert.strictEqual(isIOS, true);
    });

    it('returns true for iPadOS reporting as MacIntel with touch points > 1', () => {
      const isIOS = checkIsIOS({
        navigatorObj: {
          platform: 'MacIntel',
          maxTouchPoints: 5,
          userAgent: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 Safari/605.1.15',
        },
      });
      assert.strictEqual(isIOS, true);
    });

    it('returns false for Android userAgent (negative case)', () => {
      const isIOS = checkIsIOS({
        navigatorObj: {
          userAgent: 'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 Chrome/122.0.0.0 Mobile Safari/537.36',
        },
      });
      assert.strictEqual(isIOS, false);
    });

    it('returns false for Desktop macOS (MacIntel with maxTouchPoints 0) (negative case)', () => {
      const isIOS = checkIsIOS({
        navigatorObj: {
          platform: 'MacIntel',
          maxTouchPoints: 0,
          userAgent: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 Chrome/122.0.0.0 Safari/537.36',
        },
      });
      assert.strictEqual(isIOS, false);
    });

    it('returns false for Desktop Linux / Windows (negative case)', () => {
      const isIOS = checkIsIOS({
        navigatorObj: {
          platform: 'Linux x86_64',
          maxTouchPoints: 0,
          userAgent: 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36',
        },
      });
      assert.strictEqual(isIOS, false);
    });

    it('returns false when navigator is undefined (negative case)', () => {
      const isIOS = checkIsIOS({ navigatorObj: undefined });
      assert.strictEqual(isIOS, false);
    });
  });

  describe('shouldShowIOSCoachmark', () => {
    it('returns true when on iOS, non-standalone, and no native prompt support', () => {
      const show = shouldShowIOSCoachmark({
        isIOS: true,
        isStandalone: false,
        hasNativePromptSupport: false,
      });
      assert.strictEqual(show, true);
    });

    it('returns false when already in standalone mode on iOS (never show in standalone)', () => {
      const show = shouldShowIOSCoachmark({
        isIOS: true,
        isStandalone: true,
        hasNativePromptSupport: false,
      });
      assert.strictEqual(show, false);
    });

    it('returns false on platforms with real install prompts (never show iOS coachmark)', () => {
      const show = shouldShowIOSCoachmark({
        isIOS: false,
        isStandalone: false,
        hasNativePromptSupport: true,
      });
      assert.strictEqual(show, false);
    });

    it('returns false if hasNativePromptSupport is true even if isIOS was set (negative case)', () => {
      const show = shouldShowIOSCoachmark({
        isIOS: true,
        isStandalone: false,
        hasNativePromptSupport: true,
      });
      assert.strictEqual(show, false);
    });

    it('returns false on non-iOS browsers without install prompts (negative case)', () => {
      const show = shouldShowIOSCoachmark({
        isIOS: false,
        isStandalone: false,
        hasNativePromptSupport: false,
      });
      assert.strictEqual(show, false);
    });
  });

  describe('Dismissal persistence (isIOSCoachmarkDismissed / setIOSCoachmarkDismissed)', () => {
    it('saves and reads dismissed state correctly from storage', () => {
      const storageMap = new Map<string, string>();
      const mockStorage = {
        getItem: (k: string) => storageMap.get(k) ?? null,
        setItem: (k: string, v: string) => storageMap.set(k, v),
      } as unknown as Storage;

      assert.strictEqual(isIOSCoachmarkDismissed(mockStorage), false);
      setIOSCoachmarkDismissed(mockStorage);
      assert.strictEqual(isIOSCoachmarkDismissed(mockStorage), true);
      assert.strictEqual(storageMap.get(IOS_INSTALL_DISMISSED_KEY), 'true');
    });

    it('handles private browsing SecurityError without throwing (negative case)', () => {
      const throwingStorage = {
        getItem: () => {
          throw new Error('SecurityError: The operation is insecure.');
        },
        setItem: () => {
          throw new Error('SecurityError: The operation is insecure.');
        },
      } as unknown as Storage;

      assert.strictEqual(isIOSCoachmarkDismissed(throwingStorage), false);
      // setIOSCoachmarkDismissed should not throw
      assert.doesNotThrow(() => {
        setIOSCoachmarkDismissed(throwingStorage);
      });
    });

    it('handles undefined storage gracefully (negative case)', () => {
      assert.strictEqual(isIOSCoachmarkDismissed(undefined), false);
      assert.doesNotThrow(() => {
        setIOSCoachmarkDismissed(undefined);
      });
    });
  });
});
