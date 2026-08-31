import XCTest
import SwiftUI
import CoreLocation
import MapLibre
@testable import Derivee

final class CitySwitchNavigationTests: XCTestCase {
    
    override func setUp() {
        super.setUp()
        CameraBounds.resetToDefault()
    }
    
    override func tearDown() {
        CameraBounds.resetToDefault()
        super.tearDown()
    }
    
    // MARK: - 1. Coordinate Disambiguation & Center Fallback
    
    func testCenterCoordinateDisambiguationOnCitySwitch() {
        let bostonConfig = CityConfig.bostonDefault
        let bostonBounds = bostonConfig.bounds
        let bostonCenter = bostonConfig.center.coordinate
        
        let nycManhattan = CLLocationCoordinate2D(latitude: 40.7580, longitude: -73.9855)
        let invalidCoord = CLLocationCoordinate2D(latitude: 0, longitude: 0)
        let validBostonPoint = CLLocationCoordinate2D(latitude: 42.3500, longitude: -71.0700)
        
        // Out-of-bounds coordinate (NYC Manhattan) -> Fallback to Boston Center
        let resolvedFromNYC: CLLocationCoordinate2D = {
            if bostonBounds.contains(coordinate: nycManhattan) {
                return nycManhattan
            } else {
                return bostonCenter
            }
        }()
        XCTAssertEqual(resolvedFromNYC.latitude, bostonCenter.latitude, accuracy: 1e-4)
        XCTAssertEqual(resolvedFromNYC.longitude, bostonCenter.longitude, accuracy: 1e-4)
        
        // Zero / Invalid coordinate -> Fallback to Boston Center
        let resolvedFromZero: CLLocationCoordinate2D = {
            if invalidCoord.latitude != 0 && invalidCoord.longitude != 0 && bostonBounds.contains(coordinate: invalidCoord) {
                return invalidCoord
            } else {
                return bostonCenter
            }
        }()
        XCTAssertEqual(resolvedFromZero.latitude, bostonCenter.latitude, accuracy: 1e-4)
        XCTAssertEqual(resolvedFromZero.longitude, bostonCenter.longitude, accuracy: 1e-4)
        
        // Valid in-bounds coordinate (Back Bay) -> Preserved
        let resolvedFromBackBay: CLLocationCoordinate2D = {
            if bostonBounds.contains(coordinate: validBostonPoint) {
                return validBostonPoint
            } else {
                return bostonCenter
            }
        }()
        XCTAssertEqual(resolvedFromBackBay.latitude, validBostonPoint.latitude, accuracy: 1e-4)
        XCTAssertEqual(resolvedFromBackBay.longitude, validBostonPoint.longitude, accuracy: 1e-4)
    }
    
    // MARK: - 2. Synchronous CameraBounds & SpatialStore State Transition
    
    @MainActor
    func testSynchronousCameraBoundsAndSpatialStoreStateTransition() {
        let store = SpatialStore(cityConfig: .nycDefault)
        XCTAssertEqual(store.activeCitySlug, "nyc")
        XCTAssertEqual(CameraBounds.activeConfig.slug, "nyc")
        
        let manhattan = CLLocationCoordinate2D(latitude: 40.7580, longitude: -73.9855)
        let bostonCommon = CLLocationCoordinate2D(latitude: 42.3601, longitude: -71.0589)
        
        XCTAssertTrue(CameraBounds.isWithinBounds(manhattan))
        XCTAssertFalse(CameraBounds.isWithinBounds(bostonCommon))
        
        // Switch to Boston
        store.setActiveCity(.bostonDefault)
        
        // Assert immediate synchronous update
        XCTAssertEqual(store.activeCitySlug, "bos")
        XCTAssertEqual(CameraBounds.activeConfig.slug, "bos")
        XCTAssertFalse(CameraBounds.isWithinBounds(manhattan), "Manhattan must be outside Boston bounds")
        XCTAssertTrue(CameraBounds.isWithinBounds(bostonCommon), "Boston Common must be inside Boston bounds")
    }
    
    // MARK: - 3. Viewport Handshake Coordinates Without Clamping
    
    @MainActor
    func testPerformCitySwitchHandshakeCoordinatesCenterWithoutClamping() {
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
        
        let bosConfig = CityConfig.bostonDefault
        let bostonCommon = bosConfig.center.coordinate
        
        // Execute handshake to Boston
        coordinator.performCitySwitchHandshake(to: bosConfig, animated: false)
        
        XCTAssertEqual(CameraBounds.activeConfig.slug, "bos")
        XCTAssertEqual(coordinator.lastAppliedCitySlug, "bos")
        XCTAssertEqual(mlnMapView.centerCoordinate.latitude, bostonCommon.latitude, accuracy: 1e-4)
        XCTAssertEqual(mlnMapView.centerCoordinate.longitude, bostonCommon.longitude, accuracy: 1e-4)
        
        // Ensure coordinate is strictly within Boston CameraBounds without clamping
        XCTAssertTrue(CameraBounds.isWithinBounds(mlnMapView.centerCoordinate))
        
        coordinator.mapView = nil
    }
    
    // MARK: - 4. Manifest City Overview Center Coordinate Resolution
    
    func testManifestCityOverviewCenterCoordinateResolution() {
        let manifest = CityManifest.defaultManifest
        
        let nyc = manifest.findCity(bySlug: "nyc")
        XCTAssertNotNil(nyc?.center)
        XCTAssertEqual(nyc?.center?.coordinate.latitude ?? 0, 40.7128, accuracy: 1e-4)
        XCTAssertEqual(nyc?.center?.coordinate.longitude ?? 0, -74.0060, accuracy: 1e-4)
        
        let bos = manifest.findCity(bySlug: "bos")
        XCTAssertNotNil(bos?.center)
        XCTAssertEqual(bos?.center?.coordinate.latitude ?? 0, 42.3601, accuracy: 1e-4)
        XCTAssertEqual(bos?.center?.coordinate.longitude ?? 0, -71.0589, accuracy: 1e-4)
        
        let chi = manifest.findCity(bySlug: "chi")
        XCTAssertNotNil(chi?.center)
        XCTAssertEqual(chi?.center?.coordinate.latitude ?? 0, 41.8781, accuracy: 1e-4)
        XCTAssertEqual(chi?.center?.coordinate.longitude ?? 0, -87.6298, accuracy: 1e-4)
    }
}
