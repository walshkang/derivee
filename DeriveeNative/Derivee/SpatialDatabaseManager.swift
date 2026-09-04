import Foundation
import GRDB
import CoreLocation
import H3

public final class SpatialDatabaseManager: @unchecked Sendable {
    public private(set) static var isSharedInitialized: Bool = false
    public static let shared = SpatialDatabaseManager()
    
    public let dbWriter: any DatabaseWriter
    
    public var configuredQoS: DispatchQoS {
        dbWriter.configuration.qos
    }
    
    private let transitLock = NSLock()
    private var _currentTransitDBURL: URL?
    private var _currentNeighborhoodDBURL: URL?
    
    public var currentTransitDBURL: URL? {
        get {
            transitLock.lock()
            defer { transitLock.unlock() }
            return _currentTransitDBURL
        }
        set {
            transitLock.lock()
            defer { transitLock.unlock() }
            _currentTransitDBURL = newValue
        }
    }
    
    public var currentNeighborhoodDBURL: URL? {
        get {
            transitLock.lock()
            defer { transitLock.unlock() }
            return _currentNeighborhoodDBURL
        }
        set {
            transitLock.lock()
            defer { transitLock.unlock() }
            _currentNeighborhoodDBURL = newValue
        }
    }
    
#if DEBUG
    public static func makeForTesting(
        inMemory: Bool = true,
        customTransitURL: URL? = nil,
        customNeighborhoodURL: URL? = nil
    ) -> SpatialDatabaseManager {
        SpatialDatabaseManager(inMemory: inMemory, customTransitURL: customTransitURL, customNeighborhoodURL: customNeighborhoodURL)
    }
#endif

    private init(inMemory: Bool = false, customTransitURL: URL? = nil, customNeighborhoodURL: URL? = nil) {
        do {
            let fileManager = FileManager.default
            let appSupportURL = try fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let databaseURL = appSupportURL.appendingPathComponent("derivee_spatial.sqlite")
            let fallbackTransitURL = appSupportURL.appendingPathComponent("derivee_transit.sqlite")
            let defaultPackTransitURL = CityPackManager.shared.transitDatabaseURL(for: "nyc")
            let defaultPackNbhdURL = CityPackManager.shared.neighborhoodDatabaseURL(for: "nyc")
            let fallbackNeighborhoodURL = appSupportURL.appendingPathComponent("derivee_neighborhood.sqlite")
            
            // Ensure bundled NYC pack is unpacked and verified before setting up transit database attachment
            if customTransitURL == nil {
                try? CityPackManager.shared.ensureBundledPackExtracted()
            }
            
            let transitDBURL: URL
            if let custom = customTransitURL {
                transitDBURL = custom
            } else if CityPackManager.isValidDatabase(at: defaultPackTransitURL) {
                transitDBURL = defaultPackTransitURL
            } else {
                Self.copyBundleDatabaseIfNeeded(bundleResourceNames: ["derivee_transit", "transit_delta"], targetURL: fallbackTransitURL, fileManager: fileManager)
                transitDBURL = fallbackTransitURL
            }
            
            let neighborhoodDBURL: URL
            if let customNbhd = customNeighborhoodURL {
                neighborhoodDBURL = customNbhd
            } else if CityPackManager.isValidDatabase(at: defaultPackNbhdURL) {
                neighborhoodDBURL = defaultPackNbhdURL
            } else {
                Self.copyBundleDatabaseIfNeeded(bundleResourceNames: ["neighborhood"], targetURL: fallbackNeighborhoodURL, fileManager: fileManager)
                neighborhoodDBURL = fallbackNeighborhoodURL
            }
            
            _currentTransitDBURL = transitDBURL
            _currentNeighborhoodDBURL = neighborhoodDBURL
            
            var configuration = Configuration()
            configuration.qos = .userInitiated
            // Setting pragmas as specified in the blueprint
            configuration.prepareDatabase { db in
                try db.execute(sql: "PRAGMA synchronous = NORMAL;")
                try db.execute(sql: "PRAGMA busy_timeout = 5000;")
                
                // Only attach on reader connections during pool operation; writer is attached post-init to protect transit.sqlite from GRDB's WAL pragma
                if db.configuration.readonly {
                    if CityPackManager.isValidDatabase(at: transitDBURL) {
                        let escaped = transitDBURL.path.replacingOccurrences(of: "'", with: "''")
                        try? db.execute(sql: "ATTACH DATABASE '\(escaped)' AS transit;")
                    } else if CityPackManager.isValidDatabase(at: fallbackTransitURL) {
                        let escaped = fallbackTransitURL.path.replacingOccurrences(of: "'", with: "''")
                        try? db.execute(sql: "ATTACH DATABASE '\(escaped)' AS transit;")
                    }
                    
                    if CityPackManager.isValidDatabase(at: neighborhoodDBURL) || fileManager.fileExists(atPath: neighborhoodDBURL.path) {
                        let escaped = neighborhoodDBURL.path.replacingOccurrences(of: "'", with: "''")
                        try? db.execute(sql: "ATTACH DATABASE '\(escaped)' AS neighborhood;")
                    }
                }
            }
            
            if inMemory {
                let tempURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("derivee_test_\(UUID().uuidString).sqlite")
                dbWriter = try DatabasePool(path: tempURL.path, configuration: configuration)
            } else {
                dbWriter = try DatabasePool(path: databaseURL.path, configuration: configuration)
            }
            try migrator.migrate(dbWriter)
            
            // Attach transit and neighborhood on writer connection
            try? dbWriter.writeWithoutTransaction { db in
                try self.ensureTransitAttached(in: db, force: true)
                try self.ensureNeighborhoodAttached(in: db, force: true)
            }
            
            Self.isSharedInitialized = true
            print("🏦 [SpatialDatabaseManager] init complete for pool: \(ObjectIdentifier(dbWriter as AnyObject))")
        } catch {
            fatalError("Failed to initialize database: \(error)")
        }
    }
    
    private static func copyBundleDatabaseIfNeeded(bundleResourceNames: [String], targetURL: URL, fileManager: FileManager) {
        var sourceURL: URL? = nil
        for name in bundleResourceNames {
            if let url = Bundle.main.url(forResource: name, withExtension: "sqlite") {
                sourceURL = url
                break
            }
        }
        
        guard let bundleURL = sourceURL else {
            print("⚠️ Could not find \(bundleResourceNames.joined(separator: "/")).sqlite in main bundle")
            return
        }
        
        var shouldCopy = false
        if !fileManager.fileExists(atPath: targetURL.path) {
            shouldCopy = true
        } else {
            // 1. Compare file sizes and modification dates between bundle asset and cached local file
            do {
                let bundleAttrs = try fileManager.attributesOfItem(atPath: bundleURL.path)
                let targetAttrs = try fileManager.attributesOfItem(atPath: targetURL.path)
                let bundleSize = bundleAttrs[.size] as? Int64 ?? 0
                let targetSize = targetAttrs[.size] as? Int64 ?? 0
                
                if targetSize == 0 || (bundleSize > 0 && bundleSize != targetSize) {
                    print("Bundle \(bundleURL.lastPathComponent) size differs from local copy (\(bundleSize) vs \(targetSize)). Updating...")
                    shouldCopy = true
                } else if let bundleDate = bundleAttrs[.modificationDate] as? Date,
                          let targetDate = targetAttrs[.modificationDate] as? Date,
                          bundleDate > targetDate {
                    print("Bundle \(bundleURL.lastPathComponent) is newer than local copy (\(bundleDate) > \(targetDate)). Updating...")
                    shouldCopy = true
                }
            } catch {
                shouldCopy = true
            }
            
            // 2. Schema integrity check for neighborhood database specifically
            if !shouldCopy && bundleResourceNames.contains("neighborhood") {
                do {
                    let dbQueue = try DatabaseQueue(path: targetURL.path)
                    let hasCentroid = try dbQueue.read { db in
                        let rows = try Row.fetchAll(db, sql: "PRAGMA table_info(neighborhood_stats)")
                        return rows.contains { ($0["name"] as? String) == "centroid_lat" }
                    }
                    if !hasCentroid {
                        print("Local neighborhood DB is missing centroid_lat column. Re-copying from bundle...")
                        shouldCopy = true
                    }
                } catch {
                    print("Failed to inspect local neighborhood DB schema: \(error). Re-copying...")
                    shouldCopy = true
                }
            }
            
            // 3. Schema & record count integrity check for transit database
            if !shouldCopy && (bundleResourceNames.contains("derivee_transit") || bundleResourceNames.contains("transit_delta")) {
                do {
                    let dbQueue = try DatabaseQueue(path: targetURL.path)
                    let isValid = try dbQueue.read { db in
                        let stopsColumns = try Row.fetchAll(db, sql: "PRAGMA table_info(stops)")
                        let hasRoutes = stopsColumns.contains { ($0["name"] as? String) == "routes" }
                        let hasParentStation = stopsColumns.contains { ($0["name"] as? String) == "parent_station" }
                        let stopCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM stops") ?? 0
                        return hasRoutes && hasParentStation && stopCount >= 10000
                    }
                    if !isValid {
                        print("Local transit DB is missing routes/parent_station column or incomplete (<10k stops). Re-copying from bundle...")
                        shouldCopy = true
                    }
                } catch {
                    print("Failed to inspect local transit DB schema: \(error). Re-copying...")
                    shouldCopy = true
                }
            }
        }
        
        if shouldCopy {
            do {
                if fileManager.fileExists(atPath: targetURL.path) {
                    try fileManager.removeItem(at: targetURL)
                }
                try fileManager.copyItem(at: bundleURL, to: targetURL)
                print("Successfully copied \(bundleURL.lastPathComponent) to \(targetURL)")
            } catch {
                print("⚠️ Failed to copy \(bundleURL.lastPathComponent): \(error)")
            }
        }
    }

    
    private var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        
        migrator.registerMigration("v1") { db in
            try db.create(table: "explored_hexes") { t in
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
        
        migrator.registerMigration("v4") { db in
            // Rebuild explored_hexes to remove WITHOUT ROWID (fixes GRDB tracking bug)
            try db.create(table: "explored_hexes_new") { t in
                t.column("h3_index", .text).primaryKey()
            }
            try db.execute(sql: "INSERT INTO explored_hexes_new SELECT * FROM explored_hexes")
            try db.drop(table: "explored_hexes")
            try db.rename(table: "explored_hexes_new", to: "explored_hexes")
        }
        
        migrator.registerMigration("v5") { db in
            // Wave L-B.2: Zero-downtime schema migration from explored_hexes to explored_hexes_nyc
            let hasLegacy = try db.tableExists("explored_hexes")
            let hasNyc = try db.tableExists("explored_hexes_nyc")
            
            if hasLegacy && !hasNyc {
                try db.execute(sql: "ALTER TABLE explored_hexes RENAME TO explored_hexes_nyc;")
            } else if !hasNyc {
                try db.create(table: "explored_hexes_nyc") { t in
                    t.column("h3_index", .text).primaryKey()
                }
            }
            
            for slug in ["bos", "chi", "sf", "phl", "dc"] {
                let tbl = "explored_hexes_\(slug)"
                if try !db.tableExists(tbl) {
                    try db.create(table: tbl) { t in
                        t.column("h3_index", .text).primaryKey()
                    }
                }
            }
        }
        
        return migrator
    }
    
    // MARK: - Multi-City Table Helpers
    
    public static func tableName(for citySlug: String) -> String {
        let sanitized = citySlug.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return "explored_hexes_\(sanitized)"
    }
    
    public static func ensureExploredHexesTableExists(for citySlug: String, in db: Database) throws {
        let tbl = tableName(for: citySlug)
        try db.execute(sql: """
            CREATE TABLE IF NOT EXISTS \(tbl) (
                h3_index TEXT PRIMARY KEY
            );
        """)
    }
    
    /// Evaluates if a given H3 index resides on a terrestrial landmass or pedestrian bridge.
    /// Returns true if the hex is walkable land, or if no neighborhood mask is attached.
    public func isLandHex(h3Index: String, in db: Database) throws -> Bool {
        do {
            try self.ensureNeighborhoodAttached(in: db)
            let count = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM neighborhood.neighborhood_hexes WHERE h3_index = ? LIMIT 1", arguments: [h3Index]) ?? 0
            return count > 0
        } catch {
            // If neighborhood database is not attached (e.g. testing or unmounted metro pack), allow all hexes by default
            return true
        }
    }
    
    // MARK: - Transit & Neighborhood Database Hot-Swap (Wave L-B.3 & M.5.5)
    
    /// Ensures that the connection has the current target transit database attached.
    /// Performs an active health check on the attached transit schema and auto-heals stale or invalidated
    /// SQLite file descriptors (e.g. following city pack decompression / file replacement) to prevent disk I/O errors.
    public func ensureTransitAttached(in db: Database, force: Bool = false) throws {
        guard var targetURL = currentTransitDBURL else { return }
        
        // Validate target URL database integrity
        if !CityPackManager.isValidDatabase(at: targetURL) {
            // Attempt recovery if this is the NYC pack
            if targetURL.path.contains("/CityPacks/nyc") {
                try? CityPackManager.shared.ensureBundledPackExtracted()
            }
            
            if !CityPackManager.isValidDatabase(at: targetURL) {
                let fileManager = FileManager.default
                if let appSupportURL = try? fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false) {
                    let fallbackURL = appSupportURL.appendingPathComponent("derivee_transit.sqlite")
                    if CityPackManager.isValidDatabase(at: fallbackURL) {
                        targetURL = fallbackURL
                        currentTransitDBURL = fallbackURL
                    } else {
                        Self.copyBundleDatabaseIfNeeded(bundleResourceNames: ["derivee_transit", "transit_delta"], targetURL: fallbackURL, fileManager: fileManager)
                        if CityPackManager.isValidDatabase(at: fallbackURL) {
                            targetURL = fallbackURL
                            currentTransitDBURL = fallbackURL
                        }
                    }
                }
            }
        }
        
        guard CityPackManager.isValidDatabase(at: targetURL) else {
            return
        }
        
        let rows = try Row.fetchAll(db, sql: "PRAGMA database_list")
        let transitEntry = rows.first { ($0["name"] as? String) == "transit" }
        let attachedFile = transitEntry?["file"] as? String
        
        var needsReattach = force || (attachedFile != targetURL.path)
        
        // Proactive Health Probe: If transit is ostensibly attached to targetURL, verify the file handle is valid.
        if !needsReattach && transitEntry != nil {
            do {
                _ = try Row.fetchAll(db, sql: "PRAGMA transit.table_info(stops);")
            } catch {
                print("⚠️ [SpatialDatabaseManager] Transit schema probe failed (\(error)). Re-attaching database handle to \(targetURL.path)")
                needsReattach = true
            }
        }
        
        if needsReattach {
            if transitEntry != nil {
                try? db.execute(sql: "DETACH DATABASE transit;")
            }
            let escapedPath = targetURL.path.replacingOccurrences(of: "'", with: "''")
            try db.execute(sql: "ATTACH DATABASE '\(escapedPath)' AS transit;")
        }
    }
    
    /// Ensures that the connection has the current target neighborhood database attached.
    /// Performs an active health check on the attached neighborhood schema and auto-heals stale or invalidated handles.
    public func ensureNeighborhoodAttached(in db: Database, force: Bool = false) throws {
        let rows = try Row.fetchAll(db, sql: "PRAGMA database_list")
        let neighborhoodEntry = rows.first { ($0["name"] as? String) == "neighborhood" }
        let attachedFile = neighborhoodEntry?["file"] as? String
        
        guard let targetURL = currentNeighborhoodDBURL, FileManager.default.fileExists(atPath: targetURL.path) else {
            if neighborhoodEntry != nil {
                try? db.execute(sql: "DETACH DATABASE neighborhood;")
            }
            return
        }
        
        var needsReattach = force || (attachedFile != targetURL.path)
        
        if !needsReattach && neighborhoodEntry != nil {
            do {
                _ = try Row.fetchAll(db, sql: "PRAGMA neighborhood.table_info(neighborhood_stats);")
            } catch {
                print("⚠️ [SpatialDatabaseManager] Neighborhood schema probe failed (\(error)). Re-attaching handle to \(targetURL.path)")
                needsReattach = true
            }
        }
        
        if needsReattach {
            if neighborhoodEntry != nil {
                try? db.execute(sql: "DETACH DATABASE neighborhood;")
            }
            let escapedPath = targetURL.path.replacingOccurrences(of: "'", with: "''")
            try db.execute(sql: "ATTACH DATABASE '\(escapedPath)' AS neighborhood;")
        }
    }
    
    /// Ensures both transit and neighborhood databases are attached.
    public func ensureDatabasesAttached(in db: Database, force: Bool = false) throws {
        try ensureTransitAttached(in: db, force: force)
        try ensureNeighborhoodAttached(in: db, force: force)
    }

    
    /// Resolves platform stop IDs for a given parent or platform stop ID via stop_resolution or stops hierarchy.
    public func resolvePlatformStopIds(for stopId: String, in db: Database) -> [String] {
        var stopIds = [stopId]
        
        // 1. Try stop_resolution table
        do {
            let resColumns = try Row.fetchAll(db, sql: "PRAGMA transit.table_info(stop_resolution)")
            if !resColumns.isEmpty {
                let children = try String.fetchAll(db, sql: "SELECT child_stop_id FROM transit.stop_resolution WHERE parent_stop_id = ?", arguments: [stopId])
                for child in children {
                    if !stopIds.contains(child) {
                        stopIds.append(child)
                    }
                }
            }
        } catch {
            // Ignored
        }
        
        // 2. Try stops table parent_station join if stop_resolution had no extra rows
        if stopIds.count == 1 {
            do {
                let childStops = try String.fetchAll(db, sql: "SELECT stop_id FROM transit.stops WHERE parent_station = ?", arguments: [stopId])
                for child in childStops {
                    if !stopIds.contains(child) {
                        stopIds.append(child)
                    }
                }
            } catch {
                // Ignored
            }
        }
        
        // 3. Fallback platform directional suffixes if single ID
        if stopIds.count == 1 {
            for suffix in ["N", "S", "1", "2"] {
                let suffixed = "\(stopId)\(suffix)"
                if !stopIds.contains(suffixed) {
                    stopIds.append(suffixed)
                }
            }
        }
        
        return stopIds
    }
    
    /// Checks if the `transit` database schema is currently attached.
    public func isTransitAttached() async throws -> Bool {
        try await dbWriter.read { db in
            try self.ensureTransitAttached(in: db)
            let attached = try Row.fetchAll(db, sql: "PRAGMA database_list")
            return attached.contains { ($0["name"] as? String) == "transit" }
        }
    }
    
    /// Returns the file path of the currently attached `transit` database, if any.
    public func attachedTransitPath() async throws -> String? {
        try await dbWriter.read { db in
            try self.ensureTransitAttached(in: db)
            let attached = try Row.fetchAll(db, sql: "PRAGMA database_list")
            return attached.first { ($0["name"] as? String) == "transit" }?["file"] as? String
        }
    }
    
    /// Checks if the `neighborhood` database schema is currently attached.
    public func isNeighborhoodAttached() async throws -> Bool {
        try await dbWriter.read { db in
            try self.ensureNeighborhoodAttached(in: db)
            let attached = try Row.fetchAll(db, sql: "PRAGMA database_list")
            return attached.contains { ($0["name"] as? String) == "neighborhood" }
        }
    }
    
    /// Returns the file path of the currently attached `neighborhood` database, if any.
    public func attachedNeighborhoodPath() async throws -> String? {
        try await dbWriter.read { db in
            try self.ensureNeighborhoodAttached(in: db)
            let attached = try Row.fetchAll(db, sql: "PRAGMA database_list")
            return attached.first { ($0["name"] as? String) == "neighborhood" }?["file"] as? String
        }
    }
    
    /// Safely hot-swaps the attached `transit.sqlite` and `neighborhood.sqlite` databases using the Coordinated Two-Phase Barrier protocol.
    /// Drains memory/prepared statements across reader connections and executes DETACH/ATTACH/OPTIMIZE
    /// inside a serialized `writeWithoutTransaction` block to avoid SQLITE_LOCKED and 0xdead10cc.
    public func hotSwapCityDatabase(transitURL: URL, neighborhoodURL: URL? = nil) async throws {
        logPipeline("🔄 [SpatialDatabaseManager] Starting City DB Hot-Swap (Transit: \(transitURL.path), Neighborhood: \(neighborhoodURL?.path ?? "none"))")
        currentTransitDBURL = transitURL
        currentNeighborhoodDBURL = neighborhoodURL
        
        // 1. Drain internal caches and prepared statements across all reader connections in the GRDB pool
        if let pool = dbWriter as? DatabasePool {
            pool.releaseMemory()
        } else if let queue = dbWriter as? DatabaseQueue {
            queue.releaseMemory()
        }
        
        // 2. Execute DETACH + ATTACH + PRAGMA optimize inside serialized writeWithoutTransaction barrier
        try await dbWriter.writeWithoutTransaction { db in
            try self.ensureTransitAttached(in: db, force: true)
            try self.ensureNeighborhoodAttached(in: db, force: true)
            _ = try? db.execute(sql: "PRAGMA transit.optimize;")
            _ = try? db.execute(sql: "PRAGMA neighborhood.optimize;")
            logPipeline("✅ [SpatialDatabaseManager] City DB Hot-Swap complete & optimizers warmed")
        }
    }
    
    /// Convenience wrapper for transit-only hot swap.
    public func hotSwapTransitDatabase(to targetTransitDBURL: URL) async throws {
        try await hotSwapCityDatabase(transitURL: targetTransitDBURL, neighborhoodURL: currentNeighborhoodDBURL)
    }
    
    // Asynchronous write
    @discardableResult
    public func insertDiscoveredHex(h3Index: String, citySlug: String = "nyc", enforceLandOnly: Bool = true) async throws -> Bool {
        let table = Self.tableName(for: citySlug)
        return try await dbWriter.write { db in
            if enforceLandOnly {
                let isLand = try self.isLandHex(h3Index: h3Index, in: db)
                if !isLand {
                    // Strict Land-Only Fog Policy: Quiet water gliding (skip insert over open water)
                    return false
                }
            }
            
            try Self.ensureExploredHexesTableExists(for: citySlug, in: db)
            
            let exists = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \(table) WHERE h3_index = ?", arguments: [h3Index]) ?? 0
            if exists > 0 { return false }
            
            try db.execute(sql: """
                INSERT OR IGNORE INTO \(table) (h3_index)
                VALUES (?)
            """, arguments: [h3Index])
            return true
        }
    }
    
    public func isHydrationComplete() async throws -> Bool {
        return try await dbWriter.read { db in
            let count = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM meta WHERE key = 'hydration_complete' AND value = '1'") ?? 0
            return count > 0
        }
    }
    
    public func setHydrationComplete() async throws {
        try await dbWriter.write { db in
            try db.execute(sql: "INSERT OR REPLACE INTO meta (key, value) VALUES ('hydration_complete', '1')")
        }
    }
    
    public func clearLocalCache() async throws {
        try await dbWriter.write { db in
            try db.execute(sql: "DELETE FROM meta WHERE key = 'hydration_complete'")
        }
    }
    
    public func resetExplorationData(citySlug: String? = nil) async throws {
        try await dbWriter.write { db in
            if let slug = citySlug {
                let table = Self.tableName(for: slug)
                if try db.tableExists(table) {
                    try db.execute(sql: "DELETE FROM \(table)")
                }
            } else {
                let rows = try Row.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type='table' AND (name LIKE 'explored_hexes_%' OR name = 'explored_hexes')")
                for row in rows {
                    let name: String = row["name"]
                    try db.execute(sql: "DELETE FROM \(name)")
                }
                try db.execute(sql: "DELETE FROM discovered_pois")
            }
        }
    }
    
    public func fetchExploredHexes(citySlug: String = "nyc") async throws -> Set<String> {
        let table = Self.tableName(for: citySlug)
        return try await dbWriter.read { db in
            guard try db.tableExists(table) else { return [] }
            let rows = try String.fetchAll(db, sql: "SELECT h3_index FROM \(table)")
            return Set(rows)
        }
    }
    
    public func insertHexesBatch(h3Indices: [String], citySlug: String = "nyc", enforceLandOnly: Bool = false) async throws {
        let table = Self.tableName(for: citySlug)
        try await dbWriter.write { db in
            try Self.ensureExploredHexesTableExists(for: citySlug, in: db)
            for index in h3Indices {
                if enforceLandOnly {
                    let isLand = try self.isLandHex(h3Index: index, in: db)
                    if !isLand { continue }
                }
                try db.execute(sql: "INSERT OR IGNORE INTO \(table) (h3_index) VALUES (?)", arguments: [index])
            }
        }
    }
    
    /// Single atomic SQLite transaction partitioning and inserting hexes across multiple city tables.
    public func batchInsertMultiCityHexes(_ partitionedHexes: [String: [String]], enforceLandOnly: Bool = false) async throws {
        try await dbWriter.write { db in
            for (slug, hexList) in partitionedHexes {
                guard !hexList.isEmpty else { continue }
                try Self.ensureExploredHexesTableExists(for: slug, in: db)
                let table = Self.tableName(for: slug)
                
                for index in hexList {
                    if enforceLandOnly {
                        let isLand = try self.isLandHex(h3Index: index, in: db)
                        if !isLand { continue }
                    }
                    try db.execute(sql: "INSERT OR IGNORE INTO \(table) (h3_index) VALUES (?)", arguments: [index])
                }
            }
        }
    }
    
    /// Fetches total count of explored hexes for a specific city.
    func fetchExploredHexCount(citySlug: String) async throws -> Int {
        let table = Self.tableName(for: citySlug)
        return try await dbWriter.read { db in
            guard try db.tableExists(table) else { return 0 }
            return try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \(table)") ?? 0
        }
    }
    
    /// Aggregates exploration data across all cities for the Screen 3 "All Metros Summary" mode.
    func fetchAllMetrosSummary(
        installedSlugs: Set<String> = ["nyc"],
        manifest: CityManifest = .defaultManifest
    ) async throws -> AllMetrosSummaryData {
        return try await dbWriter.read { db in
            var cityOverviews: [CityOverviewProgress] = []
            var totalGlobalCleared = 0
            var totalGlobalHexes = 0
            var citiesExploredCount = 0
            
            // Baseline total hex counts per city (NYC known from neighborhood_stats, others estimated or configured)
            let cityTotalHexEstimates: [String: Int] = [
                "nyc": 362118,
                "bos": 115000,
                "chi": 220000
            ]
            
            for entry in manifest.cities {
                let slug = entry.slug
                let table = Self.tableName(for: slug)
                let hasTable = try db.tableExists(table)
                let clearedCount: Int
                if hasTable {
                    clearedCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \(table)") ?? 0
                } else {
                    clearedCount = 0
                }
                
                let isInstalled = installedSlugs.contains(slug) || entry.isBundled
                let totalHexes = cityTotalHexEstimates[slug] ?? 150000
                let centerCoord = entry.center?.coordinate ?? CLLocationCoordinate2D(latitude: 0, longitude: 0)
                
                if clearedCount > 0 {
                    citiesExploredCount += 1
                }
                
                totalGlobalCleared += clearedCount
                totalGlobalHexes += totalHexes
                
                let overview = CityOverviewProgress(
                    slug: slug,
                    displayName: entry.displayName,
                    region: entry.region,
                    clearedHexes: clearedCount,
                    totalHexes: totalHexes,
                    isInstalled: isInstalled,
                    centerCoordinate: centerCoord,
                    bounds: entry.bounds,
                    compressedSizeBytes: entry.compressedSizeBytes
                )
                cityOverviews.append(overview)
            }
            
            // Calculate total drift distance in km: Resolution 11 hex edge ~24.9m, average step spacing between consecutive unique hexes ~45m (0.045 km)
            let totalDriftKm = Double(totalGlobalCleared) * 0.045
            
            return AllMetrosSummaryData(
                totalGlobalClearedHexes: totalGlobalCleared,
                totalGlobalHexes: max(1, totalGlobalHexes),
                totalDriftDistanceKm: totalDriftKm,
                citiesExploredCount: citiesExploredCount,
                totalCitiesCount: max(1, manifest.cities.count),
                cityOverviews: cityOverviews
            )
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
    
    func fetchNeighborhoodProgression(citySlug: String = "nyc") async throws -> [NeighborhoodProgress] {
        let table = Self.tableName(for: citySlug)
        return try await dbWriter.read { db in
            try self.ensureNeighborhoodAttached(in: db)
            
            let statsRows: [Row]
            do {
                statsRows = try Row.fetchAll(db, sql: "SELECT id, name, total_hexes, centroid_lat, centroid_lng FROM neighborhood.neighborhood_stats")
            } catch {
                return []
            }
            
            guard !statsRows.isEmpty else { return [] }
            
            let hasTable = try db.tableExists(table)
            let clearedRows: [Row]
            if hasTable {
                clearedRows = (try? Row.fetchAll(db, sql: """
                SELECT nh.neighborhood_id, COUNT(eh.h3_index) as cleared_hexes
                FROM \(table) eh
                CROSS JOIN neighborhood.neighborhood_hexes nh ON eh.h3_index = nh.h3_index
                GROUP BY nh.neighborhood_id
                """)) ?? []
            } else {
                clearedRows = []
            }
            
            var clearedMap: [String: Int] = [:]
            for row in clearedRows {
                let nid: String = row["neighborhood_id"]
                let count: Int = row["cleared_hexes"]
                clearedMap[nid] = count
            }
            
            let list = statsRows.map { row -> NeighborhoodProgress in
                let nid: String = row["id"]
                let total: Int = row["total_hexes"]
                let name: String = row["name"]
                let lat: Double = row["centroid_lat"]
                let lng: Double = row["centroid_lng"]
                let cleared = clearedMap[nid] ?? 0
                return NeighborhoodProgress(
                    id: nid,
                    name: name,
                    clearedHexes: cleared,
                    totalHexes: max(1, total),
                    centroidLat: lat,
                    centroidLng: lng
                )
            }
            
            return list.sorted {
                let p1 = Double($0.clearedHexes) / Double($0.totalHexes)
                let p2 = Double($1.clearedHexes) / Double($1.totalHexes)
                if p1 != p2 { return p1 > p2 }
                return $0.name < $1.name
            }
        }
    }
    
    func fetchNeighborhoodName(for h3Index: String) async throws -> String? {
        return try await dbWriter.read { db in
            try self.ensureNeighborhoodAttached(in: db)
            let sql = """
            SELECT ns.name
            FROM neighborhood.neighborhood_hexes nh
            JOIN neighborhood.neighborhood_stats ns ON nh.neighborhood_id = ns.id
            WHERE nh.h3_index = ?
            """
            return try? String.fetchOne(db, sql: sql, arguments: [h3Index])
        }
    }
    
    func fetchExplorationJournalData(citySlug: String = "nyc") async throws -> ExplorationJournalData {
        let startTime = CFAbsoluteTimeGetCurrent()
        defer {
            let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000.0
            print("⏱️ fetchExplorationJournalData executed in \(String(format: "%.2f", elapsed))ms")
        }
        
        let table = Self.tableName(for: citySlug)
        let isNYC = (citySlug == "nyc")
        
        let cityTotalHexEstimates: [String: Int] = [
            "nyc": 362118,
            "bos": 56006,
            "chi": 220000
        ]
        
        return try await dbWriter.read { db in
            try self.ensureNeighborhoodAttached(in: db)
            let hasTable = try db.tableExists(table)
            // 1. Fetch all explored hexes and discovered POIs
            let exploredHexes: Set<String>
            if hasTable {
                exploredHexes = Set(try String.fetchAll(db, sql: "SELECT h3_index FROM \(table)"))
            } else {
                exploredHexes = []
            }
            let discoveredPOIs = Set(try String.fetchAll(db, sql: "SELECT poi_id FROM discovered_pois"))
            
            var totalCityHexes = cityTotalHexEstimates[citySlug] ?? 150000
            var boroughProgressList: [BoroughProgress] = []
            var totalExploredNbhdsCount = 0
            var totalNbhdsCount = 0
            
            // 2. Fetch neighborhood stats and cleared counts via fast indexed join
            let statsRows: [Row] = (try? Row.fetchAll(db, sql: "SELECT id, name, total_hexes FROM neighborhood.neighborhood_stats")) ?? []
            
            if !statsRows.isEmpty {
                let clearedRows: [Row]
                if hasTable {
                    clearedRows = (try? Row.fetchAll(db, sql: """
                    SELECT nh.neighborhood_id, COUNT(eh.h3_index) as cleared_hexes
                    FROM \(table) eh
                    CROSS JOIN neighborhood.neighborhood_hexes nh ON eh.h3_index = nh.h3_index
                    GROUP BY nh.neighborhood_id
                    """)) ?? []
                } else {
                    clearedRows = []
                }
                
                var clearedMap: [String: Int] = [:]
                for row in clearedRows {
                    let nid: String = row["neighborhood_id"]
                    let count: Int = row["cleared_hexes"]
                    clearedMap[nid] = count
                }
                
                if isNYC {
                    var boroughClearedMap: [String: Int] = ["MN": 0, "BK": 0, "QN": 0, "BX": 0, "SI": 0]
                    var boroughTotalMap: [String: Int] = ["MN": 0, "BK": 0, "QN": 0, "BX": 0, "SI": 0]
                    var boroughNbhdCountMap: [String: Int] = ["MN": 0, "BK": 0, "QN": 0, "BX": 0, "SI": 0]
                    var boroughExploredNbhdCountMap: [String: Int] = ["MN": 0, "BK": 0, "QN": 0, "BX": 0, "SI": 0]
                    var aggregatedCityHexes = 0
                    
                    for row in statsRows {
                        let id: String = row["id"]
                        let total: Int = row["total_hexes"]
                        let bCode = String(id.prefix(2)).uppercased()
                        let cleared = clearedMap[id] ?? 0
                        
                        boroughTotalMap[bCode, default: 0] += total
                        boroughClearedMap[bCode, default: 0] += cleared
                        boroughNbhdCountMap[bCode, default: 0] += 1
                        totalNbhdsCount += 1
                        
                        if cleared > 0 {
                            boroughExploredNbhdCountMap[bCode, default: 0] += 1
                            totalExploredNbhdsCount += 1
                        }
                        
                        aggregatedCityHexes += total
                    }
                    
                    if aggregatedCityHexes > 0 {
                        totalCityHexes = aggregatedCityHexes
                    }
                    
                    let boroughNames: [(code: String, name: String)] = [
                        ("MN", "Manhattan"),
                        ("BK", "Brooklyn"),
                        ("QN", "Queens"),
                        ("BX", "Bronx"),
                        ("SI", "Staten Island")
                    ]
                    
                    boroughProgressList = boroughNames.map { item in
                        BoroughProgress(
                            id: item.code,
                            name: item.name,
                            clearedHexes: boroughClearedMap[item.code] ?? 0,
                            totalHexes: max(1, boroughTotalMap[item.code] ?? 1),
                            neighborhoodCount: boroughNbhdCountMap[item.code] ?? 0,
                            exploredNeighborhoodCount: boroughExploredNbhdCountMap[item.code] ?? 0
                        )
                    }
                } else {
                    // Non-NYC metros (e.g. Boston): Group neighborhoods and aggregate total hexes
                    var aggregatedCityHexes = 0
                    totalNbhdsCount = statsRows.count
                    for row in statsRows {
                        let id: String = row["id"]
                        let total: Int = row["total_hexes"]
                        let cleared = clearedMap[id] ?? 0
                        aggregatedCityHexes += total
                        if cleared > 0 {
                            totalExploredNbhdsCount += 1
                        }
                    }
                    
                    if aggregatedCityHexes > 0 {
                        totalCityHexes = aggregatedCityHexes
                    }
                    
                    boroughProgressList = statsRows.map { row in
                        let id: String = row["id"]
                        let name: String = row["name"]
                        let total: Int = row["total_hexes"]
                        let cleared = clearedMap[id] ?? 0
                        return BoroughProgress(
                            id: id,
                            name: name,
                            clearedHexes: cleared,
                            totalHexes: max(1, total),
                            neighborhoodCount: 1,
                            exploredNeighborhoodCount: cleared > 0 ? 1 : 0
                        )
                    }.sorted {
                        let p1 = Double($0.clearedHexes) / Double($0.totalHexes)
                        let p2 = Double($1.clearedHexes) / Double($1.totalHexes)
                        if p1 != p2 { return p1 > p2 }
                        return $0.name < $1.name
                    }
                }
            }
            
            let totalClearedHexes = exploredHexes.count
            let overallCityPercentage = totalCityHexes > 0 ? min(100.0, (Double(totalClearedHexes) / Double(totalCityHexes)) * 100.0) : 0.0
            
            // 3. Transit Hubs milestone computation
            var totalTransitStations = 496
            var unlockedTransitStations = 0
            
            do {
                try self.ensureTransitAttached(in: db)
                let stopsSQL = "SELECT stop_id, stop_lat, stop_lon FROM transit.stops WHERE location_type = 1"
                let stopRows = try Row.fetchAll(db, sql: stopsSQL)
                if !stopRows.isEmpty {
                    totalTransitStations = stopRows.count
                    
                    // Precompute coordinates of explored hexes for ultra-fast spatial bounding-box filtering
                    var exploredCoords: [(lat: Double, lon: Double)] = []
                    for hStr in exploredHexes {
                        if let cell = UInt64(hStr, radix: 16), let coord = try? H3.cellToLatLng(cell: cell) {
                            exploredCoords.append((lat: coord.latitude, lon: coord.longitude))
                        }
                    }
                    
                    for stopRow in stopRows {
                        let stopId: String = stopRow["stop_id"]
                        let lat: Double = stopRow["stop_lat"]
                        let lon: Double = stopRow["stop_lon"]
                        if discoveredPOIs.contains(stopId) {
                            unlockedTransitStations += 1
                        } else if !exploredCoords.isEmpty {
                            // Fast bounding-box pre-filter (~50m delta) to avoid hundreds of expensive H3 conversions
                            let isNearExploredHex = exploredCoords.contains { abs(lat - $0.lat) < 0.0006 && abs(lon - $0.lon) < 0.0006 }
                            if isNearExploredHex {
                                let h3 = POIMaskManager.computeH3Index(latitude: lat, longitude: lon)
                                if exploredHexes.contains(h3) {
                                    unlockedTransitStations += 1
                                }
                            }
                        }
                    }
                }
            } catch {
                unlockedTransitStations = discoveredPOIs.count
            }
            
            let transitTiers: [MilestoneTier] = [
                MilestoneTier(category: .transitHubs, tierNumber: 1, title: "First Connection", requirementDescription: "Discover your first rail or subway station", targetCount: 1, badgeIconName: "tram.fill", isUnlocked: unlockedTransitStations >= 1),
                MilestoneTier(category: .transitHubs, tierNumber: 2, title: "Commuter", requirementDescription: "Connect 10 transit stations to the explored grid", targetCount: 10, badgeIconName: "figure.walk.arrival", isUnlocked: unlockedTransitStations >= 10),
                MilestoneTier(category: .transitHubs, tierNumber: 3, title: "Metro Explorer", requirementDescription: "Unlock 50 stations across multiple lines", targetCount: 50, badgeIconName: "map.fill", isUnlocked: unlockedTransitStations >= 50),
                MilestoneTier(category: .transitHubs, tierNumber: 4, title: "Transit Navigator", requirementDescription: "Discover 100 stations across the rail network", targetCount: 100, badgeIconName: "arrow.triangle.swap", isUnlocked: unlockedTransitStations >= 100),
                MilestoneTier(category: .transitHubs, tierNumber: 5, title: "Subway Maestro", requirementDescription: "Unlock 250 stations across the metropolitan network", targetCount: 250, badgeIconName: "star.fill", isUnlocked: unlockedTransitStations >= 250)
            ]
            
            let transitProgress = MilestoneProgress(
                category: .transitHubs,
                currentCount: unlockedTransitStations,
                totalCount: totalTransitStations,
                tiers: transitTiers
            )
            
            // 4. Neighborhood Voyager milestone computation
            let totalBoroughsVisited = boroughProgressList.filter { $0.exploredNeighborhoodCount > 0 }.count
            let voyagerTiers: [MilestoneTier] = [
                MilestoneTier(category: .neighborhoodVoyager, tierNumber: 1, title: "Local Drifter", requirementDescription: "Explore your very first neighborhood", targetCount: 1, badgeIconName: "location.fill", isUnlocked: totalExploredNbhdsCount >= 1),
                MilestoneTier(category: .neighborhoodVoyager, tierNumber: 2, title: "Borough Stepper", requirementDescription: "Explore neighborhoods in at least 3 districts", targetCount: 3, badgeIconName: "signpost.right.and.left.fill", isUnlocked: totalBoroughsVisited >= 3),
                MilestoneTier(category: .neighborhoodVoyager, tierNumber: 3, title: "Urban Cartographer", requirementDescription: "Map out 10 unique neighborhoods", targetCount: 10, badgeIconName: "square.grid.3x3.fill", isUnlocked: totalExploredNbhdsCount >= 10),
                MilestoneTier(category: .neighborhoodVoyager, tierNumber: 4, title: "Borough Master", requirementDescription: "Explore 25 neighborhoods across the city", targetCount: 25, badgeIconName: "globe.americas.fill", isUnlocked: totalExploredNbhdsCount >= 25),
                MilestoneTier(category: .neighborhoodVoyager, tierNumber: 5, title: "Metropolis Legend", requirementDescription: "Discover 50+ neighborhoods across the metropolitan area", targetCount: 50, badgeIconName: "crown.fill", isUnlocked: totalExploredNbhdsCount >= 50 && (isNYC ? totalBoroughsVisited == 5 : true))
            ]
            
            let voyagerProgress = MilestoneProgress(
                category: .neighborhoodVoyager,
                currentCount: totalExploredNbhdsCount,
                totalCount: max(1, totalNbhdsCount),
                tiers: voyagerTiers
            )
            
            // 5. Historic Landmarks milestone computation (NYC curated catalog)
            let landmarkCatalog = isNYC ? HistoricLandmarkCatalog.landmarks : []
            var landmarksList: [LandmarkDiscovery] = []
            var unlockedLandmarksCount = 0
            
            for item in landmarkCatalog {
                let h3 = item.h3Index
                let isDiscovered = exploredHexes.contains(h3) || discoveredPOIs.contains(item.id)
                if isDiscovered {
                    unlockedLandmarksCount += 1
                }
                landmarksList.append(LandmarkDiscovery(
                    id: item.id,
                    name: item.name,
                    borough: item.borough,
                    category: item.category,
                    landmarkDescription: item.description,
                    h3Index: h3,
                    coordinate: item.coordinate,
                    isDiscovered: isDiscovered
                ))
            }
            
            let landmarkTiers: [MilestoneTier] = [
                MilestoneTier(category: .historicLandmarks, tierNumber: 1, title: "Sightseer", requirementDescription: "Discover your first historic landmark", targetCount: 1, badgeIconName: "camera.fill", isUnlocked: unlockedLandmarksCount >= 1),
                MilestoneTier(category: .historicLandmarks, tierNumber: 2, title: "Cultural Wanderer", requirementDescription: "Uncover 3 architectural or cultural anchors", targetCount: 3, badgeIconName: "paintpalette.fill", isUnlocked: unlockedLandmarksCount >= 3),
                MilestoneTier(category: .historicLandmarks, tierNumber: 3, title: "Urban Historian", requirementDescription: "Map out 7 iconic city monuments", targetCount: 7, badgeIconName: "books.vertical.fill", isUnlocked: unlockedLandmarksCount >= 7),
                MilestoneTier(category: .historicLandmarks, tierNumber: 4, title: "Master Archivist", requirementDescription: "Discover 12 historic landmarks across the city", targetCount: 12, badgeIconName: "scroll.fill", isUnlocked: unlockedLandmarksCount >= 12),
                MilestoneTier(category: .historicLandmarks, tierNumber: 5, title: "Living Monument", requirementDescription: "Discover all curated landmarks in the city", targetCount: max(1, landmarkCatalog.count), badgeIconName: "sparkles", isUnlocked: landmarkCatalog.isEmpty ? false : unlockedLandmarksCount >= landmarkCatalog.count)
            ]
            
            let landmarkProgress = MilestoneProgress(
                category: .historicLandmarks,
                currentCount: unlockedLandmarksCount,
                totalCount: max(1, landmarkCatalog.count),
                tiers: landmarkTiers
            )
            
            var milestoneCards: [MilestoneProgress] = [transitProgress, voyagerProgress]
            if isNYC || !landmarksList.isEmpty {
                milestoneCards.append(landmarkProgress)
            }
            
            return ExplorationJournalData(
                totalClearedHexes: totalClearedHexes,
                totalCityHexes: totalCityHexes,
                cityPercentage: overallCityPercentage,
                milestoneCards: milestoneCards,
                boroughProgress: boroughProgressList,
                landmarks: landmarksList
            )
        }
    }
    
    public struct StopDetails: Sendable {
        public let stopId: String
        public let name: String
        public let routeId: String
        public let routeIds: [String]
        public let routeType: Int // GTFS route_type (0: LRT, 1: Subway, 2: Rail, 3: Bus, 4: Ferry, etc.)
        public let modalClass: TransitModalClass
        public let arrivals: [ArrivalInfo]
        
        public init(
            stopId: String,
            name: String,
            routeId: String,
            routeIds: [String] = [],
            routeType: Int,
            modalClass: TransitModalClass? = nil,
            arrivals: [ArrivalInfo]
        ) {
            self.stopId = stopId
            self.name = name
            self.routeId = routeId
            self.routeIds = routeIds.isEmpty ? [routeId] : routeIds
            self.routeType = routeType
            self.modalClass = modalClass ?? TransitModalClass.from(routeType: routeType)
            self.arrivals = arrivals
        }
    }
    
    public struct HourlyReliabilityRecord: Identifiable, Sendable, Equatable {
        public var id: String { "\(routeId)_\(stopId)_\(directionId)_\(dayOfWeek)_\(hourOfDay)" }
        public let routeId: String
        public let stopId: String
        public let directionId: Int
        public let hourOfDay: Int // 0..23
        public let dayOfWeek: Int // 0..6 (0 = Sunday, 1 = Monday, ... 6 = Saturday)
        public let medianDelaySec: Int
        public let p90DelaySec: Int
        public let medianHeadwaySec: Int
        public let headwayStdDevSec: Int
        public let ewtSeconds: Double
        public let onTimePct: Double // 0..100
        public let sampleCount: Int
        
        public init(
            routeId: String,
            stopId: String,
            directionId: Int = 0,
            hourOfDay: Int,
            dayOfWeek: Int,
            medianDelaySec: Int,
            p90DelaySec: Int,
            medianHeadwaySec: Int = 300,
            headwayStdDevSec: Int = 60,
            ewtSeconds: Double = 60.0,
            onTimePct: Double,
            sampleCount: Int
        ) {
            self.routeId = routeId
            self.stopId = stopId
            self.directionId = directionId
            self.hourOfDay = hourOfDay
            self.dayOfWeek = dayOfWeek
            self.medianDelaySec = medianDelaySec
            self.p90DelaySec = p90DelaySec
            self.medianHeadwaySec = medianHeadwaySec
            self.headwayStdDevSec = headwayStdDevSec
            self.ewtSeconds = ewtSeconds
            self.onTimePct = onTimePct
            self.sampleCount = sampleCount
        }
    }
    
    public struct StopEventRecord: Identifiable, Sendable, Equatable {
        public let eventId: String
        public var id: String { eventId }
        public let tripId: String
        public let routeId: String
        public let stopId: String
        public let scheduledTime: Date?
        public let actualTime: Date
        public let delaySeconds: Int
        public let observedAt: Date
        public let directionId: Int
        
        public init(
            eventId: String,
            tripId: String,
            routeId: String,
            stopId: String,
            scheduledTime: Date?,
            actualTime: Date,
            delaySeconds: Int,
            observedAt: Date,
            directionId: Int = 0
        ) {
            self.eventId = eventId
            self.tripId = tripId
            self.routeId = routeId
            self.stopId = stopId
            self.scheduledTime = scheduledTime
            self.actualTime = actualTime
            self.delaySeconds = delaySeconds
            self.observedAt = observedAt
            self.directionId = directionId
        }
    }
    
    public enum ScheduleRelationship: Int, Sendable, Codable, Equatable {
        case scheduled = 0
        case added = 1
        case unscheduled = 2
        case canceled = 3
        case duplicated = 4
    }
    
    public struct DeparturePillRecord: Identifiable, Sendable, Equatable {
        public let id: String
        public let tripId: String
        public let routeId: String
        public let destination: String
        public let directionId: Int
        public let minute: Int
        public let isExpress: Bool
        public let isFirstDeparture: Bool
        public let isLastDeparture: Bool
        public var liveDeltaMinutes: Int?
        public var delaySeconds: Int?
        public var isLive: Bool
        public var isPast: Bool
        public var isUnscheduled: Bool
        public var isBoarding: Bool
        public var isImminentLive: Bool
        public var isNextDeparture: Bool
        public var scheduleRelationship: ScheduleRelationship
        public var isHistoricalEvent: Bool
        public var historicalDelaySeconds: Int?
        
        public init(
            id: String,
            tripId: String,
            routeId: String,
            destination: String,
            directionId: Int = 0,
            minute: Int,
            isExpress: Bool = false,
            isFirstDeparture: Bool = false,
            isLastDeparture: Bool = false,
            liveDeltaMinutes: Int? = nil,
            delaySeconds: Int? = nil,
            isLive: Bool = false,
            isPast: Bool = false,
            isUnscheduled: Bool = false,
            isBoarding: Bool = false,
            isImminentLive: Bool = false,
            isNextDeparture: Bool = false,
            scheduleRelationship: ScheduleRelationship = .scheduled,
            isHistoricalEvent: Bool = false,
            historicalDelaySeconds: Int? = nil
        ) {
            self.id = id
            self.tripId = tripId
            self.routeId = routeId
            self.destination = destination
            self.directionId = directionId
            self.minute = minute
            self.isExpress = isExpress
            self.isFirstDeparture = isFirstDeparture
            self.isLastDeparture = isLastDeparture
            self.liveDeltaMinutes = liveDeltaMinutes
            self.delaySeconds = delaySeconds
            self.isLive = isLive
            self.isPast = isPast
            self.isUnscheduled = isUnscheduled
            self.isBoarding = isBoarding
            self.isImminentLive = isImminentLive
            self.isNextDeparture = isNextDeparture
            self.scheduleRelationship = scheduleRelationship
            self.isHistoricalEvent = isHistoricalEvent
            self.historicalDelaySeconds = historicalDelaySeconds
        }
    }
    
    public struct HourScheduleRecord: Identifiable, Sendable, Equatable {
        public var id: Int { hourOfDay }
        public let hourOfDay: Int
        public var departures: [DeparturePillRecord]
        
        public init(hourOfDay: Int, departures: [DeparturePillRecord]) {
            self.hourOfDay = hourOfDay
            self.departures = departures
        }
    }
    
    public struct TimetableResult: Sendable, Equatable {
        public let records: [HourScheduleRecord]
        public let isHistoricalFallback: Bool
        public let isObservedReplay: Bool
        public let totalDepartures: Int
        
        public init(
            records: [HourScheduleRecord],
            isHistoricalFallback: Bool = false,
            isObservedReplay: Bool = false,
            totalDepartures: Int? = nil
        ) {
            self.records = records
            self.isHistoricalFallback = isHistoricalFallback
            self.isObservedReplay = isObservedReplay
            self.totalDepartures = totalDepartures ?? records.reduce(0) { $0 + $1.departures.count }
        }
    }
    
    public struct ArrivalInfo: Identifiable, Sendable {
        public let id: UUID
        public let line: String
        public let destination: String
        public let minutes: Int
        public let direction: String?
        public let distanceDescription: String?
        public let arrivalDate: Date
        public let tripId: String?
        public let scheduleRelationship: ScheduleRelationship
        public let isHoldingStation: Bool
        public let progressLambda: Double
        public let isAssigned: Bool
        
        public init(
            id: UUID = UUID(),
            line: String,
            destination: String,
            minutes: Int,
            direction: String? = nil,
            distanceDescription: String? = nil,
            arrivalDate: Date = Date(),
            tripId: String? = nil,
            scheduleRelationship: ScheduleRelationship = .scheduled,
            isHoldingStation: Bool = false,
            progressLambda: Double = 0.0,
            isAssigned: Bool = false
        ) {
            self.id = id
            self.line = line
            self.destination = destination
            self.minutes = minutes
            self.direction = direction
            self.distanceDescription = distanceDescription
            self.arrivalDate = arrivalDate
            self.tripId = tripId
            self.scheduleRelationship = scheduleRelationship
            self.isHoldingStation = isHoldingStation
            self.progressLambda = progressLambda
            self.isAssigned = isAssigned
        }
    }
    
    public struct NearbyBusStop: Identifiable, Sendable {
        public let id: String
        public let name: String
        public let coordinate: CLLocationCoordinate2D
        public let distanceMeters: Double
        public let routes: [String]
        public let direction: String
        
        public init(id: String, name: String, coordinate: CLLocationCoordinate2D, distanceMeters: Double, routes: [String], direction: String) {
            self.id = id
            self.name = name
            self.coordinate = coordinate
            self.distanceMeters = distanceMeters
            self.routes = routes
            self.direction = direction
        }
    }
    
    /// Queries bus stops within a specified radius (default 400m) from user's current GPS location
    public func fetchNearbyBusStops(coordinate: CLLocationCoordinate2D, radiusMeters: Double = 400.0) async throws -> [NearbyBusStop] {
        let startTime = CFAbsoluteTimeGetCurrent()
        defer {
            let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000.0
            print("⏱️ fetchNearbyBusStops executed in \(String(format: "%.2f", elapsed))ms")
        }
        
        return try await dbWriter.read { db in
            // Lat/lon degree deltas for initial spatial bounding box filter (~0.005 deg ≈ 550m)
            let latDelta = (radiusMeters / 111_000.0) * 1.2
            let lonDelta = (radiusMeters / (111_000.0 * cos(coordinate.latitude * .pi / 180.0))) * 1.2
            
            let minLat = coordinate.latitude - latDelta
            let maxLat = coordinate.latitude + latDelta
            let minLon = coordinate.longitude - lonDelta
            let maxLon = coordinate.longitude + lonDelta
            
            var nearbyList: [NearbyBusStop] = []
            
            do {
                try self.ensureTransitAttached(in: db)
                let columns = try Row.fetchAll(db, sql: "PRAGMA transit.table_info(stops)")
                let hasRoutes = columns.contains { ($0["name"] as? String) == "routes" }
                let routesSelect = hasRoutes ? "routes" : "'' AS routes"
                
                let sql = """
                    SELECT stop_id, stop_name, stop_lat, stop_lon, \(routesSelect) 
                    FROM transit.stops 
                    WHERE location_type = 0 
                      AND stop_lat BETWEEN ? AND ? 
                      AND stop_lon BETWEEN ? AND ?
                """
                let rows = try Row.fetchAll(db, sql: sql, arguments: [minLat, maxLat, minLon, maxLon])
                
                let userLoc = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
                for row in rows {
                    let stopId: String = row["stop_id"]
                    if self.isSubwayPlatformId(stopId) {
                        continue
                    }
                    
                    let lat: Double = row["stop_lat"]
                    let lon: Double = row["stop_lon"]
                    let stopLoc = CLLocation(latitude: lat, longitude: lon)
                    let dist = userLoc.distance(from: stopLoc)
                    
                    if dist <= radiusMeters {
                        let stopName: String = row["stop_name"]
                        let routesStr: String = (row["routes"] as? String) ?? ""
                        let routes: [String]
                        if !routesStr.isEmpty {
                            routes = routesStr.components(separatedBy: ",").filter { !$0.isEmpty }
                        } else {
                            routes = self.inferBusRoutes(from: stopName, stopId: stopId)
                        }
                        let direction = self.inferBusDirection(from: stopName)
                        
                        nearbyList.append(NearbyBusStop(
                            id: stopId,
                            name: stopName,
                            coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                            distanceMeters: dist,
                            routes: routes.isEmpty ? ["MTA"] : routes,
                            direction: direction
                        ))
                    }
                }
            } catch {
                print("⚠️ Transit DB bus stops query unavailable: \(error)")
            }
            
            // Sort by proximity
            nearbyList.sort { $0.distanceMeters < $1.distanceMeters }
            if nearbyList.isEmpty {
                nearbyList = self.generateFallbackNearbyBusStops(for: coordinate, radiusMeters: radiusMeters)
            }
            return Array(nearbyList.prefix(8))
        }
    }
    
    public static let fallbackBusCandidates: [(id: String, name: String, lat: Double, lon: Double, routes: [String], direction: String)] = [
        // 14th St / Union Square
        ("BUS_001", "1 Av & E 14 St", 40.7320, -73.9830, ["M15-SBS", "M15"], "Southbound"),
        ("BUS_002", "E 14 St & 2 Av", 40.7335, -73.9860, ["M14A-SBS", "M14D-SBS"], "Eastbound"),
        ("BUS_003", "1 Av & E 18 St", 40.7345, -73.9810, ["M15", "M101"], "Northbound"),
        ("BUS_004", "Bedford Av & N 7 St", 40.7160, -73.9590, ["B62"], "Northbound"),
        ("BUS_005", "Grand St & Bedford Av", 40.7130, -73.9600, ["B32", "B62"], "Southbound"),
        ("BUS_006", "Union Sq West & 14 St", 40.7350, -73.9910, ["M1", "M2", "M3"], "Southbound"),
        ("BUS_007", "5 Av & W 14 St", 40.7360, -73.9930, ["M1", "M2", "M3"], "Northbound"),
        ("BUS_008", "Union Sq East & E 15 St", 40.7355, -73.9895, ["M14A-SBS", "M14D-SBS"], "Eastbound"),

        // Columbus Circle / Central Park South / 59th St (for demo walks)
        ("BUS_CC_01", "Columbus Circle & 8 Av", 40.7684, -73.9826, ["M10", "M20", "M104"], "Northbound"),
        ("BUS_CC_02", "8 Av & W 58 St", 40.7675, -73.9832, ["M20", "M104"], "Southbound"),
        ("BUS_CC_03", "Broadway & W 61 St", 40.7702, -73.9822, ["M104", "M20", "M5"], "Northbound"),
        ("BUS_CC_04", "Central Park South & Columbus Circle", 40.7668, -73.9798, ["M5", "M7", "M10"], "Eastbound"),
        ("BUS_CC_05", "W 57 St & 8 Av", 40.7663, -73.9839, ["M57", "M31"], "Westbound"),
        ("BUS_CC_06", "W 57 St & 7 Av", 40.7650, -73.9795, ["M57", "M31", "M5"], "Eastbound"),
        ("BUS_CC_07", "Broadway & W 63 St / Lincoln Center", 40.7720, -73.9818, ["M104", "M20", "M66"], "Northbound"),

        // Financial District (FiDi) & Battery Park & WTC
        ("BUS_FIDI_01", "Broadway & Wall St", 40.7075, -74.0112, ["M55", "SIM1", "SIM2"], "Southbound"),
        ("BUS_FIDI_02", "Broadway & Fulton St", 40.7112, -74.0085, ["M55", "SIM1", "SIM4"], "Northbound"),
        ("BUS_FIDI_03", "Water St & Wall St", 40.7058, -74.0076, ["M15-SBS", "M15"], "Southbound"),
        ("BUS_FIDI_04", "Battery Pl & Washington St", 40.7052, -74.0163, ["M20", "M55"], "Southbound"),
        ("BUS_FIDI_05", "Vesey St & Church St / WTC", 40.7125, -74.0098, ["M20", "M55", "M9"], "Northbound"),
        ("BUS_FIDI_06", "State St & Whitehall St / South Ferry", 40.7020, -74.0132, ["M15-SBS", "M20", "M55"], "Southbound"),
        ("BUS_FIDI_07", "Broadway & Rector St", 40.7082, -74.0110, ["M55", "SIM1"], "Northbound"),
        ("BUS_FIDI_08", "Water St & Maiden Ln", 40.7065, -74.0065, ["M15-SBS", "M15"], "Northbound"),

        // Midtown / Times Square / Grand Central / Penn Station
        ("BUS_MID_01", "7 Av & W 42 St / Times Sq", 40.7562, -73.9868, ["M7", "M20", "M104"], "Southbound"),
        ("BUS_MID_02", "8 Av & W 42 St / Port Authority", 40.7576, -73.9898, ["M20", "M104", "M34A-SBS"], "Northbound"),
        ("BUS_MID_03", "E 42 St & Lexington Av / Grand Central", 40.7516, -73.9754, ["M42", "M101", "M102"], "Eastbound"),
        ("BUS_MID_04", "E 42 St & Madison Av", 40.7525, -73.9785, ["M42", "M1", "M2", "M3"], "Westbound"),
        ("BUS_MID_05", "W 34 St & 7 Av / Penn Station", 40.7505, -73.9902, ["M34-SBS", "M34A-SBS", "M7"], "Westbound"),
        ("BUS_MID_06", "W 34 St & 8 Av", 40.7520, -73.9930, ["M34-SBS", "M20"], "Westbound"),
        ("BUS_MID_07", "5 Av & W 46 St / Rockefeller Ctr", 40.7558, -73.9795, ["M1", "M2", "M3", "M4"], "Southbound"),
        ("BUS_MID_08", "Madison Av & E 48 St", 40.7567, -73.9758, ["M1", "M2", "M3", "M4"], "Northbound"),

        // Upper West Side & Upper East Side & Harlem
        ("BUS_UWS_01", "Broadway & W 72 St", 40.7785, -73.9820, ["M104", "M72"], "Northbound"),
        ("BUS_UWS_02", "Amsterdam Av & W 79 St", 40.7836, -73.9785, ["M79-SBS", "M7", "M11"], "Northbound"),
        ("BUS_UWS_03", "Broadway & W 86 St", 40.7885, -73.9760, ["M104", "M86-SBS"], "Northbound"),
        ("BUS_UES_01", "Lexington Av & E 72 St", 40.7705, -73.9620, ["M101", "M102", "M103", "M72"], "Southbound"),
        ("BUS_UES_02", "3 Av & E 79 St", 40.7745, -73.9575, ["M101", "M102", "M79-SBS"], "Northbound"),
        ("BUS_UES_03", "2 Av & E 86 St", 40.7780, -73.9520, ["M15-SBS", "M15", "M86-SBS"], "Southbound"),
        ("BUS_HLM_01", "125 St & Lenox Av / Apollo", 40.8080, -73.9480, ["M60-SBS", "M125", "Bx15"], "Westbound"),

        // Brooklyn Hubs & Greenpoint / Williamsburg
        ("BUS_BK_01", "Cadman Plaza W & Montague St", 40.6945, -73.9915, ["B25", "B26", "B38", "B41"], "Southbound"),
        ("BUS_BK_02", "Fulton St & Jay St / Downtown BK", 40.6920, -73.9875, ["B25", "B26", "B38"], "Eastbound"),
        ("BUS_BK_03", "Atlantic Av & 4 Av / Barclays Ctr", 40.6845, -73.9780, ["B41", "B45", "B67"], "Eastbound"),
        ("BUS_BK_04", "Water St & Main St / DUMBO", 40.7032, -73.9902, ["B25"], "Northbound"),
        ("BUS_GP_01", "Manhattan Av & Nassau Av", 40.7235, -73.9507, ["B43", "B62"], "Northbound"),
        ("BUS_GP_02", "Lorimer St & Nassau Av", 40.7234, -73.9515, ["B48"], "Southbound"),
        ("BUS_GP_03", "Nassau Av & Manhattan Av", 40.7237, -73.9509, ["B62"], "Southbound")
    ]
    
    private func generateFallbackNearbyBusStops(for coordinate: CLLocationCoordinate2D, radiusMeters: Double) -> [NearbyBusStop] {
        let userLoc = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        
        var results: [NearbyBusStop] = []
        for c in Self.fallbackBusCandidates {
            let stopLoc = CLLocation(latitude: c.lat, longitude: c.lon)
            let dist = userLoc.distance(from: stopLoc)
            if dist <= radiusMeters {
                results.append(NearbyBusStop(
                    id: c.id,
                    name: c.name,
                    coordinate: CLLocationCoordinate2D(latitude: c.lat, longitude: c.lon),
                    distanceMeters: dist,
                    routes: c.routes,
                    direction: c.direction
                ))
            }
        }
        results.sort { $0.distanceMeters < $1.distanceMeters }
        return Array(results.prefix(8))
    }
    
    public func isSubwayPlatformId(_ stopId: String) -> Bool {
        let clean = stopId.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.hasPrefix("BUS_") || clean.hasPrefix("MTA_") { return false }
        if clean.count == 6 && clean.allSatisfy({ $0.isNumber }) { return false }
        if clean.count == 5 && clean.allSatisfy({ $0.isNumber }) { return false }
        if clean.hasSuffix("N") || clean.hasSuffix("S") || clean.hasSuffix("E") || clean.hasSuffix("W") {
            let base = String(clean.dropLast())
            if base.count <= 4 { return true }
        }
        if clean.count <= 4 && !clean.allSatisfy({ $0.isNumber }) { return true }
        return false
    }
    
    public func fetchStopDetails(for stopId: String) async throws -> StopDetails {
        let startTime = CFAbsoluteTimeGetCurrent()
        defer {
            let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000.0
            print("⏱️ fetchStopDetails for \(stopId) executed in \(String(format: "%.2f", elapsed))ms")
        }
        
        return try await dbWriter.read { db in
            do {
                try self.ensureTransitAttached(in: db)
                let columns = try Row.fetchAll(db, sql: "PRAGMA transit.table_info(stops)")
                let hasRoutes = columns.contains { ($0["name"] as? String) == "routes" }
                let hasLocationType = columns.contains { ($0["name"] as? String) == "location_type" }
                let hasParentStation = columns.contains { ($0["name"] as? String) == "parent_station" }
                let hasLat = columns.contains { ($0["name"] as? String) == "stop_lat" }
                let hasLon = columns.contains { ($0["name"] as? String) == "stop_lon" }
                let hasRouteType = columns.contains { ($0["name"] as? String) == "route_type" }
                
                let routesSelect = hasRoutes ? "routes" : "'' AS routes"
                let locTypeSelect = hasLocationType ? "location_type" : "1 AS location_type"
                let parentSelect = hasParentStation ? "parent_station" : "NULL AS parent_station"
                let latSelect = hasLat ? "stop_lat" : "NULL AS stop_lat"
                let lonSelect = hasLon ? "stop_lon" : "NULL AS stop_lon"
                let routeTypeSelect = hasRouteType ? "route_type" : "NULL AS route_type"
                
                let sql = "SELECT stop_name, \(locTypeSelect), \(routesSelect), \(parentSelect), \(latSelect), \(lonSelect), \(routeTypeSelect) FROM transit.stops WHERE stop_id = ?"
                if let row = try Row.fetchOne(db, sql: sql, arguments: [stopId]) {
                    var name: String = row["stop_name"] ?? ""
                    var locationType: Int = row["location_type"] ?? 1
                    var routesStr: String? = row["routes"]
                    let parentStationId: String? = row["parent_station"]
                    let stopLat: Double? = row["stop_lat"]
                    let stopLon: Double? = row["stop_lon"]
                    let rawRouteType: Int? = row["route_type"]
                    
                    let isPrimaryGeneric = self.isGenericStopName(name, stopId: stopId)
                    
                    // Tier 2: Hierarchical Parent Station Lookup
                    if let parentId = parentStationId, !parentId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, parentId != stopId {
                        if isPrimaryGeneric || locationType == 0 {
                            let parentSql = "SELECT stop_name, \(locTypeSelect), \(routesSelect) FROM transit.stops WHERE stop_id = ?"
                            if let parentRow = try Row.fetchOne(db, sql: parentSql, arguments: [parentId]) {
                                let parentName: String = parentRow["stop_name"] ?? ""
                                if !self.isGenericStopName(parentName, stopId: parentId) {
                                    if isPrimaryGeneric {
                                        name = parentName
                                    }
                                    if let pLoc = parentRow["location_type"] as? Int, locationType == 0 && isPrimaryGeneric {
                                        locationType = pLoc
                                    }
                                    let parentRoutes: String? = parentRow["routes"]
                                    if (routesStr == nil || routesStr?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true),
                                       let pRoutes = parentRoutes, !pRoutes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                        routesStr = pRoutes
                                    }
                                }
                            }
                        }
                    }
                    
                    // Tier 2.5: Parent Station Child Platform Route Resolution
                    if (routesStr == nil || routesStr?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true) && locationType == 1 {
                        let childRoutesSql = "SELECT DISTINCT routes FROM transit.stops WHERE parent_station = ? AND routes IS NOT NULL AND routes != ''"
                        if let childRows = try? Row.fetchAll(db, sql: childRoutesSql, arguments: [stopId]), !childRows.isEmpty {
                            var collected = [String]()
                            for cRow in childRows {
                                let r: String = cRow["routes"] ?? ""
                                for item in r.components(separatedBy: ",") {
                                    let trimmed = item.trimmingCharacters(in: .whitespacesAndNewlines)
                                    if !trimmed.isEmpty && !collected.contains(trimmed) {
                                        collected.append(trimmed)
                                    }
                                }
                            }
                            if !collected.isEmpty {
                                routesStr = collected.joined(separator: ",")
                            }
                        }
                    }
                    
                    // Tier 3: Offline Cross-Street Intersection / Spatial Fallback
                    if self.isGenericStopName(name, stopId: stopId) {
                        if let lat = stopLat, let lon = stopLon {
                            let latDelta = 0.002 // ~220m
                            let lonDelta = 0.002
                            let nearbySql = """
                                SELECT stop_name FROM transit.stops 
                                WHERE stop_lat BETWEEN ? AND ? 
                                  AND stop_lon BETWEEN ? AND ? 
                                  AND stop_name != '' 
                                  AND stop_id != ?
                                ORDER BY ((stop_lat - ?) * (stop_lat - ?) + (stop_lon - ?) * (stop_lon - ?)) ASC 
                                LIMIT 1
                            """
                            if let nearbyRow = try Row.fetchOne(db, sql: nearbySql, arguments: [lat - latDelta, lat + latDelta, lon - lonDelta, lon + lonDelta, stopId, lat, lat, lon, lon]) {
                                let nearbyName: String = nearbyRow["stop_name"] ?? ""
                                if !self.isGenericStopName(nearbyName, stopId: "") {
                                    name = nearbyName.contains("/") || nearbyName.contains("&") ? nearbyName : "\(nearbyName) Area"
                                }
                            }
                        }
                        
                        if self.isGenericStopName(name, stopId: stopId) {
                            let fallback = self.generateFallbackStopDetails(for: stopId)
                            name = fallback.name
                        }
                    }
                    
                    let isBusLocation = locationType == 0 || stopId.hasPrefix("BUS_") || name.contains("/")
                    
                    let routeIds: [String]
                    if let rStr = routesStr, !rStr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        let parsed = rStr.components(separatedBy: ",")
                            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                            .filter { !$0.isEmpty }
                        routeIds = parsed.isEmpty ? (isBusLocation ? self.inferBusRoutes(from: name, stopId: stopId) : [self.inferRouteId(from: stopId, name: name)]) : parsed
                    } else if isBusLocation {
                        routeIds = self.inferBusRoutes(from: name, stopId: stopId)
                    } else {
                        routeIds = [self.inferRouteId(from: stopId, name: name)]
                    }
                    
                    let routeType: Int
                    if let raw = rawRouteType {
                        routeType = raw
                    } else if routeIds.contains(where: { TransitRouteData.isFerryRoute($0) }) {
                        routeType = 4
                    } else if routeIds.contains(where: { TransitRouteData.isLightRailRoute($0) }) {
                        routeType = 0
                    } else if isBusLocation || routeIds.contains(where: { TransitRouteData.isBusRoute($0) }) {
                        routeType = 3
                    } else {
                        routeType = 1
                    }
                    
                    let modalClass = TransitModalClass.from(routeType: routeType)
                    let isBus = modalClass == .bus
                    let primaryRouteId = routeIds.first ?? (isBus ? "M15" : "L")
                    let arrivals = isBus ? self.generateBusArrivals(for: primaryRouteId, stopName: name) : self.generateArrivals(for: primaryRouteId)
                    return StopDetails(stopId: stopId, name: name, routeId: primaryRouteId, routeIds: routeIds, routeType: routeType, modalClass: modalClass, arrivals: arrivals)
                }
            } catch let error as DatabaseError {
                print("⚠️ Transit DB table missing or unattached: \(error.message). Using fallback.")
            } catch {
                throw error
            }
            
            return self.generateFallbackStopDetails(for: stopId)
        }
    }
    
    /// Fetches route information from `transit.routes` table if attached, falling back to static catalog.
    func fetchRouteInfo(for routeId: String) async -> TransitRouteData.LineInfo {
        let fallback = TransitRouteData.lineInfo(for: routeId)
        do {
            return try await dbWriter.read { db in
                try self.ensureTransitAttached(in: db)
                let columns = try Row.fetchAll(db, sql: "PRAGMA transit.table_info(routes)")
                guard !columns.isEmpty else { return fallback }
                
                let sql = "SELECT route_id, route_short_name, route_long_name, route_type, route_color, route_text_color FROM transit.routes WHERE route_id = ? OR route_short_name = ? LIMIT 1"
                if let row = try Row.fetchOne(db, sql: sql, arguments: [routeId, routeId]) {
                    let rId: String = row["route_id"] ?? routeId
                    let shortName: String = row["route_short_name"] ?? rId
                    let rType: Int = row["route_type"] ?? fallback.routeType
                    let colorHexRaw: String? = row["route_color"]
                    let textHexRaw: String? = row["route_text_color"]
                    
                    let colorHex: String
                    if let c = colorHexRaw, !c.isEmpty {
                        colorHex = c.hasPrefix("#") ? c : "#\(c)"
                    } else {
                        colorHex = fallback.colorHex
                    }
                    
                    let textColorHex: String
                    if let t = textHexRaw, !t.isEmpty {
                        textColorHex = t.hasPrefix("#") ? t : "#\(t)"
                    } else {
                        textColorHex = fallback.textColorHex
                    }
                    
                    let modalClass = TransitModalClass.from(routeType: rType)
                    return TransitRouteData.LineInfo(
                        routeId: rId,
                        name: shortName,
                        colorHex: colorHex,
                        textColorHex: textColorHex,
                        modalClass: modalClass,
                        routeType: rType
                    )
                }
                return fallback
            }
        } catch {
            return fallback
        }
    }
    
    /// Fetches the ordered progression of stops along a route for the Track Thermometer.
    /// Marks passed stops, the current stop, terminus stops, and progressive arrival minutes.
    public func fetchRouteStopLadder(
        routeId: String,
        directionId: Int,
        currentStopId: String,
        currentArrivalMinutes: Int = 0
    ) async throws -> [TrackStop] {
        return try await dbWriter.read { db in
            do {
                try self.ensureTransitAttached(in: db)
                let patternColumns = try Row.fetchAll(db, sql: "PRAGMA transit.table_info(scheduled_hourly_patterns)")
                if !patternColumns.isEmpty {
                    let sql = """
                        SELECT DISTINCT s.stop_id, s.stop_name, s.stop_lat, s.stop_lon, s.parent_station, s.routes
                        FROM transit.stops s
                        JOIN transit.scheduled_hourly_patterns p ON (s.stop_id = p.stop_id OR s.parent_station = p.stop_id)
                        WHERE p.route_id = ? AND p.direction_id = ?
                        ORDER BY p.rowid ASC
                    """
                    let rows = try Row.fetchAll(db, sql: sql, arguments: [routeId, directionId])
                    if !rows.isEmpty {
                        // Deduplicate stops by name or parent_station while preserving progression order
                        var seen = Set<String>()
                        var uniqueRows = [Row]()
                        for r in rows {
                            let key = (r["parent_station"] as String?) ?? (r["stop_name"] as String? ?? (r["stop_id"] as String))
                            if !seen.contains(key) {
                                seen.insert(key)
                                uniqueRows.append(r)
                            }
                        }
                        
                        // Sort direction: if directionId == 1 (typically Downtown/Southbound), check latitude ordering
                        if directionId == 1 && uniqueRows.count >= 2 {
                            let lat0: Double = uniqueRows.first?["stop_lat"] ?? 0
                            let lat1: Double = uniqueRows.last?["stop_lat"] ?? 0
                            if lat0 < lat1 {
                                uniqueRows.reverse()
                            }
                        } else if directionId == 0 && uniqueRows.count >= 2 {
                            let lat0: Double = uniqueRows.first?["stop_lat"] ?? 0
                            let lat1: Double = uniqueRows.last?["stop_lat"] ?? 0
                            if lat0 > lat1 {
                                uniqueRows.reverse()
                            }
                        }
                        
                        let cleanTarget = currentStopId.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                        let currentIndex = uniqueRows.firstIndex { row in
                            let sId = (row["stop_id"] as? String ?? "").uppercased()
                            let pId = (row["parent_station"] as? String ?? "").uppercased()
                            return sId == cleanTarget || pId == cleanTarget || sId.hasPrefix(cleanTarget) || cleanTarget.hasPrefix(sId)
                        } ?? 0
                        
                        return uniqueRows.enumerated().map { idx, row in
                            let sId: String = row["stop_id"]
                            let sName: String = row["stop_name"]
                            let lat: Double = row["stop_lat"]
                            let lon: Double = row["stop_lon"]
                            let rStr: String? = row["routes"]
                            
                            let isPassed = idx < currentIndex
                            let isCurrent = idx == currentIndex
                            let isTerminus = idx == 0 || idx == (uniqueRows.count - 1)
                            
                            let eta: Int?
                            if isPassed {
                                eta = nil
                            } else if isCurrent {
                                eta = currentArrivalMinutes
                            } else {
                                eta = currentArrivalMinutes + (idx - currentIndex) * 2
                            }
                            
                            let transfers = StationBulletRenderer.parseAndNormalizeRoutes(rStr ?? "")
                                .filter { $0 != routeId.uppercased() }
                            
                            return TrackStop(
                                id: "\(sId)_\(idx)",
                                stopId: sId,
                                stopName: sName,
                                coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                                sequenceIndex: idx,
                                isPassed: isPassed,
                                isCurrent: isCurrent,
                                isTerminus: isTerminus,
                                estimatedMinutes: eta,
                                transferRoutes: transfers
                            )
                        }
                    }
                }
            } catch {
                // fall through to synthetic fallback
            }
            
            // Synthetic / Fixture Fallback when database patterns are unavailable
            return self.generateFallbackStopLadder(routeId: routeId, currentStopId: currentStopId, arrivalMinutes: currentArrivalMinutes)
        }
    }
    
    private func generateFallbackStopLadder(routeId: String, currentStopId: String, arrivalMinutes: Int) -> [TrackStop] {
        let stopNames = [
            "Origin Terminal",
            "Midtown Crossing",
            "Central Square",
            "Transit Hub Platform",
            "Market St Station",
            "Civic Center",
            "Uptown Transfer",
            "Final Destination"
        ]
        let currentIdx = 3
        return stopNames.enumerated().map { idx, name in
            let isPassed = idx < currentIdx
            let isCurrent = idx == currentIdx
            let eta = isPassed ? nil : (arrivalMinutes + (idx - currentIdx) * 2)
            return TrackStop(
                id: "\(routeId)_stop_\(idx)",
                stopId: isCurrent ? currentStopId : "stop_\(idx)",
                stopName: isCurrent ? (currentStopId.replacingOccurrences(of: "_", with: " ").capitalized) : name,
                coordinate: CLLocationCoordinate2D(latitude: 40.7580 + Double(idx) * 0.005, longitude: -73.9855 + Double(idx) * 0.003),
                sequenceIndex: idx,
                isPassed: isPassed,
                isCurrent: isCurrent,
                isTerminus: idx == 0 || idx == stopNames.count - 1,
                estimatedMinutes: eta,
                transferRoutes: idx % 2 == 0 ? ["4", "5"] : []
            )
        }
    }
    
    public func isGenericStopName(_ name: String, stopId: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return true }
        
        let upper = trimmed.uppercased()
        if upper == stopId.uppercased() || upper == "BUS_\(stopId.uppercased())" { return true }
        
        let genericExact: Set<String> = [
            "BUS STOP", "BUSSTOP", "STOP", "TRANSIT STOP", "STATION",
            "SUBWAY STATION", "TRANSIT STATION", "BUS TERMINAL", "TERMINAL",
            "PLATFORM", "BAY", "GATE", "DOCK", "BERTH", "STAND", "UNKNOWN"
        ]
        if genericExact.contains(upper) { return true }
        
        let genericPrefixes = [
            "BUS STOP (", "TRANSIT STOP (", "TRANSIT STATION (", "STOP #", "STOP NO",
            "PLATFORM ", "BAY ", "GATE ", "TRACK ", "BERTH ", "DOCK "
        ]
        for prefix in genericPrefixes {
            if upper.hasPrefix(prefix) { return true }
        }
        
        return false
    }
    
    public func fetchHeadwayData(for stopId: String) async throws -> [Double] {
        let startTime = CFAbsoluteTimeGetCurrent()
        defer {
            let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000.0
            print("⏱️ fetchHeadwayData for \(stopId) executed in \(String(format: "%.2f", elapsed))ms")
        }
        
        return try await dbWriter.read { db in
            do {
                try self.ensureTransitAttached(in: db)
                let resolvedIds = self.resolvePlatformStopIds(for: stopId, in: db)
                let idPlaceholders = Array(repeating: "?", count: resolvedIds.count).joined(separator: ", ")
                let sql = "SELECT headway_min FROM transit.headway_history WHERE stop_id IN (\(idPlaceholders)) ORDER BY day_offset ASC LIMIT 7"
                let rows = try Double.fetchAll(db, sql: sql, arguments: StatementArguments(resolvedIds.map { $0 as DatabaseValueConvertible }))
                if !rows.isEmpty {
                    return rows
                }
            } catch let error as DatabaseError {
                print("⚠️ Transit headway query failed: \(error.message). Returning fallback headways.")
            } catch {
                throw error
            }
            return self.generateFallbackHeadways(for: stopId)
        }
    }
    
    public func fetchHourlyReliability(for stopId: String, routeId: String? = nil, routeIds: [String] = []) async throws -> [HourlyReliabilityRecord] {
        let startTime = CFAbsoluteTimeGetCurrent()
        defer {
            let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000.0
            print("⏱️ fetchHourlyReliability for \(stopId) executed in \(String(format: "%.2f", elapsed))ms")
        }
        
        return try await dbWriter.read { db in
            do {
                try self.ensureTransitAttached(in: db)
                let resolvedIds = self.resolvePlatformStopIds(for: stopId, in: db)
                let idPlaceholders = Array(repeating: "?", count: resolvedIds.count).joined(separator: ", ")
                var sql = """
                    SELECT route_id, stop_id, direction_id, hour_of_day, day_of_week, 
                           median_delay_sec, p90_delay_sec, median_headway_sec, headway_stddev_sec, 
                           ewt_seconds, on_time_pct, sample_count
                    FROM transit.stop_reliability_hourly
                    WHERE stop_id IN (\(idPlaceholders))
                """
                var args: [DatabaseValueConvertible] = resolvedIds.map { $0 as DatabaseValueConvertible }
                if !routeIds.isEmpty {
                    let placeholders = Array(repeating: "?", count: routeIds.count).joined(separator: ", ")
                    sql += " AND route_id IN (\(placeholders))"
                    args.append(contentsOf: routeIds.map { $0 as DatabaseValueConvertible })
                } else if let rId = routeId, !rId.isEmpty {
                    sql += " AND route_id = ?"
                    args.append(rId)
                }
                sql += " ORDER BY day_of_week ASC, hour_of_day ASC"
                
                let rows = try Row.fetchAll(db, sql: sql, arguments: StatementArguments(args))
                if !rows.isEmpty {
                    return rows.map { row in
                        HourlyReliabilityRecord(
                            routeId: row[0],
                            stopId: row[1],
                            directionId: row[2] ?? 0,
                            hourOfDay: row[3],
                            dayOfWeek: row[4],
                            medianDelaySec: row[5],
                            p90DelaySec: row[6],
                            medianHeadwaySec: row[7] ?? 300,
                            headwayStdDevSec: row[8] ?? 60,
                            ewtSeconds: row[9] ?? 60.0,
                            onTimePct: row[10],
                            sampleCount: row[11]
                        )
                    }
                }
            } catch let error as DatabaseError {
                print("⚠️ Transit stop_reliability_hourly query failed: \(error.message). Returning fallback matrix.")
            } catch {
                throw error
            }
            
            let effectiveRoute = routeIds.first ?? (routeId ?? self.inferRouteId(from: stopId, name: stopId))
            return self.generateFallbackReliabilityMatrix(for: stopId, routeId: effectiveRoute)
        }
    }
    
    // MARK: - Transit Reliability Engine Forwarding (Wave N-C.2)
    
    public var transitEngine: TransitDatabaseEngine {
        TransitDatabaseEngine.shared
    }
    
    public func fetchActiveDisruptions(at epoch: Int64 = Int64(Date().timeIntervalSince1970)) async throws -> [ServiceDisruptionRecord] {
        return try await transitEngine.fetchActiveDisruptions(at: epoch)
    }
    
    public func fetchDisruptionBitmask(at epoch: Int64 = Int64(Date().timeIntervalSince1970)) async throws -> TransitDisruptionBitmask {
        return try await transitEngine.fetchDisruptionBitmask(at: epoch)
    }
    
    public func fetchTripSlotProfile(
        routeId: String,
        directionId: Int,
        stopId: String,
        slotIndex: Int,
        dayType: Int
    ) async throws -> TripSlotProfileRecord? {
        return try await transitEngine.fetchTripSlotProfile(
            routeId: routeId,
            directionId: directionId,
            stopId: stopId,
            slotIndex: slotIndex,
            dayType: dayType
        )
    }
    
    public func fetchTripSlotProfiles(
        routeId: String,
        directionId: Int,
        slotIndex: Int,
        dayType: Int
    ) async throws -> [TripSlotProfileRecord] {
        return try await transitEngine.fetchTripSlotProfiles(
            routeId: routeId,
            directionId: directionId,
            slotIndex: slotIndex,
            dayType: dayType
        )
    }
    
    public func fetchStopEvents(for stopId: String, hourOfDay: Int, dayOfWeek: Int) async throws -> [StopEventRecord] {
        let startTime = CFAbsoluteTimeGetCurrent()
        defer {
            let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000.0
            print("⏱️ fetchStopEvents for \(stopId) h=\(hourOfDay) dow=\(dayOfWeek) executed in \(String(format: "%.2f", elapsed))ms")
        }
        
        return try await dbWriter.read { db in
            do {
                try self.ensureTransitAttached(in: db)
                let resolvedIds = self.resolvePlatformStopIds(for: stopId, in: db)
                let idPlaceholders = Array(repeating: "?", count: resolvedIds.count).joined(separator: ", ")
                let sql = """
                    SELECT event_id, trip_id, route_id, stop_id, scheduled_time, actual_time, delay_seconds, observed_at, direction_id
                    FROM transit.stop_events
                    WHERE stop_id IN (\(idPlaceholders))
                      AND CAST(strftime('%w', datetime(observed_at, 'unixepoch')) AS INTEGER) = ?
                      AND CAST(strftime('%H', datetime(observed_at, 'unixepoch')) AS INTEGER) = ?
                    ORDER BY observed_at ASC
                """
                var args: [DatabaseValueConvertible] = resolvedIds.map { $0 as DatabaseValueConvertible }
                args.append(dayOfWeek)
                args.append(hourOfDay)
                
                let rows = try Row.fetchAll(db, sql: sql, arguments: StatementArguments(args))
                if !rows.isEmpty {
                    return rows.map { row in
                        let schedEpoch: Int64? = row[4]
                        let actualEpoch: Int64 = row[5]
                        let obsEpoch: Int64 = row[7]
                        
                        return StopEventRecord(
                            eventId: row[0],
                            tripId: row[1],
                            routeId: row[2],
                            stopId: row[3],
                            scheduledTime: schedEpoch.map { Date(timeIntervalSince1970: TimeInterval($0)) },
                            actualTime: Date(timeIntervalSince1970: TimeInterval(actualEpoch)),
                            delaySeconds: row[6],
                            observedAt: Date(timeIntervalSince1970: TimeInterval(obsEpoch)),
                            directionId: row[8] ?? 0
                        )
                    }
                }
            } catch let error as DatabaseError {
                print("⚠️ Transit stop_events query failed: \(error.message). Returning fallback events.")
            } catch {
                throw error
            }
            
            return self.generateFallbackStopEvents(for: stopId, hourOfDay: hourOfDay, dayOfWeek: dayOfWeek)
        }
    }
    
    public func fetchTimetableResult(
        for stopId: String,
        routeId: String? = nil,
        routeIds: [String] = [],
        directionId: Int = 0,
        dayOffset: Int = 0,
        referenceDate: Date = Date()
    ) async throws -> TimetableResult {
        let startTime = CFAbsoluteTimeGetCurrent()
        defer {
            let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000.0
            print("⏱️ fetchTimetableResult for \(stopId) dir=\(directionId) dayOffset=\(dayOffset) executed in \(String(format: "%.2f", elapsed))ms")
        }
        
        return try await dbWriter.read { db in
            do {
                try self.ensureTransitAttached(in: db)
                
                let calendar = Calendar.current
                let targetDate = calendar.date(byAdding: .day, value: dayOffset, to: referenceDate) ?? referenceDate
                let startOfDay = calendar.startOfDay(for: targetDate)
                let startOfDayEpoch = Int64(startOfDay.timeIntervalSince1970)
                let endOfDayEpoch = startOfDayEpoch + 86400
                
                let resolvedIds = self.resolvePlatformStopIds(for: stopId, in: db)
                let idPlaceholders = Array(repeating: "?", count: resolvedIds.count).joined(separator: ", ")
                
                // Past days ($dayOffset < 0): Try Observed Reality Replay from stop_events
                if dayOffset < 0 {
                    let eventColumns = try Row.fetchAll(db, sql: "PRAGMA transit.table_info(stop_events)")
                    if !eventColumns.isEmpty {
                        var eventSql = """
                            SELECT event_id, trip_id, route_id, stop_id, scheduled_time, actual_time, delay_seconds, observed_at, direction_id
                            FROM transit.stop_events
                            WHERE stop_id IN (\(idPlaceholders)) AND direction_id = ? AND observed_at >= ? AND observed_at < ?
                        """
                        var eventArgs: [DatabaseValueConvertible] = resolvedIds.map { $0 as DatabaseValueConvertible }
                        eventArgs.append(directionId)
                        eventArgs.append(startOfDayEpoch)
                        eventArgs.append(endOfDayEpoch)
                        if !routeIds.isEmpty {
                            let placeholders = Array(repeating: "?", count: routeIds.count).joined(separator: ", ")
                            eventSql += " AND route_id IN (\(placeholders))"
                            eventArgs.append(contentsOf: routeIds.map { $0 as DatabaseValueConvertible })
                        } else if let rId = routeId, !rId.isEmpty {
                            eventSql += " AND route_id = ?"
                            eventArgs.append(rId)
                        }
                        eventSql += " ORDER BY observed_at ASC"
                        
                        let eventRows = try Row.fetchAll(db, sql: eventSql, arguments: StatementArguments(eventArgs))
                        if !eventRows.isEmpty {
                            var hourMap: [Int: [DeparturePillRecord]] = [:]
                            for hour in 0..<24 {
                                hourMap[hour] = []
                            }
                            for (idx, row) in eventRows.enumerated() {
                                let actualEpoch: Int64 = row["actual_time"] ?? row["observed_at"]
                                let actualDate = Date(timeIntervalSince1970: TimeInterval(actualEpoch))
                                let depHour = calendar.component(.hour, from: actualDate)
                                let depMin = calendar.component(.minute, from: actualDate)
                                
                                let tripId: String = row["trip_id"] ?? "EVENT_\(idx)"
                                let rId: String = row["route_id"] ?? (routeId ?? "L")
                                let dir: Int = row["direction_id"] ?? directionId
                                let delaySec: Int = row["delay_seconds"] ?? 0
                                let dest: String = TransitRealtimeService.SubwayFeed.isBusRoute(rId) ? TransitRealtimeService.resolveBusDestination(routeId: rId, directionId: dir).destination : "Terminal"
                                
                                let pill = DeparturePillRecord(
                                    id: "\(tripId)_\(depHour)_\(depMin)",
                                    tripId: tripId,
                                    routeId: rId,
                                    destination: dest,
                                    directionId: dir,
                                    minute: depMin,
                                    isExpress: rId.contains("X") || rId.contains("SBS"),
                                    isFirstDeparture: idx == 0,
                                    isLastDeparture: idx == eventRows.count - 1,
                                    delaySeconds: delaySec,
                                    isPast: true,
                                    scheduleRelationship: .scheduled,
                                    isHistoricalEvent: true,
                                    historicalDelaySeconds: delaySec
                                )
                                hourMap[depHour % 24]?.append(pill)
                            }
                            let records = (0..<24).map { h in
                                HourScheduleRecord(hourOfDay: h, departures: hourMap[h] ?? [])
                            }
                            return TimetableResult(records: records, isHistoricalFallback: false, isObservedReplay: true)
                        }
                    }
                }
                
                // Static Timetable via scheduled_hourly_patterns (Wave L-A.1 static compactor)
                let patternColumns = try Row.fetchAll(db, sql: "PRAGMA transit.table_info(scheduled_hourly_patterns)")
                if !patternColumns.isEmpty {
                    var sql = """
                        SELECT hour_of_day, minute_offsets, route_id, headsign, direction_id, service_mask, baseline_days_of_week
                        FROM transit.scheduled_hourly_patterns
                        WHERE stop_id IN (\(idPlaceholders)) AND direction_id = ?
                    """
                    var args: [DatabaseValueConvertible] = resolvedIds.map { $0 as DatabaseValueConvertible }
                    args.append(directionId)
                    if !routeIds.isEmpty {
                        let placeholders = Array(repeating: "?", count: routeIds.count).joined(separator: ", ")
                        sql += " AND route_id IN (\(placeholders))"
                        args.append(contentsOf: routeIds.map { $0 as DatabaseValueConvertible })
                    } else if let rId = routeId, !rId.isEmpty {
                        sql += " AND route_id = ?"
                        args.append(rId)
                    }
                    sql += " ORDER BY hour_of_day ASC"
                    
                    let rows = try Row.fetchAll(db, sql: sql, arguments: StatementArguments(args))
                    if !rows.isEmpty {
                        let bitIndex = dayOffset + 7
                        let weekday = calendar.component(.weekday, from: targetDate) // 1=Sun, 2=Mon ... 7=Sat
                        let baselineWeekdayIndex = weekday - 1 // 0=Sun ... 6=Sat
                        
                        var hourMap: [Int: [DeparturePillRecord]] = [:]
                        for hour in 0..<24 {
                            hourMap[hour] = []
                        }
                        
                        for row in rows {
                            let hour: Int = row["hour_of_day"]
                            let serviceMask: Int = row["service_mask"]
                            let baselineMask: Int = row["baseline_days_of_week"]
                            let minOffsets: String = row["minute_offsets"]
                            let rId: String = row["route_id"]
                            let headsign: String = row["headsign"]
                            let dir: Int = row["direction_id"]
                            
                            var isActive = false
                            if bitIndex >= 0 && bitIndex < 14 {
                                if (serviceMask & (1 << bitIndex)) != 0 {
                                    isActive = true
                                }
                            } else if baselineMask > 0 {
                                if (baselineMask & (1 << baselineWeekdayIndex)) != 0 {
                                    isActive = true
                                }
                            }
                            
                            guard isActive else { continue }
                            
                            let mins = minOffsets.components(separatedBy: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
                            for min in mins {
                                let isExp = rId.contains("X") || rId.contains("SBS") || (rId == "2" || rId == "4" || rId == "5" || rId == "A")
                                let pill = DeparturePillRecord(
                                    id: "\(rId)_\(dir)_\(hour)_\(min)",
                                    tripId: "\(rId)_\(dir)_\(hour)_\(min)",
                                    routeId: rId,
                                    destination: headsign.isEmpty ? "Terminal" : headsign,
                                    directionId: dir,
                                    minute: min,
                                    isExpress: isExp
                                )
                                hourMap[hour % 24]?.append(pill)
                            }
                        }
                        
                        var allPillsCount = 0
                        var records: [HourScheduleRecord] = []
                        for h in 0..<24 {
                            let sortedPills = (hourMap[h] ?? []).sorted { $0.minute < $1.minute }
                            allPillsCount += sortedPills.count
                            records.append(HourScheduleRecord(hourOfDay: h, departures: sortedPills))
                        }
                        
                        if allPillsCount > 0 {
                            let isHistFallback = (dayOffset < 0)
                            return TimetableResult(records: records, isHistoricalFallback: isHistFallback, isObservedReplay: false, totalDepartures: allPillsCount)
                        }
                    }
                }
                
                // Legacy scheduled_stops fallback
                let legacyColumns = try Row.fetchAll(db, sql: "PRAGMA transit.table_info(scheduled_stops)")
                if !legacyColumns.isEmpty {
                    var sql = """
                        SELECT strftime('%H', departure_time) as dep_hour,
                               strftime('%M', departure_time) as dep_min,
                               trip_id, route_id, headsign, direction_id
                        FROM transit.scheduled_stops
                        WHERE stop_id IN (\(idPlaceholders)) AND direction_id = ?
                    """
                    var args: [DatabaseValueConvertible] = resolvedIds.map { $0 as DatabaseValueConvertible }
                    args.append(directionId)
                    if !routeIds.isEmpty {
                        let placeholders = Array(repeating: "?", count: routeIds.count).joined(separator: ", ")
                        sql += " AND route_id IN (\(placeholders))"
                        args.append(contentsOf: routeIds.map { $0 as DatabaseValueConvertible })
                    } else if let rId = routeId, !rId.isEmpty {
                        sql += " AND route_id = ?"
                        args.append(rId)
                    }
                    sql += " ORDER BY departure_time ASC"
                    
                    let rows = try Row.fetchAll(db, sql: sql, arguments: StatementArguments(args))
                    if !rows.isEmpty {
                        var hourMap: [Int: [DeparturePillRecord]] = [:]
                        for hour in 0..<24 {
                            hourMap[hour] = []
                        }
                        for (idx, row) in rows.enumerated() {
                            guard let hourStr: String = row["dep_hour"], let hour = Int(hourStr),
                                  let minStr: String = row["dep_min"], let min = Int(minStr) else { continue }
                            let tripId: String = row["trip_id"] ?? "TRIP_\(idx)"
                            let rId: String = row["route_id"] ?? (routeId ?? "L")
                            let dir: Int = row["direction_id"] ?? directionId
                            let dest: String = row["headsign"] ?? (TransitRealtimeService.SubwayFeed.isBusRoute(rId) ? TransitRealtimeService.resolveBusDestination(routeId: rId, directionId: dir).destination : "Terminal")
                            let isExp = rId.contains("X") || rId.contains("SBS") || (rId == "2" || rId == "4" || rId == "5" || rId == "A")
                            let isFirst = idx == 0
                            let isLast = idx == rows.count - 1
                            
                            let pill = DeparturePillRecord(
                                id: "\(tripId)_\(hour)_\(min)",
                                tripId: tripId,
                                routeId: rId,
                                destination: dest,
                                directionId: dir,
                                minute: min,
                                isExpress: isExp,
                                isFirstDeparture: isFirst,
                                isLastDeparture: isLast
                            )
                            hourMap[hour]?.append(pill)
                        }
                        let records = (0..<24).map { h in
                            HourScheduleRecord(hourOfDay: h, departures: hourMap[h] ?? [])
                        }
                        return TimetableResult(records: records, isHistoricalFallback: dayOffset < 0, isObservedReplay: false)
                    }
                }
            } catch let error as DatabaseError {
                print("⚠️ Transit timetable query failed: \(error.message). Returning fallback timetable.")
            } catch {
                throw error
            }
            
            let effectiveRoutes: [String]
            if !routeIds.isEmpty {
                effectiveRoutes = routeIds
            } else if let rId = routeId, !rId.isEmpty {
                effectiveRoutes = [rId]
            } else {
                effectiveRoutes = [self.inferRouteId(from: stopId, name: stopId)]
            }
            
            let fallbackRecords: [HourScheduleRecord]
            if effectiveRoutes.count > 1 {
                fallbackRecords = self.generateMultiRouteFallbackTimetable(for: stopId, routeIds: effectiveRoutes, directionId: directionId)
            } else {
                fallbackRecords = self.generateFallbackTimetable(for: stopId, routeId: effectiveRoutes.first ?? "L", directionId: directionId)
            }
            let isHistFallback = (dayOffset < 0)
            return TimetableResult(records: fallbackRecords, isHistoricalFallback: isHistFallback, isObservedReplay: false, totalDepartures: fallbackRecords.reduce(0) { $0 + $1.departures.count })
        }
    }
    
    public func fetchTimetable(
        for stopId: String,
        routeId: String? = nil,
        routeIds: [String] = [],
        directionId: Int = 0,
        dayOffset: Int = 0,
        referenceDate: Date = Date()
    ) async throws -> [HourScheduleRecord] {
        let result = try await fetchTimetableResult(for: stopId, routeId: routeId, routeIds: routeIds, directionId: directionId, dayOffset: dayOffset, referenceDate: referenceDate)
        return result.records
    }
    
    public func fetchAvailableDirections(for stopId: String, routeId: String? = nil, routeIds: [String] = []) async throws -> Set<Int> {
        let startTime = CFAbsoluteTimeGetCurrent()
        defer {
            let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000.0
            print("⏱️ fetchAvailableDirections for \(stopId) executed in \(String(format: "%.2f", elapsed))ms")
        }
        
        return try await dbWriter.read { db in
            do {
                try self.ensureTransitAttached(in: db)
                let resolvedIds = self.resolvePlatformStopIds(for: stopId, in: db)
                let idPlaceholders = Array(repeating: "?", count: resolvedIds.count).joined(separator: ", ")
                
                // 1. Check scheduled_hourly_patterns
                let patternCols = try Row.fetchAll(db, sql: "PRAGMA transit.table_info(scheduled_hourly_patterns)")
                if !patternCols.isEmpty {
                    var sql = "SELECT DISTINCT direction_id FROM transit.scheduled_hourly_patterns WHERE stop_id IN (\(idPlaceholders))"
                    var args: [DatabaseValueConvertible] = resolvedIds.map { $0 as DatabaseValueConvertible }
                    if !routeIds.isEmpty {
                        let placeholders = Array(repeating: "?", count: routeIds.count).joined(separator: ", ")
                        sql += " AND route_id IN (\(placeholders))"
                        args.append(contentsOf: routeIds.map { $0 as DatabaseValueConvertible })
                    } else if let rId = routeId, !rId.isEmpty {
                        sql += " AND route_id = ?"
                        args.append(rId)
                    }
                    let rows = try Row.fetchAll(db, sql: sql, arguments: StatementArguments(args))
                    if !rows.isEmpty {
                        let dirs = rows.compactMap { row -> Int? in row["direction_id"] }
                        if !dirs.isEmpty {
                            return Set(dirs)
                        }
                    }
                }
                
                // 2. Check legacy scheduled_stops
                let columns = try Row.fetchAll(db, sql: "PRAGMA transit.table_info(scheduled_stops)")
                if !columns.isEmpty {
                    var sql = "SELECT DISTINCT direction_id FROM transit.scheduled_stops WHERE stop_id IN (\(idPlaceholders))"
                    var args: [DatabaseValueConvertible] = resolvedIds.map { $0 as DatabaseValueConvertible }
                    if !routeIds.isEmpty {
                        let placeholders = Array(repeating: "?", count: routeIds.count).joined(separator: ", ")
                        sql += " AND route_id IN (\(placeholders))"
                        args.append(contentsOf: routeIds.map { $0 as DatabaseValueConvertible })
                    } else if let rId = routeId, !rId.isEmpty {
                        sql += " AND route_id = ?"
                        args.append(rId)
                    }
                    let rows = try Row.fetchAll(db, sql: sql, arguments: StatementArguments(args))
                    if !rows.isEmpty {
                        let dirs = rows.compactMap { row -> Int? in
                            row["direction_id"]
                        }
                        if !dirs.isEmpty {
                            return Set(dirs)
                        }
                    }
                }
            } catch let error as DatabaseError {
                print("⚠️ Transit scheduled_stops query for available directions failed: \(error.message). Returning fallback directions.")
            } catch {
                throw error
            }
            
            // 3. Fallback: Lookup stop_name from database if available to disambiguate one-way corridors and qualifiers
            var stopName = ""
            if let row = try? Row.fetchOne(db, sql: "SELECT stop_name FROM transit.stops WHERE stop_id = ?", arguments: [stopId]) {
                stopName = row["stop_name"] ?? ""
            }
            return self.generateFallbackAvailableDirections(for: stopId, stopName: stopName, routeId: routeId ?? "L")
        }
    }
    
    public func fetchRouteCoordinates(for routeId: String) async throws -> [CLLocationCoordinate2D]? {
        return try await dbWriter.read { db in
            do {
                try self.ensureTransitAttached(in: db)
                let sql = "SELECT lat, lon FROM transit.route_shapes WHERE route_id = ? ORDER BY sequence ASC"
                let rows = try Row.fetchAll(db, sql: sql, arguments: [routeId])
                if !rows.isEmpty {
                    let coords = rows.compactMap { row -> CLLocationCoordinate2D? in
                        let lat: Double? = row["lat"]
                        let lon: Double? = row["lon"]
                        guard let validLat = lat, let validLon = lon else { return nil }
                        return CLLocationCoordinate2D(latitude: validLat, longitude: validLon)
                    }
                    if !coords.isEmpty {
                        return coords
                    }
                }
            } catch {
                // Fallback to static geometries
            }
            return nil
        }
    }
    
    private func generateFallbackReliabilityMatrix(for stopId: String, routeId: String) -> [HourlyReliabilityRecord] {
        var records: [HourlyReliabilityRecord] = []
        let seed = abs(stopId.hashValue ^ routeId.hashValue)
        let isBus = stopId.hasPrefix("BUS_") || TransitRouteData.isBusRoute(routeId) || TransitRouteData.isBusRoute(stopId)
        
        for dow in 0..<7 {
            let isWeekend = (dow == 0 || dow == 6)
            for hour in 0..<24 {
                let cellSeed = (seed + dow * 31 + hour * 17) % 100
                
                var baseOTP: Double
                var medianDelay: Int
                var p90Delay: Int
                var medianHeadway: Int
                var ewt: Double
                
                if hour >= 0 && hour < 5 {
                    // Late night
                    baseOTP = 72.0 + Double(cellSeed % 15)
                    medianDelay = 120 + (cellSeed % 60)
                    p90Delay = 320 + (cellSeed % 120)
                    medianHeadway = isBus ? (1800 + (cellSeed % 600)) : (720 + (cellSeed % 180))
                    ewt = 95.0 + Double(cellSeed % 30)
                } else if !isWeekend && ((hour >= 7 && hour <= 9) || (hour >= 16 && hour <= 19)) {
                    // Peak rush hour
                    baseOTP = 76.0 + Double(cellSeed % 14)
                    medianDelay = 90 + (cellSeed % 50)
                    p90Delay = 260 + (cellSeed % 90)
                    medianHeadway = isBus ? (900 + (cellSeed % 300)) : (240 + (cellSeed % 60))
                    ewt = 65.0 + Double(cellSeed % 25)
                } else if hour >= 10 && hour <= 15 {
                    // Daytime off-peak
                    baseOTP = 88.0 + Double(cellSeed % 11)
                    medianDelay = 45 + (cellSeed % 40)
                    p90Delay = 180 + (cellSeed % 60)
                    medianHeadway = isBus ? (1200 + (cellSeed % 400)) : (360 + (cellSeed % 90))
                    ewt = 45.0 + Double(cellSeed % 20)
                } else {
                    // Evening / Early morning
                    baseOTP = 84.0 + Double(cellSeed % 13)
                    medianDelay = 60 + (cellSeed % 45)
                    p90Delay = 210 + (cellSeed % 70)
                    medianHeadway = isBus ? (1500 + (cellSeed % 300)) : (480 + (cellSeed % 120))
                    ewt = 55.0 + Double(cellSeed % 25)
                }
                
                let sampleCount = 25 + (cellSeed % 50)
                let headwayStdDev = isBus ? (120 + (cellSeed % 90)) : (30 + (cellSeed % 50))
                
                records.append(
                    HourlyReliabilityRecord(
                        routeId: routeId,
                        stopId: stopId,
                        directionId: 0,
                        hourOfDay: hour,
                        dayOfWeek: dow,
                        medianDelaySec: medianDelay,
                        p90DelaySec: p90Delay,
                        medianHeadwaySec: medianHeadway,
                        headwayStdDevSec: headwayStdDev,
                        ewtSeconds: ewt,
                        onTimePct: min(100.0, max(0.0, baseOTP)),
                        sampleCount: sampleCount
                    )
                )
            }
        }
        return records
    }
    
    private func generateFallbackStopEvents(for stopId: String, hourOfDay: Int, dayOfWeek: Int) -> [StopEventRecord] {
        var events: [StopEventRecord] = []
        let routeId = self.inferRouteId(from: stopId, name: stopId)
        let seed = abs(stopId.hashValue ^ hourOfDay.hashValue ^ dayOfWeek.hashValue)
        let count = 8 + (seed % 6)
        
        let now = Date()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        
        for i in 0..<count {
            let eventSeed = (seed + i * 29) % 100
            let minuteOffset = (i * (60 / count)) + (eventSeed % 4)
            let delay = (eventSeed % 7 == 0) ? (180 + (eventSeed % 120)) : ((eventSeed % 5 == 0) ? -(30 + (eventSeed % 30)) : (20 + (eventSeed % 60)))
            
            var components = calendar.dateComponents([.year, .month, .day], from: now)
            components.hour = hourOfDay
            components.minute = minuteOffset
            components.second = (eventSeed * 7) % 60
            
            let scheduledDate = calendar.date(from: components) ?? now
            let actualDate = scheduledDate.addingTimeInterval(TimeInterval(delay))
            let observedDate = actualDate.addingTimeInterval(5)
            
            events.append(
                StopEventRecord(
                    eventId: "EVT_\(stopId)_\(hourOfDay)_\(i)",
                    tripId: "TRIP_\(routeId)_\(hourOfDay)\(minuteOffset)_\(i)",
                    routeId: routeId,
                    stopId: stopId,
                    scheduledTime: scheduledDate,
                    actualTime: actualDate,
                    delaySeconds: delay,
                    observedAt: observedDate,
                    directionId: (i % 2)
                )
            )
        }
        
        events.sort { $0.actualTime > $1.actualTime }
        return events
    }
    
    private func inferRouteId(from stopId: String, name: String) -> String {
        let cleanId = stopId.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanId.hasPrefix("1") && cleanId.count == 3 { return "1" }
        if cleanId.hasPrefix("2") && cleanId.count == 3 { return "2" }
        if cleanId.hasPrefix("3") && cleanId.count == 3 { return "3" }
        if cleanId.hasPrefix("4") && cleanId.count == 3 { return "4" }
        if cleanId.hasPrefix("5") && cleanId.count == 3 { return "5" }
        if cleanId.hasPrefix("6") && cleanId.count == 3 { return "6" }
        if cleanId.hasPrefix("7") && cleanId.count == 3 { return "7" }
        if cleanId.hasPrefix("A") { return "A" }
        if cleanId.hasPrefix("B") { return "B" }
        if cleanId.hasPrefix("C") { return "C" }
        if cleanId.hasPrefix("D") { return "F" }
        if cleanId.hasPrefix("E") { return "E" }
        if cleanId.hasPrefix("F") { return "F" }
        if cleanId.hasPrefix("G") { return "G" }
        if cleanId.hasPrefix("J") || cleanId.hasPrefix("Z") { return "J" }
        if cleanId.hasPrefix("L") { return "L" }
        if cleanId.hasPrefix("M") && cleanId.count == 3 { return "M" }
        if cleanId.hasPrefix("N") { return "N" }
        if cleanId.hasPrefix("Q") { return "Q" }
        if cleanId.hasPrefix("R") { return "R" }
        if cleanId.hasPrefix("W") { return "W" }
        if cleanId.hasPrefix("S") && cleanId.count == 3 { return "SIR" }
        
        let upperName = name.uppercased()
        if upperName.contains("CANARSIE") || upperName.contains("BEDFORD") { return "L" }
        if upperName.contains("CROSSTOWN") || upperName.contains("NASSAU AVE") { return "G" }
        if upperName.contains("FLUSHING") || upperName.contains("CORONA") { return "7" }
        if upperName.contains("LEXINGTON") { return "4" }
        if upperName.contains("SEVENTH") || upperName.contains("BROADWAY-7") { return "1" }
        if upperName.contains("EIGHTH") { return "A" }
        if upperName.contains("SIXTH") { return "F" }
        
        return "L"
    }
    
    private func inferBusRoutes(from stopName: String, stopId: String) -> [String] {
        let upper = stopName.uppercased()
        if upper.contains("CENTRAL PARK WEST") || upper.contains("CPW") || upper.contains("8 AV") || upper.contains("FREDERICK DOUGLASS") { return ["M10", "M20"] }
        if upper.contains("CENTRAL PARK SOUTH") || upper.contains("59 ST") || upper.contains("COLUMBUS CIRCLE") { return ["M10", "M20", "M104"] }
        if upper.contains("7 AV") || upper.contains("SEVENTH") { return ["M7", "M20", "M104"] }
        if upper.contains("57 ST") { return ["M57", "M31"] }
        if upper.contains("66 ST") || upper.contains("65 ST") { return ["M66", "M72"] }
        if upper.contains("72 ST") { return ["M72"] }
        if upper.contains("79 ST") { return ["M79-SBS"] }
        if upper.contains("86 ST") { return ["M86-SBS"] }
        if upper.contains("96 ST") { return ["M96"] }
        if upper.contains("125 ST") { return ["M60-SBS", "M125", "Bx15"] }
        if upper.contains("5 AV") || upper.contains("MADISON") { return ["M1", "M2", "M3", "M4"] }
        if upper.contains("LEXINGTON") || upper.contains("3 AV") { return ["M101", "M102", "M103"] }
        if upper.contains("42 ST") { return ["M42"] }
        if upper.contains("1 AV") || upper.contains("2 AV") { return ["M15-SBS", "M15"] }
        if upper.contains("14 ST") { return ["M14A-SBS", "M14D-SBS"] }
        if upper.contains("23 ST") { return ["M23-SBS"] }
        if upper.contains("34 ST") { return ["M34-SBS", "M34A-SBS"] }
        if upper.contains("BEDFORD") { return ["B62", "B44-SBS"] }
        if upper.contains("GRAND CONCOURSE") { return ["Bx1", "Bx2"] }
        if upper.contains("BROADWAY") { return ["M104", "B57"] }
        if upper.contains("FLATBUSH") { return ["B41"] }
        if upper.contains("AMSTERDAM") || upper.contains("COLUMBUS AV") { return ["M7", "M11", "M104"] }
        return ["M10", "M104"]
    }
    
    private func inferBusDirection(from stopName: String) -> String {
        let upper = stopName.uppercased()
        if upper.contains("(NB)") || upper.hasSuffix(" NB") { return "Northbound" }
        if upper.contains("(SB)") || upper.hasSuffix(" SB") { return "Southbound" }
        if upper.contains("(EB)") || upper.hasSuffix(" EB") { return "Eastbound" }
        if upper.contains("(WB)") || upper.hasSuffix(" WB") { return "Westbound" }
        if upper.contains("KENT AV") { return "Northbound" }
        if upper.contains("WYTHE AV") { return "Southbound" }
        if upper.contains("NB") && !upper.contains("NB 6 ST") && !upper.contains("NB 9 ST") { return "Northbound" }
        if upper.contains("SB") && !upper.contains("SB 6 ST") { return "Southbound" }
        if upper.contains("NORTH") && !upper.contains("CENTRAL PARK NORTH") && !upper.contains("NORTH END") && !upper.contains("NORTH MOORE") { return "Northbound" }
        if upper.contains("SOUTH") && !upper.contains("CENTRAL PARK SOUTH") { return "Southbound" }
        return "North / Southbound"
    }
    
    private func generateBusArrivals(for routeId: String, stopName: String) -> [ArrivalInfo] {
        let availableDirs = generateFallbackAvailableDirections(for: stopName, routeId: routeId)
        let (dest1, dir1) = TransitRealtimeService.resolveBusDestination(routeId: routeId, directionId: 0, stopName: stopName)
        let (dest2, dir2) = TransitRealtimeService.resolveBusDestination(routeId: routeId, directionId: 1, stopName: stopName)
        
        var arrivals: [ArrivalInfo] = []
        if availableDirs.contains(0) {
            arrivals.append(ArrivalInfo(line: routeId, destination: dest1, minutes: 8, direction: dir1, distanceDescription: "0.9 mi away"))
            arrivals.append(ArrivalInfo(line: routeId, destination: dest1, minutes: 23, direction: dir1, distanceDescription: "2.4 mi away"))
        }
        if availableDirs.contains(1) {
            arrivals.append(ArrivalInfo(line: routeId, destination: dest2, minutes: 14, direction: dir2, distanceDescription: "1.5 mi away"))
        }
        return arrivals
    }
    
    private func generateFallbackStopDetails(for stopId: String) -> StopDetails {
        switch stopId {
        case "BUS_001":
            return StopDetails(
                stopId: stopId,
                name: "1 Av & E 14 St",
                routeId: "M15-SBS",
                routeIds: ["M15-SBS", "M15"],
                routeType: 3,
                arrivals: [
                    ArrivalInfo(line: "M15-SBS", destination: "South Ferry", minutes: 2, direction: "Southbound", distanceDescription: "0.3 mi away"),
                    ArrivalInfo(line: "M15", destination: "Lower East Side", minutes: 8, direction: "Southbound", distanceDescription: "1.1 mi away"),
                    ArrivalInfo(line: "M15-SBS", destination: "East Harlem", minutes: 5, direction: "Northbound", distanceDescription: "0.5 mi away")
                ]
            )
        case "BUS_002":
            return StopDetails(
                stopId: stopId,
                name: "E 14 St & 2 Av",
                routeId: "M14A-SBS",
                routeIds: ["M14A-SBS", "M14D-SBS"],
                routeType: 3,
                arrivals: [
                    ArrivalInfo(line: "M14A-SBS", destination: "Lower East Side", minutes: 4, direction: "Eastbound", distanceDescription: "0.4 mi away"),
                    ArrivalInfo(line: "M14D-SBS", destination: "Chelsea Piers", minutes: 11, direction: "Westbound", distanceDescription: "1.2 mi away")
                ]
            )
        case "BUS_003":
            return StopDetails(
                stopId: stopId,
                name: "1 Av & E 18 St",
                routeId: "M15",
                routeIds: ["M15", "M101"],
                routeType: 3,
                arrivals: [
                    ArrivalInfo(line: "M15", destination: "East Harlem", minutes: 5, direction: "Northbound", distanceDescription: "0.6 mi away"),
                    ArrivalInfo(line: "M101", destination: "Fort George", minutes: 13, direction: "Northbound", distanceDescription: "1.4 mi away"),
                    ArrivalInfo(line: "M15", destination: "South Ferry", minutes: 7, direction: "Southbound", distanceDescription: "0.8 mi away")
                ]
            )
        default:
            if let candidate = Self.fallbackBusCandidates.first(where: { $0.id == stopId }) {
                let primaryRoute = candidate.routes.first ?? "M10"
                return StopDetails(
                    stopId: stopId,
                    name: candidate.name,
                    routeId: primaryRoute,
                    routeIds: candidate.routes,
                    routeType: 3,
                    arrivals: self.generateBusArrivals(for: primaryRoute, stopName: candidate.name)
                )
            }
            
            let cleanId = stopId.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
            let isBus = cleanId.hasPrefix("BUS_") || cleanId.hasPrefix("MTA_")
            
            let knownSubwayNames: [String: (name: String, routes: [String])] = [
                "L08": ("Bedford Av", ["L"]),
                "L08N": ("Bedford Av", ["L"]),
                "L08S": ("Bedford Av", ["L"]),
                "STOP_BEDFORD": ("Bedford Av", ["L"]),
                "L01": ("8 Av", ["L"]),
                "L01N": ("8 Av", ["L"]),
                "L01S": ("8 Av", ["L"]),
                "STOP_8TH_AVE": ("8 Av", ["L"]),
                "L02": ("6 Av", ["L"]),
                "L03": ("14 St - Union Sq", ["L", "4", "5", "6", "N", "Q", "R", "W"]),
                "L05": ("3 Av", ["L"]),
                "L06": ("1 Av", ["L"]),
                "L10": ("Lorimer St", ["L", "G"]),
                "STOP_LORIMER": ("Lorimer St", ["L", "G"]),
                "631": ("Brooklyn Bridge-City Hall", ["6", "4", "5", "J", "Z"]),
                "631N": ("Brooklyn Bridge-City Hall", ["6", "4", "5", "J", "Z"]),
                "631S": ("Brooklyn Bridge-City Hall", ["6", "4", "5", "J", "Z"]),
                "STOP_BROOKLYN_BRIDGE": ("Brooklyn Bridge-City Hall", ["6", "4", "5", "J", "Z"]),
                "635": ("14 St - Union Sq", ["6", "5", "4", "6X"]),
                "635N": ("14 St - Union Sq", ["6", "5", "4", "6X"]),
                "635S": ("14 St - Union Sq", ["6", "5", "4", "6X"]),
                "R23": ("Canal St", ["N", "Q", "R", "W", "6", "J", "Z"]),
                "STOP_CANAL": ("Canal St", ["N", "Q", "R", "W", "6", "J", "Z"]),
                "G33": ("Bedford-Nostrand Avs", ["G"]),
                "D03": ("Bedford Park Blvd", ["B", "D"]),
                "405": ("Bedford Park Blvd-Lehman College", ["4"])
            ]
            
            if let known = knownSubwayNames[cleanId] {
                let primaryRoute = known.routes.first ?? "L"
                return StopDetails(
                    stopId: stopId,
                    name: known.name,
                    routeId: primaryRoute,
                    routeIds: known.routes,
                    routeType: 1,
                    arrivals: self.generateArrivals(for: primaryRoute)
                )
            }
            
            let routeId = isBus ? "M15" : "L"
            let routeType = isBus ? 3 : 1
            let name = isBus ? "Bus Stop (\(stopId))" : "Transit Station (\(stopId))"
            let routeIds = isBus ? [routeId] : (stopId == "stop_lorimer" ? ["L", "G"] : [routeId])
            return StopDetails(
                stopId: stopId,
                name: name,
                routeId: routeId,
                routeIds: routeIds,
                routeType: routeType,
                arrivals: isBus ? self.generateBusArrivals(for: routeId, stopName: name) : self.generateArrivals(for: routeId)
            )
        }
    }
    
    private func generateArrivals(for routeId: String) -> [ArrivalInfo] {
        switch routeId.uppercased() {
        case "L":
            return [
                ArrivalInfo(line: "L", destination: "8th Ave", minutes: 3, direction: "Manhattan-bound", distanceDescription: "2 stops away"),
                ArrivalInfo(line: "L", destination: "Canarsie - Rockaway Pkwy", minutes: 5, direction: "Brooklyn-bound", distanceDescription: "1 stop away"),
                ArrivalInfo(line: "L", destination: "8th Ave", minutes: 9, direction: "Manhattan-bound", distanceDescription: "5 stops away"),
                ArrivalInfo(line: "L", destination: "Canarsie - Rockaway Pkwy", minutes: 14, direction: "Brooklyn-bound", distanceDescription: "6 stops away")
            ]
        case "G":
            return [
                ArrivalInfo(line: "G", destination: "Court Sq", minutes: 4, direction: "Queens-bound", distanceDescription: "2 stops away"),
                ArrivalInfo(line: "G", destination: "Church Ave", minutes: 7, direction: "Brooklyn-bound", distanceDescription: "3 stops away"),
                ArrivalInfo(line: "G", destination: "Court Sq", minutes: 14, direction: "Queens-bound", distanceDescription: "7 stops away")
            ]
        case "7", "7X":
            return [
                ArrivalInfo(line: "7", destination: "Flushing - Main St", minutes: 2, direction: "Queens-bound", distanceDescription: "1 stop away"),
                ArrivalInfo(line: "7", destination: "34 St - Hudson Yards", minutes: 5, direction: "Manhattan-bound", distanceDescription: "3 stops away"),
                ArrivalInfo(line: "7", destination: "Flushing - Main St", minutes: 9, direction: "Queens-bound", distanceDescription: "6 stops away")
            ]
        case "A", "C", "E":
            return [
                ArrivalInfo(line: "A", destination: "Inwood - 207 St", minutes: 2, direction: "Uptown & Queens / Bronx", distanceDescription: "1 stop away"),
                ArrivalInfo(line: "C", destination: "Euclid Ave", minutes: 5, direction: "Downtown & Brooklyn", distanceDescription: "3 stops away"),
                ArrivalInfo(line: "E", destination: "World Trade Center", minutes: 8, direction: "Downtown & Brooklyn", distanceDescription: "5 stops away"),
                ArrivalInfo(line: "A", destination: "Far Rockaway", minutes: 12, direction: "Downtown & Brooklyn", distanceDescription: "7 stops away")
            ]
        case "1", "2", "3":
            return [
                ArrivalInfo(line: "1", destination: "Van Cortlandt Park", minutes: 3, direction: "Uptown & Bronx", distanceDescription: "2 stops away"),
                ArrivalInfo(line: "2", destination: "Flatbush Ave", minutes: 6, direction: "Downtown & Brooklyn", distanceDescription: "4 stops away"),
                ArrivalInfo(line: "3", destination: "Harlem - 148 St", minutes: 12, direction: "Uptown & Bronx", distanceDescription: "8 stops away")
            ]
        case "4", "5", "6", "6X":
            return [
                ArrivalInfo(line: "4", destination: "Woodlawn", minutes: 2, direction: "Uptown & Bronx", distanceDescription: "1 stop away"),
                ArrivalInfo(line: "5", destination: "Flatbush Ave", minutes: 5, direction: "Downtown & Brooklyn", distanceDescription: "3 stops away"),
                ArrivalInfo(line: "6", destination: "Pelham Bay Park", minutes: 8, direction: "Uptown & Bronx", distanceDescription: "5 stops away")
            ]
        case "B", "D", "F", "M":
            return [
                ArrivalInfo(line: "F", destination: "Jamaica - 179 St", minutes: 3, direction: "Uptown & Queens / Bronx", distanceDescription: "2 stops away"),
                ArrivalInfo(line: "M", destination: "Middle Village", minutes: 7, direction: "Downtown & Brooklyn", distanceDescription: "4 stops away"),
                ArrivalInfo(line: "F", destination: "Coney Island", minutes: 10, direction: "Downtown & Brooklyn", distanceDescription: "6 stops away")
            ]
        case "N", "Q", "R", "W":
            return [
                ArrivalInfo(line: "N", destination: "Astoria - Ditmars Blvd", minutes: 3, direction: "Uptown & Queens", distanceDescription: "2 stops away"),
                ArrivalInfo(line: "Q", destination: "Coney Island", minutes: 6, direction: "Downtown & Brooklyn", distanceDescription: "4 stops away"),
                ArrivalInfo(line: "R", destination: "Bay Ridge - 95 St", minutes: 11, direction: "Downtown & Brooklyn", distanceDescription: "6 stops away")
            ]
        case "J", "Z":
            return [
                ArrivalInfo(line: "J", destination: "Jamaica Center", minutes: 4, direction: "Queens-bound", distanceDescription: "2 stops away"),
                ArrivalInfo(line: "J", destination: "Broad St", minutes: 8, direction: "Manhattan-bound", distanceDescription: "4 stops away")
            ]
        case "SIR":
            return [
                ArrivalInfo(line: "SIR", destination: "St George", minutes: 5, direction: "Inbound (St. George)", distanceDescription: "3 stops away"),
                ArrivalInfo(line: "SIR", destination: "Tottenville", minutes: 12, direction: "Outbound (Tottenville)", distanceDescription: "7 stops away")
            ]
        default:
            if TransitRealtimeService.SubwayFeed.isBusRoute(routeId) {
                let (dest1, dir1) = TransitRealtimeService.resolveBusDestination(routeId: routeId, directionId: 0)
                let (dest2, dir2) = TransitRealtimeService.resolveBusDestination(routeId: routeId, directionId: 1)
                return [
                    ArrivalInfo(line: routeId, destination: dest1, minutes: 3, direction: dir1, distanceDescription: "2 stops away"),
                    ArrivalInfo(line: routeId, destination: dest2, minutes: 8, direction: dir2, distanceDescription: "5 stops away")
                ]
            }
            return [
                ArrivalInfo(line: routeId, destination: "Uptown / Terminal", minutes: 3, direction: "Uptown & Northbound", distanceDescription: "2 stops away"),
                ArrivalInfo(line: routeId, destination: "Downtown / Terminal", minutes: 8, direction: "Downtown & Southbound", distanceDescription: "5 stops away")
            ]
        }
    }
    
    private func generateFallbackHeadways(for stopId: String) -> [Double] {
        let hash = abs(stopId.hashValue)
        let isBus = stopId.hasPrefix("BUS_") || TransitRouteData.isBusRoute(stopId)
        let base: Double = isBus ? (15.0 + Double(hash % 10)) : (4.0 + Double(hash % 3))
        return [
            base + 0.3,
            base - 0.5,
            base + 1.2,
            base - 0.2,
            base + 0.8,
            base + 0.1,
        ]
    }
    
    private func generateFallbackAvailableDirections(for stopId: String, stopName: String = "", routeId: String) -> Set<Int> {
        let lowerId = stopId.lowercased()
        let lowerName = stopName.lowercased()
        let upperName = stopName.uppercased()

        // Explicit directional routing qualifiers in stop name (e.g. (NB), (SB), (EB), (WB))
        if upperName.contains("(NB)") || upperName.hasSuffix(" NB") {
            return [0]
        }
        if upperName.contains("(SB)") || upperName.hasSuffix(" SB") {
            return [1]
        }
        if upperName.contains("(EB)") || upperName.hasSuffix(" EB") {
            return [0]
        }
        if upperName.contains("(WB)") || upperName.hasSuffix(" WB") {
            return [1]
        }

        // Single-direction terminal patterns or one-way stops
        if lowerId.contains("8th_ave") || lowerId.contains("eighth_ave") || lowerId.contains("van_cortlandt") || lowerId.contains("wakefield") || lowerId.contains("inwood") || lowerId.contains("flushing") || lowerId.contains("pelham") || lowerId.contains("norwood") || lowerId.contains("dir1_only") {
            return [1] // Southbound / Brooklyn / Outbound only
        }
        if lowerId.contains("canarsie") || lowerId.contains("rockaway") || lowerId.contains("south_ferry") || lowerId.contains("flatbush") || lowerId.contains("coney_island") || lowerId.contains("church_ave") || lowerId.contains("hudson_yards") || lowerId.contains("world_trade") || lowerId.contains("broad_st") || lowerId.contains("tottenville") || lowerId.contains("dir0_only") {
            return [0] // Northbound / Manhattan / Inbound only
        }
        if lowerId.contains("1way_sb") || lowerId.contains("1way_south") {
            return [1]
        }
        if lowerId.contains("1way_nb") || lowerId.contains("1way_north") {
            return [0]
        }
        // Known one-way bus corridors & stop IDs (Kent Av is NB only, Wythe Av is SB only)
        if stopId == "308666" || stopId == "308667" || stopId == "308668" ||
           ((lowerId.contains("kent") || lowerName.contains("kent av")) && (routeId == "B32" || lowerId.contains("b32") || routeId.isEmpty)) {
            return [0] // Northbound only on Kent Av
        }
        if stopId == "308683" ||
           ((lowerId.contains("wythe") || lowerName.contains("wythe av")) && (routeId == "B32" || lowerId.contains("b32") || routeId.isEmpty)) {
            return [1] // Southbound only on Wythe Av
        }
        return [0, 1]
    }
    
    private func generateFallbackTimetable(for stopId: String, routeId: String, directionId: Int) -> [HourScheduleRecord] {
        let availableDirs = generateFallbackAvailableDirections(for: stopId, routeId: routeId)
        if !availableDirs.contains(directionId) {
            return (0..<24).map { HourScheduleRecord(hourOfDay: $0, departures: []) }
        }
        
        var hourRecords: [HourScheduleRecord] = []
        let seed = abs(stopId.hashValue ^ routeId.hashValue ^ (directionId * 79))
        let isBus = stopId.hasPrefix("BUS_") || routeId.contains("-") || TransitRouteData.isBusRoute(routeId)
        let isSBS = routeId.contains("SBS") || routeId.contains("+")
        
        let destination: String
        if isBus || TransitRealtimeService.SubwayFeed.isBusRoute(routeId) {
            destination = TransitRealtimeService.resolveBusDestination(routeId: routeId, directionId: directionId).destination
        } else {
            switch routeId {
            case "L":
                destination = directionId == 0 ? "Manhattan - 8th Ave" : "Brooklyn - Canarsie"
            case "G":
                destination = directionId == 0 ? "Court Sq" : "Church Ave"
            case "7":
                destination = directionId == 0 ? "Flushing - Main St" : "34 St - Hudson Yards"
            case "A", "C", "E":
                destination = directionId == 0 ? "Inwood - 207 St" : "Far Rockaway / Lefferts"
            case "1", "2", "3":
                destination = directionId == 0 ? "Van Cortlandt / Harlem" : "South Ferry / Flatbush"
            default:
                destination = directionId == 0 ? "Uptown / Manhattan" : "Downtown / Brooklyn"
            }
        }
        
        var allDepartures: [(hour: Int, min: Int, isExp: Bool)] = []
        
        for hour in 0..<24 {
            let hourSeed = (seed + hour * 37) % 100
            let departureCount: Int
            
            if isBus {
                if hour >= 0 && hour < 6 {
                    // Late night bus: 0 departures for daytime-only routes (like B32), 1-2 for SBS/trunks
                    departureCount = isSBS ? (1 + (hourSeed % 2)) : 0
                } else if (hour >= 7 && hour <= 9) || (hour >= 16 && hour <= 19) {
                    // Peak rush hour bus: 5-7 dep/hr for SBS, 2-3 dep/hr (~20-30m) for local buses
                    departureCount = isSBS ? (5 + (hourSeed % 3)) : (2 + (hourSeed % 2))
                } else if hour >= 10 && hour <= 15 {
                    // Midday off-peak bus: 4-5 dep/hr for SBS, 2 dep/hr (~30m) for local buses
                    departureCount = isSBS ? (4 + (hourSeed % 2)) : 2
                } else if hour >= 21 {
                    // Late evening bus (9 PM - midnight): reduced service / winding down
                    departureCount = isSBS ? 2 : (hourSeed % 2)
                } else {
                    // Early morning / Evening bus: 3-4 dep/hr for SBS, 2 dep/hr for local buses
                    departureCount = isSBS ? (3 + (hourSeed % 2)) : 2
                }
            } else {
                if hour >= 0 && hour < 5 {
                    // Late night subway: 3-4 departures / hour (15-20 min headways)
                    departureCount = 3 + (hourSeed % 2)
                } else if (hour >= 7 && hour <= 9) || (hour >= 16 && hour <= 19) {
                    // Peak rush hour subway: 12-16 departures / hour (3-5 min headways)
                    departureCount = 12 + (hourSeed % 5)
                } else if hour >= 10 && hour <= 15 {
                    // Midday off-peak subway: 7-10 departures / hour (6-8 min headways)
                    departureCount = 7 + (hourSeed % 4)
                } else {
                    // Evening / Early morning subway: 5-7 departures / hour (8-12 min headways)
                    departureCount = 5 + (hourSeed % 3)
                }
            }
            
            if departureCount > 0 {
                var minutes: [Int] = []
                let interval = max(1, 60 / departureCount)
                for i in 0..<departureCount {
                    let jitter = (hourSeed + i * 11) % 3 - 1
                    let m = max(0, min(59, (i * interval) + jitter + ((hourSeed % 3))))
                    if !minutes.contains(m) {
                        minutes.append(m)
                    }
                }
                minutes.sort()
                
                for m in minutes {
                    let isExp = (routeId == "A" || routeId == "2" || routeId == "4" || routeId == "5" || routeId == "7" || routeId.contains("SBS")) && ((m + hourSeed) % 4 == 0)
                    allDepartures.append((hour: hour, min: m, isExp: isExp))
                }
            }
        }
        
        let firstIndex = allDepartures.firstIndex(where: { $0.hour == 5 }) ?? 0
        let lastIndex = (allDepartures.lastIndex(where: { $0.hour == 4 }) ?? (allDepartures.count - 1))
        
        var depMap: [Int: [DeparturePillRecord]] = [:]
        for h in 0..<24 {
            depMap[h] = []
        }
        
        for (idx, item) in allDepartures.enumerated() {
            let isFirst = idx == firstIndex
            let isLast = idx == lastIndex
            let tripId = "TRIP_\(routeId)_\(item.hour)\(String(format: "%02d", item.min))_\(idx)"
            
            let pill = DeparturePillRecord(
                id: "\(tripId)_\(item.hour)_\(item.min)",
                tripId: tripId,
                routeId: routeId,
                destination: destination,
                directionId: directionId,
                minute: item.min,
                isExpress: item.isExp,
                isFirstDeparture: isFirst,
                isLastDeparture: isLast
            )
            depMap[item.hour]?.append(pill)
        }
        
        for h in 0..<24 {
            hourRecords.append(HourScheduleRecord(hourOfDay: h, departures: depMap[h] ?? []))
        }
        
        return hourRecords
    }
    
    private func generateMultiRouteFallbackTimetable(for stopId: String, routeIds: [String], directionId: Int) -> [HourScheduleRecord] {
        var mergedHourMap: [Int: [DeparturePillRecord]] = [:]
        for h in 0..<24 {
            mergedHourMap[h] = []
        }
        
        for rId in routeIds {
            let singleTimetable = generateFallbackTimetable(for: stopId, routeId: rId, directionId: directionId)
            for hourRec in singleTimetable {
                mergedHourMap[hourRec.hourOfDay]?.append(contentsOf: hourRec.departures)
            }
        }
        
        var result: [HourScheduleRecord] = []
        for h in 0..<24 {
            let sortedDepartures = (mergedHourMap[h] ?? []).sorted { $0.minute < $1.minute }
            result.append(HourScheduleRecord(hourOfDay: h, departures: sortedDepartures))
        }
        return result
    }
}

