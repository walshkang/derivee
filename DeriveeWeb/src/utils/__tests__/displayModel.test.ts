import { describe, it } from 'node:test';
import assert from 'node:assert';
import { getTransitLayerDisplayState, type UIState } from '../displayModel.ts';

describe('Transit Layer Display Model Tests', () => {
  describe('Positive State Transitions', () => {
    it('returns correct loading state display model', () => {
      const display = getTransitLayerDisplayState('loading');
      assert.strictEqual(display.badge, 'loading');
      assert.strictEqual(display.text, 'Loading Transit Layer');
    });

    it('returns correct ready state display model', () => {
      const display = getTransitLayerDisplayState('ready');
      assert.strictEqual(display.badge, 'ready');
      assert.strictEqual(display.text, 'Transit Ready');
    });

    it('returns correct error state display model', () => {
      const display = getTransitLayerDisplayState('error');
      assert.strictEqual(display.badge, 'error');
      assert.strictEqual(display.text, 'Transit Data Unavailable');
    });
  });

  describe('Internal ID & Path Leak Prevention (Rule 12)', () => {
    it('does not leak internal error IDs or file paths into the UI copy', () => {
      const rawError = 'Failed to open file: cities/nyc/transit-lines.geojson (ID: 0x8a7f92b)';
      const display = getTransitLayerDisplayState('error', rawError);

      assert.strictEqual(display.badge, 'error');
      assert.strictEqual(display.text, 'Transit Data Unavailable');
      assert.ok(!display.text.includes('geojson'), 'Must not contain file extension');
      assert.ok(!display.text.includes('0x8a7f92b'), 'Must not contain hex address / internal ID');
      assert.ok(!display.text.includes('cities/nyc'), 'Must not contain internal file path');
    });

    it('does not leak database or system tokens when raw error contains technical exceptions', () => {
      const technicalErrors = [
        'sqlite3_open_v2: database locked (code 5)',
        'wasm instantiation failed: unreachable executed',
        'EBUSY: resource busy or locked, open /data/pack/transit.sqlite',
        'stop_id 1459 not found in timetable.bin',
        'route_id_888 parse failure in transit-lines.geojson',
      ];

      for (const err of technicalErrors) {
        const display = getTransitLayerDisplayState('error', err);
        assert.strictEqual(display.text, 'Transit Data Unavailable');
        assert.ok(!display.text.toLowerCase().includes('sqlite'));
        assert.ok(!display.text.toLowerCase().includes('wasm'));
        assert.ok(!display.text.toLowerCase().includes('stop_id'));
        assert.ok(!display.text.toLowerCase().includes('route_id'));
      }
    });

    it('handles negative cases cleanly: empty, null, undefined, or garbage error strings', () => {
      const emptyDisplay = getTransitLayerDisplayState('error', '');
      assert.strictEqual(emptyDisplay.text, 'Transit Data Unavailable');

      const undefinedDisplay = getTransitLayerDisplayState('error', undefined);
      assert.strictEqual(undefinedDisplay.text, 'Transit Data Unavailable');

      const nullDisplay = getTransitLayerDisplayState('error', null as unknown as string);
      assert.strictEqual(nullDisplay.text, 'Transit Data Unavailable');

      const giantGarbage = 'X'.repeat(5000);
      const giantDisplay = getTransitLayerDisplayState('error', giantGarbage);
      assert.strictEqual(giantDisplay.text, 'Transit Data Unavailable');
    });

    it('handles unexpected or unknown state cleanly with fallback', () => {
      const unknownStateDisplay = getTransitLayerDisplayState('unknown' as UIState);
      assert.strictEqual(unknownStateDisplay.badge, 'ready');
      assert.strictEqual(unknownStateDisplay.text, 'Transit Ready');
    });
  });
});
