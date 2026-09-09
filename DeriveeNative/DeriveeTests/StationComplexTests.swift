import XCTest
import CoreLocation
import GRDB
@testable import Derivee

final class StationComplexTests: XCTestCase {
    
    var spatialManager: SpatialDatabaseManager!
    
    override func setUp() async throws {
        try await super.setUp()
        spatialManager = SpatialDatabaseManager.shared
    }
    
    // MARK: - Complex Point Queries (Doc 16 §2 & §3)
    
    func testFetchComplexByComplexId() async throws {
        // 1. Regional Hub: Penn Station (600001)
        let pennComplex = try await spatialManager.fetchComplex(for: RegionalHubAnchor.pennStation)
        XCTAssertNotNil(pennComplex, "Penn Station complex (600001) must exist")
        XCTAssertEqual(pennComplex?.id, 600001)
        XCTAssertTrue(pennComplex?.name.contains("Penn Station") == true)
        XCTAssertEqual(pennComplex?.borough, "Manhattan")
        XCTAssertTrue(pennComplex?.isHub == true)
        
        // 2. MTA Subway Complex: 14 St-Union Sq (602)
        let unionComplex = try await spatialManager.fetchComplex(for: 602)
        XCTAssertNotNil(unionComplex, "14 St-Union Sq complex (602) must exist")
        XCTAssertEqual(unionComplex?.id, 602)
        XCTAssertEqual(unionComplex?.name, "14 St-Union Sq")
        XCTAssertEqual(unionComplex?.borough, "Manhattan")
        XCTAssertFalse(unionComplex?.isHub == true)
        
        // 3. Non-existent complex ID
        let nonExistent = try await spatialManager.fetchComplex(for: 99999999)
        XCTAssertNil(nonExistent, "Non-existent complex ID must return nil")
    }
    
    // MARK: - Reverse Inverted Index Seek (feed_id, child_stop_id -> complex)
    
    func testFetchComplexByStopId() async throws {
        // Both 7th Ave (1/2/3, stop 128) and 8th Ave (A/C/E, stop A28) platforms must resolve to Penn Station (600001)
        let complexFrom128N = try await spatialManager.fetchComplex(forStopId: "128N", feedId: "subway")
        XCTAssertNotNil(complexFrom128N)
        XCTAssertEqual(complexFrom128N?.id, RegionalHubAnchor.pennStation)
        XCTAssertTrue(complexFrom128N?.isHub == true)
        
        let complexFromA28S = try await spatialManager.fetchComplex(forStopId: "A28S", feedId: "subway")
        XCTAssertNotNil(complexFromA28S)
        XCTAssertEqual(complexFromA28S?.id, RegionalHubAnchor.pennStation)
        
        // All Union Square platforms (635, R20, L03) must resolve to 602
        let complexFromR20N = try await spatialManager.fetchComplex(forStopId: "R20N", feedId: "subway")
        XCTAssertNotNil(complexFromR20N)
        XCTAssertEqual(complexFromR20N?.id, 602)
        
        let complexFromL03S = try await spatialManager.fetchComplex(forStopId: "L03S", feedId: "subway")
        XCTAssertNotNil(complexFromL03S)
        XCTAssertEqual(complexFromL03S?.id, 602)
        
        let complexFrom635 = try await spatialManager.fetchComplex(forStopId: "635", feedId: "subway")
        XCTAssertNotNil(complexFrom635)
        XCTAssertEqual(complexFrom635?.id, 602)
    }
    
    // MARK: - Multi-Platform Stop Resolution across Complex
    
    func testFetchResolvedStopsForComplex() async throws {
        let stops = try await spatialManager.fetchResolvedStops(forComplexId: 602)
        XCTAssertFalse(stops.isEmpty, "Union Square (602) must contain resolved stops")
        
        let childStopIds = Set(stops.map(\.childStopId))
        XCTAssertTrue(childStopIds.contains("635N"), "Must contain Lexington Northbound platform")
        XCTAssertTrue(childStopIds.contains("635S"), "Must contain Lexington Southbound platform")
        XCTAssertTrue(childStopIds.contains("R20N"), "Must contain Broadway Northbound platform")
        XCTAssertTrue(childStopIds.contains("R20S"), "Must contain Broadway Southbound platform")
        XCTAssertTrue(childStopIds.contains("L03N"), "Must contain Canarsie platform")
        
        // Verify direction inference
        for stop in stops {
            XCTAssertEqual(stop.feedId, "subway")
            if stop.childStopId.hasSuffix("N") {
                XCTAssertEqual(stop.directionId, 0, "Northbound platform \(stop.childStopId) must have directionId = 0")
            } else if stop.childStopId.hasSuffix("S") {
                XCTAssertEqual(stop.directionId, 1, "Southbound platform \(stop.childStopId) must have directionId = 1")
            }
        }
    }
    
    // MARK: - Regional Hub Anchors Validation
    
    func testRegionalHubAnchors() async throws {
        // Verify all 3 regional hub anchors exist in active database
        let penn = try await spatialManager.fetchComplex(for: RegionalHubAnchor.pennStation)
        let gcm = try await spatialManager.fetchComplex(for: RegionalHubAnchor.grandCentral)
        let atl = try await spatialManager.fetchComplex(for: RegionalHubAnchor.atlanticAve)
        
        XCTAssertNotNil(penn, "Penn Station anchor (600001) must exist")
        XCTAssertNotNil(gcm, "Grand Central anchor (600002) must exist")
        XCTAssertNotNil(atl, "Atlantic Ave anchor (600003) must exist")
        
        XCTAssertTrue(penn?.isHub == true)
        XCTAssertTrue(gcm?.isHub == true)
        XCTAssertTrue(atl?.isHub == true)
        
        XCTAssertTrue(RegionalHubAnchor.isRegionalHub(600001))
        XCTAssertTrue(RegionalHubAnchor.isRegionalHub(600002))
        XCTAssertTrue(RegionalHubAnchor.isRegionalHub(600003))
        XCTAssertFalse(RegionalHubAnchor.isRegionalHub(602))
    }
    
    // MARK: - Backward-Compatible Platform Resolution
    
    func testResolvePlatformStopIdsCompatibility() async throws {
        try await spatialManager.dbWriter.read { db in
            try self.spatialManager.ensureTransitAttached(in: db)
            
            // Resolving parent station "128" should yield child platforms "128N" and "128S"
            let resolved128 = self.spatialManager.resolvePlatformStopIds(for: "128", in: db)
            XCTAssertTrue(resolved128.contains("128N"))
            XCTAssertTrue(resolved128.contains("128S"))
            
            // Resolving parent station "635" should yield child platforms "635N" and "635S"
            let resolved635 = self.spatialManager.resolvePlatformStopIds(for: "635", in: db)
            XCTAssertTrue(resolved635.contains("635N"))
            XCTAssertTrue(resolved635.contains("635S"))
        }
    }
    
    // MARK: - Fetch All Complexes
    
    func testFetchAllComplexes() async throws {
        let complexes = try await spatialManager.fetchAllComplexes()
        XCTAssertGreaterThan(complexes.count, 100, "Should have loaded NYC subway complexes")
        
        // Verify hub sorting (hubs first)
        let firstHubs = complexes.prefix(3)
        for hub in firstHubs {
            XCTAssertTrue(hub.isHub, "Leading complexes should be regional hubs")
        }
    }
}
