import GtfsRealtimeBindings from 'gtfs-realtime-bindings';
const { transit_realtime } = GtfsRealtimeBindings;
import { MTA_SUBWAY_FEEDS, MTA_BUS_SIRI_STOP_MONITORING_URL, MTA_BUS_SIRI_VEHICLE_MONITORING_URL, ONE_BUS_AWAY_BASE_URL } from './transitConfig.js';

const MTA_API_KEY = import.meta.env.VITE_MTA_API_KEY || '';

let subwayStopsMap = null;
async function getSubwayStopsMap() {
  if (subwayStopsMap) return subwayStopsMap;
  try {
    const res = await fetch('/subway-stops.geojson');
    const data = await res.json();
    subwayStopsMap = new Map();
    data.features.forEach(f => {
      subwayStopsMap.set(f.properties.stop_id, f.geometry.coordinates);
    });
    return subwayStopsMap;
  } catch (e) {
    console.error('Failed to load subway stops geojson:', e);
    return new Map();
  }
}

export const transitService = {
  async fetchSubwayFeed(feedKey) {
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
      
      const feed = transit_realtime.FeedMessage.decode(buffer);
      
      const arrivals = [];
      const vehicles = [];
      const alerts = [];
      
      const stopsMap = await getSubwayStopsMap();

      feed.entity.forEach((entity) => {
        if (entity.tripUpdate) {
          const routeId = entity.tripUpdate.trip.routeId;
          const nyctTrip = entity.tripUpdate.trip.nyctTripDescriptor;
          
          let direction = undefined;
          let isAssigned = undefined;
          if (nyctTrip) {
            isAssigned = nyctTrip.isAssigned;
            switch(nyctTrip.direction) {
              case 1: direction = 'NORTH'; break;
              case 2: direction = 'EAST'; break;
              case 3: direction = 'SOUTH'; break;
              case 4: direction = 'WEST'; break;
            }
          }

          entity.tripUpdate.stopTimeUpdate.forEach((stopUpdate) => {
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
          
          // Generate a pseudo-vehicle at the station if it's the very next stop
          const nextStop = entity.tripUpdate.stopTimeUpdate[0];
          if (nextStop && nextStop.stopId) {
             const baseStopId = nextStop.stopId.substring(0, 3);
             const coords = stopsMap.get(baseStopId) || stopsMap.get(nextStop.stopId);
             if (coords) {
                vehicles.push({
                   routeId,
                   latitude: coords[1],
                   longitude: coords[0],
                   bearing: 0
                });
             }
          }
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
          
          const informedEntities = (alert.informedEntity || []).map((e) => e.stopId || e.routeId || e.trip?.routeId);
          
          let alertType = undefined;
          let summary = undefined;
          let directionality = undefined;
          let affectedStations = [];
          
          if (mercuryAlert) {
            alertType = mercuryAlert.alertType;
            summary = mercuryAlert.humanReadableActivePeriod?.translation?.[0]?.text;
            directionality = mercuryAlert.directionality;
            affectedStations = (mercuryAlert.affectedStations || []).map((s) => s.sortOrder);
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

  async fetchBusLive(routeId) {
    try {
      const url = `${MTA_BUS_SIRI_VEHICLE_MONITORING_URL}?key=${MTA_API_KEY}${routeId ? `&LineRef=${routeId}` : ''}`;
      const response = await fetch(url);
      if (!response.ok) throw new Error('SIRI API fetch failed');
      const data = await response.json();
      
      const arrivals = [];
      const vehicles = [];

      const deliveries = data?.Siri?.ServiceDelivery?.VehicleMonitoringDelivery || [];
      deliveries.forEach((delivery) => {
        const activities = delivery.VehicleActivity || [];
        activities.forEach((activity) => {
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
          onwardCalls.forEach((call) => {
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

  async fetchBusStopLive(stopId) {
    try {
      const url = `${MTA_BUS_SIRI_STOP_MONITORING_URL}?key=${MTA_API_KEY}&MonitoringRef=${stopId}`;
      const response = await fetch(url);
      if (!response.ok) throw new Error('SIRI Stop API fetch failed');
      const data = await response.json();
      
      const arrivals = [];
      const vehicles = [];

      const deliveries = data?.Siri?.ServiceDelivery?.StopMonitoringDelivery || [];
      deliveries.forEach((delivery) => {
        const visits = delivery.MonitoredStopVisit || [];
        visits.forEach((visit) => {
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

  async fetchBusStatic(routeId) {
    try {
      const url = `${ONE_BUS_AWAY_BASE_URL}/routes-for-location.json?key=${MTA_API_KEY}&lat=40.7128&lon=-74.0060`;
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
