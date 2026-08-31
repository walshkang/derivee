import XCTest
import CoreLocation
import GRDB
import MapLibre
import H3
@testable import Derivee

final class DynamicBoundsMigrationTests: XCTestCase {
    
    override func setUp() {
        super.setUp()
        CameraBounds.resetToDefault()
    }
    
    override func tearDown() {
        CameraBounds.resetToDefault()
        super.tearDown()
    }
    
    // MARK: - 1. Zero-Downtime Schema Migration (v5)
    
    func testZeroDowntimeV5MigrationRenamesExploredHexesToExploredHexesNyc() throws {
        // Setup raw in-memory SQLite database running v1..v4
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("derivee_mig_test_\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: tempURL) }
        
        let dbQueue = try DatabaseQueue(path: tempURL.path)
        
        var v1to4Migrator = DatabaseMigrator()
        v1to4Migrator.registerMigration("v1") { db in
            try db.create(table: "explored_hexes") { t in
                t.column("h3_index", .text).primaryKey()
            }
        }
        v1to4Migrator.registerMigration("v2") { db in
            try db.create(table: "meta", options: .withoutRowID) { t in
                t.column("key", .text).primaryKey()
                t.column("value", .text)
            }
        }
        v1to4Migrator.registerMigration("v3") { db in
            try db.create(table: "discovered_pois", options: .withoutRowID) { t in
                t.column("poi_id", .text).primaryKey()
            }
        }
        v1to4Migrator.registerMigration("v4") { db in
            try db.create(table: "explored_hexes_new") { t in
                t.column("h3_index", .text).primaryKey()
            }
            try db.execute(sql: "INSERT INTO explored_hexes_new SELECT * FROM explored_hexes")
            try db.drop(table: "explored_hexes")
            try db.rename(table: "explored_hexes_new", to: "explored_hexes")
        }
        
        try v1to4Migrator.migrate(dbQueue)
        
        // Seed legacy explored_hexes with 3 test hexes
        let legacyHexes = ["8b2a1072b4cdfff", "8b2a1072b4c8fff", "8b2a1072b4cbfff"]
        try dbQueue.write { db in
            for hex in legacyHexes {
                try db.execute(sql: "INSERT INTO explored_hexes (h3_index) VALUES (?)", arguments: [hex])
            }
        }
        
        // Apply v5 migration
        var fullMigrator = v1to4Migrator
        fullMigrator.registerMigration("v5") { db in
            let hasLegacy = try db.tableExists("explored_hexes")
            let hasNyc = try db.tableExists("explored_hexes_nyc")
            
            if hasLegacy && !hasNyc {
                try db.execute(sql: "ALTER TABLE explored_hexes RENAME TO explored_hexes_nyc;")
            } else if !hasNyc {
                try db.create(table: "explored_hexes_nyc") { t in
                    t.column("h3_index", .text).primaryKey()
                }
            }
        }
        
        try fullMigrator.migrate(dbQueue)
        
        // Verify migration outcome:
        // 1. Legacy table is renamed / gone
        // 2. explored_hexes_nyc exists
        // 3. 100% of data is preserved
        try dbQueue.read { db in
            XCTAssertFalse(try db.tableExists("explored_hexes"), "Legacy explored_hexes table must be renamed")
            XCTAssertTrue(try db.tableExists("explored_hexes_nyc"), "explored_hexes_nyc table must exist")
            
            let migratedCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM explored_hexes_nyc") ?? 0
            XCTAssertEqual(migratedCount, legacyHexes.count, "All legacy hexes must be preserved")
            
            let fetchedHexes = try String.fetchAll(db, sql: "SELECT h3_index FROM explored_hexes_nyc")
            XCTAssertEqual(Set(fetchedHexes), Set(legacyHexes), "Migrated hexes must match exact legacy values")
        }
    }
    
    // MARK: - 2. Multi-City Table Creation & Isolation
    
    func testMultiCityTableCreationAndExplorationIsolation() async throws {
        let dbManager = SpatialDatabaseManager.makeForTesting(inMemory: true)
        
        // Insert hexes into NYC
        let nycHexes = ["8b2a1072b4cdfff", "8b2a1072b4c8fff"]
        try await dbManager.insertHexesBatch(h3Indices: nycHexes, citySlug: "nyc")
        
        // Insert hexes into Boston
        let bosHexes = ["8b2a304e1b5bfff", "8b2a304e1b58fff", "8b2a304e1b59fff"]
        try await dbManager.insertHexesBatch(h3Indices: bosHexes, citySlug: "bos")
        
        // Insert hexes into Chicago
        let chiHexes = ["8b2664c1256afff"]
        try await dbManager.insertHexesBatch(h3Indices: chiHexes, citySlug: "chi")
        
        // Verify isolation
        let fetchedNyc = try await dbManager.fetchExploredHexes(citySlug: "nyc")
        let fetchedBos = try await dbManager.fetchExploredHexes(citySlug: "bos")
        let fetchedChi = try await dbManager.fetchExploredHexes(citySlug: "chi")
        
        XCTAssertEqual(fetchedNyc, Set(nycHexes), "NYC hexes must be isolated")
        XCTAssertEqual(fetchedBos, Set(bosHexes), "Boston hexes must be isolated")
        XCTAssertEqual(fetchedChi, Set(chiHexes), "Chicago hexes must be isolated")
        
        // Reset Boston only
        try await dbManager.resetExplorationData(citySlug: "bos")
        let postResetBos = try await dbManager.fetchExploredHexes(citySlug: "bos")
        let postResetNyc = try await dbManager.fetchExploredHexes(citySlug: "nyc")
        
        XCTAssertEqual(postResetBos.count, 0, "Boston hexes should be cleared")
        XCTAssertEqual(postResetNyc.count, 2, "NYC hexes must remain intact after Boston reset")
    }
    
    // MARK: - 3. SpatialStore Dynamic City Hot-Switch
    
    @MainActor
    func testSpatialStoreDynamicCityHotSwitch() async throws {
        let dbManager = SpatialDatabaseManager.makeForTesting(inMemory: true)
        
        // Populate initial NYC and Boston hexes
        try await dbManager.insertHexesBatch(h3Indices: ["8b2a1072b4cdfff"], citySlug: "nyc")
        try await dbManager.insertHexesBatch(h3Indices: ["8b2a304e1b5bfff", "8b2a304e1b58fff"], citySlug: "bos")
        
        let store = SpatialStore(
            dbManager: dbManager,
            cityConfig: .nycDefault,
            liveUpdatePriority: .userInitiated,
            observationScheduler: .immediate
        )
        
        // Wait for initial NYC observation
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(store.activeCitySlug, "nyc")
        XCTAssertEqual(store.exploredHexes.count, 1)
        XCTAssertEqual(CameraBounds.activeConfig.slug, "nyc")
        
        // Hot-switch to Boston
        store.setActiveCity(.bostonDefault)
        XCTAssertEqual(store.activeCitySlug, "bos")
        XCTAssertEqual(CameraBounds.activeConfig.slug, "bos")
        
        // Wait for Boston observation to load
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(store.exploredHexes.count, 2, "SpatialStore should reactively observe Boston hexes after city switch")
        XCTAssertTrue(store.exploredHexes.contains("8b2a304e1b5bfff"))
        
        // Insert new Boston hex via dbManager
        _ = try await dbManager.insertDiscoveredHex(h3Index: "8b2a304e1b59fff", citySlug: "bos", enforceLandOnly: false)
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(store.exploredHexes.count, 3, "New Boston hex should be observed in SpatialStore")
        
        // Switch back to NYC
        store.setActiveCity(.nycDefault)
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(store.activeCitySlug, "nyc")
        XCTAssertEqual(store.exploredHexes.count, 1, "Switching back to NYC should restore NYC hexes")
    }
    
    // MARK: - 4. Strict Land-Only Water Fog Policy & Quiet Water Gliding
    
    func testStrictLandOnlyWaterFogPolicyAndQuietWaterGliding() async throws {
        // Attach a mock neighborhood database to test land vs water separation
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("derivee_land_test_\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: tempURL) }
        
        let landQueue = try DatabaseQueue(path: tempURL.path)
        try await landQueue.write { db in
            try db.execute(sql: """
                CREATE TABLE neighborhood_hexes (
                    h3_index TEXT PRIMARY KEY,
                    neighborhood_id TEXT
                );
                INSERT INTO neighborhood_hexes (h3_index, neighborhood_id) VALUES ('land_hex_1', 'MN01');
                INSERT INTO neighborhood_hexes (h3_index, neighborhood_id) VALUES ('land_hex_2', 'MN02');
            """)
        }
        
        let dbManager = SpatialDatabaseManager.makeForTesting(inMemory: true, customNeighborhoodURL: tempURL)
        
        // 1. Test Land Hex: Should be accepted and inserted
        let isLandInserted = try await dbManager.insertDiscoveredHex(h3Index: "land_hex_1", citySlug: "nyc", enforceLandOnly: true)
        XCTAssertTrue(isLandInserted, "Terrestrial land hex must be successfully inserted")
        
        let nycHexes = try await dbManager.fetchExploredHexes(citySlug: "nyc")
        XCTAssertTrue(nycHexes.contains("land_hex_1"))
        
        // 2. Test Open Water Hex: Should be rejected (Quiet Water Gliding)
        let isWaterInserted = try await dbManager.insertDiscoveredHex(h3Index: "water_hex_east_river", citySlug: "nyc", enforceLandOnly: true)
        XCTAssertFalse(isWaterInserted, "Open water hex must return false to enable quiet water gliding without fog clearance")
        
        let nycHexesAfterWater = try await dbManager.fetchExploredHexes(citySlug: "nyc")
        XCTAssertFalse(nycHexesAfterWater.contains("water_hex_east_river"), "Water hex must NOT be inserted into explored_hexes")
        
        // 3. Test insertDiscoveredHex with enforceLandOnly = false (e.g. forced admin/debug import)
        let isForcedInserted = try await dbManager.insertDiscoveredHex(h3Index: "water_hex_east_river", citySlug: "nyc", enforceLandOnly: false)
        XCTAssertTrue(isForcedInserted, "When enforceLandOnly is false, hex is inserted")
    }
    
    // MARK: - 5. Multi-City Fog Bounding Polygon & Global World Mask CW Math
    
    func testMultiCityFogBoundingPolygonCWMath() {
        let configs: [CityConfig] = [.nycDefault, .bostonDefault, .chicagoDefault]
        
        for config in configs {
            let bounds = FogPolygonMath.makeBounds(for: config)
            XCTAssertEqual(bounds.count, 5, "Exterior polygon must have 5 points (closed loop)")
            XCTAssertEqual(bounds.first?.latitude, bounds.last?.latitude, "Exterior polygon loop must be closed")
            XCTAssertEqual(bounds.first?.longitude, bounds.last?.longitude, "Exterior polygon loop must be closed")
            
            let area = FogPolygonMath.shoelaceSignedArea(bounds)
            XCTAssertGreaterThan(area, 0, "Exterior bounds for \(config.displayName) must have Clockwise (CW) winding order for MapLibre Native")
            
            // Generate fog polygon
            let fogPoly = FogPolygonMath.generateFogPolygon(hexes: ["8b2a1072b4cdfff"], config: config)
            XCTAssertEqual(fogPoly.pointCount, 5)
            
            // Generate composite fog shape
            let fogShape = FogPolygonMath.generateFogShape(hexes: ["8b2a1072b4cdfff"], config: config)
            XCTAssertNotNil(fogShape)
        }
        
        // Test Global World Fog Mask (Wave M.5.1)
        let worldBounds = FogPolygonMath.makeWorldBounds()
        XCTAssertEqual(worldBounds.count, 5)
        XCTAssertEqual(worldBounds.first?.latitude, worldBounds.last?.latitude)
        XCTAssertEqual(worldBounds.first?.longitude, worldBounds.last?.longitude)
        let worldArea = FogPolygonMath.shoelaceSignedArea(worldBounds)
        XCTAssertGreaterThan(worldArea, 0, "Global world fog bounds must have Clockwise (CW) winding order")
        
        let globalFogPoly = FogPolygonMath.generateFogPolygon(hexes: ["8b2a1072b4cdfff"])
        XCTAssertEqual(globalFogPoly.pointCount, 5)
        let globalFogShape = FogPolygonMath.generateFogShape(hexes: ["8b2a1072b4cdfff"])
        XCTAssertNotNil(globalFogShape)
    }
}
