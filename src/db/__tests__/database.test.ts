import {
  initDatabase,
  getDb,
  insertUnlockedHexes,
  getAllUnlockedHexes,
  getExploredHexCount,
  clearExploredHexes,
  closeDatabase,
  getGeoJSONCache,
  setGeoJSONCache,
  clearGeoJSONCache,
  backfillLegacyGeoJSONCache,
  runMigrations,
} from '../database';
import { open } from '@op-engineering/op-sqlite';

describe('Local Persistence Layer (op-sqlite JSI)', () => {
  beforeEach(() => {
    closeDatabase();
    const mockDb = (open as jest.Mock)();
    if (mockDb && mockDb._reset) {
      mockDb._reset();
    }
  });

  afterEach(() => {
    closeDatabase();
  });

  describe('Database Initialization & PRAGMAs', () => {
    it('initializes the database and configures WAL mode and WITHOUT ROWID schema', () => {
      const db = initDatabase('test_fog.db');
      expect(db).toBeDefined();

      const mockDb = (open as jest.Mock)();
      const executedQueries: string[] = mockDb._executedQueries;

      // Assert PRAGMAs (architecture.md Section 4 & AGENTS.md directives)
      expect(executedQueries).toContain('PRAGMA journal_mode = WAL;');
      expect(executedQueries).toContain('PRAGMA synchronous = NORMAL;');

      // Assert table creation with WITHOUT ROWID
      const tableCreationQuery = executedQueries.find((q) => q.includes('CREATE TABLE IF NOT EXISTS explored_hexes'));
      expect(tableCreationQuery).toBeDefined();
      expect(tableCreationQuery).toContain('WITHOUT ROWID');
      expect(tableCreationQuery).toContain('h3_index TEXT PRIMARY KEY');

      // W14.5-DB-MIGRATE: Assert geojson_cache table creation with WITHOUT ROWID
      const geojsonTableQuery = executedQueries.find((q) => q.includes('CREATE TABLE IF NOT EXISTS geojson_cache'));
      expect(geojsonTableQuery).toBeDefined();
      expect(geojsonTableQuery).toContain('WITHOUT ROWID');
      expect(geojsonTableQuery).toContain('key TEXT PRIMARY KEY');
    });

    it('returns the existing database instance on subsequent calls to getDb', () => {
      const db1 = initDatabase('test_fog.db');
      const db2 = getDb();
      expect(db1).toBe(db2);
    });
  });

  describe('W14.5-DB-MIGRATE: GeoJSON Cache & Migrations', () => {
    it('executes schema migration and updates PRAGMA user_version', () => {
      const db = initDatabase('test_fog.db');
      runMigrations(db);

      const mockDb = (open as jest.Mock)();
      const executedQueries: string[] = mockDb._executedQueries;
      expect(executedQueries.some((q) => q.includes('PRAGMA user_version = 1;'))).toBe(true);
    });

    it('stores, retrieves, and clears GeoJSON cache entries', () => {
      initDatabase('test_fog.db');
      const testKey = 'historical_fog';
      const testData = JSON.stringify({ type: 'Feature', geometry: { type: 'Polygon', coordinates: [] } });

      setGeoJSONCache(testKey, testData, 42);

      const cached = getGeoJSONCache(testKey);
      expect(cached).not.toBeNull();
      expect(cached?.key).toBe(testKey);
      expect(cached?.geojson_data).toBe(testData);
      expect(cached?.hex_count).toBe(42);

      clearGeoJSONCache(testKey);
      expect(getGeoJSONCache(testKey)).toBeNull();
    });

    it('backfills legacy explored hexes into geojson_cache behind splash gate', async () => {
      initDatabase('test_fog.db');
      const h3 = require('h3-js');
      const validHex1 = h3.latLngToCell(40.7128, -73.966, 11);
      const validHex2 = h3.latLngToCell(40.7130, -73.965, 11);
      insertUnlockedHexes([validHex1, validHex2]);

      expect(getGeoJSONCache('historical_fog')).toBeNull();

      const backfilled = await backfillLegacyGeoJSONCache();
      expect(backfilled).toBe(true);

      const cached = getGeoJSONCache('historical_fog');
      expect(cached).not.toBeNull();
      expect(cached?.hex_count).toBe(2);
      expect(cached?.geojson_data).toContain('MultiPolygon');
    });
  });

  describe('H3 Hex Operations & String Precision Guardrails', () => {
    it('inserts and retrieves H3 index strings with 64-bit precision preserved', () => {
      initDatabase('test_fog.db');

      const sampleHexes = ['8b2a100d213fff', '8b2a100d217fff', '8b2a100d21bfff'];
      const timestamp = 1700000000000;

      insertUnlockedHexes(sampleHexes, timestamp);

      const unlocked = getAllUnlockedHexes();
      expect(unlocked).toHaveLength(3);
      expect(unlocked).toEqual(expect.arrayContaining(sampleHexes));

      // AGENTS.md Guardrail: Assert every element is strictly a string
      unlocked.forEach((hex) => {
        expect(typeof hex).toBe('string');
      });

      expect(getExploredHexCount()).toBe(3);
    });

    it('ignores duplicate hex insertions (INSERT OR IGNORE)', () => {
      initDatabase('test_fog.db');

      const sampleHexes = ['8b2a100d213fff', '8b2a100d213fff', '8b2a100d217fff'];
      insertUnlockedHexes(sampleHexes);

      expect(getExploredHexCount()).toBe(2);
      expect(getAllUnlockedHexes()).toHaveLength(2);
    });

    it('filters out non-string or empty inputs to prevent integer truncation bugs', () => {
      initDatabase('test_fog.db');

      // Pass invalid types cast as string array to test runtime filter defense
      const mixedInputs = [
        '8b2a100d213fff',
        123456789012345 as any,
        '',
        null as any,
        undefined as any,
      ];

      insertUnlockedHexes(mixedInputs);

      const unlocked = getAllUnlockedHexes();
      expect(unlocked).toHaveLength(1);
      expect(unlocked[0]).toBe('8b2a100d213fff');
      expect(typeof unlocked[0]).toBe('string');
    });

    it('clears all explored hexes and geojson cache when clearExploredHexes is called', () => {
      initDatabase('test_fog.db');
      insertUnlockedHexes(['8b2a100d213fff', '8b2a100d217fff']);
      setGeoJSONCache('historical_fog', '{}', 2);
      expect(getExploredHexCount()).toBe(2);

      clearExploredHexes();

      expect(getExploredHexCount()).toBe(0);
      expect(getAllUnlockedHexes()).toEqual([]);
      expect(getGeoJSONCache('historical_fog')).toBeNull();
    });

    it('handles empty batch insertion gracefully without throwing errors', () => {
      initDatabase('test_fog.db');
      expect(() => insertUnlockedHexes([])).not.toThrow();
      expect(getExploredHexCount()).toBe(0);
    });
  });

  describe('Database Teardown', () => {
    it('resets database instance state upon closeDatabase', () => {
      const db1 = initDatabase('test_fog.db');
      expect(db1).toBeDefined();

      closeDatabase();

      const db2 = initDatabase('test_fog.db');
      expect(db2).toBeDefined();
    });
  });
});
