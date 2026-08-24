import XCTest
import CoreLocation
import MapLibre
@testable import Derivee

final class CameraBoundsTests: XCTestCase {
    
    // MARK: - Bounds Verification
    
    func testCoordinateInsideBounds() {
        // Manhattan
        let manhattan = CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060)
        XCTAssertTrue(CameraBounds.isWithinBounds(manhattan), "Manhattan should be within NYC fog bounds")
        
        // Brooklyn
        let brooklyn = CLLocationCoordinate2D(latitude: 40.6782, longitude: -73.9442)
        XCTAssertTrue(CameraBounds.isWithinBounds(brooklyn), "Brooklyn should be within NYC fog bounds")
        
        // Queens
        let queens = CLLocationCoordinate2D(latitude: 40.7282, longitude: -73.7949)
        XCTAssertTrue(CameraBounds.isWithinBounds(queens), "Queens should be within NYC fog bounds")
        
        // Bronx
        let bronx = CLLocationCoordinate2D(latitude: 40.8448, longitude: -73.8648)
        XCTAssertTrue(CameraBounds.isWithinBounds(bronx), "Bronx should be within NYC fog bounds")
        
        // Staten Island
        let statenIsland = CLLocationCoordinate2D(latitude: 40.5795, longitude: -74.1502)
        XCTAssertTrue(CameraBounds.isWithinBounds(statenIsland), "Staten Island should be within NYC fog bounds")
    }
    
    func testCoordinateOnExactBoundaries() {
        // SW Corner
        let sw = CLLocationCoordinate2D(latitude: 40.0, longitude: -74.5)
        XCTAssertTrue(CameraBounds.isWithinBounds(sw), "SW corner should be within bounds")
        
        // NE Corner
        let ne = CLLocationCoordinate2D(latitude: 41.5, longitude: -73.0)
        XCTAssertTrue(CameraBounds.isWithinBounds(ne), "NE corner should be within bounds")
        
        // SE Corner
        let se = CLLocationCoordinate2D(latitude: 40.0, longitude: -73.0)
        XCTAssertTrue(CameraBounds.isWithinBounds(se), "SE corner should be within bounds")
        
        // NW Corner
        let nw = CLLocationCoordinate2D(latitude: 41.5, longitude: -74.5)
        XCTAssertTrue(CameraBounds.isWithinBounds(nw), "NW corner should be within bounds")
    }
    
    func testCoordinateOutsideBounds() {
        // North
        let north = CLLocationCoordinate2D(latitude: 41.5001, longitude: -73.8)
        XCTAssertFalse(CameraBounds.isWithinBounds(north), "Latitude > 41.5 should be outside bounds")
        
        // South
        let south = CLLocationCoordinate2D(latitude: 39.9999, longitude: -73.8)
        XCTAssertFalse(CameraBounds.isWithinBounds(south), "Latitude < 40.0 should be outside bounds")
        
        // West
        let west = CLLocationCoordinate2D(latitude: 40.7, longitude: -74.5001)
        XCTAssertFalse(CameraBounds.isWithinBounds(west), "Longitude < -74.5 should be outside bounds")
        
        // East
        let east = CLLocationCoordinate2D(latitude: 40.7, longitude: -72.9999)
        XCTAssertFalse(CameraBounds.isWithinBounds(east), "Longitude > -73.0 should be outside bounds")
    }
    
    // MARK: - Clamping Math
    
    func testClampingToBoundaryEdges() {
        // Point far North-East
        let farNE = CLLocationCoordinate2D(latitude: 42.5, longitude: -72.0)
        let clampedNE = CameraBounds.clampedCoordinate(for: farNE)
        XCTAssertEqual(clampedNE.latitude, 41.5, accuracy: 1e-9)
        XCTAssertEqual(clampedNE.longitude, -73.0, accuracy: 1e-9)
        
        // Point far South-West
        let farSW = CLLocationCoordinate2D(latitude: 38.0, longitude: -76.0)
        let clampedSW = CameraBounds.clampedCoordinate(for: farSW)
        XCTAssertEqual(clampedSW.latitude, 40.0, accuracy: 1e-9)
        XCTAssertEqual(clampedSW.longitude, -74.5, accuracy: 1e-9)
        
        // Point already inside
        let midCity = CLLocationCoordinate2D(latitude: 40.75, longitude: -73.98)
        let clampedMid = CameraBounds.clampedCoordinate(for: midCity)
        XCTAssertEqual(clampedMid.latitude, 40.75, accuracy: 1e-9)
        XCTAssertEqual(clampedMid.longitude, -73.98, accuracy: 1e-9)
    }
    
    // MARK: - Rubber Band Elastic Limits
    
    func testRubberBandLimits() {
        // Slightly North within elastic margin (41.5 + 0.03 < 41.55)
        let rubberBandNorth = CLLocationCoordinate2D(latitude: 41.53, longitude: -73.8)
        XCTAssertFalse(CameraBounds.isWithinBounds(rubberBandNorth))
        XCTAssertTrue(CameraBounds.isWithinRubberBandLimit(rubberBandNorth), "Should be within rubber band elastic limit")
        
        // Far North exceeding elastic margin (41.5 + 0.10 > 41.55)
        let extremeNorth = CLLocationCoordinate2D(latitude: 41.60, longitude: -73.8)
        XCTAssertFalse(CameraBounds.isWithinBounds(extremeNorth))
        XCTAssertFalse(CameraBounds.isWithinRubberBandLimit(extremeNorth), "Should exceed rubber band elastic limit")
    }
    
    // MARK: - Camera Change Gating
    
    func testShouldAllowCameraChangeInsideBounds() {
        let oldCam = MLNMapCamera(lookingAtCenter: CLLocationCoordinate2D(latitude: 40.7, longitude: -74.0), altitude: 1000, pitch: 0, heading: 0)
        let newCam = MLNMapCamera(lookingAtCenter: CLLocationCoordinate2D(latitude: 40.75, longitude: -73.95), altitude: 1000, pitch: 0, heading: 0)
        
        let allowed = CameraBounds.shouldAllowCameraChange(from: oldCam, to: newCam, reason: .gesturePan)
        XCTAssertTrue(allowed, "Movements within bounds must always be permitted")
    }
    
    func testShouldAllowCameraChangeDuringGestureRubberBand() {
        let oldCam = MLNMapCamera(lookingAtCenter: CLLocationCoordinate2D(latitude: 41.4, longitude: -74.0), altitude: 1000, pitch: 0, heading: 0)
        // Moving slightly beyond north border into rubber-band buffer (41.53 < 41.55)
        let newCam = MLNMapCamera(lookingAtCenter: CLLocationCoordinate2D(latitude: 41.53, longitude: -74.0), altitude: 1000, pitch: 0, heading: 0)
        
        let allowedPan = CameraBounds.shouldAllowCameraChange(from: oldCam, to: newCam, reason: .gesturePan)
        XCTAssertTrue(allowedPan, "Gestures within rubber-band margin must be permitted for fluid damping physics")
        
        let allowedPinch = CameraBounds.shouldAllowCameraChange(from: oldCam, to: newCam, reason: .gesturePinch)
        XCTAssertTrue(allowedPinch, "Pinch gestures within rubber-band margin must be permitted")
        
        // Moving beyond rubber band limit (43.0 > 41.55)
        let farCam = MLNMapCamera(lookingAtCenter: CLLocationCoordinate2D(latitude: 43.0, longitude: -74.0), altitude: 1000, pitch: 0, heading: 0)
        let allowedFar = CameraBounds.shouldAllowCameraChange(from: oldCam, to: farCam, reason: .gesturePan)
        XCTAssertFalse(allowedFar, "Gestures beyond rubber band margin must be rejected to prevent drifting into oblivion")
    }
    
    func testShouldAllowCameraChangeDuringRollback() {
        let oldCam = MLNMapCamera(lookingAtCenter: CLLocationCoordinate2D(latitude: 41.7, longitude: -74.0), altitude: 1000, pitch: 0, heading: 0)
        let rollbackCam = MLNMapCamera(lookingAtCenter: CLLocationCoordinate2D(latitude: 41.5, longitude: -74.0), altitude: 1000, pitch: 0, heading: 0)
        
        let allowed = CameraBounds.shouldAllowCameraChange(from: oldCam, to: rollbackCam, reason: .programmatic, isRollingBack: true)
        XCTAssertTrue(allowed, "Rollback movements must always be permitted")
    }
    
    // MARK: - 2D Top-Down Pitch & Tilt Locking
    
    func testShouldRejectPitchedCameraChange() {
        let oldCam = MLNMapCamera(lookingAtCenter: CLLocationCoordinate2D(latitude: 40.7, longitude: -74.0), altitude: 1000, pitch: 0, heading: 0)
        let pitchedCam = MLNMapCamera(lookingAtCenter: CLLocationCoordinate2D(latitude: 40.7, longitude: -74.0), altitude: 1000, pitch: 45.0, heading: 0)
        
        let allowed = CameraBounds.shouldAllowCameraChange(from: oldCam, to: pitchedCam, reason: .gesturePan)
        XCTAssertFalse(allowed, "Any camera transition with pitch > 0 must be rejected to enforce strict 2D top-down view")
    }
    
    func testShouldRejectTiltGesture() {
        let oldCam = MLNMapCamera(lookingAtCenter: CLLocationCoordinate2D(latitude: 40.7, longitude: -74.0), altitude: 1000, pitch: 0, heading: 0)
        let newCam = MLNMapCamera(lookingAtCenter: CLLocationCoordinate2D(latitude: 40.7, longitude: -74.0), altitude: 1000, pitch: 0, heading: 0)
        
        let allowed = CameraBounds.shouldAllowCameraChange(from: oldCam, to: newCam, reason: .gestureTilt)
        XCTAssertFalse(allowed, "GestureTilt must be rejected unconditionally")
    }
    
    func testShouldAllowRotationAndPanZeroPitch() {
        let oldCam = MLNMapCamera(lookingAtCenter: CLLocationCoordinate2D(latitude: 40.7, longitude: -74.0), altitude: 1000, pitch: 0, heading: 0)
        let rotatedCam = MLNMapCamera(lookingAtCenter: CLLocationCoordinate2D(latitude: 40.71, longitude: -74.01), altitude: 1000, pitch: 0, heading: 90.0)
        
        let allowedRotate = CameraBounds.shouldAllowCameraChange(from: oldCam, to: rotatedCam, reason: .gestureRotate)
        XCTAssertTrue(allowedRotate, "2D rotation gestures with zero pitch must be permitted")
        
        let allowedPan = CameraBounds.shouldAllowCameraChange(from: oldCam, to: rotatedCam, reason: .gesturePan)
        XCTAssertTrue(allowedPan, "2D pan gestures with zero pitch must be permitted")
    }
}

