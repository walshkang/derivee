import type { LineLayerSpecification, CircleLayerSpecification } from 'maplibre-gl';
import type { StopItem } from '../types/routing.ts';

export const TRANSIT_LINES_SOURCE_ID = 'transit-lines';
export const TRANSIT_LINES_CASING_LAYER_ID = 'transit-lines-casing';
export const TRANSIT_LINES_LAYER_ID = 'transit-lines-layer';
export const TRANSIT_STATIONS_SOURCE_ID = 'transit-stations';
export const TRANSIT_STATIONS_LAYER_ID = 'transit-stations-layer';
export const TRANSIT_HIGHLIGHTED_SECTION_SOURCE_ID = 'transit-highlighted-section';
export const TRANSIT_HIGHLIGHTED_SECTION_CASING_LAYER_ID = 'transit-highlighted-section-casing';
export const TRANSIT_HIGHLIGHTED_SECTION_LAYER_ID = 'transit-highlighted-section-layer';

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

export interface RouteHighlightPaintProperties {
  lines: {
    'line-opacity': any;
    'line-width'?: any;
  };
  casing: {
    'line-opacity': any;
    'line-width'?: any;
  };
  stations: {
    'circle-opacity': number;
    'circle-stroke-opacity': number;
  };
}

/**
 * Returns paint properties for highlighting an active route on the vector transit overlay,
 * while dimming all non-matching routes.
 * Passing null/empty routeId restores full overlay opacity and widths.
 */
export function getRouteHighlightPaintProperties(routeId: string | null | undefined): RouteHighlightPaintProperties {
  const trimmed = routeId?.trim();
  if (!trimmed) {
    return {
      lines: {
        'line-opacity': 1.0,
        'line-width': RIBBON_PAINT_LINE_WIDTH,
      },
      casing: {
        'line-opacity': 0.9,
        'line-width': CASING_PAINT_LINE_WIDTH,
      },
      stations: {
        'circle-opacity': 1.0,
        'circle-stroke-opacity': 1.0,
      },
    };
  }

  const isMatchingRoute = [
    'case',
    [
      'any',
      ['==', ['get', 'route_id'], trimmed],
      ['in', trimmed, ['coalesce', ['get', 'routes'], ['literal', []]]],
    ],
    1.0,
    0.15,
  ];

  const isMatchingCasing = [
    'case',
    [
      'any',
      ['==', ['get', 'route_id'], trimmed],
      ['in', trimmed, ['coalesce', ['get', 'routes'], ['literal', []]]],
    ],
    0.95,
    0.05,
  ];

  const highlightedLineWidth = [
    'case',
    [
      'any',
      ['==', ['get', 'route_id'], trimmed],
      ['in', trimmed, ['coalesce', ['get', 'routes'], ['literal', []]]],
    ],
    ['*', RIBBON_PAINT_LINE_WIDTH, 1.4],
    ['*', RIBBON_PAINT_LINE_WIDTH, 0.8],
  ];

  const highlightedCasingWidth = [
    'case',
    [
      'any',
      ['==', ['get', 'route_id'], trimmed],
      ['in', trimmed, ['coalesce', ['get', 'routes'], ['literal', []]]],
    ],
    ['*', CASING_PAINT_LINE_WIDTH, 1.4],
    CASING_PAINT_LINE_WIDTH,
  ];

  return {
    lines: {
      'line-opacity': isMatchingRoute,
      'line-width': highlightedLineWidth,
    },
    casing: {
      'line-opacity': isMatchingCasing,
      'line-width': highlightedCasingWidth,
    },
    stations: {
      'circle-opacity': 0.25,
      'circle-stroke-opacity': 0.25,
    },
  };
}

/**
 * Returns default paint properties for the transit overlay with full opacity and standard line widths.
 */
export function getDefaultTransitPaintProperties(): RouteHighlightPaintProperties {
  return getRouteHighlightPaintProperties(null);
}

/**
 * Computes paint properties for journey map highlighting.
 * Renders the full journey's legs in muted/dimmed line colors,
 * with non-journey lines heavily dimmed.
 */
export function getJourneyHighlightPaintProperties(
  journeyRouteIds: string[],
  focusedRouteId?: string | null,
  isClipped: boolean = true
) {
  const cleanJourney = (journeyRouteIds || [])
    .map((r) => r.trim().toUpperCase())
    .filter(Boolean);
  const cleanFocused = focusedRouteId?.trim().toUpperCase() || null;

  if (cleanJourney.length === 0 && !cleanFocused) {
    return getDefaultTransitPaintProperties();
  }

  const isJourneyLeg = [
    'any',
    ...cleanJourney.map((r) => ['==', ['get', 'route_id'], r]),
    ...cleanJourney.map((r) => [
      'in',
      r,
      ['coalesce', ['get', 'routes'], ['literal', []]],
    ]),
  ];

  let lineOpacity: any;
  let casingOpacity: any;
  let lineWidth: any;
  let casingWidth: any;

  if (!isClipped && cleanFocused) {
    // Fallback: whole line highlight for focusedRouteId, dimmed for other journey legs
    const isFocused = [
      'any',
      ['==', ['get', 'route_id'], cleanFocused],
      ['in', cleanFocused, ['coalesce', ['get', 'routes'], ['literal', []]]],
    ];

    lineOpacity = [
      'case',
      isFocused,
      1.0,
      isJourneyLeg,
      0.45,
      0.08,
    ];

    casingOpacity = [
      'case',
      isFocused,
      0.95,
      isJourneyLeg,
      0.3,
      0.03,
    ];

    lineWidth = [
      'case',
      isFocused,
      ['*', RIBBON_PAINT_LINE_WIDTH, 1.4],
      isJourneyLeg,
      RIBBON_PAINT_LINE_WIDTH,
      ['*', RIBBON_PAINT_LINE_WIDTH, 0.7],
    ];

    casingWidth = [
      'case',
      isFocused,
      ['*', CASING_PAINT_LINE_WIDTH, 1.4],
      isJourneyLeg,
      CASING_PAINT_LINE_WIDTH,
      ['*', CASING_PAINT_LINE_WIDTH, 0.7],
    ];
  } else {
    // Clipped section is rendered on top in its own layer.
    // Underlying journey legs rendered dimmed; non-journey legs heavily dimmed.
    lineOpacity = [
      'case',
      isJourneyLeg,
      0.45,
      0.08,
    ];

    casingOpacity = [
      'case',
      isJourneyLeg,
      0.3,
      0.03,
    ];

    lineWidth = [
      'case',
      isJourneyLeg,
      RIBBON_PAINT_LINE_WIDTH,
      ['*', RIBBON_PAINT_LINE_WIDTH, 0.7],
    ];

    casingWidth = [
      'case',
      isJourneyLeg,
      CASING_PAINT_LINE_WIDTH,
      ['*', CASING_PAINT_LINE_WIDTH, 0.7],
    ];
  }

  return {
    lines: {
      'line-opacity': lineOpacity,
      'line-width': lineWidth,
    },
    casing: {
      'line-opacity': casingOpacity,
      'line-width': casingWidth,
    },
    stations: {
      'circle-opacity': 0.25,
      'circle-stroke-opacity': 0.25,
    },
  };
}

/**
 * Clips the route shape geometry to the board/alight stop range.
 * Uses graph search along candidate corridor LineStrings from transit-lines.geojson.
 *
 * Invariants:
 * - If shape data is missing or discontinuous, returns null (clean fallback).
 * - Never throws/crashes on malformed or null inputs.
 */
export function clipRouteShapeToStops(
  linesGeojson: any,
  routeId: string | null | undefined,
  boardCoords: [number, number] | null | undefined,
  alightCoords: [number, number] | null | undefined
): [number, number][] | null {
  if (
    !linesGeojson ||
    !Array.isArray(linesGeojson.features) ||
    !routeId ||
    !boardCoords ||
    !alightCoords ||
    boardCoords.length < 2 ||
    alightCoords.length < 2
  ) {
    return null;
  }

  const cleanRoute = String(routeId).trim().toUpperCase();
  if (!cleanRoute) return null;

  const features = linesGeojson.features.filter((f: any) => {
    if (!f || !f.properties || !f.geometry) return false;
    if (f.properties.feature_type === 'platform_capsule') return false;
    const rId = String(f.properties.route_id || '').trim().toUpperCase();
    const routes = Array.isArray(f.properties.routes)
      ? f.properties.routes.map((r: any) => String(r).trim().toUpperCase())
      : [];
    return rId === cleanRoute || routes.includes(cleanRoute);
  });

  if (features.length === 0) return null;

  const keyOf = (c: [number, number]) =>
    `${Math.round(c[0] * 100000)},${Math.round(c[1] * 100000)}`;

  const coordsMap = new Map<string, [number, number]>();
  const adj = new Map<string, Array<{ to: string; weight: number }>>();

  for (const f of features) {
    const coords = f.geometry.coordinates;
    if (!Array.isArray(coords)) continue;
    for (let i = 0; i < coords.length - 1; i++) {
      const p1 = coords[i] as [number, number];
      const p2 = coords[i + 1] as [number, number];
      if (!Array.isArray(p1) || !Array.isArray(p2)) continue;

      const u = keyOf(p1);
      const v = keyOf(p2);
      coordsMap.set(u, p1);
      coordsMap.set(v, p2);

      const dx = p1[0] - p2[0];
      const dy = p1[1] - p2[1];
      const dist = Math.hypot(dx, dy);

      let uEdges = adj.get(u);
      if (!uEdges) {
        uEdges = [];
        adj.set(u, uEdges);
      }
      uEdges.push({ to: v, weight: dist });

      let vEdges = adj.get(v);
      if (!vEdges) {
        vEdges = [];
        adj.set(v, vEdges);
      }
      vEdges.push({ to: u, weight: dist });
    }
  }

  function findClosest(pt: [number, number]): { key: string | null; dist: number } {
    let bestKey: string | null = null;
    let minDist = Infinity;
    for (const [key, coord] of coordsMap.entries()) {
      const d = Math.hypot(pt[0] - coord[0], pt[1] - coord[1]);
      if (d < minDist) {
        minDist = d;
        bestKey = key;
      }
    }
    return { key: bestKey, dist: minDist };
  }

  const start = findClosest(boardCoords);
  const end = findClosest(alightCoords);

  // If snapping failed or distance is > 0.02 deg (~2.2km) or start === end, cannot clip reliably
  if (!start.key || !end.key || start.key === end.key) return null;
  if (start.dist > 0.02 || end.dist > 0.02) return null;

  // Dijkstra
  const distMap = new Map<string, number>();
  const prevMap = new Map<string, string>();
  const pq: Array<{ key: string; dist: number }> = [{ key: start.key, dist: 0 }];
  distMap.set(start.key, 0);

  while (pq.length > 0) {
    pq.sort((a, b) => a.dist - b.dist);
    const curr = pq.shift()!;
    if (curr.key === end.key) break;
    if (curr.dist > (distMap.get(curr.key) ?? Infinity)) continue;

    const neighbors = adj.get(curr.key) || [];
    for (const edge of neighbors) {
      const newD = curr.dist + edge.weight;
      if (newD < (distMap.get(edge.to) ?? Infinity)) {
        distMap.set(edge.to, newD);
        prevMap.set(edge.to, curr.key);
        pq.push({ key: edge.to, dist: newD });
      }
    }
  }

  if (!prevMap.has(end.key)) return null;

  const path: [number, number][] = [];
  let cur: string | undefined = end.key;
  while (cur) {
    const c = coordsMap.get(cur);
    if (c) path.push(c);
    cur = prevMap.get(cur);
  }
  path.reverse();

  return path.length >= 2 ? path : null;
}

export interface RouteHighlightOptions {
  journeyRouteIds?: string[];
  clippedCoordinates?: [number, number][] | null;
  routeColor?: string;
  casingColor?: string;
}

/**
 * Highlights a route's physical geometry or clipped section on the MapLibre map,
 * with journey legs rendered in muted/dimmed colors.
 * Sets data-highlighted-route and related attributes on map container for DOM inspection/harness assertions.
 */
export function highlightRouteOnMap(
  map: any,
  routeId: string | null | undefined,
  options?: RouteHighlightOptions
): void {
  if (!map) return;

  const trimmed = routeId?.trim();

  try {
    if (!trimmed) {
      // 1. Remove highlighted section layers/source if present
      if (typeof map.getLayer === 'function') {
        if (map.getLayer(TRANSIT_HIGHLIGHTED_SECTION_LAYER_ID)) {
          map.removeLayer(TRANSIT_HIGHLIGHTED_SECTION_LAYER_ID);
        }
        if (map.getLayer(TRANSIT_HIGHLIGHTED_SECTION_CASING_LAYER_ID)) {
          map.removeLayer(TRANSIT_HIGHLIGHTED_SECTION_CASING_LAYER_ID);
        }
      }
      if (
        typeof map.getSource === 'function' &&
        map.getSource(TRANSIT_HIGHLIGHTED_SECTION_SOURCE_ID)
      ) {
        map.removeSource(TRANSIT_HIGHLIGHTED_SECTION_SOURCE_ID);
      }

      // 2. Restore normal overlays
      const normalProps = getDefaultTransitPaintProperties();
      if (
        typeof map.getLayer === 'function' &&
        map.getLayer(TRANSIT_LINES_LAYER_ID)
      ) {
        map.setPaintProperty(
          TRANSIT_LINES_LAYER_ID,
          'line-opacity',
          normalProps.lines['line-opacity']
        );
        map.setPaintProperty(
          TRANSIT_LINES_LAYER_ID,
          'line-width',
          normalProps.lines['line-width']
        );
      }
      if (
        typeof map.getLayer === 'function' &&
        map.getLayer(TRANSIT_LINES_CASING_LAYER_ID)
      ) {
        map.setPaintProperty(
          TRANSIT_LINES_CASING_LAYER_ID,
          'line-opacity',
          normalProps.casing['line-opacity']
        );
        map.setPaintProperty(
          TRANSIT_LINES_CASING_LAYER_ID,
          'line-width',
          normalProps.casing['line-width']
        );
      }
      if (
        typeof map.getLayer === 'function' &&
        map.getLayer(TRANSIT_STATIONS_LAYER_ID)
      ) {
        map.setPaintProperty(
          TRANSIT_STATIONS_LAYER_ID,
          'circle-opacity',
          normalProps.stations['circle-opacity']
        );
        map.setPaintProperty(
          TRANSIT_STATIONS_LAYER_ID,
          'circle-stroke-opacity',
          normalProps.stations['circle-stroke-opacity']
        );
      }

      // 3. Clear container attributes
      if (typeof map.getContainer === 'function') {
        const container = map.getContainer();
        if (container && typeof container.removeAttribute === 'function') {
          container.removeAttribute('data-highlighted-route');
          container.removeAttribute('data-journey-routes');
          container.removeAttribute('data-highlighted-section');
          container.removeAttribute('data-journey-dimmed');
        }
      }
      return;
    }

    // Highlighting is active for trimmed route
    const journeyRoutes =
      options?.journeyRouteIds && options.journeyRouteIds.length > 0
        ? options.journeyRouteIds
        : [trimmed];
    const clippedCoords = options?.clippedCoordinates;
    const isClipped = Boolean(clippedCoords && clippedCoords.length >= 2);

    const props = getJourneyHighlightPaintProperties(
      journeyRoutes,
      trimmed,
      isClipped
    );

    if (
      typeof map.getLayer === 'function' &&
      map.getLayer(TRANSIT_LINES_LAYER_ID)
    ) {
      map.setPaintProperty(
        TRANSIT_LINES_LAYER_ID,
        'line-opacity',
        props.lines['line-opacity']
      );
      if (props.lines['line-width']) {
        map.setPaintProperty(
          TRANSIT_LINES_LAYER_ID,
          'line-width',
          props.lines['line-width']
        );
      }
    }

    if (
      typeof map.getLayer === 'function' &&
      map.getLayer(TRANSIT_LINES_CASING_LAYER_ID)
    ) {
      map.setPaintProperty(
        TRANSIT_LINES_CASING_LAYER_ID,
        'line-opacity',
        props.casing['line-opacity']
      );
      if (props.casing['line-width']) {
        map.setPaintProperty(
          TRANSIT_LINES_CASING_LAYER_ID,
          'line-width',
          props.casing['line-width']
        );
      }
    }

    if (
      typeof map.getLayer === 'function' &&
      map.getLayer(TRANSIT_STATIONS_LAYER_ID)
    ) {
      map.setPaintProperty(
        TRANSIT_STATIONS_LAYER_ID,
        'circle-opacity',
        props.stations['circle-opacity']
      );
      map.setPaintProperty(
        TRANSIT_STATIONS_LAYER_ID,
        'circle-stroke-opacity',
        props.stations['circle-stroke-opacity']
      );
    }

    // If clipped section coordinates available: render highlighted section layer on top!
    if (isClipped && clippedCoords) {
      const geojsonData = {
        type: 'Feature' as const,
        properties: {
          route_id: trimmed,
          color: options?.routeColor || '#38bdf8',
        },
        geometry: {
          type: 'LineString' as const,
          coordinates: clippedCoords,
        },
      };

      if (typeof map.getSource === 'function') {
        const existingSource = map.getSource(
          TRANSIT_HIGHLIGHTED_SECTION_SOURCE_ID
        );
        if (existingSource && typeof existingSource.setData === 'function') {
          existingSource.setData(geojsonData);
        } else if (!existingSource && typeof map.addSource === 'function') {
          map.addSource(TRANSIT_HIGHLIGHTED_SECTION_SOURCE_ID, {
            type: 'geojson',
            data: geojsonData,
          });
        }
      }

      if (
        typeof map.getLayer === 'function' &&
        typeof map.addLayer === 'function'
      ) {
        if (!map.getLayer(TRANSIT_HIGHLIGHTED_SECTION_CASING_LAYER_ID)) {
          map.addLayer({
            id: TRANSIT_HIGHLIGHTED_SECTION_CASING_LAYER_ID,
            type: 'line',
            source: TRANSIT_HIGHLIGHTED_SECTION_SOURCE_ID,
            paint: {
              'line-color': options?.casingColor || '#FFFFFF',
              'line-width': [
                'interpolate',
                ['linear'],
                ['zoom'],
                9,
                3.5,
                11,
                5.0,
                14,
                7.5,
                17,
                11.0,
              ],
              'line-opacity': 1.0,
            },
          });
        }
        if (!map.getLayer(TRANSIT_HIGHLIGHTED_SECTION_LAYER_ID)) {
          map.addLayer({
            id: TRANSIT_HIGHLIGHTED_SECTION_LAYER_ID,
            type: 'line',
            source: TRANSIT_HIGHLIGHTED_SECTION_SOURCE_ID,
            paint: {
              'line-color': options?.routeColor || '#38bdf8',
              'line-width': [
                'interpolate',
                ['linear'],
                ['zoom'],
                9,
                2.2,
                11,
                3.5,
                14,
                5.5,
                17,
                8.5,
              ],
              'line-opacity': 1.0,
            },
          });
        }
      }
    } else {
      // Fallback: remove section layers if they existed previously
      if (typeof map.getLayer === 'function') {
        if (map.getLayer(TRANSIT_HIGHLIGHTED_SECTION_LAYER_ID)) {
          map.removeLayer(TRANSIT_HIGHLIGHTED_SECTION_LAYER_ID);
        }
        if (map.getLayer(TRANSIT_HIGHLIGHTED_SECTION_CASING_LAYER_ID)) {
          map.removeLayer(TRANSIT_HIGHLIGHTED_SECTION_CASING_LAYER_ID);
        }
      }
      if (
        typeof map.getSource === 'function' &&
        map.getSource(TRANSIT_HIGHLIGHTED_SECTION_SOURCE_ID)
      ) {
        map.removeSource(TRANSIT_HIGHLIGHTED_SECTION_SOURCE_ID);
      }
    }

    // Set DOM attributes for testability/harness assertions
    if (typeof map.getContainer === 'function') {
      const container = map.getContainer();
      if (container && typeof container.setAttribute === 'function') {
        container.setAttribute('data-highlighted-route', trimmed);
        container.setAttribute(
          'data-journey-routes',
          journeyRoutes.join(',')
        );
        container.setAttribute(
          'data-highlighted-section',
          isClipped ? 'clipped' : 'fallback'
        );
        container.setAttribute('data-journey-dimmed', 'true');
      }
    }
  } catch {
    // Graceful degrade: do not crash on missing layers or style transitions
  }
}
