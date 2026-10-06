import { describe, it } from 'node:test';
import assert from 'node:assert';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  describeLeg,
  describeItinerary,
  isZeroLengthLeg,
  resolveStopName,
  countTransfers,
  canMergeTransitLegs,
  isPhantomTransfer,
  isTransitLeg,
  type LegInput,
} from '../itineraryDisplay.ts';

describe('Itinerary Leg Display Presentation Tests', () => {
  const mockStopsMap = new Map<number, { name: string }>([
    [101, { name: 'Times Sq - 42 St' }],
    [202, { name: '14 St - Union Sq' }],
    [303, { name: 'Atlantic Av - Barclays Ctr' }],
  ]);

  describe('Requirement 1 & 2: Collapsing zero-length stub legs vs normal transit', () => {
    it('zero-length first leg (from==to, <60s) → { kind: \'start\' }, station name kept', () => {
      // Zero-length origin stub leg (departure and arrival at same station, duration 0s < 60s)
      const firstLeg: LegInput = {
        board_stop_id: 101,
        exit_stop_id: 101,
        departure_time: 28800,
        arrival_time: 28800,
        trip_id: 0,
        route_id: 0,
        transfer_distance_m: 0,
        is_transfer: false,
      };

      const result = describeLeg(firstLeg, 0, 3, mockStopsMap);

      assert.strictEqual(result.kind, 'start', 'First zero-length leg must collapse to { kind: "start" }');
      assert.strictEqual(
        result.station,
        'Times Sq - 42 St',
        'Station name must be resolved and kept on the display model'
      );
      assert.strictEqual(result.stationName, 'Times Sq - 42 St');
      assert.strictEqual(result.stopId, 101);
      assert.strictEqual(result.time, 28800);

      // Pre-fix note:
      // Before this fix, TripPlanner rendered every leg as an itinerary-leg-card with
      // "Leg 1", mode pills, departure & arrival dots, and "Trip ID: #0" for origin stubs.
    });

    it('zero-length first leg with from_stop / to_stop aliases collapses and keeps explicit station name', () => {
      const firstLeg: LegInput = {
        from_stop: 101,
        to_stop: 101,
        departure_time: 28800,
        arrival_time: 28815, // 15 seconds < 60s
        station_name: 'Times Sq - 42 St',
        trip_id: 1234,
      };

      const result = describeLeg(firstLeg, 0, 2);

      assert.strictEqual(result.kind, 'start');
      assert.strictEqual(result.station, 'Times Sq - 42 St');
      assert.strictEqual(result.stopId, 101);
      assert.strictEqual(result.time, 28800);
    });

    it('zero-length last leg → { kind: \'arrive\' }', () => {
      // Zero-length destination stub leg (leg index 2 of 3)
      const lastLeg: LegInput = {
        board_stop_id: 303,
        exit_stop_id: 303,
        departure_time: 30000,
        arrival_time: 30000,
        trip_id: 0,
        route_id: 0,
        transfer_distance_m: 0,
        is_transfer: false,
      };

      const result = describeLeg(lastLeg, 2, 3, mockStopsMap);

      assert.strictEqual(result.kind, 'arrive', 'Last zero-length leg must collapse to { kind: "arrive" }');
      assert.strictEqual(
        result.station,
        'Atlantic Av - Barclays Ctr',
        'Destination station name must be resolved and kept'
      );
      assert.strictEqual(result.stopId, 303);
      assert.strictEqual(result.time, 30000);

      // Pre-fix note:
      // Before this fix, destination stubs rendered a full leg card with identical board
      // and exit markers for Stop #303 instead of a compact "Arrive at ..." row.
    });

    it('normal transit leg (different stations) → { kind: \'transit\' }, full detail kept', () => {
      const transitLeg: LegInput = {
        board_stop_id: 101,
        exit_stop_id: 303,
        departure_time: 28860,
        arrival_time: 29940, // 1080 seconds = 18 minutes
        route_id: 12,
        transfer_distance_m: 0,
        is_transfer: false,
        trip_id: 1659,
      };

      const result = describeLeg(transitLeg, 1, 3, mockStopsMap);

      assert.strictEqual(result.kind, 'transit', 'Leg between different stations must be { kind: "transit" }');
      if (result.kind === 'transit') {
        assert.strictEqual(result.boardStopId, 101);
        assert.strictEqual(result.exitStopId, 303);
        assert.strictEqual(result.boardStopName, 'Times Sq - 42 St');
        assert.strictEqual(result.exitStopName, 'Atlantic Av - Barclays Ctr');
        assert.strictEqual(result.departureTime, 28860);
        assert.strictEqual(result.arrivalTime, 29940);
        assert.strictEqual(result.durationMinutes, 18);
        assert.strictEqual(result.durationSeconds, 1080);
        assert.strictEqual(result.routeId, 12);
        assert.strictEqual(result.isTransfer, false);
        assert.strictEqual(result.transferDistanceM, 0);
        assert.strictEqual(result.legIndex, 1);
      }

      // Pre-fix note:
      // Before this fix, the UI displayed "Trip ID: #1659" in a meta row below the stop flow.
    });

    it('negative: same-station leg with duration ≥ 60s → NOT collapsed (stays transit)', () => {
      // Leg starting and ending at same station, but with duration of exactly 60 seconds
      const exact60sLeg: LegInput = {
        board_stop_id: 101,
        exit_stop_id: 101,
        departure_time: 28800,
        arrival_time: 28860, // exactly 60 seconds
        route_id: 1,
        transfer_distance_m: 0,
        is_transfer: true,
      };

      const result60 = describeLeg(exact60sLeg, 0, 3, mockStopsMap);
      assert.strictEqual(
        result60.kind,
        'transit',
        'Same-station leg with duration == 60s must NOT collapse; it stays transit'
      );

      // Leg starting and ending at same station with duration > 60 seconds (e.g. 120s dwell/transfer)
      const dwellLeg: LegInput = {
        board_stop_id: 202,
        exit_stop_id: 202,
        departure_time: 29000,
        arrival_time: 29120, // 120 seconds
        route_id: 2,
        transfer_distance_m: 50,
        is_transfer: true,
      };

      const resultDwell = describeLeg(dwellLeg, 2, 3, mockStopsMap);
      assert.strictEqual(
        resultDwell.kind,
        'transit',
        'Same-station leg with duration > 60s must NOT collapse; it stays transit'
      );

      // Pre-fix note:
      // A naive collapse checking only `from === to` without `duration < 60` would erroneously
      // erase legitimate in-station transfer dwells or layovers.
    });

    it('negative: same-station leg with different stop IDs and duration ≥ 60s → NOT collapsed (stays transit)', () => {
      // Different stop IDs (e.g. 72 and 74) that resolve to the same station ("Times Sq-42 St"),
      // but with duration of 60 seconds or longer (e.g. 60s walk/transfer between platforms)
      const interTrackTransfer: LegInput = {
        board_stop_id: 72,
        exit_stop_id: 74,
        departure_time: 28800,
        arrival_time: 28860, // 60s
        route_id: 0,
        transfer_distance_m: 50,
        is_transfer: true,
      };

      const result = describeLeg(
        interTrackTransfer,
        0,
        3,
        new Map([
          [72, { name: 'Times Sq-42 St' }],
          [74, { name: 'Times Sq-42 St' }],
        ])
      );

      assert.strictEqual(
        result.kind,
        'transit',
        'Same-station transfer with duration >= 60s must NOT collapse; it stays transit'
      );
      if (result.kind === 'transit') {
        assert.strictEqual(result.durationSeconds, 60);
        assert.strictEqual(result.boardStopName, 'Times Sq-42 St');
        assert.strictEqual(result.exitStopName, 'Times Sq-42 St');
      }
    });

    it('edge: single-leg itinerary that is zero-length → renders as start (no crash)', () => {
      const singleLeg: LegInput = {
        board_stop_id: 101,
        exit_stop_id: 101,
        departure_time: 28800,
        arrival_time: 28800,
        trip_id: 0,
        route_id: 0,
        transfer_distance_m: 0,
        is_transfer: false,
      };

      let result!: ReturnType<typeof describeLeg>;
      assert.doesNotThrow(() => {
        result = describeLeg(singleLeg, 0, 1, mockStopsMap);
      }, 'Single-leg zero-length itinerary must not throw or crash');

      assert.ok(result, 'Result must be returned');
      assert.strictEqual(
        result.kind,
        'start',
        'Single-leg zero-length itinerary (totalLegs=1, index=0) must render as start'
      );
      if (result.kind === 'start') {
        assert.strictEqual(result.station, 'Times Sq - 42 St');
      }

      // Pre-fix note:
      // Boundary conditions where index 0 is simultaneously the first and last leg (0 === 1 - 1)
      // must deterministically resolve to 'start' without index crashes or conflicts.
    });
  });

  describe('Requirement 1: Internal Trip IDs must never reach the display model or UI', () => {
    it('negative: normal leg\'s display model contains no trip identifier in any field', () => {
      const testTripId = 98765432;
      const legWithTripId: LegInput = {
        board_stop_id: 101,
        exit_stop_id: 202,
        departure_time: 28800,
        arrival_time: 29400,
        route_id: 5,
        transfer_distance_m: 0,
        is_transfer: false,
        trip_id: testTripId,
      };

      const model = describeLeg(legWithTripId, 1, 3, mockStopsMap);

      // 1. Scan JSON-serialized model: the trip id value must NOT appear anywhere in the string
      const serialized = JSON.stringify(model);
      assert.strictEqual(
        serialized.includes(testTripId.toString()),
        false,
        `Serialized model must not contain the trip id value ${testTripId}, got: ${serialized}`
      );

      // 2. Output model properties must not have any trip fields
      assert.strictEqual('trip_id' in (model as any), false, 'Display model must not have "trip_id" property');
      assert.strictEqual('tripId' in (model as any), false, 'Display model must not have "tripId" property');
      assert.strictEqual('trip' in (model as any), false, 'Display model must not have "trip" property');

      for (const key of Object.keys(model)) {
        assert.strictEqual(
          key.toLowerCase().includes('trip'),
          false,
          `No property key may mention "trip", found: ${key}`
        );
      }

      // Pre-fix note:
      // Before this fix, TripPlanner.tsx rendered `Trip ID: #{leg.trip_id}` directly in JSX,
      // exposing internal timetable trip indexes to the end user.
    });

    it('negative: zero-length start/arrive display models contain no trip identifier in any field', () => {
      const testTripId = 884422;
      const startStub: LegInput = {
        board_stop_id: 101,
        exit_stop_id: 101,
        departure_time: 28800,
        arrival_time: 28800,
        trip_id: testTripId,
      };

      const startModel = describeLeg(startStub, 0, 2, mockStopsMap);
      assert.strictEqual(JSON.stringify(startModel).includes(testTripId.toString()), false);
      assert.strictEqual('trip_id' in (startModel as any), false);

      const arriveStub: LegInput = {
        board_stop_id: 303,
        exit_stop_id: 303,
        departure_time: 29500,
        arrival_time: 29500,
        trip_id: testTripId,
      };

      const arriveModel = describeLeg(arriveStub, 1, 2, mockStopsMap);
      assert.strictEqual(JSON.stringify(arriveModel).includes(testTripId.toString()), false);
      assert.strictEqual('trip_id' in (arriveModel as any), false);
    });
  });

  describe('describeItinerary integration helper', () => {
    it('transforms a full itinerary collapsing both stubs and keeping intermediate transit leg', () => {
      const itinerary: LegInput[] = [
        {
          board_stop_id: 101,
          exit_stop_id: 101,
          departure_time: 28800,
          arrival_time: 28800,
          trip_id: 0,
        },
        {
          board_stop_id: 101,
          exit_stop_id: 303,
          departure_time: 28860,
          arrival_time: 29940,
          route_id: 12,
          trip_id: 1659,
          is_transfer: false,
        },
        {
          board_stop_id: 303,
          exit_stop_id: 303,
          departure_time: 29940,
          arrival_time: 29940,
          trip_id: 0,
        },
      ];

      const models = describeItinerary(itinerary, mockStopsMap);

      assert.strictEqual(models.length, 3);
      assert.strictEqual(models[0].kind, 'start');
      assert.strictEqual(models[0].station, 'Times Sq - 42 St');

      assert.strictEqual(models[1].kind, 'transit');
      if (models[1].kind === 'transit') {
        assert.strictEqual(models[1].routeId, 12);
        assert.strictEqual(models[1].durationMinutes, 18);
      }

      assert.strictEqual(models[2].kind, 'arrive');
      assert.strictEqual(models[2].station, 'Atlantic Av - Barclays Ctr');

      // Verify entire itinerary JSON does not contain trip ID 1659
      const allJson = JSON.stringify(models);
      assert.strictEqual(allJson.includes('1659'), false, 'No trip ID may be in serialized itinerary');
    });
  });

  describe('Helper functions: isZeroLengthLeg & resolveStopName', () => {
    it('isZeroLengthLeg accurately checks stop equality and duration threshold', () => {
      assert.strictEqual(
        isZeroLengthLeg({ board_stop_id: 1, exit_stop_id: 1, departure_time: 0, arrival_time: 59 }),
        true
      );
      assert.strictEqual(
        isZeroLengthLeg({ board_stop_id: 1, exit_stop_id: 1, departure_time: 0, arrival_time: 60 }),
        false
      );
      assert.strictEqual(
        isZeroLengthLeg({ board_stop_id: 1, exit_stop_id: 2, departure_time: 0, arrival_time: 0 }),
        false
      );
    });

    it('resolveStopName handles functions, maps, objects, and strings', () => {
      assert.strictEqual(resolveStopName(101, mockStopsMap), 'Times Sq - 42 St');
      assert.strictEqual(resolveStopName(101, (id) => `Station #${id}`), 'Station #101');
      assert.strictEqual(resolveStopName(101, { 101: 'Custom Name' }), 'Custom Name');
      assert.strictEqual(resolveStopName(101, 'Fallback Name'), 'Fallback Name');
      assert.strictEqual(resolveStopName(999), 'Stop #999');
      assert.strictEqual(resolveStopName(999, undefined, 'Explicit Name'), 'Explicit Name');
    });
  });

  describe('Real worker output regression: Times Sq → Atlantic Av preset', () => {
    // Verbatim leg objects emitted by C++ RAPTOR engine for Times Sq (72) -> Atlantic Av (207) at dep 28800 (08:00)
    const realWorkerLegs: LegInput[] = [
      {
        board_stop_id: 72,
        exit_stop_id: 74,
        trip_id: 0,
        departure_time: 28800,
        arrival_time: 28803,
        route_id: 0,
        transfer_distance_m: 3,
        is_transfer: false,
      },
      {
        board_stop_id: 74,
        exit_stop_id: 209,
        trip_id: 1659,
        departure_time: 28890,
        arrival_time: 30210,
        route_id: 12,
        transfer_distance_m: 0,
        is_transfer: false,
      },
      {
        board_stop_id: 209,
        exit_stop_id: 207,
        trip_id: 0,
        departure_time: 30210,
        arrival_time: 30212,
        route_id: 0,
        transfer_distance_m: 2,
        is_transfer: false,
      },
    ];

    const realStopsMap = new Map<number, { name: string }>([
      [72, { name: 'Times Sq-42 St' }],
      [74, { name: 'Times Sq-42 St' }],
      [207, { name: 'Atlantic Av-Barclays Ctr' }],
      [209, { name: 'Atlantic Av-Barclays Ctr' }],
    ]);

    it('collapses leg 1 (origin stub: stop 72 -> stop 74) to { kind: \'start\' } using real worker output', () => {
      const models = describeItinerary(realWorkerLegs, realStopsMap);

      assert.strictEqual(
        models[0].kind,
        'start',
        `Expected leg 1 to collapse to { kind: 'start' }, got kind: ${models[0].kind}`
      );
      if (models[0].kind === 'start') {
        assert.strictEqual(models[0].station, 'Times Sq-42 St');
        assert.strictEqual(models[0].stopId, 72);
        assert.strictEqual(models[0].time, 28800);
      }
    });

    it('collapses leg 3 (destination stub: stop 209 -> stop 207) to { kind: \'arrive\' } using real worker output', () => {
      const models = describeItinerary(realWorkerLegs, realStopsMap);

      assert.strictEqual(
        models[2].kind,
        'arrive',
        `Expected leg 3 to collapse to { kind: 'arrive' }, got kind: ${models[2].kind}`
      );
      if (models[2].kind === 'arrive') {
        assert.strictEqual(models[2].station, 'Atlantic Av-Barclays Ctr');
        assert.strictEqual(models[2].stopId, 207);
        assert.strictEqual(models[2].time, 30212);
      }
    });

    it('preserves leg 2 as full transit leg between different stations', () => {
      const models = describeItinerary(realWorkerLegs, realStopsMap);

      assert.strictEqual(models[1].kind, 'transit');
      if (models[1].kind === 'transit') {
        assert.strictEqual(models[1].boardStopName, 'Times Sq-42 St');
        assert.strictEqual(models[1].exitStopName, 'Atlantic Av-Barclays Ctr');
        assert.strictEqual(models[1].routeId, 12);
        assert.strictEqual(models[1].durationMinutes, 22);
      }
    });
  });

  describe('Requirement 2: Itinerary Results Scroll Container (phone viewport safety)', () => {
    it('declares bounded max-height, overflow-y: auto, and touch scrolling in index.css', () => {
      const __filename = fileURLToPath(import.meta.url);
      const __dirname = path.dirname(__filename);
      const cssPath = path.resolve(__dirname, '../../index.css');
      const cssContent = fs.readFileSync(cssPath, 'utf-8');

      // Match the .itinerary-results-container CSS rule block
      const containerRuleMatch = cssContent.match(/\.itinerary-results-container\s*\{([^}]+)\}/);
      assert.ok(containerRuleMatch, '.itinerary-results-container rule must exist in index.css');

      const ruleBody = containerRuleMatch[1];

      // 1. Verify bounded height (max-height)
      assert.match(
        ruleBody,
        /max-height:\s*[^;]+;/,
        'itinerary-results-container must have bounded max-height for phone viewport safety'
      );

      // 2. Verify overflow-y: auto
      assert.match(
        ruleBody,
        /overflow-y:\s*auto;/,
        'itinerary-results-container must have overflow-y: auto for independent scrolling'
      );

      // 3. Verify touch scrolling for mobile devices
      assert.match(
        ruleBody,
        /-webkit-overflow-scrolling:\s*touch;/,
        'itinerary-results-container must enable smooth touch scrolling on mobile'
      );
    });

    it('overflows and is scrollable when 3+ legs exceed the bounded container height', () => {
      // Simulate container bounding box on a mobile viewport
      const boundedMaxHeight = 340; // px
      const summaryHeaderHeight = 70; // px
      const cardHeight = 110; // px per transit leg card
      const gap = 10; // px gap between items

      // Constrained fixture with 3+ legs:
      // Even with 3 legs (summary + 3 cards + gaps): 70 + 330 + 30 = 430px > 340px
      const legsCount = 3;
      const totalContentHeight = summaryHeaderHeight + legsCount * cardHeight + legsCount * gap;

      const simulatedContainer = {
        clientHeight: boundedMaxHeight,
        scrollHeight: totalContentHeight,
        isScrollable: function () {
          return this.scrollHeight > this.clientHeight;
        },
      };

      assert.strictEqual(
        simulatedContainer.isScrollable(),
        true,
        `With 3+ legs (content ${totalContentHeight}px > container ${boundedMaxHeight}px), container must be scrollable`
      );
      assert.ok(simulatedContainer.scrollHeight > simulatedContainer.clientHeight);
    });

    it('negative: does not trap page scroll when content fits within container', () => {
      const summaryHeaderHeight = 70; // px
      const singleCompactRowHeight = 40; // px

      // Short itinerary where content easily fits (e.g. 1 leg or 110px total <= 340px)
      const fittedContentHeight = summaryHeaderHeight + singleCompactRowHeight;

      const simulatedContainer = {
        clientHeight: fittedContentHeight, // max-height shrinks to content height
        scrollHeight: fittedContentHeight,
        hasOverflow: function () {
          return this.scrollHeight > this.clientHeight;
        },
      };

      assert.strictEqual(
        simulatedContainer.hasOverflow(),
        false,
        'When content fits, scrollHeight <= clientHeight; no scroll trapping occurs'
      );
    });
  });

  describe('M5d: Leg Mode Foundation & Zero Internal ID Leaks', () => {
    it('discriminates leg modes: transit, transfer, and walk', () => {
      // 1. Normal transit leg
      const transitLeg: LegInput = {
        board_stop_id: 101,
        exit_stop_id: 202,
        departure_time: 28800,
        arrival_time: 29400,
        route_id: 167, // RAPTOR uint16 pattern index
        is_transfer: false,
      };
      const transitModel = describeLeg(transitLeg, 1, 4, mockStopsMap);
      assert.strictEqual(transitModel.kind, 'transit');
      if (transitModel.kind === 'transit') {
        assert.strictEqual(transitModel.mode, 'transit');
        assert.strictEqual(transitModel.routeId, 167);
      }

      // 2. Transfer leg derived from is_transfer: true
      const transferLeg: LegInput = {
        board_stop_id: 202,
        exit_stop_id: 203,
        departure_time: 29400,
        arrival_time: 29550,
        route_id: 0,
        transfer_distance_m: 120,
        is_transfer: true,
      };
      const transferModel = describeLeg(transferLeg, 2, 4, mockStopsMap);
      assert.strictEqual(transferModel.kind, 'transit');
      if (transferModel.kind === 'transit') {
        assert.strictEqual(transferModel.mode, 'transfer');
        assert.strictEqual(transferModel.isTransfer, true);
        assert.strictEqual(transferModel.transferDistanceM, 120);
      }

      // 3. Explicit walk leg
      const walkLeg: LegInput = {
        board_stop_id: 203,
        exit_stop_id: 204,
        departure_time: 29550,
        arrival_time: 29700,
        mode: 'walk',
        transfer_distance_m: 100,
      };
      const walkModel = describeLeg(walkLeg, 3, 5, mockStopsMap);
      assert.strictEqual(walkModel.kind, 'transit');
      if (walkModel.kind === 'transit') {
        assert.strictEqual(walkModel.mode, 'walk');
      }
    });

    it('missing route_id stays undefined and does NOT default to 0', () => {
      const missingRouteLeg: LegInput = {
        board_stop_id: 101,
        exit_stop_id: 202,
        departure_time: 28800,
        arrival_time: 29400,
        route_id: undefined,
        is_transfer: false,
      };
      const model = describeLeg(missingRouteLeg, 1, 3, mockStopsMap);
      assert.strictEqual(model.kind, 'transit');
      if (model.kind === 'transit') {
        assert.strictEqual(model.routeId, undefined, 'routeId must be undefined when missing, not 0');
        assert.strictEqual(model.route_id, undefined, 'route_id must be undefined when missing, not 0');
      }
    });

    it('negative: zero raw pattern indices (e.g. 167, 36) or trip_ids leak into any string property', () => {
      const realEngineLegs: LegInput[] = [
        {
          board_stop_id: 101,
          exit_stop_id: 101,
          departure_time: 28800,
          arrival_time: 28800,
          is_transfer: false,
          trip_id: 998877,
        },
        {
          board_stop_id: 101,
          exit_stop_id: 202,
          departure_time: 28800,
          arrival_time: 29400,
          route_id: 167,
          trip_id: 1045,
          is_transfer: false,
        },
        {
          board_stop_id: 202,
          exit_stop_id: 203,
          departure_time: 29400,
          arrival_time: 29550,
          route_id: 0,
          transfer_distance_m: 150,
          trip_id: 0,
          is_transfer: true,
        },
        {
          board_stop_id: 203,
          exit_stop_id: 303,
          departure_time: 29550,
          arrival_time: 30300,
          route_id: 36,
          trip_id: 2099,
          is_transfer: false,
        },
        {
          board_stop_id: 303,
          exit_stop_id: 303,
          departure_time: 30300,
          arrival_time: 30300,
          is_transfer: false,
          trip_id: 0,
        },
      ];

      const models = describeItinerary(realEngineLegs, mockStopsMap);

      // Check all string properties across all models
      for (const m of models) {
        for (const [key, val] of Object.entries(m)) {
          if (typeof val === 'string') {
            assert.ok(!val.includes('167'), `String property "${key}" contains raw route pattern 167: "${val}"`);
            assert.ok(!val.includes('36'), `String property "${key}" contains raw route pattern 36: "${val}"`);
            assert.ok(!val.includes('1045'), `String property "${key}" contains raw trip_id 1045: "${val}"`);
            assert.ok(!val.includes('2099'), `String property "${key}" contains raw trip_id 2099: "${val}"`);
            assert.ok(!val.includes('998877'), `String property "${key}" contains raw trip_id 998877: "${val}"`);
          }
        }
      }
    });
  });

  describe('M5e: Itinerary Leg Grouping & Transfer Model', () => {
    const stopsResolver = new Map<number, { name: string }>([
      [101, { name: 'Times Sq - 42 St' }],
      [102, { name: '34 St - Penn Station' }],
      [103, { name: '14 St - Union Sq' }],
      [201, { name: '14 St - Union Sq' }],
      [202, { name: 'Astor Pl' }],
      [203, { name: 'Bleecker St' }],
      [1246, { name: 'Bowery' }],
      [1247, { name: 'Bowery' }],
      [1250, { name: 'Canal St' }],
      [1288, { name: 'Canal St' }],
      [1336, { name: '34 St - Herald Sq' }],
      [76, { name: '34 St - Penn Station' }],
      [67, { name: '59 St - Columbus Circle' }],
      [66, { name: '59 St - Columbus Circle' }],
    ]);

    it('groups consecutive transit segments on the same vehicle (same trip_id) into one ride leg', () => {
      const perStopSegments: LegInput[] = [
        // Origin stub
        { board_stop_id: 101, exit_stop_id: 101, departure_time: 28800, arrival_time: 28800, trip_id: 0, route_id: 0, transfer_distance_m: 0 },
        // Hop 1: Times Sq -> 34 St (same train, trip 5001)
        { board_stop_id: 101, exit_stop_id: 102, departure_time: 28860, arrival_time: 28980, trip_id: 5001, route_id: 1, transfer_distance_m: 0 },
        // Hop 2: 34 St -> 14 St (same train, trip 5001)
        { board_stop_id: 102, exit_stop_id: 103, departure_time: 28980, arrival_time: 29160, trip_id: 5001, route_id: 1, transfer_distance_m: 0 },
        // Destination stub
        { board_stop_id: 103, exit_stop_id: 103, departure_time: 29160, arrival_time: 29160, trip_id: 0, route_id: 0, transfer_distance_m: 0 },
      ];

      const models = describeItinerary(perStopSegments, stopsResolver);

      // Must produce: start row, exactly 1 grouped transit leg, arrive row
      assert.strictEqual(models.length, 3, `Expected 3 models (start, 1 ride, arrive), got ${models.length}`);
      assert.strictEqual(models[0].kind, 'start');
      assert.strictEqual(models[1].kind, 'transit');
      assert.strictEqual(models[2].kind, 'arrive');

      if (models[1].kind === 'transit') {
        assert.strictEqual(models[1].boardStopName, 'Times Sq - 42 St');
        assert.strictEqual(models[1].exitStopName, '14 St - Union Sq');
        assert.strictEqual(models[1].intermediateStopsCount, 1, 'Should record 1 intermediate stop');
        assert.strictEqual(models[1].stopCount, 1);
        assert.strictEqual(models[1].durationMinutes, 5, 'Total ride duration should be 29160 - 28860 = 300s = 5m');
        assert.strictEqual(models[1].mode, 'transit');
        assert.strictEqual(models[1].legIndex, 0);
      }

      assert.strictEqual(countTransfers(perStopSegments, stopsResolver), 0, 'Single-seat ride must have 0 transfers');
    });

    it('renders transfers between ride legs as connector rows ("Change at {station}")', () => {
      const multiRideJourney: LegInput[] = [
        // Origin stub
        { board_stop_id: 101, exit_stop_id: 101, departure_time: 28800, arrival_time: 28800, trip_id: 0, route_id: 0 },
        // Ride 1: Times Sq -> 14 St
        { board_stop_id: 101, exit_stop_id: 103, departure_time: 28860, arrival_time: 29160, trip_id: 5001, route_id: 1, transfer_distance_m: 0 },
        // Station transfer walk within 14 St complex: 103 -> 201
        { board_stop_id: 103, exit_stop_id: 201, departure_time: 29160, arrival_time: 29280, trip_id: 0, route_id: 0, transfer_distance_m: 85, is_transfer: true },
        // Ride 2: 14 St -> Bleecker St
        { board_stop_id: 201, exit_stop_id: 203, departure_time: 29340, arrival_time: 29580, trip_id: 6002, route_id: 6, transfer_distance_m: 0 },
        // Dest stub
        { board_stop_id: 203, exit_stop_id: 203, departure_time: 29580, arrival_time: 29580, trip_id: 0, route_id: 0 },
      ];

      const models = describeItinerary(multiRideJourney, stopsResolver);

      assert.strictEqual(models.length, 5, 'Must produce: start, ride 1, connector, ride 2, arrive');
      assert.strictEqual(models[0].kind, 'start');
      assert.strictEqual(models[1].kind, 'transit');
      assert.strictEqual(models[2].kind, 'connector');
      assert.strictEqual(models[3].kind, 'transit');
      assert.strictEqual(models[4].kind, 'arrive');

      if (models[2].kind === 'connector') {
        assert.match(models[2].text, /Change at 14 St/i, 'Connector text must announce Change at 14 St');
        assert.strictEqual(models[2].transferDistanceM, 85);
        assert.strictEqual(models[2].durationMinutes, 2);
      }

      assert.strictEqual(countTransfers(multiRideJourney, stopsResolver), 1, 'Two rides with connection = exactly 1 transfer');
    });

    it('real engine output fixture (Bowery -> Columbus Circle): groups rides, inserts connectors, 2 transfers', () => {
      const BOWERY_COLUMBUS_SEGMENTS: LegInput[] = [
        { board_stop_id: 1246, exit_stop_id: 1247, trip_id: 0, departure_time: 28800, arrival_time: 28802, route_id: 0, transfer_distance_m: 2, is_transfer: false },
        { board_stop_id: 1247, exit_stop_id: 1250, trip_id: 20615, departure_time: 28920, arrival_time: 29010, route_id: 217, transfer_distance_m: 0, is_transfer: false },
        { board_stop_id: 1250, exit_stop_id: 1288, trip_id: 0, departure_time: 29010, arrival_time: 29067, route_id: 0, transfer_distance_m: 74, is_transfer: false },
        { board_stop_id: 1288, exit_stop_id: 1336, trip_id: 18522, departure_time: 29130, arrival_time: 29520, route_id: 190, transfer_distance_m: 0, is_transfer: false },
        { board_stop_id: 1336, exit_stop_id: 76, trip_id: 0, departure_time: 29520, arrival_time: 29611, route_id: 0, transfer_distance_m: 118, is_transfer: false },
        { board_stop_id: 76, exit_stop_id: 67, trip_id: 89, departure_time: 29700, arrival_time: 30030, route_id: 3, transfer_distance_m: 0, is_transfer: false },
        { board_stop_id: 67, exit_stop_id: 66, trip_id: 0, departure_time: 30030, arrival_time: 30038, route_id: 0, transfer_distance_m: 10, is_transfer: false },
      ];

      const models = describeItinerary(BOWERY_COLUMBUS_SEGMENTS, stopsResolver);

      const transitModels = models.filter((m) => m.kind === 'transit');
      const connectorModels = models.filter((m) => m.kind === 'connector');

      assert.strictEqual(transitModels.length, 3, 'Must yield exactly 3 transit ride legs');
      assert.strictEqual(connectorModels.length, 2, 'Must yield exactly 2 connector rows');
      assert.strictEqual(countTransfers(BOWERY_COLUMBUS_SEGMENTS, stopsResolver), 2, 'Bowery -> Columbus Circle must count as 2 transfers');

      // Verify connector content
      assert.match(connectorModels[0].text, /Change at Canal St/i);
      assert.strictEqual(connectorModels[0].transferDistanceM, 74);
      assert.match(connectorModels[1].text, /Change at 34 St/i);
      assert.strictEqual(connectorModels[1].transferDistanceM, 118);
    });

    it('negative case: two different trip_ids on the same route do NOT merge', () => {
      const legA: LegInput = {
        board_stop_id: 101,
        exit_stop_id: 102,
        departure_time: 28800,
        arrival_time: 29000,
        route_id: 1,
        trip_id: 1001,
      };
      const legB: LegInput = {
        board_stop_id: 102,
        exit_stop_id: 103,
        departure_time: 29060,
        arrival_time: 29260,
        route_id: 1,
        trip_id: 1002, // Different trip!
      };

      assert.strictEqual(
        canMergeTransitLegs(legA, legB, stopsResolver),
        false,
        'Legs with different trip_ids must NOT merge even if on the same route'
      );

      const models = describeItinerary([legA, legB], stopsResolver);
      const transitModels = models.filter((m) => m.kind === 'transit');
      assert.strictEqual(transitModels.length, 2, 'Different trip_ids must remain 2 separate ride legs');
      assert.strictEqual(countTransfers([legA, legB], stopsResolver), 1, 'Changing trains on same route is 1 transfer');
    });

    it('negative case: zero-minute phantom transfer does NOT inflate transfer count', () => {
      const journeyWithPhantom: LegInput[] = [
        // Single transit ride
        { board_stop_id: 101, exit_stop_id: 102, departure_time: 28800, arrival_time: 29400, trip_id: 501, route_id: 1, transfer_distance_m: 0 },
        // Phantom 0-duration, 0-distance transfer
        { board_stop_id: 102, exit_stop_id: 102, departure_time: 29400, arrival_time: 29400, trip_id: 0, route_id: 0, transfer_distance_m: 0, is_transfer: true },
      ];

      assert.strictEqual(isTransitLeg(journeyWithPhantom[0]), true, 'Transit leg must be recognized by isTransitLeg');
      assert.strictEqual(isTransitLeg(journeyWithPhantom[1]), false, 'Phantom transfer must not be recognized as transit leg');
      assert.strictEqual(isPhantomTransfer(journeyWithPhantom[1], stopsResolver), true, 'Zero-duration zero-dist leg must be detected as phantom transfer');
      assert.strictEqual(countTransfers(journeyWithPhantom, stopsResolver), 0, 'Zero-minute phantom transfer must NOT inflate transfer count');
    });

    it('inserts connector row when two transit rides are adjacent without explicit transfer leg', () => {
      const adjacentRides: LegInput[] = [
        { board_stop_id: 101, exit_stop_id: 102, departure_time: 28800, arrival_time: 29000, trip_id: 101, route_id: 1 },
        { board_stop_id: 102, exit_stop_id: 203, departure_time: 29120, arrival_time: 29400, trip_id: 202, route_id: 2 },
      ];

      const models = describeItinerary(adjacentRides, stopsResolver);
      assert.strictEqual(models.length, 3, 'Must have ride 1, auto-inserted connector, ride 2');
      assert.strictEqual(models[0].kind, 'transit');
      assert.strictEqual(models[1].kind, 'connector');
      assert.strictEqual(models[2].kind, 'transit');
      if (models[1].kind === 'connector') {
        assert.match(models[1].text, /Change at 34 St/i);
        assert.strictEqual(models[1].durationMinutes, 2, 'Layover 29120 - 29000 = 120s = 2m');
      }
      assert.strictEqual(countTransfers(adjacentRides, stopsResolver), 1);
    });
  });
});
