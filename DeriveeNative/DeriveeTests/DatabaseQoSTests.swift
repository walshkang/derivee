import XCTest
import GRDB
@testable import Derivee

final class DatabaseQoSTests: XCTestCase {
    private var dbManager: SpatialDatabaseManager!
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        dbManager = SpatialDatabaseManager.makeForTesting(inMemory: true)
    }
    
    override func tearDownWithError() throws {
        dbManager = nil
        try super.tearDownWithError()
    }
    
    func testIsHydrationCompleteAsyncSignature() async throws {
        let isComplete = try await dbManager.isHydrationComplete()
        XCTAssertFalse(isComplete, "Initial hydration complete state should be false")
    }
    
    func testFetchStopDetailsAsyncSignature() async throws {
        let stopDetails = try await dbManager.fetchStopDetails(for: "test_stop")
        XCTAssertEqual(stopDetails.stopId, "test_stop", "Fetch stop details should return StopDetails struct for the given stopId")
    }
    
    func testFetchHeadwayDataAsyncSignature() async throws {
        let headways = try await dbManager.fetchHeadwayData(for: "test_stop")
        XCTAssertFalse(headways.isEmpty, "Fetch headway data should return non-empty array of headways")
    }
    
    func testFetchNeighborhoodNameAsyncSignature() async throws {
        let name = try await dbManager.fetchNeighborhoodName(for: "8b2a100d2c9ffff")
        // Can be nil if missing from neighborhood DB, but function must execute asynchronously
        _ = name
    }
    
    func testGRDBConfigurationQoSIsUserInitiated() {
        XCTAssertEqual(dbManager.configuredQoS, .userInitiated, "GRDB Configuration QoS must be explicitly set to .userInitiated")
    }
}
