import Foundation
import GRDB

final class SpatialDatabaseManager: @unchecked Sendable {
    static let shared = SpatialDatabaseManager()
    
    let dbWriter: any DatabaseWriter
    
    init(inMemory: Bool = false, customTransitURL: URL? = nil) {
        do {
            let fileManager = FileManager.default
            let appSupportURL = try fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let databaseURL = appSupportURL.appendingPathComponent("derivee_spatial.sqlite")
            let transitDBURL = customTransitURL ?? appSupportURL.appendingPathComponent("derivee_transit.sqlite")
            let neighborhoodDBURL = appSupportURL.appendingPathComponent("derivee_neighborhood.sqlite")
            
            if customTransitURL == nil {
                if !fileManager.fileExists(atPath: transitDBURL.path) {
                    if let bundleURL = Bundle.main.url(forResource: "transit_delta", withExtension: "sqlite") ?? Bundle.main.url(forResource: "derivee_transit", withExtension: "sqlite") {
                        print("Found transit DB in bundle at \(bundleURL)")
                        do {
                            try fileManager.copyItem(at: bundleURL, to: transitDBURL)
                            print("Successfully copied transit DB to \(transitDBURL)")
                        } catch {
                            print("⚠️ Failed to copy transit DB: \(error)")
                        }
                    } else {
                        print("⚠️ Could not find transit_delta.sqlite in main bundle")
                    }
                }
            }
            
            if !fileManager.fileExists(atPath: neighborhoodDBURL.path) {
                if let nbhdURL = Bundle.main.url(forResource: "neighborhood", withExtension: "sqlite") {
                    print("Found neighborhood DB in bundle at \(nbhdURL)")
                    do {
                        try fileManager.copyItem(at: nbhdURL, to: neighborhoodDBURL)
                        print("Successfully copied neighborhood DB to \(neighborhoodDBURL)")
                    } catch {
                        print("⚠️ Failed to copy neighborhood DB: \(error)")
                    }
                } else {
                    print("⚠️ Could not find neighborhood.sqlite in main bundle")
                }
            }
            
            var configuration = Configuration()
            // Setting pragmas as specified in the blueprint
            configuration.prepareDatabase { db in
                try db.execute(sql: "PRAGMA synchronous = NORMAL;")
                try db.execute(sql: "PRAGMA busy_timeout = 5000;")
                
                if fileManager.fileExists(atPath: transitDBURL.path) {
                    do {
                        try db.execute(sql: "ATTACH DATABASE '\(transitDBURL.path)' AS transit")
                        print("Successfully attached transit database")
                    } catch {
                        print("⚠️ Failed to attach transit DB: \(error)")
                    }
                } else {
                    print("⚠️ No transit DB file to attach at \(transitDBURL)")
                }
                
                if fileManager.fileExists(atPath: neighborhoodDBURL.path) {
                    do {
                        try db.execute(sql: "ATTACH DATABASE '\(neighborhoodDBURL.path)' AS neighborhood")
                        print("Successfully attached neighborhood database")
                    } catch {
                        print("⚠️ Failed to attach neighborhood DB: \(error)")
                    }
                } else {
                    print("⚠️ No neighborhood DB file to attach at \(neighborhoodDBURL)")
                }
            }
            
            if inMemory {
                dbWriter = try DatabaseQueue(configuration: configuration)
            } else {
                dbWriter = try DatabasePool(path: databaseURL.path, configuration: configuration)
            }
            try migrator.migrate(dbWriter)
        } catch {
            fatalError("Failed to initialize database: \(error)")
        }
    }
    
    private var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        
        migrator.registerMigration("v1") { db in
            try db.create(table: "explored_hexes", options: .withoutRowID) { t in
                t.column("h3_index", .text).primaryKey()
            }
        }
        
        migrator.registerMigration("v2") { db in
            try db.create(table: "meta", options: .withoutRowID) { t in
                t.column("key", .text).primaryKey()
                t.column("value", .text)
            }
        }
        
        migrator.registerMigration("v3") { db in
            try db.create(table: "discovered_pois", options: .withoutRowID) { t in
                t.column("poi_id", .text).primaryKey()
            }
        }
        
        return migrator
    }
    
    // Asynchronous write
    @discardableResult
    func insertDiscoveredHex(h3Index: String) async throws -> Bool {
        return try await dbWriter.write { db in
            try db.execute(sql: """
                INSERT OR IGNORE INTO explored_hexes (h3_index)
                VALUES (?)
            """, arguments: [h3Index])
            return db.changesCount > 0
        }
    }
    
    func isHydrationComplete() -> Bool {
        do {
            return try dbWriter.read { db in
                let count = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM meta WHERE key = 'hydration_complete' AND value = '1'") ?? 0
                return count > 0
            }
        } catch {
            return false
        }
    }
    
    func setHydrationComplete() async throws {
        try await dbWriter.write { db in
            try db.execute(sql: "INSERT OR REPLACE INTO meta (key, value) VALUES ('hydration_complete', '1')")
        }
    }
    
    func clearLocalCache() async throws {
        try await dbWriter.write { db in
            try db.execute(sql: "DELETE FROM meta WHERE key = 'hydration_complete'")
        }
    }
    
    func resetExplorationData() async throws {
        try await dbWriter.write { db in
            try db.execute(sql: "DELETE FROM explored_hexes")
            try db.execute(sql: "DELETE FROM discovered_pois")
        }
    }
    
    func insertHexesBatch(h3Indices: [String]) async throws {
        try await dbWriter.write { db in
            for index in h3Indices {
                try db.execute(sql: "INSERT OR IGNORE INTO explored_hexes (h3_index) VALUES (?)", arguments: [index])
            }
        }
    }
    
    func loadDiscoveredPOIs() async throws -> Set<String> {
        return try await dbWriter.read { db in
            let rows = try String.fetchAll(db, sql: "SELECT poi_id FROM discovered_pois")
            return Set(rows)
        }
    }
    
    func insertDiscoveredPOI(_ id: String) async throws {
        try await dbWriter.write { db in
            try db.execute(sql: "INSERT OR IGNORE INTO discovered_pois (poi_id) VALUES (?)", arguments: [id])
        }
    }
    
    struct NeighborhoodProgress: Identifiable {
        let id: String
        let name: String
        let clearedHexes: Int
        let totalHexes: Int
        let centroidLat: Double
        let centroidLng: Double
        
        var percentage: Double {
            guard totalHexes > 0 else { return 0 }
            return (Double(clearedHexes) / Double(totalHexes)) * 100.0
        }
    }
    
    func fetchNeighborhoodProgression() async throws -> [NeighborhoodProgress] {
        return try await dbWriter.read { db in
            let sql = """
            SELECT 
                ns.id, 
                ns.name, 
                ns.total_hexes, 
                ns.centroid_lat,
                ns.centroid_lng,
                COUNT(eh.h3_index) as cleared_hexes
            FROM neighborhood.neighborhood_stats ns
            LEFT JOIN neighborhood.neighborhood_hexes nh ON ns.id = nh.neighborhood_id
            LEFT JOIN explored_hexes eh ON nh.h3_index = eh.h3_index
            GROUP BY ns.id, ns.name, ns.total_hexes, ns.centroid_lat, ns.centroid_lng
            ORDER BY cleared_hexes * 1.0 / ns.total_hexes DESC, ns.name ASC
            """
            
            let rows = try Row.fetchAll(db, sql: sql)
            return rows.map { row in
                NeighborhoodProgress(
                    id: row["id"],
                    name: row["name"],
                    clearedHexes: row["cleared_hexes"],
                    totalHexes: row["total_hexes"],
                    centroidLat: row["centroid_lat"],
                    centroidLng: row["centroid_lng"]
                )
            }
        }
    }
    
    func fetchNeighborhoodName(for h3Index: String) -> String? {
        do {
            return try dbWriter.read { db in
                let sql = """
                SELECT ns.name
                FROM neighborhood.neighborhood_hexes nh
                JOIN neighborhood.neighborhood_stats ns ON nh.neighborhood_id = ns.id
                WHERE nh.h3_index = ?
                """
                return try String.fetchOne(db, sql: sql, arguments: [h3Index])
            }
        } catch {
            print("⚠️ Failed to fetch neighborhood name: \(error)")
            return nil
        }
    }
    
    struct StopDetails {
        let stopId: String
        let name: String
        let routeId: String
        let routeType: Int
        let arrivals: [ArrivalInfo]
    }
    
    struct ArrivalInfo: Identifiable {
        let id = UUID()
        let line: String
        let destination: String
        let minutes: Int
    }
    
    func fetchStopDetails(for stopId: String) -> StopDetails {
        let startTime = CFAbsoluteTimeGetCurrent()
        defer {
            let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000.0
            print("⏱️ fetchStopDetails for \(stopId) executed in \(String(format: "%.2f", elapsed))ms")
        }
        
        do {
            return try dbWriter.read { db in
                if let row = try Row.fetchOne(db, sql: "SELECT stop_name FROM transit.stops WHERE stop_id = ?", arguments: [stopId]) {
                    let name = row["stop_name"] as? String ?? "Transit Station"
                    let routeType = 1
                    let routeId = inferRouteId(from: stopId, name: name)
                    
                    let arrivals = generateArrivals(for: routeId)
                    return StopDetails(stopId: stopId, name: name, routeId: routeId, routeType: routeType, arrivals: arrivals)
                }
                
                return StopDetails(
                    stopId: stopId,
                    name: "Transit Station (\(stopId))",
                    routeId: "L",
                    routeType: 1,
                    arrivals: [
                        ArrivalInfo(line: "L", destination: "Manhattan - 8th Ave", minutes: 3),
                        ArrivalInfo(line: "L", destination: "Brooklyn - Rockaway Pkwy", minutes: 7)
                    ]
                )
            }
        } catch {
            return StopDetails(
                stopId: stopId,
                name: "Station \(stopId)",
                routeId: "L",
                routeType: 1,
                arrivals: [
                    ArrivalInfo(line: "L", destination: "Manhattan - 8th Ave", minutes: 2),
                    ArrivalInfo(line: "L", destination: "Canarsie", minutes: 8)
                ]
            )
        }
    }
    
    func fetchHeadwayData(for stopId: String) -> [Double] {
        let startTime = CFAbsoluteTimeGetCurrent()
        defer {
            let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000.0
            print("⏱️ fetchHeadwayData for \(stopId) executed in \(String(format: "%.2f", elapsed))ms")
        }
        
        do {
            return try dbWriter.read { db in
                // Attempt query against transit delta historical headway table if available
                let sql = "SELECT headway_min FROM transit.headway_history WHERE stop_id = ? ORDER BY day_offset ASC LIMIT 7"
                let rows = try Double.fetchAll(db, sql: sql, arguments: [stopId])
                if !rows.isEmpty {
                    return rows
                }
                // Fallback realistic headway variation series
                return generateFallbackHeadways(for: stopId)
            }
        } catch {
            return generateFallbackHeadways(for: stopId)
        }
    }
    
    private func inferRouteId(from stopId: String, name: String) -> String {
        let upper = (stopId + " " + name).uppercased()
        if upper.contains("L") { return "L" }
        if upper.contains("G") { return "G" }
        if upper.contains("7") { return "7" }
        if upper.contains("A") || upper.contains("C") || upper.contains("E") { return "A" }
        if upper.contains("1") || upper.contains("2") || upper.contains("3") { return "1" }
        if upper.contains("4") || upper.contains("5") || upper.contains("6") { return "4" }
        if upper.contains("N") || upper.contains("Q") || upper.contains("R") { return "N" }
        return "L"
    }
    
    private func generateArrivals(for routeId: String) -> [ArrivalInfo] {
        switch routeId.uppercased() {
        case "G":
            return [
                ArrivalInfo(line: "G", destination: "Court Sq", minutes: 4),
                ArrivalInfo(line: "G", destination: "Church Ave", minutes: 9),
                ArrivalInfo(line: "G", destination: "Court Sq", minutes: 14)
            ]
        case "A", "C", "E":
            return [
                ArrivalInfo(line: "A", destination: "Uptown / 207 St", minutes: 2),
                ArrivalInfo(line: "C", destination: "Downtown / Brooklyn", minutes: 5),
                ArrivalInfo(line: "E", destination: "World Trade Center", minutes: 11)
            ]
        case "1", "2", "3":
            return [
                ArrivalInfo(line: "1", destination: "Van Cortlandt Park", minutes: 3),
                ArrivalInfo(line: "2", destination: "Flatbush Ave", minutes: 6),
                ArrivalInfo(line: "3", destination: "Harlem - 148 St", minutes: 12)
            ]
        default:
            return [
                ArrivalInfo(line: routeId, destination: "Manhattan - 8th Ave", minutes: 3),
                ArrivalInfo(line: routeId, destination: "Brooklyn - Rockaway Pkwy", minutes: 8),
                ArrivalInfo(line: routeId, destination: "Manhattan - 8th Ave", minutes: 15)
            ]
        }
    }
    
    private func generateFallbackHeadways(for stopId: String) -> [Double] {
        let hash = abs(stopId.hashValue)
        let base = 4.0 + Double(hash % 3)
        return [
            base + 0.3,
            base - 0.5,
            base + 1.2,
            base - 0.2,
            base + 0.8,
            base + 0.1,
            base - 0.4
        ]
    }
}

