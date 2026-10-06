import { describe, it } from 'node:test';
import assert from 'node:assert';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { workboxConfig } from '../../../vite.config.ts';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const DIST_SW_PATH = path.resolve(__dirname, '../../../dist/sw.js');

describe('PWA Workbox Navigation Configuration', () => {
  describe('Positive: NetworkFirst navigation route', () => {
    it('declares runtimeCaching with a NetworkFirst handler for navigations', () => {
      const config = workboxConfig as any;
      assert.ok(
        Array.isArray(config.runtimeCaching),
        'workbox.runtimeCaching must be an array'
      );

      const navEntry = config.runtimeCaching.find((entry: any) => {
        const handlerMatches =
          typeof entry.handler === 'string' &&
          entry.handler.toLowerCase() === 'networkfirst';

        if (!handlerMatches) return false;

        // Check if urlPattern matches navigations
        if (typeof entry.urlPattern === 'function') {
          return Boolean(
            entry.urlPattern({
              request: { mode: 'navigate' },
              url: new URL('https://derivee.app/'),
            })
          );
        }
        return false;
      });

      assert.ok(
        navEntry,
        'Must contain a runtimeCaching entry with NetworkFirst handler matching navigations'
      );

      // Verify options
      assert.strictEqual(
        navEntry.options?.cacheName,
        'navigations',
        "Navigation cacheName should be 'navigations'"
      );
      assert.ok(
        typeof navEntry.options?.networkTimeoutSeconds === 'number' &&
          navEntry.options.networkTimeoutSeconds > 0 &&
          navEntry.options.networkTimeoutSeconds <= 10,
        'Must specify a short networkTimeoutSeconds (positive number <= 10s)'
      );
      assert.ok(
        navEntry.options?.expiration?.maxEntries !== undefined ||
          navEntry.options?.expiration?.maxAgeSeconds !== undefined,
        'Must specify bounded expiration (maxEntries and/or maxAgeSeconds)'
      );
    });

    it('navigation matcher correctly discriminates navigation mode from subresource requests', () => {
      const config = workboxConfig as any;
      const navEntry = config.runtimeCaching?.find(
        (entry: any) =>
          typeof entry.handler === 'string' &&
          entry.handler.toLowerCase() === 'networkfirst'
      );

      assert.ok(navEntry, 'NetworkFirst entry must exist to test matcher discrimination');
      assert.strictEqual(
        typeof navEntry.urlPattern,
        'function',
        'urlPattern must be a matcher function'
      );

      // Positive case: navigation mode
      const navMatch = navEntry.urlPattern({
        request: { mode: 'navigate' },
        url: new URL('https://derivee.app/'),
      });
      assert.strictEqual(Boolean(navMatch), true, 'Must match navigate requests');

      // Negative case: non-navigation subresource modes (cors, no-cors, etc.)
      const corsMatch = navEntry.urlPattern({
        request: { mode: 'cors' },
        url: new URL('https://derivee.app/assets/index.js'),
      });
      assert.strictEqual(Boolean(corsMatch), false, 'Must NOT match cors subresource requests');

      const fetchMatch = navEntry.urlPattern({
        request: { mode: 'same-origin' },
        url: new URL('https://derivee.app/api/me'),
      });
      assert.strictEqual(Boolean(fetchMatch), false, 'Must NOT match standard fetch/same-origin requests');
    });

    it('ensures /api/* remains uncached with no caching rules matching it', () => {
      const config = workboxConfig as any;
      const entries = config.runtimeCaching || [];

      // No entry should explicitly target /api routes
      const apiEntry = entries.find((entry: any) => {
        if (entry.urlPattern instanceof RegExp) {
          return entry.urlPattern.test('/api/me') || entry.urlPattern.test('https://derivee.app/api/me');
        }
        if (typeof entry.urlPattern === 'string') {
          return entry.urlPattern.includes('/api');
        }
        return false;
      });

      assert.strictEqual(
        apiEntry,
        undefined,
        '/api/* must remain uncached with zero runtimeCaching rules matching it'
      );

      // And navigation rule should also exclude /api navigations
      const navEntry = entries.find(
        (entry: any) =>
          typeof entry.handler === 'string' &&
          entry.handler.toLowerCase() === 'networkfirst'
      );
      if (navEntry && typeof navEntry.urlPattern === 'function') {
        const apiNavMatch = navEntry.urlPattern({
          request: { mode: 'navigate' },
          url: new URL('https://derivee.app/api/me'),
        });
        assert.strictEqual(
          Boolean(apiNavMatch),
          false,
          'Navigation rule must not match /api/* navigations'
        );
      }
    });
  });

  describe('Negative: precache navigateFallback removal', () => {
    it('asserts navigateFallback is unset / absent from workbox options', () => {
      const config = workboxConfig as any;
      assert.ok(
        config.navigateFallback == null,
        `navigateFallback must be null or undefined (unset/absent), got: ${config.navigateFallback}`
      );
    });

    it('asserts navigateFallbackDenylist is unset / absent from workbox options', () => {
      const config = workboxConfig as any;
      assert.strictEqual(
        config.navigateFallbackDenylist,
        undefined,
        'navigateFallbackDenylist must be unset/absent'
      );
      assert.ok(
        !('navigateFallbackDenylist' in config),
        "'navigateFallbackDenylist' key must not be present in workbox config"
      );
    });
  });

  describe('Generated dist/sw.js contract inspection', () => {
    it('confirms dist/sw.js registers NetworkFirst for navigations and contains NO createHandlerBoundToURL', () => {
      if (!fs.existsSync(DIST_SW_PATH)) {
        // Only verify artifact contract if dist/sw.js exists
        return;
      }

      const swContent = fs.readFileSync(DIST_SW_PATH, 'utf8');

      // (a) Must register a NetworkFirst-based route for navigations
      assert.ok(
        swContent.includes('NetworkFirst'),
        'dist/sw.js must register a NetworkFirst handler'
      );
      assert.ok(
        swContent.includes('navigations'),
        "dist/sw.js must use cacheName 'navigations'"
      );
      assert.ok(
        swContent.includes('"navigate"===') || swContent.includes('mode==="navigate"') || swContent.includes("mode==='navigate'"),
        'dist/sw.js must match navigate requests'
      );

      // (b) Must contain NO precache-bound NavigationRoute
      assert.ok(
        !swContent.includes('createHandlerBoundToURL'),
        'dist/sw.js must contain NO createHandlerBoundToURL call'
      );
      assert.ok(
        !swContent.includes('NavigationRoute'),
        'dist/sw.js must contain NO NavigationRoute registration'
      );
    });
  });
});
