import { describe, it, before, after } from 'node:test';
import assert from 'node:assert';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { Miniflare, convertV4MiniflareOptions } from 'miniflare';
import { transit_realtime } from '../src/proto/gtfs-realtime.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const FIXTURE_L_PATH = path.join(__dirname, 'fixtures', 'gtfs-l.proto.bin');
const RAW_FIXTURE_L_BUFFER = fs.readFileSync(FIXTURE_L_PATH);

/**
 * Creates a dynamic GTFS-RT protobuf fixture buffer whose timestamps
 * are shifted so that the latest arrival times align with the current time.
 */
function createFreshFixtureBuffer(targetEpoch: number = Math.floor(Date.now() / 1000)): Uint8Array {
  const feed = transit_realtime.FeedMessage.decode(new Uint8Array(RAW_FIXTURE_L_BUFFER));
  const headerEpoch = Number(feed.header.timestamp?.low ?? feed.header.timestamp ?? 0);
  const offset = targetEpoch - headerEpoch;

  if (feed.header.timestamp) {
    feed.header.timestamp = targetEpoch as any;
  }

  for (const entity of feed.entity) {
    if (entity.tripUpdate?.stopTimeUpdate) {
      for (const stu of entity.tripUpdate.stopTimeUpdate) {
        if (stu.arrival?.time) {
          const currentArrival = Number(stu.arrival.time.low ?? stu.arrival.time);
          stu.arrival.time = (currentArrival + offset) as any;
        }
        if (stu.departure?.time) {
          const currentDep = Number(stu.departure.time.low ?? stu.departure.time);
          stu.departure.time = (currentDep + offset) as any;
        }
      }
    }
  }

  return transit_realtime.FeedMessage.encode(feed).finish();
}

describe('Worker Realtime Arrivals (M7a) with Miniflare KV', async () => {
  const { fetchFeeds, getArrivalsForStop } = await import('../src/gtfs.js');
  const worker = (await import('../src/index.js')).default;

  let mf: Miniflare;
  let kv: KVNamespace;
  const originalFetch = global.fetch;

  before(async () => {
    mf = new Miniflare(
      convertV4MiniflareOptions({
        modules: true,
        script: 'export default { fetch() { return new Response("miniflare-kv-host"); } }',
        kvNamespaces: ['KV_REALTIME'],
      })
    );
    kv = (await mf.getKVNamespace('KV_REALTIME')) as unknown as KVNamespace;
  });

  after(async () => {
    global.fetch = originalFetch;
    await mf.dispose();
  });

  it('ingests GTFS-RT fixture into Miniflare KV with sane TTL (120s) and isolates failing feeds', async () => {
    const now = Math.floor(Date.now() / 1000);
    const freshFixture = createFreshFixtureBuffer(now);

    let capturedPutOptions: any = null;
    const kvProxy = new Proxy(kv, {
      get(target, prop, receiver) {
        if (prop === 'put') {
          return async (...args: any[]) => {
            capturedPutOptions = args[2];
            return (target as any).put(...args);
          };
        }
        return Reflect.get(target, prop, receiver);
      },
    });

    global.fetch = async (url: string | URL | Request) => {
      const urlStr = url.toString();
      if (urlStr.includes('gtfs-l')) {
        return new Response(freshFixture, {
          status: 200,
          headers: { 'Content-Type': 'application/octet-stream' },
        });
      }
      return new Response('Internal Server Error', { status: 500 });
    };

    await fetchFeeds(kvProxy, {
      now,
      ttl: 120,
      feeds: [
        'https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/nyct%2Fgtfs-l',
        'https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/nyct%2Fgtfs-failing',
      ],
    });

    // Verify sane TTL was passed to KV put
    assert.ok(capturedPutOptions, 'kv.put must be called');
    assert.strictEqual(capturedPutOptions.expirationTtl, 120, 'TTL must be 120 seconds');

    // Key 'stops-L' should exist in Miniflare KV
    const lStops = (await kv.get('stops-L', 'json')) as Record<string, any>;
    assert.ok(lStops, 'stops-L should be written to Miniflare KV');
    assert.ok(Object.keys(lStops).length > 0, 'Should contain L line stops');

    // Verify L01 arrivals
    const stopData = await getArrivalsForStop(kv, 'L01');
    assert.ok(stopData, 'L01 stop data must be found');
    assert.strictEqual(stopData.stop_id, 'L01');
    assert.ok(stopData.arrivals.length > 0, 'Must have arrival predictions');
    assert.strictEqual(stopData.arrivals[0].route_id, 'L');
    assert.ok(['NORTH', 'SOUTH'].includes(stopData.arrivals[0].direction));
    assert.strictEqual(stopData.arrivals[0].is_realtime, true);

    // Verify predictions are sorted ascending
    for (let i = 1; i < stopData.arrivals.length; i++) {
      assert.ok(
        stopData.arrivals[i].predicted_arrival_epoch >= stopData.arrivals[i - 1].predicted_arrival_epoch,
        'Arrivals must be sorted ascending by epoch'
      );
    }
  });

  it('serves fresh arrivals via /api/realtime/arrivals endpoint with stop_id and stop params', async () => {
    const env = { KV_REALTIME: kv } as any;

    // Test with stop_id parameter
    const req1 = new Request('http://localhost/api/realtime/arrivals?stop_id=L01');
    const res1 = await worker.fetch(req1, env);
    assert.strictEqual(res1.status, 200);
    assert.strictEqual(res1.headers.get('Content-Type'), 'application/json');
    assert.ok(res1.headers.get('Cache-Control')?.includes('max-age=15'));
    const body1 = (await res1.json()) as any;
    assert.strictEqual(body1.stop_id, 'L01');
    assert.ok(body1.arrivals.length > 0);

    // Test with backward-compatible stop parameter
    const req2 = new Request('http://localhost/api/realtime/arrivals?stop=L01');
    const res2 = await worker.fetch(req2, env);
    assert.strictEqual(res2.status, 200);
    const body2 = (await res2.json()) as any;
    assert.strictEqual(body2.stop_id, 'L01');

    // Test platform stop ID direction filtering (e.g. L01N)
    const req3 = new Request('http://localhost/api/realtime/arrivals?stop_id=L01N');
    const res3 = await worker.fetch(req3, env);
    assert.strictEqual(res3.status, 200);
    const body3 = (await res3.json()) as any;
    assert.strictEqual(body3.stop_id, 'L01N');
    for (const arr of body3.arrivals) {
      assert.strictEqual(arr.direction, 'NORTH');
    }
  });

  it('handles TTL expiry and cache staleness', async () => {
    const env = { KV_REALTIME: kv } as any;

    // 1. Stale cache: when data in KV is older than 120s TTL window, endpoint returns 503 stale
    const staleTimestamp = Math.floor(Date.now() / 1000) - 150;
    await kv.put('stops-L', JSON.stringify({
      L01: {
        stop_id: 'L01',
        updated_at: staleTimestamp,
        arrivals: [{ route_id: 'L', direction: 'NORTH', headsign: '', predicted_arrival_epoch: staleTimestamp + 20, is_realtime: true }],
      },
    }));

    const staleReq = new Request('http://localhost/api/realtime/arrivals?stop_id=L01');
    const staleRes = await worker.fetch(staleReq, env);
    assert.strictEqual(staleRes.status, 503);
    const staleBody = (await staleRes.json()) as any;
    assert.strictEqual(staleBody.stale, true);

    // 2. Key eviction/expiration: when key is evicted or expired from KV, getArrivalsForStop returns null
    await kv.delete('stops-L');
    const evicted = await getArrivalsForStop(kv, 'L01');
    assert.strictEqual(evicted, null, 'Evicted or expired KV key must return null');

    // Endpoint returns 404 when key is expired/missing from KV
    const missingRes = await worker.fetch(staleReq, env);
    assert.strictEqual(missingRes.status, 404);
  });

  it('returns 404 for unknown stop', async () => {
    const env = { KV_REALTIME: kv } as any;
    const req = new Request('http://localhost/api/realtime/arrivals?stop_id=X99');
    const res = await worker.fetch(req, env);
    assert.strictEqual(res.status, 404);
    const body = (await res.json()) as any;
    assert.strictEqual(body.error, 'not_found');
  });

  it('returns 400 for missing stop param', async () => {
    const env = { KV_REALTIME: kv } as any;
    const req = new Request('http://localhost/api/realtime/arrivals');
    const res = await worker.fetch(req, env);
    assert.strictEqual(res.status, 400);
    const body = (await res.json()) as any;
    assert.strictEqual(body.error, 'missing_stop');
  });

  it('returns 503 when KV binding is unconfigured', async () => {
    const env = {} as any;
    const req = new Request('http://localhost/api/realtime/arrivals?stop_id=L01');
    const res = await worker.fetch(req, env);
    assert.strictEqual(res.status, 503);
    const body = (await res.json()) as any;
    assert.strictEqual(body.error, 'kv_not_configured');
  });

  it('handles malformed feed without crashing and preserves cache (negative case)', async () => {
    const now = Math.floor(Date.now() / 1000);
    const freshFixture = createFreshFixtureBuffer(now);

    // Prime cache with valid data first
    await fetchFeeds(kv, {
      now,
      ttl: 120,
      feeds: ['https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/nyct%2Fgtfs-l'],
    });
    assert.ok(await getArrivalsForStop(kv, 'L01'));

    // Simulate corrupted binary response from MTA
    global.fetch = async () => {
      return new Response(Buffer.from('corrupted non-protobuf binary content'), {
        status: 200,
        headers: { 'Content-Type': 'application/octet-stream' },
      });
    };

    // fetchFeeds should catch and swallow malformed protobuf decode error
    await assert.doesNotReject(async () => {
      await fetchFeeds(kv, {
        now,
        feeds: ['https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/nyct%2Fgtfs-malformed'],
      });
    });

    // Existing cache should not be overwritten with empty data
    const cachedAfterMalformed = await getArrivalsForStop(kv, 'L01');
    assert.ok(cachedAfterMalformed, 'Existing cache must remain intact when feed is malformed');
  });

  it('performs end-to-end miniflare flow: cron ingestion tick -> arrivals query', async () => {
    const now = Math.floor(Date.now() / 1000);
    const freshFixture = createFreshFixtureBuffer(now);

    global.fetch = async (url: string | URL | Request) => {
      const urlStr = url.toString();
      if (urlStr.includes('gtfs-l')) {
        return new Response(freshFixture, {
          status: 200,
          headers: { 'Content-Type': 'application/octet-stream' },
        });
      }
      return new Response('Not Found', { status: 404 });
    };

    const env = { KV_REALTIME: kv } as any;
    const scheduledPromises: Promise<any>[] = [];
    const ctx = {
      waitUntil(promise: Promise<any>) {
        scheduledPromises.push(promise);
      },
    } as any;

    // Trigger scheduled handler directly to simulate Cloudflare cron tick
    await worker.scheduled({} as any, env, ctx);
    await Promise.all(scheduledPromises);

    // Query endpoint
    const req = new Request('http://localhost/api/realtime/arrivals?stop_id=L01');
    const res = await worker.fetch(req, env);
    assert.strictEqual(res.status, 200);
    const data = (await res.json()) as any;
    assert.strictEqual(data.stop_id, 'L01');
    assert.ok(data.arrivals.length > 0);
    assert.strictEqual(data.arrivals[0].route_id, 'L');
  });
});
