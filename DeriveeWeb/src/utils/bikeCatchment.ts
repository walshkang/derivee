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
 * Simple grid spatial index for fast nearby lookups.
 * Cell size ~500m (approx 0.0045 degrees lat).
 */
class GridIndex<T extends { lat: number; lon: number }> {
  private cells = new Map<string, T[]>();
  private cellSize = 0.0045; // ~500m

  constructor(items: T[]) {
    for (const item of items) {
      const key = this.key(item.lat, item.lon);
      if (!this.cells.has(key)) this.cells.set(key, []);
      this.cells.get(key)!.push(item);
    }
  }

  private key(lat: number, lon: number): string {
    return `${Math.floor(lat / this.cellSize)},${Math.floor(lon / this.cellSize)}`;
  }

  /** Find all items within radiusMeters of (lat, lon) */
  nearby(lat: number, lon: number, radiusMeters: number): T[] {
    const radiusDeg = radiusMeters / 111000; // approx degrees
    const minLat = Math.floor((lat - radiusDeg) / this.cellSize);
    const maxLat = Math.floor((lat + radiusDeg) / this.cellSize);
    const minLon = Math.floor((lon - radiusDeg) / this.cellSize);
    const maxLon = Math.floor((lon + radiusDeg) / this.cellSize);
    const results: T[] = [];
    for (let clat = minLat; clat <= maxLat; clat++) {
      for (let clon = minLon; clon <= maxLon; clon++) {
        const cell = this.cells.get(`${clat},${clon}`);
        if (cell) {
          for (const item of cell) {
            if (haversineM(lat, lon, item.lat, item.lon) <= radiusMeters) {
              results.push(item);
            }
          }
        }
      }
    }
    return results;
  }
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

  // Build spatial indices (fast nearby lookups)
  const dockIndex = new GridIndex(bikeStations);
  const stopIndex = new GridIndex(transitStops);

  // Find docks within walk range of origin (via index, not O(n) scan)
  const nearbyDocks = dockIndex.nearby(originLat, originLon, MAX_WALK_TO_DOCK_M);

  for (const pickupDock of nearbyDocks) {
    const walkToDockM = haversineM(originLat, originLon, pickupDock.lat, pickupDock.lon) * MANHATTAN_GRID_FACTOR;
    const walkToDockS = walkToDockM / WALK_SPEED_MS;

    // For each transit stop within bike range of this dock (via index)
    const nearbyStops = stopIndex.nearby(pickupDock.lat, pickupDock.lon, MAX_BIKE_RIDE_M);
    for (const stop of nearbyStops) {
      const bikeDistM = haversineM(pickupDock.lat, pickupDock.lon, stop.lat, stop.lon);
      // (already filtered by index, but double-check for exactness)
      if (bikeDistM > MAX_BIKE_RIDE_M) continue;

      // Find dropoff dock near the transit stop (via index)
      const dropoffCands = dockIndex.nearby(stop.lat, stop.lon, MAX_WALK_TO_DOCK_M);
      let bestDropoff: BikeStation | null = null;
      let bestDropoffDist = Infinity;
      for (const dock of dropoffCands) {
        const d = haversineM(stop.lat, stop.lon, dock.lat, dock.lon);
        if (d < bestDropoffDist) {
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
