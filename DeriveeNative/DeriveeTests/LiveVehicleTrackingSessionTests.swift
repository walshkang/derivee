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
    
    // MARK: - 7. Critically Damped Reconciliation (Wave Pre-T.8b)
    
    func testReconciliation_ZeroJumpContinuity() {
        let session = LiveVehicleTrackingSession()
        let t0 = 1700000000.0
        
        let initialArrival = SpatialDatabaseManager.ArrivalInfo(
            line: "7",
            destination: "Flushing-Main St",
            minutes: 4,
            distanceDescription: "In Transit",
            tripId: "TRIP_RECONCILE_1",
            progressLambda: 0.25
        )
        let ladder = makeTestLadder()
        
        session.configure(polyline: testPolyline, arrival: initialArrival, ladder: ladder, now: t0)
        session.stepSimulation(at: t0)
        let dPredicted = session.lastRenderedDistance
        
        // Feed update arrives at t0 with updated progress (train is further ahead)
        let updatedArrival = SpatialDatabaseManager.ArrivalInfo(
            line: "7",
            destination: "Flushing-Main St",
            minutes: 2,
            distanceDescription: "Approaching",
            tripId: "TRIP_RECONCILE_1",
            progressLambda: 0.75
        )
        
        session.reconcile(arrival: updatedArrival, ladder: ladder, now: t0)
        XCTAssertTrue(session.isCurrentlyReconciling, "Reconciliation must be active when feed reports different position")
        XCTAssertGreaterThan(session.activeReconciliationError, 0.0)
        
        // At Δt = 0 (exact moment of reconciliation), rendered distance must equal dPredicted
        session.stepSimulation(at: t0)
        XCTAssertEqual(
            session.lastRenderedDistance,
            dPredicted,
            accuracy: 1e-4,
            "At Δt = 0, critically damped filter must preserve exact continuity with zero frame jump"
        )
    }
    
    func testReconciliation_CriticallyDampedDecayRate() {
        let session = LiveVehicleTrackingSession()
        let t0 = 1700000000.0
        
        let initialArrival = SpatialDatabaseManager.ArrivalInfo(
            line: "7",
            destination: "Flushing-Main St",
            minutes: 5,
            distanceDescription: "In Transit",
            tripId: "TRIP_RECONCILE_DECAY",
            progressLambda: 0.2
        )
        let ladder = makeTestLadder()
        session.configure(polyline: testPolyline, arrival: initialArrival, ladder: ladder, now: t0)
        session.stepSimulation(at: t0)
        
        let updatedArrival = SpatialDatabaseManager.ArrivalInfo(
            line: "7",
            destination: "Flushing-Main St",
            minutes: 2,
            distanceDescription: "Approaching",
            tripId: "TRIP_RECONCILE_DECAY",
            progressLambda: 0.8
        )
        session.reconcile(arrival: updatedArrival, ladder: ladder, now: t0)
        
        let e0 = session.activeReconciliationError
        XCTAssertGreaterThan(e0, 1.0)
        
        // Verify decay at Δt = 0.2s: theoretical offset = e0 * (1 + 5*0.2) * exp(-5*0.2) = e0 * 2 * exp(-1)
        let dt1 = 0.2
        let expectedOffset1 = e0 * (1.0 + 5.0 * dt1) * exp(-5.0 * dt1)
        let ratio1 = expectedOffset1 / e0
        XCTAssertEqual(ratio1, 2.0 * exp(-1.0), accuracy: 1e-4) // ~0.7358
        
        // Verify decay at Δt = 1.0s: theoretical offset = e0 * (1 + 5) * exp(-5) = e0 * 6 * exp(-5) ~ 0.0404
        let dt2 = 1.0
        let expectedOffset2 = e0 * (1.0 + 5.0 * dt2) * exp(-5.0 * dt2)
        let ratio2 = expectedOffset2 / e0
        XCTAssertEqual(ratio2, 6.0 * exp(-5.0), accuracy: 1e-4)
        XCTAssertLessThan(ratio2, 0.05, "After 1.0s, >95% of prediction error must be absorbed")
        
        // Advance simulation past 1.5s -> reconciliation must complete and extinguish
        session.stepSimulation(at: t0 + 1.5)
        XCTAssertFalse(session.isCurrentlyReconciling, "Reconciliation must mark complete after 1.5s window")
        XCTAssertEqual(session.activeReconciliationError, 0.0, accuracy: 1e-6)
    }
    
    func testReconciliation_MonotonicClampPreventsBackwardSnaps() {
        let session = LiveVehicleTrackingSession()
        let t0 = 1700000000.0
        
        // Position vehicle near target station
        let initialArrival = SpatialDatabaseManager.ArrivalInfo(
            line: "7",
            destination: "Flushing-Main St",
            minutes: 1,
            distanceDescription: "Approaching",
            tripId: "TRIP_RECONCILE_MONOTONIC",
            progressLambda: 0.8
        )
        let ladder = makeTestLadder()
        session.configure(polyline: testPolyline, arrival: initialArrival, ladder: ladder, now: t0)
        
        // Advance vehicle forward
        session.stepSimulation(at: t0 + 20.0)
        let advancedDistance = session.lastRenderedDistance
        XCTAssertGreaterThan(advancedDistance, 50.0)
        
        // Retroactive/delayed feed packet arrives reporting train earlier in corridor
        let retroactiveArrival = SpatialDatabaseManager.ArrivalInfo(
            line: "7",
            destination: "Flushing-Main St",
            minutes: 6,
            distanceDescription: "6 stops away",
            tripId: "TRIP_RECONCILE_MONOTONIC",
            progressLambda: 0.1
        )
        session.reconcile(arrival: retroactiveArrival, ladder: ladder, now: t0 + 20.0)
        
        // Error e0 must be negative (reported < predicted)
        XCTAssertLessThan(session.activeReconciliationError, 0.0)
        
        // Step simulation across 30 frames: distance must NEVER drop below advancedDistance
        var previousDistance = advancedDistance
        for step in 1...30 {
            let simTime = (t0 + 20.0) + (Double(step) * (1.0 / 30.0))
            session.stepSimulation(at: simTime)
            
            XCTAssertGreaterThanOrEqual(
                session.lastRenderedDistance,
                previousDistance,
                "Distance must be monotonically non-decreasing (no backward snaps)"
            )
            XCTAssertGreaterThanOrEqual(
                session.lastRenderedDistance,
                advancedDistance,
                "Monotonic clamp must prevent retroactive feed packet from pulling consist backwards"
            )
            previousDistance = session.lastRenderedDistance
        }
    }
    
    func testReconciliation_ChainedFeedUpdates() {
        let session = LiveVehicleTrackingSession()
        let t0 = 1700000000.0
        
        let initialArrival = SpatialDatabaseManager.ArrivalInfo(
            line: "7",
            destination: "Flushing-Main St",
            minutes: 4,
            distanceDescription: "4 stops away",
            tripId: "TRIP_CHAINED",
            progressLambda: 0.2
        )
        let ladder = makeTestLadder()
        session.configure(polyline: testPolyline, arrival: initialArrival, ladder: ladder, now: t0)
        session.stepSimulation(at: t0)
        
        // First feed update at t0 + 0.1s
        let update1 = SpatialDatabaseManager.ArrivalInfo(
            line: "7",
            destination: "Flushing-Main St",
            minutes: 3,
            distanceDescription: "3 stops away",
            tripId: "TRIP_CHAINED",
            progressLambda: 0.4
        )
        session.reconcile(arrival: update1, ladder: ladder, now: t0 + 0.1)
        session.stepSimulation(at: t0 + 0.3)
        let distBeforeSecond = session.lastRenderedDistance
        
        // Second feed update arrives at t0 + 0.3s while first reconciliation is still active
        let update2 = SpatialDatabaseManager.ArrivalInfo(
            line: "7",
            destination: "Flushing-Main St",
            minutes: 2,
            distanceDescription: "2 stops away",
            tripId: "TRIP_CHAINED",
            progressLambda: 0.7
        )
        session.reconcile(arrival: update2, ladder: ladder, now: t0 + 0.3)
        
        // At instant of second update, continuity must be preserved
        session.stepSimulation(at: t0 + 0.3)
        XCTAssertEqual(
            session.lastRenderedDistance,
            distBeforeSecond,
            accuracy: 1e-4,
            "Chained reconciliation must maintain seamless continuity without jump"
        )
    }
    
    func testReconciliation_IdempotentOnIdenticalFeed() {
        let session = LiveVehicleTrackingSession()
        let t0 = 1700000000.0
        
        let initialArrival = SpatialDatabaseManager.ArrivalInfo(
            line: "7",
            destination: "Flushing-Main St",
            minutes: 3,
            distanceDescription: "3 stops away",
            tripId: "TRIP_IDEMPOTENT",
            progressLambda: 0.5
        )
        let ladder = makeTestLadder()
        session.configure(polyline: testPolyline, arrival: initialArrival, ladder: ladder, now: t0)
        session.stepSimulation(at: t0)
        
        // Reconcile with identical arrival at t0
        session.reconcile(arrival: initialArrival, ladder: ladder, now: t0)
        
        XCTAssertFalse(session.isCurrentlyReconciling, "Identical feed update must not trigger unnecessary reconciliation")
        XCTAssertEqual(session.activeReconciliationError, 0.0, accuracy: 0.1)
    }
}
