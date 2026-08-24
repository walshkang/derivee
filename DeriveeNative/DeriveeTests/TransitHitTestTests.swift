import XCTest
import CoreGraphics
import CoreLocation
import MapLibre
@testable import Derivee

final class TransitHitTestTests: XCTestCase {
    
    func testHitBoxCalculation() {
        let tapPoint = CGPoint(x: 150.0, y: 300.0)
        let hitBox = TransitHitTest.hitBox(for: tapPoint)
        
        XCTAssertEqual(hitBox.origin.x, 150.0 - 22.0)
        XCTAssertEqual(hitBox.origin.y, 300.0 - 22.0)
        XCTAssertEqual(hitBox.size.width, 44.0)
        XCTAssertEqual(hitBox.size.height, 44.0)
        XCTAssertTrue(hitBox.contains(tapPoint))
    }
    
    func testSingleFeatureExactHit() {
        let tapPoint = CGPoint(x: 100.0, y: 100.0)
        let feature = MLNPointFeature()
        feature.coordinate = CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060)
        feature.attributes = ["id": "stop_123"]
        
        let closest = TransitHitTest.closestFeature(
            to: tapPoint,
            among: [feature],
            coordinateConverter: { _ in CGPoint(x: 100.0, y: 100.0) }
        )
        
        XCTAssertNotNil(closest)
        XCTAssertEqual(closest?.attributes["id"] as? String, "stop_123")
    }
    
    func testSingleFeatureNearEdgeHit() {
        let tapPoint = CGPoint(x: 100.0, y: 100.0)
        let feature = MLNPointFeature()
        feature.coordinate = CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060)
        feature.attributes = ["id": "stop_edge"]
        
        // Point is 20pt away on X and 15pt away on Y (within 22pt tolerance box)
        let closest = TransitHitTest.closestFeature(
            to: tapPoint,
            among: [feature],
            coordinateConverter: { _ in CGPoint(x: 120.0, y: 115.0) }
        )
        
        XCTAssertNotNil(closest)
        XCTAssertEqual(closest?.attributes["id"] as? String, "stop_edge")
    }
    
    func testClosestFeatureTiebreaker() {
        let tapPoint = CGPoint(x: 100.0, y: 100.0)
        
        // Feature A: 5pt away
        let featureA = MLNPointFeature()
        featureA.coordinate = CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060)
        featureA.attributes = ["id": "stop_close"]
        
        // Feature B: 18pt away
        let featureB = MLNPointFeature()
        featureB.coordinate = CLLocationCoordinate2D(latitude: 40.7130, longitude: -74.0065)
        featureB.attributes = ["id": "stop_further"]
        
        let closest = TransitHitTest.closestFeature(
            to: tapPoint,
            among: [featureB, featureA], // Feature B passed first in array
            coordinateConverter: { coord in
                if coord.latitude == featureA.coordinate.latitude {
                    return CGPoint(x: 103.0, y: 104.0) // distance = 5
                } else {
                    return CGPoint(x: 118.0, y: 100.0) // distance = 18
                }
            }
        )
        
        XCTAssertNotNil(closest)
        XCTAssertEqual(closest?.attributes["id"] as? String, "stop_close")
    }
    
    func testIgnoresFeaturesWithoutValidId() {
        let tapPoint = CGPoint(x: 100.0, y: 100.0)
        
        let noIdFeature = MLNPointFeature()
        noIdFeature.coordinate = CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060)
        noIdFeature.attributes = [:]
        
        let emptyIdFeature = MLNPointFeature()
        emptyIdFeature.coordinate = CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060)
        emptyIdFeature.attributes = ["id": ""]
        
        let validFeature = MLNPointFeature()
        validFeature.coordinate = CLLocationCoordinate2D(latitude: 40.7130, longitude: -74.0065)
        validFeature.attributes = ["id": "stop_valid"]
        
        let closest = TransitHitTest.closestFeature(
            to: tapPoint,
            among: [noIdFeature, emptyIdFeature, validFeature],
            coordinateConverter: { coord in
                if coord.latitude == validFeature.coordinate.latitude {
                    return CGPoint(x: 115.0, y: 115.0)
                } else {
                    return CGPoint(x: 100.0, y: 100.0) // Closer, but invalid ID
                }
            }
        )
        
        XCTAssertNotNil(closest)
        XCTAssertEqual(closest?.attributes["id"] as? String, "stop_valid")
    }
    
    func testEmptyFeaturesReturnsNil() {
        let tapPoint = CGPoint(x: 100.0, y: 100.0)
        let closest = TransitHitTest.closestFeature(
            to: tapPoint,
            among: [],
            coordinateConverter: { _ in CGPoint(x: 100.0, y: 100.0) }
        )
        
        XCTAssertNil(closest)
    }
}
