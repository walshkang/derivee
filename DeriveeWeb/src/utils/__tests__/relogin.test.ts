import { describe, it } from 'node:test';
import assert from 'node:assert';
import {
  forceRelogin,
  RELOGIN_FALLBACK_MESSAGE,
  type NavigatorLike,
  type LocationLike,
  type ServiceWorkerRegistrationLike,
} from '../relogin.ts';

describe('Auth Gate Relogin & SW Breakout Tests', () => {
  describe('Positive: Active Service Worker Registrations', () => {
    it('unregisters all service workers and triggers full page reload', async () => {
      let unregisterCalls = 0;
      let reloadCalls = 0;

      const mockRegistration1: ServiceWorkerRegistrationLike = {
        unregister: async () => {
          unregisterCalls++;
          return true;
        },
      };

      const mockRegistration2: ServiceWorkerRegistrationLike = {
        unregister: async () => {
          unregisterCalls++;
          return true;
        },
      };

      const mockNav: NavigatorLike = {
        serviceWorker: {
          getRegistrations: async () => [mockRegistration1, mockRegistration2],
        },
      };

      const mockLoc: LocationLike = {
        href: 'https://derivee.app/',
        reload: () => {
          reloadCalls++;
        },
      };

      await forceRelogin(mockNav, mockLoc);

      assert.strictEqual(unregisterCalls, 2, 'Must call unregister() on all registrations');
      assert.strictEqual(reloadCalls, 1, 'Must call location.reload() exactly once');
      assert.strictEqual(mockLoc.href, 'https://derivee.app/', 'Href must remain unchanged when reload is used');
    });

    it('works when getRegistrations returns an empty array', async () => {
      let reloadCalls = 0;

      const mockNav: NavigatorLike = {
        serviceWorker: {
          getRegistrations: async () => [],
        },
      };

      const mockLoc: LocationLike = {
        reload: () => {
          reloadCalls++;
        },
      };

      await forceRelogin(mockNav, mockLoc);
      assert.strictEqual(reloadCalls, 1, 'Must call location.reload() even if no SW was registered');
    });
  });

  describe('Negative: Environments Without Service Worker Support', () => {
    it('falls back to cache-busted navigation without throwing when navigator.serviceWorker is undefined', async () => {
      let reloadCalls = 0;
      const mockNav: NavigatorLike = {
        serviceWorker: undefined,
      };

      const mockLoc = {
        href: '/',
        reload: () => {
          reloadCalls++;
        },
      };

      await forceRelogin(mockNav, mockLoc);

      assert.strictEqual(reloadCalls, 0, 'Must NOT call location.reload() in fallback mode');
      assert.match(
        mockLoc.href,
        /^\/\?t=\d+$/,
        'Must navigate to a cache-busted path such as /?t=<timestamp>'
      );
      const timestamp = Number(mockLoc.href.split('=')[1]);
      assert.ok(!Number.isNaN(timestamp) && timestamp > 0, 'Cache buster parameter must be a valid positive timestamp');
    });

    it('falls back to cache-busted navigation when navigator is entirely undefined', async () => {
      let reloadCalls = 0;
      const mockLoc = {
        href: '/',
        reload: () => {
          reloadCalls++;
        },
      };

      await forceRelogin(undefined, mockLoc);

      assert.strictEqual(reloadCalls, 0, 'Must NOT call location.reload()');
      assert.match(mockLoc.href, /^\/\?t=\d+$/);
    });
  });

  describe('Negative: Unregister or Reload Failure Propagation (Not Swallowed)', () => {
    it('surfaces user-visible fallback message path when unregister() rejects and does not swallow the rejection', async () => {
      const mockReg: ServiceWorkerRegistrationLike = {
        unregister: async () => {
          throw new Error('Disk locked or SW unregister denied');
        },
      };

      const mockNav: NavigatorLike = {
        serviceWorker: {
          getRegistrations: async () => [mockReg],
        },
      };

      let reloadCalled = false;
      const mockLoc: LocationLike = {
        reload: () => {
          reloadCalled = true;
        },
      };

      let surfacedMessage: string | null = null;
      const onErrorSpy = (msg: string) => {
        surfacedMessage = msg;
      };

      // Must reject (not swallowed)
      await assert.rejects(
        async () => {
          await forceRelogin(mockNav, mockLoc, onErrorSpy);
        },
        /Disk locked or SW unregister denied/
      );

      assert.strictEqual(
        surfacedMessage,
        RELOGIN_FALLBACK_MESSAGE,
        'Must surface the user-visible fallback message via onError handler'
      );
      assert.strictEqual(reloadCalled, false, 'location.reload() must not be called after unregister rejection');
    });

    it('surfaces user-visible fallback message path when getRegistrations() rejects', async () => {
      const mockNav: NavigatorLike = {
        serviceWorker: {
          getRegistrations: async () => {
            throw new Error('SecurityError: Access to Storage is denied');
          },
        },
      };

      const mockLoc: LocationLike = {
        reload: () => {},
      };

      let surfacedMessage: string | null = null;
      await assert.rejects(
        async () => {
          await forceRelogin(mockNav, mockLoc, (msg) => {
            surfacedMessage = msg;
          });
        },
        /SecurityError/
      );

      assert.strictEqual(surfacedMessage, RELOGIN_FALLBACK_MESSAGE);
    });

    it('surfaces user-visible fallback message path when location.reload() throws', async () => {
      const mockNav: NavigatorLike = {
        serviceWorker: {
          getRegistrations: async () => [],
        },
      };

      const mockLoc: LocationLike = {
        reload: () => {
          throw new Error('Blocked cross-frame reload');
        },
      };

      let surfacedMessage: string | null = null;
      await assert.rejects(
        async () => {
          await forceRelogin(mockNav, mockLoc, (msg) => {
            surfacedMessage = msg;
          });
        },
        /Blocked cross-frame reload/
      );

      assert.strictEqual(surfacedMessage, RELOGIN_FALLBACK_MESSAGE);
    });
  });

  describe('UI Message Compliance', () => {
    it('fallback message contains clear instructions to clear browser cache and reload', () => {
      const lower = RELOGIN_FALLBACK_MESSAGE.toLowerCase();
      assert.ok(
        lower.includes('clear') && lower.includes('reload'),
        'Message must instruct user to clear cache and reload'
      );
      assert.ok(
        !lower.includes('error:'),
        'Message must not contain raw "error:" prefix'
      );
      assert.ok(
        !lower.includes('pmtiles') && !lower.includes('opfs') && !lower.includes('wasm'),
        'Message must not leak internal tokens'
      );
    });
  });
});
