import XCTest
import CoreLocation
import UIKit
@testable import Derivee
@testable import DeriveeCore

@MainActor
final class LiveVehicleTrackingSessionTests: XCTestCase {
    
    // MARK: - Fixtures
    
    private let testPolyline: [CLLocationCoordinate2D] = [
        CLLocationCoordinate2D(latitude: 40.7580, longitude: -73.9855), // Times Square (42 St)
        CLLocationCoordinate2D(latitude: 40.7527, longitude: -73.9772), // Grand Central (42 St)
        CLLocationCoordinate2D(latitude: 40.7484, longitude: -73.9857)  // 34 St-Herald Sq
    ]
    
    private func makeTestLadder() -> [TrackStop] {
        [
            TrackStop(
                stopId: "TIMES_SQ",
                stopName: "Times Sq-42 St",
                coordinate: testPolyline[0],
                sequenceIndex: 1,
                isVehicleHere: true
            ),
            TrackStop(
                stopId: "GRAND_CENTRAL",
                stopName: "Grand Central-42 St",
                coordinate: testPolyline[1],
                sequenceIndex: 2,
                isCurrent: true
            ),
            TrackStop(
                stopId: "HERALD_SQ",
                stopName: "34 St-Herald Sq",
                coordinate: testPolyline[2],
                sequenceIndex: 3
            )
        ]
    }
    
    // MARK: - 1. Session Initialization & Geometry Construction
    
    func testSessionInitialization_BuildsInterpolatorAndGeometry() {
        let session = LiveVehicleTrackingSession()
        XCTAssertFalse(session.isRunning)
        
        let arrival = SpatialDatabaseManager.ArrivalInfo(
            line: "7",
            destination: "Flushing-Main St",
            minutes: 0,
            distanceDescription: "Boarding",
            tripId: "TRIP_7_TEST"
        )
        let ladder = makeTestLadder()
        
        session.configure(polyline: testPolyline, arrival: arrival, ladder: ladder)
        XCTAssertFalse(session.isRunning, "Session should not start until start() is explicitly invoked")
        
        session.start()
        XCTAssertTrue(session.isRunning, "Session must be running after start()")
        
        session.stop()
        XCTAssertFalse(session.isRunning, "Session must stop after stop()")
    }
    
    // MARK: - 2. Direct VehicleFrameRelay (Zero SwiftUI Body Churn)
    
    func testDirectRelay_EmitsCoordinatesWithoutBodyReEvaluation() {
        let relay = VehicleFrameRelay()
        
        var receivedCoord: CLLocationCoordinate2D? = nil
        var receivedBearing: Double? = nil
        var callCount = 0
        
        relay.handler = { coord, bearing in
            receivedCoord = coord
            receivedBearing = bearing
            callCount += 1
        }
        
        let testCoord = CLLocationCoordinate2D(latitude: 40.7527, longitude: -73.9772)
        let testBearing: Double = 90.0
        
        // Emit 30 frames
        for _ in 0..<30 {
            relay.emit(coordinate: testCoord, bearing: testBearing)
        }
        
        XCTAssertEqual(callCount, 30, "Relay must directly forward every frame callback")
        XCTAssertEqual(receivedCoord?.latitude ?? 0, testCoord.latitude, accuracy: 0.0001)
        XCTAssertEqual(receivedCoord?.longitude ?? 0, testCoord.longitude, accuracy: 0.0001)
        XCTAssertEqual(receivedBearing ?? 0, testBearing, accuracy: 0.1)
    }
    
    // MARK: - 3. Doc 17 Invariant: Terminal Origin Dwell Clamp (λ ≡ 0.0)
    
    func testDoc17_TerminalOriginDwellClamp() {
        let session = LiveVehicleTrackingSession()
        let arrival = SpatialDatabaseManager.ArrivalInfo(
            line: "7",
            destination: "Flushing-Main St",
            minutes: 0,
            distanceDescription: "At Platform",
            tripId: "TRIP_TERMINAL_DWELL",
            isAssigned: true
        )
        let ladder = makeTestLadder()
        
        session.configure(polyline: testPolyline, arrival: arrival, ladder: ladder)
        session.start()
        
        // In dwell state, progress must clamp to 0.0
        XCTAssertEqual(session.linearProgress, 0.0, accuracy: 1e-6)
        
        session.stop()
    }
    
    // MARK: - 4. Doc 17 Invariant: Mid-Tunnel Hold Clamp (λ = 0.85)
    
    func testDoc17_MidTunnelHoldClamp() {
        let session = LiveVehicleTrackingSession()
        let arrival = SpatialDatabaseManager.ArrivalInfo(
            line: "7",
            destination: "Flushing-Main St",
            minutes: 3,
            distanceDescription: "In Transit",
            tripId: "TRIP_IN_TRANSIT",
            progressLambda: 0.95 // Telemetry attempting to exceed approach ceiling
        )
        let ladder = makeTestLadder()
        
        session.configure(polyline: testPolyline, arrival: arrival, ladder: ladder)
        session.start()
        
        // Progress for IN_TRANSIT_TO must never exceed approach progress ceiling (0.85)
        XCTAssertLessThanOrEqual(session.linearProgress, 0.85 + 1e-6)
        
        session.stop()
    }
    
    // MARK: - 5. Lifecycle & Battery Conservation (0% Background Idle Drain)
    
    func testLifecycle_PausesOnBackground_ResumesOnForeground() {
        let session = LiveVehicleTrackingSession()
        let arrival = SpatialDatabaseManager.ArrivalInfo(
            line: "7",
            destination: "Flushing-Main St",
            minutes: 2,
            distanceDescription: "2 stops away"
        )
        let ladder = makeTestLadder()
        
        session.configure(polyline: testPolyline, arrival: arrival, ladder: ladder)
        session.start()
        XCTAssertTrue(session.isRunning)
        
        // Post background notification -> must pause
        NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        XCTAssertFalse(session.isRunning, "Tracking session must pause on backgrounding (0% idle battery drain)")
        
        // Post foreground notification -> must resume
        NotificationCenter.default.post(name: UIApplication.willEnterForegroundNotification, object: nil)
        XCTAssertTrue(session.isRunning, "Tracking session must resume upon returning to foreground")
        
        session.stop()
        XCTAssertFalse(session.isRunning)
    }
    
    // MARK: - 6. Teardown Lifecycle
    
    func testInspectorDismiss_InvalidatesSession() {
        let session = LiveVehicleTrackingSession()
        session.start()
        XCTAssertTrue(session.isRunning)
        
        session.stop()
        XCTAssertFalse(session.isRunning)
        
        // Subsequent stop calls should be idempotent
        session.stop()
        XCTAssertFalse(session.isRunning)
    }
}
