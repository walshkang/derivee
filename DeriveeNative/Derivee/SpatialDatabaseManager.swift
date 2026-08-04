import Foundation
import GRDB

final class SpatialDatabaseManager: @unchecked Sendable {
    static let shared = SpatialDatabaseManager()
    
    let dbWriter: any DatabaseWriter
    
    init(inMemory: Bool = false) {
        do {
            let fileManager = FileManager.default
            let appSupportURL = try fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let databaseURL = appSupportURL.appendingPathComponent("derivee_spatial.sqlite")
            let transitDBURL = appSupportURL.appendingPathComponent("derivee_transit.sqlite")
            
            if let bundleURL = Bundle.main.url(forResource: "transit_delta", withExtension: "sqlite") ?? Bundle.main.url(forResource: "derivee_transit", withExtension: "sqlite") {
                print("Found transit DB in bundle at \(bundleURL)")
                do {
                    if fileManager.fileExists(atPath: transitDBURL.path) {
                        try fileManager.removeItem(at: transitDBURL)
                    }
                    try fileManager.copyItem(at: bundleURL, to: transitDBURL)
                    print("Successfully copied transit DB to \(transitDBURL)")
                } catch {
                    print("⚠️ Failed to copy transit DB: \(error)")
                }
            } else {
                print("⚠️ Could not find transit_delta.sqlite in main bundle")
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
    func insertDiscoveredHex(h3Index: String) async throws {
        try await dbWriter.write { db in
            try db.execute(sql: """
                INSERT OR IGNORE INTO explored_hexes (h3_index)
                VALUES (?)
            """, arguments: [h3Index])
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
}
