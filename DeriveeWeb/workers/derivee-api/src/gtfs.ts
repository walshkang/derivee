import { transit_realtime } from "./proto/gtfs-realtime.js";

const MTA_FEEDS = [
  "https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/nyct%2Fgtfs",
  "https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/nyct%2Fgtfs-ace",
  "https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/nyct%2Fgtfs-bdfm",
  "https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/nyct%2Fgtfs-g",
  "https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/nyct%2Fgtfs-jz",
  "https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/nyct%2Fgtfs-l",
  "https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/nyct%2Fgtfs-nqrw",
  "https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/nyct%2Fgtfs-si"
];

export interface ArrivalPrediction {
  route_id: string;
  direction: string;
  headsign: string;
  predicted_arrival_epoch: number;
  is_realtime: boolean;
}

export interface StopPredictions {
  stop_id: string;
  updated_at: number;
  arrivals: ArrivalPrediction[];
}

export async function fetchFeeds(kv: KVNamespace) {
  const updated_at = Math.floor(Date.now() / 1000);
  const stopArrivals = new Map<string, ArrivalPrediction[]>();

  const results = await Promise.allSettled(
    MTA_FEEDS.map(async (url) => {
      const controller = new AbortController();
      const id = setTimeout(() => controller.abort(), 20000);
      try {
        const response = await fetch(url, { signal: controller.signal });
        if (!response.ok) throw new Error(`Status ${response.status}`);
        const buffer = await response.arrayBuffer();
        const feed = transit_realtime.FeedMessage.decode(new Uint8Array(buffer));
        
        for (const entity of feed.entity) {
          if (entity.tripUpdate && entity.tripUpdate.stopTimeUpdate) {
            const trip = entity.tripUpdate.trip;
            const route_id = trip.routeId || "UNKNOWN";
            
            // NYCT extensions direction
            let nyctDirection = "UNKNOWN";
            const nyctDesc = trip[".transit_realtime.nyctTripDescriptor"];
            if (nyctDesc && nyctDesc.direction) {
              const dirEnum = nyctDesc.direction;
              nyctDirection = dirEnum === 1 ? "NORTH" : dirEnum === 2 ? "EAST" : dirEnum === 3 ? "SOUTH" : dirEnum === 4 ? "WEST" : "UNKNOWN";
            }

            for (const stopTime of entity.tripUpdate.stopTimeUpdate) {
              if (!stopTime.arrival || !stopTime.arrival.time) continue;
              
              const rawStopId = stopTime.stopId || "";
              const baseStopId = rawStopId.substring(0, 3);
              if (!baseStopId) continue;
              
              const suffix = rawStopId.length > 3 ? rawStopId.substring(3) : "";
              let direction = nyctDirection;
              if (direction === "UNKNOWN") {
                if (suffix === "N") direction = "NORTH";
                else if (suffix === "S") direction = "SOUTH";
              }
              
              const timeLow = typeof stopTime.arrival.time === 'object' ? stopTime.arrival.time.low : stopTime.arrival.time;
              // Skip past arrivals
              if (timeLow < updated_at - 60) continue;
              
              const prediction: ArrivalPrediction = {
                route_id,
                direction,
                headsign: "",
                predicted_arrival_epoch: timeLow,
                is_realtime: true
              };
              
              if (!stopArrivals.has(baseStopId)) {
                stopArrivals.set(baseStopId, []);
              }
              stopArrivals.get(baseStopId)!.push(prediction);
            }
          }
        }
      } finally {
        clearTimeout(id);
      }
    })
  );

  // Group by first character of stopId to minimize KV writes (max 22 writes per minute)
  const groupedStops = new Map<string, Record<string, StopPredictions>>();
  
  for (const [stopId, arrivals] of stopArrivals.entries()) {
    const firstChar = stopId.charAt(0).toUpperCase();
    if (!groupedStops.has(firstChar)) {
      groupedStops.set(firstChar, {});
    }
    // Sort arrivals by time
    arrivals.sort((a, b) => a.predicted_arrival_epoch - b.predicted_arrival_epoch);
    
    groupedStops.get(firstChar)![stopId] = {
      stop_id: stopId,
      updated_at,
      arrivals
    };
  }

  // Write to KV with 90s TTL
  const writePromises = [];
  for (const [firstChar, stopsMap] of groupedStops.entries()) {
    const key = `stops-${firstChar}`;
    writePromises.push(kv.put(key, JSON.stringify(stopsMap), { expirationTtl: 90 }));
  }
  
  await Promise.allSettled(writePromises);
}

export async function getArrivalsForStop(kv: KVNamespace, stopId: string): Promise<StopPredictions | null> {
  const firstChar = stopId.charAt(0).toUpperCase();
  const key = `stops-${firstChar}`;
  const data = await kv.get(key, 'json');
  if (!data) return null;
  const stopsMap = data as Record<string, StopPredictions>;
  return stopsMap[stopId] || null;
}
