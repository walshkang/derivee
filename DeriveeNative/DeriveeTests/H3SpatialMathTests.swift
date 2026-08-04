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
    
    func testBoundaryVertexExtractionAndClockwiseWindingOrder() throws {
        let lat = 40.768075
        let lng = -73.981897
        let cell = try H3.latLngToCell(latitude: lat, longitude: lng, resolution: 11)
        
        let boundary = try H3.cellToBoundary(cell: cell)
        XCTAssertGreaterThanOrEqual(boundary.count, 6, "H3 cell boundary must contain at least 6 vertices.")
        
        var coords = boundary.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
        
        // As per GeoJSON RFC 7946 & SpatialStore implementation:
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
}
