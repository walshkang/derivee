export interface PackInfo {
  version: number;
  size: number;
  updated_at: string;
}

export const LOCAL_STORAGE_CITY_VERSIONS_KEY = 'derivee_city_pack_versions';

/**
 * Returns a map of tracked city pack versions: { [citySlug: string]: number }
 */
export function getTrackedCityPackVersions(): Record<string, number> {
  try {
    const raw = localStorage.getItem(LOCAL_STORAGE_CITY_VERSIONS_KEY);
    if (!raw) return {};
    const parsed = JSON.parse(raw);
    if (parsed && typeof parsed === 'object' && !Array.isArray(parsed)) {
      return parsed as Record<string, number>;
    }
  } catch {
    // Ignore storage parse errors
  }
  return {};
}

/**
 * Returns tracked version for a specific city slug, or null if untracked.
 */
export function getTrackedCityPackVersion(citySlug: string): number | null {
  const versions = getTrackedCityPackVersions();
  const v = versions[citySlug];
  return typeof v === 'number' && !isNaN(v) ? v : null;
}

/**
 * Persists the installed/updated version for a specific city slug.
 */
export function setTrackedCityPackVersion(citySlug: string, version: number): void {
  try {
    const versions = getTrackedCityPackVersions();
    versions[citySlug] = version;
    localStorage.setItem(LOCAL_STORAGE_CITY_VERSIONS_KEY, JSON.stringify(versions));
  } catch {
    // Ignore storage quota/security errors
  }
}

/**
 * Pure function: compares installedVersion against server PackInfo.
 * Returns true if serverInfo represents a strictly newer, valid pack.
 * Negative cases (same, older, missing, malformed, negative size, NaN) return false.
 */
export function isPackUpdateAvailable(
  installedVersion: number,
  serverInfo: PackInfo | null | undefined
): boolean {
  if (typeof installedVersion !== 'number' || isNaN(installedVersion)) {
    return false;
  }
  if (!serverInfo || typeof serverInfo !== 'object') {
    return false;
  }
  const { version, size } = serverInfo;
  if (typeof version !== 'number' || isNaN(version) || version <= 0) {
    return false;
  }
  if (typeof size !== 'number' || isNaN(size) || size <= 0) {
    return false;
  }
  return version > installedVersion;
}

/**
 * Fetches pack info from /api/pack-info?city={citySlug}.
 * Returns null if network fails or non-200.
 */
export async function fetchPackInfo(
  citySlug: string = 'nyc',
  signal?: AbortSignal
): Promise<PackInfo | null> {
  const url = `/api/pack-info?city=${encodeURIComponent(citySlug)}`;
  const res = await fetch(url, {
    credentials: 'include',
    signal,
    headers: {
      Accept: 'application/json',
    },
  });

  if (!res.ok) {
    return null;
  }

  const data = await res.json() as unknown;
  if (!data || typeof data !== 'object') {
    return null;
  }

  const candidate = data as Partial<PackInfo>;
  if (
    typeof candidate.version === 'number' &&
    !isNaN(candidate.version) &&
    typeof candidate.size === 'number' &&
    !isNaN(candidate.size) &&
    typeof candidate.updated_at === 'string'
  ) {
    return candidate as PackInfo;
  }

  return null;
}
