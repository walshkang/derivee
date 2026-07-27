import { XMLParser } from 'fast-xml-parser';
import { coordToH3 } from './h3Utils';

/**
 * Parses a raw GPX XML string and extracts all track points (trkpt) and waypoints (wpt).
 * Converts their coordinates to H3 hex indices (resolution 11) and removes duplicates.
 * @param gpxString The raw GPX file content.
 * @returns Array of unique H3 hexadecimal strings.
 */
export function parseGPXToH3(gpxString: string): string[] {
  const parser = new XMLParser({
    ignoreAttributes: false,
    attributeNamePrefix: '@_',
  });

  const parsed = parser.parse(gpxString);
  const hexes = new Set<string>();

  if (!parsed || !parsed.gpx) {
    throw new Error('Invalid GPX format: Missing root <gpx> element');
  }

  // Extract from Waypoints (<wpt>)
  if (parsed.gpx.wpt) {
    const wpts = Array.isArray(parsed.gpx.wpt) ? parsed.gpx.wpt : [parsed.gpx.wpt];
    wpts.forEach((wpt: any) => {
      const lat = parseFloat(wpt['@_lat']);
      const lon = parseFloat(wpt['@_lon']);
      if (!isNaN(lat) && !isNaN(lon)) {
        hexes.add(coordToH3(lat, lon));
      }
    });
  }

  // Extract from Tracks (<trk> -> <trkseg> -> <trkpt>)
  if (parsed.gpx.trk) {
    const trks = Array.isArray(parsed.gpx.trk) ? parsed.gpx.trk : [parsed.gpx.trk];
    trks.forEach((trk: any) => {
      if (trk.trkseg) {
        const trksegs = Array.isArray(trk.trkseg) ? trk.trkseg : [trk.trkseg];
        trksegs.forEach((trkseg: any) => {
          if (trkseg.trkpt) {
            const trkpts = Array.isArray(trkseg.trkpt) ? trkseg.trkpt : [trkseg.trkpt];
            trkpts.forEach((pt: any) => {
              const lat = parseFloat(pt['@_lat']);
              const lon = parseFloat(pt['@_lon']);
              if (!isNaN(lat) && !isNaN(lon)) {
                hexes.add(coordToH3(lat, lon));
              }
            });
          }
        });
      }
    });
  }

  return Array.from(hexes);
}
