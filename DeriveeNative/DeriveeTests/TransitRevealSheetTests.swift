import XCTest
import GRDB
import SwiftUI
import SnapshotTesting
@testable import Derivee

final class TransitRevealSheetTests: XCTestCase {

    private var tempDirectoryURL: URL!
    private var mockTransitURL: URL!
    private var dbManager: SpatialDatabaseManager!

    override func setUpWithError() throws {
        try super.setUpWithError()
        
        // ARCHITECT GUARDRAIL 4: Create temp directory and seed mock transit database
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
                    route_type INTEGER NOT NULL DEFAULT 1,
                    location_type INTEGER NOT NULL DEFAULT 0,
                    routes TEXT NOT NULL DEFAULT ''
                );
                INSERT INTO stops VALUES ('stop_bedford', 'Bedford Ave Station', 40.7180, -73.9575, 1, 1, 'L');
                INSERT INTO stops VALUES ('stop_lorimer', 'Lorimer St Station', 40.7140, -73.9500, 1, 1, 'L,G');
                
                CREATE TABLE headway_history (
                    stop_id TEXT NOT NULL,
                    day_offset INTEGER NOT NULL,
                    headway_min REAL NOT NULL,
                    PRIMARY KEY (stop_id, day_offset)
                );
                INSERT INTO headway_history VALUES ('stop_bedford', 0, 4.2);
                INSERT INTO headway_history VALUES ('stop_bedford', 1, 4.5);
                INSERT INTO headway_history VALUES ('stop_bedford', 2, 4.0);
                INSERT INTO headway_history VALUES ('stop_bedford', 3, 5.8);
                INSERT INTO headway_history VALUES ('stop_bedford', 4, 4.3);
                INSERT INTO headway_history VALUES ('stop_bedford', 5, 4.6);
                INSERT INTO headway_history VALUES ('stop_bedford', 6, 4.1);
            """)
        }
        
        // Initialize SpatialDatabaseManager with attached transit DB
        dbManager = SpatialDatabaseManager.makeForTesting(inMemory: true, customTransitURL: mockTransitURL)
    }

    override func tearDownWithError() throws {
        dbManager = nil
        if let tempURL = tempDirectoryURL {
            try? FileManager.default.removeItem(at: tempURL)
        }
        try super.tearDownWithError()
    }

    func testHeadwayDataQueryPerformanceUnder12ms() async throws {
        let startTime = CFAbsoluteTimeGetCurrent()
        let headways = try await dbManager.fetchHeadwayData(for: "stop_bedford")
        let durationMs = (CFAbsoluteTimeGetCurrent() - startTime) * 1000.0
        
        XCTAssertEqual(headways.count, 7, "Headway query should return 7 historical data points.")
        XCTAssertLessThan(durationMs, 12.0, "Historical headway database query must complete in < 12ms (Actual: \(durationMs)ms).")
    }

    func testStopDetailsQueryPerformanceUnder12ms() async throws {
        let startTime = CFAbsoluteTimeGetCurrent()
        let details = try await dbManager.fetchStopDetails(for: "stop_bedford")
        let durationMs = (CFAbsoluteTimeGetCurrent() - startTime) * 1000.0
        
        XCTAssertEqual(details.name, "Bedford Ave Station")
        XCTAssertLessThan(durationMs, 12.0, "Stop details database query must complete in < 12ms (Actual: \(durationMs)ms).")
    }

    func testTransitSparklineViewSnapshot() throws {
        let view = TransitSparklineView(
            headways: [4.2, 4.5, 4.0, 5.8, 4.3, 4.6, 4.1],
            title: "7-Day Headway Reliability (min)"
        )
        .frame(width: 320, height: 100)

        let vc = UIHostingController(rootView: view)
        assertSnapshot(of: vc, as: .image(on: ViewImageConfig(size: CGSize(width: 320, height: 100))))
    }
}
