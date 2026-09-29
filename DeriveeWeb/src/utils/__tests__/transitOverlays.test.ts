import { describe, it } from 'node:test';
import assert from 'node:assert';
import {
  TRANSIT_LINES_SOURCE_ID,
  TRANSIT_LINES_LAYER_ID,
  TRANSIT_STATIONS_SOURCE_ID,
  TRANSIT_STATIONS_LAYER_ID,
  RIBBON_PAINT_LINE_COLOR,
  buildStationGeoJSON,
  getTransitLinesLayerConfig,
  getTransitStationsLayerConfig,
  escapeHtml,
} from '../transitOverlays.ts';
import type { StopItem } from '../../types/routing.ts';

describe('Transit Overlays Layer & Station Data Tests', () => {
  describe('Defect 1: Ribbon Color Key Specification', () => {
    it('sets ribbon line-color paint property to trunk_color_hex', () => {
      const config = getTransitLinesLayerConfig() as any;

      assert.strictEqual(config.id, TRANSIT_LINES_LAYER_ID);
      assert.strictEqual(config.source, TRANSIT_LINES_SOURCE_ID);
      assert.strictEqual(config.type, 'line');
      assert.deepStrictEqual(config.paint['line-color'], ['get', 'trunk_color_hex']);
      assert.deepStrictEqual(RIBBON_PAINT_LINE_COLOR, ['get', 'trunk_color_hex']);
    });

    it('negative case: rejects the broken ["get", "color"] property key', () => {
      const config = getTransitLinesLayerConfig() as any;
      const lineColor = config.paint['line-color'];

      assert.notDeepStrictEqual(
        lineColor,
        ['get', 'color'],
        'Ribbon line-color must NOT use "color" key as it does not exist in transit-lines.geojson'
      );
      assert.ok(Array.isArray(lineColor) && (lineColor[1] as string) !== 'color');
      assert.ok(lineColor[1] === 'trunk_color_hex');
    });

    it('negative case: ensures line-color is not undefined, null, or fallback black literal', () => {
      const config = getTransitLinesLayerConfig() as any;
      const lineColor = config.paint['line-color'];

      assert.ok(lineColor != null, 'line-color must not be null or undefined');
      assert.notStrictEqual(lineColor, '#000000', 'line-color must not be hardcoded black');
      assert.notStrictEqual(lineColor, 'black');
    });
  });

  describe('Defect 2: Station Bullets from Stops Data', () => {
    const sampleStops: StopItem[] = [
      { id: 101, name: 'Times Sq - 42 St', lat: 40.75529, lon: -73.987495 },
      { id: 102, name: 'Times Sq - 42 St (Southbound)', lat: 40.75529, lon: -73.987495 }, // Duplicate coord
      { id: 103, name: 'Grand Central - 42 St', lat: 40.751776, lon: -73.976848 },
      { id: 104, name: 'Union Sq - 14 St', lat: 40.734789, lon: -73.990714 },
    ];

    it('builds a valid GeoJSON FeatureCollection of Point features', () => {
      const geojson = buildStationGeoJSON(sampleStops);

      assert.strictEqual(geojson.type, 'FeatureCollection');
      assert.strictEqual(geojson.features.length, 3, 'Should deduplicate co-located platform stops');

      // Verify first feature
      const f0 = geojson.features[0];
      assert.strictEqual(f0.type, 'Feature');
      assert.strictEqual(f0.geometry.type, 'Point');
      assert.strictEqual(f0.geometry.coordinates[0], -73.987495, 'Coordinate 0 must be longitude');
      assert.strictEqual(f0.geometry.coordinates[1], 40.75529, 'Coordinate 1 must be latitude');
      assert.strictEqual(f0.properties.name, 'Times Sq - 42 St');
      assert.strictEqual(f0.properties.id, 101);

      // Verify all features have Point geometry and correct coordinates
      for (const f of geojson.features) {
        assert.strictEqual(f.geometry.type, 'Point');
        assert.strictEqual(f.geometry.coordinates.length, 2);
        assert.strictEqual(typeof f.geometry.coordinates[0], 'number');
        assert.strictEqual(typeof f.geometry.coordinates[1], 'number');
        assert.ok(f.geometry.coordinates[0] < 0, 'NYC longitude must be negative');
        assert.ok(f.geometry.coordinates[1] > 0, 'NYC latitude must be positive');
      }
    });

    it('deduplicates multiple platform stops sharing coordinates into single station bullet', () => {
      const coLocatedPlatforms: StopItem[] = [
        { id: 1, name: 'Platform N', lat: 40.7128, lon: -74.006 },
        { id: 2, name: 'Platform S', lat: 40.7128, lon: -74.006 },
        { id: 3, name: 'Platform Express', lat: 40.7128, lon: -74.006 },
      ];

      const result = buildStationGeoJSON(coLocatedPlatforms);
      assert.strictEqual(result.features.length, 1, 'Co-located stops must yield exactly one feature');
      assert.strictEqual(result.features[0].properties.id, 1);
    });

    it('negative case: handles empty stops array cleanly', () => {
      const geojson = buildStationGeoJSON([]);
      assert.strictEqual(geojson.type, 'FeatureCollection');
      assert.deepStrictEqual(geojson.features, []);
    });

    it('negative case: handles null or undefined input cleanly without throwing', () => {
      const nullGeojson = buildStationGeoJSON(null as unknown as StopItem[]);
      assert.strictEqual(nullGeojson.type, 'FeatureCollection');
      assert.deepStrictEqual(nullGeojson.features, []);

      const undefinedGeojson = buildStationGeoJSON(undefined as unknown as StopItem[]);
      assert.strictEqual(undefinedGeojson.type, 'FeatureCollection');
      assert.deepStrictEqual(undefinedGeojson.features, []);
    });

    it('negative case: filters out invalid or corrupted stop records', () => {
      const corruptedStops: StopItem[] = [
        null as unknown as StopItem,
        { id: 901, name: 'NaN Lat', lat: NaN, lon: -73.98 } as StopItem,
        { id: 902, name: 'NaN Lon', lat: 40.75, lon: NaN } as StopItem,
        { id: 903, name: 'String Coords', lat: '40.75' as unknown as number, lon: -73.98 },
        { id: 904, name: 'Missing Coords' } as unknown as StopItem,
        { id: 905, name: 'Valid Stop', lat: 40.75, lon: -73.98 },
      ];

      const geojson = buildStationGeoJSON(corruptedStops);
      assert.strictEqual(geojson.features.length, 1);
      assert.strictEqual(geojson.features[0].properties.name, 'Valid Stop');
    });

    it('negative case: handles stops with missing name property safely', () => {
      const noNameStop = [{ id: 999, lat: 40.71, lon: -74.01 }] as unknown as StopItem[];
      const geojson = buildStationGeoJSON(noNameStop);
      assert.strictEqual(geojson.features.length, 1);
      assert.strictEqual(geojson.features[0].properties.name, '');
    });
  });

  describe('Defect 2: Station Layer Configuration & Dark Basemap Contrast', () => {
    it('configures station layer using separate transit-stations source and circle type', () => {
      const layerConfig = getTransitStationsLayerConfig() as any;

      assert.strictEqual(layerConfig.id, TRANSIT_STATIONS_LAYER_ID);
      assert.strictEqual(layerConfig.source, TRANSIT_STATIONS_SOURCE_ID);
      assert.strictEqual(layerConfig.type, 'circle');
      assert.strictEqual(layerConfig.paint['circle-color'], '#ffffff');
      assert.strictEqual(layerConfig.paint['circle-stroke-color'], '#000000');
      assert.ok(layerConfig.paint['circle-radius'] > 0);
      assert.ok(layerConfig.paint['circle-stroke-width'] > 0);
    });

    it('negative case: station layer does NOT depend on transit-lines source', () => {
      const layerConfig = getTransitStationsLayerConfig() as any;

      assert.notStrictEqual(
        layerConfig.source,
        TRANSIT_LINES_SOURCE_ID,
        'Station bullets must NOT use transit-lines source which only has LineString geometries'
      );
      assert.notStrictEqual(layerConfig.source, 'transit-lines');
    });
  });

  describe('HTML Escaping for Station Popups', () => {
    it('escapes special characters to prevent HTML/XSS injection in popups', () => {
      const unsafe = '<script>alert("xss")</script> & "special" \'station\'';
      const safe = escapeHtml(unsafe);

      assert.ok(!safe.includes('<script>'));
      assert.ok(!safe.includes('</script>'));
      assert.ok(!safe.includes('"xss"'));
      assert.ok(safe.includes('&lt;script&gt;'));
      assert.ok(safe.includes('&amp;'));
      assert.ok(safe.includes('&quot;special&quot;'));
      assert.ok(safe.includes('&#039;station&#039;'));
    });

    it('leaves standard station names unmodified', () => {
      const name = 'Times Sq - 42 St';
      assert.strictEqual(escapeHtml(name), name);
    });
  });
});
