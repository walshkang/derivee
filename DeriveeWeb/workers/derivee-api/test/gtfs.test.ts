import { describe, it } from 'node:test';
import assert from 'node:assert';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// Override global fetch to return our fixture
const originalFetch = global.fetch;

// A mock KV namespace
class MockKV {
  private store = new Map<string, { value: string, expirationTtl?: number }>();
  
  async put(key: string, value: string, options?: any): Promise<void> {
    this.store.set(key, { value, expirationTtl: options?.expirationTtl });
  }
  
  async get(key: string, type?: string): Promise<any> {
    const entry = this.store.get(key);
    if (!entry) return null;
    if (type === 'json') return JSON.parse(entry.value);
    return entry.value;
  }
}

describe('Worker GTFS API', async () => {
  const { fetchFeeds, getArrivalsForStop } = await import('../src/gtfs.js');
  const worker = (await import('../src/index.js')).default;

  it('ingests feeds into KV successfully even if some fail', async () => {
    const kv = new MockKV() as any;

    global.fetch = async (url: string | URL | Request) => {
      const urlStr = url.toString();
      if (urlStr.includes('gtfs-l')) {
        const fixture = fs.readFileSync(path.join(__dirname, 'fixtures', 'gtfs-l.proto.bin'));
        return new Response(fixture, { status: 200 });
      } else {
        // Simulate failure for other feeds to test isolation
        return new Response('Not Found', { status: 404 });
      }
    };

    await fetchFeeds(kv);
    
    // Check that L01 was written (L train stops typically start with L)
    const lStops = await kv.get('stops-L', 'json');
    assert.ok(lStops, 'stops-L should be written to KV');
    assert.ok(Object.keys(lStops).length > 0, 'Should have some stops');

    const firstStopKey = Object.keys(lStops)[0];
    const stopData = lStops[firstStopKey];
    assert.strictEqual(stopData.stop_id, firstStopKey);
    assert.ok(stopData.arrivals.length > 0);
    assert.strictEqual(stopData.arrivals[0].route_id, 'L');
    assert.ok(stopData.arrivals[0].direction === 'NORTH' || stopData.arrivals[0].direction === 'SOUTH');
  });

  it('serves fresh arrivals from API', async () => {
    const kv = new MockKV() as any;
    
    // Inject mock data
    await kv.put('stops-L', JSON.stringify({
      'L01': {
        stop_id: 'L01',
        updated_at: Math.floor(Date.now() / 1000),
        arrivals: [
          { route_id: 'L', direction: 'NORTH', headsign: '', predicted_arrival_epoch: 1234567890, is_realtime: true }
        ]
      }
    }));

    const env = { KV_REALTIME: kv } as any;
    const req = new Request('http://localhost/api/realtime/arrivals?stop=L01');
    const res = await worker.fetch(req, env);
    
    assert.strictEqual(res.status, 200);
    const body = await res.json() as any;
    assert.strictEqual(body.stop_id, 'L01');
    assert.strictEqual(body.arrivals.length, 1);
  });

  it('returns 503 stale when cache is older than 90s', async () => {
    const kv = new MockKV() as any;
    
    // Inject old mock data
    await kv.put('stops-L', JSON.stringify({
      'L01': {
        stop_id: 'L01',
        updated_at: Math.floor(Date.now() / 1000) - 100, // 100 seconds old
        arrivals: []
      }
    }));

    const env = { KV_REALTIME: kv } as any;
    const req = new Request('http://localhost/api/realtime/arrivals?stop=L01');
    const res = await worker.fetch(req, env);
    
    assert.strictEqual(res.status, 503);
    const body = await res.json() as any;
    assert.strictEqual(body.stale, true);
  });

  it('returns 404 for unknown stop', async () => {
    const kv = new MockKV() as any;
    const env = { KV_REALTIME: kv } as any;
    const req = new Request('http://localhost/api/realtime/arrivals?stop=X99');
    const res = await worker.fetch(req, env);
    
    assert.strictEqual(res.status, 404);
  });

  it('returns 400 for missing stop param', async () => {
    const env = {} as any;
    const req = new Request('http://localhost/api/realtime/arrivals');
    const res = await worker.fetch(req, env);
    
    assert.strictEqual(res.status, 400);
  });
});
