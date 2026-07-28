import * as h3 from 'h3-js';
import { insertUnlockedHexes } from '../db/database';

/**
 * Default H3 resolution for Fog of Wburg.
 * Resolution 11 (~24.9 meter edge length, ~0.004 km² area) provides optimal human-scale granularity.
 */
export const DEFAULT_H3_RESOLUTION = 11;

/**
 * Default buffer radius (k-ring radius).
 * Radius 1 yields 7 hexes (1 center cell + 6 immediate neighbors).
 */
export const DEFAULT_BUFFER_RADIUS = 1;

/**
 * Validates whether a value is a valid H3 index string.
 * AGENTS.md Directive: H3 indices must always be stored, transmitted, and processed as 15-character hexadecimal strings.
 */
export function isValidH3Index(h3Index: unknown): h3Index is string {
  return (
    typeof h3Index === 'string' &&
    h3Index.length === 15 &&
    h3.isValidCell(h3Index)
  );
}

/**
 * Converts a GPS coordinate (latitude/longitude) to an H3 index string at the specified resolution.
 * Strict type enforcement guarantees the output is a 15-character hexadecimal string.
 *
 * @param lat Latitude (-90 to 90)
 * @param lng Longitude (-180 to 180)
 * @param resolution H3 grid resolution (default: 11)
 * @returns 15-character H3 hex index string
 */
export function coordToH3(
  lat: number,
  lng: number,
  resolution: number = DEFAULT_H3_RESOLUTION
): string {
  if (typeof lat !== 'number' || isNaN(lat) || lat < -90 || lat > 90) {
    throw new Error(`Invalid latitude coordinate: ${lat}`);
  }
  if (typeof lng !== 'number' || isNaN(lng) || lng < -180 || lng > 180) {
    throw new Error(`Invalid longitude coordinate: ${lng}`);
  }

  const h3Index = h3.latLngToCell(lat, lng, resolution);

  // Strict string type check (AGENTS.md guardrail)
  if (typeof h3Index !== 'string' || h3Index.length === 0) {
    throw new Error(`h3.latLngToCell failed to return a valid string for (${lat}, ${lng})`);
  }

  return h3Index;
}

/**
 * Calculates the H3 buffer (k-ring / gridDisk) surrounding a given H3 cell index.
 *
 * @param h3Index 15-character H3 cell index string
 * @param radius k-ring radius (0 = center only, 1 = center + 6 neighbors [7 hexes], 2 = 19 hexes, etc.)
 * @returns Array of 15-character H3 hex index strings
 */
export function getH3Buffer(
  h3Index: string,
  radius: number = DEFAULT_BUFFER_RADIUS
): string[] {
  if (!isValidH3Index(h3Index)) {
    throw new Error(`Invalid H3 index string provided to getH3Buffer: "${h3Index}"`);
  }
  if (typeof radius !== 'number' || radius < 0 || !Number.isInteger(radius)) {
    throw new Error(`Invalid buffer radius: ${radius}. Must be a non-negative integer.`);
  }

  const hexes = h3.gridDisk(h3Index, radius);

  // Strict type filter ensuring return values are strictly strings (AGENTS.md guardrail)
  return hexes.filter((hex): hex is string => typeof hex === 'string' && hex.length > 0);
}

/**
 * Converts a GPS coordinate into a list of H3 buffer hexes surrounding the location.
 *
 * @param lat Latitude
 * @param lng Longitude
 * @param radius k-ring radius (default: 1)
 * @param resolution H3 grid resolution (default: 11)
 * @returns Array of H3 hex index strings
 */
export function getHexesForCoordinate(
  lat: number,
  lng: number,
  radius: number = DEFAULT_BUFFER_RADIUS,
  resolution: number = DEFAULT_H3_RESOLUTION
): string[] {
  const centerHex = coordToH3(lat, lng, resolution);
  return getH3Buffer(centerHex, radius);
}

/**
 * Processes a new location coordinate update:
 * 1. Converts location to Resolution 11 H3 cell index and calculates surrounding buffer hexes.
 * 2. Writes newly unlocked hexes to local op-sqlite database (explored_hexes).
 * 3. Updates Zustand exploration store with newly unlocked hexes.
 *
 * @param lat Latitude
 * @param lng Longitude
 * @param radius Buffer radius (default: 1)
 * @param resolution H3 resolution (default: 11)
 * @returns Object containing center hex and all buffer hexes
 */
export function processAndStoreLocationHexes(
  lat: number,
  lng: number,
  radius: number = DEFAULT_BUFFER_RADIUS,
  resolution: number = DEFAULT_H3_RESOLUTION
): { centerHex: string; bufferHexes: string[]; newHexCount: number } {
  const centerHex = coordToH3(lat, lng, resolution);
  const bufferHexes = getH3Buffer(centerHex, radius);

  // Persist hexes to op-sqlite database
  const dbInsertedCount = insertUnlockedHexes(bufferHexes);

  // Update Zustand store
  const { useExplorationStore } = require('../store/useExplorationStore');
  const store = useExplorationStore.getState();
  store.setCurrentLocation({ latitude: lat, longitude: lng });
  const storeAddedCount = store.addUnlockedHexes(bufferHexes);

  const newHexCount = Math.max(dbInsertedCount, storeAddedCount);

  return {
    centerHex,
    bufferHexes,
    newHexCount,
  };
}
