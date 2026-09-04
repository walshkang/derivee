import XCTest
import CoreLocation
import GRDB
@testable import Derivee

final class BusStopNameSanitizationTests: XCTestCase {
    
    private var dbManager: SpatialDatabaseManager!
    
    override func setUp() async throws {
        try await super.setUp()
        dbManager = SpatialDatabaseManager.shared
    }
    
    func testKentAvBusStopNameSanitization() async throws {
        // Stop 308667 is Kent Av & North 6th St
        let detailsNB = try await dbManager.fetchStopDetails(for: "308667")
        XCTAssertEqual(detailsNB.name, "Kent Av & N 6 St", "Kent Av stop 308667 must be sanitized to 'Kent Av & N 6 St'.")
        XCTAssertFalse(detailsNB.name.contains("NB 6 St"), "Stop name must not bind 'NB' into street token '6 St'.")
        
        // Stop 308396 is Kent Av & South 6th St
        let detailsSB = try await dbManager.fetchStopDetails(for: "308396")
        XCTAssertEqual(detailsSB.name, "Kent Av & S 6 St", "Kent Av stop 308396 must be sanitized to 'Kent Av & S 6 St'.")
        XCTAssertFalse(detailsSB.name.contains("SB 6 St"), "Stop name must not bind 'SB' into street token '6 St'.")
    }
    
    func testSingleDirectionBusStopAvailableDirections() async throws {
        // Kent Av (B32) is Northbound only (Direction 0)
        let dirs308667 = try await dbManager.fetchAvailableDirections(for: "308667", routeId: "B32")
        XCTAssertEqual(dirs308667, Set([0]), "Kent Av stop 308667 must have only Direction 0 (Northbound).")
        
        let dirs308666 = try await dbManager.fetchAvailableDirections(for: "308666", routeId: "B32")
        XCTAssertEqual(dirs308666, Set([0]), "Kent Av stop 308666 must have only Direction 0 (Northbound).")
        
        // Wythe Av (B32) is Southbound only (Direction 1)
        let dirsWythe = try await dbManager.fetchAvailableDirections(for: "308683", routeId: "B32")
        XCTAssertEqual(dirsWythe, Set([1]), "Wythe Av stop 308683 must have only Direction 1 (Southbound).")
    }
    
    func testSingleDirectionBusStopArrivalsGating() async throws {
        let details = try await dbManager.fetchStopDetails(for: "308667")
        XCTAssertFalse(details.arrivals.isEmpty, "Arrivals should be generated for Kent Av stop.")
        
        // All arrivals must be Northbound (Direction 0)
        for arrival in details.arrivals {
            let dir = arrival.direction ?? ""
            XCTAssertTrue(dir.contains("Northbound") || dir.contains("Uptown"),
                          "Arrival direction '\(dir)' must be Northbound for Kent Av.")
            XCTAssertFalse(dir.contains("Southbound") || dir.contains("Downtown"),
                           "Arrival direction must NOT contain Southbound for Northbound-only Kent Av stop.")
        }
    }
    
    func testEliminationOfCorruptedCompassTokensInDatabase() async throws {
        let count = try await dbManager.dbWriter.read { db -> Int in
            try self.dbManager.ensureTransitAttached(in: db)
            return try Int.fetchOne(db, sql: """
                SELECT count(*) FROM transit.stops 
                WHERE stop_name LIKE '%NB 6 St%' 
                   OR stop_name LIKE '%SB 6 St%' 
                   OR stop_name LIKE '%EB 14 St%'
                   OR stop_name LIKE '%WB 139 St%'
                   OR stop_name LIKE '%Central Park NB%'
                   OR stop_name LIKE '%Central Park WB%'
            """) ?? 0
        }
        XCTAssertEqual(count, 0, "Database must contain zero corrupted compass tokens.")
    }
}
