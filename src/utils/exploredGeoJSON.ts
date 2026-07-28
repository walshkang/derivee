import { cellToBoundary, cellsToMultiPolygon } from 'h3-js';
import type { Feature, MultiPolygon, Polygon } from 'geojson';

/**
 * Generates a GeoJSON MultiPolygon or Polygon of ONLY the unlocked hexes.
 * This is used for rendering illuminated areas in minimaps, rather than creating a fog mask.
 */
export function generateExploredHexesGeoJSON(hexes: string[]): Feature<Polygon | MultiPolygon> | null {
  if (!hexes || hexes.length === 0) {
    return null;
  }

  try {
    const multiPolygonCoords = cellsToMultiPolygon(hexes, true);
    if (!multiPolygonCoords || multiPolygonCoords.length === 0) {
      return null;
    }
    return {
      type: 'Feature',
      geometry: {
        type: 'MultiPolygon',
        coordinates: multiPolygonCoords,
      },
      properties: {},
    };
  } catch (error) {
    console.error('Failed to generate explored hexes GeoJSON:', error);
    return null;
  }
}
