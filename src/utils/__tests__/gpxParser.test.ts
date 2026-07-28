import { parseGPX } from '../workoutParser';

// Mock the coordToH3 function since we don't need to test h3-js logic here
jest.mock('../h3Utils', () => ({
  coordToH3: jest.fn((lat, lon) => `h3_${lat}_${lon}`),
}));

describe('workoutParser parseGPX', () => {
  it('extracts waypoints and track points and removes duplicates', async () => {
    const mockGPX = `
      <?xml version="1.0" encoding="UTF-8"?>
      <gpx version="1.1" creator="MockCreator">
        <wpt lat="40.7128" lon="-74.0060">
          <name>Point A</name>
        </wpt>
        <trk>
          <trkseg>
            <trkpt lat="40.7128" lon="-74.0060"></trkpt>
            <trkpt lat="40.7129" lon="-74.0061"></trkpt>
          </trkseg>
        </trk>
      </gpx>
    `;

    const result = await parseGPX(mockGPX);

    // Expecting 2 unique points since the first trkpt is a duplicate of wpt
    expect(result.hexes).toHaveLength(2);
    expect(result.hexes).toContain('h3_40.7128_-74.006');
    expect(result.hexes).toContain('h3_40.7129_-74.0061');
    
    // Test the string enforcement guardrail
    result.hexes.forEach((h3) => {
      expect(typeof h3).toBe('string');
    });
  });

  it('throws error for invalid GPX format', async () => {
    const invalidGPX = `<notgpx></notgpx>`;
    await expect(parseGPX(invalidGPX)).rejects.toThrow('Invalid GPX format: Missing root <gpx> element');
  });
});
