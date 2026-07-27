import { transit_realtime } from '../proto/gtfs.js';
import { MTA_SUBWAY_FEEDS, MTA_BUS_SIRI_STOP_MONITORING_URL, MTA_BUS_SIRI_VEHICLE_MONITORING_URL, ONE_BUS_AWAY_BASE_URL } from '../constants/transitConfig';

const MTA_API_KEY = process.env.EXPO_PUBLIC_MTA_API_KEY || '';

export interface TransitArrival {
  routeId: string;
  arrivalTime: number;
  departureTime: number;
  stopId: string;
  actualTrack?: string;
  scheduledTrack?: string;
  direction?: 'NORTH' | 'SOUTH' | 'EAST' | 'WEST';
  isAssigned?: boolean;
}

export interface TransitVehicle {
  routeId: string;
  latitude: number;
  longitude: number;
  bearing?: number;
}

export interface TransitAlert {
  alertType?: string;
  summary?: string;
  informedEntities: string[];
  affectedStations: string[];
  sortOrder?: string;
  directionality?: number;
}

export const transitService = {
  /**
   * Fetch and decode a specific GTFS-RT subway feed.
   */
  async fetchSubwayFeed(feedKey: keyof typeof MTA_SUBWAY_FEEDS) {
    const url = MTA_SUBWAY_FEEDS[feedKey];
    if (!url) throw new Error(`Invalid feed key: ${feedKey}`);

    try {
      const response = await fetch(url, {
        headers: {
          'x-api-key': MTA_API_KEY,
        },
      });
      if (!response.ok) {
        throw new Error(`Failed to fetch GTFS-RT feed: ${response.statusText}`);
      }
      
      const arrayBuffer = await response.arrayBuffer();
      const buffer = new Uint8Array(arrayBuffer);
      
      // Decode the binary protobuf payload
      const feed = transit_realtime.FeedMessage.decode(buffer);
      
      const arrivals: TransitArrival[] = [];
      const vehicles: TransitVehicle[] = [];
      const alerts: TransitAlert[] = [];

      feed.entity.forEach((entity: any) => {
        if (entity.tripUpdate) {
          const routeId = entity.tripUpdate.trip.routeId;
          const nyctTrip = entity.tripUpdate.trip.nyctTripDescriptor;
          
          let direction: 'NORTH' | 'EAST' | 'SOUTH' | 'WEST' | undefined = undefined;
          let isAssigned: boolean | undefined = undefined;
          if (nyctTrip) {
            isAssigned = nyctTrip.isAssigned;
            switch(nyctTrip.direction) {
              case 1: direction = 'NORTH'; break;
              case 2: direction = 'EAST'; break;
              case 3: direction = 'SOUTH'; break;
              case 4: direction = 'WEST'; break;
            }
          }

          entity.tripUpdate.stopTimeUpdate.forEach((stopUpdate: any) => {
            if (stopUpdate.arrival && stopUpdate.arrival.time) {
              const nyctStop = stopUpdate.nyctStopTimeUpdate;
              
              arrivals.push({
                routeId,
                stopId: stopUpdate.stopId,
                arrivalTime: typeof stopUpdate.arrival.time === 'object' ? stopUpdate.arrival.time.low : stopUpdate.arrival.time,
                departureTime: stopUpdate.departure?.time ? (typeof stopUpdate.departure.time === 'object' ? stopUpdate.departure.time.low : stopUpdate.departure.time) : (typeof stopUpdate.arrival.time === 'object' ? stopUpdate.arrival.time.low : stopUpdate.arrival.time),
                actualTrack: nyctStop?.actualTrack,
                scheduledTrack: nyctStop?.scheduledTrack,
                direction,
                isAssigned
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
        
        if (entity.alert) {
          const alert = entity.alert;
          const mercuryAlert = alert.mercuryAlert;
          
          const informedEntities = (alert.informedEntity || []).map((e: any) => e.stopId || e.routeId || e.trip?.routeId);
          
          let alertType = undefined;
          let summary = undefined;
          let directionality = undefined;
          let affectedStations: string[] = [];
          
          if (mercuryAlert) {
            alertType = mercuryAlert.alertType;
            summary = mercuryAlert.humanReadableActivePeriod?.translation?.[0]?.text;
            directionality = mercuryAlert.directionality;
            affectedStations = (mercuryAlert.affectedStations || []).map((s: any) => s.sortOrder);
          }
          
          alerts.push({
            alertType,
            summary,
            informedEntities: informedEntities.filter(Boolean),
            affectedStations: affectedStations.filter(Boolean),
            directionality,
          });
        }
      });

      return { arrivals, vehicles, alerts };
    } catch (error) {
      console.error('Error fetching/decoding GTFS-RT feed:', error);
      return { arrivals: [], vehicles: [], alerts: [] };
    }
  },

  /**
   * Fetch MTA SIRI API (JSON) for bus tracking (Vehicle Monitoring)
   */
  async fetchBusLive(routeId: string) {
    try {
      const url = `${MTA_BUS_SIRI_VEHICLE_MONITORING_URL}?key=${MTA_API_KEY}&LineRef=${routeId}`;
      const response = await fetch(url);
      if (!response.ok) throw new Error('SIRI API fetch failed');
      const data = await response.json();
      
      const arrivals: TransitArrival[] = [];
      const vehicles: TransitVehicle[] = [];

      const deliveries = data?.Siri?.ServiceDelivery?.VehicleMonitoringDelivery || [];
      deliveries.forEach((delivery: any) => {
        const activities = delivery.VehicleActivity || [];
        activities.forEach((activity: any) => {
          const journey = activity.MonitoredVehicleJourney;
          if (!journey) return;

          if (journey.VehicleLocation) {
            vehicles.push({
              routeId: journey.LineRef,
              latitude: journey.VehicleLocation.Latitude,
              longitude: journey.VehicleLocation.Longitude,
              bearing: journey.Bearing,
            });
          }

          if (journey.MonitoredCall) {
            const call = journey.MonitoredCall;
            const expectedTime = call.ExpectedArrivalTime || call.AimedArrivalTime;
            if (expectedTime) {
              const timeSeconds = Math.floor(new Date(expectedTime).getTime() / 1000);
              arrivals.push({
                routeId: journey.LineRef,
                stopId: call.StopPointRef,
                arrivalTime: timeSeconds,
                departureTime: timeSeconds,
              });
            }
          }
          
          const onwardCalls = journey.OnwardCalls?.OnwardCall || [];
          onwardCalls.forEach((call: any) => {
             const expectedTime = call.ExpectedArrivalTime || call.AimedArrivalTime;
             if (expectedTime) {
               const timeSeconds = Math.floor(new Date(expectedTime).getTime() / 1000);
               arrivals.push({
                 routeId: journey.LineRef,
                 stopId: call.StopPointRef,
                 arrivalTime: timeSeconds,
                 departureTime: timeSeconds,
               });
             }
          });
        });
      });

      return { arrivals, vehicles };
    } catch (error) {
      console.error('Error fetching SIRI API:', error);
      return { arrivals: [], vehicles: [] };
    }
  },

  /**
   * Fetch MTA SIRI API (JSON) for a specific stop (Stop Monitoring)
   */
  async fetchBusStopLive(stopId: string) {
    try {
      const url = `${MTA_BUS_SIRI_STOP_MONITORING_URL}?key=${MTA_API_KEY}&MonitoringRef=${stopId}`;
      const response = await fetch(url);
      if (!response.ok) throw new Error('SIRI Stop API fetch failed');
      const data = await response.json();
      
      const arrivals: TransitArrival[] = [];
      const vehicles: TransitVehicle[] = [];

      const deliveries = data?.Siri?.ServiceDelivery?.StopMonitoringDelivery || [];
      deliveries.forEach((delivery: any) => {
        const visits = delivery.MonitoredStopVisit || [];
        visits.forEach((visit: any) => {
          const journey = visit.MonitoredVehicleJourney;
          if (!journey) return;

          if (journey.VehicleLocation) {
            vehicles.push({
              routeId: journey.LineRef,
              latitude: journey.VehicleLocation.Latitude,
              longitude: journey.VehicleLocation.Longitude,
              bearing: journey.Bearing,
            });
          }

          if (journey.MonitoredCall) {
            const call = journey.MonitoredCall;
            const expectedTime = call.ExpectedArrivalTime || call.AimedArrivalTime;
            if (expectedTime) {
              const timeSeconds = Math.floor(new Date(expectedTime).getTime() / 1000);
              arrivals.push({
                routeId: journey.LineRef,
                stopId: call.StopPointRef,
                arrivalTime: timeSeconds,
                departureTime: timeSeconds,
              });
            }
          }
        });
      });

      return { arrivals, vehicles };
    } catch (error) {
      console.error('Error fetching SIRI Stop API:', error);
      return { arrivals: [], vehicles: [] };
    }
  },

  /**
   * Fetch OneBusAway REST API (JSON) for bus discovery/static data
   */
  async fetchBusStatic(routeId: string) {
    try {
      const url = `${ONE_BUS_AWAY_BASE_URL}/routes-for-location.json?key=${MTA_API_KEY}&lat=40.7128&lon=-74.0060`; // Example implementation
      const response = await fetch(url);
      if (!response.ok) throw new Error('OneBusAway API fetch failed');
      const data = await response.json();
      return data;
    } catch (error) {
      console.error('Error fetching OneBusAway API:', error);
      return null;
    }
  }
};
