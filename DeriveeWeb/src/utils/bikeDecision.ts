import {
  type BikeCandidate,
  type BikeStation,
  computeBikeOnlySeconds,
} from './bikeCatchment.ts';

export interface DockStatus {
  bikes: number;
  docks: number;
}

export type AvailabilityMap = ReadonlyMap<string, DockStatus>;

export interface BikeThresholdConfig {
  hassleThresholdSec?: number;
  minBikes?: number;
  minDocks?: number;
}

export interface BikeBannerData {
  bikeStationName: string;
  bikeAccessMin: number;
  pickupDockName: string;
  savingsMin: number;
  walkTotalMin: number;
  bikeTotalMin: number;
  bikeOnlyMin?: number;
  ebikeAccessMin?: number;
}

export type BikeDecisionReason =
  | 'threshold'
  | 'no-availability'
  | 'no-candidates'
  | 'no-data';

export interface BikeDecisionResult {
  suggestion: 'bike' | 'walk';
  reason: BikeDecisionReason;
  selectedCandidate: BikeCandidate | null;
  bannerData: BikeBannerData | null;
  savingsSec?: number;
}

export interface DecideBikeOptionInput {
  candidates: BikeCandidate[];
  ebikeCandidates?: BikeCandidate[];
  /**
   * Live dock availability map.
   * Pass an empty Map when the status fetch failed or returned no stations —
   * with no availability information the safe default is to walk
   * (selectAvailableCandidate returns null).
   */
  availability: AvailabilityMap;
  walkTotalSec?: number;
  /** Transit-only leg duration from the selected bike candidate stop to destination */
  bikeTransitSec?: number;
  origin?: { lat: number; lon: number };
  destination?: { lat: number; lon: number };
  bikeStations?: BikeStation[];
  config?: BikeThresholdConfig;
}

export const DEFAULT_HASSLE_THRESHOLD_SEC = 300; // 5 minutes
export const DEFAULT_MIN_BIKES = 2; // availability buffer: one other rider must not invalidate the suggestion
export const DEFAULT_MIN_DOCKS = 2;

/**
 * Pure helper to pick the first candidate satisfying the availability buffer.
 * Returns null when there are no candidates or none meets the buffer —
 * including when the availability map is empty (status fetch failed),
 * in which case the safe default is to walk.
 */
export function selectAvailableCandidate(
  candidates: BikeCandidate[],
  availability: AvailabilityMap,
  config?: BikeThresholdConfig
): BikeCandidate | null {
  if (candidates.length === 0) return null;

  const minBikes = config?.minBikes ?? DEFAULT_MIN_BIKES;
  const minDocks = config?.minDocks ?? DEFAULT_MIN_DOCKS;

  for (const cand of candidates) {
    const pickup = availability.get(cand.pickupDockId);
    const dropoff = availability.get(cand.dropoffDockId);
    if (pickup && pickup.bikes >= minBikes && dropoff && dropoff.docks >= minDocks) {
      return cand;
    }
  }

  return null;
}

/**
 * Pure decision function for evaluating bike-access vs walk-access.
 *
 * Returns:
 * - suggestion: 'bike' | 'walk'
 * - reason: 'no-candidates' | 'no-availability' | 'threshold' | 'no-data'
 * - selectedCandidate: the first candidate passing availability buffer (or null)
 * - bannerData: populated when suggestion === 'bike', otherwise null
 */
export function decideBikeOption(input: DecideBikeOptionInput): BikeDecisionResult {
  const {
    candidates,
    ebikeCandidates = [],
    availability,
    walkTotalSec,
    bikeTransitSec,
    origin,
    destination,
    bikeStations,
    config,
  } = input;

  if (!candidates || candidates.length === 0) {
    return {
      suggestion: 'walk',
      reason: 'no-candidates',
      selectedCandidate: null,
      bannerData: null,
    };
  }

  const best = selectAvailableCandidate(candidates, availability, config);
  if (!best) {
    return {
      suggestion: 'walk',
      reason: 'no-availability',
      selectedCandidate: null,
      bannerData: null,
    };
  }

  // If RAPTOR transit times are not provided, the threshold cannot be evaluated.
  if (walkTotalSec === undefined || bikeTransitSec === undefined) {
    return {
      suggestion: 'walk',
      reason: 'no-data',
      selectedCandidate: best,
      bannerData: null,
    };
  }

  const hassleThresholdSec = config?.hassleThresholdSec ?? DEFAULT_HASSLE_THRESHOLD_SEC;
  const bikeAccessSec = Math.round(best.bikeTimeSeconds);
  const bikeTotalSec = bikeAccessSec + bikeTransitSec;
  const savingsSec = walkTotalSec - bikeTotalSec;

  if (savingsSec < hassleThresholdSec) {
    return {
      suggestion: 'walk',
      reason: 'threshold',
      selectedCandidate: best,
      bannerData: null,
      savingsSec,
    };
  }

  // Compute direct bike-only time using shared bikeCatchment primitives
  let bikeOnlyMin: number | undefined;
  if (origin && destination && bikeStations && bikeStations.length > 0) {
    const bikeOnlySec = computeBikeOnlySeconds(
      origin.lat,
      origin.lon,
      destination.lat,
      destination.lon,
      best.pickupDockId,
      bikeStations
    );
    if (bikeOnlySec !== undefined) {
      bikeOnlyMin = Math.round(bikeOnlySec / 60);
    }
  }

  const ebikeBest = ebikeCandidates.find(c => c.stopName === best.stopName);

  const bannerData: BikeBannerData = {
    bikeStationName: best.stopName,
    bikeAccessMin: Math.round(bikeAccessSec / 60),
    pickupDockName: best.pickupDockName,
    savingsMin: Math.round(savingsSec / 60),
    walkTotalMin: Math.round(walkTotalSec / 60),
    bikeTotalMin: Math.round(bikeTotalSec / 60),
    bikeOnlyMin,
    ebikeAccessMin: ebikeBest ? Math.round(ebikeBest.bikeTimeSeconds / 60) : undefined,
  };

  return {
    suggestion: 'bike',
    reason: 'threshold',
    selectedCandidate: best,
    bannerData,
    savingsSec,
  };
}
