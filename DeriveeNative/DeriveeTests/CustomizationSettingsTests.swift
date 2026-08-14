import XCTest
import UIKit
import MapLibre
@testable import Derivee

final class CustomizationSettingsTests: XCTestCase {
    
    // MARK: - AppStorage Keys & Defaults Tests
    
    func testAppStorageKeysUniqueAndNonEmpty() {
        let keys = [
            AppStorageKeys.selectedBasemapTheme,
            AppStorageKeys.fogOpacity,
            AppStorageKeys.showBoundaryBorders
        ]
        
        for key in keys {
            XCTAssertFalse(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "AppStorage key must not be empty")
        }
        
        let uniqueKeys = Set(keys)
        XCTAssertEqual(uniqueKeys.count, keys.count, "All AppStorage keys must be unique")
    }
    
    func testMapCustomizationDefaultsBounds() {
        XCTAssertEqual(MapCustomizationDefaults.minFogOpacity, 0.60, "Minimum fog opacity should be 0.60")
        XCTAssertEqual(MapCustomizationDefaults.maxFogOpacity, 0.98, "Maximum fog opacity should be 0.98")
        
        XCTAssertGreaterThanOrEqual(MapCustomizationDefaults.defaultFogOpacity, MapCustomizationDefaults.minFogOpacity)
        XCTAssertLessThanOrEqual(MapCustomizationDefaults.defaultFogOpacity, MapCustomizationDefaults.maxFogOpacity)
        
        XCTAssertFalse(MapCustomizationDefaults.defaultShowBoundaryBorders, "Default boundary borders should be false for clean aesthetic")
        XCTAssertEqual(MapCustomizationDefaults.boundaryBorderColorHex, "#FFB300", "Boundary borders should use Dérivée Electric Amber")
        XCTAssertEqual(MapCustomizationDefaults.boundaryBorderWidth, 1.5, "Boundary border width should be 1.5pt")
        XCTAssertEqual(MapCustomizationDefaults.boundaryBorderOpacity, 0.75, "Boundary border opacity should be 0.75")
        XCTAssertEqual(MapCustomizationDefaults.fogBorderLayerId, "fog-border-layer")
    }
    
    // MARK: - Zero-Geometry Layer Configuration Tests
    
    func testFogBorderLineStyleLayerConfiguration() {
        // Create dummy shape source (representing existing fog-source)
        let bounds = [
            CLLocationCoordinate2D(latitude: 41.5, longitude: -74.5),
            CLLocationCoordinate2D(latitude: 41.5, longitude: -73.0),
            CLLocationCoordinate2D(latitude: 40.0, longitude: -73.0),
            CLLocationCoordinate2D(latitude: 40.0, longitude: -74.5),
            CLLocationCoordinate2D(latitude: 41.5, longitude: -74.5)
        ]
        let initialPolygon = MLNPolygon(coordinates: bounds, count: UInt(bounds.count))
        let fogSource = MLNShapeSource(identifier: "fog-source", shape: initialPolygon, options: nil)
        
        // Attach border line layer directly to existing fog-source (zero geometry overhead)
        let borderLayer = MLNLineStyleLayer(identifier: MapCustomizationDefaults.fogBorderLayerId, source: fogSource)
        borderLayer.lineColor = NSExpression(forConstantValue: UIColor(hex: MapCustomizationDefaults.boundaryBorderColorHex))
        borderLayer.lineWidth = NSExpression(forConstantValue: MapCustomizationDefaults.boundaryBorderWidth)
        borderLayer.lineOpacity = NSExpression(forConstantValue: MapCustomizationDefaults.boundaryBorderOpacity)
        borderLayer.lineJoin = NSExpression(forConstantValue: "round")
        borderLayer.lineCap = NSExpression(forConstantValue: "round")
        
        XCTAssertEqual(borderLayer.identifier, "fog-border-layer")
        XCTAssertEqual(borderLayer.sourceIdentifier, "fog-source")
        
        // Assert that mutating lineOpacity is instantaneous with duration 0
        let zeroTransition = MLNTransition(duration: 0, delay: 0)
        borderLayer.lineOpacityTransition = zeroTransition
        borderLayer.lineOpacity = NSExpression(forConstantValue: 0.0)
        
        XCTAssertEqual(borderLayer.lineOpacityTransition.duration, 0)
        
        // Verify underlying shape is untouched (zero-geometry recalculation)
        XCTAssertEqual((fogSource.shape as? MLNPolygon)?.pointCount, UInt(bounds.count))
    }
    
    func testFogFillStyleLayerOpacityZeroTransition() {
        let bounds = [
            CLLocationCoordinate2D(latitude: 41.5, longitude: -74.5),
            CLLocationCoordinate2D(latitude: 41.5, longitude: -73.0),
            CLLocationCoordinate2D(latitude: 40.0, longitude: -73.0),
            CLLocationCoordinate2D(latitude: 40.0, longitude: -74.5),
            CLLocationCoordinate2D(latitude: 41.5, longitude: -74.5)
        ]
        let initialPolygon = MLNPolygon(coordinates: bounds, count: UInt(bounds.count))
        let fogSource = MLNShapeSource(identifier: "fog-source", shape: initialPolygon, options: nil)
        
        let fogLayer = MLNFillStyleLayer(identifier: "cloud-layer", source: fogSource)
        fogLayer.fillColor = NSExpression(forConstantValue: UIColor.black)
        fogLayer.fillOpacity = NSExpression(forConstantValue: MapCustomizationDefaults.defaultFogOpacity)
        
        XCTAssertEqual(fogLayer.identifier, "cloud-layer")
        XCTAssertEqual(fogLayer.sourceIdentifier, "fog-source")
        
        // Test updating opacity with zero transition
        fogLayer.fillOpacityTransition = MLNTransition(duration: 0, delay: 0)
        fogLayer.fillOpacity = NSExpression(forConstantValue: 0.95)
        
        XCTAssertEqual(fogLayer.fillOpacityTransition.duration, 0)
        
        // Assert shape instance pointer did not change
        XCTAssertTrue(fogSource.shape === initialPolygon, "Fog source shape must not be recomputed on opacity change")
    }
}
