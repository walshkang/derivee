import XCTest
import GRDB
@testable import Derivee

final class GRDBObservationTests: XCTestCase {
    func testRawGRDBValueObservation() async throws {
        let dbManager = SpatialDatabaseManager(inMemory: true)
        let writer = dbManager.dbWriter
        
        let exp = expectation(description: "ValueObservation fires twice")
        var firedCounts: [Int] = []
        
        let observation = ValueObservation.tracking { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM explored_hexes") ?? 0
        }
        
        let cancellable = observation.start(in: writer, onError: { error in
            XCTFail("Observation error: \(error)")
        }, onChange: { count in
            firedCounts.append(count)
            if firedCounts.count == 2 {
                exp.fulfill()
            }
        })
        
        try await dbManager.insertDiscoveredHex(h3Index: "8b2a10089081fff")
        
        await fulfillment(of: [exp], timeout: 2.0)
        XCTAssertEqual(firedCounts, [0, 1])
        _ = cancellable
    }
}
