import XCTest
import CoreLocation
import MapLibre
@testable import Derivee

final class SubwayCartographyTests: XCTestCase {
    
    func testTrunkLineCompletenessAndColors() {
        let expectedGroups: Set<String> = ["123", "456", "7", "ACE", "BDFM", "G", "JZ", "L", "NQRW", "S", "SIR"]
        let actualGroups = Set(MtaSubwayNetworkData.trunkLines.map { $0.id })
        
        XCTAssertEqual(actualGroups, expectedGroups, "All 11 MTA trunk line groups must be present.")
        
        for trunk in MtaSubwayNetworkData.trunkLines {
            XCTAssertFalse(trunk.coordinates.isEmpty, "Trunk line \(trunk.id) must have valid coordinates.")
            XCTAssertTrue(trunk.colorHex.hasPrefix("#"), "Trunk line \(trunk.id) color must be a valid hex code.")
            
            // Check that all coordinates fall within NYC geographic boundary
            for coord in trunk.coordinates {
                XCTAssertGreaterThan(coord.latitude, 40.4, "Latitude out of bounds for \(trunk.id)")
                XCTAssertLessThan(coord.latitude, 41.0, "Latitude out of bounds for \(trunk.id)")
                XCTAssertGreaterThan(coord.longitude, -74.4, "Longitude out of bounds for \(trunk.id)")
                XCTAssertLessThan(coord.longitude, -73.6, "Longitude out of bounds for \(trunk.id)")
            }
        }
    }
    
    func testSubwayNetworkShapeGeneration() {
        let shapeCollection = MtaSubwayNetworkData.createSubwayNetworkShape()
        XCTAssertEqual(shapeCollection.shapes.count, 11, "Shape collection should contain 11 polyline features.")
        
        for shape in shapeCollection.shapes {
            guard let polyline = shape as? MLNPolylineFeature else {
                XCTFail("Shape must be an MLNPolylineFeature.")
                continue
            }
            XCTAssertNotNil(polyline.attributes["route_group"], "Polyline must have route_group attribute.")
            XCTAssertNotNil(polyline.attributes["color_hex"], "Polyline must have color_hex attribute.")
            XCTAssertNotNil(polyline.attributes["color"], "Polyline must have color UIColor attribute.")
            XCTAssertGreaterThan(polyline.pointCount, 1, "Polyline must contain at least 2 points.")
        }
    }
    
    func testSubwayLineColorExpressionEvaluation() {
        let expr = MapView.Coordinator.subwayLineColorExpression()
        XCTAssertNotNil(expr, "Subway line color expression must be valid.")
    }
}
