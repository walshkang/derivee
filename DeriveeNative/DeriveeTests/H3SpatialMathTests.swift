import XCTest
import CoreLocation
import H3
import MapLibre
@testable import Derivee

final class H3SpatialMathTests: XCTestCase {

    func testResolution11HexIndexGeneration() throws {
        // Columbus Circle, NYC
        let lat = 40.768075
        let lng = -73.981897
        
        let cell = try H3.latLngToCell(latitude: lat, longitude: lng, resolution: 11)
        XCTAssertNotEqual(cell, 0, "Resolution 11 cell index should not be zero.")
        
        let hexString = String(cell, radix: 16)
        XCTAssertEqual(hexString.count, 15, "Resolution 11 hex index string representation should be 15 hex characters.")
        XCTAssertTrue(hexString.hasPrefix("8b"), "Res 11 hex strings in NYC region typically start with 8b.")
    }
    
    func testDistinctResolution11CellsForSeparatedPoints() throws {
        // Columbus Circle
        let point1 = CLLocationCoordinate2D(latitude: 40.768075, longitude: -73.981897)
        // 59th St / 5th Ave (~700m away)
        let point2 = CLLocationCoordinate2D(latitude: 40.764500, longitude: -73.973400)
        
        let cell1 = try H3.latLngToCell(latitude: point1.latitude, longitude: point1.longitude, resolution: 11)
        let cell2 = try H3.latLngToCell(latitude: point2.latitude, longitude: point2.longitude, resolution: 11)
        
        XCTAssertNotEqual(cell1, cell2, "Points 700m apart must resolve to distinct Resolution 11 hex cells.")
    }
    
    func testCoordinateRoundTrippingPrecision() throws {
        let origin = CLLocation(latitude: 40.768075, longitude: -73.981897)
        let cell = try H3.latLngToCell(latitude: origin.coordinate.latitude, longitude: origin.coordinate.longitude, resolution: 11)
        
        let centerCoord = try H3.cellToLatLng(cell: cell)
        let centerLocation = CLLocation(latitude: centerCoord.latitude, longitude: centerCoord.longitude)
        
        let distance = origin.distance(from: centerLocation)
        // Resolution 11 hex edge length is ~14m, max distance from center to vertex is ~16m.
        XCTAssertLessThan(distance, 25.0, "Reconstituted cell center should be within 25m of origin coordinate.")
    }
    
    func testGlobalWorldBoundingPolygonClockwiseWindingOrder() {
        let bounds = FogPolygonMath.makeWorldBounds()
        
        XCTAssertEqual(bounds.count, 5, "Global world fog mask outer polygon must contain exactly 5 points (closed loop)")
        XCTAssertEqual(bounds.first?.latitude, bounds.last?.latitude, "Global world fog loop must be closed in latitude")
        XCTAssertEqual(bounds.first?.longitude, bounds.last?.longitude, "Global world fog loop must be closed in longitude")
        
        // Check exact Web Mercator limits
        XCTAssertEqual(bounds[0].latitude, 85.0511, accuracy: 1e-4)
        XCTAssertEqual(bounds[0].longitude, -179.999, accuracy: 1e-4)
        XCTAssertEqual(bounds[1].latitude, 85.0511, accuracy: 1e-4)
        XCTAssertEqual(bounds[1].longitude, 179.999, accuracy: 1e-4)
        XCTAssertEqual(bounds[2].latitude, -85.0511, accuracy: 1e-4)
        XCTAssertEqual(bounds[2].longitude, 179.999, accuracy: 1e-4)
        XCTAssertEqual(bounds[3].latitude, -85.0511, accuracy: 1e-4)
        XCTAssertEqual(bounds[3].longitude, -179.999, accuracy: 1e-4)
        
        let area = FogPolygonMath.shoelaceSignedArea(bounds)
        XCTAssertGreaterThan(area, 0, "Global world fog polygon must have Clockwise (CW) winding order (positive shoelace sum).")
    }

    func testExteriorBoundingBoxClockwiseWindingOrder() {
        let bounds = [
            CLLocationCoordinate2D(latitude: 41.5, longitude: -74.5), // Top Left
            CLLocationCoordinate2D(latitude: 41.5, longitude: -73.0), // Top Right
            CLLocationCoordinate2D(latitude: 40.0, longitude: -73.0), // Bottom Right
            CLLocationCoordinate2D(latitude: 40.0, longitude: -74.5), // Bottom Left
            CLLocationCoordinate2D(latitude: 41.5, longitude: -74.5)  // Top Left (closed)
        ]
        
        var shoelaceSum: Double = 0
        for i in 0..<(bounds.count - 1) {
            let p1 = bounds[i]
            let p2 = bounds[i + 1]
            shoelaceSum += (p2.longitude - p1.longitude) * (p2.latitude + p1.latitude)
        }
        
        XCTAssertGreaterThan(shoelaceSum, 0, "Exterior fog polygon bounds must have Clockwise (CW) winding order (positive shoelace sum in lat/lng coordinate space).")
    }

    func testBoundaryVertexExtractionAndClockwiseWindingOrder() throws {
        let lat = 40.768075
        let lng = -73.981897
        let cell = try H3.latLngToCell(latitude: lat, longitude: lng, resolution: 11)
        
        let boundary = try H3.cellToBoundary(cell: cell)
        XCTAssertGreaterThanOrEqual(boundary.count, 6, "H3 cell boundary must contain at least 6 vertices.")
        
        var coords = boundary.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
        
        // As per GeoJSON RFC 7946 & SpatialStore verified implementation:
        // Interior hole polygons in MapLibre fog masks MUST have Clockwise (CW) winding order.
        // H3 boundary vertices default to CCW, so reversing them produces CW winding order.
        coords.reverse()
        
        if let first = coords.first {
            coords.append(first)
        }
        XCTAssertGreaterThanOrEqual(coords.count, 7, "Closed polygon ring must have at least 7 points.")
        
        // Calculate signed area to verify Clockwise (CW) winding order
        // In lat/lng space (y=lat, x=lng), CW order results in positive shoelace sum (sum((x_{i+1} - x_i) * (y_{i+1} + y_i)))
        var shoelaceSum: Double = 0
        for i in 0..<(coords.count - 1) {
            let p1 = coords[i]
            let p2 = coords[i + 1]
            shoelaceSum += (p2.longitude - p1.longitude) * (p2.latitude + p1.latitude)
        }
        
        XCTAssertGreaterThan(shoelaceSum, 0, "Reversed interior ring coordinates must have Clockwise winding order (positive shoelace sum in lat/lng coordinate space).")
    }
    
    func testWaterAndEdgeCaseCoordinates() throws {
        // Hudson River near Manhattan
        let waterPoint = CLLocationCoordinate2D(latitude: 40.7200, longitude: -74.0200)
        let cell = try H3.latLngToCell(latitude: waterPoint.latitude, longitude: waterPoint.longitude, resolution: 11)
        let hexString = String(cell, radix: 16)
        
        XCTAssertEqual(hexString.count, 15)
        
        // Re-parse back from hex string
        let reconstitutedCell = UInt64(hexString, radix: 16)
        XCTAssertEqual(reconstitutedCell, cell, "Hex string parsing must reconstitute the exact UInt64 cell ID.")
    }
    
    func testInvalidHexStringParsingHandling() {
        let invalidHex = "not_a_valid_hex_string"
        let cell = UInt64(invalidHex, radix: 16)
        XCTAssertNil(cell, "Invalid hex string parsing should return nil safely.")
    }
    
    // MARK: - FogPolygonMath Dissolution Tests (Wave J.2)
    
    func testContiguousHexDissolutionReducesInteriorRingAndVertexCount() throws {
        // Columbus Circle center cell
        let centerCell = try H3.latLngToCell(latitude: 40.768075, longitude: -73.981897, resolution: 11)
        let diskCells = try H3.gridDisk(origin: centerCell, distance: 1)
        XCTAssertGreaterThanOrEqual(diskCells.count, 2)
        
        let contiguousTwo = Array(diskCells.prefix(2))
        let dissolvedPolygons = FogPolygonMath.dissolveCellsToInteriorPolygons(cells: contiguousTwo)
        
        // 2 contiguous hexagons must dissolve into 1 single polygon
        XCTAssertEqual(dissolvedPolygons.count, 1, "2 contiguous hexes must dissolve into exactly 1 interior ring.")
        
        // 2 individual hexes have 2 * 6 = 12 boundary vertices (14 closed).
        // Merged together, they share 1 edge (2 vertices), producing 10 unique boundary vertices (11 closed).
        let pointCount = dissolvedPolygons[0].pointCount
        XCTAssertEqual(pointCount, 11, "Dissolved 2-hex boundary must contain exactly 11 points (10 distinct vertices + 1 closed).")
    }
    
    func testSevenCellRingDissolutionMath() throws {
        let centerCell = try H3.latLngToCell(latitude: 40.768075, longitude: -73.981897, resolution: 11)
        let ringCells = try H3.gridDisk(origin: centerCell, distance: 1)
        XCTAssertEqual(ringCells.count, 7, "Res 11 k-ring (distance 1) must contain exactly 7 cells.")
        
        let hexStrings = Set(ringCells.map { String($0, radix: 16) })
        let dissolvedPolygons = FogPolygonMath.dissolveHexesToInteriorPolygons(hexes: hexStrings)
        
        XCTAssertEqual(dissolvedPolygons.count, 1, "7 contiguous hexes in a k-ring must dissolve into exactly 1 interior ring.")
        
        // 7 individual hexes = 7 * 7 = 49 un-dissolved points.
        // Dissolved 7-cell k-ring perimeter has 18 perimeter vertices (19 closed points), an >60% vertex reduction.
        let pointCount = dissolvedPolygons[0].pointCount
        XCTAssertEqual(pointCount, 19, "Dissolved 7-cell k-ring must contain exactly 19 points (18 perimeter vertices + 1 closed).")
    }
    
    func testDisjointHexClustersProduceDistinctInteriorPolygons() throws {
        // Columbus Circle (Manhattan)
        let cell1 = try H3.latLngToCell(latitude: 40.768075, longitude: -73.981897, resolution: 11)
        // Wall Street (Lower Manhattan, ~7km away)
        let cell2 = try H3.latLngToCell(latitude: 40.706000, longitude: -74.008800, resolution: 11)
        // Flushing (Queens, ~14km away)
        let cell3 = try H3.latLngToCell(latitude: 40.758000, longitude: -73.830000, resolution: 11)
        
        let hexSet: Set<String> = [
            String(cell1, radix: 16),
            String(cell2, radix: 16),
            String(cell3, radix: 16)
        ]
        
        let dissolvedPolygons = FogPolygonMath.dissolveHexesToInteriorPolygons(hexes: hexSet)
        XCTAssertEqual(dissolvedPolygons.count, 3, "3 disjoint non-contiguous hexes must produce 3 distinct interior rings.")
    }
    
    func testDissolvedPolygonClockwiseWindingOrder() throws {
        let centerCell = try H3.latLngToCell(latitude: 40.768075, longitude: -73.981897, resolution: 11)
        let ringCells = try H3.gridDisk(origin: centerCell, distance: 1)
        let dissolvedPolygons = FogPolygonMath.dissolveCellsToInteriorPolygons(cells: ringCells)
        
        XCTAssertEqual(dissolvedPolygons.count, 1)
        let poly = dissolvedPolygons[0]
        
        var coords = [CLLocationCoordinate2D](repeating: kCLLocationCoordinate2DInvalid, count: Int(poly.pointCount))
        poly.getCoordinates(&coords, range: NSRange(location: 0, length: Int(poly.pointCount)))
        
        // Compute shoelace sum in lat/lng coordinate space to verify CW winding order
        var shoelaceSum: Double = 0
        for i in 0..<(coords.count - 1) {
            let p1 = coords[i]
            let p2 = coords[i + 1]
            shoelaceSum += (p2.longitude - p1.longitude) * (p2.latitude + p1.latitude)
        }
        
        XCTAssertGreaterThan(shoelaceSum, 0, "Dissolved interior polygon ring must have Clockwise (CW) winding order (positive shoelace sum).")
    }
    
    func testEmptyAndInvalidHexInputs() {
        let emptyResult = FogPolygonMath.dissolveHexesToInteriorPolygons(hexes: [])
        XCTAssertTrue(emptyResult.isEmpty, "Empty hex set must produce empty interior rings.")
        
        let invalidResult = FogPolygonMath.dissolveHexesToInteriorPolygons(hexes: ["invalid_hex_string"])
        XCTAssertTrue(invalidResult.isEmpty, "Invalid hex string set must produce empty interior rings safely.")
        
        let fogPoly = FogPolygonMath.generateFogPolygon(hexes: [])
        XCTAssertNil(fogPoly.interiorPolygons, "Empty hex set must generate a fog polygon with nil interior rings.")
    }
    
    func testHollowHexRingPreservesCenterFogIslandGeometry() throws {
        // 1. Arrange: Columbus Circle center cell + 1-ring (7 cells total)
        let centerCell = try H3.latLngToCell(latitude: 40.768075, longitude: -73.981897, resolution: 11)
        let diskCells = try H3.gridDisk(origin: centerCell, distance: 1)
        XCTAssertEqual(diskCells.count, 7)
        
        // 2. Remove center cell to create a hollow 6-hex perimeter ring
        let ringCells = diskCells.filter { $0 != centerCell }
        XCTAssertEqual(ringCells.count, 6)
        
        // 3. Act: Dissolve cells into FogGeometry
        let bounds = FogPolygonMath.makeDefaultBounds()
        let fogGeom = FogPolygonMath.dissolveCellsToFogGeometry(cells: ringCells, bounds: bounds)
        
        // 4. Assert:
        // a) World mask has exactly 1 cutout hole (the outer perimeter of the 6-hex loop)
        XCTAssertEqual(fogGeom.worldMaskPolygon.interiorPolygons?.count, 1)
        let outerCutout = fogGeom.worldMaskPolygon.interiorPolygons!.first!
        XCTAssertEqual(outerCutout.pointCount, 19, "6-hex outer perimeter must have 18 vertices + 1 closing point")
        
        // b) Exactly 1 additive fog island polygon for the unvisited center
        XCTAssertEqual(fogGeom.islandPolygons.count, 1, "Must generate exactly 1 center fog island polygon")
        let islandPoly = fogGeom.islandPolygons.first!
        XCTAssertEqual(islandPoly.pointCount, 7, "Center unvisited hex island must have 6 vertices + 1 closing point")
        
        // c) Verify center coordinate is inside the fog island's bounding rect
        let centerCoord = try H3.cellToLatLng(cell: centerCell)
        var islandCoords = [CLLocationCoordinate2D](repeating: kCLLocationCoordinate2DInvalid, count: Int(islandPoly.pointCount))
        islandPoly.getCoordinates(&islandCoords, range: NSRange(location: 0, length: Int(islandPoly.pointCount)))
        
        let minLat = islandCoords.map(\.latitude).min()!
        let maxLat = islandCoords.map(\.latitude).max()!
        let minLng = islandCoords.map(\.longitude).min()!
        let maxLng = islandCoords.map(\.longitude).max()!
        
        XCTAssertTrue(centerCoord.latitude >= minLat && centerCoord.latitude <= maxLat, "Center cell latitude must be enclosed in island bounds")
        XCTAssertTrue(centerCoord.longitude >= minLng && centerCoord.longitude <= maxLng, "Center cell longitude must be enclosed in island bounds")
        
        // d) Verify Clockwise (CW) winding order on both outer cutout and center island
        var cutoutCoords = [CLLocationCoordinate2D](repeating: kCLLocationCoordinate2DInvalid, count: Int(outerCutout.pointCount))
        outerCutout.getCoordinates(&cutoutCoords, range: NSRange(location: 0, length: Int(outerCutout.pointCount)))
        
        XCTAssertGreaterThan(FogPolygonMath.shoelaceSignedArea(cutoutCoords), 0, "Outer cutout must have Clockwise (CW) winding order")
        XCTAssertGreaterThan(FogPolygonMath.shoelaceSignedArea(islandCoords), 0, "Fog island must have Clockwise (CW) winding order")
        
        // e) Verify composite shape polymorphism
        let composite = fogGeom.compositeShape
        XCTAssertTrue(composite is MLNShapeCollection, "Composite shape with islands must be an MLNShapeCollection")
        let collection = composite as! MLNShapeCollection
        XCTAssertEqual(collection.shapes.count, 2, "Collection must contain 1 world mask + 1 island polygon")
    }
}
