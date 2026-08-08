import XCTest
import GRDB
@testable import Derivee

final class GRDBObservationTests: XCTestCase {
    @MainActor
    func testRawGRDBValueObservation() async throws {
        let dbManager = SpatialDatabaseManager(inMemory: true)
        let writer = dbManager.dbWriter
        
        var firedCounts: [Int] = []
        
        let observation = ValueObservation.tracking { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM explored_hexes") ?? 0
        }
        
        let cancellable = observation.start(in: writer, onError: { error in
            XCTFail("Observation error: \(error)")
        }, onChange: { count in
            firedCounts.append(count)
        })
        
        try await dbManager.insertDiscoveredHex(h3Index: "8b2a10089081fff")
        
        let timeout = 2.0
        let start = Date()
        while Date().timeIntervalSince(start) < timeout {
            if firedCounts.contains(1) {
                break
            }
            
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01))
            
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        
        XCTAssertTrue(firedCounts.contains(1))
        _ = cancellable
    }
}
