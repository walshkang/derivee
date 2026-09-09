import XCTest
import CxxStdlib
@testable import DeriveeCore

final class SubwayPositionInterpolatorTests: XCTestCase {

    // MARK: - Helpers

    private func makeInterpolator(
        points: [Point2D],
        refLat: Double = 40.7128,
        refLon: Double = -74.0060
    ) -> SubwayPositionInterpolator {
        points.withUnsafeBufferPointer { buf in
            SubwayPositionInterpolator(buf.baseAddress, buf.count, refLat, refLon)
        }
    }

    private func makeGeographicInterpolator(
        coords: [GeoCoordinate],
        refLat: Double = 40.7128,
        refLon: Double = -74.0060
    ) -> SubwayPositionInterpolator {
        coords.withUnsafeBufferPointer { buf in
            SubwayPositionInterpolator.from_geographic_coords(buf.baseAddress, buf.count, refLat, refLon)
        }
    }

    // MARK: - 1. Conformal Coordinate Projection

    func testConformalProjectionRoundTrip() {
        let interpolator = makeInterpolator(points: [])

        // Reference center should project to origin (0, 0)
        let originGeo = GeoCoordinate(40.7128, -74.0060)
        let originPt = interpolator.to_conformal(originGeo)
        XCTAssertEqual(originPt.x, 0.0, accuracy: 1e-4)
        XCTAssertEqual(originPt.y, 0.0, accuracy: 1e-4)

        // Times Square (40.7580, -73.9855)
        let timesSquareGeo = GeoCoordinate(40.7580, -73.9855)
        let timesSquarePt = interpolator.to_conformal(timesSquareGeo)

        // Conformal coordinates should be positive North and East
        XCTAssertGreaterThan(timesSquarePt.x, 1000.0)
        XCTAssertGreaterThan(timesSquarePt.y, 4000.0)

        // Inverse projection should restore latitude and longitude to sub-millimeter precision
        let roundTripGeo = interpolator.to_geographic(timesSquarePt)
        XCTAssertEqual(roundTripGeo.latitude, timesSquareGeo.latitude, accuracy: 1e-7)
        XCTAssertEqual(roundTripGeo.longitude, timesSquareGeo.longitude, accuracy: 1e-7)
    }

    // MARK: - 2. Polyline Geometry & Distance Interpolation

    func testPolylineGeometryCreationAndDistance() {
        // L-shaped polyline: (0, 0) -> (100, 0) -> (100, 200)
        // Segment 1: East 100m; Segment 2: North 200m; Total = 300m
        let pts = [
            Point2D(0.0, 0.0),
            Point2D(100.0, 0.0),
            Point2D(100.0, 200.0)
        ]
        let interpolator = makeInterpolator(points: pts)

        XCTAssertEqual(interpolator.vertex_count(), 3)
        XCTAssertEqual(interpolator.total_shape_distance(), 300.0, accuracy: 1e-6)

        // Midway along Segment 1 (50m) -> (50, 0), heading East (pi/2 rad, 90 deg)
        var heading50: Double = 0.0
        let pt50 = interpolator.interpolate_point_at_distance(50.0, &heading50)
        XCTAssertEqual(pt50.x, 50.0, accuracy: 1e-6)
        XCTAssertEqual(pt50.y, 0.0, accuracy: 1e-6)
        XCTAssertEqual(heading50, .pi / 2.0, accuracy: 1e-6)

        // Midway along Segment 2 (200m = 100m + 100m) -> (100, 100), heading North (0 rad, 0 deg)
        var heading200: Double = 0.0
        let pt200 = interpolator.interpolate_point_at_distance(200.0, &heading200)
        XCTAssertEqual(pt200.x, 100.0, accuracy: 1e-6)
        XCTAssertEqual(pt200.y, 100.0, accuracy: 1e-6)
        XCTAssertEqual(heading200, 0.0, accuracy: 1e-6)

        // Beyond total distance (clamped to 300m) -> (100, 200)
        var heading400: Double = 0.0
        let pt400 = interpolator.interpolate_point_at_distance(400.0, &heading400)
        XCTAssertEqual(pt400.x, 100.0, accuracy: 1e-6)
        XCTAssertEqual(pt400.y, 200.0, accuracy: 1e-6)
    }

    // MARK: - 3. Orthogonal Polyline Linear Referencing (Doc 17 Eq. 88–98)

    func testOrthogonalProjectionOnAndOffAxis() {
        let pts = [
            Point2D(0.0, 0.0),
            Point2D(200.0, 0.0)
        ]
        let interpolator = makeInterpolator(points: pts)

        // 1. Point directly on the segment
        var perpDist1: Double = 0.0
        let linDist1 = interpolator.project_point_with_distance(Point2D(75.0, 0.0), &perpDist1)
        XCTAssertEqual(linDist1, 75.0, accuracy: 1e-6)
        XCTAssertEqual(perpDist1, 0.0, accuracy: 1e-6)

        // 2. Point off-axis (requiring orthogonal projection)
        var perpDist2: Double = 0.0
        let linDist2 = interpolator.project_point_with_distance(Point2D(120.0, 35.0), &perpDist2)
        XCTAssertEqual(linDist2, 120.0, accuracy: 1e-6)
        XCTAssertEqual(perpDist2, 35.0, accuracy: 1e-6)

        // 3. Point before start of segment (clamped to start, u_hat = 0)
        var perpDist3: Double = 0.0
        let linDist3 = interpolator.project_point_with_distance(Point2D(-40.0, 30.0), &perpDist3)
        XCTAssertEqual(linDist3, 0.0, accuracy: 1e-6)
        XCTAssertEqual(perpDist3, 50.0, accuracy: 1e-6) // sqrt((-40)^2 + 30^2) = 50

        // 4. Point beyond end of segment (clamped to end, u_hat = 1)
        var perpDist4: Double = 0.0
        let linDist4 = interpolator.project_point_with_distance(Point2D(230.0, 40.0), &perpDist4)
        XCTAssertEqual(linDist4, 200.0, accuracy: 1e-6)
        XCTAssertEqual(perpDist4, 50.0, accuracy: 1e-6) // sqrt((230-200)^2 + 40^2) = 50

        // 5. Multi-segment bend resolution
        let bendPts = [
            Point2D(0.0, 0.0),
            Point2D(100.0, 0.0),
            Point2D(100.0, 200.0)
        ]
        let bendInterp = makeInterpolator(points: bendPts)

        // Platform at (115, 140) -> nearest to second segment at (100, 140)
        // Linear distance = 100 + 140 = 240m; perp distance = 15m
        var perpDistBend: Double = 0.0
        let linDistBend = bendInterp.project_point_with_distance(Point2D(115.0, 140.0), &perpDistBend)
        XCTAssertEqual(linDistBend, 240.0, accuracy: 1e-6)
        XCTAssertEqual(perpDistBend, 15.0, accuracy: 1e-6)
    }

    // MARK: - 4. Analytical Trapezoidal Kinematic Solver (R160/R142 Profile)

    func testAnalyticalTrapezoidalKinematicSolver() {
        let interpolator = SubwayPositionInterpolator()
        let distance: Double = 1000.0 // 1 km
        let totalDur: Double = 80.0   // 80 s
        let a: Double = 1.15
        let d: Double = 1.25

        // Boundary checks
        XCTAssertEqual(interpolator.solve_kinematic_progress(0.0, totalDur, distance, a, d), 0.0, accuracy: 1e-6)
        XCTAssertEqual(interpolator.solve_kinematic_progress(totalDur, totalDur, distance, a, d), 1.0, accuracy: 1e-6)

        // Strict monotonicity verification across time progression
        var previousLambda: Double = -1.0
        for sec in stride(from: 0.0, through: totalDur, by: 5.0) {
            let lambda = interpolator.solve_kinematic_progress(sec, totalDur, distance, a, d)
            XCTAssertGreaterThanOrEqual(lambda, previousLambda)
            XCTAssertGreaterThanOrEqual(lambda, 0.0)
            XCTAssertLessThanOrEqual(lambda, 1.0)
            previousLambda = lambda
        }

        // Acceleration phase verification: s = 0.5 * a * t^2
        let tAcc = 4.0 // 4 seconds in
        let expectedAccDist = 0.5 * a * tAcc * tAcc
        let expectedAccLambda = expectedAccDist / distance
        let actualAccLambda = interpolator.solve_kinematic_progress(tAcc, totalDur, distance, a, d)
        XCTAssertEqual(actualAccLambda, expectedAccLambda, accuracy: 1e-4)

        // Deceleration phase verification: s = L - 0.5 * d * (T - t)^2
        let tDec = 78.0 // 2 seconds before arrival
        let dtBrake = totalDur - tDec
        let expectedDecDist = distance - (0.5 * d * dtBrake * dtBrake)
        let expectedDecLambda = expectedDecDist / distance
        let actualDecLambda = interpolator.solve_kinematic_progress(tDec, totalDur, distance, a, d)
        XCTAssertEqual(actualDecLambda, expectedDecLambda, accuracy: 1e-4)
    }

    // MARK: - 5. Quintic Hermite Smootherstep Fallback for Compressed Schedules

    func testCompressedScheduleQuinticHermiteFallback() {
        let interpolator = SubwayPositionInterpolator()
        let distance: Double = 1000.0
        let compressedDur: Double = 20.0 // Physically impossible in 20s under 1.15/1.25 m/s^2

        // Discriminant is negative -> triggers quintic Hermite smootherstep: 6*tau^5 - 15*tau^4 + 10*tau^3
        XCTAssertEqual(interpolator.solve_kinematic_progress(0.0, compressedDur, distance, 1.15, 1.25), 0.0, accuracy: 1e-6)
        XCTAssertEqual(interpolator.solve_kinematic_progress(compressedDur, compressedDur, distance, 1.15, 1.25), 1.0, accuracy: 1e-6)

        // At midpoint tau = 0.5, lambda should be exactly 0.5
        let midLambda = interpolator.solve_kinematic_progress(10.0, compressedDur, distance, 1.15, 1.25)
        XCTAssertEqual(midLambda, 0.5, accuracy: 1e-6)

        // Analytical smootherstep values at tau = 0.2
        // tau^3 * (10 + tau*(-15 + 6*tau)) = 0.008 * (10 + 0.2*(-13.8)) = 0.008 * 7.24 = 0.05792
        let lambda02 = interpolator.solve_kinematic_progress(4.0, compressedDur, distance, 1.15, 1.25)
        XCTAssertEqual(lambda02, 0.05792, accuracy: 1e-5)

        // Strict monotonicity
        var prev: Double = -1.0
        for sec in stride(from: 0.0, through: compressedDur, by: 1.0) {
            let lambda = interpolator.solve_kinematic_progress(sec, compressedDur, distance, 1.15, 1.25)
            XCTAssertGreaterThanOrEqual(lambda, prev)
            prev = lambda
        }
    }

    // MARK: - 6. Terminal Origin Dwell Suppression & Anti-Ghost Movement

    func testTerminalOriginDwellSuppression() {
        let pts = [
            Point2D(0.0, 0.0),
            Point2D(1000.0, 0.0)
        ]
        let interpolator = makeInterpolator(points: pts)

        let depTime: Double = 10000.0
        let arrTime: Double = 10100.0
        let feedTime: Double = 10020.0

        // Case A: Assigned train at origin terminal (seq <= 1, STOPPED_AT), dwelling normally (dwell <= 120s)
        let telemNormal = IngestedTelemetry(
            std.string("TRIP_001"),
            std.string("1"),
            1, // stop sequence 1 = origin
            std.string("101N"),
            GTFSVehicleStatus.STOPPED_AT,
            true, // is_assigned
            depTime,
            arrTime,
            feedTime,
            0.0, // origin platform dist
            1000.0 // target platform dist
        )

        let nowNormal: Double = 10040.0 // 40s past scheduled departure (<= 120s)
        let estimateNormal = interpolator.update(telemNormal, nowNormal)

        XCTAssertEqual(estimateNormal.linear_progress, 0.0, accuracy: 1e-6)
        XCTAssertEqual(estimateNormal.coordinates.x, 0.0, accuracy: 1e-6)
        XCTAssertEqual(estimateNormal.visual_state, VisualState.BOARDING_TERMINAL)
        XCTAssertFalse(estimateNormal.is_holding)

        // Case B: Origin terminal train delayed > 120s -> Transitions to HOLDING_STATION
        let nowDelayed: Double = 10130.0 // 130s past scheduled departure (> 120s)
        let estimateDelayed = interpolator.update(telemNormal, nowDelayed)

        XCTAssertEqual(estimateDelayed.linear_progress, 0.0, accuracy: 1e-6)
        XCTAssertEqual(estimateDelayed.visual_state, VisualState.HOLDING_STATION)
        XCTAssertTrue(estimateDelayed.is_holding)
    }

    // MARK: - 7. Intermediate Station Platform Dwell

    func testIntermediateStationDwell() {
        let pts = [
            Point2D(0.0, 0.0),
            Point2D(500.0, 0.0),
            Point2D(1000.0, 0.0)
        ]
        let interpolator = makeInterpolator(points: pts)

        let depTime: Double = 10000.0
        let arrTime: Double = 10080.0
        let feedTime: Double = 10010.0

        let telemIntermediate = IngestedTelemetry(
            std.string("TRIP_002"),
            std.string("6"),
            5, // sequence 5 = intermediate station
            std.string("628N"),
            GTFSVehicleStatus.STOPPED_AT,
            true,
            depTime,
            arrTime,
            feedTime,
            500.0, // origin platform dist
            1000.0 // target platform dist
        )

        // Normal dwell (within 120s)
        let estimateNormal = interpolator.update(telemIntermediate, 10030.0)
        XCTAssertEqual(estimateNormal.linear_progress, 0.0, accuracy: 1e-6)
        XCTAssertEqual(estimateNormal.coordinates.x, 500.0, accuracy: 1e-6)
        XCTAssertEqual(estimateNormal.visual_state, VisualState.STOPPED_IN_STATION)
        XCTAssertFalse(estimateNormal.is_holding)

        // Delayed station dwell (> 120s)
        let estimateHeld = interpolator.update(telemIntermediate, 10125.0)
        XCTAssertEqual(estimateHeld.linear_progress, 0.0, accuracy: 1e-6)
        XCTAssertEqual(estimateHeld.visual_state, VisualState.HOLDING_STATION)
        XCTAssertTrue(estimateHeld.is_holding)
    }

    // MARK: - 8. Status-Dependent Boundary Clamping & Approach Circuit

    func testStatusDependentBoundaryClamping() {
        let pts = [
            Point2D(0.0, 0.0),
            Point2D(1000.0, 0.0)
        ]
        let interpolator = makeInterpolator(points: pts)

        let depTime: Double = 10000.0
        let arrTime: Double = 10060.0
        let feedTime: Double = 10050.0

        // Train IN_TRANSIT_TO but kinematic model would place it near 0.95 progress
        let telemInTransit = IngestedTelemetry(
            std.string("TRIP_003"),
            std.string("4"),
            3,
            std.string("412N"),
            GTFSVehicleStatus.IN_TRANSIT_TO,
            true,
            depTime,
            arrTime,
            feedTime,
            0.0,
            1000.0
        )

        let nowNearArrival: Double = 10058.0 // 58s into a 60s run
        let estimateInTransit = interpolator.update(telemInTransit, nowNearArrival)

        // IN_TRANSIT_TO must clamp to approach_progress_ceiling (0.85)
        XCTAssertEqual(estimateInTransit.linear_progress, SubwayPositionInterpolator.approach_progress_ceiling(), accuracy: 1e-6)
        XCTAssertEqual(estimateInTransit.coordinates.x, 850.0, accuracy: 1e-6)
        XCTAssertEqual(estimateInTransit.visual_state, VisualState.APPROACHING_STATION)
        XCTAssertFalse(estimateInTransit.is_holding)

        // When wayside reports INCOMING_AT, clamp opens to [0.85, 0.995]
        let telemIncoming = IngestedTelemetry(
            std.string("TRIP_003"),
            std.string("4"),
            3,
            std.string("412N"),
            GTFSVehicleStatus.INCOMING_AT,
            true,
            depTime,
            arrTime,
            feedTime,
            0.0,
            1000.0
        )

        let estimateIncoming = interpolator.update(telemIncoming, nowNearArrival)
        XCTAssertGreaterThan(estimateIncoming.linear_progress, 0.85)
        XCTAssertLessThanOrEqual(estimateIncoming.linear_progress, 0.995)
        XCTAssertEqual(estimateIncoming.visual_state, VisualState.APPROACHING_STATION)
        XCTAssertFalse(estimateIncoming.is_holding)
    }

    // MARK: - 9. Mid-Tunnel Signal Stop & Telemetry Stale Dropout

    func testMidTunnelSignalHoldAndTelemetryStale() {
        let pts = [
            Point2D(0.0, 0.0),
            Point2D(1000.0, 0.0)
        ]
        let interpolator = makeInterpolator(points: pts)

        let depTime: Double = 10000.0
        let arrTime: Double = 10060.0 // 60s expected transit

        // Case A: Elapsed time exceeds total + 30s (now = 10095s) -> Clamped at 0.85 with HOLDING_MID_TUNNEL
        let telemTunnelHold = IngestedTelemetry(
            std.string("TRIP_004"),
            std.string("A"),
            2,
            std.string("A15N"),
            GTFSVehicleStatus.IN_TRANSIT_TO,
            true,
            depTime,
            arrTime,
            10050.0, // feed is fresh
            0.0,
            1000.0
        )

        let estimateTunnelHold = interpolator.update(telemTunnelHold, 10095.0)
        XCTAssertEqual(estimateTunnelHold.linear_progress, SubwayPositionInterpolator.approach_progress_ceiling(), accuracy: 1e-6)
        XCTAssertEqual(estimateTunnelHold.visual_state, VisualState.HOLDING_MID_TUNNEL)
        XCTAssertTrue(estimateTunnelHold.is_holding)

        // Case B: Feed staleness > 90s -> Clamped with TELEMETRY_STALE
        let telemStale = IngestedTelemetry(
            std.string("TRIP_004"),
            std.string("A"),
            2,
            std.string("A15N"),
            GTFSVehicleStatus.IN_TRANSIT_TO,
            true,
            depTime,
            arrTime,
            10000.0, // feed timestamp 10000
            0.0,
            1000.0
        )

        let nowStale: Double = 10095.0 // feed age = 95s (> 90s)
        let estimateStale = interpolator.update(telemStale, nowStale)
        XCTAssertEqual(estimateStale.linear_progress, SubwayPositionInterpolator.approach_progress_ceiling(), accuracy: 1e-6)
        XCTAssertEqual(estimateStale.visual_state, VisualState.TELEMETRY_STALE)
        XCTAssertTrue(estimateStale.is_holding)
    }

    // MARK: - 10. Heading & Bearing Orientation

    func testHeadingAndBearingOrientation() {
        // Polyline making a square:
        // (0, 0) -> (100, 0) East
        // (100, 0) -> (100, 100) North
        // (100, 100) -> (0, 100) West
        // (0, 100) -> (0, 0) South
        let pts = [
            Point2D(0.0, 0.0),
            Point2D(100.0, 0.0),
            Point2D(100.0, 100.0),
            Point2D(0.0, 100.0),
            Point2D(0.0, 0.0)
        ]
        let interpolator = makeInterpolator(points: pts)

        // Eastbound (50m) -> 90 degrees
        var hEast: Double = 0.0
        _ = interpolator.interpolate_point_at_distance(50.0, &hEast)
        XCTAssertEqual(hEast, .pi / 2.0, accuracy: 1e-6)

        // Northbound (150m) -> 0 degrees
        var hNorth: Double = 0.0
        _ = interpolator.interpolate_point_at_distance(150.0, &hNorth)
        XCTAssertEqual(hNorth, 0.0, accuracy: 1e-6)

        // Westbound (250m) -> -pi/2 radians
        var hWest: Double = 0.0
        _ = interpolator.interpolate_point_at_distance(250.0, &hWest)
        XCTAssertEqual(hWest, -.pi / 2.0, accuracy: 1e-6)

        // Southbound (350m) -> pi radians (180 degrees)
        var hSouth: Double = 0.0
        _ = interpolator.interpolate_point_at_distance(350.0, &hSouth)
        XCTAssertEqual(abs(hSouth), .pi, accuracy: 1e-6)
    }

    // MARK: - 11. Geographic Shape Construction & Tracking

    func testGeographicShapeConstructionAndTracking() {
        // Synthetic line from Brooklyn Bridge-City Hall (40.7130, -74.0040)
        // to Canal St (40.7188, -74.0018) along Lexington line
        var coords: [GeoCoordinate] = []
        coords.append(GeoCoordinate(40.7130, -74.0040))
        coords.append(GeoCoordinate(40.7188, -74.0018))

        let interpolator = makeGeographicInterpolator(coords: coords)

        XCTAssertEqual(interpolator.vertex_count(), 2)
        XCTAssertGreaterThan(interpolator.total_shape_distance(), 600.0)

        let totalDist = interpolator.total_shape_distance()

        // Test telemetry run along the geographic track
        let telem = IngestedTelemetry(
            std.string("TRIP_GEO"),
            std.string("6"),
            1,
            std.string("635N"),
            GTFSVehicleStatus.IN_TRANSIT_TO,
            true,
            1000.0,
            1060.0,
            1030.0,
            0.0,
            totalDist
        )

        let estimate = interpolator.update(telem, 1030.0) // 50% through run
        XCTAssertEqual(estimate.visual_state, VisualState.TRANSITING_NOMINAL)
        XCTAssertGreaterThan(estimate.latitude, 40.7130)
        XCTAssertLessThan(estimate.latitude, 40.7188)
        XCTAssertGreaterThan(estimate.longitude, -74.0040)
        XCTAssertLessThan(estimate.longitude, -74.0018)
        XCTAssertGreaterThan(estimate.heading_degrees, 0.0)
        XCTAssertLessThan(estimate.heading_degrees, 45.0)
    }

    // MARK: - 12. Degenerate Geometry Safety

    func testDegenerateGeometrySafety() {
        // Empty geometry
        let emptyInterp = SubwayPositionInterpolator()
        XCTAssertEqual(emptyInterp.total_shape_distance(), 0.0)
        XCTAssertEqual(emptyInterp.vertex_count(), 0)

        var emptyHeading: Double = 0.0
        let emptyPt = emptyInterp.interpolate_point_at_distance(100.0, &emptyHeading)
        XCTAssertEqual(emptyPt.x, 0.0)
        XCTAssertEqual(emptyPt.y, 0.0)
        XCTAssertEqual(emptyHeading, 0.0)

        // Single-point geometry
        let singlePt = [Point2D(42.0, 84.0)]
        let singleInterp = makeInterpolator(points: singlePt)
        XCTAssertEqual(singleInterp.total_shape_distance(), 0.0)
        XCTAssertEqual(singleInterp.vertex_count(), 1)

        var singleHeading: Double = 0.0
        let resPt = singleInterp.interpolate_point_at_distance(50.0, &singleHeading)
        XCTAssertEqual(resPt.x, 42.0)
        XCTAssertEqual(resPt.y, 84.0)

        // Inter-station distance <= 0
        let pts = [Point2D(0.0, 0.0), Point2D(100.0, 0.0)]
        let interp = makeInterpolator(points: pts)
        let telemZeroDist = IngestedTelemetry(
            std.string("ZERO"),
            std.string("1"),
            1,
            std.string("STOP"),
            GTFSVehicleStatus.IN_TRANSIT_TO,
            true,
            100.0,
            150.0,
            120.0,
            50.0,
            50.0 // target == origin
        )
        let estZero = interp.update(telemZeroDist, 120.0)
        XCTAssertEqual(estZero.linear_progress, 0.0)
        XCTAssertEqual(estZero.visual_state, VisualState.STOPPED_IN_STATION)
    }
}
