/**
 * Pure functions and display models for rendering itinerary legs in Dérivée Web.
 *
 * Requirements:
 * - Internal trip IDs (e.g. #0, #1659) must NEVER reach the UI or display model.
 * - Zero-length origin/destination stubs (from_stop === to_stop and duration < 60s)
 *   are collapsed into compact "Start at {station}" and "Arrive at {station}" rows.
 */

import type { RoutePatternEntry } from '../types/routing.ts';

export type LegMode = 'transit' | 'walk' | 'transfer';

export type PatternResolver =
  | ((patternIndex: number) => string | undefined)
  | RoutePatternEntry[]
  | string[]
  | Map<number, string>;

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
  mode?: LegMode;
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

export interface LegStopDetail {
  stopId: number;
  stopName: string;
  time: number;
  isBoarding: boolean;
  isAlighting: boolean;
}

export interface TransitLegDisplay {
  kind: 'transit';
  mode: LegMode;
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
  routeId?: number | string;
  route_id?: number | string;
  transferDistanceM: number;
  transfer_distance_m: number;
  isTransfer: boolean;
  is_transfer: boolean;
  intermediateStopsCount?: number;
  stopCount?: number;
  headsign?: string;
  stops?: LegStopDetail[];
}

export interface TransferConnectorDisplay {
  kind: 'connector';
  station: string;
  stationName: string;
  stopId: number;
  stop_id: number;
  text: string;
  durationMinutes: number;
  duration_minutes: number;
  durationSeconds: number;
  duration_seconds: number;
  transferDistanceM: number;
  transfer_distance_m: number;
}

export interface WalkAccessDisplay {
  kind: 'walk';
  mode: 'walk';
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
  transferDistanceM: number;
  transfer_distance_m: number;
}

export type LegDisplayModel =
  | StartLegDisplay
  | ArriveLegDisplay
  | TransferConnectorDisplay
  | WalkAccessDisplay
  | TransitLegDisplay;

/**
 * Normalizes a station name for comparison by removing punctuation variations and extra whitespace.
 */
function normalizeStationName(name: string): string {
  return name.trim().toLowerCase().replace(/\s*-\s*/g, '-').replace(/\s+/g, ' ');
}

/**
 * Checks whether a leg is a zero-length stub:
 * - duration < 60s AND
 * - either from_stop === to_stop OR both stops resolve to the same station name.
 */
export function isZeroLengthLeg(leg: LegInput, resolver?: StopNameResolver): boolean {
  const fromStop = leg.from_stop !== undefined ? leg.from_stop : leg.board_stop_id;
  const toStop = leg.to_stop !== undefined ? leg.to_stop : leg.exit_stop_id;
  if (fromStop === undefined || toStop === undefined) {
    return false;
  }
  const duration = Math.abs(leg.arrival_time - leg.departure_time);
  if (duration >= 60) {
    return false;
  }
  if (fromStop === toStop) {
    return true;
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

  if (boardName && exitName) {
    const normBoard = normalizeStationName(boardName);
    const normExit = normalizeStationName(exitName);
    // Same station if normalized names match and are not unresolved fallbacks (e.g. Stop #72 vs Stop #74)
    if (normBoard === normExit && !normBoard.startsWith('stop #')) {
      return true;
    }
  }

  return false;
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
 * Formats a destination headsign using commuter-first "To [Terminal]" style.
 * Strictly adheres to FC-2 (no internal IDs or raw hashes leak into the UI).
 */
export function formatHeadsign(headsign?: string, fallbackDestination?: string): string {
  const sanitize = (val: string) => {
    return val
      .replace(/^(?:trip_id_|route_id_|route_|trip_)\w+/gi, '')
      .replace(/^#\d+/g, '')
      .trim();
  };

  if (headsign && headsign.trim().length > 0) {
    const cleaned = sanitize(headsign);
    if (cleaned.length > 0) {
      if (/^to\s+/i.test(cleaned)) {
        return cleaned;
      }
      return `To ${cleaned}`;
    }
  }

  if (fallbackDestination && fallbackDestination.trim().length > 0) {
    const cleaned = sanitize(fallbackDestination);
    if (cleaned.length > 0) {
      if (/^to\s+/i.test(cleaned)) {
        return cleaned;
      }
      return `To ${cleaned}`;
    }
  }

  return '';
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

  if (isZeroLengthLeg(leg, resolver)) {
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

  const mode: LegMode = leg.mode ?? (leg.is_transfer ? 'transfer' : 'transit');

  return {
    kind: 'transit',
    mode,
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
    routeId: leg.route_id,
    route_id: leg.route_id,
    transferDistanceM: leg.transfer_distance_m ?? 0,
    transfer_distance_m: leg.transfer_distance_m ?? 0,
    isTransfer: Boolean(leg.is_transfer || mode === 'transfer' || mode === 'walk'),
    is_transfer: Boolean(leg.is_transfer || mode === 'transfer' || mode === 'walk'),
    intermediateStopsCount: 0,
    stopCount: 0,
    stops: [
      {
        stopId: fromStop,
        stopName: boardName,
        time: leg.departure_time,
        isBoarding: true,
        isAlighting: false,
      },
      {
        stopId: toStop,
        stopName: exitName,
        time: leg.arrival_time,
        isBoarding: false,
        isAlighting: true,
      },
    ],
  };
}

export const TRIP_TRANSFER = 0xFFFFFFFF;
export const ROUTE_TRANSFER = 0xFFFF;

export function isTransferLeg(tripId?: number, routeId?: number): boolean {
  return tripId === TRIP_TRANSFER || routeId === ROUTE_TRANSFER;
}

export function isTransitLeg(leg: LegInput): boolean {
  if (leg.mode === 'transit') return true;
  if (leg.mode === 'walk' || leg.mode === 'transfer') return false;
  if (leg.is_transfer) return false;
  if (isTransferLeg(leg.trip_id, leg.route_id)) return false;
  if (leg.trip_id === 0 && leg.route_id === 0 && (leg.transfer_distance_m ?? 0) > 0) return false;
  if ((leg.trip_id !== undefined && leg.trip_id > 0) || (leg.route_id !== undefined && leg.route_id > 0)) {
    return true;
  }
  const fromStop = leg.from_stop !== undefined ? leg.from_stop : leg.board_stop_id;
  const toStop = leg.to_stop !== undefined ? leg.to_stop : leg.exit_stop_id;
  if (!leg.is_transfer && fromStop !== undefined && toStop !== undefined && fromStop !== toStop) {
    return true;
  }
  return false;
}

export function isPhantomTransfer(leg: LegInput, _resolver?: StopNameResolver): boolean {
  const dur = Math.abs(leg.arrival_time - leg.departure_time);
  const dist = leg.transfer_distance_m ?? 0;
  if (dur === 0 && dist === 0) return true;
  const fromStop = leg.from_stop !== undefined ? leg.from_stop : leg.board_stop_id;
  const toStop = leg.to_stop !== undefined ? leg.to_stop : leg.exit_stop_id;
  if (fromStop === toStop && dur < 60 && dist === 0 && (!leg.trip_id || leg.trip_id === 0)) {
    return true;
  }
  return false;
}

export function canMergeTransitLegs(
  prev: LegInput,
  curr: LegInput,
  resolver?: StopNameResolver
): boolean {
  if (
    prev.trip_id !== undefined &&
    curr.trip_id !== undefined &&
    prev.trip_id > 0 &&
    curr.trip_id > 0
  ) {
    return prev.trip_id === curr.trip_id;
  }
  if (
    prev.trip_id !== undefined &&
    curr.trip_id !== undefined &&
    prev.trip_id !== curr.trip_id &&
    prev.trip_id > 0 &&
    curr.trip_id > 0
  ) {
    return false;
  }
  if (
    prev.route_id !== undefined &&
    curr.route_id !== undefined &&
    prev.route_id === curr.route_id
  ) {
    const prevTo = prev.to_stop !== undefined ? prev.to_stop : prev.exit_stop_id;
    const currFrom = curr.from_stop !== undefined ? curr.from_stop : curr.board_stop_id;
    const continuousStops =
      prevTo !== undefined &&
      currFrom !== undefined &&
      (prevTo === currFrom ||
        (resolveStopName(prevTo, resolver) === resolveStopName(currFrom, resolver) &&
          !resolveStopName(prevTo, resolver).toLowerCase().startsWith('stop #')));
    const noAlighting =
      curr.departure_time >= prev.arrival_time &&
      curr.departure_time - prev.arrival_time <= 180;
    return continuousStops && noAlighting;
  }
  return false;
}

/**
 * Transforms an array of itinerary legs into grouped presentation display models.
 * Groups consecutive transit hops on the same vehicle into a single ride leg.
 * Renders transfers as connector rows between ride legs.
 */
export function describeItinerary(
  legs: LegInput[],
  resolver?: StopNameResolver,
  patternResolver?: PatternResolver
): LegDisplayModel[] {
  if (!legs || legs.length === 0) return [];

  const hasStartStub = isZeroLengthLeg(legs[0], resolver);
  const hasArriveStub = legs.length > 1 && isZeroLengthLeg(legs[legs.length - 1], resolver);

  const startLeg = hasStartStub ? describeLeg(legs[0], 0, legs.length, resolver) : null;
  const arriveLeg = hasArriveStub
    ? describeLeg(legs[legs.length - 1], legs.length - 1, legs.length, resolver)
    : null;

  const startIndex = hasStartStub ? 1 : 0;
  const endIndex = hasArriveStub ? legs.length - 1 : legs.length;
  const middle = legs.slice(startIndex, endIndex);

  if (middle.length === 0) {
    const res: LegDisplayModel[] = [];
    if (startLeg) res.push(startLeg);
    if (arriveLeg) res.push(arriveLeg);
    return res;
  }

  const activeLegs = middle.filter((leg) => !isPhantomTransfer(leg, resolver));
  const operationalLegs = activeLegs.length > 0 ? activeLegs : middle;

  interface GroupedBlock {
    type: 'transit' | 'transfer' | 'walk';
    legs: LegInput[];
  }

  const blocks: GroupedBlock[] = [];
  for (const leg of operationalLegs) {
    const isTransit = isTransitLeg(leg);
    const blockType = isTransit ? 'transit' : (leg.mode === 'walk' ? 'walk' : 'transfer');

    if (blocks.length === 0) {
      blocks.push({ type: blockType, legs: [leg] });
      continue;
    }

    const lastBlock = blocks[blocks.length - 1];
    if (lastBlock.type === 'transit' && blockType === 'transit') {
      const prevLeg = lastBlock.legs[lastBlock.legs.length - 1];
      if (canMergeTransitLegs(prevLeg, leg, resolver)) {
        lastBlock.legs.push(leg);
        continue;
      }
    }

    if (lastBlock.type === blockType && blockType !== 'transit') {
      lastBlock.legs.push(leg);
      continue;
    }

    blocks.push({ type: blockType, legs: [leg] });
  }

  const result: LegDisplayModel[] = [];
  if (startLeg) {
    result.push(startLeg);
  }

  let transitRideIndex = 0;

  for (let i = 0; i < blocks.length; i++) {
    const block = blocks[i];

    if (block.type === 'transit') {
      const first = block.legs[0];
      const last = block.legs[block.legs.length - 1];
      const fromStop = first.from_stop !== undefined ? first.from_stop : first.board_stop_id ?? 0;
      const toStop = last.to_stop !== undefined ? last.to_stop : last.exit_stop_id ?? 0;

      const explicitBoardName =
        first.board_name ??
        first.boardStopName ??
        first.board_stop_name ??
        first.station ??
        first.stationName ??
        first.station_name;
      const explicitExitName =
        last.exit_name ??
        last.exitStopName ??
        last.exit_stop_name ??
        last.station ??
        last.stationName ??
        last.station_name;

      const boardName = resolveStopName(fromStop, resolver, explicitBoardName);
      const exitName = resolveStopName(toStop, resolver, explicitExitName);

      const depTime = first.departure_time;
      const arrTime = last.arrival_time;
      const durationSec = Math.max(0, arrTime - depTime);
      const durationMin = Math.max(0, Math.round(durationSec / 60));
      const intermediateStopsCount = block.legs.length - 1;

      let resolvedRouteId: string | number | undefined;
      let resolvedHeadsign: string | undefined;
      if (patternResolver && first.route_id !== undefined) {
        if (Array.isArray(patternResolver)) {
          const entry = patternResolver[first.route_id];
          if (typeof entry === 'string') {
            resolvedRouteId = entry;
          } else if (entry && typeof entry === 'object') {
            resolvedRouteId = entry.route_id;
            resolvedHeadsign = entry.headsign;
          }
        } else if (typeof patternResolver === 'function') {
          resolvedRouteId = patternResolver(first.route_id);
        } else if (patternResolver instanceof Map) {
          const entry = patternResolver.get(first.route_id);
          if (typeof entry === 'string') {
            resolvedRouteId = entry;
          } else if (entry && typeof entry === 'object') {
            resolvedRouteId = (entry as any).route_id;
            resolvedHeadsign = (entry as any).headsign;
          }
        }
      }
      
      const finalRouteId = resolvedRouteId ?? (patternResolver ? undefined : first.route_id);

      const legStops: LegStopDetail[] = [];
      legStops.push({
        stopId: fromStop,
        stopName: boardName,
        time: depTime,
        isBoarding: true,
        isAlighting: false,
      });

      for (let sIdx = 0; sIdx < block.legs.length - 1; sIdx++) {
        const seg = block.legs[sIdx];
        const nextSeg = block.legs[sIdx + 1];
        const stopId = seg.exit_stop_id !== undefined ? seg.exit_stop_id : seg.to_stop ?? 0;
        const name = resolveStopName(stopId, resolver);
        const time = seg.arrival_time || nextSeg.departure_time;
        legStops.push({
          stopId,
          stopName: name,
          time,
          isBoarding: false,
          isAlighting: false,
        });
      }

      legStops.push({
        stopId: toStop,
        stopName: exitName,
        time: arrTime,
        isBoarding: false,
        isAlighting: true,
      });

      const transitModel: TransitLegDisplay = {
        kind: 'transit',
        mode: 'transit',
        legIndex: transitRideIndex,
        leg_index: transitRideIndex,
        boardStopId: fromStop,
        board_stop_id: fromStop,
        exitStopId: toStop,
        exit_stop_id: toStop,
        boardStopName: boardName,
        board_stop_name: boardName,
        exitStopName: exitName,
        exit_stop_name: exitName,
        departureTime: depTime,
        departure_time: depTime,
        arrivalTime: arrTime,
        arrival_time: arrTime,
        durationMinutes: durationMin,
        duration_minutes: durationMin,
        durationSeconds: durationSec,
        duration_seconds: durationSec,
        routeId: finalRouteId,
        route_id: finalRouteId,
        transferDistanceM: 0,
        transfer_distance_m: 0,
        isTransfer: false,
        is_transfer: false,
        intermediateStopsCount,
        stopCount: intermediateStopsCount,
        headsign: resolvedHeadsign,
        stops: legStops,
      };

      result.push(transitModel);
      transitRideIndex++;
    } else {
      const prevBlock = i > 0 ? blocks[i - 1] : null;
      const nextBlock = i + 1 < blocks.length ? blocks[i + 1] : null;

      if (prevBlock && prevBlock.type === 'transit' && nextBlock && nextBlock.type === 'transit') {
        const first = block.legs[0];
        const last = block.legs[block.legs.length - 1];
        const prevTransitLast = prevBlock.legs[prevBlock.legs.length - 1];
        const changeStopId =
          first.board_stop_id ??
          first.from_stop ??
          prevTransitLast.exit_stop_id ??
          prevTransitLast.to_stop ??
          0;
        const station = resolveStopName(changeStopId, resolver);
        const totalDist = block.legs.reduce((acc, l) => acc + (l.transfer_distance_m ?? 0), 0);
        const depTime = first.departure_time;
        const arrTime = last.arrival_time;
        const durSec = Math.max(0, arrTime - depTime);
        const durMin = Math.max(0, Math.round(durSec / 60));

        const connector: TransferConnectorDisplay = {
          kind: 'connector',
          station,
          stationName: station,
          stopId: changeStopId,
          stop_id: changeStopId,
          text: `Change at ${station}`,
          durationMinutes: durMin,
          duration_minutes: durMin,
          durationSeconds: durSec,
          duration_seconds: durSec,
          transferDistanceM: totalDist,
          transfer_distance_m: totalDist,
        };
        result.push(connector);
      } else {
        const first = block.legs[0];
        const last = block.legs[block.legs.length - 1];
        const fromStop = first.board_stop_id ?? first.from_stop ?? 0;
        const toStop = last.exit_stop_id ?? last.to_stop ?? 0;
        const boardName = resolveStopName(fromStop, resolver);
        const exitName = resolveStopName(toStop, resolver);
        const totalDist = block.legs.reduce((acc, l) => acc + (l.transfer_distance_m ?? 0), 0);
        const depTime = first.departure_time;
        const arrTime = last.arrival_time;
        const durSec = Math.max(0, arrTime - depTime);
        const durMin = Math.max(0, Math.round(durSec / 60));

        const walkModel: WalkAccessDisplay = {
          kind: 'walk',
          mode: 'walk',
          boardStopId: fromStop,
          board_stop_id: fromStop,
          exitStopId: toStop,
          exit_stop_id: toStop,
          boardStopName: boardName,
          board_stop_name: boardName,
          exitStopName: exitName,
          exit_stop_name: exitName,
          departureTime: depTime,
          departure_time: depTime,
          arrivalTime: arrTime,
          arrival_time: arrTime,
          durationMinutes: durMin,
          duration_minutes: durMin,
          durationSeconds: durSec,
          duration_seconds: durSec,
          transferDistanceM: totalDist,
          transfer_distance_m: totalDist,
        };
        result.push(walkModel);
      }
    }
  }

  // Insert transfer connector if two transit blocks were adjacent without explicit transfer leg
  const finalResult: LegDisplayModel[] = [];
  for (let j = 0; j < result.length; j++) {
    finalResult.push(result[j]);
    if (
      result[j].kind === 'transit' &&
      j + 1 < result.length &&
      result[j + 1].kind === 'transit'
    ) {
      const prevTransit = result[j] as TransitLegDisplay;
      const nextTransit = result[j + 1] as TransitLegDisplay;
      const changeStation = prevTransit.exitStopName;
      const durSec = Math.max(0, nextTransit.departureTime - prevTransit.arrivalTime);
      const durMin = Math.max(0, Math.round(durSec / 60));

      finalResult.push({
        kind: 'connector',
        station: changeStation,
        stationName: changeStation,
        stopId: prevTransit.exitStopId,
        stop_id: prevTransit.exitStopId,
        text: `Change at ${changeStation}`,
        durationMinutes: durMin,
        duration_minutes: durMin,
        durationSeconds: durSec,
        duration_seconds: durSec,
        transferDistanceM: 0,
        transfer_distance_m: 0,
      });
    }
  }

  if (arriveLeg) {
    finalResult.push(arriveLeg);
  }

  return finalResult;
}

/**
 * Calculates true commuter transfer count from itinerary legs.
 * Commuter transfers = actual vehicle changes = (transit ride legs - 1).
 */
export function countTransfers(legs: LegInput[], resolver?: StopNameResolver): number {
  if (!legs || legs.length === 0) return 0;
  const models = describeItinerary(legs, resolver);
  const transitLegs = models.filter((m) => m.kind === 'transit');
  return Math.max(0, transitLegs.length - 1);
}

export interface LiveArrivalMatch {
  isLive: boolean;
  minutesAway: number;
  isApproaching: boolean;
}

/**
 * Matches realtime arrival predictions against the leg route and computes ETA minutes.
 * Handles both GTFS-RT predicted_arrival_epoch (seconds) and pre-calculated minutesAway.
 * Returns null if no match or if data is empty/invalid (triggering clean fallback to scheduled times).
 */
export function matchLiveArrival(
  arrivals: any[] | null | undefined,
  targetRoute: string | null | undefined,
  nowEpoch: number = Math.floor(Date.now() / 1000)
): LiveArrivalMatch | null {
  if (!Array.isArray(arrivals) || arrivals.length === 0 || !targetRoute) {
    return null;
  }
  const cleanTarget = targetRoute.trim().toLowerCase();
  if (!cleanTarget) return null;

  const match = arrivals.find((arr) => {
    if (!arr) return false;
    const rId = String(arr.route_id || '').trim().toLowerCase();
    return rId === cleanTarget;
  });

  if (!match) return null;

  let minutesAway: number | null = null;
  if (typeof match.minutesAway === 'number' && !isNaN(match.minutesAway)) {
    minutesAway = match.minutesAway;
  } else if (typeof match.predicted_arrival_epoch === 'number' && !isNaN(match.predicted_arrival_epoch)) {
    minutesAway = Math.max(0, Math.round((match.predicted_arrival_epoch - nowEpoch) / 60));
  }

  if (minutesAway === null) return null;

  return {
    isLive: true,
    minutesAway,
    isApproaching: Boolean(match.isApproaching || minutesAway <= 1),
  };
}

