import type { RoutingSegment, RoutePatternEntry } from '../types/routing.ts';

/**
 * Fares verified from https://new.mta.info/fares
 * Rules (per Walsh spec):
 * - Flat base fare: 300 cents ($3.00)
 * - Free transfer subway <-> local bus, bus <-> bus.
 * - SBS is NOT a free transfer (requires a new fare).
 * - Ferry is a separate fare.
 * - Bike legs contribute $0.
 */

type FareFormula = 'flat' | 'distance' | 'zone';

interface CityFareConfig {
  formula: FareFormula;
  baseFareCents: number;
  computeFare: (segments: RoutingSegment[], patterns: RoutePatternEntry[] | undefined) => number;
}

const nycConfig: CityFareConfig = {
  formula: 'flat',
  baseFareCents: 300,
  computeFare: (segments, patterns) => {
    let totalCents = 0;
    let inTransferWindow = false;

    for (const seg of segments) {
      if (seg.is_transfer) continue;

      // Determine transit mode. route_id refers to patterns array index
      const pattern = patterns?.[seg.route_id];
      const routeStr = pattern?.route_id || '';
      const isSubway = /^[1-7A-Z]$/.test(routeStr) || routeStr === 'FS' || routeStr === 'GS'; // Approximation, though often we just use prefix or length
      const isLocalBus = /^[BMQx]?\d+$/.test(routeStr) && !routeStr.includes('+'); // Basic approximation
      const isSbs = routeStr.endsWith('+') || routeStr.includes('SBS');
      const isFerry = routeStr.toLowerCase().includes('ferry') || routeStr.startsWith('ER');
      const isBike = seg.trip_id === 0xFFFFFFFF && seg.route_id === 0xFFFF; // Transfer

      if (isFerry) {
        totalCents += 400; // NYC Ferry is $4.00
        inTransferWindow = false;
        continue;
      }

      if (isSbs) {
        totalCents += 300; // No free transfer to SBS
        inTransferWindow = false;
        continue;
      }

      // Local bus or subway
      if (!inTransferWindow) {
        totalCents += 300;
        inTransferWindow = true; // Opens transfer window
      } else {
        // Already in transfer window, it's free, but consumes the window
        inTransferWindow = false;
      }
    }

    return totalCents;
  }
};

const distanceFixtureConfig: CityFareConfig = {
  formula: 'distance',
  baseFareCents: 200, // base $2.00
  computeFare: (segments) => {
    let total = 0;
    for (const seg of segments) {
      if (seg.is_transfer) continue;
      // distance formula: $2 + $0.10 per 100 meters
      total += 200 + Math.floor(seg.transfer_distance_m / 100) * 10;
    }
    return total;
  }
};

export const fareTables: Record<string, CityFareConfig> = {
  nyc: nycConfig,
  distance_fixture: distanceFixtureConfig,
};

export function computeItineraryFare(segments: RoutingSegment[], citySlug: string, patterns?: RoutePatternEntry[]): number {
  const config = fareTables[citySlug];
  if (!config) return 0; // Default or unsupported

  return config.computeFare(segments, patterns);
}
