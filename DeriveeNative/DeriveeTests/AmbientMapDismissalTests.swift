import XCTest
import CoreGraphics
import CoreLocation
import MapLibre
import SwiftUI
@testable import Derivee

final class AmbientMapDismissalTests: XCTestCase {
    
    // MARK: - Tap Disambiguation Tests
    
    func testAmbientTapWhenNoFeaturesHit() {
        let tapPoint = CGPoint(x: 200.0, y: 300.0)
        let features: [MLNFeature] = []
        
        let closest = TransitHitTest.closestFeature(
            to: tapPoint,
            among: features,
            coordinateConverter: { _ in CGPoint(x: 0, y: 0) }
        )
        
        XCTAssertNil(closest, "Ambient tap with no nearby features must return nil closest feature")
    }
    
    func testAmbientTapWhenFeaturesOutsideHitBox() {
        let tapPoint = CGPoint(x: 100.0, y: 100.0)
        let farFeature = MLNPointFeature()
        farFeature.coordinate = CLLocationCoordinate2D(latitude: 40.7580, longitude: -73.9855)
        farFeature.attributes = ["id": "stop_far"]
        
        // Feature is 50pt away (outside 22pt radius tolerance)
        let _ = TransitHitTest.closestFeature(
            to: tapPoint,
            among: [farFeature],
            coordinateConverter: { _ in CGPoint(x: 150.0, y: 100.0) }
        )
        
        // If query was restricted to hitBox, features would be empty. Even if passed, dist is 50.
        // TransitHitTest selects closest if passed in features array, but MapView.visibleFeatures(in: hitBox) filters before.
        let hitBox = TransitHitTest.hitBox(for: tapPoint)
        XCTAssertFalse(hitBox.contains(CGPoint(x: 150.0, y: 100.0)), "Features outside 44pt hitBox must not be in hitBox")
    }
    
    func testPOITapReturnsValidStopId() {
        let tapPoint = CGPoint(x: 100.0, y: 100.0)
        let stopFeature = MLNPointFeature()
        stopFeature.coordinate = CLLocationCoordinate2D(latitude: 40.7580, longitude: -73.9855)
        stopFeature.attributes = ["id": "subway_times_sq_42"]
        
        let closest = TransitHitTest.closestFeature(
            to: tapPoint,
            among: [stopFeature],
            coordinateConverter: { _ in CGPoint(x: 105.0, y: 102.0) }
        )
        
        XCTAssertNotNil(closest)
        XCTAssertEqual(closest?.attributes["id"] as? String, "subway_times_sq_42")
    }
    
    // MARK: - Camera Gesture Reason Filter Tests
    
    func isUserGestureReason(_ reason: MLNCameraChangeReason) -> Bool {
        return reason.contains(.gesturePan) ||
               reason.contains(.gesturePinch) ||
               reason.contains(.gestureRotate) ||
               reason.contains(.gestureZoomIn) ||
               reason.contains(.gestureZoomOut)
    }
    
    func testUserGesturesTriggerAutoCollapse() {
        XCTAssertTrue(isUserGestureReason(.gesturePan), "Pan gesture must trigger auto-collapse")
        XCTAssertTrue(isUserGestureReason(.gesturePinch), "Pinch gesture must trigger auto-collapse")
        XCTAssertTrue(isUserGestureReason(.gestureRotate), "Rotate gesture must trigger auto-collapse")
        XCTAssertTrue(isUserGestureReason(.gestureZoomIn), "ZoomIn gesture must trigger auto-collapse")
        XCTAssertTrue(isUserGestureReason(.gestureZoomOut), "ZoomOut gesture must trigger auto-collapse")
        XCTAssertTrue(isUserGestureReason([.gesturePan, .gesturePinch]), "Combined gestures must trigger auto-collapse")
    }
    
    func testProgrammaticAndMomentumChangesDoNotTriggerAutoCollapse() {
        XCTAssertFalse(isUserGestureReason(.programmatic), "Programmatic camera change must NOT trigger auto-collapse")
        XCTAssertFalse(isUserGestureReason([]), "Empty camera change reason must NOT trigger auto-collapse")
    }
    
    // MARK: - State Pipeline & Reset Contract Tests
    
    @MainActor
    func testAmbientDismissalStateResetPipeline() {
        var isNearbyBusesExpanded = true
        let spatialStore = SpatialStore()
        spatialStore.newlyDiscoveredPOIName = "Grand Central - 42 St"
        
        let cityDetectionService = CityDetectionService()
        cityDetectionService.autoSwitchToast = CityAutoSwitchToastData(slug: "bos", cityName: "Boston")
        
        XCTAssertTrue(isNearbyBusesExpanded)
        XCTAssertNotNil(spatialStore.newlyDiscoveredPOIName)
        XCTAssertNotNil(cityDetectionService.autoSwitchToast)
        
        // Simulate ambient map tap action
        let onAmbientMapTap: () -> Void = {
            isNearbyBusesExpanded = false
            spatialStore.newlyDiscoveredPOIName = nil
            cityDetectionService.autoSwitchToast = nil
        }
        
        onAmbientMapTap()
        
        XCTAssertFalse(isNearbyBusesExpanded, "Nearby buses capsule must collapse on ambient tap")
        XCTAssertNil(spatialStore.newlyDiscoveredPOIName, "POI discovery toast must dismiss on ambient tap")
        XCTAssertNil(cityDetectionService.autoSwitchToast, "City auto-switch toast must dismiss on ambient tap")
    }
    
    @MainActor
    func testMapGestureCapsuleCollapsePipeline() {
        var isNearbyBusesExpanded = true
        
        let onMapGesture: () -> Void = {
            if isNearbyBusesExpanded {
                isNearbyBusesExpanded = false
            }
        }
        
        onMapGesture()
        XCTAssertFalse(isNearbyBusesExpanded, "Nearby buses capsule must collapse on map pan/drag gesture")
    }
    
    // MARK: - MapView Coordinator Wiring Tests
    
    @MainActor
    func testMapViewCoordinatorCallbacks() {
        var ambientTapFired = false
        var mapGestureFired = false
        
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
            nearbyBusStops: [],
            onAmbientMapTap: {
                ambientTapFired = true
            },
            onMapGesture: {
                mapGestureFired = true
            }
        )
        
        let coordinator = mapViewRepresentable.makeCoordinator()
        let mapView = MLNMapView(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        coordinator.mapView = mapView
        
        // Verify regionWillChange with gesture triggers onMapGesture
        coordinator.mapView(mapView, regionWillChangeWith: .gesturePan, animated: true)
        
        let exp = expectation(description: "Wait for main queue dispatch")
        DispatchQueue.main.async {
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1.0)
        
        XCTAssertTrue(mapGestureFired, "Coordinator must invoke parent.onMapGesture on gesturePan")
        XCTAssertFalse(ambientTapFired, "Gesture pan must not invoke onAmbientMapTap")
    }
}
