import { describe, it } from 'node:test';
import assert from 'node:assert';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  validatePMTilesHeader,
  PMTilesIntegrityError,
  PMTILES_HEADER_SIZE,
  PMTILES_SPEC_VERSION_3,
  PMTILES_MAX_BUDGET_BYTES,
} from '../pmtilesIntegrity.ts';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const REAL_PMTILES_PATH = path.resolve(__dirname, '../../../../DeriveeNative/Derivee/basemap-nyc.pmtiles');

describe('PMTiles Integrity Validation Tests', () => {
  const realFileBuffer = fs.readFileSync(REAL_PMTILES_PATH);
  const realPhysicalSize = realFileBuffer.length;
  const validHeader = new Uint8Array(realFileBuffer.subarray(0, PMTILES_HEADER_SIZE));

  describe('Positive validation: real NYC basemap PMTiles archive', () => {
    it('validates authentic basemap-nyc.pmtiles header and returns metadata', () => {
      const meta = validatePMTilesHeader(validHeader, realPhysicalSize, 'cities/nyc/basemap.pmtiles');

      assert.strictEqual(meta.specVersion, PMTILES_SPEC_VERSION_3, 'Spec version must be 3');
      assert.strictEqual(meta.tileType, 1, 'Tile type must be 1 (MVT)');
      assert.strictEqual(meta.minZoom, 0, 'Min zoom should be 0');
      assert.strictEqual(meta.maxZoom, 14, 'Max zoom should be 14');
      assert.strictEqual(meta.numTileEntries, 972, 'Num tile entries should match build');
      assert.strictEqual(meta.numTileContents, 944, 'Num tile contents should match build');
      assert.strictEqual(meta.clustered, true, 'Archive must be clustered');
      assert.strictEqual(meta.tileDataOffset, 2814, 'Tile data offset must match header');
      assert.strictEqual(meta.tileDataLength, 24988681, 'Tile data length must match header');

      // Invariant: tile data fits within physical size
      assert.ok(
        meta.tileDataOffset + meta.tileDataLength <= realPhysicalSize,
        'Tile data section must be within physical file bounds'
      );

      // Invariant: under budget ceiling (<= ~30 MB budget)
      assert.ok(
        realPhysicalSize <= PMTILES_MAX_BUDGET_BYTES,
        `Physical size ${realPhysicalSize} must be <= budget ${PMTILES_MAX_BUDGET_BYTES}`
      );
    });
  });

  describe('Negative validation: corrupted or invalid PMTiles headers', () => {
    it('rejects file when physicalSize < 127 bytes', () => {
      assert.throws(
        () => validatePMTilesHeader(validHeader, 120),
        (err: unknown) => {
          assert.ok(err instanceof PMTilesIntegrityError);
          assert.match(err.message, /Physical size \(120 bytes\) is less than required header size/);
          return true;
        }
      );
    });

    it('rejects headerData when shorter than 127 bytes', () => {
      const truncatedHeader = validHeader.subarray(0, 64);
      assert.throws(
        () => validatePMTilesHeader(truncatedHeader, realPhysicalSize),
        (err: unknown) => {
          assert.ok(err instanceof PMTilesIntegrityError);
          assert.match(err.message, /Could not read 127-byte header/);
          return true;
        }
      );
    });

    it('rejects corrupted magic bytes 0-1', () => {
      const corruptHeader = new Uint8Array(validHeader);
      corruptHeader[0] = 0x00; // 'P' -> 0
      corruptHeader[1] = 0x00; // 'M' -> 0

      assert.throws(
        () => validatePMTilesHeader(corruptHeader, realPhysicalSize),
        (err: unknown) => {
          assert.ok(err instanceof PMTilesIntegrityError);
          assert.match(err.message, /Missing PMTiles magic header bytes 0-1/);
          return true;
        }
      );
    });

    it('rejects corrupted magic signature bytes 2-6', () => {
      const corruptHeader = new Uint8Array(validHeader);
      corruptHeader[2] = 0x58; // 'T' -> 'X'

      assert.throws(
        () => validatePMTilesHeader(corruptHeader, realPhysicalSize),
        (err: unknown) => {
          assert.ok(err instanceof PMTilesIntegrityError);
          assert.match(err.message, /Invalid PMTiles magic signature/);
          return true;
        }
      );
    });

    it('rejects unsupported spec version (e.g. version 2 or 4)', () => {
      const v2Header = new Uint8Array(validHeader);
      v2Header[7] = 2;

      assert.throws(
        () => validatePMTilesHeader(v2Header, realPhysicalSize),
        (err: unknown) => {
          assert.ok(err instanceof PMTilesIntegrityError);
          assert.match(err.message, /Unsupported PMTiles spec version \(expected 3, found 2\)/);
          return true;
        }
      );

      const v4Header = new Uint8Array(validHeader);
      v4Header[7] = 4;

      assert.throws(
        () => validatePMTilesHeader(v4Header, realPhysicalSize),
        (err: unknown) => {
          assert.ok(err instanceof PMTilesIntegrityError);
          assert.match(err.message, /Unsupported PMTiles spec version \(expected 3, found 4\)/);
          return true;
        }
      );
    });

    it('rejects archive exceeding budget ceiling (> 35 MB)', () => {
      const oversized = PMTILES_MAX_BUDGET_BYTES + 1;
      assert.throws(
        () => validatePMTilesHeader(validHeader, oversized),
        (err: unknown) => {
          assert.ok(err instanceof PMTilesIntegrityError);
          assert.match(err.message, /exceeds budget ceiling/);
          return true;
        }
      );
    });

    it('rejects archive whose tile data section exceeds physical file size', () => {
      // Simulate file truncated after header
      const truncatedSize = 5000;
      assert.throws(
        () => validatePMTilesHeader(validHeader, truncatedSize),
        (err: unknown) => {
          assert.ok(err instanceof PMTilesIntegrityError);
          assert.match(err.message, /Tile data section .* exceeds physical file size/);
          return true;
        }
      );
    });

    it('rejects archive with 0 tile entries', () => {
      const zeroEntriesHeader = new Uint8Array(validHeader);
      // Byte 80-87: numTileEntries (uint64 little endian)
      zeroEntriesHeader.fill(0, 80, 88);

      assert.throws(
        () => validatePMTilesHeader(zeroEntriesHeader, realPhysicalSize),
        (err: unknown) => {
          assert.ok(err instanceof PMTilesIntegrityError);
          assert.match(err.message, /contains no tile entries/);
          return true;
        }
      );
    });

    it('rejects archive with unsupported tile type (non-MVT, e.g. raster PNG = 2)', () => {
      const rasterHeader = new Uint8Array(validHeader);
      rasterHeader[99] = 2; // PNG

      assert.throws(
        () => validatePMTilesHeader(rasterHeader, realPhysicalSize),
        (err: unknown) => {
          assert.ok(err instanceof PMTilesIntegrityError);
          assert.match(err.message, /Unsupported tile type \(expected 1 for MVT, found 2\)/);
          return true;
        }
      );
    });

    it('rejects archive with minZoom > maxZoom', () => {
      const badZoomHeader = new Uint8Array(validHeader);
      badZoomHeader[100] = 15; // minZoom
      badZoomHeader[101] = 14; // maxZoom

      assert.throws(
        () => validatePMTilesHeader(badZoomHeader, realPhysicalSize),
        (err: unknown) => {
          assert.ok(err instanceof PMTilesIntegrityError);
          assert.match(err.message, /Invalid zoom levels \(minZoom 15 > maxZoom 14\)/);
          return true;
        }
      );
    });
  });

  describe('Installer rejection and cleanup simulation', () => {
    it('corrupt header → install rejected, error state, no partial file left', async () => {
      // Mock an OPFS filesystem in-memory
      const mockStorage = new Map<string, Uint8Array>();
      const slug = 'nyc';
      const targetPath = `cities/${slug}/basemap.pmtiles`;

      // Simulate partial corrupted write
      const corruptData = new Uint8Array([0x00, 0x01, 0x02, 0x03]);
      mockStorage.set(targetPath, corruptData);
      assert.strictEqual(mockStorage.has(targetPath), true, 'Partial file exists before validation');

      // Simulate installer worker integrity check & catch cleanup
      let caughtError: Error | null = null;
      try {
        const fileBytes = mockStorage.get(targetPath)!;
        if (fileBytes.length < PMTILES_HEADER_SIZE) {
          throw new PMTilesIntegrityError(targetPath, 'Downloaded file is incomplete.');
        }
        validatePMTilesHeader(fileBytes.subarray(0, PMTILES_HEADER_SIZE), fileBytes.length, targetPath);
      } catch (err: unknown) {
        caughtError = err as Error;
        // Worker cleanup: removeEntry
        mockStorage.delete(targetPath);
      }

      assert.ok(caughtError instanceof PMTilesIntegrityError, 'Installer must catch integrity error');
      assert.strictEqual(mockStorage.has(targetPath), false, 'Partial corrupt file must be deleted (no partial file left)');
    });
  });
});
