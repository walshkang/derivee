/**
 * Pure functions and display models for rendering itinerary legs in Dérivée Web.
 *
 * Requirements:
 * - Internal trip IDs (e.g. #0, #1659) must NEVER reach the UI or display model.
 * - Zero-length origin/destination stubs (from_stop === to_stop and duration < 60s)
 *   are collapsed into compact "Start at {station}" and "Arrive at {station}" rows.
 */

export interface LegInput {
  board_stop_id?: number;
  exit_stop_id?: number;
  from_stop?: number;
  to_stop?: number;
  departure_time: number;
  arrival_time: number;
  route_id?: number;
  transfer_distance_m?: number;
  is_transfer?: boolean;
  trip_id?: number;
  station_name?: string;
  stationName?: string;
  station?: string;
  board_stop_name?: string;
  boardStopName?: string;
  board_name?: string;
  exit_stop_name?: string;
  exitStopName?: string;
  exit_name?: string;
}

export type StopNameResolver =
  | ((stopId: number) => string | undefined)
  | Map<number, { name: string } | string>
  | Record<number, string | { name: string }>
  | { getStopName?: (stopId: number) => string | undefined }
  | string;

export interface StartLegDisplay {
  kind: 'start';
  station: string;
  stationName: string;
  stopId: number;
  stop_id: number;
  time: number;
  departureTime: number;
  departure_time: number;
}

export interface ArriveLegDisplay {
  kind: 'arrive';
  station: string;
  stationName: string;
  stopId: number;
  stop_id: number;
  time: number;
  arrivalTime: number;
  arrival_time: number;
}

export interface TransitLegDisplay {
  kind: 'transit';
  legIndex: number;
  leg_index: number;
  boardStopId: number;
  board_stop_id: number;
  exitStopId: number;
  exit_stop_id: number;
  boardStopName: string;
  board_stop_name: string;
  exitStopName: string;
  exit_stop_name: string;
  departureTime: number;
  departure_time: number;
  arrivalTime: number;
  arrival_time: number;
  durationMinutes: number;
  duration_minutes: number;
  durationSeconds: number;
  duration_seconds: number;
  routeId: number;
  route_id: number;
  transferDistanceM: number;
  transfer_distance_m: number;
  isTransfer: boolean;
  is_transfer: boolean;
}

export type LegDisplayModel =
  | StartLegDisplay
  | ArriveLegDisplay
  | TransitLegDisplay;

/**
 * Checks whether a leg is a zero-length stub (from_stop === to_stop and duration < 60s).
 */
export function isZeroLengthLeg(leg: LegInput): boolean {
  const fromStop = leg.from_stop !== undefined ? leg.from_stop : leg.board_stop_id;
  const toStop = leg.to_stop !== undefined ? leg.to_stop : leg.exit_stop_id;
  if (fromStop === undefined || toStop === undefined) {
    return false;
  }
  if (fromStop !== toStop) {
    return false;
  }
  const duration = Math.abs(leg.arrival_time - leg.departure_time);
  return duration < 60;
}

/**
 * Resolves a human-readable station name given a stop ID and optional resolver.
 */
export function resolveStopName(
  stopId: number,
  resolver?: StopNameResolver,
  explicitName?: string
): string {
  if (explicitName && explicitName.trim().length > 0) {
    return explicitName;
  }
  if (typeof resolver === 'string' && resolver.trim().length > 0) {
    return resolver;
  }
  if (typeof resolver === 'function') {
    const resolved = resolver(stopId);
    if (resolved) return resolved;
  } else if (resolver instanceof Map) {
    const val = resolver.get(stopId);
    if (typeof val === 'string' && val.length > 0) return val;
    if (val && typeof val === 'object' && 'name' in val && typeof val.name === 'string') {
      return val.name;
    }
  } else if (resolver && typeof resolver === 'object') {
    if ('getStopName' in resolver && typeof (resolver as any).getStopName === 'function') {
      const resolved = (resolver as any).getStopName(stopId);
      if (resolved) return resolved;
    }
    const val = (resolver as Record<number, any>)[stopId];
    if (typeof val === 'string' && val.length > 0) return val;
    if (val && typeof val === 'object' && 'name' in val && typeof val.name === 'string') {
      return val.name;
    }
  }
  return `Stop #${stopId}`;
}

/**
 * Transforms an itinerary leg into its presentation display model.
 * Note: `trip_id` is completely excluded from all output types.
 */
export function describeLeg(
  leg: LegInput,
  index: number,
  totalLegs: number,
  resolver?: StopNameResolver
): LegDisplayModel {
  const fromStop = leg.from_stop !== undefined ? leg.from_stop : leg.board_stop_id ?? 0;
  const toStop = leg.to_stop !== undefined ? leg.to_stop : leg.exit_stop_id ?? 0;

  if (isZeroLengthLeg(leg)) {
    if (index === 0) {
      const explicitName =
        leg.station ??
        leg.stationName ??
        leg.station_name ??
        leg.board_name ??
        leg.boardStopName ??
        leg.board_stop_name;
      const station = resolveStopName(fromStop, resolver, explicitName);
      return {
        kind: 'start',
        station,
        stationName: station,
        stopId: fromStop,
        stop_id: fromStop,
        time: leg.departure_time,
        departureTime: leg.departure_time,
        departure_time: leg.departure_time,
      };
    }
    if (index === totalLegs - 1) {
      const explicitName =
        leg.station ??
        leg.stationName ??
        leg.station_name ??
        leg.exit_name ??
        leg.exitStopName ??
        leg.exit_stop_name;
      const station = resolveStopName(toStop, resolver, explicitName);
      return {
        kind: 'arrive',
        station,
        stationName: station,
        stopId: toStop,
        stop_id: toStop,
        time: leg.arrival_time,
        arrivalTime: leg.arrival_time,
        arrival_time: leg.arrival_time,
      };
    }
  }

  const explicitBoardName =
    leg.board_name ??
    leg.boardStopName ??
    leg.board_stop_name ??
    leg.station ??
    leg.stationName ??
    leg.station_name;
  const explicitExitName =
    leg.exit_name ??
    leg.exitStopName ??
    leg.exit_stop_name;

  const boardName = resolveStopName(fromStop, resolver, explicitBoardName);
  const exitName = resolveStopName(toStop, resolver, explicitExitName);

  const durationSec = Math.max(0, leg.arrival_time - leg.departure_time);
  const durationMin = Math.max(0, Math.round(durationSec / 60));

  return {
    kind: 'transit',
    legIndex: index,
    leg_index: index,
    boardStopId: fromStop,
    board_stop_id: fromStop,
    exitStopId: toStop,
    exit_stop_id: toStop,
    boardStopName: boardName,
    board_stop_name: boardName,
    exitStopName: exitName,
    exit_stop_name: exitName,
    departureTime: leg.departure_time,
    departure_time: leg.departure_time,
    arrivalTime: leg.arrival_time,
    arrival_time: leg.arrival_time,
    durationMinutes: durationMin,
    duration_minutes: durationMin,
    durationSeconds: durationSec,
    duration_seconds: durationSec,
    routeId: leg.route_id ?? 0,
    route_id: leg.route_id ?? 0,
    transferDistanceM: leg.transfer_distance_m ?? 0,
    transfer_distance_m: leg.transfer_distance_m ?? 0,
    isTransfer: Boolean(leg.is_transfer),
    is_transfer: Boolean(leg.is_transfer),
  };
}

/**
 * Transforms an array of itinerary legs into display models.
 */
export function describeItinerary(
  legs: LegInput[],
  resolver?: StopNameResolver
): LegDisplayModel[] {
  return legs.map((leg, index) => describeLeg(leg, index, legs.length, resolver));
}
