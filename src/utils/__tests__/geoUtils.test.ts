import {
  calculateDistanceMeters,
  isWithinVicinityBubble,
  generateVicinityBubbleGeoJSON,
} from '../geoUtils';

describe('geoUtils (Vicinity & Distance Calculations)', () => {
  const USER_LAT = 40.7128;
  const USER_LNG = -74.006; // NYC Financial District center

  describe('calculateDistanceMeters', () => {
    it('returns 0 meters for identical coordinates', () => {
      const dist = calculateDistanceMeters(USER_LAT, USER_LNG, USER_LAT, USER_LNG);
      expect(dist).toBe(0);
    });

    it('accurately calculates distance for known points (~150 meters away)', () => {
      // Coordinate ~150 meters north
      const NEARBY_LAT = 40.71415;
      const NEARBY_LNG = -74.006;
      const dist = calculateDistanceMeters(USER_LAT, USER_LNG, NEARBY_LAT, NEARBY_LNG);
      expect(dist).toBeGreaterThan(140);
      expect(dist).toBeLessThan(160);
    });

    it('throws error when passed non-numeric or NaN coordinates', () => {
      expect(() => calculateDistanceMeters(NaN, USER_LNG, USER_LAT, USER_LNG)).toThrow();
      expect(() => calculateDistanceMeters(USER_LAT, 'abc' as any, USER_LAT, USER_LNG)).toThrow();
    });
  });

  describe('isWithinVicinityBubble', () => {
    it('returns true when point is within 200m radius', () => {
      // ~100m away
      const WITHIN_LAT = 40.7135;
      const WITHIN_LNG = -74.006;
      const isInside = isWithinVicinityBubble(USER_LAT, USER_LNG, WITHIN_LAT, WITHIN_LNG, 200);
      expect(isInside).toBe(true);
    });

    it('returns false when point is beyond 200m radius', () => {
      // ~500m away
      const OUTSIDE_LAT = 40.7173;
      const OUTSIDE_LNG = -74.006;
      const isInside = isWithinVicinityBubble(USER_LAT, USER_LNG, OUTSIDE_LAT, OUTSIDE_LNG, 200);
      expect(isInside).toBe(false);
    });
  });

  describe('generateVicinityBubbleGeoJSON', () => {
    it('generates a valid Polygon GeoJSON feature centered on coordinates', () => {
      const geojson = generateVicinityBubbleGeoJSON(USER_LAT, USER_LNG, 200);
      expect(geojson.type).toBe('Feature');
      expect(geojson.geometry.type).toBe('Polygon');
      expect(geojson.properties?.radiusMeters).toBe(200);

      const rings = geojson.geometry.coordinates;
      expect(rings.length).toBe(1);
      
      const polygonRing = rings[0];
      // 64 steps + 1 closing vertex = 65 vertices
      expect(polygonRing.length).toBe(65);

      // Verify closed ring (first coordinate equals last coordinate)
      const firstCoord = polygonRing[0];
      const lastCoord = polygonRing[polygonRing.length - 1];
      expect(firstCoord[0]).toBeCloseTo(lastCoord[0], 6);
      expect(firstCoord[1]).toBeCloseTo(lastCoord[1], 6);
    });
  });
});
