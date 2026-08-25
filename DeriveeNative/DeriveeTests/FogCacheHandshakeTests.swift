import XCTest
import SwiftUI
import CoreLocation
import MapLibre
import H3
@testable import Derivee

final class FogCacheHandshakeTests: XCTestCase {
    
    override func setUp() {
        super.setUp()
        CameraBounds.resetToDefault()
    }
    
    override func tearDown() {
        CameraBounds.resetToDefault()
        super.tearDown()
    }
    
    // MARK: - 1. Feature Allocation & Memory Isolation
    
    func testFreshShapeCollectionFeatureAllocationAndArrayIsolation() {
        let nycConfig = CityConfig.nycDefault
        let bosConfig = CityConfig.bostonDefault
        
        // 1. Generate initial baseline fog features
        let feature1 = FogPolygonMath.makeInitialFogShapeFeature(for: nycConfig)
        let feature2 = FogPolygonMath.makeInitialFogShapeFeature(for: nycConfig)
        let featureBos = FogPolygonMath.makeInitialFogShapeFeature(for: bosConfig)
        
        // Assert distinct object references (never reused memory)
        XCTAssertTrue(feature1 !== feature2, "Each fog feature must be a distinct newly allocated instance")
        XCTAssertTrue(feature1 !== featureBos, "Features across different cities must be distinct instances")
        
        // Verify shapes structure
        XCTAssertEqual(feature1.shapes.count, 1)
        XCTAssertEqual(featureBos.shapes.count, 1)
        
        guard let polyNyc = feature1.shapes.first as? MLNPolygon,
              let polyBos = featureBos.shapes.first as? MLNPolygon else {
            XCTFail("Root shape in MLNShapeCollectionFeature must be MLNPolygon")
            return
        }
        
        XCTAssertEqual(polyNyc.pointCount, 5)
        XCTAssertEqual(polyBos.pointCount, 5)
        
        // Verify NYC coordinates vs Boston coordinates
        var nycCoords = [CLLocationCoordinate2D](repeating: kCLLocationCoordinate2DInvalid, count: 5)
        polyNyc.getCoordinates(&nycCoords, range: NSRange(location: 0, length: 5))
        
        var bosCoords = [CLLocationCoordinate2D](repeating: kCLLocationCoordinate2DInvalid, count: 5)
        polyBos.getCoordinates(&bosCoords, range: NSRange(location: 0, length: 5))
        
        // NYC bounds ~40.0 - 41.5 lat, -74.5 - -73.0 lon
        XCTAssertEqual(nycCoords[1].latitude, nycConfig.bounds.maxLatitude, accuracy: 1e-5)
        XCTAssertEqual(nycCoords[1].longitude, nycConfig.bounds.maxLongitude, accuracy: 1e-5)
        
        // Boston bounds ~42.20 - 42.50 lat, -71.25 - -70.90 lon
        XCTAssertEqual(bosCoords[1].latitude, bosConfig.bounds.maxLatitude, accuracy: 1e-5)
        XCTAssertEqual(bosCoords[1].longitude, bosConfig.bounds.maxLongitude, accuracy: 1e-5)
        
        // Bounding boxes must not overlap or share coordinates
        XCTAssertNotEqual(nycCoords[0].latitude, bosCoords[0].latitude)
        XCTAssertNotEqual(nycCoords[0].longitude, bosCoords[0].longitude)
    }
    
    // MARK: - 2. Winding Order & Closed Loop Geometry
    
    func testMultiCityFogFeatureWindingOrderAndClosedLoops() {
        let configs: [CityConfig] = [.nycDefault, .bostonDefault, .chicagoDefault]
        
        for config in configs {
            let feature = FogPolygonMath.makeInitialFogShapeFeature(for: config)
            guard let poly = feature.shapes.first as? MLNPolygon else {
                XCTFail("Feature root shape must be an MLNPolygon")
                continue
            }
            
            var coords = [CLLocationCoordinate2D](repeating: kCLLocationCoordinate2DInvalid, count: Int(poly.pointCount))
            poly.getCoordinates(&coords, range: NSRange(location: 0, length: Int(poly.pointCount)))
            
            XCTAssertEqual(coords.count, 5, "\(config.displayName) bounds must have 5 points")
            XCTAssertEqual(coords.first?.latitude, coords.last?.latitude, "\(config.displayName) loop must be closed")
            XCTAssertEqual(coords.first?.longitude, coords.last?.longitude, "\(config.displayName) loop must be closed")
            
            let area = FogPolygonMath.shoelaceSignedArea(coords)
            XCTAssertGreaterThan(area, 0, "\(config.displayName) exterior bounds must have Clockwise (CW) winding order")
        }
    }
    
    // MARK: - 3. Composite Shape Feature with Islands
    
    func testCompositeShapeFeatureWithIslandsAllocation() {
        let config = CityConfig.bostonDefault
        let hexes: Set<String> = ["8b2a304e1b5bfff", "8b2a304e1b58fff"]
        
        let feature = FogPolygonMath.generateFogShapeFeature(hexes: hexes, config: config)
        XCTAssertFalse(feature.shapes.isEmpty)
        
        guard let worldMask = feature.shapes.first as? MLNPolygon else {
            XCTFail("First shape must be world mask polygon")
            return
        }
        
        XCTAssertEqual(worldMask.pointCount, 5)
        let interiorCount = worldMask.interiorPolygons?.count ?? 0
        XCTAssertGreaterThanOrEqual(interiorCount, 1, "Explored Boston hexes must dissolve into interior cutout holes")
    }
    
    // MARK: - 4. Atomic Viewport Handshake State Execution
    
    @MainActor
    func testAtomicViewportHandshakeStateExecution() {
        let trackingEngine = AmbientTrackingEngine()
        let store = SpatialStore(cityConfig: .nycDefault)
        
        var showSheet = false
        var selectedStop: String? = nil
        var isCentered = true
        var recenterTrigger = false
        var userPos: CGPoint? = nil
        var targetCoord: CLLocationCoordinate2D? = nil
        var currentLoc: CLLocationCoordinate2D? = nil
        
        let mapViewRepresentable = MapView(
            trackingEngine: trackingEngine,
            spatialStore: store,
            fogShape: nil,
            showTransitSheet: Binding(get: { showSheet }, set: { showSheet = $0 }),
            selectedTransitStop: Binding(get: { selectedStop }, set: { selectedStop = $0 }),
            isCentered: Binding(get: { isCentered }, set: { isCentered = $0 }),
            recenterTrigger: Binding(get: { recenterTrigger }, set: { recenterTrigger = $0 }),
            userScreenPosition: Binding(get: { userPos }, set: { userPos = $0 }),
            targetCoordinate: Binding(get: { targetCoord }, set: { targetCoord = $0 }),
            currentUserLocation: Binding(get: { currentLoc }, set: { currentLoc = $0 })
        )
        
        let coordinator = mapViewRepresentable.makeCoordinator()
        let mlnMapView = MLNMapView(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        coordinator.mapView = mlnMapView
        
        XCTAssertEqual(CameraBounds.activeConfig.slug, "nyc")
        XCTAssertEqual(coordinator.lastAppliedCitySlug, "nyc")
        
        // Execute Atomic Viewport Handshake to Boston
        let bosConfig = CityConfig.bostonDefault
        coordinator.performCitySwitchHandshake(to: bosConfig, animated: false)
        
        // Assert synchronous @MainActor updates:
        // 1. CameraBounds activeConfig updated immediately
        XCTAssertEqual(CameraBounds.activeConfig.slug, "bos")
        XCTAssertEqual(coordinator.lastAppliedCitySlug, "bos")
        
        // 2. Camera center coordinated to Boston
        XCTAssertEqual(mlnMapView.centerCoordinate.latitude, bosConfig.center.latitude, accuracy: 1e-4)
        XCTAssertEqual(mlnMapView.centerCoordinate.longitude, bosConfig.center.longitude, accuracy: 1e-4)
        
        // 3. Handshake back to Chicago
        let chiConfig = CityConfig.chicagoDefault
        coordinator.performCitySwitchHandshake(to: chiConfig, animated: false)
        
        XCTAssertEqual(CameraBounds.activeConfig.slug, "chi")
        XCTAssertEqual(coordinator.lastAppliedCitySlug, "chi")
        XCTAssertEqual(mlnMapView.centerCoordinate.latitude, chiConfig.center.latitude, accuracy: 1e-4)
        XCTAssertEqual(mlnMapView.centerCoordinate.longitude, chiConfig.center.longitude, accuracy: 1e-4)
        
        coordinator.mapView = nil
    }
    
    // MARK: - 5. Rapid Sequential Hot-Switches Stability
    
    @MainActor
    func testRapidSequentialCitySwitchingStability() {
        let trackingEngine = AmbientTrackingEngine()
        let store = SpatialStore(cityConfig: .nycDefault)
        
        var showSheet = false
        var selectedStop: String? = nil
        var isCentered = true
        var recenterTrigger = false
        var userPos: CGPoint? = nil
        var targetCoord: CLLocationCoordinate2D? = nil
        var currentLoc: CLLocationCoordinate2D? = nil
        
        let mapViewRepresentable = MapView(
            trackingEngine: trackingEngine,
            spatialStore: store,
            fogShape: nil,
            showTransitSheet: Binding(get: { showSheet }, set: { showSheet = $0 }),
            selectedTransitStop: Binding(get: { selectedStop }, set: { selectedStop = $0 }),
            isCentered: Binding(get: { isCentered }, set: { isCentered = $0 }),
            recenterTrigger: Binding(get: { recenterTrigger }, set: { recenterTrigger = $0 }),
            userScreenPosition: Binding(get: { userPos }, set: { userPos = $0 }),
            targetCoordinate: Binding(get: { targetCoord }, set: { targetCoord = $0 }),
            currentUserLocation: Binding(get: { currentLoc }, set: { currentLoc = $0 })
        )
        
        let coordinator = mapViewRepresentable.makeCoordinator()
        let mlnMapView = MLNMapView(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        coordinator.mapView = mlnMapView
        
        let sequence: [CityConfig] = [
            .bostonDefault,
            .chicagoDefault,
            .nycDefault,
            .bostonDefault,
            .nycDefault
        ]
        
        for config in sequence {
            coordinator.performCitySwitchHandshake(to: config, animated: false)
            XCTAssertEqual(CameraBounds.activeConfig.slug, config.slug)
            XCTAssertEqual(coordinator.lastAppliedCitySlug, config.slug)
            XCTAssertEqual(mlnMapView.centerCoordinate.latitude, config.center.latitude, accuracy: 1e-4)
            XCTAssertEqual(mlnMapView.centerCoordinate.longitude, config.center.longitude, accuracy: 1e-4)
        }
        
        coordinator.mapView = nil
    }
}
