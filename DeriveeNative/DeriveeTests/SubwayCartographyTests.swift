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
            guard let feature = shape as? MLNFeature else {
                XCTFail("Shape must conform to MLNFeature.")
                continue
            }
            XCTAssertNotNil(feature.attributes["route_group"], "Feature must have route_group attribute.")
            XCTAssertNotNil(feature.attributes["color_hex"], "Feature must have color_hex attribute.")
            XCTAssertNotNil(feature.attributes["color"], "Feature must have color UIColor attribute.")
            
            let pointCount: UInt
            if let poly = shape as? MLNPolylineFeature {
                pointCount = poly.pointCount
            } else if let multiPoly = shape as? MLNMultiPolylineFeature {
                pointCount = UInt(multiPoly.polylines.reduce(0) { $0 + Int($1.pointCount) })
            } else {
                pointCount = 0
            }
            XCTAssertGreaterThan(pointCount, 1, "Feature must contain at least 2 points.")
        }
    }
    
    func testSubwayLineColorExpressionEvaluation() {
        let expr = MapView.Coordinator.subwayLineColorExpression()
        XCTAssertNotNil(expr, "Subway line color expression must be valid.")
    }
}
