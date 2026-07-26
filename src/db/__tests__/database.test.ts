import {
  initDatabase,
  getDb,
  insertUnlockedHexes,
  getAllUnlockedHexes,
  getExploredHexCount,
  closeDatabase,
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
    });

    it('returns the existing database instance on subsequent calls to getDb', () => {
      const db1 = initDatabase('test_fog.db');
      const db2 = getDb();
      expect(db1).toBe(db2);
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
