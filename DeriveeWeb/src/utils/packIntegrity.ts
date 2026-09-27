/**
 * Integrity ground truth validation mirroring:
 * DeriveeNative/Derivee/CityPackManager.swift (lines 73-92 and 592-666)
 *
 * Validates binary magic signatures, schema versions, endianness markers,
 * header sizes, file size invariants, and SQLite magic bytes.
 */

import type { CityConfig } from '../types/pack';

export class PackIntegrityError extends Error {
  constructor(public readonly file: string, public readonly reason: string) {
    super(`Integrity verification failed for ${file}: ${reason}`);
    this.name = 'PackIntegrityError';
  }
}

// Expected Magic Constants (little-endian byte representation)
export const MAGIC_TIMETABLE_DRV1 = 0x31565244; // "DRV1" in ASCII (0x44, 0x52, 0x56, 0x31)
export const MAGIC_WALK_GRAPH     = 0x4B4C4157; // "WALK" in ASCII (0x57, 0x41, 0x4C, 0x4B)
export const MAGIC_ULTRA_CSR      = 0x554C5452; // "ULTR" in ASCII (0x52, 0x54, 0x4C, 0x55)
export const ENDIANNESS_MARKER    = 0x01020304;
export const MASTER_HEADER_SIZE   = 232;
export const BINARY_HEADER_SIZE   = 32;

// SQLite format 3\0 magic header (16 bytes)
const SQLITE_MAGIC = new Uint8Array([
  0x53, 0x51, 0x4c, 0x69, 0x74, 0x65, 0x20, 0x66,
  0x6f, 0x72, 0x6d, 0x61, 0x74, 0x20, 0x33, 0x00
]);

function bytesToHex(bytes: Uint8Array, maxBytes: number = 16): string {
  return Array.from(bytes.slice(0, maxBytes))
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('');
}

/**
 * Validates that a file begins with the SQLite 3 magic header and is >= 4096 bytes.
 * Mirrors CityPackManager.isValidDatabase
 */
export function validateSqliteDatabase(headerData: Uint8Array, physicalSize: number, fileName: string = 'transit.sqlite'): void {
  if (physicalSize < 4096) {
    throw new PackIntegrityError(fileName, `File size (${physicalSize} bytes) is smaller than minimum SQLite page size (4096 bytes)`);
  }

  if (headerData.length < 16) {
    throw new PackIntegrityError(fileName, `Could not read 16-byte SQLite header`);
  }

  for (let i = 0; i < 16; i++) {
    if (headerData[i] !== SQLITE_MAGIC[i]) {
      const foundHex = bytesToHex(headerData, 16);
      const expectedHex = bytesToHex(SQLITE_MAGIC, 16);
      throw new PackIntegrityError(
        fileName,
        `Missing SQLite format 3 magic header signature (found: 0x${foundHex}, expected: 0x${expectedHex})`
      );
    }
  }
}

/**
 * Validates MasterHeader (232 bytes total, first 40 bytes core fields).
 * Mirrors CityPackManager.validateBinaryAsset with isMasterHeader = true.
 */
export function validateMasterHeader(
  headerData: Uint8Array,
  physicalSize: number,
  expectedMagic: number,
  expectedVersion: number = 1,
  fileName: string
): void {
  if (physicalSize < MASTER_HEADER_SIZE) {
    throw new PackIntegrityError(fileName, `File size (${physicalSize} bytes) is smaller than MasterHeader size (232 bytes)`);
  }

  if (headerData.length < 40) {
    throw new PackIntegrityError(fileName, `Failed to read 40-byte MasterHeader preamble`);
  }

  const view = new DataView(headerData.buffer, headerData.byteOffset, headerData.byteLength);

  const magic = view.getUint32(0, true);
  const version = view.getUint32(4, true);
  const endian = view.getUint32(8, true);
  const parsedHeaderSize = view.getUint32(12, true);
  const fileSize = view.getBigUint64(16, true);

  if (magic !== expectedMagic) {
    const foundHex = bytesToHex(headerData, 16);
    throw new PackIntegrityError(
      fileName,
      `Invalid magic signature: 0x${magic.toString(16).toUpperCase().padStart(8, '0')} (expected: 0x${expectedMagic.toString(16).toUpperCase().padStart(8, '0')}, first 16 bytes: 0x${foundHex})`
    );
  }

  if (version !== expectedVersion) {
    throw new PackIntegrityError(fileName, `Schema version mismatch: ${version} (expected: ${expectedVersion})`);
  }

  if (endian !== ENDIANNESS_MARKER) {
    throw new PackIntegrityError(
      fileName,
      `Endianness marker mismatch: 0x${endian.toString(16).toUpperCase()} (expected: 0x01020304)`
    );
  }

  if (parsedHeaderSize !== MASTER_HEADER_SIZE) {
    throw new PackIntegrityError(fileName, `Invalid header size: ${parsedHeaderSize} (expected: ${MASTER_HEADER_SIZE})`);
  }

  if (fileSize !== BigInt(physicalSize)) {
    throw new PackIntegrityError(
      fileName,
      `Header file_size (${fileSize}) != physical file size (${physicalSize})`
    );
  }
}

/**
 * Validates BinaryHeader (32 bytes total, first 8 bytes core fields).
 * Mirrors CityPackManager.validateBinaryAsset with isMasterHeader = false.
 */
export function validateBinaryHeader(
  headerData: Uint8Array,
  physicalSize: number,
  expectedMagic: number,
  expectedVersion: number = 1,
  fileName: string
): void {
  if (physicalSize < BINARY_HEADER_SIZE) {
    throw new PackIntegrityError(fileName, `File size (${physicalSize} bytes) is smaller than BinaryHeader size (32 bytes)`);
  }

  if (headerData.length < 8) {
    throw new PackIntegrityError(fileName, `Failed to read 8-byte BinaryHeader preamble`);
  }

  const view = new DataView(headerData.buffer, headerData.byteOffset, headerData.byteLength);

  const magic = view.getUint32(0, true);
  const version = view.getUint32(4, true);

  if (magic !== expectedMagic) {
    const foundHex = bytesToHex(headerData, 16);
    throw new PackIntegrityError(
      fileName,
      `Invalid magic signature: 0x${magic.toString(16).toUpperCase().padStart(8, '0')} (expected: 0x${expectedMagic.toString(16).toUpperCase().padStart(8, '0')}, first 16 bytes: 0x${foundHex})`
    );
  }

  if (version !== expectedVersion) {
    throw new PackIntegrityError(fileName, `Version mismatch: ${version} (expected: ${expectedVersion})`);
  }
}

/**
 * Validates city_config.json structure and required metadata.
 */
export function validateCityConfig(jsonText: string): CityConfig {
  let config: CityConfig;
  try {
    config = JSON.parse(jsonText);
  } catch (err) {
    throw new PackIntegrityError('city_config.json', `JSON syntax error: ${(err as Error).message}`);
  }

  if (!config.slug || config.slug.trim() !== 'nyc') {
    throw new PackIntegrityError('city_config.json', `Expected slug "nyc", found "${config.slug}"`);
  }

  if (!config.version || config.version < 2) {
    throw new PackIntegrityError('city_config.json', `Expected config version >= 2, found ${config.version}`);
  }

  if (!config.routing || !config.routing.timetableBinFile || !config.routing.walkGraphFile || !config.routing.ultraCsrFile) {
    throw new PackIntegrityError('city_config.json', 'Missing required routing asset file declarations');
  }

  return config;
}

/**
 * Validates transit-lines.geojson is valid GeoJSON.
 */
export function validateTransitLinesGeoJson(jsonText: string): void {
  try {
    const parsed = JSON.parse(jsonText);
    if (!parsed || parsed.type !== 'FeatureCollection' || !Array.isArray(parsed.features)) {
      throw new Error('Not a valid GeoJSON FeatureCollection');
    }
  } catch (err) {
    throw new PackIntegrityError('transit-lines.geojson', `Invalid GeoJSON: ${(err as Error).message}`);
  }
}
