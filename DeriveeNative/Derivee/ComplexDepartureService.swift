import Foundation
import GRDB

// MARK: - Complex Departure Service (Doc 16 §2 & §3)

/// High-performance read-only departure query engine optimized for sub-0.10ms queries across station complexes.
/// Uses 2GB memory-mapped I/O, exclusive locking, zero-copy positional decoding, and clustered primary key range scans.
public final class ComplexDepartureService: @unchecked Sendable {
    public static let shared = ComplexDepartureService()
    
    private var dbPool: DatabasePool?
    private let lock = NSLock()
    private var currentDatabasePath: String?
    
    public init(databasePath: String? = nil, readonly: Bool = true) {
        if let path = databasePath {
            try? openPool(at: path, readonly: readonly)
        }
    }
    
    public init(dbPool: DatabasePool) {
        self.dbPool = dbPool
    }
    
    /// Opens or re-opens the high-performance memory-mapped connection pool.
    public func openPool(at databasePath: String, readonly: Bool = true) throws {
        lock.lock()
        defer { lock.unlock() }
        
        if let existing = dbPool {
            existing.releaseMemory()
            dbPool = nil
        }
        
        var config = Configuration()
        config.qos = .userInitiated
        config.readonly = readonly
        
        config.prepareDatabase { db in
            // Map up to 2GB of virtual memory to eliminate read() syscall overhead
            try db.execute(sql: "PRAGMA mmap_size = 2147483648;")
            // 64MB buffer cache for database pages
            try db.execute(sql: "PRAGMA cache_size = -64000;")
            // Maintain single exclusive lock handle across connection lifetime
            try db.execute(sql: "PRAGMA locking_mode = EXCLUSIVE;")
            // Force temporary sorting tables and intermediate structures into RAM
            try db.execute(sql: "PRAGMA temp_store = MEMORY;")
            if readonly {
                // Enable read-only query mode
                try db.execute(sql: "PRAGMA query_only = ON;")
            }
        }
        
        self.dbPool = try DatabasePool(path: databasePath, configuration: config)
        self.currentDatabasePath = databasePath
    }
    
    public func ensurePool() throws -> DatabasePool {
        lock.lock()
        defer { lock.unlock() }
        if let pool = dbPool {
            return pool
        }
        let defaultURL = SpatialDatabaseManager.shared.currentTransitDBURL 
            ?? CityPackManager.shared.transitDatabaseURL(for: "nyc")
        let path = defaultURL.path
        
        var config = Configuration()
        config.qos = .userInitiated
        config.readonly = true
        config.prepareDatabase { db in
            try db.execute(sql: "PRAGMA mmap_size = 2147483648;")
            try db.execute(sql: "PRAGMA cache_size = -64000;")
            try db.execute(sql: "PRAGMA locking_mode = EXCLUSIVE;")
            try db.execute(sql: "PRAGMA temp_store = MEMORY;")
            try db.execute(sql: "PRAGMA query_only = ON;")
        }
        let pool = try DatabasePool(path: path, configuration: config)
        self.dbPool = pool
        self.currentDatabasePath = path
        return pool
    }
    
    // MARK: - Sub-0.10ms Clustered Complex Departures Query (Doc 16 §3)
    
    /// Fetches chronological departures across an entire multi-modal station complex in sub-0.10ms.
    /// Traverses the clustered index B-tree leaf nodes with zero temporary B-tree allocations.
    public func fetchDepartures(
        complexId: Int64, 
        cutoffTime: Int64, 
        limit: Int = 30,
        in db: Database? = nil
    ) throws -> [ComplexDeparture] {
        if let db = db {
            return try executeFetchDepartures(complexId: complexId, cutoffTime: cutoffTime, limit: limit, in: db)
        }
        let pool = try ensurePool()
        return try pool.read { db in
            try self.executeFetchDepartures(complexId: complexId, cutoffTime: cutoffTime, limit: limit, in: db)
        }
    }
    
    private func executeFetchDepartures(
        complexId: Int64,
        cutoffTime: Int64,
        limit: Int,
        in db: Database
    ) throws -> [ComplexDeparture] {
        let statement = try db.cachedStatement(sql: """
            SELECT 
                complex_id,
                departure_time,
                feed_id,
                parent_station_id,
                child_stop_id,
                trip_id,
                route_id,
                route_short_name,
                direction_id,
                dynamic_terminal_stop_id,
                dynamic_terminal_name,
                is_express,
                COALESCE(actual_track, scheduled_track, '')
            FROM realtime_departures
            WHERE complex_id = ?
              AND departure_time >= ?
            ORDER BY departure_time ASC
            LIMIT ?
        """)
        
        return try ComplexDeparture.fetchAll(statement, arguments: [complexId, cutoffTime, limit])
    }
    
    // MARK: - Unified Serving Routes Resolution (Doc 16 §3)
    
    /// Fetches all distinct transit routes serving the station complex across all constituent platforms.
    public func fetchServingRoutes(
        complexId: Int64,
        in db: Database? = nil
    ) throws -> [ComplexServingRoute] {
        if let db = db {
            return try executeFetchServingRoutes(complexId: complexId, in: db)
        }
        let pool = try ensurePool()
        return try pool.read { db in
            try self.executeFetchServingRoutes(complexId: complexId, in: db)
        }
    }
    
    private func executeFetchServingRoutes(
        complexId: Int64,
        in db: Database
    ) throws -> [ComplexServingRoute] {
        let statement = try db.cachedStatement(sql: """
            SELECT DISTINCT
                sr.feed_id,
                rd.route_id,
                rd.route_short_name
            FROM stop_resolution sr
            JOIN realtime_departures rd 
                ON rd.complex_id = sr.complex_id
               AND rd.feed_id = sr.feed_id 
               AND rd.child_stop_id = sr.child_stop_id
            WHERE sr.complex_id = ?
            ORDER BY sr.feed_id ASC, rd.route_short_name ASC
        """)
        
        return try ComplexServingRoute.fetchAll(statement, arguments: [complexId])
    }
    
    // MARK: - Query Plan Explanation (Diagnostics)
    
    /// Explains the query plan for complex departure queries to verify zero temporary B-tree allocation.
    public func explainQueryPlan(
        complexId: Int64, 
        cutoffTime: Int64, 
        limit: Int = 30
    ) throws -> String {
        let pool = try ensurePool()
        return try pool.read { db in
            let rows = try Row.fetchAll(db, sql: """
                EXPLAIN QUERY PLAN
                SELECT 
                    complex_id,
                    departure_time,
                    feed_id,
                    parent_station_id,
                    child_stop_id,
                    trip_id,
                    route_id,
                    route_short_name,
                    direction_id,
                    dynamic_terminal_stop_id,
                    dynamic_terminal_name,
                    is_express,
                    COALESCE(actual_track, scheduled_track, '')
                FROM realtime_departures
                WHERE complex_id = ?
                  AND departure_time >= ?
                ORDER BY departure_time ASC
                LIMIT ?
            """, arguments: [complexId, cutoffTime, limit])
            
            return rows.compactMap { $0["detail"] as? String }.joined(separator: "\n")
        }
    }
    
    // MARK: - Mutation / Ingestion Helpers
    
    /// Creates the realtime_departures table and TTL index if needed (e.g. in-memory test databases).
    public static func createTableIfNeeded(in db: Database) throws {
        try db.execute(sql: """
            CREATE TABLE IF NOT EXISTS realtime_departures (
                complex_id               INTEGER NOT NULL,
                departure_time           INTEGER NOT NULL,
                feed_id                  TEXT    NOT NULL,
                parent_station_id        TEXT    NOT NULL,
                child_stop_id            TEXT    NOT NULL,
                trip_id                  TEXT    NOT NULL,
                route_id                 TEXT    NOT NULL,
                route_short_name         TEXT    NOT NULL,
                direction_id             INTEGER NOT NULL CHECK(direction_id IN (0, 1)),
                dynamic_terminal_stop_id TEXT    NOT NULL,
                dynamic_terminal_name    TEXT    NOT NULL,
                is_express               INTEGER NOT NULL DEFAULT 0 CHECK(is_express IN (0, 1)),
                scheduled_track          TEXT,
                actual_track             TEXT,
                updated_at               INTEGER NOT NULL,
                PRIMARY KEY (complex_id, departure_time, feed_id, child_stop_id, trip_id)
            ) WITHOUT ROWID;
            CREATE INDEX IF NOT EXISTS idx_realtime_departures_ttl 
            ON realtime_departures (departure_time);
        """)
    }
    
    /// Materializes departures into the clustered table.
    public func materializeDepartures(_ departures: [ComplexDeparture], in db: Database) throws {
        let statement = try db.cachedStatement(sql: """
            INSERT OR REPLACE INTO realtime_departures (
                complex_id, departure_time, feed_id, parent_station_id, child_stop_id,
                trip_id, route_id, route_short_name, direction_id,
                dynamic_terminal_stop_id, dynamic_terminal_name, is_express,
                scheduled_track, actual_track, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """)
        
        for d in departures {
            statement.arguments = [
                d.complexId,
                d.departureTime,
                d.feedId,
                d.parentStationId,
                d.childStopId,
                d.tripId,
                d.routeId,
                d.routeShortName,
                d.directionId,
                d.dynamicTerminalStopId,
                d.dynamicTerminalName,
                d.isExpress ? 1 : 0,
                d.track.isEmpty ? nil : d.track,
                d.track.isEmpty ? nil : d.track,
                d.updatedAt
            ]
            try statement.execute()
        }
    }
    
    /// Purges expired departures using the TTL index `idx_realtime_departures_ttl`.
    public func purgeExpiredDepartures(before cutoffTime: Int64, in db: Database) throws {
        try db.execute(sql: """
            DELETE FROM realtime_departures WHERE departure_time < ?
        """, arguments: [cutoffTime])
    }
    
    // MARK: - Multi-City Two-Phase Barrier Teardown (Wave L & Q)
    
    /// Releases database memory and closes the connection pool prior to city switching or app backgrounding.
    public func prepareForCitySwap() {
        lock.lock()
        defer { lock.unlock() }
        logPipeline("🛑 [ComplexDepartureService] prepareForCitySwap executing — releasing memory and closing connection pool")
        if let pool = dbPool {
            pool.releaseMemory()
            dbPool = nil
            currentDatabasePath = nil
        }
    }
    
    /// Updates the target transit database URL when switching cities.
    public func switchCity(to databaseURL: URL) {
        lock.lock()
        defer { lock.unlock() }
        logPipeline("🔄 [ComplexDepartureService] switchCity to \(databaseURL.lastPathComponent)")
        if let pool = dbPool {
            pool.releaseMemory()
            dbPool = nil
        }
        currentDatabasePath = databaseURL.path
    }
}
