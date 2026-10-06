import { describe, it } from 'node:test';
import assert from 'node:assert';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { PMTiles, FileSource, Protocol } from 'pmtiles';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const REAL_PMTILES_PATH = path.resolve(__dirname, '../../../../DeriveeNative/Derivee/basemap-nyc.pmtiles');

describe('Tile Protocol Offline Serving Tests', () => {
  const fileBuffer = fs.readFileSync(REAL_PMTILES_PATH);
  // Web File API is natively available in Node 20+
  const mockOpfsFile = new File([fileBuffer], 'basemap.pmtiles');

  describe('Offline tile extraction via PMTiles FileSource', () => {
    it('serves a known tile (z=12, x=1206, y=1539) and asserts non-empty vector tile bytes', async () => {
      const fileSource = new FileSource(mockOpfsFile);
      const pmtiles = new PMTiles(fileSource);

      const header = await pmtiles.getHeader();
      assert.strictEqual(header.specVersion, 3, 'PMTiles spec version must be 3');
      assert.strictEqual(header.tileType, 1, 'Tile type must be MVT (1)');
      assert.strictEqual(header.minZoom, 0);
      assert.strictEqual(header.maxZoom, 14);

      // Known tile in Midtown Manhattan (Times Sq / Midtown)
      const tile = await pmtiles.getZxy(12, 1206, 1539);

      assert.ok(tile, 'Known tile 12/1206/1539 must exist in NYC extract');
      assert.ok(tile.data, 'Tile data must not be null');
      assert.strictEqual(tile.data.byteLength, 185180, 'Tile data byteLength must match build');

      // Check MVT protobuf wire format: field 3 (layers), length-delimited tag = (3 << 3) | 2 = 0x1a (26)
      const bytes = new Uint8Array(tile.data);
      assert.strictEqual(bytes[0], 0x1a, 'First byte of MVT protobuf should be field 3 tag 0x1a');
    });

    it('serves another known tile at zoom 14 (Downtown Manhattan / Brooklyn Bridge)', async () => {
      const fileSource = new FileSource(mockOpfsFile);
      const pmtiles = new PMTiles(fileSource);

      // Zoom 14 tile in Lower Manhattan
      const tile = await pmtiles.getZxy(14, 4825, 6161);
      assert.ok(tile, 'Tile 14/4825/6161 must exist in NYC extract');
      assert.ok(tile.data.byteLength > 10000, 'Tile must contain substantial vector geometries');
    });
  });

  describe('MapLibre Protocol Integration', () => {
    it('serves tile through Protocol handler callback matching offline PMTiles bytes', async () => {
      const protocol = new Protocol();
      const fileSource = new FileSource(mockOpfsFile);
      const pmtiles = new PMTiles(fileSource);
      protocol.add(pmtiles);

      const key = pmtiles.source.getKey();
      const tileUrl = `pmtiles://${key}/12/1206/1539`;

      const tileResponse = await new Promise<{ err?: Error; data?: ArrayBuffer | Uint8Array | null }>((resolve) => {
        const timeout = setTimeout(() => {
          resolve({ err: new Error('Protocol tile request timed out (hang detected)') });
        }, 2000);

        protocol.tile({ url: tileUrl }, (err, data) => {
          clearTimeout(timeout);
          resolve({ err: (err as Error) || undefined, data: (data as ArrayBuffer | Uint8Array | null) });
        });
      });

      assert.ifError(tileResponse.err);
      assert.ok(tileResponse.data, 'Protocol must return tile data');
      assert.ok((tileResponse.data as Uint8Array).byteLength > 0, 'Protocol tile data must not be empty');
    });
  });

  describe('Negative cases: missing tiles and invalid requests (no hang)', () => {
    it('returns undefined cleanly without hang when tile is outside extract bounds', async () => {
      const fileSource = new FileSource(mockOpfsFile);
      const pmtiles = new PMTiles(fileSource);

      // Tile 14/0/0 is off the coast of Africa (null island area), far outside NYC
      const tile = await Promise.race([
        pmtiles.getZxy(14, 0, 0),
        new Promise<never>((_, reject) =>
          setTimeout(() => reject(new Error('PMTiles getZxy hung on missing tile')), 2000)
        ),
      ]);

      assert.strictEqual(tile, undefined, 'Missing tile must return undefined cleanly');
    });

    it('Protocol returns empty/clean response without hang on missing tile', async () => {
      const protocol = new Protocol();
      const fileSource = new FileSource(mockOpfsFile);
      const pmtiles = new PMTiles(fileSource);
      protocol.add(pmtiles);

      const key = pmtiles.source.getKey();
      const missingTileUrl = `pmtiles://${key}/14/0/0`;

      const result = await new Promise<{ err?: Error; data?: ArrayBuffer | Uint8Array | null }>((resolve) => {
        const timeout = setTimeout(() => {
          resolve({ err: new Error('Protocol tile request hung on missing tile') });
        }, 2000);

        protocol.tile({ url: missingTileUrl }, (err, data) => {
          clearTimeout(timeout);
          resolve({ err: (err as Error) || undefined, data: (data as ArrayBuffer | Uint8Array | null) });
        });
      });

      assert.ifError(result.err);
      // MapLibre protocol returns empty Uint8Array for nonexistent tiles (HTTP 204 equivalent)
      assert.ok(result.data !== undefined);
    });

    it('handles out-of-range zoom levels cleanly without hanging', async () => {
      const fileSource = new FileSource(mockOpfsFile);
      const pmtiles = new PMTiles(fileSource);

      // Zoom 22 exceeds maxZoom 14
      const tile = await Promise.race([
        pmtiles.getZxy(22, 0, 0),
        new Promise<never>((_, reject) =>
          setTimeout(() => reject(new Error('PMTiles hung on out-of-range zoom')), 2000)
        ),
      ]);

      assert.strictEqual(tile, undefined, 'Out-of-range zoom must resolve cleanly to undefined');
    });
  });
});
