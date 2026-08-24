import XCTest
import GRDB
import CoreLocation
@testable import Derivee

final class BusTerminalNameResolutionTests: XCTestCase {
    
    private var tempDirectoryURL: URL!
    private var mockTransitURL: URL!
    private var dbManager: SpatialDatabaseManager!
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        
        tempDirectoryURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectoryURL, withIntermediateDirectories: true)
        
        mockTransitURL = tempDirectoryURL.appendingPathComponent("transit_delta.sqlite")
        
        let mockDB = try DatabaseQueue(path: mockTransitURL.path)
        try mockDB.write { db in
            try db.execute(sql: """
                CREATE TABLE stops (
                    stop_id TEXT PRIMARY KEY,
                    stop_name TEXT NOT NULL,
                    stop_lat REAL NOT NULL,
                    stop_lon REAL NOT NULL,
                    location_type INTEGER NOT NULL DEFAULT 0,
                    routes TEXT NOT NULL DEFAULT "",
                    parent_station TEXT DEFAULT NULL
                );
                
                -- Tier 1: Descriptive standalone stop
                INSERT INTO stops VALUES ('STOP_WILLIS', 'WILLIS AV/E 138 ST', 40.8080, -73.9240, 0, 'M125', NULL);
                
                -- Tier 2: Parent Station + Generic Child Gates/Bays
                INSERT INTO stops VALUES ('PABT_MAIN', 'Port Authority Bus Terminal', 40.7570, -73.9900, 1, 'M42,M34A-SBS', NULL);
                INSERT INTO stops VALUES ('PABT_GATE_201', 'Gate 201', 40.7571, -73.9901, 0, '', 'PABT_MAIN');
                INSERT INTO stops VALUES ('PABT_BAY_3', 'Bay 3', 40.7572, -73.9902, 0, 'M42', 'PABT_MAIN');
                INSERT INTO stops VALUES ('PABT_EMPTY_NAME', '', 40.7573, -73.9903, 0, '', 'PABT_MAIN');
                
                -- Tier 3: Unnamed stop near known intersection
                INSERT INTO stops VALUES ('STOP_5TH_42ND', '5 AV/W 42 ST', 40.7538, -73.9818, 0, 'M1,M2,M3,M4', NULL);
                INSERT INTO stops VALUES ('UNNAMED_NEARBY', 'Bus Stop', 40.7539, -73.9817, 0, '', NULL);
            """)
        }
        
        dbManager = SpatialDatabaseManager.makeForTesting(inMemory: true, customTransitURL: mockTransitURL)
    }
    
    override func tearDownWithError() throws {
        dbManager = nil
        if let tempURL = tempDirectoryURL {
            try? FileManager.default.removeItem(at: tempURL)
        }
        try super.tearDownWithError()
    }
    
    func testTier1DirectDescriptiveNameResolution() async throws {
        let details = try await dbManager.fetchStopDetails(for: "STOP_WILLIS")
        XCTAssertEqual(details.name, "WILLIS AV/E 138 ST", "Tier 1: Non-generic primary name should be preserved.")
        XCTAssertEqual(details.routeIds, ["M125"])
        XCTAssertEqual(details.routeType, 3)
    }
    
    func testTier2ParentStationResolutionForGenericGateName() async throws {
        let details = try await dbManager.fetchStopDetails(for: "PABT_GATE_201")
        XCTAssertEqual(details.name, "Port Authority Bus Terminal", "Tier 2: Generic 'Gate 201' should resolve to parent terminal name.")
        XCTAssertEqual(details.routeIds, ["M42", "M34A-SBS"], "Tier 2: Child stop should inherit routes from parent station when empty.")
    }
    
    func testTier2ParentStationResolutionWithPreservedChildRoutes() async throws {
        let details = try await dbManager.fetchStopDetails(for: "PABT_BAY_3")
        XCTAssertEqual(details.name, "Port Authority Bus Terminal", "Tier 2: Generic 'Bay 3' should resolve to parent terminal name.")
        XCTAssertEqual(details.routeIds, ["M42"], "Tier 2: Child stop should keep specific route mappings when present.")
    }
    
    func testTier2ParentStationResolutionForEmptyStopName() async throws {
        let details = try await dbManager.fetchStopDetails(for: "PABT_EMPTY_NAME")
        XCTAssertEqual(details.name, "Port Authority Bus Terminal", "Tier 2: Empty stop_name should resolve to parent terminal name.")
    }
    
    func testTier3SpatialCrossStreetFallbackForUnnamedStop() async throws {
        let details = try await dbManager.fetchStopDetails(for: "UNNAMED_NEARBY")
        XCTAssertEqual(details.name, "5 AV/W 42 ST", "Tier 3: Unnamed stop should resolve nearby cross-street intersection.")
    }
    
    func testLegacyDatabaseWithoutParentStationColumn() async throws {
        let legacyTransitURL = tempDirectoryURL.appendingPathComponent("legacy_transit.sqlite")
        let legacyDB = try DatabaseQueue(path: legacyTransitURL.path)
        try await legacyDB.write { db in
            try db.execute(sql: """
                CREATE TABLE stops (
                    stop_id TEXT PRIMARY KEY,
                    stop_name TEXT NOT NULL,
                    stop_lat REAL NOT NULL,
                    stop_lon REAL NOT NULL
                );
                INSERT INTO stops VALUES ('LEGACY_001', 'Atlantic Ave-Barclays Ctr', 40.6840, -73.9780);
            """)
        }
        
        let legacyManager = SpatialDatabaseManager.makeForTesting(inMemory: true, customTransitURL: legacyTransitURL)
        let details = try await legacyManager.fetchStopDetails(for: "LEGACY_001")
        XCTAssertEqual(details.name, "Atlantic Ave-Barclays Ctr", "Legacy database without parent_station column must resolve gracefully.")
    }
    
    func testGenericNameClassifier() {
        XCTAssertTrue(dbManager.isGenericStopName("", stopId: "101"))
        XCTAssertTrue(dbManager.isGenericStopName("   ", stopId: "101"))
        XCTAssertTrue(dbManager.isGenericStopName("Bus Stop", stopId: "101"))
        XCTAssertTrue(dbManager.isGenericStopName("BUS STOP", stopId: "101"))
        XCTAssertTrue(dbManager.isGenericStopName("Gate 201", stopId: "101"))
        XCTAssertTrue(dbManager.isGenericStopName("Bay 3", stopId: "101"))
        XCTAssertTrue(dbManager.isGenericStopName("Platform A", stopId: "101"))
        XCTAssertTrue(dbManager.isGenericStopName("Stop #402", stopId: "101"))
        XCTAssertTrue(dbManager.isGenericStopName("101", stopId: "101"))
        XCTAssertTrue(dbManager.isGenericStopName("BUS_101", stopId: "101"))
        XCTAssertTrue(dbManager.isGenericStopName("Bus Stop (101)", stopId: "101"))
        
        XCTAssertFalse(dbManager.isGenericStopName("Port Authority Bus Terminal", stopId: "PABT"))
        XCTAssertFalse(dbManager.isGenericStopName("Grand Central-42 St", stopId: "GC"))
        XCTAssertFalse(dbManager.isGenericStopName("WILLIS AV/E 138 ST", stopId: "101014"))
        XCTAssertFalse(dbManager.isGenericStopName("1 Av & E 14 St", stopId: "BUS_001"))
        XCTAssertFalse(dbManager.isGenericStopName("Times Sq-42 St", stopId: "127"))
    }
    
    func testQueryPerformanceQoS() async throws {
        // Warm up database connection
        _ = try await dbManager.fetchStopDetails(for: "STOP_WILLIS")
        _ = try await dbManager.fetchStopDetails(for: "PABT_GATE_201")
        
        let startTime = CFAbsoluteTimeGetCurrent()
        for _ in 0..<10 {
            _ = try await dbManager.fetchStopDetails(for: "STOP_WILLIS")
            _ = try await dbManager.fetchStopDetails(for: "PABT_GATE_201")
        }
        let totalElapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000.0
        let avgPerQuery = totalElapsed / 20.0
        XCTAssertLessThan(avgPerQuery, 12.0, "Average query latency must remain well under 12ms (Actual: \(avgPerQuery)ms).")
    }
}
