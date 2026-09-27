# Cloudflare Private Distribution & Sync Architecture

**Date:** 2026-09-27  
**Status:** Approved Research / Architecture Specification  
**Project:** Dérivée Web (NYC Offline-First Transit PWA)  
**Target Audience:** Owner (Walsh) + ~10 invited friends  
**Primary Assets:** 28 MB Zstandard City Pack (`city-nyc.pack.zst`), Daily GTFS Deltas (`transit_delta.sqlite.zst`), Fog-of-War H3 sync  

---

## 1. Executive Summary & Architecture Diagram

Dérivée Web requires an offline-first PWA architecture where an iPhone-first client can reliably download a 28 MB binary transit pack and synchronize daily GTFS reliability deltas without any long-lived credentials exposed in client-side code. Furthermore, private exploration state (fog-of-war H3 hexes) must synchronize across a trusted group of ~10 friends.

### Core Architecture

```
                                      ┌──────────────────────────────────────────────────────────┐
                                      │             Cloudflare Edge Platform                     │
                                      │                                                          │
[ iPhone PWA Client ]                 │  ┌────────────────────────┐                              │
   │                                  │  │ Cloudflare Access      │                              │
   │ 1. GET /api/pack-url             │  │ (Zero Trust Free Tier) │                              │
   ├─────────────────────────────────>│  │ - Email OTP Allowlist  │                              │
   │    Cookie: CF_Authorization     │  │ - Injects Cf-Access-*  │                              │
   │                                  │  └───────────┬────────────┘                              │
   │                                  │              │                                           │
   │                                  │              ▼                                           │
   │                                  │  ┌────────────────────────┐     Class B GET              │
   │                                  │  │   Cloudflare Worker    │ ──────────────────┐          │
   │                                  │  │ - Rate Limiter Binding │                   │          │
   │                                  │  │ - aws4fetch SigV4 Sign │                   ▼          │
   │                                  │  └─────┬────────────┬─────┘         ┌───────────────────┐│
   │                                  │        │            │               │   Cloudflare R2   ││
   │ 2. JSON: { signedUrl, expires }  │        │            │               │  fog-of-transit   ││
   │<─────────────────────────────────┤        │ D1 Binding │               │ (Private Bucket)  ││
   │                                  │        ▼            ▼               └─────────┬─────────┘│
   │ 3. Direct GET (signedUrl)        │   ┌──────────┐ ┌──────────┐                   │          │
   ├──────────────────────────────────┼───┼──────────┼─┼──────────┼───────────────────┘          │
   │    Direct binary stream (28 MB)  │   │ D1 SQLite│ │Rate Limit│                                  │
   │<─────────────────────────────────┼───┤ (Fog DB) │ │ (Memory) │                                  │
   │                                  │   └──────────┘ └──────────┘                                  │
   └──────────────────────────────────┴──────────────────────────────────────────────────────────┘
```

---

## 2. Key Findings & Source Evidence

### 2.1 R2 Presigned URLs via Cloudflare Workers
* **Canonical Edge Signing:** The official AWS SDK v3 (`@aws-sdk/s3-request-presigner`) is heavyweight and relies on Node.js internals that historically cause cold-start latency and compatibility errors in edge V8 isolates. The canonical 2026 pattern in Cloudflare Workers is **`aws4fetch`** (`AwsClient` with `signQuery: true`), a zero-dependency, Web Crypto-native library built specifically for Cloudflare Workers.
* **Endpoint Constraints:** Presigned URLs **cannot** use R2 Custom Domains (`cdn.derivee.app`). AWS SigV4 signatures require the host header to match the signing authority; R2 presigned URLs must target the S3 API endpoint format: `https://<ACCOUNT_ID>.r2.cloudflarestorage.com/<BUCKET>/<KEY>`.
* **CORS Requirement:** Because the browser client downloads directly from `<ACCOUNT_ID>.r2.cloudflarestorage.com`, the request is cross-origin. The R2 bucket **must** have an explicit CORS configuration allowing `GET` and exposing `ETag` and `Content-Length`.
* **Sources:**
  - [Cloudflare R2 Presigned URLs Documentation](https://developers.cloudflare.com/r2/api/s3/presigned-urls/)
  - [Cloudflare Workers Runtime APIs](https://developers.cloudflare.com/workers/runtime-apis/)
  - [`aws4fetch` Specification & Edge Signing](https://github.com/mhart/aws4fetch)

### 2.2 Cloudflare Access for a Tiny Private Group
* **Free Tier Quota:** Cloudflare Zero Trust Access includes **50 free seats** (active user identities) on the Free plan at $0.00/month. Walsh + 10 friends consumes 11 seats (~22% of free allowance).
* **Identity Mechanism (Email OTP):** Cloudflare Access supports One-Time PIN (OTP) over email natively. For an iOS PWA, Email OTP is strongly preferred over external OAuth (e.g. Google Login). In iOS standalone PWA mode (`display: standalone`), external redirects to Google OAuth can break out of the PWA container into standard Safari or trip WebKit's Intelligent Tracking Prevention (ITP) cookie partitioning. Email OTP remains completely within the PWA webview context.
* **Cookie vs. Header Handling:**
  - Upon successful OTP verification, Cloudflare Access sets an `HttpOnly`, `SameSite=Lax` cookie named `CF_Authorization` on the application domain.
  - Client-side JavaScript cannot read `CF_Authorization` (protecting against XSS token exfiltration).
  - When the PWA makes API calls with `credentials: 'include'`, the browser attaches this cookie automatically.
  - The Cloudflare Access edge proxy intercepts the request, verifies the cookie, and forwards the request to the Worker with injected headers: `Cf-Access-Authenticated-User-Email` and the cryptographically signed JWT `Cf-Access-Jwt-Assertion`.
* **Sources:**
  - [Cloudflare Zero Trust Access Pricing & Plans](https://developers.cloudflare.com/cloudflare-one/plans/)
  - [Validating Access JWTs at Origin/Worker](https://developers.cloudflare.com/cloudflare-one/identity/authorization-cookie/validating-json/)

### 2.3 Edge Rate Limiting on Workers
* **Workers Rate Limiting Binding:** Cloudflare provides a native rate-limiting binding (`[[ratelimits]]` in `wrangler.toml`). It is Generally Available (GA) and runs natively in Workers runtime memory without requiring external KV or Redis lookups.
* **Per-Identity Keying:** Rate limits can be keyed directly on `userEmail` extracted from the Access assertion header (`env.RATE_LIMITER.limit({ key: userEmail })`), preventing one aggressive client or script loop from degrading performance for other friends.
* **Configuration Semantics:** Rules configure `limit` and `period` (10s or 60s windows).
* **Sources:**
  - [Cloudflare Workers Rate Limiting Runtime API](https://developers.cloudflare.com/workers/runtime-apis/bindings/rate-limit/)

### 2.4 Cost & Bandwidth Reality (2026 Pricing)
* **Zero Egress:** Cloudflare R2 has **$0.00 egress charges** unconditionally across all tiers.
* **Standard Storage Free Tier:**
  - Storage: **10 GB-months / month** free ($0.015/GB-month thereafter).
  - Class A Operations (writes/mutations/uploads): **1,000,000 requests / month** free ($4.50/million thereafter).
  - Class B Operations (reads/GETs): **10,000,000 requests / month** free ($0.36/million thereafter).
* **Monthly Cost for 10 Friends Downloading 28 MB Pack:**
  - Storage: 1 × 28 MB pack + 30 daily deltas (~100 KB each) ≈ 31 MB (<0.31% of 10 GB free tier).
  - Downloads: 10 initial downloads + occasional updates = ~20 Class B ops (<0.0002% of 10M free limit).
  - Bandwidth: 10 × 28 MB = 280 MB egress = **$0.00**.
  - Monthly Bill: **$0.00**.
* **Alerting Options:**
  - Cloudflare Dashboard → *Notifications* → *Add Notification*.
  - Alerts available for: Billing Threshold (notify if charges > $1.00), Usage Alerts (R2 Operations > 80% free tier), and Workers Daily Request anomalies. Notifications route via Email, Slack, or Discord webhooks.
* **Sources:**
  - [Cloudflare R2 Official Pricing](https://developers.cloudflare.com/r2/pricing/)
  - [Cloudflare Notifications & Alerts Guide](https://developers.cloudflare.com/fundamentals/notifications/)

### 2.5 Light User State: D1 vs. R2 for Fog-of-War Sync
* **The Data Shape:** Dérivée tracks explored territory via Uber H3 Resolution 11 hex IDs. 1,000 unlocked hexes = 8 KB (packed 64-bit integer buffer) or ~16 KB JSON. An active user over months may accumulate 10,000 hexes (~80 KB binary).
* **Comparison Matrix:**

| Evaluation Metric | Cloudflare D1 (SQLite) | Cloudflare R2 (Object Store) | Workers KV (Key-Value) |
| :--- | :--- | :--- | :--- |
| **Data Model** | Relational / SQLite | Unstructured Object | Key-Value Blob |
| **Free Tier Quota** | 5M read rows/day<br>100k write rows/day<br>5 GB storage | 10M Class B/mo<br>1M Class A/mo<br>10 GB storage | 100k reads/day<br>1,000 writes/day<br>1 GB storage |
| **Concurrency / Write Model** | Strong consistency on primary; atomic SQL `ON CONFLICT` | ETag `If-Match` conditional overwrite | Eventual consistency; max 1 write/sec per key |
| **Multi-User Queries** | Trivially supports leaderboards (`ORDER BY hex_count`) | Impossible without listing/reading all objects | Impossible without full key iteration |
| **Suitability for Fog Sync** | **Optimal** (fast, atomic upsert, relational progress) | Poor (high latency for 50 KB blobs, no SQL) | Suboptimal (low write quota, eventual consistency) |

* **Sources:**
  - [Cloudflare D1 Pricing & Limits](https://developers.cloudflare.com/d1/platform/pricing/)
  - [Cloudflare Workers KV Limits](https://developers.cloudflare.com/kv/platform/limits/)

### 2.6 Critical Anti-Patterns
1. **Client-Held Storage or Cloudflare Credentials (Fatal):** Hardcoding R2 S3 Access Keys or D1 API tokens in client-side PWA code allows anyone with Safari Web Inspector to extract credentials and execute bucket-wide deletion (`s3:DeleteBucket`, `s3:DeleteObject`) or tamper with transit databases.
2. **CORS Wildcard with Credentials:** Using `Access-Control-Allow-Origin: *` while passing credentials (`credentials: 'include'`) is rejected by all modern browsers. The Worker must reflect the exact requesting origin.
3. **Blocking Preflight `OPTIONS` Requests:** If authentication middleware runs before handling `OPTIONS` preflight, the browser preflight fails with 401/403, completely blocking the subsequent GET/POST.
4. **Caching Cloudflare Access Redirects in Service Worker:** If a Service Worker intercepts all network traffic with a network-first strategy, an expired session redirect (302 to Cloudflare login page) can accidentally overwrite cached PWA assets with HTML login markup.

---

## 3. Concrete Recommendations for Dérivée Web

### 3.1 Domain & Routing Architecture (Split Strategy)

To achieve reliable offline-first PWA behavior on iOS without authentication lockouts:

```
https://derivee.app/              --> Public / CDN Cached (Service Worker Cache-First)
├── index.html                   --> PWA Shell
├── app.js                       --> Application Logic
├── manifest.webmanifest         --> Web App Manifest
├── assets/                      --> Icons, UI Assets
└── wasm/                        --> RAPTOR & Walk Router Binaries

https://derivee.app/api/*         --> Cloudflare Access Gated + Cloudflare Worker
├── /api/me                      --> Session identity check
├── /api/pack-url                --> Returns short-lived R2 presigned GET URL
├── /api/delta                   --> Streams latest daily transit delta
└── /api/sync                    --> Fog-of-war H3 state synchronization (D1)
```

> [!IMPORTANT]
> **Why the Public Shell is Crucial:**
> If the entire domain `derivee.app` is protected behind Cloudflare Access, opening the app underground (without cell service) risks Safari failing navigation if the session token is expired or if WebKit attempts network revalidation. By keeping the static shell public and caching it aggressively via Service Worker, the PWA **always opens offline**. Only data-plane synchronization operations (`/api/*`) require the active Cloudflare Access session.

---

### 3.2 Cloudflare Access Policy Configuration

In the Cloudflare One / Zero Trust Dashboard:
1. **Application Type:** Self-hosted
2. **Application Domain:** `derivee.app`, Path: `/api/*`
3. **Session Duration:** `1 month` (730 hours). This minimizes login friction for Walsh and friends while maintaining reasonable security.
4. **Identity Providers:** One-Time PIN (Email OTP) enabled. (Google OAuth disabled to prevent iOS standalone PWA redirect breaking).
5. **Access Policy:**
   - **Action:** Allow
   - **Rule Type:** Include → Emails
   - **Allowed List:** Walsh's email + ~10 invited friends' emails.
6. **CORS Settings:**
   - Allow credentials: `true`
   - Allowed Origins: `https://derivee.app`
   - Allowed Methods: `GET, POST, OPTIONS`

---

### 3.3 Worker Endpoint & Security Design

#### A. Presigned URL Generation (`GET /api/pack-url`)
* **Lifespan:** **600 seconds (10 minutes)**.
  - *Rationale:* A 28 MB download takes ~25 seconds on a 10 Mbps LTE connection and ~2 minutes on 2 Mbps 3G. In AWS SigV4, the expiry timestamp is checked when the HTTP GET connection starts, not when the stream finishes. 10 minutes provides ample buffer for slow connection handshakes while strictly limiting the window if a URL leaks.
* **Scoping:**
  - Method: Strictly `GET`.
  - Path: Strictly `fog-of-transit/city-nyc.pack.zst`.
  - Query parameters: Signed with `signQuery: true`.
* **Rate Limit:** 5 requests per 60 seconds per user.

#### B. Daily Transit Delta Sync (`GET /api/delta`)
* Rather than generating a presigned URL for tiny daily deltas (~100 KB), the Worker can stream the delta directly using the native R2 Worker binding (`env.FOG_BUCKET.get('transit_delta.sqlite.zst')`), passing along `ETag` and `Content-Type: application/zstd`.
* **Rate Limit:** 15 requests per 60 seconds per user.

#### C. Fog-of-War H3 Synchronization (`POST /api/sync` & `GET /api/sync`)
* **Storage Engine:** Cloudflare D1.
* **Write Mechanism (`POST /api/sync`):** Client debounces discovered hexes and sends a compressed JSON payload:
  `{ "addedHexes": ["8b2a1072895ffff", ...], "timestamp": 1727461692 }`
* The Worker verifies user email from `request.headers.get('cf-access-authenticated-user-email')` and executes an atomic upsert into D1.
* **Rate Limit:** 30 requests per 60 seconds per user.

---

### 3.4 Complete Worker Implementation (`src/index.ts`)

```typescript
import { AwsClient } from 'aws4fetch';

export interface Env {
  FOG_BUCKET: R2Bucket;
  DB: D1Database;
  RATE_LIMITER: {
    limit: (options: { key: string }) => Promise<{ success: boolean }>;
  };
  R2_ACCOUNT_ID: string;
  R2_ACCESS_KEY_ID: string;
  R2_SECRET_ACCESS_KEY: string;
  BUCKET_NAME: string;
}

const ALLOWED_ORIGIN = 'https://derivee.app';

function corsHeaders(extraHeaders: Record<string, string> = {}): Headers {
  const headers = new Headers({
    'Access-Control-Allow-Origin': ALLOWED_ORIGIN,
    'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type, Authorization',
    'Access-Control-Allow-Credentials': 'true',
    ...extraHeaders,
  });
  return headers;
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);

    // 1. Handle CORS Preflight immediately (Never gate OPTIONS behind auth!)
    if (request.method === 'OPTIONS') {
      return new Response(null, {
        status: 204,
        headers: corsHeaders({ 'Access-Control-Max-Age': '86400' }),
      });
    }

    // 2. Identity Verification (Injected by Cloudflare Access)
    const userEmail = request.headers.get('cf-access-authenticated-user-email');
    if (!userEmail) {
      return new Response(JSON.stringify({ error: 'Unauthorized: Missing Access Identity' }), {
        status: 401,
        headers: corsHeaders({ 'Content-Type': 'application/json' }),
      });
    }

    // 3. Per-Identity Rate Limiting
    const rateLimit = await env.RATE_LIMITER.limit({ key: userEmail });
    if (!rateLimit.success) {
      return new Response(JSON.stringify({ error: 'Too Many Requests' }), {
        status: 429,
        headers: corsHeaders({
          'Content-Type': 'application/json',
          'Retry-After': '60',
        }),
      });
    }

    // 4. Route: Session Identity Check
    if (url.pathname === '/api/me' && request.method === 'GET') {
      return new Response(JSON.stringify({ email: userEmail }), {
        status: 200,
        headers: corsHeaders({ 'Content-Type': 'application/json' }),
      });
    }

    // 5. Route: Presigned Download URL for 28 MB City Pack
    if (url.pathname === '/api/pack-url' && request.method === 'GET') {
      const aws = new AwsClient({
        accessKeyId: env.R2_ACCESS_KEY_ID,
        secretAccessKey: env.R2_SECRET_ACCESS_KEY,
        service: 's3',
        region: 'auto',
      });

      const objectKey = 'city-nyc.pack.zst';
      const expiresInSeconds = 600; // 10 minutes
      const r2Endpoint = `https://${env.R2_ACCOUNT_ID}.r2.cloudflarestorage.com`;
      const targetUrl = `${r2Endpoint}/${env.BUCKET_NAME}/${objectKey}?X-Amz-Expires=${expiresInSeconds}`;

      const presignedRequest = await aws.sign(
        new Request(targetUrl, { method: 'GET' }),
        { aws: { signQuery: true } }
      );

      return new Response(
        JSON.stringify({
          downloadUrl: presignedRequest.url,
          expiresIn: expiresInSeconds,
          filename: objectKey,
        }),
        {
          status: 200,
          headers: corsHeaders({ 'Content-Type': 'application/json' }),
        }
      );
    }

    // 6. Route: Direct Stream for Small Daily Delta (~100 KB)
    if (url.pathname === '/api/delta' && request.method === 'GET') {
      const objectKey = 'transit_delta.sqlite.zst';
      const deltaObj = await env.FOG_BUCKET.get(objectKey);

      if (!deltaObj) {
        return new Response(JSON.stringify({ error: 'Delta not found' }), {
          status: 404,
          headers: corsHeaders({ 'Content-Type': 'application/json' }),
        });
      }

      const headers = corsHeaders({
        'Content-Type': 'application/zstd',
        'ETag': deltaObj.httpEtag,
        'Cache-Control': 'private, no-cache',
      });

      return new Response(deltaObj.body, { status: 200, headers });
    }

    // 7. Route: Fog-of-War H3 Synchronization (D1)
    if (url.pathname === '/api/sync') {
      if (request.method === 'GET') {
        const row = await env.DB.prepare(
          'SELECT hex_list, hex_count, updated_at FROM user_fog WHERE user_email = ?'
        ).bind(userEmail).first();

        return new Response(JSON.stringify(row || { hex_list: '[]', hex_count: 0 }), {
          status: 200,
          headers: corsHeaders({ 'Content-Type': 'application/json' }),
        });
      }

      if (request.method === 'POST') {
        const body = await request.json<{ addedHexes: string[]; timestamp: number }>();
        if (!Array.isArray(body.addedHexes)) {
          return new Response(JSON.stringify({ error: 'Invalid payload' }), {
            status: 400,
            headers: corsHeaders({ 'Content-Type': 'application/json' }),
          });
        }

        // Fetch existing hex set, merge, and upsert
        const existing = await env.DB.prepare(
          'SELECT hex_list FROM user_fog WHERE user_email = ?'
        ).bind(userEmail).first<{ hex_list: string }>();

        const hexSet = new Set<string>(existing ? JSON.parse(existing.hex_list) : []);
        for (const hex of body.addedHexes) {
          hexSet.add(hex);
        }

        const mergedArray = Array.from(hexSet);
        const now = Math.floor(Date.now() / 1000);

        await env.DB.prepare(`
          INSERT INTO user_fog (user_email, hex_list, hex_count, updated_at)
          VALUES (?, ?, ?, ?)
          ON CONFLICT(user_email) DO UPDATE SET
            hex_list = excluded.hex_list,
            hex_count = excluded.hex_count,
            updated_at = excluded.updated_at
        `).bind(userEmail, JSON.stringify(mergedArray), mergedArray.length, now).run();

        return new Response(
          JSON.stringify({ success: true, count: mergedArray.length, updatedAt: now }),
          {
            status: 200,
            headers: corsHeaders({ 'Content-Type': 'application/json' }),
          }
        );
      }
    }

    return new Response(JSON.stringify({ error: 'Endpoint Not Found' }), {
      status: 404,
      headers: corsHeaders({ 'Content-Type': 'application/json' }),
    });
  },
};
```

---

### 3.5 Worker Configuration (`wrangler.toml`)

```toml
name = "derivee-api"
main = "src/index.ts"
compatibility_date = "2026-09-01"
compatibility_flags = ["nodejs_compat"]

# 1. Native R2 Bucket Binding (for direct delta streaming)
[[r2_buckets]]
binding = "FOG_BUCKET"
bucket_name = "fog-of-transit"

# 2. D1 Database Binding (for fog-of-war state)
[[d1_databases]]
binding = "DB"
database_name = "derivee_users"
database_id = "00000000-0000-0000-0000-000000000000" # Replace with actual UUID

# 3. Native Edge Rate Limiting Binding
[[ratelimits]]
name = "RATE_LIMITER"
namespace_id = "1001"

[ratelimits.simple]
limit = 60
period = 60

# 4. Public Environment Variables
[vars]
R2_ACCOUNT_ID = "YOUR_CLOUDFLARE_ACCOUNT_ID"
BUCKET_NAME = "fog-of-transit"

# Encrypted Secrets (Set via: wrangler secret put <NAME>)
# - R2_ACCESS_KEY_ID
# - R2_SECRET_ACCESS_KEY
```

---

### 3.6 D1 Database Schema (`schema.sql`)

```sql
CREATE TABLE IF NOT EXISTS user_fog (
  user_email TEXT PRIMARY KEY,
  hex_list TEXT NOT NULL DEFAULT '[]', -- JSON array of H3 string indices
  hex_count INTEGER NOT NULL DEFAULT 0,
  updated_at INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_user_fog_updated ON user_fog(updated_at);
```

---

### 3.7 R2 Bucket CORS Configuration (`cors.json`)

To allow direct browser download from the presigned URL, apply the following CORS rule to the `fog-of-transit` bucket:

```json
[
  {
    "AllowedOrigins": [
      "https://derivee.app",
      "http://localhost:5173"
    ],
    "AllowedMethods": [
      "GET",
      "HEAD"
    ],
    "AllowedHeaders": [
      "*"
    ],
    "ExposeHeaders": [
      "ETag",
      "Content-Length",
      "Accept-Ranges"
    ],
    "MaxAgeSeconds": 3600
  }
]
```

*Apply via Wrangler:*
```bash
wrangler r2 bucket cors set fog-of-transit --file ./cors.json
```

---

## 4. Pitfalls & Anti-Patterns to Avoid

### Pitfall 1: Signing Presigned URLs with Custom Domains
* **Mistake:** Attempting to presign `https://cdn.derivee.app/city-nyc.pack.zst`.
* **Failure Mode:** R2 rejects the request with HTTP 403 SignatureDoesNotMatch.
* **Mitigation:** Always sign against `<ACCOUNT_ID>.r2.cloudflarestorage.com`. Use custom domains exclusively for unauthenticated CDN caching, never for S3 SigV4 query signing.

### Pitfall 2: Neglecting R2 Bucket CORS on Presigned Downloads
* **Mistake:** Generating a valid presigned URL but omitting bucket-level CORS.
* **Failure Mode:** The Worker returns the signed URL successfully, but the browser's subsequent `fetch(signedUrl)` fails with a CORS origin policy error.
* **Mitigation:** Ensure `fog-of-transit` has an active CORS rule exposing `Content-Length` and `ETag`.

### Pitfall 3: Service Worker Caching Access 302 Redirects
* **Mistake:** A naive `fetch` event handler in the Service Worker intercepts all requests without checking response status or URL prefix.
* **Failure Mode:** When Walsh opens the app after an Access session expiration, a background fetch receives a 302 redirect to Cloudflare login HTML. If cached in Cache Storage, the offline PWA shell breaks.
* **Mitigation:** 
  1. Exclude `/api/*` from Service Worker caching entirely (`if (url.pathname.startsWith('/api/')) return;`).
  2. Implement Cache-First strictly for application shell assets (`/`, `/app.js`, `/wasm/*`).

### Pitfall 4: Google OAuth Redirect Loops in iOS Standalone PWA
* **Mistake:** Enabling Google OAuth or external SAML in Cloudflare Access for a standalone home-screen PWA.
* **Failure Mode:** WebKit opens Google login in an isolated external sheet or standard Safari. The session cookie is written to Safari's cookie jar, leaving the standalone PWA unauthenticated and stuck in a redirect loop.
* **Mitigation:** Use **Email OTP** exclusively for Cloudflare Access policies in this PWA.

### Pitfall 5: Client-Held R2 S3 Tokens
* **Mistake:** Storing `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` in client `.env` files or IndexedDB.
* **Failure Mode:** Trivial extraction via Web Inspector enables malicious bucket wiping or quota exhaustion.
* **Mitigation:** The client possesses zero storage credentials. The Worker acts as an authenticated broker, issuing short-lived presigned URLs.

---

## 5. Open Questions & Technical Debts

1. **Subway Reconnect Behavior:** When an iPhone transitions from an underground dead zone to station Wi-Fi / cellular, how should the PWA resume a stalled 28 MB pack download?
   - *Exploration:* Verify whether R2 presigned URLs support HTTP `Range` requests for resumable downloads. (R2 natively supports `Range: bytes=start-end`; client should track byte offsets in Cache Storage).
2. **Delta Cache Headers:** Should daily GTFS deltas (`transit_delta.sqlite.zst`) include a `Cache-Control: public, max-age=3600` header in the Worker, or should the Worker maintain strict `private, no-cache` with ETags?
   - *Exploration:* ETag-based 304 Not Modified validation avoids re-downloading unchanged deltas while preventing cross-user stale cache poisoning.
3. **Multi-City City Pack Expansion (Wave L):** When Boston or additional cities are onboarded, should each city maintain its own R2 bucket or share `fog-of-transit` with path prefixing (`packs/{city}.pack.zst`)?
   - *Exploration:* Path prefixing under a single bucket simplifies CORS and access policies while keeping all packs within the single 10 GB free tier.

---

## 6. Implementation Checklist for M2 & M6

- [ ] Create Cloudflare Access Application for `derivee.app/api/*` with Email OTP allowlist.
- [ ] Configure `fog-of-transit` R2 bucket CORS via `wrangler r2 bucket cors set`.
- [ ] Create D1 database (`derivee_users`) and execute `schema.sql`.
- [ ] Deploy Cloudflare Worker (`derivee-api`) with `FOG_BUCKET`, `DB`, and `RATE_LIMITER` bindings.
- [ ] Set encrypted Worker secrets: `R2_ACCESS_KEY_ID` and `R2_SECRET_ACCESS_KEY`.
- [ ] Set up billing threshold notification ($1.00) in Cloudflare Dashboard.
- [ ] Integrate PWA download pipeline: fetch `/api/pack-url` → download binary → decompress zstd → populate IndexedDB/OPFS.
