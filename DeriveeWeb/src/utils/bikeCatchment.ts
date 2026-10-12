/**
 * Bike catchment expansion for Dérivée.
 *
 * Instead of replacing walk with bike for the same stations, bike EXPANDS
 * the catchment to reach stations faster than walking could.
 *
 * The function is deterministic: same inputs always produce same outputs.
 * It computes access times only — transit time comparison happens via
 * dual RAPTOR (walk route vs bike route) in the caller.
 */

export interface BikeStation {
  station_id: string;
  lat: number;
  lon: number;
  name: string;
  capacity: number;
}

export interface TransitStop {
  id: string | number;
  lat: number;
  lon: number;
  name: string;
}

export interface BikeCandidate {
  stopId: string | number;
  stopName: string;
  bikeTimeSeconds: number;
  pickupDockId: string;
  pickupDockName: string;
  walkToDockSeconds: number;
  bikeRideSeconds: number;
  dropoffDockId: string;
  dropoffDockName: string;
  walkFromDockSeconds: number;
}

// Constants from research
const WALK_SPEED_MS = 1.4; // 5 km/h
const BIKE_SPEED_MS = 3.58; // ~8 mph (classic Citi Bike)
const EBIKE_SPEED_MS = 6.71; // ~15 mph
const MANHATTAN_GRID_FACTOR = 1.32; // Haversine to street distance
const MAX_WALK_TO_DOCK_M = 400;
const MAX_BIKE_RIDE_M = 5000; // 5km max
const PICKUP_PENALTY_S = 60;
const DROPOFF_PENALTY_S = 30;

function haversineM(lat1: number, lon1: number, lat2: number, lon2: number): number {
  const R = 6371000;
  const dLat = (lat2 - lat1) * Math.PI / 180;
  const dLon = (lon2 - lon1) * Math.PI / 180;
  const a = Math.sin(dLat / 2) ** 2 +
    Math.cos(lat1 * Math.PI / 180) * Math.cos(lat2 * Math.PI / 180) *
    Math.sin(dLon / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(a));
}

/**
 * Find transit stops reachable by bike from origin.
 * 
 * For each bike dock within walk range of origin:
 *   For each transit stop within bike range of that dock:
 *     Compute total time = walk_to_dock + bike_ride + walk_to_stop
 * 
 * Returns candidates sorted by total time, deduplicated by stop (keeps fastest).
 */
export function findBikeCandidates(
  originLat: number,
  originLon: number,
  bikeStations: BikeStation[],
  transitStops: TransitStop[],
  useEbike: boolean = false
): BikeCandidate[] {
  const bikeSpeed = useEbike ? EBIKE_SPEED_MS : BIKE_SPEED_MS;
  // Dedupe by station name (dataset has separate IDs per platform at same coords)
  const candidates = new Map<string, BikeCandidate>();

  // Find docks within walk range of origin
  const nearbyDocks = bikeStations.filter(dock => {
    const dist = haversineM(originLat, originLon, dock.lat, dock.lon);
    return dist <= MAX_WALK_TO_DOCK_M;
  });

  for (const pickupDock of nearbyDocks) {
    const walkToDockM = haversineM(originLat, originLon, pickupDock.lat, pickupDock.lon) * MANHATTAN_GRID_FACTOR;
    const walkToDockS = walkToDockM / WALK_SPEED_MS;

    // For each transit stop within bike range of this dock
    for (const stop of transitStops) {
      const bikeDistM = haversineM(pickupDock.lat, pickupDock.lon, stop.lat, stop.lon);
      if (bikeDistM > MAX_BIKE_RIDE_M) continue;

      // Find dropoff dock near the transit stop
      let bestDropoff: BikeStation | null = null;
      let bestDropoffDist = Infinity;
      for (const dock of bikeStations) {
        const d = haversineM(stop.lat, stop.lon, dock.lat, dock.lon);
        if (d < bestDropoffDist && d <= MAX_WALK_TO_DOCK_M) {
          bestDropoffDist = d;
          bestDropoff = dock;
        }
      }
      if (!bestDropoff) continue;

      const bikeRideM = bikeDistM * MANHATTAN_GRID_FACTOR;
      const bikeRideS = bikeRideM / bikeSpeed;
      const walkFromDockS = (bestDropoffDist * MANHATTAN_GRID_FACTOR) / WALK_SPEED_MS;

      const totalS = walkToDockS + PICKUP_PENALTY_S + bikeRideS + DROPOFF_PENALTY_S + walkFromDockS;

      const existing = candidates.get(stop.name);
      if (!existing || totalS < existing.bikeTimeSeconds) {
        candidates.set(stop.name, {
          stopId: stop.id,
          stopName: stop.name,
          bikeTimeSeconds: Math.round(totalS),
          pickupDockId: pickupDock.station_id,
          pickupDockName: pickupDock.name,
          walkToDockSeconds: Math.round(walkToDockS),
          bikeRideSeconds: Math.round(bikeRideS),
          dropoffDockId: bestDropoff.station_id,
          dropoffDockName: bestDropoff.name,
          walkFromDockSeconds: Math.round(walkFromDockS),
        });
      }
    }
  }

  return Array.from(candidates.values()).sort((a, b) => a.bikeTimeSeconds - b.bikeTimeSeconds);
}
