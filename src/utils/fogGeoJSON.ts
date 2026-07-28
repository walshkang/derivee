import type { Feature, Polygon } from 'geojson';
import destination from '@turf/destination';
import * as h3 from 'h3-js';

// 50km half-width (radius from center to edge of the bounding box)
const BBOX_HALF_WIDTH_KM = 25;

/**
 * Generates an inverted "Fog of War" GeoJSON polygon.
 * The fog is a 50x50km dark bounding box centered on the user,
 * with the user's unlocked H3 hexes punched out as transparent holes.
 *
 * Rather than using @turf/mask (which performs expensive spatial boolean ops on JS thread),
 * this natively concatenates the 50x50km bounding box outer ring with all interior hex hole rings
 * into a single GeoJSON Polygon feature. MapLibre's native C++ earcut triangulator natively
 * cuts out all inner rings from the outer bounding box.
 *
 * @param latitude Current latitude
 * @param longitude Current longitude
 * @param unlockedHexes Array of 15-character H3 hex strings
 * @returns A GeoJSON Feature<Polygon> representing the fog layer
 */
export async function generateFogGeoJSON(
  latitude: number,
  longitude: number,
  unlockedHexes: string[]
): Promise<Feature<Polygon>> {
  return new Promise((resolve) => {
    // We wrap this in a Promise and setTimeout to allow the JS thread to yield
    // before running the CPU-intensive h3 operations.
    setTimeout(() => {
      const center = [longitude, latitude];

      // 1. Calculate a ~50km x 50km bounding box around the center coordinate
      const ptNorth = destination(center, BBOX_HALF_WIDTH_KM, 0, { units: 'kilometers' });
      const ptEast = destination(center, BBOX_HALF_WIDTH_KM, 90, { units: 'kilometers' });
      const ptSouth = destination(center, BBOX_HALF_WIDTH_KM, 180, { units: 'kilometers' });
      const ptWest = destination(center, BBOX_HALF_WIDTH_KM, -90, { units: 'kilometers' });

      // bbox coordinate boundaries: [westLng, southLat, eastLng, northLat]
      const minX = ptWest.geometry.coordinates[0];
      const minY = ptSouth.geometry.coordinates[1];
      const maxX = ptEast.geometry.coordinates[0];
      const maxY = ptNorth.geometry.coordinates[1];

      // Outer linear ring of the bounding box (closed loop: NW -> NE -> SE -> SW -> NW)
      const bboxRing: number[][] = [
        [minX, maxY],
        [maxX, maxY],
        [maxX, minY],
        [minX, minY],
        [minX, maxY],
      ];

      const makeBboxFeature = (): Feature<Polygon> => ({
        type: 'Feature',
        properties: {},
        geometry: {
          type: 'Polygon',
          coordinates: [bboxRing],
        },
      });

      if (!unlockedHexes || unlockedHexes.length === 0) {
        resolve(makeBboxFeature());
        return;
      }

      // 2. Convert unlocked H3 hexes into merged GeoJSON MultiPolygon linear rings
      // h3.cellsToMultiPolygon(hexes, true) returns coordinates in [lng, lat] GeoJSON format.
      // Output structure: Array<PolygonCoordinates> where each PolygonCoordinates is Array<LinearRingCoordinates>.
      let holesCoordinates: number[][][][];
      try {
        holesCoordinates = h3.cellsToMultiPolygon(unlockedHexes, true);
      } catch (e) {
        console.error('Error generating multipolygon from hexes:', e);
        resolve(makeBboxFeature());
        return;
      }

      // 3. Flatten linear rings across all polygon clusters into inner rings (holes)
      const innerRings: number[][][] = [];
      if (holesCoordinates && holesCoordinates.length > 0) {
        for (const polygon of holesCoordinates) {
          for (const ring of polygon) {
            if (ring && ring.length > 0) {
              innerRings.push(ring);
            }
          }
        }
      }

      // 4. Return single Polygon feature with bbox outer boundary [0] and hex hole inner rings [1..N]
      resolve({
        type: 'Feature',
        properties: {},
        geometry: {
          type: 'Polygon',
          coordinates: [bboxRing, ...innerRings],
        },
      });
    }, 0);
  });
}

