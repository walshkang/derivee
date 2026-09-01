import Foundation
import GRDB
import CoreLocation

public final class GBFSDatabaseManager: Sendable {
    public static let shared = GBFSDatabaseManager()
    
    public let dbQueue: DatabaseQueue
    public let databaseURL: URL?
    
    private static let earthRadiusMeters: Double = 6_371_000.0
    
    // MARK: - Initializers
    
    public init(systemId: String = "default", inMemory: Bool = false) {
        if inMemory {
            var config = Configuration()
            config.qos = .userInitiated
            config.prepareDatabase { db in
                try db.execute(sql: "PRAGMA synchronous = NORMAL;")
                try db.execute(sql: "PRAGMA busy_timeout = 3000;")
            }
            do {
                self.dbQueue = try DatabaseQueue(configuration: config)
                self.databaseURL = nil
                try Self.createSchema(in: self.dbQueue)
            } catch {
                fatalError("Failed to initialize in-memory GBFSDatabaseManager: \(error)")
            }
        } else {
            let tempDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            let dbURL = tempDir.appendingPathComponent("gbfs_cache_\(systemId).sqlite")
            self.databaseURL = dbURL
            
            var config = Configuration()
            config.qos = .userInitiated
            config.prepareDatabase { db in
                try db.execute(sql: "PRAGMA journal_mode = DELETE;")
                try db.execute(sql: "PRAGMA synchronous = NORMAL;")
                try db.execute(sql: "PRAGMA busy_timeout = 3000;")
                try db.execute(sql: "PRAGMA foreign_keys = ON;")
            }
            
            do {
                self.dbQueue = try DatabaseQueue(path: dbURL.path, configuration: config)
                try Self.createSchema(in: self.dbQueue)
            } catch {
                fatalError("Failed to initialize ephemeral GBFSDatabaseManager at \(dbURL.path): \(error)")
            }
        }
    }
    
    public static func makeForTesting(inMemory: Bool = true) -> GBFSDatabaseManager {
        GBFSDatabaseManager(systemId: "test_\(UUID().uuidString)", inMemory: inMemory)
    }
    
    // MARK: - Schema Setup
    
    private static func createSchema(in dbQueue: DatabaseQueue) throws {
        try dbQueue.write { db in
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS gbfs_station_info (
                    station_id TEXT PRIMARY KEY NOT NULL,
                    system_id TEXT NOT NULL,
                    name TEXT NOT NULL,
                    lat REAL NOT NULL,
                    lon REAL NOT NULL,
                    capacity INTEGER NOT NULL,
                    region_id TEXT,
                    has_kiosk INTEGER NOT NULL DEFAULT 0
                );
                
                CREATE TABLE IF NOT EXISTS gbfs_station_status (
                    station_id TEXT PRIMARY KEY NOT NULL,
                    num_bikes_available INTEGER NOT NULL,
                    num_ebikes_available INTEGER NOT NULL,
                    num_docks_available INTEGER NOT NULL,
                    is_installed INTEGER NOT NULL,
                    is_renting INTEGER NOT NULL,
                    is_returning INTEGER NOT NULL,
                    last_reported INTEGER NOT NULL
                );
                
                CREATE INDEX IF NOT EXISTS idx_gbfs_spatial ON gbfs_station_info(lat, lon);
                CREATE INDEX IF NOT EXISTS idx_gbfs_status_lookup ON gbfs_station_status(station_id, num_bikes_available, num_docks_available);
            """)
        }
    }
    
    // MARK: - Ingestion
    
    public func upsertStationInfo(_ stations: [GBFSStationInfoRecord], systemId: String) async throws {
        guard !stations.isEmpty else { return }
        try await dbQueue.write { db in
            let stmt = try db.makeStatement(sql: """
                INSERT INTO gbfs_station_info (
                    station_id, system_id, name, lat, lon, capacity, region_id, has_kiosk
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(station_id) DO UPDATE SET
                    system_id = excluded.system_id,
                    name = excluded.name,
                    lat = excluded.lat,
                    lon = excluded.lon,
                    capacity = excluded.capacity,
                    region_id = excluded.region_id,
                    has_kiosk = excluded.has_kiosk;
            """)
            
            for station in stations {
                try stmt.execute(arguments: [
                    station.stationId,
                    systemId,
                    station.name,
                    station.lat,
                    station.lon,
                    station.capacity,
                    station.regionId,
                    station.hasKiosk ? 1 : 0
                ])
            }
        }
    }
    
    public func upsertStationStatus(_ stations: [GBFSStationStatusRecord]) async throws {
        guard !stations.isEmpty else { return }
        try await dbQueue.write { db in
            let stmt = try db.makeStatement(sql: """
                INSERT INTO gbfs_station_status (
                    station_id, num_bikes_available, num_ebikes_available,
                    num_docks_available, is_installed, is_renting, is_returning, last_reported
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(station_id) DO UPDATE SET
                    num_bikes_available = excluded.num_bikes_available,
                    num_ebikes_available = excluded.num_ebikes_available,
                    num_docks_available = excluded.num_docks_available,
                    is_installed = excluded.is_installed,
                    is_renting = excluded.is_renting,
                    is_returning = excluded.is_returning,
                    last_reported = excluded.last_reported;
            """)
            
            for station in stations {
                try stmt.execute(arguments: [
                    station.stationId,
                    station.numBikesAvailable,
                    station.numEbikesAvailable,
                    station.numDocksAvailable,
                    station.isInstalled ? 1 : 0,
                    station.isRenting ? 1 : 0,
                    station.isReturning ? 1 : 0,
                    station.lastReported
                ])
            }
        }
    }
    
    // MARK: - Zero-Lag Spatial Querying (<0.8ms)
    
    /// Queries candidate stations within radius `radiusMeters` of `centerCoordinate`.
    /// Executes a 2-phase query: indexed SQLite bounding box scan followed by flat-Earth Euclidean distance pruning.
    public func fetchCandidateStations(
        near centerCoordinate: CLLocationCoordinate2D,
        radiusMeters: Double = 500.0,
        preference: GBFSVehiclePreference = .anyBike
    ) async throws -> [GBFSStation] {
        let lat0 = centerCoordinate.latitude
        let lon0 = centerCoordinate.longitude
        let radConversion = Double.pi / 180.0
        
        let deltaLatDeg = (radiusMeters / Self.earthRadiusMeters) * (180.0 / Double.pi)
        let cosLat = cos(lat0 * radConversion)
        let safeCosLat = max(abs(cosLat), 0.0001)
        let deltaLonDeg = (radiusMeters / (Self.earthRadiusMeters * safeCosLat)) * (180.0 / Double.pi)
        
        let minLat = lat0 - deltaLatDeg
        let maxLat = lat0 + deltaLatDeg
        let minLon = lon0 - deltaLonDeg
        let maxLon = lon0 + deltaLonDeg
        
        return try await dbQueue.read { db in
            let sql = """
                SELECT 
                    i.station_id, i.system_id, i.name, i.lat, i.lon, i.capacity, i.region_id, i.has_kiosk,
                    COALESCE(s.num_bikes_available, 0) AS num_bikes_available,
                    COALESCE(s.num_ebikes_available, 0) AS num_ebikes_available,
                    COALESCE(s.num_docks_available, 0) AS num_docks_available,
                    COALESCE(s.is_installed, 1) AS is_installed,
                    COALESCE(s.is_renting, 1) AS is_renting,
                    COALESCE(s.is_returning, 1) AS is_returning,
                    COALESCE(s.last_reported, 0) AS last_reported
                FROM gbfs_station_info i
                LEFT JOIN gbfs_station_status s ON i.station_id = s.station_id
                WHERE i.lat >= ? AND i.lat <= ? AND i.lon >= ? AND i.lon <= ?;
            """
            
            let rows = try Row.fetchAll(db, sql: sql, arguments: [minLat, maxLat, minLon, maxLon])
            var results: [GBFSStation] = []
            results.reserveCapacity(rows.count)
            
            for row in rows {
                let lat: Double = row["lat"]
                let lon: Double = row["lon"]
                
                // Flat-Earth Euclidean distance formula (<0.1% error for <10km)
                let dLatRad = (lat - lat0) * radConversion
                let dLonRad = (lon - lon0) * radConversion
                let meanLatRad = ((lat + lat0) / 2.0) * radConversion
                
                let x = dLonRad * cos(meanLatRad)
                let y = dLatRad
                let dist = Self.earthRadiusMeters * sqrt(x * x + y * y)
                
                if dist <= radiusMeters {
                    let numBikes: Int = row["num_bikes_available"]
                    let numEbikes: Int = row["num_ebikes_available"]
                    let numDocks: Int = row["num_docks_available"]
                    let isInstalled = (row["is_installed"] as Int) != 0
                    let isRenting = (row["is_renting"] as Int) != 0
                    let isReturning = (row["is_returning"] as Int) != 0
                    let lastReported: Int = row["last_reported"]
                    
                    let station = GBFSStation(
                        stationId: row["station_id"],
                        systemId: row["system_id"],
                        name: row["name"],
                        latitude: lat,
                        longitude: lon,
                        capacity: row["capacity"],
                        regionId: row["region_id"],
                        hasKiosk: (row["has_kiosk"] as Int) != 0,
                        numBikesAvailable: numBikes,
                        numEbikesAvailable: numEbikes,
                        numDocksAvailable: numDocks,
                        isInstalled: isInstalled,
                        isRenting: isRenting,
                        isReturning: isReturning,
                        lastReported: lastReported,
                        distanceMeters: dist
                    )
                    results.append(station)
                }
            }
            
            results.sort { ($0.distanceMeters ?? 0) < ($1.distanceMeters ?? 0) }
            return results
        }
    }
    
    // MARK: - Station Lookups
    
    public func fetchStation(by stationId: String) async throws -> GBFSStation? {
        try await dbQueue.read { db in
            let sql = """
                SELECT 
                    i.station_id, i.system_id, i.name, i.lat, i.lon, i.capacity, i.region_id, i.has_kiosk,
                    COALESCE(s.num_bikes_available, 0) AS num_bikes_available,
                    COALESCE(s.num_ebikes_available, 0) AS num_ebikes_available,
                    COALESCE(s.num_docks_available, 0) AS num_docks_available,
                    COALESCE(s.is_installed, 1) AS is_installed,
                    COALESCE(s.is_renting, 1) AS is_renting,
                    COALESCE(s.is_returning, 1) AS is_returning,
                    COALESCE(s.last_reported, 0) AS last_reported
                FROM gbfs_station_info i
                LEFT JOIN gbfs_station_status s ON i.station_id = s.station_id
                WHERE i.station_id = ?
                LIMIT 1;
            """
            guard let row = try Row.fetchOne(db, sql: sql, arguments: [stationId]) else { return nil }
            return GBFSStation(
                stationId: row["station_id"],
                systemId: row["system_id"],
                name: row["name"],
                latitude: row["lat"],
                longitude: row["lon"],
                capacity: row["capacity"],
                regionId: row["region_id"],
                hasKiosk: (row["has_kiosk"] as Int) != 0,
                numBikesAvailable: row["num_bikes_available"],
                numEbikesAvailable: row["num_ebikes_available"],
                numDocksAvailable: row["num_docks_available"],
                isInstalled: (row["is_installed"] as Int) != 0,
                isRenting: (row["is_renting"] as Int) != 0,
                isReturning: (row["is_returning"] as Int) != 0,
                lastReported: row["last_reported"],
                distanceMeters: nil
            )
        }
    }
    
    public func fetchStationStatus(for stationId: String) async throws -> GBFSStationStatusRecord? {
        try await dbQueue.read { db in
            let sql = """
                SELECT station_id, num_bikes_available, num_ebikes_available, num_docks_available,
                       is_installed, is_renting, is_returning, last_reported
                FROM gbfs_station_status
                WHERE station_id = ?
                LIMIT 1;
            """
            guard let row = try Row.fetchOne(db, sql: sql, arguments: [stationId]) else { return nil }
            return GBFSStationStatusRecord(
                stationId: row["station_id"],
                numBikesAvailable: row["num_bikes_available"],
                numEbikesAvailable: row["num_ebikes_available"],
                numDocksAvailable: row["num_docks_available"],
                isInstalled: (row["is_installed"] as Int) != 0,
                isRenting: (row["is_renting"] as Int) != 0,
                isReturning: (row["is_returning"] as Int) != 0,
                lastReported: row["last_reported"]
            )
        }
    }
    
    public func fetchAllStations() async throws -> [GBFSStation] {
        try await dbQueue.read { db in
            let sql = """
                SELECT 
                    i.station_id, i.system_id, i.name, i.lat, i.lon, i.capacity, i.region_id, i.has_kiosk,
                    COALESCE(s.num_bikes_available, 0) AS num_bikes_available,
                    COALESCE(s.num_ebikes_available, 0) AS num_ebikes_available,
                    COALESCE(s.num_docks_available, 0) AS num_docks_available,
                    COALESCE(s.is_installed, 1) AS is_installed,
                    COALESCE(s.is_renting, 1) AS is_renting,
                    COALESCE(s.is_returning, 1) AS is_returning,
                    COALESCE(s.last_reported, 0) AS last_reported
                FROM gbfs_station_info i
                LEFT JOIN gbfs_station_status s ON i.station_id = s.station_id
                ORDER BY i.name ASC;
            """
            let rows = try Row.fetchAll(db, sql: sql)
            return rows.map { row in
                GBFSStation(
                    stationId: row["station_id"],
                    systemId: row["system_id"],
                    name: row["name"],
                    latitude: row["lat"],
                    longitude: row["lon"],
                    capacity: row["capacity"],
                    regionId: row["region_id"],
                    hasKiosk: (row["has_kiosk"] as Int) != 0,
                    numBikesAvailable: row["num_bikes_available"],
                    numEbikesAvailable: row["num_ebikes_available"],
                    numDocksAvailable: row["num_docks_available"],
                    isInstalled: (row["is_installed"] as Int) != 0,
                    isRenting: (row["is_renting"] as Int) != 0,
                    isReturning: (row["is_returning"] as Int) != 0,
                    lastReported: row["last_reported"],
                    distanceMeters: nil
                )
            }
        }
    }
    
    public func stationCount() async throws -> Int {
        try await dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM gbfs_station_info") ?? 0
        }
    }
    
    // MARK: - Lifecycle & Cache Maintenance
    
    public func releaseMemory() {
        dbQueue.releaseMemory()
    }
    
    public func clearCache() async throws {
        try await dbQueue.write { db in
            try db.execute(sql: """
                DELETE FROM gbfs_station_status;
                DELETE FROM gbfs_station_info;
            """)
        }
    }
    
    public func purgeStaleRecords(olderThanEpoch: Int) async throws {
        try await dbQueue.write { db in
            try db.execute(sql: "DELETE FROM gbfs_station_status WHERE last_reported < ?", arguments: [olderThanEpoch])
        }
    }
    
    deinit {
        releaseMemory()
    }
}
