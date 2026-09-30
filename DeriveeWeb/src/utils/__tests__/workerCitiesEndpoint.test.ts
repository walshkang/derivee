import { describe, it } from 'node:test';
import assert from 'node:assert';
import worker from '../../../workers/derivee-api/src/index.ts';

describe('Worker /api/cities & /api/pack Endpoint Tests', () => {
  const allowedOrigin = 'https://derivee.app';

  function createMockEnv(overrides?: Partial<any>) {
    return {
      PACK: {
        get: async (key: string) => {
          if (key === 'cities.json') {
            return {
              body: JSON.stringify([
                {
                  slug: 'nyc',
                  name: 'New York City',
                  pack_bytes: 29688421,
                  version: '2.0.0',
                  bbox: [-74.25, 40.49, -73.7, 40.91],
                },
              ]),
              size: 150,
              httpEtag: '"test-etag-123"',
            };
          }
          if (key === 'city-bos.pack.zst') {
            return {
              body: 'mock-bos-pack-bytes',
              size: 19,
              httpEtag: '"bos-etag"',
            };
          }
          return null;
        },
        ...overrides?.PACK,
      },
      RATE_LIMITER: overrides?.RATE_LIMITER || {
        limit: async () => ({ success: true }),
      },
      ...overrides,
    };
  }

  describe('GET /api/cities Authentication & Rate Limiting', () => {
    it('returns 401 when Cloudflare Access email header is missing', async () => {
      const req = new Request('https://derivee-api.walsh-8de.workers.dev/api/cities', {
        method: 'GET',
        headers: { Origin: allowedOrigin },
      });
      const env = createMockEnv();
      const res = await worker.fetch(req, env as any);

      assert.strictEqual(res.status, 401);
      const data = await res.json() as any;
      assert.strictEqual(data.error, 'unauthorized');
    });

    it('returns 429 when rate limit is exceeded', async () => {
      const req = new Request('https://derivee-api.walsh-8de.workers.dev/api/cities', {
        method: 'GET',
        headers: {
          Origin: allowedOrigin,
          'cf-access-authenticated-user-email': 'tester@derivee.app',
        },
      });
      const env = createMockEnv({
        RATE_LIMITER: {
          limit: async () => ({ success: false }),
        },
      });
      const res = await worker.fetch(req, env as any);

      assert.strictEqual(res.status, 429);
      assert.strictEqual(res.headers.get('Retry-After'), '60');
      const data = await res.json() as any;
      assert.strictEqual(data.error, 'rate_limited');
    });
  });

  describe('GET /api/cities R2 Manifest Streaming', () => {
    it('returns 404 when cities.json is missing in R2 bucket', async () => {
      const req = new Request('https://derivee-api.walsh-8de.workers.dev/api/cities', {
        method: 'GET',
        headers: {
          Origin: allowedOrigin,
          'cf-access-authenticated-user-email': 'tester@derivee.app',
        },
      });
      const env = createMockEnv({
        PACK: {
          get: async () => null, // Not found
        },
      });
      const res = await worker.fetch(req, env as any);

      assert.strictEqual(res.status, 404);
      const data = await res.json() as any;
      assert.strictEqual(data.error, 'not_found');
    });

    it('streams cities.json directly from R2 bucket on authenticated request', async () => {
      const req = new Request('https://derivee-api.walsh-8de.workers.dev/api/cities', {
        method: 'GET',
        headers: {
          Origin: allowedOrigin,
          'cf-access-authenticated-user-email': 'tester@derivee.app',
        },
      });
      const env = createMockEnv();
      const res = await worker.fetch(req, env as any);

      assert.strictEqual(res.status, 200);
      assert.strictEqual(res.headers.get('Content-Type'), 'application/json');
      assert.strictEqual(res.headers.get('Cache-Control'), 'no-store');
      assert.strictEqual(res.headers.get('ETag'), '"test-etag-123"');
      assert.strictEqual(res.headers.get('Access-Control-Allow-Origin'), allowedOrigin);

      const raw = await res.text();
      assert.ok(raw.includes('New York City'));
    });

    it('handles OPTIONS preflight for /api/cities', async () => {
      const req = new Request('https://derivee-api.walsh-8de.workers.dev/api/cities', {
        method: 'OPTIONS',
        headers: { Origin: allowedOrigin },
      });
      const env = createMockEnv();
      const res = await worker.fetch(req, env as any);

      assert.strictEqual(res.status, 204);
      assert.strictEqual(res.headers.get('Access-Control-Allow-Origin'), allowedOrigin);
      assert.ok(res.headers.get('Access-Control-Allow-Methods')?.includes('GET'));
    });
  });

  describe('GET /api/pack dynamic city parameter support', () => {
    it('queries city-specific pack key when city query param is supplied', async () => {
      const req = new Request('https://derivee-api.walsh-8de.workers.dev/api/pack?city=bos', {
        method: 'GET',
        headers: {
          Origin: allowedOrigin,
          'cf-access-authenticated-user-email': 'tester@derivee.app',
        },
      });
      const env = createMockEnv();
      const res = await worker.fetch(req, env as any);

      assert.strictEqual(res.status, 200);
      assert.strictEqual(res.headers.get('Content-Type'), 'application/zstd');
      assert.strictEqual(
        res.headers.get('Content-Disposition'),
        'attachment; filename="city-bos.pack.zst"'
      );
      assert.strictEqual(await res.text(), 'mock-bos-pack-bytes');
    });
  });
});
