import { describe, it, beforeEach } from 'node:test';
import assert from 'node:assert';
import {
  isPackUpdateAvailable,
  getTrackedCityPackVersions,
  getTrackedCityPackVersion,
  setTrackedCityPackVersion,
  fetchPackInfo,
  LOCAL_STORAGE_CITY_VERSIONS_KEY,
  type PackInfo,
} from '../packUpdates.ts';

// Setup minimal localStorage mock for Node test environment
const mockStorage = new Map<string, string>();
const localStorageMock = {
  getItem: (key: string) => mockStorage.get(key) ?? null,
  setItem: (key: string, val: string) => { mockStorage.set(key, String(val)); },
  removeItem: (key: string) => { mockStorage.delete(key); },
  clear: () => { mockStorage.clear(); },
};

(globalThis as any).localStorage = localStorageMock;

describe('Pack Updates Utility (packUpdates.ts)', () => {
  beforeEach(() => {
    mockStorage.clear();
  });

  describe('isPackUpdateAvailable - Version Comparison Logic', () => {
    const validServerInfo: PackInfo = {
      version: 4,
      size: 29684406,
      updated_at: '2026-10-03T12:00:00.000Z',
    };

    it('returns true when server version is strictly newer than installed version', () => {
      assert.strictEqual(isPackUpdateAvailable(3, validServerInfo), true);
      assert.strictEqual(isPackUpdateAvailable(1, validServerInfo), true);
    });

    it('returns false when server version is identical to installed version (negative case)', () => {
      assert.strictEqual(isPackUpdateAvailable(4, validServerInfo), false);
    });

    it('returns false when server version is older than installed version (negative case)', () => {
      assert.strictEqual(isPackUpdateAvailable(5, validServerInfo), false);
    });

    it('returns false when serverInfo is null or undefined (negative case)', () => {
      assert.strictEqual(isPackUpdateAvailable(3, null), false);
      assert.strictEqual(isPackUpdateAvailable(3, undefined), false);
    });

    it('returns false when serverInfo is missing version or has non-number version (negative case)', () => {
      assert.strictEqual(isPackUpdateAvailable(3, {} as any), false);
      assert.strictEqual(isPackUpdateAvailable(3, { version: '4', size: 1000, updated_at: 'now' } as any), false);
      assert.strictEqual(isPackUpdateAvailable(3, { version: NaN, size: 1000, updated_at: 'now' } as any), false);
      assert.strictEqual(isPackUpdateAvailable(3, { version: -1, size: 1000, updated_at: 'now' } as any), false);
      assert.strictEqual(isPackUpdateAvailable(3, { version: 0, size: 1000, updated_at: 'now' } as any), false);
    });

    it('returns false when serverInfo has zero, negative, or invalid size (negative sanity check)', () => {
      assert.strictEqual(isPackUpdateAvailable(3, { version: 4, size: 0, updated_at: 'now' }), false);
      assert.strictEqual(isPackUpdateAvailable(3, { version: 4, size: -100, updated_at: 'now' }), false);
      assert.strictEqual(isPackUpdateAvailable(3, { version: 4, size: NaN, updated_at: 'now' }), false);
      assert.strictEqual(isPackUpdateAvailable(3, { version: 4, updated_at: 'now' } as any), false);
    });

    it('returns false when installedVersion is NaN or invalid (negative case)', () => {
      assert.strictEqual(isPackUpdateAvailable(NaN, validServerInfo), false);
      assert.strictEqual(isPackUpdateAvailable(null as any, validServerInfo), false);
    });
  });

  describe('Per-City Keyed Version Tracking', () => {
    it('returns empty record when no versions are stored', () => {
      assert.deepStrictEqual(getTrackedCityPackVersions(), {});
      assert.strictEqual(getTrackedCityPackVersion('nyc'), null);
    });

    it('tracks versions independently per city', () => {
      setTrackedCityPackVersion('nyc', 4);
      assert.strictEqual(getTrackedCityPackVersion('nyc'), 4);
      assert.strictEqual(getTrackedCityPackVersion('bos'), null);

      setTrackedCityPackVersion('bos', 2);
      assert.strictEqual(getTrackedCityPackVersion('nyc'), 4);
      assert.strictEqual(getTrackedCityPackVersion('bos'), 2);

      const all = getTrackedCityPackVersions();
      assert.deepStrictEqual(all, { nyc: 4, bos: 2 });
    });

    it('updates version for an existing city without affecting other cities', () => {
      setTrackedCityPackVersion('nyc', 3);
      setTrackedCityPackVersion('bos', 1);

      setTrackedCityPackVersion('nyc', 4);
      assert.strictEqual(getTrackedCityPackVersion('nyc'), 4);
      assert.strictEqual(getTrackedCityPackVersion('bos'), 1);
    });

    it('handles corrupted localStorage JSON gracefully (negative case)', () => {
      localStorage.setItem(LOCAL_STORAGE_CITY_VERSIONS_KEY, '{ invalid json');
      assert.deepStrictEqual(getTrackedCityPackVersions(), {});
      assert.strictEqual(getTrackedCityPackVersion('nyc'), null);

      // Can overwrite corrupted storage safely
      setTrackedCityPackVersion('nyc', 4);
      assert.strictEqual(getTrackedCityPackVersion('nyc'), 4);
    });
  });

  describe('fetchPackInfo', () => {
    const originalFetch = globalThis.fetch;

    it('returns parsed PackInfo on HTTP 200 with valid json', async () => {
      (globalThis as any).fetch = async (url: string) => {
        assert.ok(url.includes('city=nyc'));
        return {
          ok: true,
          status: 200,
          json: async () => ({
            version: 4,
            size: 29684406,
            updated_at: '2026-10-03T12:00:00.000Z',
          }),
        };
      };

      const info = await fetchPackInfo('nyc');
      assert.ok(info);
      assert.strictEqual(info?.version, 4);
      assert.strictEqual(info?.size, 29684406);
      assert.strictEqual(info?.updated_at, '2026-10-03T12:00:00.000Z');
    });

    it('returns null on non-200 HTTP response (negative case)', async () => {
      (globalThis as any).fetch = async () => ({
        ok: false,
        status: 404,
      });

      const info = await fetchPackInfo('unknown');
      assert.strictEqual(info, null);
    });

    it('returns null on malformed response body (negative case)', async () => {
      (globalThis as any).fetch = async () => ({
        ok: true,
        status: 200,
        json: async () => ({ version: 'not-a-number' }),
      });

      const info = await fetchPackInfo('nyc');
      assert.strictEqual(info, null);
    });

    it('cleans up global fetch mock', () => {
      (globalThis as any).fetch = originalFetch;
    });
  });
});
