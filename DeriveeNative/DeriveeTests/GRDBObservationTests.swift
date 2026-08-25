import XCTest
import GRDB
@testable import Derivee

final class GRDBObservationTests: XCTestCase {
    
    @MainActor
    func testValueObservationFiresOnInsert() async throws {
        let dbManager = SpatialDatabaseManager.makeForTesting(inMemory: true)
        
        let observation = ValueObservation.tracking { db in
            try String.fetchAll(db, sql: "SELECT h3_index FROM explored_hexes_nyc")
        }
        
        let expectation = XCTestExpectation(description: "Observation fired")
        expectation.expectedFulfillmentCount = 2 // 1 for initial fetch, 1 for insert
        
        let cancellable = observation.start(
            in: dbManager.dbWriter,
            scheduling: .async(onQueue: .main),
            onError: { error in
                XCTFail("Error: \(error)")
            },
            onChange: { hexes in
                print("🧪 [MINIMAL TEST] onChange fired with \(hexes.count) hexes")
                expectation.fulfill()
            }
        )
        
        try await Task.sleep(nanoseconds: 100_000_000) // Wait for initial fetch
        
        print("🧪 [MINIMAL TEST] Inserting hex...")
        let inserted = try await dbManager.insertDiscoveredHex(h3Index: "testhex", enforceLandOnly: false)
        print("🧪 [MINIMAL TEST] Insert returned: \(inserted)")
        
        await fulfillment(of: [expectation], timeout: 2.0)
        cancellable.cancel()
    }
}
