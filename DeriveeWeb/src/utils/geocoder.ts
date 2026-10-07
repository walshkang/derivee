/**
 * geocoder.ts
 * Online Nominatim client and place-to-station snapping for transit routing.
 * Conforms to OpenStreetMap Nominatim usage policy (1 req/sec rate limit, User-Agent identification).
 */

import type { StopItem } from '../types/routing';

export interface GeocodedPlace {
  displayName: string;
  lat: number;
  lon: number;
  placeId?: number | string;
  type?: string;
  class?: string;
}

export interface GeocoderOptions {
  fetchFn?: typeof fetch;
  limit?: number;
  minIntervalMs?: number;
  userAgent?: string;
  endpoint?: string;
}

export const NOMINATIM_ENDPOINT = 'https://nominatim.openstreetmap.org/search';
export const DEFAULT_USER_AGENT = 'Derivee/1.0 (transit routing; https://derivee.app)';

let lastRequestTimestamp = 0;

export function resetRateLimiterForTesting(): void {
  lastRequestTimestamp = 0;
}

export async function throttleNominatimRequest(minIntervalMs: number = 1000): Promise<void> {
  const now = Date.now();
  const timeSinceLast = now - lastRequestTimestamp;
  if (timeSinceLast < minIntervalMs) {
    const delay = minIntervalMs - timeSinceLast;
    await new Promise((resolve) => setTimeout(resolve, delay));
  }
  lastRequestTimestamp = Date.now();
}

/**
 * Debounce helper to prevent excessive requests while typing.
 */
export function debounce<Args extends unknown[]>(
  fn: (...args: Args) => void,
  waitMs: number = 300
): {
  (...args: Args): void;
  cancel: () => void;
} {
  let timer: ReturnType<typeof setTimeout> | null = null;
  const debounced = (...args: Args) => {
    if (timer) clearTimeout(timer);
    timer = setTimeout(() => {
      timer = null;
      fn(...args);
    }, waitMs);
  };
  debounced.cancel = () => {
    if (timer) {
      clearTimeout(timer);
      timer = null;
    }
  };
  return debounced;
}

/**
 * Parses raw JSON response from Nominatim into structured GeocodedPlace objects.
 * Defensive against malformed payloads, non-array inputs, and non-numeric lat/lon.
 */
export function parseNominatimResponse(data: unknown): GeocodedPlace[] {
  if (!Array.isArray(data)) {
    return [];
  }

  const places: GeocodedPlace[] = [];
  for (const item of data) {
    if (!item || typeof item !== 'object') continue;
    const raw = item as Record<string, unknown>;
    const displayName = typeof raw.display_name === 'string' ? raw.display_name.trim() : '';
    const lat = typeof raw.lat === 'string' ? parseFloat(raw.lat) : typeof raw.lat === 'number' ? raw.lat : NaN;
    const lon = typeof raw.lon === 'string' ? parseFloat(raw.lon) : typeof raw.lon === 'number' ? raw.lon : NaN;

    if (!displayName || Number.isNaN(lat) || Number.isNaN(lon)) {
      continue;
    }

    places.push({
      displayName,
      lat,
      lon,
      placeId: typeof raw.place_id === 'number' || typeof raw.place_id === 'string' ? raw.place_id : undefined,
      type: typeof raw.type === 'string' ? raw.type : undefined,
      class: typeof raw.class === 'string' ? raw.class : undefined,
    });
  }

  return places;
}

/**
 * Searches Nominatim for places matching query.
 * Enforces rate limiting, user agent header, and graceful error handling.
 */
export async function searchPlaces(
  query: string,
  options?: GeocoderOptions
): Promise<GeocodedPlace[]> {
  const trimmed = query.trim();
  if (trimmed.length < 2) {
    return [];
  }

  const endpoint = options?.endpoint ?? NOMINATIM_ENDPOINT;
  const limit = options?.limit ?? 5;
  const minInterval = options?.minIntervalMs ?? 1000;
  const fetchFn = options?.fetchFn ?? (typeof fetch !== 'undefined' ? fetch : undefined);

  if (!fetchFn) {
    return [];
  }

  try {
    if (minInterval > 0) {
      await throttleNominatimRequest(minInterval);
    }

    const url = new URL(endpoint);
    url.searchParams.set('q', trimmed);
    url.searchParams.set('format', 'json');
    url.searchParams.set('limit', String(limit));
    url.searchParams.set('addressdetails', '1');

    const headers: Record<string, string> = {
      Accept: 'application/json',
    };
    if (options?.userAgent) {
      headers['User-Agent'] = options.userAgent;
    } else {
      headers['User-Agent'] = DEFAULT_USER_AGENT;
    }

    const response = await fetchFn(url.toString(), {
      method: 'GET',
      headers,
    });

    if (!response.ok) {
      return [];
    }

    const data = await response.json();
    return parseNominatimResponse(data);
  } catch {
    // Offline or network error: degrade gracefully, do not throw
    return [];
  }
}

export type CandidateStopLookupFn = (
  lat: number,
  lon: number,
  maxRadius?: number,
  flags?: number,
  maxResults?: number
) => number[] | Promise<number[]>;

/**
 * Snaps a geocoded place to its nearest transit station using candidate stop lookup.
 * Returns null if no candidates are found or none match available stops.
 */
export async function resolvePlaceToNearestStation(
  place: { lat: number; lon: number },
  findCandidates: CandidateStopLookupFn,
  stops: StopItem[] | Map<number, StopItem>,
  options?: {
    maxRadius?: number;
    flags?: number;
    maxResults?: number;
    fallbackToDistance?: boolean;
  }
): Promise<StopItem | null> {
  const stopsMap = stops instanceof Map ? stops : new Map(stops.map((s) => [s.id, s]));

  try {
    const candidateIds = await findCandidates(
      place.lat,
      place.lon,
      options?.maxRadius,
      options?.flags,
      options?.maxResults
    );

    if (candidateIds && Array.isArray(candidateIds) && candidateIds.length > 0) {
      for (const id of candidateIds) {
        const found = stopsMap.get(id);
        if (found) {
          return found;
        }
      }
    }
  } catch {
    // Engine lookup error: degrade gracefully
  }

  if (options?.fallbackToDistance) {
    const stopsList = stops instanceof Map ? Array.from(stops.values()) : stops;
    return findNearestStopByCoordinates(place.lat, place.lon, stopsList);
  }

  return null;
}

/**
 * Geometric fallback: finds the closest stop by Euclidean coordinate distance.
 */
export function findNearestStopByCoordinates(
  lat: number,
  lon: number,
  stops: StopItem[]
): StopItem | null {
  if (!stops || stops.length === 0) return null;
  let nearest: StopItem | null = null;
  let minDistSq = Infinity;
  for (const s of stops) {
    const dLat = s.lat - lat;
    const dLon = s.lon - lon;
    const distSq = dLat * dLat + dLon * dLon;
    if (distSq < minDistSq) {
      minDistSq = distSq;
      nearest = s;
    }
  }
  return nearest;
}

export interface SearchLocationsResult {
  stations: StopItem[];
  places: GeocodedPlace[];
}

/**
 * Combined station and online place search with graceful offline degradation.
 * When geocoder fetch throws, gracefully returns station-only results.
 */
export async function searchLocationsWithFallback({
  query,
  stops,
  fetchFn,
  minIntervalMs = 0,
  limitPlaces = 5,
}: {
  query: string;
  stops: StopItem[];
  fetchFn?: typeof fetch;
  minIntervalMs?: number;
  limitPlaces?: number;
}): Promise<SearchLocationsResult> {
  const q = query.trim().toLowerCase();
  if (q.length < 2) {
    return { stations: [], places: [] };
  }

  const matchingStations: StopItem[] = [];
  const seenNames = new Set<string>();
  for (const stop of stops) {
    if (stop.name.toLowerCase().includes(q)) {
      if (!seenNames.has(stop.name)) {
        seenNames.add(stop.name);
        matchingStations.push(stop);
        if (matchingStations.length >= 8) break;
      }
    }
  }

  let places: GeocodedPlace[] = [];
  try {
    places = await searchPlaces(query, {
      fetchFn,
      minIntervalMs,
      limit: limitPlaces,
    });
  } catch {
    places = [];
  }

  return {
    stations: matchingStations,
    places,
  };
}
