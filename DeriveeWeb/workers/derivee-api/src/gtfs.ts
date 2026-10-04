import { transit_realtime } from './proto/gtfs-realtime.js';

export const MTA_FEED_URLS: Record<string, string> = {
  NUMERIC: 'https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/nyct%2Fgtfs',
  ACE: 'https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/nyct%2Fgtfs-ace',
  BDFM: 'https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/nyct%2Fgtfs-bdfm',
  G: 'https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/nyct%2Fgtfs-g',
  JZ: 'https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/nyct%2Fgtfs-jz',
  L: 'https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/nyct%2Fgtfs-l',
  NQRW: 'https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/nyct%2Fgtfs-nqrw',
  SI: 'https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/nyct%2Fgtfs-si',
};

export interface ArrivalPrediction {
  route_id: string;
  direction: string;
  headsign: string;
  predicted_arrival_epoch: number;
  is_realtime: boolean;
  minutesAway?: number;
}

export interface StopPredictions {
  stop_id: string;
  updated_at: number;
  arrivals: ArrivalPrediction[];
}

export function getFeedUrlsForStop(stopId: string, routeId?: string): string[] {
  if (routeId) {
    const cleanRoute = routeId.trim().toUpperCase();
    if (['1', '2', '3', '4', '5', '6', '7', 'GS'].includes(cleanRoute)) {
      return [MTA_FEED_URLS.NUMERIC];
    }
    if (['A', 'C', 'E', 'H', 'FS'].includes(cleanRoute)) {
      return [MTA_FEED_URLS.ACE];
    }
    if (['B', 'D', 'F', 'M'].includes(cleanRoute)) {
      return [MTA_FEED_URLS.BDFM];
    }
    if (cleanRoute === 'G') {
      return [MTA_FEED_URLS.G];
    }
    if (['J', 'Z'].includes(cleanRoute)) {
      return [MTA_FEED_URLS.JZ];
    }
    if (cleanRoute === 'L') {
      return [MTA_FEED_URLS.L];
    }
    if (['N', 'Q', 'R', 'W'].includes(cleanRoute)) {
      return [MTA_FEED_URLS.NQRW];
    }
    if (cleanRoute === 'SI') {
      return [MTA_FEED_URLS.SI];
    }
  }

  if (!stopId) return [MTA_FEED_URLS.NUMERIC];
  const cleanStop = stopId.trim().toUpperCase();
  const first = cleanStop.charAt(0);

  switch (first) {
    case '1':
    case '2':
    case '3':
    case '4':
    case '5':
    case '6':
    case '7':
    case '9':
      return [MTA_FEED_URLS.NUMERIC];
    case 'A':
    case 'C':
    case 'E':
    case 'H':
      return [MTA_FEED_URLS.ACE];
    case 'B':
    case 'D':
    case 'F':
      return [MTA_FEED_URLS.BDFM];
    case 'M':
      return [MTA_FEED_URLS.JZ, MTA_FEED_URLS.BDFM];
    case 'G':
      return [MTA_FEED_URLS.G];
    case 'J':
    case 'Z':
      return [MTA_FEED_URLS.JZ];
    case 'L':
      return [MTA_FEED_URLS.L];
    case 'N':
    case 'Q':
    case 'R':
    case 'W':
      return [MTA_FEED_URLS.NQRW];
    case 'S':
      return [MTA_FEED_URLS.SI, MTA_FEED_URLS.BDFM];
    default:
      return Object.values(MTA_FEED_URLS);
  }
}

export interface FetchFeedOptions {
  cache?: Cache | null;
  cacheTtl?: number;
  timeoutMs?: number;
}

export async function fetchFeedBytes(
  feedUrl: string,
  options?: FetchFeedOptions
): Promise<Uint8Array> {
  const cache =
    options?.cache !== undefined
      ? options.cache
      : typeof caches !== 'undefined'
      ? (caches as any).default
      : null;

  const cacheKey = new Request(feedUrl, { method: 'GET' });

  if (cache) {
    try {
      const cached = await cache.match(cacheKey);
      if (cached) {
        const buf = await cached.arrayBuffer();
        return new Uint8Array(buf);
      }
    } catch {
      // Ignore cache lookup errors, fallback to network
    }
  }

  const timeoutMs = options?.timeoutMs ?? 5000;
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);

  try {
    const res = await fetch(feedUrl, { signal: controller.signal });
    if (!res.ok) {
      throw new Error(`Feed fetch failed with HTTP ${res.status}`);
    }
    const buf = await res.arrayBuffer();
    const array = new Uint8Array(buf);

    if (cache) {
      const ttl = options?.cacheTtl ?? 60;
      const cachedResponse = new Response(array, {
        status: 200,
        headers: {
          'Content-Type': 'application/octet-stream',
          'Cache-Control': `public, max-age=${ttl}`,
        },
      });
      try {
        await cache.put(cacheKey, cachedResponse);
      } catch {
        // Cache put error should not block returning the feed
      }
    }

    return array;
  } finally {
    clearTimeout(timer);
  }
}

export function extractArrivalsFromFeed(
  feedBytes: Uint8Array,
  stopId: string,
  nowEpoch: number = Math.floor(Date.now() / 1000)
): { arrivals: ArrivalPrediction[]; feedTimestamp: number } {
  const feed = transit_realtime.FeedMessage.decode(feedBytes);
  const rawHeaderTime = feed.header?.timestamp as any;
  const feedTimestamp = Number(
    rawHeaderTime?.low ?? rawHeaderTime ?? nowEpoch
  );

  const cleanStopId = stopId.trim().toUpperCase();
  const isPlatformQuery =
    cleanStopId.length > 3 &&
    (cleanStopId.endsWith('N') || cleanStopId.endsWith('S'));
  const queryBaseId = isPlatformQuery ? cleanStopId.slice(0, 3) : cleanStopId;
  const targetDirection = cleanStopId.endsWith('N')
    ? 'NORTH'
    : cleanStopId.endsWith('S')
    ? 'SOUTH'
    : null;

  const arrivals: ArrivalPrediction[] = [];

  for (const entity of feed.entity || []) {
    if (!entity.tripUpdate || !entity.tripUpdate.stopTimeUpdate) continue;

    const trip = entity.tripUpdate.trip;
    const routeId = trip?.routeId || 'UNKNOWN';

    // NYCT direction extension
    let nyctDirection = 'UNKNOWN';
    const nyctDesc = trip
      ? (trip as any)['.transit_realtime.nyctTripDescriptor']
      : null;
    if (nyctDesc?.direction) {
      const d = nyctDesc.direction;
      nyctDirection =
        d === 1
          ? 'NORTH'
          : d === 2
          ? 'EAST'
          : d === 3
          ? 'SOUTH'
          : d === 4
          ? 'WEST'
          : 'UNKNOWN';
    }

    for (const stu of entity.tripUpdate.stopTimeUpdate) {
      if (!stu.arrival || !stu.arrival.time) continue;

      const rawStopId = (stu.stopId || '').trim().toUpperCase();
      if (!rawStopId) continue;

      const baseStopId = rawStopId.slice(0, 3);
      const suffix = rawStopId.length > 3 ? rawStopId.slice(3) : '';

      let direction = nyctDirection;
      if (direction === 'UNKNOWN') {
        if (suffix === 'N') direction = 'NORTH';
        else if (suffix === 'S') direction = 'SOUTH';
      }

      // Check if this stopTime matches the queried stop
      let matches = false;
      if (rawStopId === cleanStopId) {
        matches = true;
      } else if (!isPlatformQuery && baseStopId === queryBaseId) {
        matches = true;
      } else if (isPlatformQuery && baseStopId === queryBaseId) {
        if (!targetDirection || direction === targetDirection) {
          matches = true;
        }
      }

      if (!matches) continue;

      const timeVal =
        typeof stu.arrival.time === 'object'
          ? (stu.arrival.time as any).low
          : stu.arrival.time;
      const arrivalEpoch = Number(timeVal);

      // Skip past arrivals (> 60s ago)
      if (arrivalEpoch < nowEpoch - 60) continue;

      arrivals.push({
        route_id: routeId,
        direction,
        headsign: '',
        predicted_arrival_epoch: arrivalEpoch,
        is_realtime: true,
        minutesAway: Math.max(0, Math.round((arrivalEpoch - nowEpoch) / 60)),
      });
    }
  }

  // Sort ascending by arrival time
  arrivals.sort((a, b) => a.predicted_arrival_epoch - b.predicted_arrival_epoch);

  return { arrivals, feedTimestamp };
}

export async function getLiveArrivalsForStop(
  stopId: string,
  options?: {
    routeId?: string;
    now?: number;
    cache?: Cache | null;
    cacheTtl?: number;
    timeoutMs?: number;
    feedUrls?: string[];
  }
): Promise<StopPredictions> {
  const cleanStopId = stopId.trim().toUpperCase();
  const feedUrls =
    options?.feedUrls ?? getFeedUrlsForStop(cleanStopId, options?.routeId);
  const now = options?.now ?? Math.floor(Date.now() / 1000);

  // Fetch all relevant feeds in parallel
  const results = await Promise.allSettled(
    feedUrls.map((url) =>
      fetchFeedBytes(url, {
        cache: options?.cache,
        cacheTtl: options?.cacheTtl,
        timeoutMs: options?.timeoutMs,
      })
    )
  );

  const successfulBytes: Uint8Array[] = [];
  for (const res of results) {
    if (res.status === 'fulfilled') {
      successfulBytes.push(res.value);
    }
  }

  // If ALL feeds failed, throw error so caller can return 503
  if (successfulBytes.length === 0) {
    const firstRejection = results.find(
      (r) => r.status === 'rejected'
    ) as PromiseRejectedResult | undefined;
    throw new Error(firstRejection?.reason?.message || 'Failed to fetch feeds');
  }

  const allArrivals: ArrivalPrediction[] = [];
  let latestTimestamp = now;
  let decodedFeedsCount = 0;

  for (const bytes of successfulBytes) {
    try {
      const { arrivals, feedTimestamp } = extractArrivalsFromFeed(
        bytes,
        cleanStopId,
        now
      );
      allArrivals.push(...arrivals);
      if (feedTimestamp > latestTimestamp) {
        latestTimestamp = feedTimestamp;
      }
      decodedFeedsCount++;
    } catch (err) {
      console.warn('Failed to decode GTFS-RT feed:', err);
    }
  }

  if (decodedFeedsCount === 0) {
    throw new Error('Failed to decode any GTFS-RT feed');
  }

  // Sort all arrivals ascending
  allArrivals.sort(
    (a, b) => a.predicted_arrival_epoch - b.predicted_arrival_epoch
  );

  return {
    stop_id: cleanStopId,
    updated_at: latestTimestamp,
    arrivals: allArrivals.slice(0, 10),
  };
}
