import { generateFogGeoJSON } from '../fogGeoJSON';
import { coordToH3, getH3Buffer } from '../h3Utils';

describe('generateFogGeoJSON', () => {
  const mockLat = 40.7128;
  const mockLng = -73.956;

  it('should generate a GeoJSON Polygon with bounding box outer ring when no hexes are unlocked', async () => {
    const result = await generateFogGeoJSON(mockLat, mockLng, []);

    expect(result).toBeDefined();
    expect(result.type).toBe('Feature');
    expect(result.geometry.type).toBe('Polygon');

    const coordinates = result.geometry.coordinates;
    // coordinates[0] is the outer ring of the ~50x50km bounding box
    expect(coordinates.length).toBe(1);
    expect(coordinates[0].length).toBe(5); // Closed 5-vertex polygon ring
  });

  it('should concatenate unlocked hex rings as inner rings (holes) in the fog polygon', async () => {
    // Valid 15-character H3 resolution 11 hex index strings
    const centerHex = coordToH3(mockLat, mockLng, 11);
    const unlockedHexes = getH3Buffer(centerHex, 1); // 7 valid hex strings

    const result = await generateFogGeoJSON(mockLat, mockLng, unlockedHexes);

    expect(result.type).toBe('Feature');
    expect(result.geometry.type).toBe('Polygon');

    const coordinates = result.geometry.coordinates;
    // Outer bounding box ring + inner rings for unlocked hex holes
    expect(coordinates.length).toBeGreaterThan(1);

    // Verify outer ring bounding box boundaries
    const bboxRing = coordinates[0];
    expect(bboxRing.length).toBe(5);

    // Verify inner ring (hole) exists and contains coordinate pairs [lng, lat]
    const firstHole = coordinates[1];
    expect(firstHole.length).toBeGreaterThan(0);
    expect(firstHole[0].length).toBe(2);
    expect(typeof firstHole[0][0]).toBe('number');
    expect(typeof firstHole[0][1]).toBe('number');
  });

  it('CRITICAL AGENTS.md RULE: Enforce H3 string input types and prevent truncation', async () => {
    const centerHex = coordToH3(mockLat, mockLng, 11);
    const validStringHexes = getH3Buffer(centerHex, 1);
    
    validStringHexes.forEach((hex) => {
      expect(typeof hex).toBe('string');
      expect(hex.length).toBe(15); // Standard H3 index hex string length
    });

    const result = await generateFogGeoJSON(mockLat, mockLng, validStringHexes);
    expect(result.geometry.coordinates.length).toBeGreaterThan(1);
  });

  it('should handle invalid hex strings gracefully without crashing', async () => {
    const invalidHexes = ['invalid_hex_string'];

    const result = await generateFogGeoJSON(mockLat, mockLng, invalidHexes);
    expect(result).toBeDefined();
    expect(result.geometry.type).toBe('Polygon');
  });
});

