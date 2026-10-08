/**
 * routeComparison.ts
 * Screen 4B Multimodal Route Comparison & Profile Ranking.
 *
 * Implements:
 * - Sequential two-query routing flow across the single WASM worker
 *   (Fastest with flags=0, then Fewest Transfers with flags=2).
 * - Exact itinerary deduplication (collapsing identical paths to a single card badged with both profiles).
 * - Ranking, sorting, human duration formatting, transfer counts, and UI state classification.
 *
 * Design Ground Truth:
 * - design.md §12.3 (Screen 4B route comparison: arrival, transfers, timetable-only).
 * - design.md §13.2 (Screen 4B row: profile selector bar, ranked cards, human durations, no raw seconds).
 * - FC-2: zero raw database IDs or internal tokens in UI copy.
 */

import type {
  RoutingSegment,
  RoutingProfile,
  RankedItinerary,
  RoutingWorkerIncomingMessage,
  RoutingWorkerOutgoingMessage,
} from '../types/routing.ts';
import {
  ROUTING_FLAG_NONE,
  ROUTING_FLAG_AVOID_TRANSFERS,
  ROUTING_FLAG_MINIMIZE_WALKING,
} from '../types/routing.ts';


/**
 * Checks whether two itineraries are completely identical across all segments.
 */
export function areItinerariesIdentical(
  a: RoutingSegment[] | null | undefined,
  b: RoutingSegment[] | null | undefined
): boolean {
  if (!a || !b) return false;
  if (a.length !== b.length) return false;
  if (a.length === 0 && b.length === 0) return true;

  for (let i = 0; i < a.length; i++) {
    const sA = a[i];
    const sB = b[i];
    if (
      sA.board_stop_id !== sB.board_stop_id ||
      sA.exit_stop_id !== sB.exit_stop_id ||
      sA.route_id !== sB.route_id ||
      sA.departure_time !== sB.departure_time ||
      sA.arrival_time !== sB.arrival_time ||
      Boolean(sA.is_transfer) !== Boolean(sB.is_transfer)
    ) {
      return false;
    }
    if (sA.is_transfer && sA.transfer_distance_m !== sB.transfer_distance_m) {
      return false;
    }
  }
  return true;
}

/**
 * Calculates transfer count from itinerary segments.
 * Each non-transfer transit leg represents boarding a vehicle.
 * Transfers = max(0, transitLegCount - 1).
 */
export function countTransfers(segments: RoutingSegment[]): number {
  if (!segments || segments.length === 0) return 0;
  const transitLegs = segments.filter((s) => !s.is_transfer);
  return Math.max(0, transitLegs.length - 1);
}

/**
 * Human-friendly commuter transfer badge text (design.md §12.3 / §13.2).
 */
export function formatTransferCount(count: number): string {
  if (count <= 0) return 'No transfers';
  if (count === 1) return '1 transfer';
  return `${count} transfers`;
}

/**
 * Formats duration into commuter-readable human string (design.md §13.2 rejection: raw seconds).
 * Always returns formatted human duration (e.g. "24 min" or "1 hr 15 min").
 */
export function formatDurationHuman(seconds: number): string {
  const totalMinutes = Math.max(1, Math.round(seconds / 60));
  if (totalMinutes < 60) {
    return `${totalMinutes} min`;
  }
  const hours = Math.floor(totalMinutes / 60);
  const remainingMinutes = totalMinutes % 60;
  if (remainingMinutes === 0) {
    return `${hours} hr`;
  }
  return `${hours} hr ${remainingMinutes} min`;
}

/**
 * Formats seconds-of-day into HH:MM (24-hour timetable format).
 */
export function formatClockTime(sec: number): string {
  const h = Math.floor(sec / 3600) % 24;
  const m = Math.floor((sec % 3600) / 60);
  return `${h.toString().padStart(2, '0')}:${m.toString().padStart(2, '0')}`;
}

/**
 * Formats seconds-of-day into commuter glance arrival time (e.g. "8:24 AM", design.md §12.3).
 */
export function formatArrivalTime(sec: number): string {
  const h24 = Math.floor(sec / 3600) % 24;
  const m = Math.floor((sec % 3600) / 60);
  const h12 = h24 % 12 || 12;
  const ampm = h24 < 12 ? 'AM' : 'PM';
  return `${h12}:${m.toString().padStart(2, '0')} ${ampm}`;
}

/**
 * Converts a "HH:MM" 24-hour time string into seconds of the day.
 * Falls back to 28800 (8:00 AM) if invalid or malformed.
 */
export function getDepartureSeconds(timeStr: string): number {
  if (!timeStr || typeof timeStr !== 'string') return 28800;
  const parts = timeStr.split(':');
  if (parts.length === 2) {
    const h = parseInt(parts[0], 10);
    const m = parseInt(parts[1], 10);
    if (!isNaN(h) && !isNaN(m) && h >= 0 && h < 24 && m >= 0 && m < 60) {
      return h * 3600 + m * 60;
    }
  }
  return 28800; // 8:00 AM fallback
}

/**
 * Computes departure timestamp in seconds of the day based on departure timing mode.
 * - 'now': uses the CURRENT time (hours * 3600 + minutes * 60 + seconds).
 * - 'depart_at': uses the explicit "HH:MM" user-selected time string.
 */
export function computeDepartureSeconds(
  mode: 'now' | 'depart_at',
  departureTimeStr: string,
  now: Date = new Date()
): number {
  if (mode === 'now') {
    return now.getHours() * 3600 + now.getMinutes() * 60 + now.getSeconds();
  }
  return getDepartureSeconds(departureTimeStr);
}

/**
 * Constructs a single RankedItinerary display model from segments and profile attribution.
 */
export function createRankedItinerary(
  segments: RoutingSegment[],
  primaryProfile: RoutingProfile,
  allProfiles: RoutingProfile[] = [primaryProfile],
  isDeduped: boolean = false
): RankedItinerary {
  const first = segments[0];
  const last = segments[segments.length - 1];
  const dep = first ? first.departure_time : 0;
  const arr = last ? last.arrival_time : 0;
  const durationSec = Math.max(0, arr - dep);
  const durationMin = Math.max(1, Math.round(durationSec / 60));
  const transferCount = countTransfers(segments);

  return {
    id: isDeduped ? 'itinerary-optimal-deduped' : `itinerary-${primaryProfile}`,
    profile: primaryProfile,
    profiles: allProfiles,
    segments,
    departureTime: dep,
    arrivalTime: arr,
    durationSeconds: durationSec,
    durationMinutes: durationMin,
    transferCount,
    isDeduped,
  };
}

/**
 * Assembles and ranks itinerary cards from the two query results.
 * Deduplicates identical itineraries into a single card badged with both profiles.
 *
 * UX Justification for dual-badging deduped cards:
 * When the fastest route is ALSO the route with the fewest transfers (a very common transit scenario),
 * showing both badges [⚡ Fastest] [🔄 Fewest Transfers] explicitly reassures the commuter that their
 * transfer preference was evaluated and that no faster alternative exists, eliminating ambiguity.
 */
export function buildRankedItineraries(
  fastestSegments: RoutingSegment[] | null,
  fewestTransfersSegments: RoutingSegment[] | null,
  activeSortProfile: RoutingProfile = 'fastest'
): RankedItinerary[] {
  const hasFastest = Boolean(fastestSegments && fastestSegments.length > 0);
  const hasFewest = Boolean(fewestTransfersSegments && fewestTransfersSegments.length > 0);

  if (!hasFastest && !hasFewest) {
    return [];
  }

  if (hasFastest && hasFewest) {
    if (areItinerariesIdentical(fastestSegments!, fewestTransfersSegments!)) {
      // Deduplicate to single optimal card badged with both profiles
      return [
        createRankedItinerary(
          fastestSegments!,
          'fastest',
          ['fastest', 'fewest_transfers'],
          true
        ),
      ];
    }

    // Two differing routes
    const fastestCard = createRankedItinerary(fastestSegments!, 'fastest', ['fastest'], false);
    const fewestCard = createRankedItinerary(
      fewestTransfersSegments!,
      'fewest_transfers',
      ['fewest_transfers'],
      false
    );

    if (activeSortProfile === 'fewest_transfers') {
      return [fewestCard, fastestCard];
    }
    return [fastestCard, fewestCard];
  }

  if (hasFastest) {
    return [createRankedItinerary(fastestSegments!, 'fastest', ['fastest'], false)];
  }

  return [
    createRankedItinerary(fewestTransfersSegments!, 'fewest_transfers', ['fewest_transfers'], false),
  ];
}

export interface RoutingWorkerLike {
  postMessage: (msg: RoutingWorkerIncomingMessage) => void;
  addEventListener?: (type: string, listener: (event: any) => void) => void;
  removeEventListener?: (type: string, listener: (event: any) => void) => void;
  onmessage?: ((event: MessageEvent<RoutingWorkerOutgoingMessage>) => void) | null;
  onerror?: ((err: any) => void) | null;
}

/**
 * Sequentially executes the two profile routing queries on the worker:
 * 1. Flags=0 (Fastest)
 * 2. Flags=2 (Fewest Transfers)
 *
 * Enforces sequential dispatch: query 2 is NEVER posted until query 1 has completed.
 * Guarantees zero C++ concurrency race conditions and avoids spawning a duplicate 55MB worker.
 */
export async function executeDualProfileRouting(
  worker: RoutingWorkerLike,
  originStopId: number,
  destStopId: number,
  departureTimestamp: number,
  options?: {
    timeoutMs?: number;
    onProgress?: (stage: RoutingProfile) => void;
  }
): Promise<{
  fastest: RoutingSegment[];
  fewestTransfers: RoutingSegment[];
  lessWalking: RoutingSegment[];
}> {
  const timeoutMs = options?.timeoutMs ?? 8000;

  function runSingleQuery(
    profile: RoutingProfile,
    flags: number,
    queryId: string
  ): Promise<RoutingSegment[]> {
    return new Promise((resolve, reject) => {
      let timer: ReturnType<typeof setTimeout> | null = null;

      const messageHandler = (event: MessageEvent<RoutingWorkerOutgoingMessage>) => {
        const data = event.data;
        if (data.type === 'RESULT' && (data.queryId === undefined || data.queryId === queryId)) {
          cleanup();
          resolve(data.segments);
        } else if (data.type === 'ERROR' && (data.queryId === undefined || data.queryId === queryId)) {
          cleanup();
          reject(new Error(data.message));
        }
      };

      const errorHandler = (err: any) => {
        cleanup();
        reject(err instanceof Error ? err : new Error(String(err)));
      };

      const cleanup = () => {
        if (timer) clearTimeout(timer);
        if (typeof worker.removeEventListener === 'function') {
          worker.removeEventListener('message', messageHandler);
          worker.removeEventListener('error', errorHandler);
        }
      };

      if (typeof worker.addEventListener === 'function') {
        worker.addEventListener('message', messageHandler);
        worker.addEventListener('error', errorHandler);
      } else {
        const prevOnMessage = worker.onmessage;
        worker.onmessage = (e) => {
          messageHandler(e);
          prevOnMessage?.(e);
        };
      }

      timer = setTimeout(() => {
        cleanup();
        reject(new Error(`Routing query timed out for profile ${profile}`));
      }, timeoutMs);

      worker.postMessage({
        type: 'ROUTE',
        origin_stop_id: originStopId,
        dest_stop_id: destStopId,
        departure_timestamp: departureTimestamp,
        profile,
        flags,
        queryId,
      });
    });
  }

  // 1. Query Fastest (flags: 0)
  options?.onProgress?.('fastest');
  const fastest = await runSingleQuery('fastest', ROUTING_FLAG_NONE, 'query-fastest');

  // 2. Query Fewest Transfers (flags: 2) sequentially
  options?.onProgress?.('fewest_transfers');
  const fewestTransfers = await runSingleQuery(
    'fewest_transfers',
    ROUTING_FLAG_AVOID_TRANSFERS,
    'query-transfers'
  );

  // 3. Query Less Walking (flags: 4) sequentially
  options?.onProgress?.('less_walking');
  const lessWalking = await runSingleQuery(
    'less_walking',
    ROUTING_FLAG_MINIMIZE_WALKING,
    'query-walking'
  );

  return { fastest, fewestTransfers, lessWalking };
}

export type RouteComparisonUIStateKind =
  | 'loading'
  | 'one_result'
  | 'two_results'
  | 'deduped'
  | 'error'
  | 'empty';

export interface RouteComparisonUIState {
  state: RouteComparisonUIStateKind;
  userFacingTitle: string;
  userFacingDescription: string;
  hasCards: boolean;
  cardCount: number;
}

/**
 * Explicitly enumerates the 6 UI states and what the commuter sees in each:
 * 1. loading: active search progress indicator
 * 2. error: explicit error banner with diagnostic message
 * 3. empty: clean notice that no route connects stops at this time
 * 4. one_result: single card for the available profile
 * 5. two_results: 2 ranked cards reorderable by profile selector
 * 6. deduped: single optimal card badged with both profiles
 */
export function getRouteComparisonUIState(params: {
  isRouting: boolean;
  routeError: string | null;
  rankedCards: RankedItinerary[];
  hasQueried: boolean;
}): RouteComparisonUIState {
  if (params.isRouting) {
    return {
      state: 'loading',
      userFacingTitle: 'Routing offline trip...',
      userFacingDescription: 'Evaluating fastest and fewest-transfer routes via offline RAPTOR engine',
      hasCards: false,
      cardCount: 0,
    };
  }

  if (params.routeError) {
    return {
      state: 'error',
      userFacingTitle: 'Route Calculation Error',
      userFacingDescription: params.routeError,
      hasCards: false,
      cardCount: 0,
    };
  }

  if (!params.hasQueried || params.rankedCards.length === 0) {
    return {
      state: 'empty',
      userFacingTitle: 'No routes found',
      userFacingDescription: 'No route found between selected stops at this departure time.',
      hasCards: false,
      cardCount: 0,
    };
  }

  if (params.rankedCards.length === 1 && params.rankedCards[0].isDeduped) {
    return {
      state: 'deduped',
      userFacingTitle: 'Optimal Route (Fastest + Fewest Transfers)',
      userFacingDescription: 'Single optimal route found that satisfies both fastest travel time and minimal transfers',
      hasCards: true,
      cardCount: 1,
    };
  }

  if (params.rankedCards.length === 1) {
    return {
      state: 'one_result',
      userFacingTitle: 'Single Route Available',
      userFacingDescription: 'Found 1 route for selected profile',
      hasCards: true,
      cardCount: 1,
    };
  }

  return {
    state: 'two_results',
    userFacingTitle: '2 Alternative Routes Available',
    userFacingDescription: 'Comparing fastest arrival vs fewest transfers',
    hasCards: true,
    cardCount: 2,
  };
}
