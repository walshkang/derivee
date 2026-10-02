// Injected at build time by Vite define, or provided via environment in tests/server.
declare const __BUILD_HASH__: string | undefined;
declare const __BUILD_TIME__: string | undefined;

export interface BuildInfo {
  hash: string;
  timestamp: string;
}

export interface BuildInfoInput {
  hash?: string | null;
  timestamp?: string | null;
}

function sanitizeHash(raw: unknown): string {
  if (typeof raw !== 'string') return 'unknown';
  const trimmed = raw.trim();
  if (!trimmed || trimmed === 'unknown') return 'unknown';

  // Prevent path leaks, protocol leaks, command injection, or multi-word sentences
  if (
    trimmed.includes('/') ||
    trimmed.includes('\\') ||
    trimmed.includes(' ') ||
    trimmed.includes(':') ||
    trimmed.includes('=')
  ) {
    return 'unknown';
  }

  // Git commit hash (hex): truncate 7..40 chars down to 7 chars
  if (/^[0-9a-fA-F]{7,40}$/.test(trimmed)) {
    return trimmed.slice(0, 7).toLowerCase();
  }

  // Short alphanumeric build tags (e.g. v1.0.0 or 1234567)
  if (/^[0-9a-zA-Z._-]{1,12}$/.test(trimmed)) {
    return trimmed;
  }

  return 'unknown';
}

function sanitizeTimestamp(raw: unknown): string {
  if (typeof raw !== 'string') return 'unknown';
  const trimmed = raw.trim();
  if (!trimmed || trimmed === 'unknown') return 'unknown';

  // Reject paths, HTML/script tags, quotes, or environment variable assignments
  if (
    trimmed.includes('<') ||
    trimmed.includes('>') ||
    trimmed.includes('"') ||
    trimmed.includes("'") ||
    trimmed.includes('\\') ||
    trimmed.includes('=') ||
    trimmed.startsWith('/')
  ) {
    return 'unknown';
  }

  return trimmed;
}

export function getBuildInfo(): BuildInfo {
  let rawHash: string | undefined;
  let rawTime: string | undefined;

  // 1. Vite define injection (client bundle)
  if (typeof __BUILD_HASH__ !== 'undefined' && __BUILD_HASH__) {
    rawHash = __BUILD_HASH__;
  }
  if (typeof __BUILD_TIME__ !== 'undefined' && __BUILD_TIME__) {
    rawTime = __BUILD_TIME__;
  }

  // 2. Node.js environment variables (testing / CI / server)
  if (!rawHash && typeof process !== 'undefined' && process?.env) {
    rawHash =
      process.env.CF_PAGES_COMMIT_SHA?.slice(0, 7) ||
      process.env.VITE_COMMIT_HASH?.slice(0, 7) ||
      process.env.COMMIT_HASH?.slice(0, 7);
  }

  if (!rawTime && typeof process !== 'undefined' && process?.env) {
    rawTime = process.env.VITE_BUILD_TIME || process.env.BUILD_TIME;
  }

  return {
    hash: sanitizeHash(rawHash),
    timestamp: sanitizeTimestamp(rawTime),
  };
}

export function formatBuildInfo(
  hashOrInput?: string | null | BuildInfoInput,
  timestampArg?: string | null
): string {
  try {
    let rawHash: unknown;
    let rawTime: unknown;

    if (
      typeof hashOrInput === 'object' &&
      hashOrInput !== null &&
      !Array.isArray(hashOrInput)
    ) {
      rawHash = hashOrInput.hash;
      rawTime = hashOrInput.timestamp;
    } else {
      rawHash = hashOrInput;
      rawTime = timestampArg;
    }

    // When called with no arguments (or empty undefined), read from build/environment
    if (rawHash === undefined && rawTime === undefined) {
      const info = getBuildInfo();
      rawHash = info.hash;
      rawTime = info.timestamp;
    }

    const cleanHash = sanitizeHash(rawHash);
    const cleanTime = sanitizeTimestamp(rawTime);

    if (cleanHash === 'unknown' && cleanTime === 'unknown') {
      return 'unknown';
    }

    if (cleanTime === 'unknown') {
      return cleanHash;
    }

    if (cleanHash === 'unknown') {
      return `unknown (${cleanTime})`;
    }

    return `${cleanHash} (${cleanTime})`;
  } catch {
    return 'unknown';
  }
}
