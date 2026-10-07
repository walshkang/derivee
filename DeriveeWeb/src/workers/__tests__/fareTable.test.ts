import test from 'node:test';
import assert from 'node:assert';
import { computeItineraryFare } from '../fareTable.ts';
import type { RoutingSegment, RoutePatternEntry } from '../../types/routing.ts';

test('Fare Calculation - NYC NYC Subway -> Local Bus is $3.00 (One Fare)', () => {
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
});

test('Fare Calculation - NYC Subway -> SBS is $6.00 (Two Fares)', () => {
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
  assert.strictEqual(fare, 600); // Fails if free transfer is applied
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
});

test('Fare Calculation - Distance Formula Fixture', () => {
  const segments: RoutingSegment[] = [
    { board_stop_id: 1, exit_stop_id: 2, trip_id: 1, route_id: 0, departure_time: 0, arrival_time: 100, is_transfer: false, transfer_distance_m: 550 },
    { board_stop_id: 2, exit_stop_id: 3, trip_id: 2, route_id: 1, departure_time: 200, arrival_time: 300, is_transfer: false, transfer_distance_m: 1000 }
  ];
  
  const fare = computeItineraryFare(segments, 'distance_fixture');
  // 550m -> base 200 + 5*10 = 250
  // 1000m -> base 200 + 10*10 = 300
  // total 550
  assert.strictEqual(fare, 550);
});

test('Fare Calculation - Negative Case (Unsupported city returns 0)', () => {
  const segments: RoutingSegment[] = [
    { board_stop_id: 1, exit_stop_id: 2, trip_id: 1, route_id: 0, departure_time: 0, arrival_time: 100, is_transfer: false, transfer_distance_m: 0 }
  ];
  
  const fare = computeItineraryFare(segments, 'unknown_city');
  assert.strictEqual(fare, 0);
});
