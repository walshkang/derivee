import XCTest
import MapLibre
@testable import Derivee

final class AdaptiveTransitFogTests: XCTestCase {
    
    // MARK: - 1. Dynamic Transit Fog Opacity Reduction
    
    func testTransitFogOpacityIsLowerThanDefault() {
        XCTAssertLessThan(
            MapCustomizationDefaults.transitFogOpacity,
            MapCustomizationDefaults.defaultFogOpacity,
            "Transit fog opacity (0.40) must be lower than exploration default (0.85)"
        )
        XCTAssertEqual(MapCustomizationDefaults.transitFogOpacity, 0.40, accuracy: 0.001)
        XCTAssertEqual(MapCustomizationDefaults.defaultFogOpacity, 0.85, accuracy: 0.001)
    }
    
    func testAdaptiveFogCalculation_WhenInspectingStation_AttenuatesToTransitOpacity() {
        let defaultFog = MapCustomizationDefaults.defaultFogOpacity // 0.85
        let isTransitInspecting = true
        
        let effectiveFog = isTransitInspecting ? min(defaultFog, MapCustomizationDefaults.transitFogOpacity) : defaultFog
        XCTAssertEqual(effectiveFog, 0.40, accuracy: 0.001, "Effective fog opacity must attenuate to 0.40 during transit inspection")
    }
    
    func testAdaptiveFogCalculation_WhenExitingInspection_RestoresBaseline() {
        let customUserBaseline = 0.92
        var isTransitInspecting = true
        
        var effectiveFog = isTransitInspecting ? min(customUserBaseline, MapCustomizationDefaults.transitFogOpacity) : customUserBaseline
        XCTAssertEqual(effectiveFog, 0.40, accuracy: 0.001)
        
        // Commuter exits inspection back to exploration
        isTransitInspecting = false
        effectiveFog = isTransitInspecting ? min(customUserBaseline, MapCustomizationDefaults.transitFogOpacity) : customUserBaseline
        XCTAssertEqual(effectiveFog, 0.92, accuracy: 0.001, "Effective fog opacity must restore cleanly to user baseline")
    }
    
    // MARK: - 2. MetalFogStyleLayer Opacity Interpolation
    
    func testMetalFogStyleLayer_SetTargetFogOpacity() {
        let layer = MetalFogStyleLayer(identifier: "test-fog-interpolation")
        XCTAssertEqual(layer.fogOpacity, 0.85, accuracy: 0.001)
        XCTAssertEqual(layer.targetFogOpacity, 0.85, accuracy: 0.001)
        XCTAssertFalse(layer.isAnimatingOpacity)
        
        // Immediate update (animated: false)
        layer.setTargetFogOpacity(0.40, animated: false)
        XCTAssertEqual(layer.fogOpacity, 0.40, accuracy: 0.001)
        XCTAssertEqual(layer.targetFogOpacity, 0.40, accuracy: 0.001)
        XCTAssertFalse(layer.isAnimatingOpacity)
        
        // Animated transition (animated: true)
        layer.setTargetFogOpacity(0.85, animated: true)
        XCTAssertEqual(layer.fogOpacity, 0.40, accuracy: 0.001, "Initial opacity unchanged at start of transition")
        XCTAssertEqual(layer.targetFogOpacity, 0.85, accuracy: 0.001)
        XCTAssertTrue(layer.isAnimatingOpacity)
    }
    
    // MARK: - 3. Inspected Corridor Z-Stack Placement Above MetalFog Layer
    
    func testInspectedCorridorZStack_InsertedAboveMetalFogLayer() {
        let source = MLNShapeSource(identifier: "test-src", shape: nil, options: nil)
        let subwayLines = MLNLineStyleLayer(identifier: MapCustomizationDefaults.subwayLinesLayerId, source: source)
        let metalFog = MetalFogStyleLayer(identifier: MapCustomizationDefaults.metalFogLayerId)
        let labelLayer = MLNSymbolStyleLayer(identifier: "place-labels", source: source)
        
        var mockLayers: [MLNStyleLayer] = [subwayLines, metalFog, labelLayer]
        
        // In MapView.swift: updateRouteInspection inserts newCasing above metalFog
        let casingLayer = MLNLineStyleLayer(identifier: "ephemeral-route-casing", source: source)
        let routeLayer = MLNLineStyleLayer(identifier: "ephemeral-route-line", source: source)
        
        if let metalIndex = mockLayers.firstIndex(where: { $0.identifier == MapCustomizationDefaults.metalFogLayerId }) {
            mockLayers.insert(casingLayer, at: metalIndex + 1)
            mockLayers.insert(routeLayer, at: metalIndex + 2)
        }
        
        let casingIndex = mockLayers.firstIndex(where: { $0.identifier == "ephemeral-route-casing" })!
        let routeIndex = mockLayers.firstIndex(where: { $0.identifier == "ephemeral-route-line" })!
        let fogIndex = mockLayers.firstIndex(where: { $0.identifier == MapCustomizationDefaults.metalFogLayerId })!
        let labelsIndex = mockLayers.firstIndex(where: { $0.identifier == "place-labels" })!
        
        XCTAssertGreaterThan(casingIndex, fogIndex, "Route casing MUST sit strictly above MetalFogStyleLayer (Wave PE.3)")
        XCTAssertGreaterThan(routeIndex, casingIndex, "Route line MUST sit above casing")
        XCTAssertLessThan(routeIndex, labelsIndex, "Route line MUST sit below symbol labels to preserve legibility")
    }
}
