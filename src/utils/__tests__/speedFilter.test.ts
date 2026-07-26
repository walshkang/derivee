import type { LocationObject } from 'expo-location';
import {
  calculateHaversineDistance,
  calculateImpliedSpeed,
  filterLocationsBySpeed,
  MAX_IMPLIED_SPEED_MPS,
} from '../speedFilter';

describe('Speed Filter & Velocity Gate (speedFilter.ts)', () => {
  const baseTime = 1700000000000; // Mock timestamp in ms

  const createMockLocation = (
    lat: number,
    lng: number,
    timestampOffsetSeconds: number
  ): LocationObject => ({
    coords: {
      latitude: lat,
      longitude: lng,
      altitude: null,
      accuracy: 5,
      altitudeAccuracy: null,
      heading: null,
      speed: null,
    },
    timestamp: baseTime + timestampOffsetSeconds * 1000,
  });

  describe('calculateHaversineDistance', () => {
    it('returns 0 for identical coordinates', () => {
      const dist = calculateHaversineDistance(40.7128, -73.956, 40.7128, -73.956);
      expect(dist).toBe(0);
    });

    it('calculates accurate distance between known coordinates in Williamsburg', () => {
      // ~0.001 degree latitude diff is approx 111 meters
      const dist = calculateHaversineDistance(40.7128, -73.956, 40.7138, -73.956);
      expect(dist).toBeGreaterThan(110);
      expect(dist).toBeLessThan(112);
    });

    it('handles invalid coordinate parameters gracefully', () => {
      expect(calculateHaversineDistance(NaN, -73.956, 40.7128, -73.956)).toBe(0);
    });
  });

  describe('calculateImpliedSpeed', () => {
    it('calculates correct speed in meters per second', () => {
      const loc1 = createMockLocation(40.7128, -73.956, 0);
      // Move ~111m over 100 seconds => ~1.11 m/s (walking pace)
      const loc2 = createMockLocation(40.7138, -73.956, 100);

      const speed = calculateImpliedSpeed(loc1, loc2);
      expect(speed).toBeGreaterThan(1.1);
      expect(speed).toBeLessThan(1.12);
    });

    it('returns 0 if points are identical even with positive time delta', () => {
      const loc1 = createMockLocation(40.7128, -73.956, 0);
      const loc2 = createMockLocation(40.7128, -73.956, 10);

      expect(calculateImpliedSpeed(loc1, loc2)).toBe(0);
    });

    it('returns Infinity for non-zero movement with 0 or negative time delta', () => {
      const loc1 = createMockLocation(40.7128, -73.956, 10);
      const loc2 = createMockLocation(40.7138, -73.956, 10);

      expect(calculateImpliedSpeed(loc1, loc2)).toBe(Infinity);
    });
  });

  describe('filterLocationsBySpeed', () => {
    it('accepts the first location when lastLocation is null', () => {
      const loc = createMockLocation(40.7128, -73.956, 0);
      const result = filterLocationsBySpeed([loc], null);

      expect(result.validLocations).toHaveLength(1);
      expect(result.validLocations[0]).toEqual(loc);
      expect(result.lastAcceptedLocation).toEqual(loc);
    });

    it('accepts sequential updates within speed threshold (<= 12 m/s)', () => {
      const loc1 = createMockLocation(40.7128, -73.956, 0);
      // ~111 meters over 20 seconds => ~5.55 m/s (running/cycling speed, below 12 m/s limit)
      const loc2 = createMockLocation(40.7138, -73.956, 20);

      const result = filterLocationsBySpeed([loc1, loc2], null);

      expect(result.validLocations).toHaveLength(2);
      expect(result.lastAcceptedLocation).toEqual(loc2);
    });

    it('discards urban canyon GPS multipath jump exceeding 12 m/s', () => {
      const loc1 = createMockLocation(40.7128, -73.956, 0);
      // Teleport jump of ~500m over 2 seconds => 250 m/s (far exceeds 12 m/s threshold)
      const driftLoc = createMockLocation(40.7173, -73.956, 2);

      const result = filterLocationsBySpeed([loc1, driftLoc], null);

      expect(result.validLocations).toHaveLength(1);
      expect(result.validLocations[0]).toEqual(loc1);
      expect(result.lastAcceptedLocation).toEqual(loc1);
    });

    it('handles mixed batches containing both valid movements and drift jumps', () => {
      const loc1 = createMockLocation(40.7128, -73.956, 0);
      // Valid step: ~111m over 60s (~1.85 m/s)
      const loc2 = createMockLocation(40.7138, -73.956, 60);
      // GPS drift jump: ~1000m over 1s (1000 m/s) -> SHOULD BE DISCARDED
      const drift = createMockLocation(40.7228, -73.956, 61);
      // Valid step from loc2: ~111m over 60s (~1.85 m/s)
      const loc3 = createMockLocation(40.7148, -73.956, 120);

      const result = filterLocationsBySpeed([loc1, loc2, drift, loc3], null);

      expect(result.validLocations).toHaveLength(3);
      expect(result.validLocations).toEqual([loc1, loc2, loc3]);
      expect(result.lastAcceptedLocation).toEqual(loc3);
    });

    it('returns empty array when given empty input batch', () => {
      const result = filterLocationsBySpeed([], null);
      expect(result.validLocations).toEqual([]);
      expect(result.lastAcceptedLocation).toBeNull();
    });
  });
});
