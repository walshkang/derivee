export interface StopItem {
  id: number;
  name: string;
  lat: number;
  lon: number;
  gtfs_id?: string;
}

export interface RouteItem {
  shortName: string;
  color: string;
  textColor: string;
}

export interface RouteBadgeModel {
  label: string;
  backgroundColor: string;
  textColor: string;
  isFallback: boolean;
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

export type RoutingProfile = 'fastest' | 'fewest_transfers';

export const ROUTING_FLAG_NONE = 0;
export const ROUTING_FLAG_AVOID_TRANSFERS = 2; // 1 << 1

export interface RankedItinerary {
  id: string;
  profile: RoutingProfile;
  profiles: RoutingProfile[];
  segments: RoutingSegment[];
  departureTime: number;
  arrivalTime: number;
  durationSeconds: number;
  durationMinutes: number;
  transferCount: number;
  isDeduped: boolean;
}

export interface RoutePatternEntry {
  route_id: string;
  direction_id?: number;
  headsign?: string;
}

export type RoutingWorkerIncomingMessage =
  | { type: 'INIT'; city?: string }
  | {
      type: 'ROUTE';
      origin_stop_id: number;
      dest_stop_id: number;
      departure_timestamp: number;
      profile?: RoutingProfile;
      flags?: number;
      queryId?: string | number;
    };

export type RoutingWorkerOutgoingMessage =
  | { type: 'READY'; loadTimeMs: number; patterns?: RoutePatternEntry[] }
  | { type: 'ERROR'; message: string; queryId?: string | number }
  | {
      type: 'RESULT';
      segments: RoutingSegment[];
      totalFareCents?: number;
      profile?: RoutingProfile;
      flags?: number;
      queryId?: string | number;
    };

