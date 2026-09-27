export interface StopItem {
  id: number;
  name: string;
  lat: number;
  lon: number;
}

export interface RoutingSegment {
  board_stop_id: number;
  exit_stop_id: number;
  trip_id: number;
  departure_time: number;
  arrival_time: number;
  route_id: number;
  transfer_distance_m: number;
  is_transfer: boolean;
}

export type RoutingWorkerIncomingMessage =
  | { type: 'INIT'; city?: string }
  | {
      type: 'ROUTE';
      origin_stop_id: number;
      dest_stop_id: number;
      departure_timestamp: number;
    };

export type RoutingWorkerOutgoingMessage =
  | { type: 'READY'; loadTimeMs: number }
  | { type: 'ERROR'; message: string }
  | { type: 'RESULT'; segments: RoutingSegment[] };
