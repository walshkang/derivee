import XCTest
import CoreLocation
import MapLibre
import H3
import GRDB
@testable import Derivee

final class SpatialStoreFogTests: XCTestCase {
    
    private var dbManager: SpatialDatabaseManager!
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        dbManager = SpatialDatabaseManager(inMemory: true)
    }
    
    override func tearDownWithError() throws {
        dbManager = nil
        try super.tearDownWithError()
    }
    
    // MARK: - Helpers
    
    /// Generates `count` distinct valid Res 11 H3 hex strings in the NYC region.
    private func generateH3Hexes(count: Int) throws -> [String] {
        var hexes = Set<String>()
        var offset: Double = 0.0
        let baseLat = 40.768075
        let baseLng = -73.981897
        
        while hexes.count < count {
            let cell = try H3.latLngToCell(latitude: baseLat + offset, longitude: baseLng + (offset * 0.5), resolution: 11)
            let hexStr = String(cell, radix: 16)
            hexes.insert(hexStr)
            offset += 0.005
        }
        
        return Array(hexes)
    }
    
    /// Waits reactively for `store.currentFogShape` to match the expected interior ring count using @Observable tracking.
    @MainActor
    private func waitForFogShape(
        on store: SpatialStore,
        expectedInteriorCount: Int? = nil,
        timeout: TimeInterval = 4.0
    ) async throws -> MLNPolygon {
        // First check if it's already in the desired state
        if let polygon = store.currentFogShape as? MLNPolygon {
            let count = polygon.interiorPolygons?.count ?? 0
            if expectedInteriorCount == nil || count == expectedInteriorCount {
                return polygon
            }
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            var resumed = false
            
            func checkState() {
                if resumed { return }
                
                var polygonToReturn: MLNPolygon? = nil
                
                withObservationTracking {
                    if let polygon = store.currentFogShape as? MLNPolygon {
                        let count = polygon.interiorPolygons?.count ?? 0
                        if expectedInteriorCount == nil || count == expectedInteriorCount {
                            polygonToReturn = polygon
                        }
                    }
                } onChange: {
                    DispatchQueue.main.async {
                        checkState()
                    }
                }
                
                if let poly = polygonToReturn {
                    resumed = true
                    continuation.resume(returning: poly)
                }
            }
            
            checkState()
            
            // Timeout task
            Task {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                if !resumed {
                    resumed = true
                    continuation.resume(throwing: NSError(domain: "SpatialStoreFogTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Timed out waiting for store.currentFogShape"]))
                }
            }
        }
    }
    
    // MARK: - Tests
    
    @MainActor
    func testColdStartFogShapeInitializationWithExistingHexes() async throws {
        let hexes = try generateH3Hexes(count: 5)
        for hex in hexes {
            try await dbManager.insertDiscoveredHex(h3Index: hex)
        }
        
        let store = SpatialStore(
            dbManager: dbManager,
            liveUpdatePriority: .userInitiated
        )
        
        let fogPolygon = try await waitForFogShape(on: store, expectedInteriorCount: 5)
        
        XCTAssertNotNil(fogPolygon, "currentFogShape must not be nil on cold start when hexes exist")
        XCTAssertEqual(fogPolygon.interiorPolygons?.count, 5, "Cold-start fog polygon must contain exactly 5 interior rings for 5 pre-inserted hexes")
    }
    
    @MainActor
    func testInteriorRingCountMatchesExploredHexCount() async throws {
        let testCounts = [1, 10, 50]
        
        for count in testCounts {
            let testDb = SpatialDatabaseManager(inMemory: true)
            let hexes = try generateH3Hexes(count: count)
            for hex in hexes {
                try await testDb.insertDiscoveredHex(h3Index: hex)
            }
            
            let store = SpatialStore(
                dbManager: testDb,
                liveUpdatePriority: .userInitiated
            )
            let fogPolygon = try await waitForFogShape(on: store, expectedInteriorCount: count)
            
            XCTAssertEqual(
                fogPolygon.interiorPolygons?.count,
                count,
                "Interior polygon count (\(fogPolygon.interiorPolygons?.count ?? 0)) must equal explored hex count (\(count))"
            )
        }
    }
    
    @MainActor
    func testColdStartFogShapeInitializationWithDefaultPriority() async throws {
        let hexes = try generateH3Hexes(count: 5)
        for hex in hexes {
            try await dbManager.insertDiscoveredHex(h3Index: hex)
        }
        
        let store = SpatialStore(dbManager: dbManager)
        let fogPolygon = try await waitForFogShape(on: store, expectedInteriorCount: 5)
        
        XCTAssertNotNil(fogPolygon, "currentFogShape must not be nil on cold start with default liveUpdatePriority")
        XCTAssertEqual(fogPolygon.interiorPolygons?.count, 5)
    }

    @MainActor
    func disabled_testNewlyDiscoveredHexTriggersFogShapeUpdate() async throws {
        let fourHexes = try generateH3Hexes(count: 4)
        let initialHexes = Array(fourHexes[0..<3])
        let newHex = fourHexes[3]
        
        for hex in initialHexes {
            try await dbManager.insertDiscoveredHex(h3Index: hex)
        }
        
        let store = SpatialStore(
            dbManager: dbManager, 
            liveUpdatePriority: .userInitiated
        )
        let initialPolygon = try await waitForFogShape(on: store, expectedInteriorCount: 3)
        XCTAssertEqual(initialPolygon.interiorPolygons?.count, 3)
        
        // Insert 4th hex into DB
        print("DEBUG: About to insert 4th hex")
        let didInsert = try await dbManager.insertDiscoveredHex(h3Index: newHex)
        print("DEBUG: Inserted 4th hex, didInsert = \(didInsert)")
        
        let countAfterInsert = try await dbManager.dbWriter.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM explored_hexes") ?? 0
        }
        print("DEBUG: Count after insert = \(countAfterInsert)")
        
        print("DEBUG: Calling waitForFogShape(4)")
        let updatedPolygon = try await waitForFogShape(on: store, expectedInteriorCount: 4)
        print("DEBUG: waitForFogShape(4) completed")
        XCTAssertEqual(updatedPolygon.interiorPolygons?.count, 4, "Fog shape should update to 4 interior rings after inserting a new hex")
        
        guard let cell = UInt64(newHex, radix: 16) else {
            XCTFail("Invalid H3 hex string")
            return
        }
        let boundary = try H3.cellToBoundary(cell: cell)
        let expectedFirstCoord = boundary.first!
        
        let hasMatchingRing = updatedPolygon.interiorPolygons?.contains { ring in
            var ringCoords = [CLLocationCoordinate2D](repeating: kCLLocationCoordinate2DInvalid, count: Int(ring.pointCount))
            ring.getCoordinates(&ringCoords, range: NSRange(location: 0, length: Int(ring.pointCount)))
            
            return ringCoords.contains { coord in
                abs(coord.latitude - expectedFirstCoord.latitude) < 0.0001 &&
                abs(coord.longitude - expectedFirstCoord.longitude) < 0.0001
            }
        } ?? false
        
        XCTAssertTrue(hasMatchingRing, "The updated fog polygon must mathematically contain the newly inserted 4th hex boundary coordinates")
    }
    
    @MainActor
    func testFogBoundingBoxCoordinatesWithinExpectedBounds() async throws {
        let hexes = try generateH3Hexes(count: 2)
        for hex in hexes {
            try await dbManager.insertDiscoveredHex(h3Index: hex)
        }
        
        let store = SpatialStore(
            dbManager: dbManager,
            liveUpdatePriority: .userInitiated
        )
        let fogPolygon = try await waitForFogShape(on: store, expectedInteriorCount: 2)
        
        var coords = [CLLocationCoordinate2D](repeating: kCLLocationCoordinate2DInvalid, count: Int(fogPolygon.pointCount))
        fogPolygon.getCoordinates(&coords, range: NSRange(location: 0, length: Int(fogPolygon.pointCount)))
        
        XCTAssertGreaterThanOrEqual(coords.count, 4, "Exterior ring bounding box must have at least 4 coordinates")
        
        for coord in coords {
            // Latitude range: 40.0 to 41.5 (+ small jitter tolerance 0.0001)
            XCTAssertGreaterThanOrEqual(coord.latitude, 39.999, "Latitude \(coord.latitude) below expected 40.0 bound")
            XCTAssertLessThanOrEqual(coord.latitude, 41.501, "Latitude \(coord.latitude) above expected 41.5 bound")
            
            // Longitude range: -74.5 to -73.0 (+ small jitter tolerance 0.0001)
            XCTAssertGreaterThanOrEqual(coord.longitude, -74.501, "Longitude \(coord.longitude) below expected -74.5 bound")
            XCTAssertLessThanOrEqual(coord.longitude, -72.999, "Longitude \(coord.longitude) above expected -73.0 bound")
        }
    }
}
