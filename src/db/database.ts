import { open, OPSQLiteConnection, Transaction } from '@op-engineering/op-sqlite';
import * as FileSystem from 'expo-file-system';
import { Asset } from 'expo-asset';

let dbInstance: OPSQLiteConnection | null = null;

export const DB_NAME = 'fog_of_wburg.db';

export interface NeighborhoodStat {
  id: string;
  name: string;
  total_hexes: number;
  explored_hexes: number;
}

export interface GeoJSONCacheEntry {
  key: string;
  geojson_data: string;
  updated_at: number;
  hex_count: number;
}

/**
 * Runs database migrations based on PRAGMA user_version.
 */
export function runMigrations(db: OPSQLiteConnection): void {
  try {
    const res = db.execute('PRAGMA user_version;');
    let currentVersion = 0;
    if (res && res.rows) {
      let row: any = null;
      if (Array.isArray(res.rows) && res.rows.length > 0) row = res.rows[0];
      else if (Array.isArray(res.rows._array) && res.rows._array.length > 0) row = res.rows._array[0];
      else if (typeof res.rows.item === 'function' && res.rows.length > 0) row = res.rows.item(0);
      if (row) {
        currentVersion = row.user_version ?? row['user_version'] ?? 0;
      }
    }

    if (currentVersion < 1) {
      db.execute(`
        CREATE TABLE IF NOT EXISTS geojson_cache (
          key TEXT PRIMARY KEY,
          geojson_data TEXT NOT NULL,
          updated_at INTEGER NOT NULL,
          hex_count INTEGER NOT NULL DEFAULT 0
        ) WITHOUT ROWID;
      `);
      db.execute('PRAGMA user_version = 1;');
      console.log('[Database] Migrated database schema to version 1.');
    }
  } catch (error) {
    console.error('[Database] Failed to execute schema migrations:', error);
  }
}

/**
 * Initializes the op-sqlite local database.
 * Sets WAL journal mode, synchronous NORMAL, and creates tables WITHOUT ROWID.
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

  // W13-FOG: Create active_visibility table for reference counting
  db.execute(`
    CREATE TABLE IF NOT EXISTS active_visibility (
      h3_index TEXT PRIMARY KEY,
      reference_count INTEGER NOT NULL
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

  // 4. Create tracking_sessions table for Screen 3
  db.execute(`
    CREATE TABLE IF NOT EXISTS tracking_sessions (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      started_at INTEGER NOT NULL,
      hex_count INTEGER NOT NULL,
      distance_meters REAL NOT NULL,
      duration_seconds INTEGER NOT NULL,
      route_geojson TEXT
    ) WITHOUT ROWID;
  `);

  // W14.5: Create geojson_cache table WITHOUT ROWID
  db.execute(`
    CREATE TABLE IF NOT EXISTS geojson_cache (
      key TEXT PRIMARY KEY,
      geojson_data TEXT NOT NULL,
      updated_at INTEGER NOT NULL,
      hex_count INTEGER NOT NULL DEFAULT 0
    ) WITHOUT ROWID;
  `);

  // Execute version migrations
  runMigrations(db);

  dbInstance = db;
  return db;
}

/**
 * Gets the current active database instance.
 * Automatically initializes the database if not already open.
 */
export function getDb(): OPSQLiteConnection {
  if (dbInstance) {
    try {
      dbInstance.execute('PRAGMA user_version;');
      return dbInstance;
    } catch (e) {
      console.warn('[Database] Active dbInstance handle is closed or lost. Re-initializing...', e);
      dbInstance = null;
    }
  }
  return initDatabase();
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
 * Clears all explored hexes, active visibility records, and geojson_cache from the local SQLite database.
 */
export function clearExploredHexes(): void {
  const db = getDb();
  db.execute('DELETE FROM explored_hexes;');
  db.execute('DELETE FROM active_visibility;');
  db.execute('DELETE FROM geojson_cache;');
}

/**
 * Retrieves a GeoJSON cache entry by key.
 */
export function getGeoJSONCache(key: string): GeoJSONCacheEntry | null {
  try {
    const db = getDb();
    const result = db.execute('SELECT key, geojson_data, updated_at, hex_count FROM geojson_cache WHERE key = ?;', [key]);
    if (result && result.rows) {
      let row: any = null;
      if (Array.isArray(result.rows) && result.rows.length > 0) row = result.rows[0];
      else if (Array.isArray(result.rows._array) && result.rows._array.length > 0) row = result.rows._array[0];
      else if (typeof result.rows.item === 'function' && result.rows.length > 0) row = result.rows.item(0);

      if (row) {
        return {
          key: row.key,
          geojson_data: row.geojson_data,
          updated_at: typeof row.updated_at === 'number' ? row.updated_at : parseInt(row.updated_at, 10),
          hex_count: typeof row.hex_count === 'number' ? row.hex_count : parseInt(row.hex_count, 10),
        };
      }
    }
  } catch (error) {
    console.error('[Database] Failed to get GeoJSON cache for key:', key, error);
  }
  return null;
}

/**
 * Stores or updates a GeoJSON cache entry.
 */
export function setGeoJSONCache(key: string, geojsonData: string, hexCount: number, timestamp: number = Date.now()): void {
  try {
    const db = getDb();
    db.execute(
      `INSERT OR REPLACE INTO geojson_cache (key, geojson_data, updated_at, hex_count)
       VALUES (?, ?, ?, ?);`,
      [key, geojsonData, timestamp, hexCount]
    );
  } catch (error) {
    console.error('[Database] Failed to set GeoJSON cache for key:', key, error);
  }
}

/**
 * Clears GeoJSON cache entries. If key is provided, clears only that entry; otherwise clears all entries.
 */
export function clearGeoJSONCache(key?: string): void {
  try {
    const db = getDb();
    if (key) {
      db.execute('DELETE FROM geojson_cache WHERE key = ?;', [key]);
    } else {
      db.execute('DELETE FROM geojson_cache;');
    }
  } catch (error) {
    console.error('[Database] Failed to clear GeoJSON cache:', error);
  }
}

/**
 * Splash screen migration gate helper: Backfills geojson_cache for legacy users with explored hexes.
 * Returns true if backfill occurred or cache was already populated.
 */
export async function backfillLegacyGeoJSONCache(): Promise<boolean> {
  try {
    const existingCache = getGeoJSONCache('historical_fog');
    if (existingCache) {
      return true; // Already populated
    }

    const hexes = getAllUnlockedHexes();
    if (hexes.length === 0) {
      return true; // No legacy hexes to backfill
    }

    // Convert legacy explored hexes into cached MultiPolygon feature payload
    const h3 = require('h3-js');
    const validHexes = hexes.filter((hex) => {
      try {
        return typeof hex === 'string' && h3.isValidCell(hex);
      } catch {
        return false;
      }
    });

    if (validHexes.length === 0) {
      return true;
    }

    let holesCoordinates: number[][][][];
    try {
      holesCoordinates = h3.cellsToMultiPolygon(validHexes, true);
    } catch (e) {
      console.error('[Database] Error converting legacy hexes to MultiPolygon:', e);
      return false;
    }

    const payload = JSON.stringify({
      type: 'Feature',
      properties: {},
      geometry: {
        type: 'MultiPolygon',
        coordinates: holesCoordinates,
      },
    });

    setGeoJSONCache('historical_fog', payload, validHexes.length);
    console.log(`[Database] Backfilled legacy geojson_cache with ${validHexes.length} hexes.`);
    return true;
  } catch (error) {
    console.error('[Database] Failed to backfill legacy GeoJSON cache:', error);
    return false;
  }
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

/**
 * Attaches the downloaded historical transit sqlite database.
 */
export async function attachTransitDB(dbPath: string): Promise<void> {
  const db = getDb();
  try {
    // ATTACH DATABASE command
    db.execute(`ATTACH DATABASE '${dbPath}' AS transit_history;`);
    console.log('[Database] Attached transit_history successfully.');
  } catch (error) {
    console.error('[Database] Failed to attach transit_history db:', error);
    throw error;
  }
}

/**
 * Updates the active visibility reference count for a set of hexes.
 */
export function updateActiveVisibility(hexes: string[], increment: number): void {
  const db = getDb();
  const validHexes = hexes.filter((hex): hex is string => typeof hex === 'string' && hex.length > 0);

  if (validHexes.length === 0) return;

  if (typeof db.transaction === 'function') {
    db.transaction(async (tx: Transaction) => {
      for (const hex of validHexes) {
        tx.execute(
          `INSERT INTO active_visibility (h3_index, reference_count) 
           VALUES (?, ?) 
           ON CONFLICT(h3_index) 
           DO UPDATE SET reference_count = reference_count + ?;`,
          [hex, increment, increment]
        );
      }
      // Cleanup any that reached 0
      tx.execute('DELETE FROM active_visibility WHERE reference_count <= 0;');
    });
  } else {
    for (const hex of validHexes) {
      db.execute(
        `INSERT INTO active_visibility (h3_index, reference_count) 
         VALUES (?, ?) 
         ON CONFLICT(h3_index) 
         DO UPDATE SET reference_count = reference_count + ?;`,
        [hex, increment, increment]
      );
    }
    db.execute('DELETE FROM active_visibility WHERE reference_count <= 0;');
  }
}

/**
 * Retrieves all currently visible H3 index strings (reference_count > 0).
 */
export function getVisibleHexes(): string[] {
  const db = getDb();
  const result = db.execute('SELECT h3_index FROM active_visibility WHERE reference_count > 0;');

  let rows: Array<{ h3_index: string }> = [];
  if (result && result.rows) {
    if (Array.isArray(result.rows)) rows = result.rows;
    else if (Array.isArray(result.rows._array)) rows = result.rows._array;
    else if (typeof result.rows.item === 'function') {
      const len = result.rows.length || 0;
      for (let i = 0; i < len; i++) rows.push(result.rows.item(i));
    }
  }

  return rows
    .map((r) => r.h3_index)
    .filter((hex): hex is string => typeof hex === 'string' && hex.length > 0);
}

export interface TrackingSession {
  id: string;
  name: string;
  started_at: number;
  hex_count: number;
  distance_meters: number;
  duration_seconds: number;
  route_geojson?: string;
}

export function insertTrackingSession(session: TrackingSession): void {
  const db = getDb();
  db.execute(
    `INSERT OR REPLACE INTO tracking_sessions 
    (id, name, started_at, hex_count, distance_meters, duration_seconds, route_geojson) 
    VALUES (?, ?, ?, ?, ?, ?, ?);`,
    [
      session.id,
      session.name,
      session.started_at,
      session.hex_count,
      session.distance_meters,
      session.duration_seconds,
      session.route_geojson || null,
    ]
  );
}

export function getAllTrackingSessions(): TrackingSession[] {
  try {
    const db = getDb();
    const result = db.execute('SELECT * FROM tracking_sessions ORDER BY started_at DESC;');
    
    let rows: TrackingSession[] = [];
    if (result && result.rows) {
      if (Array.isArray(result.rows)) rows = result.rows as TrackingSession[];
      else if (Array.isArray(result.rows._array)) rows = result.rows._array as TrackingSession[];
      else if (typeof result.rows.item === 'function') {
        const len = result.rows.length || 0;
        for (let i = 0; i < len; i++) rows.push(result.rows.item(i));
      }
    }
    return rows;
  } catch (error) {
    console.error('[Database] Failed to get tracking sessions:', error);
    return [];
  }
}

/**
 * Wave 14: Attaches the static neighborhood stats database.
 * Uses a pre-populated SQLite DB generated by our Python scripts.
 */
export async function attachNeighborhoodDB(): Promise<void> {
  const db = getDb();
  try {
    const dbPath = FileSystem.documentDirectory + 'neighborhood.sqlite';
    let fileInfo = await FileSystem.getInfoAsync(dbPath);
    
    // If it exists but is suspiciously small (e.g. failed bundle from before), delete it
    if (fileInfo.exists && fileInfo.size && fileInfo.size < 1000) {
       await FileSystem.deleteAsync(dbPath);
       fileInfo = await FileSystem.getInfoAsync(dbPath);
    }

    if (!fileInfo.exists) {
       console.log('[Database] Copying neighborhood DB from bundle to documents...');
       const asset = Asset.fromModule(require('../../assets/neighborhood.sqlite'));
       await asset.downloadAsync();
       if (asset.localUri) {
          await FileSystem.copyAsync({ from: asset.localUri, to: dbPath });
       } else {
          await FileSystem.downloadAsync(asset.uri, dbPath);
       }
    }
    
    // op-sqlite requires a POSIX path, not a file:// URI
    const posixDbPath = dbPath.replace('file://', '');
    
    // Check if it's already attached
    const dbsResult = db.execute('PRAGMA database_list;');
    let isAlreadyAttached = false;
    if (dbsResult && dbsResult.rows) {
      let rows: any[] = [];
      if (Array.isArray(dbsResult.rows)) rows = dbsResult.rows;
      else if (Array.isArray(dbsResult.rows._array)) rows = dbsResult.rows._array;
      else if (typeof dbsResult.rows.item === 'function') {
        const len = dbsResult.rows.length || 0;
        for (let i = 0; i < len; i++) rows.push(dbsResult.rows.item(i));
      }
      
      for (const row of rows) {
        if (row.name === 'neighborhood_db') {
          isAlreadyAttached = true;
          break;
        }
      }
    }

    if (!isAlreadyAttached) {
      db.execute(`ATTACH DATABASE '${posixDbPath}' AS neighborhood_db;`);
      console.log('[Database] Attached neighborhood_db successfully.');
    } else {
      console.log('[Database] neighborhood_db is already attached. Skipping attach.');
    }
  } catch (error) {
    console.error('[Database] Failed to attach neighborhood_db:', error);
  }
}

/**
 * Wave 14: Calculates the explored completion percentage for all neighborhoods.
 * Uses an efficient inner join between the attached neighborhood mapping table and the user's explored_hexes.
 */
export function getNeighborhoodCompletion(): NeighborhoodStat[] {
  const db = getDb();
  
  try {
    const result = db.execute(`
      SELECT 
        n.id, 
        n.name, 
        n.total_hexes, 
        COUNT(e.h3_index) as explored_hexes
      FROM neighborhood_db.neighborhood_stats n
      JOIN neighborhood_db.neighborhood_hexes h ON n.id = h.neighborhood_id
      LEFT JOIN main.explored_hexes e ON h.h3_index = e.h3_index
      GROUP BY n.id
    `);

    let rows: any[] = [];
    if (result && result.rows) {
      if (Array.isArray(result.rows)) rows = result.rows;
      else if (Array.isArray(result.rows._array)) rows = result.rows._array;
      else if (typeof result.rows.item === 'function') {
        const len = result.rows.length || 0;
        for (let i = 0; i < len; i++) rows.push(result.rows.item(i));
      }
    }
    
    return rows.map((r: any) => ({
      id: r.id,
      name: r.name,
      total_hexes: typeof r.total_hexes === 'number' ? r.total_hexes : parseInt(r.total_hexes, 10),
      explored_hexes: typeof r.explored_hexes === 'number' ? r.explored_hexes : (r.explored_hexes ? parseInt(r.explored_hexes, 10) : 0)
    }));
  } catch (error) {
    console.error('[Database] Failed to get neighborhood completion:', error);
    return [];
  }
}

/**
 * Wave 14: Calculates the completion percentage for a specific neighborhood given a current H3 index.
 */
export function getCurrentNeighborhoodStat(h3Index: string): NeighborhoodStat | null {
  const db = getDb();
  
  try {
    const result = db.execute(`
      SELECT 
        n.id, 
        n.name, 
        n.total_hexes, 
        COUNT(e.h3_index) as explored_hexes
      FROM neighborhood_db.neighborhood_stats n
      JOIN neighborhood_db.neighborhood_hexes h ON n.id = h.neighborhood_id
      LEFT JOIN main.explored_hexes e ON h.h3_index = e.h3_index
      WHERE n.id = (SELECT neighborhood_id FROM neighborhood_db.neighborhood_hexes WHERE h3_index = ?)
      GROUP BY n.id
    `, [h3Index]);

    if (result && result.rows) {
      let row: any = null;
      if (Array.isArray(result.rows) && result.rows.length > 0) row = result.rows[0];
      else if (Array.isArray(result.rows._array) && result.rows._array.length > 0) row = result.rows._array[0];
      else if (typeof result.rows.item === 'function' && result.rows.length > 0) row = result.rows.item(0);
      
      if (row) {
        return {
          id: row.id,
          name: row.name,
          total_hexes: typeof row.total_hexes === 'number' ? row.total_hexes : parseInt(row.total_hexes, 10),
          explored_hexes: typeof row.explored_hexes === 'number' ? row.explored_hexes : (row.explored_hexes ? parseInt(row.explored_hexes, 10) : 0)
        };
      }
    }
  } catch (error) {
    console.warn('[Database] Failed to get current neighborhood stat:', error);
  }
  return null;
}

/**
 * Retrieves all hexes for the entire city (all neighborhoods) for the minimap outline.
 */
export function getAllCityHexes(): string[] {
  const db = getDb();
  
  try {
    const result = db.execute(`
      SELECT h3_index FROM neighborhood_db.neighborhood_hexes;
    `);

    let rows: Array<{ h3_index: string }> = [];
    if (result && result.rows) {
      if (Array.isArray(result.rows)) rows = result.rows;
      else if (Array.isArray(result.rows._array)) rows = result.rows._array;
      else if (typeof result.rows.item === 'function') {
        const len = result.rows.length || 0;
        for (let i = 0; i < len; i++) rows.push(result.rows.item(i));
      }
    }

    return rows
      .map((r) => r.h3_index)
      .filter((hex): hex is string => typeof hex === 'string' && hex.length > 0);
  } catch (error) {
    console.error('[Database] Failed to get city hexes:', error);
    return [];
  }
}

