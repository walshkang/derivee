import type { LineLayerSpecification, CircleLayerSpecification } from 'maplibre-gl';
import type { StopItem } from '../types/routing.ts';

export const TRANSIT_LINES_SOURCE_ID = 'transit-lines';
export const TRANSIT_LINES_CASING_LAYER_ID = 'transit-lines-casing';
export const TRANSIT_LINES_LAYER_ID = 'transit-lines-layer';
export const TRANSIT_STATIONS_SOURCE_ID = 'transit-stations';
export const TRANSIT_STATIONS_LAYER_ID = 'transit-stations-layer';

export const RIBBON_PAINT_LINE_COLOR = ['get', 'trunk_color_hex'] as const;

export const RIBBON_PAINT_LINE_OFFSET = [
  'interpolate',
  ['linear'],
  ['zoom'],
  9,
  ['*', ['coalesce', ['get', 'delta_offset'], 0], 1.2],
  11,
  ['*', ['coalesce', ['get', 'delta_offset'], 0], 1.0],
  14,
  ['*', ['coalesce', ['get', 'delta_offset'], 0], 0.5],
  16,
  0,
] as const;

export const RIBBON_PAINT_LINE_WIDTH = [
  'interpolate',
  ['linear'],
  ['zoom'],
  9,
  1.5,
  11,
  2.0,
  14,
  3.0,
  17,
  5.0,
] as const;

export const CASING_PAINT_LINE_WIDTH = [
  'interpolate',
  ['linear'],
  ['zoom'],
  9,
  2.7,
  11,
  3.4,
  14,
  4.6,
  17,
  7.0,
] as const;

export interface StationFeatureProperties {
  id: number;
  name: string;
}

export interface StationPointFeature {
  type: 'Feature';
  geometry: {
    type: 'Point';
    coordinates: [number, number]; // [lon, lat]
  };
  properties: StationFeatureProperties;
}

export interface StationGeoJSON {
  type: 'FeatureCollection';
  features: StationPointFeature[];
}

/**
 * Builds a GeoJSON FeatureCollection of Point features from stop items.
 * Deduplicates co-located platform stops (by lat/lon) into a single station bullet.
 */
export function buildStationGeoJSON(stops: StopItem[]): StationGeoJSON {
  const seen = new Set<string>();
  const features: StationPointFeature[] = [];

  if (Array.isArray(stops)) {
    for (const stop of stops) {
      if (
        !stop ||
        typeof stop.lat !== 'number' ||
        typeof stop.lon !== 'number' ||
        Number.isNaN(stop.lat) ||
        Number.isNaN(stop.lon)
      ) {
        continue;
      }

      // Round coordinate key slightly to collapse microscopic platform offsets if any
      const key = `${stop.lat.toFixed(6)},${stop.lon.toFixed(6)}`;
      if (seen.has(key)) {
        continue;
      }
      seen.add(key);

      features.push({
        type: 'Feature',
        geometry: {
          type: 'Point',
          coordinates: [stop.lon, stop.lat],
        },
        properties: {
          id: stop.id,
          name: typeof stop.name === 'string' ? stop.name : '',
        },
      });
    }
  }

  return {
    type: 'FeatureCollection',
    features,
  };
}

export function getTransitLinesCasingLayerConfig(): LineLayerSpecification {
  return {
    id: TRANSIT_LINES_CASING_LAYER_ID,
    type: 'line',
    source: TRANSIT_LINES_SOURCE_ID,
    filter: ['==', ['geometry-type'], 'LineString'],
    paint: {
      'line-color': '#FFFFFF',
      'line-width': CASING_PAINT_LINE_WIDTH as unknown as number,
      'line-offset': RIBBON_PAINT_LINE_OFFSET as unknown as number,
      'line-opacity': 0.9,
    },
  };
}

export function getTransitLinesLayerConfig(): LineLayerSpecification {
  return {
    id: TRANSIT_LINES_LAYER_ID,
    type: 'line',
    source: TRANSIT_LINES_SOURCE_ID,
    filter: ['==', ['geometry-type'], 'LineString'],
    paint: {
      'line-color': RIBBON_PAINT_LINE_COLOR as unknown as string,
      'line-width': RIBBON_PAINT_LINE_WIDTH as unknown as number,
      'line-offset': RIBBON_PAINT_LINE_OFFSET as unknown as number,
    },
  };
}

export function getTransitStationsLayerConfig(): CircleLayerSpecification {
  return {
    id: TRANSIT_STATIONS_LAYER_ID,
    type: 'circle',
    source: TRANSIT_STATIONS_SOURCE_ID,
    paint: {
      'circle-color': '#ffffff',
      'circle-stroke-color': '#000000',
      'circle-stroke-width': 2,
      'circle-radius': 4,
    },
  };
}

export function escapeHtml(str: string): string {
  return str
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#039;');
}
