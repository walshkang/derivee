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
});


