import Foundation
import GRDB

final class SpatialDatabaseManager {
    static let shared = SpatialDatabaseManager()
    
    let dbPool: DatabasePool
    
    private init() {
        do {
            let fileManager = FileManager.default
            let appSupportURL = try fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let databaseURL = appSupportURL.appendingPathComponent("derivee_spatial.sqlite")
            
            var configuration = Configuration()
            // Setting pragmas as specified in the blueprint
            configuration.prepareDatabase { db in
                try db.execute(sql: "PRAGMA synchronous = NORMAL;")
                try db.execute(sql: "PRAGMA busy_timeout = 5000;")
            }
            
            dbPool = try DatabasePool(path: databaseURL.path, configuration: configuration)
            try migrator.migrate(dbPool)
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
        
        return migrator
    }
    
    // Asynchronous write
    func insertDiscoveredHex(h3Index: String) async throws {
        try await dbPool.write { db in
            try db.execute(sql: """
                INSERT OR IGNORE INTO explored_hexes (h3_index)
                VALUES (?)
            """, arguments: [h3Index])
        }
    }
}
