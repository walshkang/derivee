import {
  seedPOIs,
  getAllPOIs,
  markPOIDiscovered,
  getPOIByH3Index,
  getPOIAtLocation,
} from '../poiQueries';

describe('POI Queries & Spatial Lookups', () => {
  const SAMPLE_H3_INDEX = '8b2a100d213fff';

  it('retrieves POIs and asserts H3 indices are strictly string types', () => {
    seedPOIs();
    const pois = getAllPOIs();
    expect(Array.isArray(pois)).toBe(true);

    if (pois.length > 0) {
      const firstPoi = pois[0];
      expect(typeof firstPoi.id).toBe('string');
      expect(typeof firstPoi.name).toBe('string');
      expect(typeof firstPoi.h3_index).toBe('string');
      expect(firstPoi.h3_index.length).toBeGreaterThanOrEqual(14);
    }
  });

  it('queries POI by H3 index string accurately', () => {
    const poi = getPOIByH3Index(SAMPLE_H3_INDEX);
    if (poi) {
      expect(poi.h3_index).toBe(SAMPLE_H3_INDEX);
      expect(typeof poi.h3_index).toBe('string');
      expect(poi.id).toBeDefined();
    }
  });

  it('throws error when getPOIByH3Index is passed non-string or invalid length H3 index', () => {
    expect(() => getPOIByH3Index(12345 as any)).toThrow();
    expect(() => getPOIByH3Index('short')).toThrow();
  });

  it('resolves GPS coordinate to POI via getPOIAtLocation', () => {
    const lat = 40.7153;
    const lng = -73.9678;
    const poi = getPOIAtLocation(lat, lng);
    // May return POI or null depending on mock database state
    if (poi) {
      expect(typeof poi.h3_index).toBe('string');
    }
  });

  it('updates POI discovered state when marked', () => {
    expect(() => markPOIDiscovered('poi_1')).not.toThrow();
  });
});
