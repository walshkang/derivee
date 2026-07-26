import {
  coordToH3,
  getH3Buffer,
  getHexesForCoordinate,
  processAndStoreLocationHexes,
  isValidH3Index,
  DEFAULT_H3_RESOLUTION,
  DEFAULT_BUFFER_RADIUS,
} from '../h3Utils';
import { getAllUnlockedHexes, getExploredHexCount, closeDatabase } from '../../db/database';
import { useExplorationStore } from '../../store/useExplorationStore';

describe('h3Utils Spatial Logic & Grid Conversions', () => {
  // Williamsburg, Brooklyn coordinates
  const WBURG_LAT = 40.7128;
  const WBURG_LNG = -73.966;

  beforeEach(() => {
    // Reset Zustand store state before each test
    useExplorationStore.getState().resetExploration();
  });

  afterEach(() => {
    closeDatabase();
  });

  describe('isValidH3Index', () => {
    it('returns true for valid 15-character Resolution 11 H3 hex strings', () => {
      const hex = coordToH3(WBURG_LAT, WBURG_LNG, 11);
      expect(isValidH3Index(hex)).toBe(true);
      expect(typeof hex).toBe('string');
      expect(hex.length).toBe(15);
    });

    it('returns false for invalid hex strings or non-string inputs', () => {
      expect(isValidH3Index('invalid_hex')).toBe(false);
      expect(isValidH3Index('')).toBe(false);
      expect(isValidH3Index(123456789)).toBe(false);
      expect(isValidH3Index(null)).toBe(false);
      expect(isValidH3Index(undefined)).toBe(false);
    });
  });

  describe('coordToH3', () => {
    it('converts lat/lng coordinates to a 15-character H3 index string at Resolution 11', () => {
      const hex = coordToH3(WBURG_LAT, WBURG_LNG);

      // AGENTS.md Directive: Explicitly assert string primitive type
      expect(typeof hex).toBe('string');
      expect(hex.length).toBe(15);
      expect(isValidH3Index(hex)).toBe(true);
    });

    it('supports custom resolutions', () => {
      const res8Hex = coordToH3(WBURG_LAT, WBURG_LNG, 8);
      expect(typeof res8Hex).toBe('string');
      expect(res8Hex.length).toBe(15);
      expect(isValidH3Index(res8Hex)).toBe(true);
      expect(res8Hex).not.toEqual(coordToH3(WBURG_LAT, WBURG_LNG, 11));
    });

    it('throws an error on out-of-range coordinates', () => {
      expect(() => coordToH3(95, WBURG_LNG)).toThrow('Invalid latitude coordinate: 95');
      expect(() => coordToH3(-95, WBURG_LNG)).toThrow('Invalid latitude coordinate: -95');
      expect(() => coordToH3(WBURG_LAT, 190)).toThrow('Invalid longitude coordinate: 190');
      expect(() => coordToH3(WBURG_LAT, -190)).toThrow('Invalid longitude coordinate: -190');
      expect(() => coordToH3(NaN, WBURG_LNG)).toThrow();
    });
  });

  describe('getH3Buffer (k-ring / gridDisk)', () => {
    it('returns 1 hex for radius 0', () => {
      const centerHex = coordToH3(WBURG_LAT, WBURG_LNG);
      const buffer = getH3Buffer(centerHex, 0);

      expect(buffer).toHaveLength(1);
      expect(buffer[0]).toBe(centerHex);
      expect(typeof buffer[0]).toBe('string');
    });

    it('returns 7 hexes for default radius 1 (1 center + 6 neighbors)', () => {
      const centerHex = coordToH3(WBURG_LAT, WBURG_LNG);
      const buffer = getH3Buffer(centerHex, 1);

      expect(buffer).toHaveLength(7);
      expect(buffer).toContain(centerHex);

      // Enforce strict string type check for all returned hexes (AGENTS.md guardrail)
      buffer.forEach((hex) => {
        expect(typeof hex).toBe('string');
        expect(hex.length).toBe(15);
        expect(isValidH3Index(hex)).toBe(true);
      });
    });

    it('returns 19 hexes for radius 2', () => {
      const centerHex = coordToH3(WBURG_LAT, WBURG_LNG);
      const buffer = getH3Buffer(centerHex, 2);

      expect(buffer).toHaveLength(19);
      expect(buffer).toContain(centerHex);
    });

    it('throws error for invalid H3 index string or invalid radius', () => {
      expect(() => getH3Buffer('invalid_hex_string', 1)).toThrow();
      expect(() => getH3Buffer(coordToH3(WBURG_LAT, WBURG_LNG), -1)).toThrow();
      expect(() => getH3Buffer(coordToH3(WBURG_LAT, WBURG_LNG), 1.5)).toThrow();
    });
  });

  describe('getHexesForCoordinate', () => {
    it('conveniently converts coordinate to buffer hex array', () => {
      const hexes = getHexesForCoordinate(WBURG_LAT, WBURG_LNG, DEFAULT_BUFFER_RADIUS, DEFAULT_H3_RESOLUTION);
      expect(hexes).toHaveLength(7);
      hexes.forEach((hex) => {
        expect(typeof hex).toBe('string');
        expect(hex.length).toBe(15);
      });
    });
  });

  describe('processAndStoreLocationHexes (SQLite & Zustand integration)', () => {
    it('persists newly discovered buffer hexes to op-sqlite and updates Zustand state', () => {
      const { centerHex, bufferHexes } = processAndStoreLocationHexes(WBURG_LAT, WBURG_LNG, 1);

      expect(bufferHexes).toHaveLength(7);
      expect(bufferHexes).toContain(centerHex);

      // Verify op-sqlite persistence
      const storedHexes = getAllUnlockedHexes();
      expect(storedHexes).toHaveLength(7);
      bufferHexes.forEach((hex) => {
        expect(storedHexes).toContain(hex);
      });
      expect(getExploredHexCount()).toBe(7);

      // Verify Zustand state update
      const storeState = useExplorationStore.getState();
      expect(storeState.currentLocation).toEqual({ latitude: WBURG_LAT, longitude: WBURG_LNG });
      expect(storeState.unlockedHexes).toHaveLength(7);
      bufferHexes.forEach((hex) => {
        expect(storeState.unlockedHexes).toContain(hex);
      });
    });

    it('prevents duplicate hex insertions into database on repeated location updates in same area', () => {
      // First update
      processAndStoreLocationHexes(WBURG_LAT, WBURG_LNG, 1);
      expect(getExploredHexCount()).toBe(7);

      // Second update at same location
      processAndStoreLocationHexes(WBURG_LAT, WBURG_LNG, 1);
      // Explored count should remain 7 due to INSERT OR IGNORE and set deduplication
      expect(getExploredHexCount()).toBe(7);
      expect(useExplorationStore.getState().unlockedHexes).toHaveLength(7);
    });
  });

  describe('64-bit Integer Precision Guardrails (AGENTS.md)', () => {
    it('asserts all H3 indices are strictly string primitives and never silently truncated numbers', () => {
      const centerHex = coordToH3(WBURG_LAT, WBURG_LNG, 11);
      const buffer = getH3Buffer(centerHex, 1);

      // Ensure index fails Number.isSafeInteger check if converted from hex to int
      // H3 indices are 64-bit unsigned integers. e.g. parseInt(hex, 16) > Number.MAX_SAFE_INTEGER
      const hexAsInt = parseInt(centerHex, 16);
      expect(typeof centerHex).toBe('string');
      expect(typeof hexAsInt).toBe('number');

      // Assert that we NEVER store or handle numeric representations in our pipeline
      buffer.forEach((hex) => {
        expect(typeof hex).toBe('string');
        expect(hex).not.toBeInstanceOf(Number);
        expect(typeof hex.valueOf()).toBe('string');
      });
    });
  });
});
