import XCTest
import MapLibre
@testable import Derivee

final class StationPlatformCapsuleTests: XCTestCase {
    
    // MARK: - Invariant INV-CAPSULE-04: Zoom Opacity Ramp Tests
    
    func testPlatformCapsuleOpacityExpression() {
        let expr = TransitModalClass.platformCapsuleOpacityExpression()
        XCTAssertEqual(expr.expressionType, .function)
        XCTAssertEqual(expr.function, "mgl_interpolate:withCurveType:parameters:stops:")
        
        let stops = (expr.arguments?[3] as? NSExpression)?.constantValue as? [NSNumber: NSNumber]
        XCTAssertNotNil(stops, "Expression stops must be dictionary of zoom -> opacity")
        if let stops = stops {
            XCTAssertEqual(stops[13.5]?.doubleValue ?? -1, 0.0, accuracy: 0.01, "Capsule opacity must be 0.0 at z=13.5 (INV-CAPSULE-04)")
            XCTAssertEqual(stops[14.5]?.doubleValue ?? -1, 1.0, accuracy: 0.01, "Capsule opacity must be 1.0 at z=14.5 (INV-CAPSULE-04)")
        }
    }
    
    // MARK: - Invariant INV-CAPSULE-03: Capsule Width & Casing Dimensions
    
    func testPlatformCapsuleWidthExpressions() {
        let widthExpr = TransitModalClass.platformCapsuleWidthExpression()
        XCTAssertEqual(widthExpr.expressionType, .function)
        XCTAssertEqual(widthExpr.function, "mgl_interpolate:withCurveType:parameters:stops:")
        
        let widthStops = (widthExpr.arguments?[3] as? NSExpression)?.constantValue as? [NSNumber: NSNumber]
        XCTAssertNotNil(widthStops)
        if let stops = widthStops {
            XCTAssertEqual(stops[13.0]?.doubleValue ?? -1, 4.0, accuracy: 0.01)
            XCTAssertEqual(stops[15.0]?.doubleValue ?? -1, 7.0, accuracy: 0.01)
            XCTAssertEqual(stops[17.0]?.doubleValue ?? -1, 10.0, accuracy: 0.01)
        }
        
        let casingExpr = TransitModalClass.platformCapsuleCasingWidthExpression()
        XCTAssertEqual(casingExpr.expressionType, .function)
        XCTAssertEqual(casingExpr.function, "mgl_interpolate:withCurveType:parameters:stops:")
        
        let casingStops = (casingExpr.arguments?[3] as? NSExpression)?.constantValue as? [NSNumber: NSNumber]
        XCTAssertNotNil(casingStops)
        if let stops = casingStops {
            // Casing must provide 2.0pt halo (1.0pt margin on each side)
            XCTAssertEqual(stops[13.0]?.doubleValue ?? -1, 6.0, accuracy: 0.01)
            XCTAssertEqual(stops[15.0]?.doubleValue ?? -1, 9.0, accuracy: 0.01)
            XCTAssertEqual(stops[17.0]?.doubleValue ?? -1, 12.0, accuracy: 0.01)
        }
    }
    
    // MARK: - Invariant INV-CAPSULE-05: Layer Constants & Predicate Isolation
    
    func testPlatformCapsuleLayerConstants() {
        XCTAssertEqual(MapCustomizationDefaults.stationPlatformCapsuleLayerId, "station-platform-capsule-layer")
        XCTAssertEqual(MapCustomizationDefaults.stationPlatformCapsuleCasingLayerId, "station-platform-capsule-casing-layer")
    }
    
    func testPlatformCapsulePredicateIsolation() {
        let capsulePredicate = NSPredicate(format: "feature_type == 'platform_capsule'")
        let ribbonPredicate = NSPredicate(format: "(modal_class == 0 OR modal_class == 1) AND feature_type != 'platform_capsule'")
        
        // 1. Regular ribbon feature (feature_type is nil or not platform_capsule)
        let ribbonFeature: [String: Any] = [
            "modal_class": 0,
            "corridor_id": "corridor_arc_1",
            "trunk_color": "#0039A6"
        ]
        XCTAssertFalse(capsulePredicate.evaluate(with: ribbonFeature), "Capsule predicate must reject ribbon feature")
        XCTAssertTrue(ribbonPredicate.evaluate(with: ribbonFeature), "Ribbon predicate must accept ribbon feature")
        
        // 2. Platform capsule feature
        let capsuleFeature: [String: Any] = [
            "feature_type": "platform_capsule",
            "modal_class": 0,
            "station_name": "Queens Plaza",
            "bundle_size": 3
        ]
        XCTAssertTrue(capsulePredicate.evaluate(with: capsuleFeature), "Capsule predicate must accept capsule feature")
        XCTAssertFalse(ribbonPredicate.evaluate(with: capsuleFeature), "Ribbon predicate must reject capsule feature")
    }
}
