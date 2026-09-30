/**
 * Ambient type shims for Cloudflare Worker bindings when imported in client test suites.
 */
declare global {
  interface R2Bucket {
    [key: string]: any;
  }
  interface RateLimit {
    [key: string]: any;
  }
  interface Fetcher {
    [key: string]: any;
  }
}

export {};
