const fs = require('fs');
const GtfsRealtimeBindings = require('gtfs-realtime-bindings');
const { transit_realtime } = GtfsRealtimeBindings;

async function test() {
  const geojson = JSON.parse(fs.readFileSync('public/subway-stops.geojson'));
  const stopsMap = new Map();
  geojson.features.forEach(f => {
    stopsMap.set(f.properties.stop_id, f.geometry.coordinates);
  });
  
  const res = await fetch('https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/nyct%2Fgtfs-l');
  const buffer = await res.arrayBuffer();
  const feed = transit_realtime.FeedMessage.decode(new Uint8Array(buffer));
  
  let vehicles = [];
  feed.entity.forEach(e => {
    if (e.tripUpdate && e.tripUpdate.stopTimeUpdate && e.tripUpdate.stopTimeUpdate.length > 0) {
      const nextStop = e.tripUpdate.stopTimeUpdate[0];
      const stopId = nextStop.stopId;
      // MTA stopIds in GTFS-RT often have 'N' or 'S' suffix for direction.
      const baseStopId = stopId.substring(0, 3);
      const coords = stopsMap.get(baseStopId) || stopsMap.get(stopId);
      if (coords) {
        vehicles.push({ stopId, coords });
      }
    }
  });
  console.log("Mapped vehicles:", vehicles.length);
}
test();
