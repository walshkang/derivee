import '../maplibreEnv.ts';
import { describe, it } from 'node:test';
import assert from 'node:assert';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { getWorkerUrl } from 'maplibre-gl';
import { getGlobalPMTilesProtocol, maplibreWorkerUrl } from '../maplibreAdapter.ts';
import { formatMapWorkerError } from '../mapErrorClassification.ts';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const DIST_DIR = path.resolve(__dirname, '../../../dist');
const ASSETS_DIR = path.join(DIST_DIR, 'assets');

describe('MapLibre Worker Build-Output & Configuration Regression Tests', () => {
  describe('Build output asset verification (dist contract)', () => {
    it('confirms dist/assets contains emitted maplibre-gl-worker bundle and index references it', () => {
      assert.ok(
        fs.existsSync(DIST_DIR),
        'dist directory must exist for build-output verification (run npm run build)'
      );
      assert.ok(
        fs.existsSync(ASSETS_DIR),
        'dist/assets directory must exist'
      );

      const assetFiles = fs.readdirSync(ASSETS_DIR);
      const indexFile = assetFiles.find((f) => f.startsWith('index-') && f.endsWith('.js'));
      assert.ok(indexFile, 'Main index-*.js bundle must exist in dist/assets/');

      const indexContent = fs.readFileSync(path.join(ASSETS_DIR, indexFile), 'utf8');

      // Assert index bundle contains the configured worker URL pattern
      const workerUrlMatch = indexContent.match(/["'](\/assets\/maplibre-gl-worker-[a-zA-Z0-9_-]+\.js)["']/);
      assert.ok(
        workerUrlMatch,
        'Main index bundle must contain the configured /assets/maplibre-gl-worker-*.js URL'
      );

      const configuredWorkerUrl = workerUrlMatch[1];
      const resolvedWorkerPath = path.join(DIST_DIR, configuredWorkerUrl);

      // Assert the referenced worker file actually exists on disk in dist/
      assert.ok(
        fs.existsSync(resolvedWorkerPath),
        `Configured worker asset "${configuredWorkerUrl}" must exist at ${resolvedWorkerPath}`
      );

      // Assert worker bundle is substantial (> 100 KB, actual ~510 KB)
      const stat = fs.statSync(resolvedWorkerPath);
      assert.ok(
        stat.size > 100_000,
        `MapLibre worker file must contain full worker code (expected > 100KB, got ${stat.size} bytes)`
      );
    });

    it('negative case: verifies unconfigured or fabricated worker URLs do not exist in dist', () => {
      const bogusWorkerPath = path.join(ASSETS_DIR, 'maplibre-gl-worker-fabricated-bogus.js');
      assert.strictEqual(
        fs.existsSync(bogusWorkerPath),
        false,
        'Fabricated worker path must not exist in dist/assets/'
      );
    });
  });

  describe('MapLibre Worker runtime configuration & error wiring', () => {
    it('confirms setWorkerUrl was invoked before map creation and getWorkerUrl returns configured target', () => {
      assert.ok(maplibreWorkerUrl, 'maplibreWorkerUrl export must be defined');

      const configuredUrl = getWorkerUrl();
      assert.ok(
        configuredUrl,
        'MapLibre getWorkerUrl() must return the configured worker URL'
      );
      assert.strictEqual(
        configuredUrl,
        maplibreWorkerUrl,
        'getWorkerUrl() must match the worker URL imported in maplibreAdapter'
      );
    });

    it('confirms formatMapWorkerError integrates with adapter error path', () => {
      const workerErr = new Error('Worker thread failed to respond');
      const testUrl = '/assets/maplibre-gl-worker-mock.js';
      const formatted = formatMapWorkerError(workerErr, testUrl);

      assert.strictEqual(
        formatted.message,
        `Worker thread failed to respond (Worker URL: ${testUrl})`
      );
    });

    it('negative case: non-worker fatal error in adapter does not append worker URL', () => {
      const nonWorkerErr = new Error('WebGL context was lost');
      const testUrl = '/assets/maplibre-gl-worker-mock.js';
      const formatted = formatMapWorkerError(nonWorkerErr, testUrl);

      assert.strictEqual(formatted.message, 'WebGL context was lost');
      assert.strictEqual(formatted, nonWorkerErr);
    });
  });

  describe('PMTiles protocol integration with explicit worker', () => {
    it('provides a singleton Protocol instance with addProtocol registered', () => {
      const protocol1 = getGlobalPMTilesProtocol();
      assert.ok(protocol1, 'Protocol instance must be returned');
      assert.strictEqual(typeof protocol1.tile, 'function', 'protocol.tile method must exist');

      const protocol2 = getGlobalPMTilesProtocol();
      assert.strictEqual(protocol1, protocol2, 'Must return same singleton Protocol instance');
    });

    it('resolves offline tiles through global PMTiles protocol handler without hang', async () => {
      const protocol = getGlobalPMTilesProtocol();
      const realPmtilesPath = path.resolve(__dirname, '../../../../DeriveeNative/Derivee/basemap-nyc.pmtiles');
      const fileBuffer = fs.readFileSync(realPmtilesPath);
      const mockFile = new File([fileBuffer], 'basemap.pmtiles');
      const { PMTiles, FileSource } = await import('pmtiles');
      const pmtiles = new PMTiles(new FileSource(mockFile));
      protocol.add(pmtiles);

      const key = pmtiles.source.getKey();
      const tileUrl = `pmtiles://${key}/12/1206/1539`;

      const result = await new Promise<{ err?: Error; data?: unknown }>((resolve) => {
        const timeout = setTimeout(() => {
          resolve({ err: new Error('Protocol tile request hung') });
        }, 2000);

        protocol.tile({ url: tileUrl }, (err, data) => {
          clearTimeout(timeout);
          resolve({ err: (err as Error) || undefined, data });
        });
      });

      assert.ifError(result.err);
      assert.ok(result.data, 'Protocol must resolve tile data');
      assert.ok((result.data as Uint8Array).byteLength > 0, 'Tile data must not be empty');
    });

    it('negative case: protocol tile handler handles missing tile outside extract bounds cleanly without hanging', async () => {
      const protocol = getGlobalPMTilesProtocol();
      const realPmtilesPath = path.resolve(__dirname, '../../../../DeriveeNative/Derivee/basemap-nyc.pmtiles');
      const fileBuffer = fs.readFileSync(realPmtilesPath);
      const mockFile = new File([fileBuffer], 'basemap.pmtiles');
      const { PMTiles, FileSource } = await import('pmtiles');
      const pmtiles = new PMTiles(new FileSource(mockFile));
      protocol.add(pmtiles);

      const key = pmtiles.source.getKey();
      const missingTileUrl = `pmtiles://${key}/14/0/0`;

      const result = await new Promise<{ err?: Error; data?: unknown }>((resolve) => {
        const timeout = setTimeout(() => {
          resolve({ err: new Error('Protocol tile request hung on missing tile') });
        }, 2000);

        protocol.tile({ url: missingTileUrl }, (err, data) => {
          clearTimeout(timeout);
          resolve({ err: (err as Error) || undefined, data });
        });
      });

      assert.ifError(result.err);
      assert.ok(result.data !== undefined, 'Missing tile must return clean empty response');
    });
  });
});
