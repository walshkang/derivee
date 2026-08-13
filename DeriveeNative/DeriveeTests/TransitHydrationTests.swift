import XCTest
import GRDB
@testable import Derivee

final class TransitHydrationTests: XCTestCase {

    private var tempDirectoryURL: URL!
    private var mockTransitURL: URL!
    private var dbManager: SpatialDatabaseManager!

    override func setUpWithError() throws {
        try super.setUpWithError()
        
        // 1. Synthesize isolated temporary directory for XCTest sandbox
        tempDirectoryURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectoryURL, withIntermediateDirectories: true)
        
        mockTransitURL = tempDirectoryURL.appendingPathComponent("transit_delta.sqlite")
        
        // 2. Populate mock transit SQLite file on disk
        let mockDB = try DatabaseQueue(path: mockTransitURL.path)
        try mockDB.write { db in
            try db.execute(sql: """
                CREATE TABLE stops (
                    stop_id TEXT PRIMARY KEY,
                    stop_name TEXT NOT NULL,
                    stop_lat REAL NOT NULL,
                    stop_lon REAL NOT NULL
                );
                INSERT INTO stops VALUES ('stop_columbus', 'Columbus Circle Station', 40.768075, -73.981897);
                INSERT INTO stops VALUES ('stop_timessq', 'Times Square Station', 40.758000, -73.985500);
            """)
        }
        
        // 3. Initialize SpatialDatabaseManager with custom transit URL
        dbManager = SpatialDatabaseManager.makeForTesting(inMemory: true, customTransitURL: mockTransitURL)
    }

    override func tearDownWithError() throws {
        dbManager = nil
        if let tempURL = tempDirectoryURL {
            try? FileManager.default.removeItem(at: tempURL)
        }
        try super.tearDownWithError()
    }

    func testAttachedTransitDatabaseQuery() async throws {
        let stopCount = try await dbManager.dbWriter.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM transit.stops") ?? 0
        }
        XCTAssertEqual(stopCount, 2, "Attached transit database should contain 2 mock stops.")
        
        let columbusName = try await dbManager.dbWriter.read { db in
            try String.fetchOne(db, sql: "SELECT stop_name FROM transit.stops WHERE stop_id = 'stop_columbus'")
        }
        XCTAssertEqual(columbusName, "Columbus Circle Station")
    }

    func testCrossDatabaseJoinQuery() async throws {
        // Insert a discovered POI into the main spatial database
        try await dbManager.insertDiscoveredPOI("stop_columbus")
        
        // Perform joint query across main database (discovered_pois) and attached database (transit.stops)
        let joinedStopNames = try await dbManager.dbWriter.read { db in
            try String.fetchAll(db, sql: """
                SELECT t.stop_name 
                FROM discovered_pois d
                JOIN transit.stops t ON d.poi_id = t.stop_id
            """)
        }
        
        XCTAssertEqual(joinedStopNames.count, 1)
        XCTAssertEqual(joinedStopNames.first, "Columbus Circle Station", "Cross-database JOIN should resolve attached transit stop name.")
    }

    func testHydrationMetadataFlagOperations() async throws {
        // Initially incomplete
        let initialComplete = try await dbManager.isHydrationComplete()
        XCTAssertFalse(initialComplete, "Hydration complete flag should default to false.")
        
        // Set hydration complete
        try await dbManager.setHydrationComplete()
        
        // Assert updated flag
        let updatedComplete = try await dbManager.isHydrationComplete()
        XCTAssertTrue(updatedComplete, "Hydration complete flag should return true after setHydrationComplete().")
    }

    func testGracefulRecoveryWhenTransitDatabaseAbsent() async throws {
        let nonExistentURL = tempDirectoryURL.appendingPathComponent("non_existent.sqlite")
        let fallbackDBManager = SpatialDatabaseManager.makeForTesting(inMemory: true, customTransitURL: nonExistentURL)
        
        // Should initialize without crashing
        try await fallbackDBManager.insertDiscoveredHex(h3Index: "8b2a10089081fff")
        
        let count = try await fallbackDBManager.dbWriter.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM explored_hexes") ?? 0
        }
        XCTAssertEqual(count, 1, "Main spatial operations must function normally even if transit DB is absent.")
    }
}
