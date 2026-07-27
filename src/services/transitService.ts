import GtfsRealtimeBindings from 'gtfs-realtime-bindings';

// Configurable endpoint (for prototyping)
// e.g., MTA Subway feed, or a public mock feed
const GTFS_RT_URL = process.env.EXPO_PUBLIC_GTFS_RT_URL || 'https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/nyct%2Fgtfs';

export interface TransitArrival {
  routeId: string;
  arrivalTime: number; // Unix timestamp in seconds
  departureTime: number; // Unix timestamp in seconds
  stopId: string;
}

export interface TransitVehicle {
  routeId: string;
  latitude: number;
  longitude: number;
  bearing?: number;
}

export const transitService = {
  /**
   * Fetch and decode the GTFS-RT feed.
   */
  async fetchLiveFeed() {
    try {
      const response = await fetch(GTFS_RT_URL);
      if (!response.ok) {
        throw new Error(`Failed to fetch GTFS-RT feed: ${response.statusText}`);
      }
      
      const arrayBuffer = await response.arrayBuffer();
      const buffer = new Uint8Array(arrayBuffer);
      
      // Decode the binary protobuf payload
      const feed = GtfsRealtimeBindings.transit_realtime.FeedMessage.decode(buffer);
      
      const arrivals: TransitArrival[] = [];
      const vehicles: TransitVehicle[] = [];

      feed.entity.forEach((entity: any) => {
        if (entity.tripUpdate) {
          const routeId = entity.tripUpdate.trip.routeId;
          entity.tripUpdate.stopTimeUpdate.forEach((stopUpdate: any) => {
            if (stopUpdate.arrival && stopUpdate.arrival.time) {
              arrivals.push({
                routeId,
                stopId: stopUpdate.stopId,
                arrivalTime: typeof stopUpdate.arrival.time === 'object' ? stopUpdate.arrival.time.low : stopUpdate.arrival.time,
                departureTime: stopUpdate.departure?.time ? (typeof stopUpdate.departure.time === 'object' ? stopUpdate.departure.time.low : stopUpdate.departure.time) : (typeof stopUpdate.arrival.time === 'object' ? stopUpdate.arrival.time.low : stopUpdate.arrival.time),
              });
            }
          });
        }

        if (entity.vehicle && entity.vehicle.position) {
          vehicles.push({
            routeId: entity.vehicle.trip?.routeId || 'unknown',
            latitude: entity.vehicle.position.latitude,
            longitude: entity.vehicle.position.longitude,
            bearing: entity.vehicle.position.bearing,
          });
        }
      });

      return { arrivals, vehicles };
    } catch (error) {
      console.error('Error fetching/decoding GTFS-RT feed:', error);
      return { arrivals: [], vehicles: [] };
    }
  }
};
