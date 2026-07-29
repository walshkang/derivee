import * as h3 from 'h3-js';
import type { Feature, Polygon } from 'geojson';
import destination from '@turf/destination';
import { point } from '@turf/helpers';

export function generateFogGeoJSON(
  centerLat: number,
  centerLng: number,
  unlockedHexes: string[]
): Feature<Polygon> {
  const center = point([centerLng, centerLat]);
  
  // Create a 50x50km bounding box (25km radius in each cardinal direction)
  const north = destination(center, 25, 0, { units: 'kilometers' }).geometry.coordinates;
  const east = destination(center, 25, 90, { units: 'kilometers' }).geometry.coordinates;
  const south = destination(center, 25, 180, { units: 'kilometers' }).geometry.coordinates;
  const west = destination(center, 25, -90, { units: 'kilometers' }).geometry.coordinates;

  const bboxRing = [
    [west[0], north[1]],
    [east[0], north[1]],
    [east[0], south[1]],
    [west[0], south[1]],
    [west[0], north[1]], // close ring
  ];

  const innerRings: number[][][] = [];

  if (unlockedHexes.length > 0) {
    try {
      const multiPolygons = h3.cellsToMultiPolygon(unlockedHexes, true);
      multiPolygons.forEach((polygonRings) => {
        innerRings.push(polygonRings[0]);
        for (let i = 1; i < polygonRings.length; i++) {
          innerRings.push(polygonRings[i]);
        }
      });
    } catch (e) {
      console.warn("Failed to generate multi-polygon for unlocked hexes", e);
    }
  }

  const geojson: Feature<Polygon> = {
    type: 'Feature',
    geometry: {
      type: 'Polygon',
      coordinates: [bboxRing, ...innerRings],
    },
    properties: {},
  };

  return geojson;
}
