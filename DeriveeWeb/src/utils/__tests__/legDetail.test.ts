import { describe, it } from 'node:test';
import assert from 'node:assert';
import {
  describeItinerary,
  formatHeadsign,
  type LegInput,
  type TransitLegDisplay,
} from '../itineraryDisplay.ts';
import {
  getRouteHighlightPaintProperties,
  highlightRouteOnMap,
  TRANSIT_LINES_LAYER_ID,
  TRANSIT_LINES_CASING_LAYER_ID,
  TRANSIT_STATIONS_LAYER_ID,
} from '../transitOverlays.ts';

describe('Leg Detail & Map Highlight Tests (Wave T2)', () => {
  const sampleStops = new Map([
    [101, { name: 'Times Sq - 42 St' }],
    [102, { name: '34 St - Penn Station' }],
    [103, { name: '28 St' }],
    [104, { name: '23 St' }],
    [105, { name: '14 St - Union Sq' }],
  ]);

  const samplePatterns = [
    { route_id: '1', direction_id: 1, headsign: 'South Ferry' },
  ];

  describe('1. Stop list & Scheduled Times Extraction in describeItinerary', () => {
    it('populates full stop list with scheduled times for multi-stop ride legs', () => {
      const multiHopLegs: LegInput[] = [
        // Times Sq -> 34 St
        { board_stop_id: 101, exit_stop_id: 102, departure_time: 28800, arrival_time: 28920, trip_id: 501, route_id: 0, transfer_distance_m: 0 },
        // 34 St -> 28 St
        { board_stop_id: 102, exit_stop_id: 103, departure_time: 28920, arrival_time: 29010, trip_id: 501, route_id: 0, transfer_distance_m: 0 },
        // 28 St -> 23 St
        { board_stop_id: 103, exit_stop_id: 104, departure_time: 29010, arrival_time: 29100, trip_id: 501, route_id: 0, transfer_distance_m: 0 },
        // 23 St -> 14 St
        { board_stop_id: 104, exit_stop_id: 105, departure_time: 29100, arrival_time: 29220, trip_id: 501, route_id: 0, transfer_distance_m: 0 },
      ];

      const models = describeItinerary(multiHopLegs, sampleStops, samplePatterns);
      const transitLeg = models.find((m) => m.kind === 'transit') as TransitLegDisplay | undefined;

      assert.ok(transitLeg, 'Must produce a transit leg');
      assert.strictEqual(transitLeg.intermediateStopsCount, 3, 'Must have 3 intermediate stops');
      assert.ok(Array.isArray(transitLeg.stops), 'Must attach stops array');
      assert.strictEqual(transitLeg.stops?.length, 5, 'Must contain 5 total stops (board + 3 intermediate + alight)');

      // Check Boarding Stop
      const boardStop = transitLeg.stops[0];
      assert.strictEqual(boardStop.stopId, 101);
      assert.strictEqual(boardStop.stopName, 'Times Sq - 42 St');
      assert.strictEqual(boardStop.time, 28800);
      assert.strictEqual(boardStop.isBoarding, true);
      assert.strictEqual(boardStop.isAlighting, false);

      // Check Intermediate Stops
      const stop2 = transitLeg.stops[1];
      assert.strictEqual(stop2.stopId, 102);
      assert.strictEqual(stop2.stopName, '34 St - Penn Station');
      assert.strictEqual(stop2.time, 28920);
      assert.strictEqual(stop2.isBoarding, false);
      assert.strictEqual(stop2.isAlighting, false);

      const stop3 = transitLeg.stops[2];
      assert.strictEqual(stop3.stopId, 103);
      assert.strictEqual(stop3.stopName, '28 St');
      assert.strictEqual(stop3.time, 29010);

      const stop4 = transitLeg.stops[3];
      assert.strictEqual(stop4.stopId, 104);
      assert.strictEqual(stop4.stopName, '23 St');
      assert.strictEqual(stop4.time, 29100);

      // Check Alighting Stop
      const alightStop = transitLeg.stops[4];
      assert.strictEqual(alightStop.stopId, 105);
      assert.strictEqual(alightStop.stopName, '14 St - Union Sq');
      assert.strictEqual(alightStop.time, 29220);
      assert.strictEqual(alightStop.isBoarding, false);
      assert.strictEqual(alightStop.isAlighting, true);
    });

    it('negative case: handles single-hop leg cleanly (0 intermediate stops)', () => {
      const singleHopLegs: LegInput[] = [
        { board_stop_id: 101, exit_stop_id: 102, departure_time: 28800, arrival_time: 28920, trip_id: 501, route_id: 0, transfer_distance_m: 0 },
      ];

      const models = describeItinerary(singleHopLegs, sampleStops, samplePatterns);
      const transitLeg = models.find((m) => m.kind === 'transit') as TransitLegDisplay | undefined;

      assert.ok(transitLeg);
      assert.strictEqual(transitLeg.intermediateStopsCount, 0);
      assert.strictEqual(transitLeg.stops?.length, 2);
      assert.strictEqual(transitLeg.stops[0].isBoarding, true);
      assert.strictEqual(transitLeg.stops[1].isAlighting, true);
    });
  });

  describe('2. Headsign Engine & FC-2 Destination Formatting', () => {
    it('formats headsign with "To [Terminal]" prefix when headsign is present', () => {
      assert.strictEqual(formatHeadsign('South Ferry'), 'To South Ferry');
      assert.strictEqual(formatHeadsign('Van Cortlandt Park-242 St'), 'To Van Cortlandt Park-242 St');
      assert.strictEqual(formatHeadsign('To South Ferry'), 'To South Ferry', 'Does not duplicate "To To"');
    });

    it('falls back cleanly to "To [Station]" when headsign is missing', () => {
      assert.strictEqual(formatHeadsign(undefined, '14 St - Union Sq'), 'To 14 St - Union Sq');
      assert.strictEqual(formatHeadsign('', '14 St - Union Sq'), 'To 14 St - Union Sq');
      assert.strictEqual(formatHeadsign('   ', 'Atlantic Av'), 'To Atlantic Av');
    });

    it('negative case: returns empty string when neither headsign nor fallback station is provided', () => {
      assert.strictEqual(formatHeadsign(undefined, undefined), '');
      assert.strictEqual(formatHeadsign('', ''), '');
    });

    it('FC-2 invariant: headsign formatting never outputs raw numeric IDs or hashes', () => {
      const out = formatHeadsign('trip_id_9901_L');
      // If dirty telemetry string was passed, ensures sanitized or plain English
      assert.ok(!out.includes('trip_id_'));
    });
  });

  describe('3. Map Highlight & Dimming Paint Properties', () => {
    it('returns dimmed paint properties for non-matching lines when routeId is active', () => {
      const props = getRouteHighlightPaintProperties('1');

      assert.ok(props.lines['line-opacity'], 'Must specify line-opacity');
      assert.ok(props.casing['line-opacity'], 'Must specify casing line-opacity');
      assert.strictEqual(props.stations['circle-opacity'], 0.25);
      assert.strictEqual(props.stations['circle-stroke-opacity'], 0.25);

      // Verify structure of the expression: case expression matching route '1'
      const lineOpacityExpr = props.lines['line-opacity'] as any[];
      assert.strictEqual(lineOpacityExpr[0], 'case');
      // Active route has opacity 1.0, dimmed routes have 0.15
      assert.strictEqual(lineOpacityExpr[2], 1.0);
      assert.strictEqual(lineOpacityExpr[3], 0.15);

      const casingOpacityExpr = props.casing['line-opacity'] as any[];
      assert.strictEqual(casingOpacityExpr[0], 'case');
      assert.strictEqual(casingOpacityExpr[2], 0.95);
      assert.strictEqual(casingOpacityExpr[3], 0.05);
    });

    it('returns full-overlay restored paint properties when routeId is null', () => {
      const props = getRouteHighlightPaintProperties(null);

      assert.strictEqual(props.lines['line-opacity'], 1.0, 'Restores full line opacity');
      assert.strictEqual(props.casing['line-opacity'], 0.9, 'Restores full casing opacity');
      assert.strictEqual(props.stations['circle-opacity'], 1.0, 'Restores full station opacity');
      assert.strictEqual(props.stations['circle-stroke-opacity'], 1.0, 'Restores station stroke opacity');
    });

    it('negative case: handles empty string or whitespace routeId as unhighlighted (restored)', () => {
      const propsEmpty = getRouteHighlightPaintProperties('');
      assert.strictEqual(propsEmpty.lines['line-opacity'], 1.0);

      const propsWhitespace = getRouteHighlightPaintProperties('   ');
      assert.strictEqual(propsWhitespace.lines['line-opacity'], 1.0);
    });
  });

  describe('4. highlightRouteOnMap Integration with MapLibre Map', () => {
    it('applies paint properties and sets data-highlighted-route attribute on map container', () => {
      const paintCalls: Record<string, Record<string, any>> = {
        [TRANSIT_LINES_LAYER_ID]: {},
        [TRANSIT_LINES_CASING_LAYER_ID]: {},
        [TRANSIT_STATIONS_LAYER_ID]: {},
      };
      const attributes: Record<string, string> = {};

      const mockMap: any = {
        getLayer(layerId: string) {
          return paintCalls[layerId] !== undefined ? {} : null;
        },
        setPaintProperty(layerId: string, prop: string, val: any) {
          if (paintCalls[layerId]) {
            paintCalls[layerId][prop] = val;
          }
        },
        getContainer() {
          return {
            setAttribute(k: string, v: string) { attributes[k] = v; },
            removeAttribute(k: string) { delete attributes[k]; },
            getAttribute(k: string) { return attributes[k] || null; },
          };
        },
      };

      // 1. Highlight Route 'L'
      highlightRouteOnMap(mockMap, 'L');
      assert.strictEqual(attributes['data-highlighted-route'], 'L');
      assert.ok(paintCalls[TRANSIT_LINES_LAYER_ID]['line-opacity'] !== undefined);
      assert.ok(paintCalls[TRANSIT_LINES_CASING_LAYER_ID]['line-opacity'] !== undefined);

      // 2. Restore Full Overlay (null route)
      highlightRouteOnMap(mockMap, null);
      assert.strictEqual(attributes['data-highlighted-route'], undefined);
      assert.strictEqual(paintCalls[TRANSIT_LINES_LAYER_ID]['line-opacity'], 1.0);
      assert.strictEqual(paintCalls[TRANSIT_LINES_CASING_LAYER_ID]['line-opacity'], 0.9);
      assert.strictEqual(paintCalls[TRANSIT_STATIONS_LAYER_ID]['circle-opacity'], 1.0);
    });

    it('negative case: handles null map or missing layers safely without throwing', () => {
      assert.doesNotThrow(() => {
        highlightRouteOnMap(null, '1');
      });

      const emptyMap: any = {
        getLayer() { return null; },
        setPaintProperty() {},
        getContainer() { return { setAttribute() {}, removeAttribute() {} }; },
      };
      assert.doesNotThrow(() => {
        highlightRouteOnMap(emptyMap, '1');
        highlightRouteOnMap(emptyMap, null);
      });
    });
  });
});
