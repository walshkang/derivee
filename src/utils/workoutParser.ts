import { XMLParser } from 'fast-xml-parser';
import { coordToH3 } from './h3Utils';
import FitParser from 'fit-file-parser';

export interface ParsedWorkout {
  hexes: string[];
  routeGeoJSON: string;
  distanceMeters: number;
  durationSeconds: number;
  startedAt: number;
}

// Haversine distance in meters
function haversineDistance(lat1: number, lon1: number, lat2: number, lon2: number): number {
  const R = 6371000; 
  const rlat1 = lat1 * (Math.PI / 180);
  const rlat2 = lat2 * (Math.PI / 180);
  const difflat = rlat2 - rlat1;
  const difflon = (lon2 - lon1) * (Math.PI / 180);

  return 2 * R * Math.asin(Math.sqrt(
    Math.sin(difflat/2)*Math.sin(difflat/2) +
    Math.cos(rlat1)*Math.cos(rlat2)*Math.sin(difflon/2)*Math.sin(difflon/2)
  ));
}

// Yields back to the main thread
const yieldThread = () => new Promise(resolve => setTimeout(resolve, 0));

export async function parseGPX(gpxString: string): Promise<ParsedWorkout> {
  const parser = new XMLParser({
    ignoreAttributes: false,
    attributeNamePrefix: '@_',
  });

  const parsed = parser.parse(gpxString);
  if (!parsed || !parsed.gpx) {
    throw new Error('Invalid GPX format: Missing root <gpx> element');
  }

  const hexes = new Set<string>();
  const routeCoords: number[][] = [];
  let totalDistance = 0;
  let lastLat: number | null = null;
  let lastLon: number | null = null;
  let startTime = Date.now();
  let endTime = startTime;

  let points: any[] = [];
  
  // Extract from Waypoints
  if (parsed.gpx.wpt) {
    points = points.concat(Array.isArray(parsed.gpx.wpt) ? parsed.gpx.wpt : [parsed.gpx.wpt]);
  }

  // Extract from Tracks
  if (parsed.gpx.trk) {
    const trks = Array.isArray(parsed.gpx.trk) ? parsed.gpx.trk : [parsed.gpx.trk];
    trks.forEach((trk: any) => {
      if (trk.trkseg) {
        const trksegs = Array.isArray(trk.trkseg) ? trk.trkseg : [trk.trkseg];
        trksegs.forEach((trkseg: any) => {
          if (trkseg.trkpt) {
            points = points.concat(Array.isArray(trkseg.trkpt) ? trkseg.trkpt : [trkseg.trkpt]);
          }
        });
      }
    });
  }

  // Process points in chunks
  const CHUNK_SIZE = 500;
  for (let i = 0; i < points.length; i++) {
    if (i % CHUNK_SIZE === 0) {
      await yieldThread();
    }

    const pt = points[i];
    const lat = parseFloat(pt['@_lat']);
    const lon = parseFloat(pt['@_lon']);
    
    if (isNaN(lat) || isNaN(lon)) continue;

    const ptTimeStr = pt.time;
    if (ptTimeStr) {
      const ts = new Date(ptTimeStr).getTime();
      if (i === 0 || ts < startTime) startTime = ts;
      if (ts > endTime) endTime = ts;
    }

    if (lastLat === null || lastLon === null) {
      hexes.add(coordToH3(lat, lon));
      routeCoords.push([lon, lat]);
      lastLat = lat;
      lastLon = lon;
    } else {
      const dist = haversineDistance(lastLat, lastLon, lat, lon);
      if (dist >= 10) { // Downsample > 10m
        totalDistance += dist;
        hexes.add(coordToH3(lat, lon));
        routeCoords.push([lon, lat]);
        lastLat = lat;
        lastLon = lon;
      }
    }
  }

  const routeGeoJSON = JSON.stringify({
    type: "Feature",
    properties: {},
    geometry: {
      type: "LineString",
      coordinates: routeCoords
    }
  });

  return {
    hexes: Array.from(hexes),
    routeGeoJSON,
    distanceMeters: Math.round(totalDistance),
    durationSeconds: Math.round((endTime - startTime) / 1000) || 0,
    startedAt: startTime,
  };
}

export async function parseFIT(buffer: ArrayBuffer): Promise<ParsedWorkout> {
  return new Promise((resolve, reject) => {
    const fitParser = new FitParser({
      force: true,
      speedUnit: 'km/h',
      lengthUnit: 'km',
      temperatureUnit: 'celsius',
      elapsedRecordField: true,
      mode: 'cascade',
    });

    fitParser.parse(buffer, async (error: any, data: any) => {
      if (error) {
        return reject(error);
      }

      try {
        const hexes = new Set<string>();
        const routeCoords: number[][] = [];
        let totalDistance = 0;
        let lastLat: number | null = null;
        let lastLon: number | null = null;
        let startTime = Date.now();
        let endTime = startTime;

        if (data.activity && data.activity.sessions && data.activity.sessions.length > 0) {
           startTime = new Date(data.activity.sessions[0].start_time).getTime() || startTime;
        }

        const records = data.activity?.sessions?.[0]?.laps?.flatMap((l: any) => l.records) || data.records || [];
        
        const CHUNK_SIZE = 500;
        for (let i = 0; i < records.length; i++) {
          if (i % CHUNK_SIZE === 0) {
            await yieldThread();
          }

          const record = records[i];
          const lat = record.position_lat;
          const lon = record.position_long;
          
          if (typeof lat !== 'number' || typeof lon !== 'number') continue;
          
          const ts = record.timestamp ? new Date(record.timestamp).getTime() : 0;
          if (ts > endTime) endTime = ts;

          if (lastLat === null || lastLon === null) {
            hexes.add(coordToH3(lat, lon));
            routeCoords.push([lon, lat]);
            lastLat = lat;
            lastLon = lon;
          } else {
            const dist = haversineDistance(lastLat, lastLon, lat, lon);
            if (dist >= 10) {
              totalDistance += dist;
              hexes.add(coordToH3(lat, lon));
              routeCoords.push([lon, lat]);
              lastLat = lat;
              lastLon = lon;
            }
          }
        }

        const routeGeoJSON = JSON.stringify({
          type: "Feature",
          properties: {},
          geometry: {
            type: "LineString",
            coordinates: routeCoords
          }
        });

        resolve({
          hexes: Array.from(hexes),
          routeGeoJSON,
          distanceMeters: Math.round(totalDistance),
          durationSeconds: Math.round((endTime - startTime) / 1000) || 0,
          startedAt: startTime,
        });
      } catch (err) {
        reject(err);
      }
    });
  });
}
