import { open, OPSQLiteConnection, Transaction } from '@op-engineering/op-sqlite';

let dbInstance: OPSQLiteConnection | null = null;

export const DB_NAME = 'fog_of_wburg.db';

/**
 * Initializes the op-sqlite local database.
 * Sets WAL journal mode, synchronous NORMAL, and creates explored_hexes table WITHOUT ROWID.
 */
export function initDatabase(name: string = DB_NAME): OPSQLiteConnection {
  if (dbInstance) {
    return dbInstance;
  }

  const db = open({ name });

  // 1. Configure PRAGMAs for high-performance concurrent writes/reads
  db.execute('PRAGMA journal_mode = WAL;');
  db.execute('PRAGMA synchronous = NORMAL;');

  // 2. Create explored_hexes table enforcing WITHOUT ROWID and H3 string primary key (AGENTS.md guardrail)
  db.execute(`
    CREATE TABLE IF NOT EXISTS explored_hexes (
      h3_index TEXT PRIMARY KEY,
      discovered_at INTEGER NOT NULL
    ) WITHOUT ROWID;
  `);

  // 3. Create pois table (Gamification Wave 5)
  db.execute(`
    CREATE TABLE IF NOT EXISTS pois (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      description TEXT,
      latitude REAL NOT NULL,
      longitude REAL NOT NULL,
      h3_index TEXT NOT NULL,
      discovered INTEGER DEFAULT 0,
      reward_type TEXT
    ) WITHOUT ROWID;
  `);

  dbInstance = db;
  return db;
}

/**
 * Gets the current active database instance.
 * Automatically initializes the database if not already open.
 */
export function getDb(): OPSQLiteConnection {
  if (!dbInstance) {
    return initDatabase();
  }
  return dbInstance;
}

/**
 * Inserts a batch of unlocked H3 hexes into the database.
 * Uses INSERT OR IGNORE to skip hexes already discovered.
 * Strict type enforcement guarantees only valid strings are processed (AGENTS.md guardrail).
 */
export function insertUnlockedHexes(hexes: string[], timestamp: number = Date.now()): number {
  const db = getDb();

  // Strict string type assertion for 64-bit H3 indices
  const validHexes = hexes.filter((hex): hex is string => typeof hex === 'string' && hex.length > 0);

  if (validHexes.length === 0) {
    return 0;
  }

  let insertedCount = 0;

  if (typeof db.transaction === 'function') {
    db.transaction(async (tx: Transaction) => {
      for (const hex of validHexes) {
        const res = tx.execute('INSERT OR IGNORE INTO explored_hexes (h3_index, discovered_at) VALUES (?, ?);', [
          hex,
          timestamp,
        ]);
        if (res && typeof res.rowsAffected === 'number') {
          insertedCount += res.rowsAffected;
        }
      }
    });
  } else {
    for (const hex of validHexes) {
      const res = db.execute('INSERT OR IGNORE INTO explored_hexes (h3_index, discovered_at) VALUES (?, ?);', [
        hex,
        timestamp,
      ]);
      if (res && typeof res.rowsAffected === 'number') {
        insertedCount += res.rowsAffected;
      }
    }
  }

  return insertedCount;
}

/**
 * Retrieves all unlocked H3 index strings from the database.
 * Ensures returned array contains strictly valid strings.
 */
export function getAllUnlockedHexes(): string[] {
  const db = getDb();
  const result = db.execute('SELECT h3_index FROM explored_hexes;');

  let rows: Array<{ h3_index: string }> = [];

  if (result && result.rows) {
    if (Array.isArray(result.rows)) {
      rows = result.rows;
    } else if (Array.isArray(result.rows._array)) {
      rows = result.rows._array;
    } else if (typeof result.rows.item === 'function') {
      const len = result.rows.length || 0;
      for (let i = 0; i < len; i++) {
        rows.push(result.rows.item(i));
      }
    }
  }

  return rows
    .map((r) => r.h3_index)
    .filter((hex): hex is string => typeof hex === 'string' && hex.length > 0);
}

/**
 * Gets the total count of explored H3 hexes.
 */
export function getExploredHexCount(): number {
  const db = getDb();
  const result = db.execute('SELECT COUNT(*) as count FROM explored_hexes;');

  if (result && result.rows) {
    let row: any = null;
    if (Array.isArray(result.rows) && result.rows.length > 0) {
      row = result.rows[0];
    } else if (Array.isArray(result.rows._array) && result.rows._array.length > 0) {
      row = result.rows._array[0];
    } else if (typeof result.rows.item === 'function' && result.rows.length > 0) {
      row = result.rows.item(0);
    }

    if (row) {
      const val = row.count ?? row['COUNT(*)'];
      if (typeof val === 'number') return val;
      if (typeof val === 'string') return parseInt(val, 10);
    }
  }

  return 0;
}

/**
 * Closes the active database connection and resets the singleton instance.
 */
export function closeDatabase(): void {
  if (dbInstance) {
    if (typeof dbInstance.close === 'function') {
      dbInstance.close();
    }
    dbInstance = null;
  }
}
