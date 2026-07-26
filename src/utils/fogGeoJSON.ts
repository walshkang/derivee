import { Feature, Polygon, MultiPolygon } from '@turf/helpers';
import bboxPolygon from '@turf/bbox-polygon';
import mask from '@turf/mask';
import destination from '@turf/destination';
import * as h3 from 'h3-js';

// 50km half-width (radius from center to edge of the bounding box)
const BBOX_HALF_WIDTH_KM = 25;

/**
 * Generates an inverted "Fog of War" GeoJSON polygon.
 * The fog is a 50x50km dark bounding box centered on the user,
 * with the user's unlocked H3 hexes punched out as transparent holes.
 *
 * @param latitude Current latitude
 * @param longitude Current longitude
 * @param unlockedHexes Array of 15-character H3 hex strings
 * @returns A GeoJSON Feature (Polygon or MultiPolygon) representing the fog layer
 */
export async function generateFogGeoJSON(
  latitude: number,
  longitude: number,
  unlockedHexes: string[]
): Promise<Feature<Polygon | MultiPolygon>> {
  return new Promise((resolve) => {
    // We wrap this in a Promise and setTimeout to allow the JS thread to yield
    // before running the CPU-intensive h3 and turf operations.
    setTimeout(() => {
      const center = [longitude, latitude];

      // 1. Calculate a ~50km x 50km bounding box around the center coordinate
      const ptNorth = destination(center, BBOX_HALF_WIDTH_KM, 0, { units: 'kilometers' });
      const ptEast = destination(center, BBOX_HALF_WIDTH_KM, 90, { units: 'kilometers' });
      const ptSouth = destination(center, BBOX_HALF_WIDTH_KM, 180, { units: 'kilometers' });
      const ptWest = destination(center, BBOX_HALF_WIDTH_KM, -90, { units: 'kilometers' });

      // bbox is [minX, minY, maxX, maxY] which corresponds to [westLng, southLat, eastLng, northLat]
      const minX = ptWest.geometry.coordinates[0];
      const minY = ptSouth.geometry.coordinates[1];
      const maxX = ptEast.geometry.coordinates[0];
      const maxY = ptNorth.geometry.coordinates[1];
      
      const fogBbox = bboxPolygon([minX, minY, maxX, maxY]);

      if (unlockedHexes.length === 0) {
        resolve(fogBbox);
        return;
      }

      // 2. Convert unlocked H3 hexes into a merged GeoJSON MultiPolygon coordinates array
      // h3.cellsToMultiPolygon(hexes, true) returns coordinates in [lng, lat] GeoJSON format.
      let holesCoordinates: number[][][][];
      try {
        holesCoordinates = h3.cellsToMultiPolygon(unlockedHexes, true);
      } catch (e) {
        console.error('Error generating multipolygon from hexes:', e);
        resolve(fogBbox); // Fallback to full fog
        return;
      }

      // 3. Create a GeoJSON Polygon for the holes to mask out
      // Turf mask requires a Polygon or MultiPolygon feature for the inner holes.
      // h3.cellsToMultiPolygon returns an Array<PolygonCoordinates>, where each PolygonCoordinates is Array<LinearRingCoordinates>.
      
      let maskResult: Feature<Polygon | MultiPolygon>;
      
      if (holesCoordinates.length > 0) {
         try {
           const holesFeature: Feature<MultiPolygon> = {
              type: 'Feature',
              properties: {},
              geometry: {
                type: 'MultiPolygon',
                coordinates: holesCoordinates,
              }
           };
           // 4. Subtract the holes from the bounding box
           maskResult = mask(holesFeature, fogBbox) as Feature<Polygon | MultiPolygon>;
         } catch (e) {
           console.error('Error masking fog polygon:', e);
           maskResult = fogBbox; // Fallback to full fog if mask fails
         }
      } else {
        maskResult = fogBbox;
      }
      
      resolve(maskResult);
    }, 0);
  });
}
