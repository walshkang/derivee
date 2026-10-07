import type { RoutingSegment, RoutePatternEntry } from '../types/routing.ts';

// Source: https://new.mta.info/fares
// MTA Fare Rules Confirmed:
// - Flat base fare is $3.00 (300 cents)
// - Free transfers: subway<->local bus, bus<->bus within 2 hours.
// - SBS: MTA site confirms SBS fare is $3.00 and allows standard tap-and-ride. There is no language excluding SBS from free transfers. Therefore, SBS IS a free transfer. (This contradicts Walsh's spec; we are following the MTA source as instructed).
// - Ferry is a separate fare.

interface CityFareConfig {
  formula: 'flat' | 'distance' | 'zone';
  baseCents: number;
  per100mCents?: number;
  modeOverrides: Record<string, number>;
  freeTransfers: Array<[string, string]>; // [fromMode, toMode]
}

const FARE_TABLE: Record<string, CityFareConfig> = {
  nyc: {
    formula: 'flat',
    baseCents: 300,
    modeOverrides: {
      ferry: 400
    },
    freeTransfers: [
      ['subway', 'local_bus'],
      ['local_bus', 'subway'],
      ['local_bus', 'local_bus'],
      ['subway', 'sbs'],
      ['sbs', 'subway'],
      ['local_bus', 'sbs'],
      ['sbs', 'local_bus'],
      ['sbs', 'sbs']
    ]
  },
  distance_fixture: {
    formula: 'distance',
    baseCents: 200,
    per100mCents: 10,
    modeOverrides: {},
    freeTransfers: []
  }
};

function determineNycMode(routeId: string): string {
  if (routeId === 'ER' || routeId.toLowerCase().includes('ferry')) return 'ferry';
  if (routeId.endsWith('+') || routeId.includes('SBS')) return 'sbs';
  if (/^(B|M|Q|Bx|S)\d+/.test(routeId) && !routeId.includes('SIR')) return 'local_bus';
  if (/^[1-7A-Z]$/.test(routeId) || routeId === 'SIR' || routeId === 'FS' || routeId === 'GS') return 'subway';
  return 'unknown';
}

export function computeItineraryFare(
  segments: RoutingSegment[],
  citySlug: string,
  patterns?: RoutePatternEntry[]
): number {
  const config = FARE_TABLE[citySlug];
  if (!config) return 0;

  let totalCents = 0;
  let lastTransitMode: string | null = null;
  let transfersUsed = 0;

  for (const seg of segments) {
    if (seg.is_transfer) continue;

    const pattern = patterns?.[seg.route_id];
    const routeIdStr = pattern?.route_id || '';
    
    let mode = 'unknown';
    if (citySlug === 'nyc') {
      mode = determineNycMode(routeIdStr);
    } else {
      mode = 'default';
    }

    if (mode === 'unknown') {
      // Bike-share or unclassified legs contribute $0
      continue;
    }

    let legCost = 0;

    if (config.formula === 'distance') {
      const distUnits = Math.floor(seg.transfer_distance_m / 100);
      legCost = config.baseCents + (distUnits * (config.per100mCents || 0));
    } else {
      legCost = config.modeOverrides[mode] ?? config.baseCents;
    }

    if (lastTransitMode && transfersUsed < 1) {
      const isFree = config.freeTransfers.some(
        ([from, to]) => from === lastTransitMode && to === mode
      );
      if (isFree) {
        legCost = 0;
        transfersUsed++;
      } else {
        transfersUsed = 0;
      }
    } else {
      transfersUsed = 0;
    }

    totalCents += legCost;
    lastTransitMode = mode;
  }

  return totalCents;
}
