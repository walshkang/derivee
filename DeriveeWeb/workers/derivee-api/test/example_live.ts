import { fetchFeeds, getArrivalsForStop } from '../src/gtfs.js';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// Override global fetch to return our fixture
const originalFetch = global.fetch;

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

async function run() {
  const kv = new MockKV() as any;

  global.fetch = async (url: string | URL | Request) => {
    const urlStr = url.toString();
    if (urlStr.includes('gtfs-l')) {
      const fixture = fs.readFileSync(path.join(__dirname, 'fixtures', 'gtfs-l.proto.bin'));
      return new Response(fixture, { status: 200 });
    } else {
      return new Response('Not Found', { status: 404 });
    }
  };

  await fetchFeeds(kv);
  const data = await getArrivalsForStop(kv, 'L01');
  console.log(JSON.stringify(data, null, 2));
}

run().catch(console.error);
