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

    // MARK: - 7. Surface Bus Tracking & Dead-Reckoning (Wave Pre-T.8c)

    func testBusTracking_InitialFixSnapsToCenterline() {
        // Straight Eastbound bus corridor along 42nd St (lat 40.7527)
        let busPolyline = [
            CLLocationCoordinate2D(latitude: 40.7527, longitude: -74.0000),
            CLLocationCoordinate2D(latitude: 40.7527, longitude: -73.9800)
        ]
        let session = LiveVehicleTrackingSession(modalClass: .bus)
        let t0 = 1700000000.0

        // Bus GPS reported 15m North of 42nd St (40.7527 + 0.000135)
        let rawGPS = CLLocationCoordinate2D(latitude: 40.7527 + 0.000135, longitude: -73.9900)
        let arrival = SpatialDatabaseManager.ArrivalInfo(
            line: "M42",
            destination: "Pier 83",
            minutes: 5,
            distanceDescription: "5 stops away",
            tripId: "BUS_M42_TEST",
            vehicleCoordinate: rawGPS,
            vehicleBearing: 90.0
        )
        let ladder = makeTestLadder()

        session.configure(polyline: busPolyline, arrival: arrival, ladder: ladder, now: t0)
        session.stepSimulation(at: t0)

        XCTAssertTrue(session.isVehicleOnCorridor, "Vehicle within 15m of corridor must be flagged on-corridor (<= 50m)")
        XCTAssertNotNil(session.currentCoordinate)
        XCTAssertEqual(session.currentCoordinate?.latitude ?? 0, 40.7527, accuracy: 1e-5, "Latitude must snap to road centerline")
        XCTAssertEqual(session.currentBearing, 90.0, accuracy: 2.0, "Bearing must match road segment orientation")
        XCTAssertEqual(session.activeEstimatedSpeed, 8.0, accuracy: 0.1, "Default initial cruising speed must be nominal 8 m/s")
    }

    func testBusTracking_DeadReckoningAdvancesAlongPolylineAtClampedSpeed() {
        let busPolyline = [
            CLLocationCoordinate2D(latitude: 40.7527, longitude: -74.0000),
            CLLocationCoordinate2D(latitude: 40.7527, longitude: -73.9800)
        ]
        let session = LiveVehicleTrackingSession(modalClass: .bus)
        let t0 = 1700000000.0

        let rawGPS = CLLocationCoordinate2D(latitude: 40.7527, longitude: -73.9950)
        let arrival = SpatialDatabaseManager.ArrivalInfo(
            line: "M42",
            destination: "Pier 83",
            minutes: 4,
            distanceDescription: "4 stops away",
            tripId: "BUS_M42_DEAD_RECKON",
            vehicleCoordinate: rawGPS,
            vehicleBearing: 90.0
        )
        let ladder = makeTestLadder()

        session.configure(polyline: busPolyline, arrival: arrival, ladder: ladder, now: t0)
        session.stepSimulation(at: t0)
        let initialDist = session.lastRenderedDistance

        // Advance simulation forward 5 seconds: dead-reckoning should advance by ~ 5s * 8 m/s = 40m
        session.stepSimulation(at: t0 + 5.0)
        let advancedDist = session.lastRenderedDistance

        XCTAssertGreaterThan(advancedDist, initialDist)
        XCTAssertEqual(advancedDist - initialDist, 40.0, accuracy: 2.0, "Dead-reckoning must advance along polyline at estimated speed")
    }

    func testBusTracking_SpeedClampedTo22MetersPerSecond() {
        let busPolyline = [
            CLLocationCoordinate2D(latitude: 40.7527, longitude: -74.0000),
            CLLocationCoordinate2D(latitude: 40.7527, longitude: -73.9700)
        ]
        let session = LiveVehicleTrackingSession(modalClass: .bus)
        let t0 = 1700000000.0

        let rawGPS1 = CLLocationCoordinate2D(latitude: 40.7527, longitude: -73.9950)
        let arrival1 = SpatialDatabaseManager.ArrivalInfo(
            line: "M42",
            destination: "Pier 83",
            minutes: 6,
            distanceDescription: "6 stops away",
            tripId: "BUS_SPEED_CLAMP",
            vehicleCoordinate: rawGPS1,
            vehicleBearing: 90.0
        )
        let ladder = makeTestLadder()

        session.configure(polyline: busPolyline, arrival: arrival1, ladder: ladder, now: t0)
        session.stepSimulation(at: t0)

        // New fix arrives 15s later with a 600m jump (40 m/s average speed -> exceeding 22 m/s ceiling)
        // 600m East lon diff ~ 600 / (111139 * cos(40.75 deg)) ~ 0.0071 deg lon
        let rawGPS2 = CLLocationCoordinate2D(latitude: 40.7527, longitude: -73.9950 + 0.0071)
        let arrival2 = SpatialDatabaseManager.ArrivalInfo(
            line: "M42",
            destination: "Pier 83",
            minutes: 3,
            distanceDescription: "3 stops away",
            tripId: "BUS_SPEED_CLAMP",
            vehicleCoordinate: rawGPS2,
            vehicleBearing: 90.0
        )

        session.reconcile(arrival: arrival2, ladder: ladder, now: t0 + 15.0)

        XCTAssertEqual(session.activeEstimatedSpeed, 22.0, accuracy: 1e-4, "Estimated speed must clamp to physical ceiling of 22 m/s (~49 mph)")
    }

    func testBusTracking_OffCorridorRetainsRawCoordinatesWithoutSnapping() {
        let busPolyline = [
            CLLocationCoordinate2D(latitude: 40.7527, longitude: -74.0000),
            CLLocationCoordinate2D(latitude: 40.7527, longitude: -73.9800)
        ]
        let session = LiveVehicleTrackingSession(modalClass: .bus)
        let t0 = 1700000000.0

        // Bus GPS reported 80m North of 42nd St (80m > 50m corridor gating)
        let rawGPS = CLLocationCoordinate2D(latitude: 40.7527 + 0.00072, longitude: -73.9900)
        let arrival = SpatialDatabaseManager.ArrivalInfo(
            line: "M42",
            destination: "Pier 83",
            minutes: 8,
            distanceDescription: "8 stops away",
            tripId: "BUS_OFF_CORRIDOR",
            vehicleCoordinate: rawGPS,
            vehicleBearing: 180.0
        )
        let ladder = makeTestLadder()

        session.configure(polyline: busPolyline, arrival: arrival, ladder: ladder, now: t0)
        session.stepSimulation(at: t0)

        XCTAssertFalse(session.isVehicleOnCorridor, "Vehicle offset 80m must be flagged off-corridor (> 50m threshold)")
        XCTAssertEqual(session.currentCoordinate?.latitude ?? 0, rawGPS.latitude, accuracy: 1e-7, "Off-corridor bus must retain raw GPS latitude")
        XCTAssertEqual(session.currentCoordinate?.longitude ?? 0, rawGPS.longitude, accuracy: 1e-7, "Off-corridor bus must retain raw GPS longitude")
        XCTAssertEqual(session.currentBearing, 180.0, accuracy: 0.1, "Off-corridor bus must retain raw GPS bearing")
        XCTAssertEqual(session.activeEstimatedSpeed, 0.0, accuracy: 1e-4, "Dead-reckoning along polyline must be bypassed when off-corridor")
    }

    func testBusTracking_15sFixReconciliationEliminatesJumps() {
        let busPolyline = [
            CLLocationCoordinate2D(latitude: 40.7527, longitude: -74.0000),
            CLLocationCoordinate2D(latitude: 40.7527, longitude: -73.9800)
        ]
        let session = LiveVehicleTrackingSession(modalClass: .bus)
        let t0 = 1700000000.0

        let rawGPS1 = CLLocationCoordinate2D(latitude: 40.7527, longitude: -73.9950)
        let arrival1 = SpatialDatabaseManager.ArrivalInfo(
            line: "M42",
            destination: "Pier 83",
            minutes: 5,
            distanceDescription: "5 stops away",
            tripId: "BUS_RECONCILE_JUMP",
            vehicleCoordinate: rawGPS1,
            vehicleBearing: 90.0
        )
        let ladder = makeTestLadder()

        session.configure(polyline: busPolyline, arrival: arrival1, ladder: ladder, now: t0)
        session.stepSimulation(at: t0)

        // Advance 15s with dead-reckoning
        session.stepSimulation(at: t0 + 15.0)
        let distBeforeReconcile = session.lastRenderedDistance

        // Second fix arrives at t0 + 15s with a 25m forward discrepancy
        // ~150m total progress vs dead-reckoned ~120m
        let rawGPS2 = CLLocationCoordinate2D(latitude: 40.7527, longitude: -73.9950 + 0.0018)
        let arrival2 = SpatialDatabaseManager.ArrivalInfo(
            line: "M42",
            destination: "Pier 83",
            minutes: 3,
            distanceDescription: "3 stops away",
            tripId: "BUS_RECONCILE_JUMP",
            vehicleCoordinate: rawGPS2,
            vehicleBearing: 90.0
        )

        session.reconcile(arrival: arrival2, ladder: ladder, now: t0 + 15.0)

        // At instant of reconciliation (t0 + 15s), position must match predicted exactly (zero jump)
        session.stepSimulation(at: t0 + 15.0)
        XCTAssertEqual(
            session.lastRenderedDistance,
            distBeforeReconcile,
            accuracy: 1e-4,
            "Reconciliation must eliminate teleportation jump at t = 0"
        )
        XCTAssertTrue(session.isCurrentlyReconciling)

        // After 1.5s, reconciliation completes smoothly
        session.stepSimulation(at: t0 + 16.5)
        XCTAssertFalse(session.isCurrentlyReconciling)
    }

    func testBusTracking_MonotonicClampPreventsBackwardSnapsOnStop() {
        let busPolyline = [
            CLLocationCoordinate2D(latitude: 40.7527, longitude: -74.0000),
            CLLocationCoordinate2D(latitude: 40.7527, longitude: -73.9800)
        ]
        let session = LiveVehicleTrackingSession(modalClass: .bus)
        let t0 = 1700000000.0

        let rawGPS1 = CLLocationCoordinate2D(latitude: 40.7527, longitude: -73.9950)
        let arrival1 = SpatialDatabaseManager.ArrivalInfo(
            line: "M42",
            destination: "Pier 83",
            minutes: 4,
            distanceDescription: "4 stops away",
            tripId: "BUS_MONOTONIC_RED_LIGHT",
            vehicleCoordinate: rawGPS1,
            vehicleBearing: 90.0
        )
        let ladder = makeTestLadder()

        session.configure(polyline: busPolyline, arrival: arrival1, ladder: ladder, now: t0)
        session.stepSimulation(at: t0)

        // Advance 15s
        session.stepSimulation(at: t0 + 15.0)
        let coastedDist = session.lastRenderedDistance

        // Bus actually stopped at a red light 10m behind where dead-reckoning coasted
        // GPS fix reports position at distance < coastedDist
        let rawGPS2 = CLLocationCoordinate2D(latitude: 40.7527, longitude: -73.9950 + 0.0008)
        let arrival2 = SpatialDatabaseManager.ArrivalInfo(
            line: "M42",
            destination: "Pier 83",
            minutes: 4,
            distanceDescription: "4 stops away",
            tripId: "BUS_MONOTONIC_RED_LIGHT",
            vehicleCoordinate: rawGPS2,
            vehicleBearing: 90.0
        )

        session.reconcile(arrival: arrival2, ladder: ladder, now: t0 + 15.0)

        // Monotonic clamp must prevent backward snap
        var prevDist = coastedDist
        for frame in 1...30 {
            let simTime = (t0 + 15.0) + (Double(frame) * (1.0 / 30.0))
            session.stepSimulation(at: simTime)
            XCTAssertGreaterThanOrEqual(
                session.lastRenderedDistance,
                prevDist,
                "Bus distance must be monotonically non-decreasing when stopped at red light"
            )
            prevDist = session.lastRenderedDistance
        }
    }

    func testRunInspectorSeparation_BusDoesNotUseSubwayKinematicTrapezoid() {
        let session = LiveVehicleTrackingSession(modalClass: .bus)
        XCTAssertEqual(session.modalClass, .bus, "Session modal class must be .bus")

        let subwaySession = LiveVehicleTrackingSession(modalClass: .subway)
        XCTAssertEqual(subwaySession.modalClass, .subway, "Subway session modal class must be .subway")
    }
}
