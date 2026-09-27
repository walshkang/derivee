export interface Env {
  PACK: R2Bucket;
  RATE_LIMITER?: RateLimit;
}

const ALLOWED_ORIGINS = new Set([
  'https://9c770b10.derivee-web.pages.dev',
  'https://derivee.app',
  'http://localhost:5173',
  'http://127.0.0.1:5173',
]);

function isAllowedOrigin(origin: string | null): boolean {
  if (!origin) return false;
  if (ALLOWED_ORIGINS.has(origin)) return true;
  if (/^https:\/\/[a-z0-9-]+\.derivee-web\.pages\.dev$/.test(origin)) return true;
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

    // 2. Health check route: GET /api/health
    if (url.pathname === '/api/health' && request.method === 'GET') {
      return jsonResponse({ ok: true }, 200, origin);
    }

    // 3. Pack streaming route: GET /api/pack
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

      // Fetch pack object from R2
      const obj = await env.PACK.get('city-nyc.pack.zst');
      if (!obj) {
        return jsonResponse({ error: 'not_found' }, 404, origin);
      }

      // Stream object body back directly without buffering
      const headers = new Headers({
        'Content-Type': 'application/zstd',
        'Content-Length': obj.size.toString(),
        'Content-Disposition': 'attachment; filename="city-nyc.pack.zst"',
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

    // 4. All other routes → 404 JSON
    return jsonResponse({ error: 'not_found' }, 404, origin);
  },
};
