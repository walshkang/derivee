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

/**
 * Creates an empty GTFS-RT feed (0 entities) with valid header.
 */
function createEmptyFeedBuffer(targetEpoch: number = Math.floor(Date.now() / 1000)): Uint8Array {
  const feed = transit_realtime.FeedMessage.create({
    header: {
      gtfsRealtimeVersion: '2.0',
      timestamp: targetEpoch as any,
    },
    entity: [],
  });
  return transit_realtime.FeedMessage.encode(feed).finish();
}

describe('Worker Realtime On-Demand Arrivals (Zero KV, Live GTFS-RT)', async () => {
  const { getLiveArrivalsForStop, getFeedUrlsForStop } = await import('../src/gtfs.ts');
  const worker = (await import('../src/index.ts')).default;

  let mf: Miniflare;
  const originalFetch = global.fetch;

  before(async () => {
    mf = new Miniflare(
      convertV4MiniflareOptions({
        modules: true,
        script: 'export default { fetch() { return new Response("miniflare-host"); } }',
      })
    );
    (globalThis as any).caches = await mf.getCaches();
  });

  after(async () => {
    global.fetch = originalFetch;
    delete (globalThis as any).caches;
    await mf.dispose();
  });

  it('resolves relevant MTA feed URLs based on stop_id prefix or route_id', () => {
    // 1-7, 9 lines
    assert.deepStrictEqual(getFeedUrlsForStop('101'), ['https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/nyct%2Fgtfs']);
    assert.deepStrictEqual(getFeedUrlsForStop('725N'), ['https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/nyct%2Fgtfs']);
    // ACE
    assert.deepStrictEqual(getFeedUrlsForStop('A34N'), ['https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/nyct%2Fgtfs-ace']);
    // BDFM
    assert.deepStrictEqual(getFeedUrlsForStop('D28'), ['https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/nyct%2Fgtfs-bdfm']);
    // G
    assert.deepStrictEqual(getFeedUrlsForStop('G30'), ['https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/nyct%2Fgtfs-g']);
    // JZ
    assert.deepStrictEqual(getFeedUrlsForStop('J28S'), ['https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/nyct%2Fgtfs-jz']);
    assert.deepStrictEqual(getFeedUrlsForStop('M20S'), [
      'https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/nyct%2Fgtfs-jz',
      'https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/nyct%2Fgtfs-bdfm',
    ]);
    // L
    assert.deepStrictEqual(getFeedUrlsForStop('L01'), ['https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/nyct%2Fgtfs-l']);
    // NQRW
    assert.deepStrictEqual(getFeedUrlsForStop('R23S'), ['https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/nyct%2Fgtfs-nqrw']);
    assert.deepStrictEqual(getFeedUrlsForStop('Q01N'), ['https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/nyct%2Fgtfs-nqrw']);
    // Route ID override
    assert.deepStrictEqual(getFeedUrlsForStop('1288', 'Q'), ['https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/nyct%2Fgtfs-nqrw']);
  });

  it('arrivals returned for a stop: serves live predictions with minutesAway on-demand (zero KV)', async () => {
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

    const env = {} as any; // ZERO KV binding

    // 1. Query with stop_id=L01
    const req1 = new Request('http://localhost/api/realtime/arrivals?stop_id=L01');
    const res1 = await worker.fetch(req1, env);
    assert.strictEqual(res1.status, 200);
    assert.strictEqual(res1.headers.get('Content-Type'), 'application/json');
    assert.ok(res1.headers.get('Cache-Control')?.includes('max-age=15'));

    const body1 = (await res1.json()) as any;
    assert.strictEqual(body1.stop_id, 'L01');
    assert.ok(body1.arrivals.length > 0, 'Must have arrival predictions');
    assert.strictEqual(body1.arrivals[0].route_id, 'L');
    assert.strictEqual(body1.arrivals[0].is_realtime, true);
    assert.strictEqual(typeof body1.arrivals[0].minutesAway, 'number');
    assert.ok(body1.arrivals[0].minutesAway >= 0);

    // 2. Query with platform direction stop_id=L01N
    const req2 = new Request('http://localhost/api/realtime/arrivals?stop_id=L01N');
    const res2 = await worker.fetch(req2, env);
    assert.strictEqual(res2.status, 200);
    const body2 = (await res2.json()) as any;
    assert.strictEqual(body2.stop_id, 'L01N');
    assert.ok(body2.arrivals.length > 0);
    for (const arr of body2.arrivals) {
      assert.strictEqual(arr.direction, 'NORTH');
    }

    // 3. Backward-compatible ?stop=L01
    const req3 = new Request('http://localhost/api/realtime/arrivals?stop=L01');
    const res3 = await worker.fetch(req3, env);
    assert.strictEqual(res3.status, 200);
    const body3 = (await res3.json()) as any;
    assert.strictEqual(body3.stop_id, 'L01');
  });

  it('empty feed → empty arrivals: returns 200 with empty arrivals array', async () => {
    const emptyFeed = createEmptyFeedBuffer();

    global.fetch = async (url: string | URL | Request) => {
      const urlStr = url.toString();
      if (urlStr.includes('gtfs-g')) {
        return new Response(emptyFeed, {
          status: 200,
          headers: { 'Content-Type': 'application/octet-stream' },
        });
      }
      return new Response('Not Found', { status: 404 });
    };

    const env = {} as any;
    const req = new Request('http://localhost/api/realtime/arrivals?stop_id=G30');
    const res = await worker.fetch(req, env);
    assert.strictEqual(res.status, 200);

    const body = (await res.json()) as any;
    assert.strictEqual(body.stop_id, 'G30');
    assert.ok(Array.isArray(body.arrivals));
    assert.strictEqual(body.arrivals.length, 0);
  });

  it('feed fetch failure → clean error: returns 503 feed_unavailable when MTA fails', async () => {
    global.fetch = async () => {
      return new Response('Internal Server Error', { status: 500 });
    };

    const env = {} as any;
    // Using J line stop to avoid any cached L feed
    const req = new Request('http://localhost/api/realtime/arrivals?stop_id=J20');
    const res = await worker.fetch(req, env);
    assert.strictEqual(res.status, 503);

    const body = (await res.json()) as any;
    assert.strictEqual(body.error, 'feed_unavailable');
  });

  it('cache hit → no second fetch: caches raw feed in Cache API within TTL window', async () => {
    const now = Math.floor(Date.now() / 1000);
    const freshFixture = createFreshFixtureBuffer(now);
    let fetchCount = 0;

    global.fetch = async (url: string | URL | Request) => {
      const urlStr = url.toString();
      if (urlStr.includes('gtfs-bdfm')) {
        fetchCount++;
        return new Response(freshFixture, {
          status: 200,
          headers: { 'Content-Type': 'application/octet-stream' },
        });
      }
      return new Response('Not Found', { status: 404 });
    };

    const env = {} as any;

    // 1st request -> triggers network fetch
    const req1 = new Request('http://localhost/api/realtime/arrivals?stop_id=D28');
    const res1 = await worker.fetch(req1, env);
    assert.strictEqual(res1.status, 200);
    assert.strictEqual(fetchCount, 1, 'First request must fetch feed from MTA');

    // 2nd request -> served from Cache API without secondary fetch
    const req2 = new Request('http://localhost/api/realtime/arrivals?stop_id=D28');
    const res2 = await worker.fetch(req2, env);
    assert.strictEqual(res2.status, 200);
    assert.strictEqual(fetchCount, 1, 'Second request within TTL must hit Cache API and NOT fetch again');

    // 3rd request for different stop in same feed (B25 in BDFM feed) -> still served from cached feed!
    const req3 = new Request('http://localhost/api/realtime/arrivals?stop_id=B25');
    const res3 = await worker.fetch(req3, env);
    assert.strictEqual(res3.status, 200);
    assert.strictEqual(fetchCount, 1, 'Request for another stop in same feed must reuse cached raw feed');
  });

  it('no-KV operation: functions fully when env has zero KV namespaces', async () => {
    const env = { PACK: {} } as any; // Strictly zero KV
    assert.strictEqual(env.KV_REALTIME, undefined);

    const req = new Request('http://localhost/api/realtime/arrivals?stop_id=L01');
    const res = await worker.fetch(req, env);
    assert.strictEqual(res.status, 200);
    const body = (await res.json()) as any;
    assert.strictEqual(body.stop_id, 'L01');
  });

  it('returns 400 for missing stop param', async () => {
    const env = {} as any;
    const req = new Request('http://localhost/api/realtime/arrivals');
    const res = await worker.fetch(req, env);
    assert.strictEqual(res.status, 400);
    const body = (await res.json()) as any;
    assert.strictEqual(body.error, 'missing_stop');
  });

  it('handles malformed feed binary cleanly without crashing worker (negative case)', async () => {
    global.fetch = async () => {
      return new Response(Buffer.from('corrupted non-protobuf binary content'), {
        status: 200,
        headers: { 'Content-Type': 'application/octet-stream' },
      });
    };

    const env = {} as any;
    // Use A line stop to hit uncached feed
    const req = new Request('http://localhost/api/realtime/arrivals?stop_id=A34');
    const res = await worker.fetch(req, env);
    assert.strictEqual(res.status, 503);
    const body = (await res.json()) as any;
    assert.strictEqual(body.error, 'feed_unavailable');
  });

  it('latency honesty: on-demand fetch and protobuf parse completes well under 3s', async () => {
    const now = Math.floor(Date.now() / 1000);
    const freshFixture = createFreshFixtureBuffer(now);

    global.fetch = async () => {
      return new Response(freshFixture, {
        status: 200,
        headers: { 'Content-Type': 'application/octet-stream' },
      });
    };

    const durations: number[] = [];
    for (let i = 0; i < 10; i++) {
      const start = performance.now();
      await getLiveArrivalsForStop('L01', {
        now,
        cache: null, // Force uncached parse iteration
      });
      durations.push(performance.now() - start);
    }

    durations.sort((a, b) => a - b);
    const p95 = durations[Math.floor(durations.length * 0.95)];
    assert.ok(p95 < 500, `p95 latency (${p95.toFixed(2)}ms) must be well under 3000ms`);
  });
});
