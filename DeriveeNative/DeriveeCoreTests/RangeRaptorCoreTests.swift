import XCTest
import CxxStdlib
@testable import DeriveeCore

final class RangeRaptorCoreTests: XCTestCase {

    // Helper to build synthetic MasterHeader aligned timetable buffer with optional Section 7
    private func buildSyntheticTimetable(
        stops: [Stop],
        routes: [Route],
        trips: [Trip],
        stopTimes: [StopTime],
        transfers: [Transfer],
        stopRoutes: [UInt32],
        routeStops: [UInt32],
        stochasticWeights: [StochasticWeight] = []
    ) -> Data {
        func align64(_ offset: Int) -> Int {
            let rem = offset % 64
            return rem == 0 ? offset : offset + (64 - rem)
        }

        let headerSize = 232
        let lenS0 = stops.count * MemoryLayout<Stop>.size
        let lenS1 = routes.count * MemoryLayout<Route>.size
        let lenS2 = trips.count * MemoryLayout<Trip>.size
        let lenS3 = stopTimes.count * MemoryLayout<StopTime>.size
        let lenS4 = transfers.count * MemoryLayout<Transfer>.size
        let lenS5 = stopRoutes.count * MemoryLayout<UInt32>.size
        let lenS6 = routeStops.count * MemoryLayout<UInt32>.size
        let lenS7 = stochasticWeights.count * MemoryLayout<StochasticWeight>.size

        let offS0 = align64(headerSize)
        let offS1 = align64(offS0 + lenS0)
        let offS2 = align64(offS1 + lenS1)
        let offS3 = align64(offS2 + lenS2)
        let offS4 = align64(offS3 + lenS3)
        let offS5 = align64(offS4 + lenS4)
        let offS6 = align64(offS5 + lenS5)
        let offS7 = align64(offS6 + lenS6)
        let totalSize = align64(offS7 + lenS7)

        var data = Data(count: totalSize)

        data.withUnsafeMutableBytes { rawBuf in
            let ptr = rawBuf.baseAddress!

            // MasterHeader
            ptr.storeBytes(of: UInt32(0x31565244), toByteOffset: 0, as: UInt32.self) // MAGIC_TIMETABLE
            ptr.storeBytes(of: UInt32(1), toByteOffset: 4, as: UInt32.self)          // schema_version
            ptr.storeBytes(of: UInt32(0x01020304), toByteOffset: 8, as: UInt32.self) // endian_marker
            ptr.storeBytes(of: UInt32(232), toByteOffset: 12, as: UInt32.self)       // header_size
            ptr.storeBytes(of: UInt64(totalSize), toByteOffset: 16, as: UInt64.self) // file_size
            ptr.storeBytes(of: UInt64(0), toByteOffset: 24, as: UInt64.self)         // checksum
            let numSections = stochasticWeights.isEmpty ? 7 : 8
            ptr.storeBytes(of: UInt32(numSections), toByteOffset: 32, as: UInt32.self)
            ptr.storeBytes(of: UInt32(0), toByteOffset: 36, as: UInt32.self)         // flags

            // TOC entries
            func writeTOC(index: Int, offset: Int, size: Int, count: Int) {
                let tocBase = 40 + index * 24
                ptr.storeBytes(of: UInt64(offset), toByteOffset: tocBase, as: UInt64.self)
                ptr.storeBytes(of: UInt64(size), toByteOffset: tocBase + 8, as: UInt64.self)
                ptr.storeBytes(of: UInt64(count), toByteOffset: tocBase + 16, as: UInt64.self)
            }

            writeTOC(index: 0, offset: offS0, size: lenS0, count: stops.count)
            writeTOC(index: 1, offset: offS1, size: lenS1, count: routes.count)
            writeTOC(index: 2, offset: offS2, size: lenS2, count: trips.count)
            writeTOC(index: 3, offset: offS3, size: lenS3, count: stopTimes.count)
            writeTOC(index: 4, offset: offS4, size: lenS4, count: transfers.count)
            writeTOC(index: 5, offset: offS5, size: lenS5, count: stopRoutes.count)
            writeTOC(index: 6, offset: offS6, size: lenS6, count: routeStops.count)
            if !stochasticWeights.isEmpty {
                writeTOC(index: 7, offset: offS7, size: lenS7, count: stochasticWeights.count)
            }

            for (i, s) in stops.enumerated() {
                ptr.storeBytes(of: s, toByteOffset: offS0 + i * MemoryLayout<Stop>.size, as: Stop.self)
            }
            for (i, r) in routes.enumerated() {
                ptr.storeBytes(of: r, toByteOffset: offS1 + i * MemoryLayout<Route>.size, as: Route.self)
            }
            for (i, t) in trips.enumerated() {
                ptr.storeBytes(of: t, toByteOffset: offS2 + i * MemoryLayout<Trip>.size, as: Trip.self)
            }
            for (i, st) in stopTimes.enumerated() {
                ptr.storeBytes(of: st, toByteOffset: offS3 + i * MemoryLayout<StopTime>.size, as: StopTime.self)
            }
            for (i, tr) in transfers.enumerated() {
                ptr.storeBytes(of: tr, toByteOffset: offS4 + i * MemoryLayout<Transfer>.size, as: Transfer.self)
            }
            for (i, sr) in stopRoutes.enumerated() {
                ptr.storeBytes(of: sr, toByteOffset: offS5 + i * MemoryLayout<UInt32>.size, as: UInt32.self)
            }
            for (i, rs) in routeStops.enumerated() {
                ptr.storeBytes(of: rs, toByteOffset: offS6 + i * MemoryLayout<UInt32>.size, as: UInt32.self)
            }
            for (i, sw) in stochasticWeights.enumerated() {
                ptr.storeBytes(of: sw, toByteOffset: offS7 + i * MemoryLayout<StochasticWeight>.size, as: StochasticWeight.self)
            }
        }
        return data
    }

    // 1. Continuous Range-RAPTOR sweep across 60-minute window
    func testRangeRaptor60MinuteWindowSweep() {
        let stops = [
            Stop(40.71, -74.00, 0, 0, 1, 0), // Stop 0 (Origin)
            Stop(40.75, -74.00, 1, 0, 1, 0)  // Stop 1 (Destination)
        ]
        let routes = [Route(0, 0, 4, 2)] // 4 scheduled trips on Route 0
        let trips = [
            Trip(0, 2, 1), // Trip 0: 08:00 -> 08:20
            Trip(2, 2, 1), // Trip 1: 08:15 -> 08:35
            Trip(4, 2, 1), // Trip 2: 08:30 -> 08:50
            Trip(6, 2, 1)  // Trip 3: 08:55 -> 09:15
        ]
        let stopTimes = [
            // Trip 0
            StopTime(28800, 28800, 0), StopTime(30000, 30000, 1),
            // Trip 1
            StopTime(29700, 29700, 0), StopTime(30900, 30900, 1),
            // Trip 2
            StopTime(30600, 30600, 0), StopTime(31800, 31800, 1),
            // Trip 3
            StopTime(32100, 32100, 0), StopTime(33300, 33300, 1)
        ]
        let stopRoutes: [UInt32] = [0, 0]
        let routeStops: [UInt32] = [0, 1]

        let blob = buildSyntheticTimetable(
            stops: stops, routes: routes, trips: trips,
            stopTimes: stopTimes, transfers: [],
            stopRoutes: stopRoutes, routeStops: routeStops
        )

        var engine = RaptorEngine()
        _ = blob.withUnsafeBytes { raw in
            engine.load_timetable_blob(raw.baseAddress?.assumingMemoryBound(to: UInt8.self), raw.count)
        }

        // Query Range: 08:00 (28800) to 09:00 (32400)
        let rangeParams = RangeQueryParams(0, 1, 28800, 32400, 4, 0)
        let paretoSet = engine.compute_range_journeys(rangeParams)

        // All 4 trips depart within [28800, 32400], and each has earlier arrival for later departure
        // (they are all Pareto optimal departure alternatives for different user ready times)
        XCTAssertEqual(paretoSet.size(), 4)

        // Verify journeys in ParetoSet
        let journeys = paretoSet.get_journeys()
        XCTAssertEqual(journeys.size(), 4)
    }

    // 2. Local vs Express Trade-Off (Dominance & Alternative Discovery)
    func testRangeRaptorLocalVsExpressTradeOff() {
        let stops = [
            Stop(40.71, -74.00, 0, 0, 2, 0), // Stop 0 (Origin): routes_offset = 0, route_count = 2 (Routes 0, 1)
            Stop(40.73, -74.00, 2, 0, 1, 0), // Stop 1 (Intermediate): routes_offset = 2, route_count = 1 (Route 0)
            Stop(40.75, -74.00, 3, 0, 2, 0)  // Stop 2 (Destination): routes_offset = 3, route_count = 2 (Routes 0, 1)
        ]
        let routes = [
            Route(0, 0, 1, 3), // Route 0: Local (0 -> 1 -> 2), trips_offset = 0, route_stops_offset = 0
            Route(1, 3, 1, 2)  // Route 1: Express (0 -> 2), trips_offset = 1, route_stops_offset = 3
        ]
        let trips = [
            Trip(0, 3, 1), // Local Trip: Dep 08:00 (28800) -> Arr Stop 2 at 08:25 (30300)
            Trip(3, 2, 1)  // Express Trip: Dep 08:10 (29400) -> Arr Stop 2 at 08:20 (30000)
        ]
        let stopTimes = [
            // Local
            StopTime(28800, 28800, 0),
            StopTime(29400, 29400, 1),
            StopTime(30300, 30300, 2),
            // Express
            StopTime(29400, 29400, 0),
            StopTime(30000, 30000, 2)
        ]
        let stopRoutes: [UInt32] = [0, 1, 0, 0, 1]
        let routeStops: [UInt32] = [0, 1, 2, 0, 2]

        let blob = buildSyntheticTimetable(
            stops: stops, routes: routes, trips: trips,
            stopTimes: stopTimes, transfers: [],
            stopRoutes: stopRoutes, routeStops: routeStops
        )

        var engine = RaptorEngine()
        _ = blob.withUnsafeBytes { raw in
            engine.load_timetable_blob(raw.baseAddress?.assumingMemoryBound(to: UInt8.self), raw.count)
        }

        // At departure time 08:00 (28800):
        // Express departs later (08:10) but arrives earlier (08:20 vs 08:25),
        // so single query at 08:00 picks the Express train.
        let singleQuery = engine.compute_journey(QueryParams(0, 2, 28800, 2))
        XCTAssertEqual(singleQuery.size(), 1)
        XCTAssertEqual(singleQuery[0].route_id, 1) // Express
        XCTAssertEqual(singleQuery[0].arrival_time, 30000)

        // Range query [28800, 29400] also discovers Express as dominant
        let rangeParams = RangeQueryParams(0, 2, 28800, 29400, 2, 0)
        let paretoSet = engine.compute_range_journeys(rangeParams)
        XCTAssertEqual(paretoSet.size(), 1)
        XCTAssertEqual(paretoSet[0].cost.arrival_time_sec, 30000)
    }

    // 3. Quadratic Layover Connection Risk Penalty Scoring
    func testQuadraticLayoverPenaltyScoring() {
        let engine = RaptorEngine()

        // Comfortable connection: 5 min (300s) slack >= 180s ideal buffer
        let segComfortable1 = JourneySegment(0, 1, 100, 28800, 29100, 1, 0)
        let segComfortable2 = JourneySegment(1, 2, 101, 29400, 29700, 2, 0) // 29400 - 29100 = 300s slack
        let penaltyComfortable = engine.calculate_layover_penalty([segComfortable1, segComfortable2])
        XCTAssertEqual(penaltyComfortable, 0, "Comfortable transfer >= 180s should have 0 penalty")

        // Tight connection: 1 min (60s) slack < 180s ideal buffer (deficit = 120s)
        // Penalty = ceil(0.001 * 120^2) = ceil(0.001 * 14400) = 15
        let segTight1 = JourneySegment(0, 1, 100, 28800, 29100, 1, 0)
        let segTight2 = JourneySegment(1, 2, 101, 29160, 29500, 2, 0) // 29160 - 29100 = 60s slack
        let penaltyTight = engine.calculate_layover_penalty([segTight1, segTight2])
        XCTAssertEqual(penaltyTight, 15, "Tight connection (60s slack) should yield quadratic penalty of 15")

        // 0s transfer sprint: deficit = 180s -> ceil(0.001 * 32400) = 33
        let segZeroSlack1 = JourneySegment(0, 1, 100, 28800, 29100, 1, 0)
        let segZeroSlack2 = JourneySegment(1, 2, 101, 29100, 29400, 2, 0)
        let penaltyZeroSlack = engine.calculate_layover_penalty([segZeroSlack1, segZeroSlack2])
        XCTAssertEqual(penaltyZeroSlack, 33)
    }

    // 4. Probabilistic Frequency Expected Wait Time (Osuna-Newell Formula)
    func testProbabilisticFrequencyWaitTimeCalculation() {
        // High frequency line: headway h = 300s (5m), variance = 0 (perfect regularity)
        // E[wait] = 300 / 2 = 150s (2.5m)
        let waitRegular = RaptorEngine.calculate_probabilistic_wait_time(300, 0)
        XCTAssertEqual(waitRegular, 150)

        // Headway h = 600s (10m), variance sigma^2 = 36000 (irregular/bunched)
        // E[wait] = 600 / 2 + 36000 / (2 * 600) = 300 + 30 = 330s
        let waitBunched = RaptorEngine.calculate_probabilistic_wait_time(600, 36000)
        XCTAssertEqual(waitBunched, 330)
    }

    // 5. Section 7 Stochastic Weights Table Integration
    func testStochasticWeightsSection7Integration() {
        let stops = [
            Stop(40.71, -74.00, 0, 0, 1, 0),
            Stop(40.75, -74.00, 1, 0, 1, 0)
        ]
        let routes = [Route(0, 0, 1, 2)]
        let trips = [Trip(0, 2, 1)]
        let stopTimes = [
            StopTime(28800, 28800, 0),
            StopTime(29400, 29400, 1)
        ]
        let stopRoutes: [UInt32] = [0, 0]
        let routeStops: [UInt32] = [0, 1]

        // Section 7 stochastic weights (e.g. Stop 0 has expected wait 180s, variance penalty 45)
        let stochasticWeights = [
            StochasticWeight(180, 45),
            StochasticWeight(200, 30)
        ]

        let blob = buildSyntheticTimetable(
            stops: stops, routes: routes, trips: trips,
            stopTimes: stopTimes, transfers: [],
            stopRoutes: stopRoutes, routeStops: routeStops,
            stochasticWeights: stochasticWeights
        )

        var engine = RaptorEngine()
        let loaded = blob.withUnsafeBytes { raw in
            engine.load_timetable_blob(raw.baseAddress?.assumingMemoryBound(to: UInt8.self), raw.count)
        }
        XCTAssertTrue(loaded)

        let rangeParams = RangeQueryParams(0, 1, 28800, 28800, 2, 0)
        let paretoSet = engine.compute_range_journeys(rangeParams)
        XCTAssertEqual(paretoSet.size(), 1)

        // Variance disutility should incorporate Section 7 variance penalty (45)
        let journey = paretoSet[0]
        XCTAssertEqual(journey.cost.variance_disutility, 45)
    }

    // 6. Dynamic Disruption Route Segment & Stop Pruning in Range-RAPTOR
    func testRangeRaptorWithDisruptions() {
        let stops = [
            Stop(40.71, -74.00, 0, 0, 2, 0), // Stop 0: routes_offset = 0, route_count = 2 (Routes 0, 1)
            Stop(40.73, -74.00, 2, 0, 1, 0), // Stop 1: routes_offset = 2, route_count = 1 (Route 0)
            Stop(40.75, -74.00, 3, 0, 2, 0)  // Stop 2: routes_offset = 3, route_count = 2 (Routes 0, 1)
        ]
        let routes = [
            Route(0, 0, 2, 3), // Route 0: trips_offset = 0, route_stops_offset = 0, trip_count = 2, stop_count = 3
            Route(2, 3, 2, 2)  // Route 1: trips_offset = 2, route_stops_offset = 3, trip_count = 2, stop_count = 2
        ]
        let trips = [
            // Route 0 trips (faster when open)
            Trip(0, 3, 1),
            Trip(3, 3, 1),
            // Route 1 trips (slower alternative)
            Trip(6, 2, 1),
            Trip(8, 2, 1)
        ]
        let stopTimes = [
            // Route 0 Trip 0: 08:00 -> 08:15
            StopTime(28800, 28800, 0), StopTime(29100, 29100, 1), StopTime(29700, 29700, 2),
            // Route 0 Trip 1: 08:30 -> 08:45
            StopTime(30600, 30600, 0), StopTime(30900, 30900, 1), StopTime(31500, 31500, 2),
            // Route 1 Trip 0: 08:05 -> 08:25
            StopTime(29100, 29100, 0), StopTime(30300, 30300, 2),
            // Route 1 Trip 1: 08:35 -> 08:55
            StopTime(30900, 30900, 0), StopTime(32100, 32100, 2)
        ]
        let stopRoutes: [UInt32] = [0, 1, 0, 0, 1]
        let routeStops: [UInt32] = [0, 1, 2, 0, 2]

        let blob = buildSyntheticTimetable(
            stops: stops, routes: routes, trips: trips,
            stopTimes: stopTimes, transfers: [],
            stopRoutes: stopRoutes, routeStops: routeStops
        )

        var engine = RaptorEngine()
        _ = blob.withUnsafeBytes { raw in
            engine.load_timetable_blob(raw.baseAddress?.assumingMemoryBound(to: UInt8.self), raw.count)
        }

        // Disrupt intermediate Stop 1 on Route 0
        engine.set_stop_disrupted(1, true)

        let rangeParams = RangeQueryParams(0, 2, 28800, 31000, 2, 0)
        let paretoSet = engine.compute_range_journeys(rangeParams)

        // Should automatically fall back to Route 1 bypass trips
        XCTAssertEqual(paretoSet.size(), 2)
        for i in 0..<paretoSet.size() {
            let j = paretoSet[i]
            XCTAssertEqual(j.segments[0].route_id, 1, "Must route via alternative Route 1")
        }
    }
}
