import { describe, it, expect } from 'vitest';
import { getTransitLayerDisplayState } from './displayModel';

describe('displayModel', () => {
  it('does not leak internal error IDs or paths into the UI copy', () => {
    const rawError = 'Failed to open file: cities/nyc/transit-lines.geojson (ID: 0x8a7f92b)';
    const display = getTransitLayerDisplayState('error', rawError);
    
    expect(display.text).not.toContain('geojson');
    expect(display.text).not.toContain('0x8a7f92b');
    expect(display.text).toBe('Transit Data Unavailable');
  });

  it('returns correct loading state', () => {
    const display = getTransitLayerDisplayState('loading');
    expect(display.text).toBe('Loading Transit Layer');
  });
});
