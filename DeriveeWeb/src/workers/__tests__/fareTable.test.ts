import test from 'node:test';
import assert from 'node:assert';
import { computeItineraryFare } from '../fareTable.ts';
import type { RoutingSegment, RoutePatternEntry } from '../../types/routing.ts';

test('Fare Calculation - NYC Subway -> Local Bus is $3.00 (One Fare)', () => {
  const segments: RoutingSegment[] = [
    { board_stop_id: 1, exit_stop_id: 2, trip_id: 1, route_id: 0, departure_time: 0, arrival_time: 100, is_transfer: false, transfer_distance_m: 0 },
    { board_stop_id: 2, exit_stop_id: 2, trip_id: 0xFFFFFFFF, route_id: 0xFFFF, departure_time: 100, arrival_time: 150, is_transfer: true, transfer_distance_m: 100 },
    { board_stop_id: 2, exit_stop_id: 3, trip_id: 2, route_id: 1, departure_time: 200, arrival_time: 300, is_transfer: false, transfer_distance_m: 0 }
  ];
  
  const patterns: RoutePatternEntry[] = [
    { route_id: '1' }, // Subway
    { route_id: 'B44' } // Local bus
  ];
  
  const fare = computeItineraryFare(segments, 'nyc', patterns);
  assert.strictEqual(fare, 300);

  // Negative case: third leg is not free
  const segments3: RoutingSegment[] = [
    ...segments,
    { board_stop_id: 3, exit_stop_id: 3, trip_id: 0xFFFFFFFF, route_id: 0xFFFF, departure_time: 300, arrival_time: 350, is_transfer: true, transfer_distance_m: 100 },
    { board_stop_id: 3, exit_stop_id: 4, trip_id: 3, route_id: 1, departure_time: 400, arrival_time: 500, is_transfer: false, transfer_distance_m: 0 }
  ];
  const fare3 = computeItineraryFare(segments3, 'nyc', patterns);
  assert.strictEqual(fare3, 600, 'Second transfer should not be free');
});

test('Fare Calculation - NYC Subway -> SBS is $3.00 (One Fare per MTA site)', () => {
  const segments: RoutingSegment[] = [
    { board_stop_id: 1, exit_stop_id: 2, trip_id: 1, route_id: 0, departure_time: 0, arrival_time: 100, is_transfer: false, transfer_distance_m: 0 },
    { board_stop_id: 2, exit_stop_id: 2, trip_id: 0xFFFFFFFF, route_id: 0xFFFF, departure_time: 100, arrival_time: 150, is_transfer: true, transfer_distance_m: 100 },
    { board_stop_id: 2, exit_stop_id: 3, trip_id: 2, route_id: 1, departure_time: 200, arrival_time: 300, is_transfer: false, transfer_distance_m: 0 }
  ];
  
  const patterns: RoutePatternEntry[] = [
    { route_id: '1' }, // Subway
    { route_id: 'B44+' } // SBS
  ];
  
  const fare = computeItineraryFare(segments, 'nyc', patterns);
  assert.strictEqual(fare, 300, 'Subway -> SBS should be a free transfer per MTA rules');

  // Negative case: Bike share (unknown mode) contributes 0
  const segmentsBike: RoutingSegment[] = [
    { board_stop_id: 1, exit_stop_id: 2, trip_id: 1, route_id: 2, departure_time: 0, arrival_time: 100, is_transfer: false, transfer_distance_m: 0 }
  ];
  const patternsBike: RoutePatternEntry[] = [
    { route_id: '1' }, { route_id: 'B44+' }, { route_id: 'UNKNOWN' }
  ];
  const fareBike = computeItineraryFare(segmentsBike, 'nyc', patternsBike);
  assert.strictEqual(fareBike, 0, 'Unknown modes should contribute 0');
});

test('Fare Calculation - NYC Ferry Leg is $4.00 (Separate Fare)', () => {
  const segments: RoutingSegment[] = [
    { board_stop_id: 1, exit_stop_id: 2, trip_id: 1, route_id: 0, departure_time: 0, arrival_time: 100, is_transfer: false, transfer_distance_m: 0 },
    { board_stop_id: 2, exit_stop_id: 2, trip_id: 0xFFFFFFFF, route_id: 0xFFFF, departure_time: 100, arrival_time: 150, is_transfer: true, transfer_distance_m: 100 },
    { board_stop_id: 2, exit_stop_id: 3, trip_id: 2, route_id: 1, departure_time: 200, arrival_time: 300, is_transfer: false, transfer_distance_m: 0 }
  ];
  
  const patterns: RoutePatternEntry[] = [
    { route_id: '1' }, // Subway
    { route_id: 'ER' } // Ferry
  ];
  
  const fare = computeItineraryFare(segments, 'nyc', patterns);
  assert.strictEqual(fare, 700); // 300 + 400

  // Negative case: Ferry -> Ferry is not free
  const segmentsFerryFerry: RoutingSegment[] = [
    { board_stop_id: 1, exit_stop_id: 2, trip_id: 1, route_id: 1, departure_time: 0, arrival_time: 100, is_transfer: false, transfer_distance_m: 0 },
    { board_stop_id: 2, exit_stop_id: 2, trip_id: 0xFFFFFFFF, route_id: 0xFFFF, departure_time: 100, arrival_time: 150, is_transfer: true, transfer_distance_m: 100 },
    { board_stop_id: 2, exit_stop_id: 3, trip_id: 2, route_id: 1, departure_time: 200, arrival_time: 300, is_transfer: false, transfer_distance_m: 0 }
  ];
  const fareFerryFerry = computeItineraryFare(segmentsFerryFerry, 'nyc', patterns);
  assert.strictEqual(fareFerryFerry, 800, 'Ferry does not have free transfers');
});

test('Fare Calculation - Distance Formula Fixture', () => {
  const segments: RoutingSegment[] = [
    { board_stop_id: 1, exit_stop_id: 2, trip_id: 1, route_id: 0, departure_time: 0, arrival_time: 100, is_transfer: false, transfer_distance_m: 550 },
    { board_stop_id: 2, exit_stop_id: 3, trip_id: 2, route_id: 1, departure_time: 200, arrival_time: 300, is_transfer: false, transfer_distance_m: 1000 }
  ];
  
  const fare = computeItineraryFare(segments, 'distance_fixture');
  assert.strictEqual(fare, 550);

  // Negative case: 0 distance yields base fare
  const segmentsZero: RoutingSegment[] = [
    { board_stop_id: 1, exit_stop_id: 2, trip_id: 1, route_id: 0, departure_time: 0, arrival_time: 100, is_transfer: false, transfer_distance_m: 0 }
  ];
  const fareZero = computeItineraryFare(segmentsZero, 'distance_fixture');
  assert.strictEqual(fareZero, 200, 'Base fare only when distance is 0');
});

test('Fare Calculation - Negative Case (Unsupported city returns 0)', () => {
  const segments: RoutingSegment[] = [
    { board_stop_id: 1, exit_stop_id: 2, trip_id: 1, route_id: 0, departure_time: 0, arrival_time: 100, is_transfer: false, transfer_distance_m: 0 }
  ];
  
  const fare = computeItineraryFare(segments, 'unknown_city');
  assert.strictEqual(fare, 0);

  // Negative case: empty segments yields 0
  const fareEmpty = computeItineraryFare([], 'nyc');
  assert.strictEqual(fareEmpty, 0, 'Empty segments yields 0');
});
