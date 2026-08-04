import XCTest
import GRDB
import CoreLocation
import MapLibre
@testable import Derivee

final class ExplorationResetTests: XCTestCase {

    private var dbManager: SpatialDatabaseManager!

    override func setUpWithError() throws {
        try super.setUpWithError()
        // Initialize an in-memory database for fresh isolated tests
        dbManager = SpatialDatabaseManager(inMemory: true)
    }

    override func tearDownWithError() throws {
        dbManager = nil
        try super.tearDownWithError()
    }

    func testDatabaseResetClearsExploredHexes() async throws {
        // 1. Insert mock data
        try await dbManager.insertDiscoveredHex(h3Index: "8b2a10089081fff")
        try await dbManager.insertDiscoveredHex(h3Index: "8b2a10089082fff")
        
        // 2. Verify insertion
        let initialCount = try await dbManager.dbWriter.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM explored_hexes") ?? 0
        }
        XCTAssertEqual(initialCount, 2, "Database should have 2 hexes before reset.")
        
        // 3. Perform reset
        try await dbManager.resetExplorationData()
        
        // 4. Verify deletion
        let finalCount = try await dbManager.dbWriter.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM explored_hexes") ?? 0
        }
        XCTAssertEqual(finalCount, 0, "Database should have 0 hexes after reset.")
    }
    
    @MainActor
    func testSpatialStoreClearDataResetsState() async throws {
        let store = SpatialStore(dbManager: dbManager)
        
        // 1. Inject mock state
        store.exploredHexes = ["8b2a10089081fff", "8b2a10089082fff"]
        store.discoveredPOIs = ["poi_123"]
        store.currentFogShape = MLNPolygon(coordinates: [CLLocationCoordinate2D(latitude: 0, longitude: 0)], count: 1)
        
        XCTAssertFalse(store.exploredHexes.isEmpty)
        XCTAssertFalse(store.discoveredPOIs.isEmpty)
        XCTAssertNotNil(store.currentFogShape)
        
        // 2. Clear data
        store.clearData()
        
        // 3. Verify state is fully wiped
        XCTAssertTrue(store.exploredHexes.isEmpty, "exploredHexes should be empty after clearData()")
        XCTAssertTrue(store.discoveredPOIs.isEmpty, "discoveredPOIs should be empty after clearData()")
        XCTAssertNil(store.currentFogShape, "currentFogShape should be nil after clearData()")
        XCTAssertNil(store.transientHexShape, "transientHexShape should be nil after clearData()")
    }
}
