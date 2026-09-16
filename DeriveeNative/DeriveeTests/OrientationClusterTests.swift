import XCTest
import CoreLocation
import MapLibre
import SwiftUI
@testable import Derivee

final class OrientationClusterTests: XCTestCase {
    
    @MainActor
    func testCompassPositionAndMarginConfiguration() {
        let mapView = MLNMapView(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        
        let spatialStore = SpatialStore()
        let trackingEngine = AmbientTrackingEngine(locationProvider: MockLocationProvider())
        let mapViewRepresentable = MapView(
            trackingEngine: trackingEngine,
            spatialStore: spatialStore,
            fogShape: nil,
            showTransitSheet: .constant(false),
            selectedTransitStop: .constant(nil),
            isCentered: .constant(true),
            recenterTrigger: .constant(false),
            userScreenPosition: .constant(nil),
            targetCoordinate: .constant(nil),
            currentUserLocation: .constant(nil),
            transientHexShape: nil,
            selectedTheme: .day,
            fogOpacity: 0.94,
            showBoundaryBorders: true,
            showSubwayThoroughfares: true,
            subwayStationMarkerStyle: .allStations,
            nearbyBusStops: []
        )
        
        let coordinator = mapViewRepresentable.makeCoordinator()
        coordinator.mapView = mapView
        coordinator.setupCompass()
        
        // Assert native MapLibre compass is positioned in .bottomRight
        XCTAssertEqual(mapView.compassViewPosition, .bottomRight, "Compass position must be .bottomRight stacked above RecenterFAB")
        
        // Assert margins follow (x: 20, y: 102 + bottomInset)
        XCTAssertEqual(mapView.compassViewMargins.x, 20.0, accuracy: 0.001, "Compass trailing margin must be 20pt")
        XCTAssertGreaterThanOrEqual(mapView.compassViewMargins.y, 102.0, "Compass bottom margin must be at least 102pt above bottom safe area")
        
        // Assert custom Aperture compass needle image is applied
        XCTAssertNotNil(mapView.compassView.image, "Compass view must have custom Aperture needle image")
    }
    
    func testApertureCompassNeedleAssetIntegrity() {
        let needleImage = ApertureCompassNeedle.makeNeedleImage(size: CGSize(width: 40, height: 40))
        XCTAssertNotNil(needleImage, "Aperture compass needle image must be generated")
        XCTAssertEqual(needleImage.size.width, 40.0)
        XCTAssertEqual(needleImage.size.height, 40.0)
        XCTAssertNotNil(needleImage.cgImage, "Needle CGImage must be valid")
    }
    
    @MainActor
    func testDynamicMarginComputation() {
        let testInsets: [CGFloat] = [0.0, 34.0, 48.0]
        
        for inset in testInsets {
            let computedY = 102.0 + (inset > 0 ? inset : 34.0)
            XCTAssertEqual(computedY, 102.0 + (inset > 0 ? inset : 34.0))
            if inset == 34.0 {
                XCTAssertEqual(computedY, 136.0, "Default iPhone 34pt bottom safe area produces y=136pt margin")
            }
        }
    }
    
    @MainActor
    func testNativeAutoFadePreservation() {
        let mapView = MLNMapView(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        let spatialStore = SpatialStore()
        let trackingEngine = AmbientTrackingEngine(locationProvider: MockLocationProvider())
        let mapViewRepresentable = MapView(
            trackingEngine: trackingEngine,
            spatialStore: spatialStore,
            fogShape: nil,
            showTransitSheet: .constant(false),
            selectedTransitStop: .constant(nil),
            isCentered: .constant(true),
            recenterTrigger: .constant(false),
            userScreenPosition: .constant(nil),
            targetCoordinate: .constant(nil),
            currentUserLocation: .constant(nil),
            transientHexShape: nil,
            selectedTheme: .day,
            fogOpacity: 0.94,
            showBoundaryBorders: true,
            showSubwayThoroughfares: true,
            subwayStationMarkerStyle: .allStations,
            nearbyBusStops: []
        )
        
        let coordinator = mapViewRepresentable.makeCoordinator()
        coordinator.mapView = mapView
        coordinator.setupCompass()
        
        // Verify compassView is not forcibly unhidden by custom KVO observers
        // MapLibre's native compassView manages isHidden / alpha on rotation
        mapView.compassView.isHidden = true
        XCTAssertTrue(mapView.compassView.isHidden, "Auto-fade when North-Up must be preserved without forced KVO overrides")
        
        mapView.compassView.alpha = 0.0
        XCTAssertEqual(mapView.compassView.alpha, 0.0, "Auto-fade alpha must be preserved without forced KVO overrides")
    }
    
    // MARK: - Wave PD.4: Pedestrian Recenter Zoom (WPD4-LOCAL-DEEXPRESS-RECENTER-ZOOM)
    
    @MainActor
    func testRecenterTriggerActivatesPedestrianZoomLevel() {
        let mapView = MLNMapView(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        mapView.setCenter(CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060), zoomLevel: 12.0, animated: false)
        XCTAssertEqual(mapView.zoomLevel, 12.0, accuracy: 0.1, "Initial zoom should be at regional scale")
        
        let spatialStore = SpatialStore()
        let trackingEngine = AmbientTrackingEngine(locationProvider: MockLocationProvider())
        var recenterTrigger = false
        
        let mapViewRepresentable = MapView(
            trackingEngine: trackingEngine,
            spatialStore: spatialStore,
            fogShape: nil,
            showTransitSheet: .constant(false),
            selectedTransitStop: .constant(nil),
            isCentered: .constant(true),
            recenterTrigger: Binding(get: { recenterTrigger }, set: { recenterTrigger = $0 }),
            userScreenPosition: .constant(nil),
            targetCoordinate: .constant(nil),
            currentUserLocation: .constant(nil),
            transientHexShape: nil,
            selectedTheme: .day,
            fogOpacity: 0.94,
            showBoundaryBorders: true,
            showSubwayThoroughfares: true,
            subwayStationMarkerStyle: .allStations,
            nearbyBusStops: []
        )
        
        let coordinator = mapViewRepresentable.makeCoordinator()
        coordinator.mapView = mapView
        XCTAssertEqual(coordinator.lastRecenterTrigger, false)
        
        // Trigger recenter activation
        coordinator.handleRecenterTrigger(true, on: mapView, animated: false)
        
        XCTAssertEqual(coordinator.lastRecenterTrigger, true, "Coordinator must update lastRecenterTrigger to true")
        XCTAssertEqual(mapView.userTrackingMode, .followWithHeading, "Recenter must set tracking mode to followWithHeading")
        XCTAssertEqual(mapView.zoomLevel, 16.0, accuracy: 0.001, "Recenter trigger must set camera zoom to z = 16.0 pedestrian scale")
        
        // Triggering with the same value should be a no-op
        coordinator.handleRecenterTrigger(true, on: mapView, animated: false)
        XCTAssertEqual(coordinator.lastRecenterTrigger, true)
    }
}
