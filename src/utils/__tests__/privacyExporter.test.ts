import { exportSpatialDataJSON, PRIVACY_STATEMENT } from '../privacyExporter';

describe('privacyExporter', () => {
  it('should contain a valid offline-first zero-telemetry privacy disclosure', () => {
    expect(PRIVACY_STATEMENT).toContain('Offline-First');
    expect(PRIVACY_STATEMENT).toContain('Zero-Telemetry');
    expect(PRIVACY_STATEMENT).toContain('@op-engineering/op-sqlite');
  });

  it('should export spatial log payload as formatted JSON string', () => {
    const mockHexes = ['8b2a100d213fff', '8b2a100d213888'];
    const jsonOutput = exportSpatialDataJSON(mockHexes, 2);

    expect(typeof jsonOutput).toBe('string');
    const parsed = JSON.parse(jsonOutput);

    expect(parsed.app).toBe('Fog of Wburg');
    expect(parsed.metrics.totalUnlockedHexes).toBe(2);
    expect(parsed.metrics.estimatedAreaKm2).toBe(0.1);
    expect(parsed.unlockedHexes).toEqual(mockHexes);
  });

  it('strictly enforces string data type for H3 hexes per AGENTS.md guardrail', () => {
    // Pass a mix of string and invalid non-string values
    const inputHexes = ['8b2a100d213fff', 123456789 as any, '8b2a100d213888'];
    const jsonOutput = exportSpatialDataJSON(inputHexes, 3);
    const parsed = JSON.parse(jsonOutput);

    parsed.unlockedHexes.forEach((hex: any) => {
      expect(typeof hex).toBe('string');
    });

    expect(parsed.unlockedHexes).toHaveLength(2);
  });
});
