import { fetchFeeds, getArrivalsForStop } from './gtfs.js';

export interface Env {
  PACK: R2Bucket;
  RATE_LIMITER?: RateLimit;
  ASSETS?: Fetcher;
  KV_REALTIME: KVNamespace;
}

const ALLOWED_ORIGINS = new Set([
  'https://derivee-api.walsh-8de.workers.dev',
  'https://9c770b10.derivee-web.pages.dev',
  'https://derivee.app',
  'http://localhost:5173',
  'http://127.0.0.1:5173',
]);

function isAllowedOrigin(origin: string | null): boolean {
  if (!origin) return false;
  if (ALLOWED_ORIGINS.has(origin)) return true;
  if (/^https:\/\/[a-z0-9-]+\.derivee-web\.pages\.dev$/.test(origin)) return true;
  if (/^https:\/\/[a-z0-9-]+\.walsh-8de\.workers\.dev$/.test(origin)) return true;
  return false;
}

function getPreflightHeaders(origin: string | null): Headers {
  const headers = new Headers({ Vary: 'Origin' });
  if (isAllowedOrigin(origin)) {
    headers.set('Access-Control-Allow-Origin', origin!);
    headers.set('Access-Control-Allow-Methods', 'GET, OPTIONS');
    headers.set('Access-Control-Allow-Headers', 'Content-Type, Range');
    headers.set('Access-Control-Allow-Credentials', 'true');
    headers.set('Access-Control-Max-Age', '86400');
  }
  return headers;
}

function getCorsHeaders(origin: string | null): Record<string, string> {
  const headers: Record<string, string> = { Vary: 'Origin' };
  if (isAllowedOrigin(origin)) {
    headers['Access-Control-Allow-Origin'] = origin!;
    headers['Access-Control-Allow-Credentials'] = 'true';
    headers['Access-Control-Expose-Headers'] = 'Content-Length, Content-Disposition, ETag';
  }
  return headers;
}

function jsonResponse(
  body: unknown,
  status: number,
  origin: string | null,
  extraHeaders: Record<string, string> = {}
): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      'Content-Type': 'application/json',
      ...getCorsHeaders(origin),
      ...extraHeaders,
    },
  });
}

export default {
  async scheduled(event: ScheduledEvent, env: Env, ctx: ExecutionContext) {
    ctx.waitUntil(fetchFeeds(env.KV_REALTIME));
  },

  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    const origin = request.headers.get('Origin');

    // 1. Handle OPTIONS preflight on any /api/* route FIRST (before auth)
    if (request.method === 'OPTIONS') {
      if (url.pathname.startsWith('/api/')) {
        return new Response(null, {
          status: 204,
          headers: getPreflightHeaders(origin),
        });
      }
      return jsonResponse({ error: 'not_found' }, 404, origin);
    }

    // 2. Health check route: GET /api/health (unauthenticated)
    if (url.pathname === '/api/health' && request.method === 'GET') {
      return jsonResponse({ ok: true }, 200, origin);
    }

    // 2.5 Realtime arrivals: GET /api/realtime/arrivals?stop=XXX
    if (url.pathname === '/api/realtime/arrivals' && request.method === 'GET') {
      const stop = url.searchParams.get('stop');
      if (!stop) {
        return jsonResponse({ error: 'missing_stop' }, 400, origin);
      }
      const data = await getArrivalsForStop(env.KV_REALTIME, stop);
      if (!data) {
        return jsonResponse({ error: 'not_found' }, 404, origin);
      }
      // Check freshness
      const now = Math.floor(Date.now() / 1000);
      if (now - data.updated_at > 90) {
        return jsonResponse({ error: 'stale', stale: true }, 503, origin);
      }
      return jsonResponse(data, 200, origin);
    }

    // 3. Authenticated session check: GET /api/me
    if (url.pathname === '/api/me' && request.method === 'GET') {
      const userEmail =
        request.headers.get('cf-access-authenticated-user-email') ||
        request.headers.get('Cf-Access-Authenticated-User-Email');

      if (!userEmail) {
        return jsonResponse({ error: 'unauthorized' }, 401, origin);
      }

      return jsonResponse({ email: userEmail }, 200, origin);
    }

    // 4. Pack streaming route: GET /api/pack
    if (url.pathname === '/api/pack' && request.method === 'GET') {
      // Identity verification injected by Cloudflare Access edge
      const userEmail =
        request.headers.get('cf-access-authenticated-user-email') ||
        request.headers.get('Cf-Access-Authenticated-User-Email');

      if (!userEmail) {
        return jsonResponse({ error: 'unauthorized' }, 401, origin);
      }

      // Per-identity rate limiting via ratelimits binding
      if (env.RATE_LIMITER) {
        const { success } = await env.RATE_LIMITER.limit({ key: userEmail });
        if (!success) {
          return jsonResponse(
            { error: 'rate_limited' },
            429,
            origin,
            { 'Retry-After': '60' }
          );
        }
      }

      const city = url.searchParams.get('city') || 'nyc';
      const key = `city-${city}.pack.zst`;

      // Fetch pack object from R2
      const obj = await env.PACK.get(key);
      if (!obj) {
        return jsonResponse({ error: 'not_found' }, 404, origin);
      }

      // Stream object body back directly without buffering
      const headers = new Headers({
        'Content-Type': 'application/zstd',
        'Content-Length': obj.size.toString(),
        'Content-Disposition': `attachment; filename="${key}"`,
        'Cache-Control': 'no-store',
        ...getCorsHeaders(origin),
      });

      if (obj.httpEtag) {
        headers.set('ETag', obj.httpEtag);
      }

      return new Response(obj.body, {
        status: 200,
        headers,
      });
    }

    // 5. Cities manifest streaming route: GET /api/cities
    if (url.pathname === '/api/cities' && request.method === 'GET') {
      // Identity verification injected by Cloudflare Access edge
      const userEmail =
        request.headers.get('cf-access-authenticated-user-email') ||
        request.headers.get('Cf-Access-Authenticated-User-Email');

      if (!userEmail) {
        return jsonResponse({ error: 'unauthorized' }, 401, origin);
      }

      // Per-identity rate limiting via ratelimits binding
      if (env.RATE_LIMITER) {
        const { success } = await env.RATE_LIMITER.limit({ key: userEmail });
        if (!success) {
          return jsonResponse(
            { error: 'rate_limited' },
            429,
            origin,
            { 'Retry-After': '60' }
          );
        }
      }

      // Fetch cities manifest object from R2
      const obj = await env.PACK.get('cities.json');
      if (!obj) {
        return jsonResponse({ error: 'not_found' }, 404, origin);
      }

      // Stream object body back directly without buffering
      const headers = new Headers({
        'Content-Type': 'application/json',
        'Content-Length': obj.size.toString(),
        'Content-Disposition': 'inline; filename="cities.json"',
        'Cache-Control': 'no-store',
        ...getCorsHeaders(origin),
      });

      if (obj.httpEtag) {
        headers.set('ETag', obj.httpEtag);
      }

      return new Response(obj.body, {
        status: 200,
        headers,
      });
    }

    // 5. Basemap streaming route: GET /api/basemap
    if (url.pathname === '/api/basemap' && request.method === 'GET') {
      const city = url.searchParams.get('city') || 'nyc';
      const key = `basemap-${city}.pmtiles`;

      const obj = await env.PACK.get(key, {
        range: request.headers,
        onlyIf: request.headers,
      });

      if (!obj) {
        return jsonResponse({ error: 'not_found' }, 404, origin);
      }

      const headers = new Headers({
        'Content-Type': 'application/vnd.pmtiles',
        'Cache-Control': 'public, max-age=86400',
        ...getCorsHeaders(origin),
      });

      if (obj.httpEtag) {
        headers.set('ETag', obj.httpEtag);
      }

      if (!('body' in obj)) {
        return new Response(null, { status: 304, headers });
      }

      if ('range' in obj && obj.range) {
        const r = obj.range as { offset: number; length: number };
        headers.set('Content-Range', `bytes ${r.offset}-${r.offset + r.length - 1}/${obj.size}`);
        headers.set('Content-Length', r.length.toString());
        return new Response(obj.body, {
          status: 206,
          headers,
        });
      }

      headers.set('Content-Length', obj.size.toString());
      headers.set('Content-Disposition', `attachment; filename="${city}-basemap.pmtiles"`);

      return new Response(obj.body, {
        status: 200,
        headers,
      });
    }

    // 6. Any unmatched /api/* route -> 404 JSON
    if (url.pathname.startsWith('/api/')) {
      return jsonResponse({ error: 'not_found' }, 404, origin);
    }

    // 6. Static assets fallback (PWA shell, HTML, JS, CSS, fonts, wasm)
    if (env.ASSETS) {
      return env.ASSETS.fetch(request);
    }

    // Fallback if ASSETS binding not present
    return jsonResponse({ error: 'not_found' }, 404, origin);
  },
};
