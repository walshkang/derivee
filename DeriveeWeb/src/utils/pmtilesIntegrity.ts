/**
 * PMTiles v3 integrity validation mirroring T.1b check standards.
 * Validates binary magic ("PMTiles"), spec version 3, physical size bounds,
 * tile data section constraints, entry counts, and MVT tile type.
 */

export class PMTilesIntegrityError extends Error {
  public readonly file: string;
  public readonly reason: string;

  constructor(file: string, reason: string) {
    super(`PMTiles integrity verification failed for ${file}: ${reason}`);
    this.name = 'PMTilesIntegrityError';
    this.file = file;
    this.reason = reason;
  }
}

export const PMTILES_HEADER_SIZE = 127;
export const PMTILES_MAGIC_BYTES = new Uint8Array([0x50, 0x4D, 0x54, 0x69, 0x6C, 0x65, 0x73]); // "PMTiles" in ASCII
export const PMTILES_SPEC_VERSION_3 = 3;
export const PMTILES_MAX_BUDGET_BYTES = 35 * 1024 * 1024; // ~35 MB ceiling (spec requires <= ~30 MB)

export interface PMTilesHeaderMetadata {
  specVersion: number;
  tileType: number;
  minZoom: number;
  maxZoom: number;
  numAddressedTiles: number;
  numTileEntries: number;
  numTileContents: number;
  tileDataOffset: number;
  tileDataLength: number;
  clustered: boolean;
}

/**
 * Validates PMTiles v3 binary header and physical file size.
 * Throws PMTilesIntegrityError on any mismatch.
 */
export function validatePMTilesHeader(
  headerData: Uint8Array,
  physicalSize: number,
  fileName: string = 'cities/nyc/basemap.pmtiles'
): PMTilesHeaderMetadata {
  if (physicalSize < PMTILES_HEADER_SIZE) {
    throw new PMTilesIntegrityError(
      fileName,
      `Physical size (${physicalSize} bytes) is less than required header size (${PMTILES_HEADER_SIZE} bytes)`
    );
  }

  if (headerData.length < PMTILES_HEADER_SIZE) {
    throw new PMTilesIntegrityError(
      fileName,
      `Could not read 127-byte header (got ${headerData.length} bytes)`
    );
  }

  // Check magic bytes 0-1 ("PM")
  if (headerData[0] !== 0x50 || headerData[1] !== 0x4D) {
    const b0 = headerData[0].toString(16).padStart(2, '0');
    const b1 = headerData[1].toString(16).padStart(2, '0');
    throw new PMTilesIntegrityError(
      fileName,
      `Missing PMTiles magic header bytes 0-1 (expected 'PM' [0x50, 0x4d], found 0x${b0} 0x${b1})`
    );
  }

  // Check full 7-byte signature ("PMTiles")
  for (let i = 0; i < PMTILES_MAGIC_BYTES.length; i++) {
    if (headerData[i] !== PMTILES_MAGIC_BYTES[i]) {
      throw new PMTilesIntegrityError(
        fileName,
        `Invalid PMTiles magic signature (expected "PMTiles")`
      );
    }
  }

  // Check spec version
  const specVersion = headerData[7];
  if (specVersion !== PMTILES_SPEC_VERSION_3) {
    throw new PMTilesIntegrityError(
      fileName,
      `Unsupported PMTiles spec version (expected ${PMTILES_SPEC_VERSION_3}, found ${specVersion})`
    );
  }

  const view = new DataView(headerData.buffer, headerData.byteOffset, headerData.byteLength);

  const getUint64 = (offset: number): number => {
    const lo = view.getUint32(offset, true);
    const hi = view.getUint32(offset + 4, true);
    return hi * 0x100000000 + lo;
  };

  const tileDataOffset = getUint64(56);
  const tileDataLength = getUint64(64);
  const numAddressedTiles = getUint64(72);
  const numTileEntries = getUint64(80);
  const numTileContents = getUint64(88);
  const clustered = headerData[96] === 1;
  const tileType = headerData[99];
  const minZoom = headerData[100];
  const maxZoom = headerData[101];

  if (physicalSize > PMTILES_MAX_BUDGET_BYTES) {
    throw new PMTilesIntegrityError(
      fileName,
      `File size (${physicalSize} bytes) exceeds budget ceiling of ${PMTILES_MAX_BUDGET_BYTES} bytes (~30 MB)`
    );
  }

  if (tileDataOffset + tileDataLength > physicalSize) {
    throw new PMTilesIntegrityError(
      fileName,
      `Tile data section (${tileDataOffset} + ${tileDataLength} = ${tileDataOffset + tileDataLength} bytes) exceeds physical file size (${physicalSize} bytes)`
    );
  }

  if (numTileEntries <= 0) {
    throw new PMTilesIntegrityError(
      fileName,
      `PMTiles archive contains no tile entries (numTileEntries = 0)`
    );
  }

  if (tileType !== 1) { // 1 = MVT
    throw new PMTilesIntegrityError(
      fileName,
      `Unsupported tile type (expected 1 for MVT, found ${tileType})`
    );
  }

  if (minZoom > maxZoom) {
    throw new PMTilesIntegrityError(
      fileName,
      `Invalid zoom levels (minZoom ${minZoom} > maxZoom ${maxZoom})`
    );
  }

  return {
    specVersion,
    tileType,
    minZoom,
    maxZoom,
    numAddressedTiles,
    numTileEntries,
    numTileContents,
    tileDataOffset,
    tileDataLength,
    clustered,
  };
}
