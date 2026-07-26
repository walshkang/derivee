import type { LocationObject } from 'expo-location';

/**
 * Maximum allowed implied speed in meters per second (12 m/s = 43.2 km/h).
 * Coordinates producing a higher implied speed are treated as GPS drift / multipath noise.
 */
export const MAX_IMPLIED_SPEED_MPS = 12;

/**
 * Earth radius in meters used for Haversine distance formula.
 */
const EARTH_RADIUS_METERS = 6371000;

/**
 * Calculates the Haversine distance in meters between two GPS coordinates.
 *
 * @param lat1 Latitude of point 1 (in degrees)
 * @param lon1 Longitude of point 1 (in degrees)
 * @param lat2 Latitude of point 2 (in degrees)
 * @param lon2 Longitude of point 2 (in degrees)
 * @returns Distance in meters
 */
export function calculateHaversineDistance(
  lat1: number,
  lon1: number,
  lat2: number,
  lon2: number
): number {
  if (
    typeof lat1 !== 'number' || isNaN(lat1) ||
    typeof lon1 !== 'number' || isNaN(lon1) ||
    typeof lat2 !== 'number' || isNaN(lat2) ||
    typeof lon2 !== 'number' || isNaN(lon2)
  ) {
    return 0;
  }

  const toRad = (deg: number) => (deg * Math.PI) / 180;

  const dLat = toRad(lat2 - lat1);
  const dLon = toRad(lon2 - lon1);

  const radLat1 = toRad(lat1);
  const radLat2 = toRad(lat2);

  const a =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos(radLat1) * Math.cos(radLat2) * Math.sin(dLon / 2) * Math.sin(dLon / 2);

  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));

  return EARTH_RADIUS_METERS * c;
}

/**
 * Calculates the implied speed in meters per second (m/s) between two timestamped LocationObjects.
 *
 * @param loc1 First location object (starting point)
 * @param loc2 Second location object (destination point)
 * @returns Implied speed in m/s, or Infinity if invalid zero/negative time delta with non-zero distance
 */
export function calculateImpliedSpeed(loc1: LocationObject, loc2: LocationObject): number {
  if (!loc1?.coords || !loc2?.coords || typeof loc1.timestamp !== 'number' || typeof loc2.timestamp !== 'number') {
    return 0;
  }

  const distance = calculateHaversineDistance(
    loc1.coords.latitude,
    loc1.coords.longitude,
    loc2.coords.latitude,
    loc2.coords.longitude
  );

  const timeDeltaSeconds = (loc2.timestamp - loc1.timestamp) / 1000;

  if (timeDeltaSeconds <= 0) {
    return distance === 0 ? 0 : Infinity;
  }

  return distance / timeDeltaSeconds;
}

export interface SpeedFilterResult {
  validLocations: LocationObject[];
  lastAcceptedLocation: LocationObject | null;
}

/**
 * Pure function that filters a batch of location updates through the velocity gate (Implied Speed Filter).
 * Any location jump resulting in an implied speed > maxSpeedMps is discarded as GPS drift.
 * Decoupled from Expo location listener context for clean unit testing per AGENTS.md.
 *
 * @param locations Array of incoming LocationObjects
 * @param lastLocation Previously accepted location reference (or null)
 * @param maxSpeedMps Maximum allowed speed in m/s (default: 12 m/s)
 * @returns SpeedFilterResult containing valid locations and updated last accepted location reference
 */
export function filterLocationsBySpeed(
  locations: LocationObject[],
  lastLocation: LocationObject | null = null,
  maxSpeedMps: number = MAX_IMPLIED_SPEED_MPS
): SpeedFilterResult {
  if (!Array.isArray(locations) || locations.length === 0) {
    return { validLocations: [], lastAcceptedLocation: lastLocation };
  }

  const validLocations: LocationObject[] = [];
  let currentLastLocation = lastLocation;

  for (const location of locations) {
    if (!location || !location.coords || typeof location.timestamp !== 'number') {
      continue;
    }

    const { latitude, longitude } = location.coords;
    if (
      typeof latitude !== 'number' ||
      isNaN(latitude) ||
      latitude < -90 ||
      latitude > 90 ||
      typeof longitude !== 'number' ||
      isNaN(longitude) ||
      longitude < -180 ||
      longitude > 180
    ) {
      continue;
    }

    if (!currentLastLocation) {
      // First valid coordinate is accepted
      validLocations.push(location);
      currentLastLocation = location;
      continue;
    }

    const speed = calculateImpliedSpeed(currentLastLocation, location);

    if (speed <= maxSpeedMps) {
      validLocations.push(location);
      currentLastLocation = location;
    } else {
      console.warn(
        `[SpeedFilter] Discarded GPS drift coordinate (${latitude}, ${longitude}) with implied speed ${speed.toFixed(2)} m/s (max threshold: ${maxSpeedMps} m/s)`
      );
    }
  }

  return {
    validLocations,
    lastAcceptedLocation: currentLastLocation,
  };
}
