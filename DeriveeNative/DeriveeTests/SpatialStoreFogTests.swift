import XCTest
import CoreLocation
import MapLibre
import H3
import GRDB
@testable import Derivee

final class SpatialStoreFogTests: XCTestCase {
    
    private var dbManager: SpatialDatabaseManager!
    private var retainedStores: [SpatialStore] = []
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        dbManager = SpatialDatabaseManager.makeForTesting(inMemory: true)
        retainedStores = []
    }
    
    override func tearDownWithError() throws {
        retainedStores.removeAll()
        dbManager = nil
        try super.tearDownWithError()
    }
    
    // MARK: - Helpers
    
    /// Generates `count` distinct valid Res 11 H3 hex strings in the NYC region.
    private func generateH3Hexes(count: Int) throws -> [String] {
        var hexes: [String] = []
        var offset: Double = 0.0
        let baseLat = 40.768075
        let baseLng = -73.981897
        
        while hexes.count < count {
            let cell = try H3.latLngToCell(latitude: baseLat + offset, longitude: baseLng + (offset * 0.5), resolution: 11)
            let hexStr = String(cell, radix: 16)
            if !hexes.contains(hexStr) {
                hexes.append(hexStr)
            }
            offset += 0.005
        }
        
        return hexes
    }
    
    /// Waits reactively for `store.currentFogShape` to match the expected interior ring count using cooperative polling.
    @MainActor
    private func waitForFogShape(
        on store: SpatialStore,
        expectedInteriorCount: Int? = nil,
        timeout: TimeInterval = 10.0
    ) async throws -> MLNPolygon {
        let start = Date()
        while Date().timeIntervalSince(start) < timeout {
            let poly: MLNPolygon?
            if let directPoly = store.currentFogShape as? MLNPolygon {
                poly = directPoly
            } else if let collection = store.currentFogShape as? MLNShapeCollection, let firstPoly = collection.shapes.first as? MLNPolygon {
                poly = firstPoly
            } else {
                poly = nil
            }
            
            if let polygon = poly {
                let count = polygon.interiorPolygons?.count ?? 0
                if expectedInteriorCount == nil || count == expectedInteriorCount {
                    return polygon
                }
            }
            
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01))
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        
        let poly: MLNPolygon?
        if let directPoly = store.currentFogShape as? MLNPolygon {
            poly = directPoly
        } else if let collection = store.currentFogShape as? MLNShapeCollection, let firstPoly = collection.shapes.first as? MLNPolygon {
            poly = firstPoly
        } else {
            poly = nil
        }
        
        if let polygon = poly {
            let count = polygon.interiorPolygons?.count ?? 0
            if expectedInteriorCount == nil || count == expectedInteriorCount {
                return polygon
            }
        }
        throw NSError(domain: "SpatialStoreFogTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Timed out waiting for store.currentFogShape matching expected interior count \(String(describing: expectedInteriorCount))"])
    }
    
    // MARK: - Tests
    
    @MainActor
    func testColdStartFogShapeInitializationWithExistingHexes() async throws {
        let hexes = try generateH3Hexes(count: 5)
        for hex in hexes {
            try await dbManager.insertDiscoveredHex(h3Index: hex, enforceLandOnly: false)
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
            let testDb = SpatialDatabaseManager.makeForTesting(inMemory: true)
            let hexes = try generateH3Hexes(count: count)
            for hex in hexes {
                try await testDb.insertDiscoveredHex(h3Index: hex, enforceLandOnly: false)
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
            try await dbManager.insertDiscoveredHex(h3Index: hex, enforceLandOnly: false)
        }
        
        let store = SpatialStore(dbManager: dbManager)
        let fogPolygon = try await waitForFogShape(on: store, expectedInteriorCount: 5)
        
        XCTAssertNotNil(fogPolygon, "currentFogShape must not be nil on cold start with default liveUpdatePriority")
        XCTAssertEqual(fogPolygon.interiorPolygons?.count, 5)
    }

    @MainActor
    func testNewlyDiscoveredHexTriggersFogShapeUpdate() async throws {
        let initialHexes = try generateH3Hexes(count: 2)
        for hex in initialHexes {
            try await dbManager.insertDiscoveredHex(h3Index: hex, enforceLandOnly: false)
        }
        
        let store = SpatialStore(
            dbManager: dbManager,
            liveUpdatePriority: .userInitiated
        )
        retainedStores.append(store)
        
        let initialFogPolygon = try await waitForFogShape(on: store, expectedInteriorCount: 2)
        XCTAssertEqual(initialFogPolygon.interiorPolygons?.count, 2, "Initial fog polygon should contain 2 interior rings")
        
        let newHexes = try generateH3Hexes(count: 3)
        print("🧪 [TEST DEBUG] Initial hexes: \(initialHexes)")
        print("🧪 [TEST DEBUG] New hexes generated: \(newHexes)")
        let newHex = newHexes.last!
        print("🧪 [TEST DEBUG] Inserting new hex: \(newHex)")
        let inserted = try await dbManager.insertDiscoveredHex(h3Index: newHex, enforceLandOnly: false)
        print("🧪 [TEST DEBUG] insertDiscoveredHex returned: \(inserted)")
        
        let updatedFogPolygon = try await waitForFogShape(on: store, expectedInteriorCount: 3)
        XCTAssertEqual(updatedFogPolygon.interiorPolygons?.count, 3, "Updated fog polygon should contain 3 interior rings after live insertion")
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
            // Global World Fog Mask latitude range: -85.0511 to 85.0511 (+ small jitter tolerance 0.0001)
            XCTAssertGreaterThanOrEqual(coord.latitude, -85.0512, "Latitude \(coord.latitude) below expected -85.0511 world bound")
            XCTAssertLessThanOrEqual(coord.latitude, 85.0512, "Latitude \(coord.latitude) above expected 85.0511 world bound")
            
            // Global World Fog Mask longitude range: -179.999 to 179.999 (+ small jitter tolerance 0.0001)
            XCTAssertGreaterThanOrEqual(coord.longitude, -180.0, "Longitude \(coord.longitude) below expected -179.999 world bound")
            XCTAssertLessThanOrEqual(coord.longitude, 180.0, "Longitude \(coord.longitude) above expected 179.999 world bound")
        }
        
        // Assert top-left, top-right, bottom-right, bottom-left world corners are present
        XCTAssertEqual(coords[0].latitude, 85.0511, accuracy: 1e-4)
        XCTAssertEqual(coords[0].longitude, -179.999, accuracy: 1e-4)
        XCTAssertEqual(coords[1].latitude, 85.0511, accuracy: 1e-4)
        XCTAssertEqual(coords[1].longitude, 179.999, accuracy: 1e-4)
        XCTAssertEqual(coords[2].latitude, -85.0511, accuracy: 1e-4)
        XCTAssertEqual(coords[2].longitude, 179.999, accuracy: 1e-4)
        XCTAssertEqual(coords[3].latitude, -85.0511, accuracy: 1e-4)
        XCTAssertEqual(coords[3].longitude, -179.999, accuracy: 1e-4)
    }
    
    @MainActor
    func testContiguousHexExplorationDissolvesIntoSingleInteriorRing() async throws {
        // Generate a 7-cell contiguous k-ring around Columbus Circle
        let centerCell = try H3.latLngToCell(latitude: 40.768075, longitude: -73.981897, resolution: 11)
        let ringCells = try H3.gridDisk(origin: centerCell, distance: 1)
        XCTAssertEqual(ringCells.count, 7)
        
        for cell in ringCells {
            try await dbManager.insertDiscoveredHex(h3Index: String(cell, radix: 16))
        }
        
        let store = SpatialStore(
            dbManager: dbManager,
            liveUpdatePriority: .userInitiated
        )
        retainedStores.append(store)
        
        // 7 contiguous hexes must dissolve into exactly 1 interior macro-polygon
        let fogPolygon = try await waitForFogShape(on: store, expectedInteriorCount: 1)
        XCTAssertEqual(fogPolygon.interiorPolygons?.count, 1, "7 contiguous hexes must dissolve into 1 single interior ring.")
        
        guard let hole = fogPolygon.interiorPolygons?.first else {
            XCTFail("Missing interior hole")
            return
        }
        
        // 18 perimeter vertices + 1 closed point = 19 points
        XCTAssertEqual(hole.pointCount, 19, "Dissolved 7-cell cluster must contain 19 boundary points.")
    }
    
    func testDissolutionPerformanceUnder5ms() throws {
        // Generate 100 cells across NYC
        let centerCell = try H3.latLngToCell(latitude: 40.768075, longitude: -73.981897, resolution: 11)
        let diskCells = try H3.gridDisk(origin: centerCell, distance: 5) // 91 cells in radius 5
        let hexSet = Set(diskCells.map { String($0, radix: 16) })
        
        let start = CFAbsoluteTimeGetCurrent()
        let dissolved = FogPolygonMath.dissolveHexesToInteriorPolygons(hexes: hexSet)
        let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000.0 // ms
        
        print("⏱️ Dissolution of \(hexSet.count) cells completed in \(String(format: "%.3f", elapsed))ms")
        XCTAssertEqual(dissolved.count, 1, "Connected k-ring of radius 5 must dissolve into 1 macro-polygon.")
        XCTAssertLessThan(elapsed, 15.0, "Dissolution of 91 Res-11 hexes must complete in <15ms (target <5ms).")
    }
    
    @MainActor
    func testReactivePipelinePreservesCenterFogIslandOnEnclosedLoop() async throws {
        let centerCell = try H3.latLngToCell(latitude: 40.768075, longitude: -73.981897, resolution: 11)
        let diskCells = try H3.gridDisk(origin: centerCell, distance: 1)
        let ringCells = diskCells.filter { $0 != centerCell }
        XCTAssertEqual(ringCells.count, 6)
        
        for cell in ringCells {
            try await dbManager.insertDiscoveredHex(h3Index: String(cell, radix: 16))
        }
        
        let store = SpatialStore(
            dbManager: dbManager,
            liveUpdatePriority: .userInitiated
        )
        retainedStores.append(store)
        
        let start = Date()
        var compositeFeature: MLNShapeCollection? = nil
        while Date().timeIntervalSince(start) < 4.0 {
            if let collection = store.currentFogShape as? MLNShapeCollection {
                compositeFeature = collection
                break
            }
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01))
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        
        XCTAssertNotNil(compositeFeature, "store.currentFogShape must produce an MLNShapeCollection when an unvisited island exists")
        guard let collection = compositeFeature else { return }
        
        XCTAssertEqual(collection.shapes.count, 2, "Collection must contain 1 world mask + 1 island polygon")
        guard let worldMask = collection.shapes.first as? MLNPolygon,
              let island = collection.shapes.last as? MLNPolygon else {
            XCTFail("Collection shapes must be MLNPolygons")
            return
        }
        
        XCTAssertEqual(worldMask.interiorPolygons?.count, 1, "World mask must have 1 cutout hole")
        XCTAssertEqual(worldMask.interiorPolygons?.first?.pointCount, 19, "Outer perimeter cutout has 19 points")
        XCTAssertEqual(island.pointCount, 7, "Center island polygon has 7 points")
    }
}
