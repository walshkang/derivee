import { describe, it } from 'node:test';
import assert from 'node:assert';
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
});
