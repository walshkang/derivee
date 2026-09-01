import XCTest
import CxxStdlib
@testable import DeriveeCore

final class RaptorCoreTests: XCTestCase {

    // Helper: Build binary MasterHeader aligned byte buffer for synthetic timetable
    private func buildSyntheticTimetable(
        stops: [Stop],
        routes: [Route],
        trips: [Trip],
        stopTimes: [StopTime],
        transfers: [Transfer],
        stopRoutes: [UInt32],
        routeStops: [UInt32]
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
        let lenS7 = 0

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

        // Populate MasterHeader
        data.withUnsafeMutableBytes { rawBuf in
            let ptr = rawBuf.baseAddress!

            // MasterHeader fixed fields
            ptr.storeBytes(of: UInt32(0x31565244), toByteOffset: 0, as: UInt32.self) // MAGIC_TIMETABLE
            ptr.storeBytes(of: UInt32(1), toByteOffset: 4, as: UInt32.self)          // schema_version
            ptr.storeBytes(of: UInt32(0x01020304), toByteOffset: 8, as: UInt32.self) // endian_marker
            ptr.storeBytes(of: UInt32(232), toByteOffset: 12, as: UInt32.self)       // header_size
            ptr.storeBytes(of: UInt64(totalSize), toByteOffset: 16, as: UInt64.self) // file_size
            ptr.storeBytes(of: UInt64(0), toByteOffset: 24, as: UInt64.self)         // checksum
            ptr.storeBytes(of: UInt32(7), toByteOffset: 32, as: UInt32.self)         // num_sections
            ptr.storeBytes(of: UInt32(0), toByteOffset: 36, as: UInt32.self)         // flags

            // TOC entries (24B each)
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

            // Section 0: Stops
            for (i, s) in stops.enumerated() {
                ptr.storeBytes(of: s, toByteOffset: offS0 + i * MemoryLayout<Stop>.size, as: Stop.self)
            }

            // Section 1: Routes
            for (i, r) in routes.enumerated() {
                ptr.storeBytes(of: r, toByteOffset: offS1 + i * MemoryLayout<Route>.size, as: Route.self)
            }

            // Section 2: Trips
            for (i, t) in trips.enumerated() {
                ptr.storeBytes(of: t, toByteOffset: offS2 + i * MemoryLayout<Trip>.size, as: Trip.self)
            }

            // Section 3: StopTimes
            for (i, st) in stopTimes.enumerated() {
                ptr.storeBytes(of: st, toByteOffset: offS3 + i * MemoryLayout<StopTime>.size, as: StopTime.self)
            }

            // Section 4: Transfers
            for (i, tr) in transfers.enumerated() {
                ptr.storeBytes(of: tr, toByteOffset: offS4 + i * MemoryLayout<Transfer>.size, as: Transfer.self)
            }

            // Section 5: StopRoutes
            for (i, sr) in stopRoutes.enumerated() {
                ptr.storeBytes(of: sr, toByteOffset: offS5 + i * MemoryLayout<UInt32>.size, as: UInt32.self)
            }

            // Section 6: RouteStops
            for (i, rs) in routeStops.enumerated() {
                ptr.storeBytes(of: rs, toByteOffset: offS6 + i * MemoryLayout<UInt32>.size, as: UInt32.self)
            }
        }

        return data
    }

    // Helper: Build synthetic ULTRA CSR blob
    private func buildSyntheticUltraCsr(
        numStops: UInt32,
        indptr: [UInt64],
        targets: [UInt32],
        durations: [UInt16],
        flags: [UInt8] = []
    ) -> Data {
        var header = UltraCsrHeader()
        header.magic_bytes = 0x554C5452 // "ULTR"
        header.version = 1
        header.num_stops = numStops
        header.total_shortcuts = UInt64(targets.count)
        header.tau_max = 900

        let headerSize = MemoryLayout<UltraCsrHeader>.size // 32
        let indptrSize = indptr.count * MemoryLayout<UInt64>.size
        let targetsSize = targets.count * MemoryLayout<UInt32>.size
        let durationsSize = durations.count * MemoryLayout<UInt16>.size
        let flagsSize = flags.count * MemoryLayout<UInt8>.size

        var data = Data(count: headerSize + indptrSize + targetsSize + durationsSize + flagsSize)

        data.withUnsafeMutableBytes { rawBuf in
            let ptr = rawBuf.baseAddress!
            ptr.storeBytes(of: header, toByteOffset: 0, as: UltraCsrHeader.self)

            var offset = headerSize
            for val in indptr {
                ptr.storeBytes(of: val, toByteOffset: offset, as: UInt64.self)
                offset += MemoryLayout<UInt64>.size
            }
            for val in targets {
                ptr.storeBytes(of: val, toByteOffset: offset, as: UInt32.self)
                offset += MemoryLayout<UInt32>.size
            }
            for val in durations {
                ptr.storeBytes(of: val, toByteOffset: offset, as: UInt16.self)
                offset += MemoryLayout<UInt16>.size
            }
            for val in flags {
                ptr.storeBytes(of: val, toByteOffset: offset, as: UInt8.self)
                offset += MemoryLayout<UInt8>.size
            }
        }

        return data
    }

    // 1. Direct Single-Leg Journey (Origin -> Destination on same route)
    func testDirectSingleLegJourney() {
        // Stops: 0, 1, 2
        // Route 0: serves 0 -> 1 -> 2
        // Trip 0: 08:00 (28800) -> 08:05 (29100) -> 08:10 (29400)
        let stops = [
            Stop(40.71, -74.00, 0, 0, 1, 0), // Stop 0
            Stop(40.72, -74.00, 1, 0, 1, 0), // Stop 1
            Stop(40.73, -74.00, 2, 0, 1, 0)  // Stop 2
        ]
        let routes = [
            Route(0, 0, 1, 3) // Route 0: trips_off=0, stops_off=0, trip_cnt=1, stop_cnt=3
        ]
        let trips = [
            Trip(0, 3, 1) // Trip 0: stop_times_off=0, count=3, service=1
        ]
        let stopTimes = [
            StopTime(28800, 28800, 0), // Stop 0 dep 08:00:00
            StopTime(29100, 29100, 1), // Stop 1 arr/dep 08:05:00
            StopTime(29400, 29400, 2)  // Stop 2 arr 08:10:00
        ]
        let transfers: [Transfer] = []
        let stopRoutes: [UInt32] = [0, 0, 0]
        let routeStops: [UInt32] = [0, 1, 2]

        let blob = buildSyntheticTimetable(
            stops: stops, routes: routes, trips: trips,
            stopTimes: stopTimes, transfers: transfers,
            stopRoutes: stopRoutes, routeStops: routeStops
        )

        var engine = RaptorEngine()
        let loaded = blob.withUnsafeBytes { raw in
            engine.load_timetable_blob(raw.baseAddress?.assumingMemoryBound(to: UInt8.self), raw.count)
        }
        XCTAssertTrue(loaded)
        XCTAssertEqual(engine.stops_count(), 3)
        XCTAssertEqual(engine.routes_count(), 1)
        XCTAssertEqual(engine.trips_count(), 1)

        let params = QueryParams(0, 2, 28800, 4)
        let journeys = engine.compute_journey(params)

        XCTAssertEqual(journeys.size(), 1)
        let seg = journeys[0]
        XCTAssertEqual(seg.board_stop_id, 0)
        XCTAssertEqual(seg.exit_stop_id, 2)
        XCTAssertEqual(seg.departure_time, 28800)
        XCTAssertEqual(seg.arrival_time, 29400)
        XCTAssertEqual(seg.trip_id, 0)
        XCTAssertEqual(seg.route_id, 0)
    }

    // 2. Multi-Leg Journey with Transfer: Stop 0 -> Stop 1 (Route 0) -> Walk -> Stop 2 -> Stop 3 (Route 1)
    func testMultiLegJourneyWithTransfer() {
        let stops = [
            Stop(40.71, -74.00, 0, 0, 1, 0), // Stop 0 (serves Route 0)
            Stop(40.72, -74.00, 1, 0, 1, 1), // Stop 1 (serves Route 0, has transfer to Stop 2)
            Stop(40.72, -73.99, 2, 1, 1, 0), // Stop 2 (serves Route 1)
            Stop(40.73, -73.99, 3, 1, 1, 0)  // Stop 3 (serves Route 1)
        ]
        let routes = [
            Route(0, 0, 1, 2), // Route 0: Stop 0 -> Stop 1
            Route(1, 2, 1, 2)  // Route 1: Stop 2 -> Stop 3
        ]
        let trips = [
            Trip(0, 2, 1), // Trip 0 on Route 0
            Trip(2, 2, 1)  // Trip 1 on Route 1
        ]
        let stopTimes = [
            // Trip 0 (Route 0): 08:00 -> 08:05
            StopTime(28800, 28800, 0),
            StopTime(29100, 29100, 1),
            // Trip 1 (Route 1): 08:08 -> 08:15
            StopTime(29280, 29280, 2),
            StopTime(29700, 29700, 3)
        ]
        // Transfer from Stop 1 -> Stop 2 (duration 120s = 2 min, distance 150m)
        let transfers = [
            Transfer(2, 120, 150)
        ]
        let stopRoutes: [UInt32] = [0, 0, 1, 1]
        let routeStops: [UInt32] = [0, 1, 2, 3]

        let blob = buildSyntheticTimetable(
            stops: stops, routes: routes, trips: trips,
            stopTimes: stopTimes, transfers: transfers,
            stopRoutes: stopRoutes, routeStops: routeStops
        )

        var engine = RaptorEngine()
        let loaded = blob.withUnsafeBytes { raw in
            engine.load_timetable_blob(raw.baseAddress?.assumingMemoryBound(to: UInt8.self), raw.count)
        }
        XCTAssertTrue(loaded)

        let params = QueryParams(0, 3, 28800, 3)
        let journeys = engine.compute_journey(params)

        XCTAssertEqual(journeys.size(), 3, "Expected 3 segments: Route 0, Transfer, Route 1")

        // Segment 1: Route 0 (Stop 0 -> Stop 1)
        let seg1 = journeys[0]
        XCTAssertEqual(seg1.board_stop_id, 0)
        XCTAssertEqual(seg1.exit_stop_id, 1)
        XCTAssertEqual(seg1.departure_time, 28800)
        XCTAssertEqual(seg1.arrival_time, 29100)

        // Segment 2: Transfer (Stop 1 -> Stop 2)
        let seg2 = journeys[1]
        XCTAssertEqual(seg2.board_stop_id, 1)
        XCTAssertEqual(seg2.exit_stop_id, 2)
        XCTAssertEqual(seg2.departure_time, 29100)
        XCTAssertEqual(seg2.arrival_time, 29220) // 29100 + 120 = 29220 (08:07:00)
        XCTAssertEqual(seg2.trip_id, 0, "Transfer trip_id must be 0")

        // Segment 3: Route 1 (Stop 2 -> Stop 3)
        let seg3 = journeys[2]
        XCTAssertEqual(seg3.board_stop_id, 2)
        XCTAssertEqual(seg3.exit_stop_id, 3)
        XCTAssertEqual(seg3.departure_time, 29280) // Departs 08:08:00
        XCTAssertEqual(seg3.arrival_time, 29700)   // Arrives 08:15:00
    }

    // 3. Dynamic Disruption Stop Pruning: Disabled intermediate stop reroutes to alternate path
    func testDynamicDisruptionStopPruning() {
        // Stop 0 -> Path A: Stop 1 -> Stop 3 (Fast, Route 0)
        // Stop 0 -> Path B: Stop 2 -> Stop 3 (Slow, Route 1)
        let stops = [
            Stop(40.71, -74.00, 0, 0, 2, 0), // Stop 0 (Routes 0, 1)
            Stop(40.72, -74.00, 2, 0, 1, 0), // Stop 1 (Route 0)
            Stop(40.71, -73.99, 3, 0, 1, 0), // Stop 2 (Route 1)
            Stop(40.73, -74.00, 4, 0, 2, 0)  // Stop 3 (Routes 0, 1)
        ]
        let routes = [
            Route(0, 0, 1, 3), // Route 0: Stop 0 -> Stop 1 -> Stop 3
            Route(1, 3, 1, 3)  // Route 1: Stop 0 -> Stop 2 -> Stop 3
        ]
        let trips = [
            Trip(0, 3, 1), // Trip 0 on Route 0 (Fast)
            Trip(3, 3, 1)  // Trip 1 on Route 1 (Slow)
        ]
        let stopTimes = [
            // Fast Trip 0: 08:00 -> 08:05 (Stop 1) -> 08:10 (Stop 3)
            StopTime(28800, 28800, 0),
            StopTime(29100, 29100, 1),
            StopTime(29400, 29400, 3),
            // Slow Trip 1: 08:00 -> 08:10 (Stop 2) -> 08:20 (Stop 3)
            StopTime(28800, 28800, 0),
            StopTime(29400, 29400, 2),
            StopTime(30000, 30000, 3)
        ]
        let stopRoutes: [UInt32] = [0, 1, 0, 1, 0, 1]
        let routeStops: [UInt32] = [0, 1, 3, 0, 2, 3]

        let blob = buildSyntheticTimetable(
            stops: stops, routes: routes, trips: trips,
            stopTimes: stopTimes, transfers: [],
            stopRoutes: stopRoutes, routeStops: routeStops
        )

        var engine = RaptorEngine()
        _ = blob.withUnsafeBytes { raw in
            engine.load_timetable_blob(raw.baseAddress?.assumingMemoryBound(to: UInt8.self), raw.count)
        }

        // Before disruption: Should select fast Route 0 (arrives at 29400)
        let initialJourneys = engine.compute_journey(QueryParams(0, 3, 28800, 2))
        XCTAssertEqual(initialJourneys.size(), 1)
        XCTAssertEqual(initialJourneys[0].arrival_time, 29400)
        XCTAssertEqual(initialJourneys[0].route_id, 0)

        // Disrupt Stop 1 (on Route 0)
        engine.set_stop_disrupted(1, true)
        XCTAssertFalse(engine.is_stop_active(1))

        // After disruption: Engine must bypass Route 0 and select Route 1 (arrives at 30000)
        let disruptedJourneys = engine.compute_journey(QueryParams(0, 3, 28800, 2))
        XCTAssertEqual(disruptedJourneys.size(), 1)
        XCTAssertEqual(disruptedJourneys[0].arrival_time, 30000)
        XCTAssertEqual(disruptedJourneys[0].route_id, 1)

        // Restore Stop 1
        engine.set_stop_disrupted(1, false)
        XCTAssertTrue(engine.is_stop_active(1))

        let restoredJourneys = engine.compute_journey(QueryParams(0, 3, 28800, 2))
        XCTAssertEqual(restoredJourneys[0].arrival_time, 29400)
    }

    // 4. Dynamic Disruption Route Segment Pruning
    func testDynamicDisruptionRouteSegmentPruning() {
        let stops = [
            Stop(40.71, -74.00, 0, 0, 1, 0),
            Stop(40.72, -74.00, 1, 0, 1, 0),
            Stop(40.73, -74.00, 2, 0, 1, 0)
        ]
        let routes = [Route(0, 0, 1, 3)]
        let trips = [Trip(0, 3, 1)]
        let stopTimes = [
            StopTime(28800, 28800, 0),
            StopTime(29100, 29100, 1),
            StopTime(29400, 29400, 2)
        ]
        let stopRoutes: [UInt32] = [0, 0, 0]
        let routeStops: [UInt32] = [0, 1, 2]

        let blob = buildSyntheticTimetable(
            stops: stops, routes: routes, trips: trips,
            stopTimes: stopTimes, transfers: [],
            stopRoutes: stopRoutes, routeStops: routeStops
        )

        var engine = RaptorEngine()
        _ = blob.withUnsafeBytes { raw in
            engine.load_timetable_blob(raw.baseAddress?.assumingMemoryBound(to: UInt8.self), raw.count)
        }

        // Disrupt segment between Stop 0 and Stop 2 on Route 0
        engine.set_route_segment_disrupted(0, 0, 2, true)
        XCTAssertFalse(engine.is_route_segment_active(0, 0, 2))

        let journeys = engine.compute_journey(QueryParams(0, 2, 28800, 2))
        XCTAssertTrue(journeys.empty(), "Journey across disrupted segment should be pruned")

        // Clear disruptions
        engine.clear_disruptions()
        XCTAssertTrue(engine.is_route_segment_active(0, 0, 2))

        let journeysRestored = engine.compute_journey(QueryParams(0, 2, 28800, 2))
        XCTAssertFalse(journeysRestored.empty())
    }

    // 5. Real-Time Delay Rerouting
    func testRealtimeDelayRerouting() {
        let stops = [
            Stop(40.71, -74.00, 0, 0, 2, 0),
            Stop(40.73, -74.00, 2, 0, 2, 0)
        ]
        let routes = [
            Route(0, 0, 1, 2), // Route 0 (Express)
            Route(1, 2, 1, 2)  // Route 1 (Local)
        ]
        let trips = [
            Trip(0, 2, 1), // Trip 0: Dep 08:00, Arr 08:08
            Trip(2, 2, 1)  // Trip 1: Dep 08:02, Arr 08:12
        ]
        let stopTimes = [
            // Express: 28800 -> 29280
            StopTime(28800, 28800, 0),
            StopTime(29280, 29280, 1),
            // Local: 28920 -> 29520
            StopTime(28920, 28920, 0),
            StopTime(29520, 29520, 1)
        ]
        let stopRoutes: [UInt32] = [0, 1, 0, 1]
        let routeStops: [UInt32] = [0, 1, 0, 1]

        let blob = buildSyntheticTimetable(
            stops: stops, routes: routes, trips: trips,
            stopTimes: stopTimes, transfers: [],
            stopRoutes: stopRoutes, routeStops: routeStops
        )

        var engine = RaptorEngine()
        _ = blob.withUnsafeBytes { raw in
            engine.load_timetable_blob(raw.baseAddress?.assumingMemoryBound(to: UInt8.self), raw.count)
        }

        // Before delay: Express is faster (departs 28800, arrives 29280)
        let initial = engine.compute_journey(QueryParams(0, 1, 28800, 2))
        XCTAssertEqual(initial[0].trip_id, 0)
        XCTAssertEqual(initial[0].arrival_time, 29280)

        // Apply +15 min delay to Trip 0 (+900s) -> now departs 29700, arrives 30180
        engine.update_realtime_delay(0, 900)
        XCTAssertEqual(engine.get_realtime_delay(0), 900)

        // After delay: Local (Trip 1) departs earlier at 28920 and arrives earlier at 29520
        let afterDelay = engine.compute_journey(QueryParams(0, 1, 28800, 2))
        XCTAssertEqual(afterDelay[0].trip_id, 1)
        XCTAssertEqual(afterDelay[0].departure_time, 28920)
        XCTAssertEqual(afterDelay[0].arrival_time, 29520)
    }

    // 6. ULTRA CSR Transfer Relaxation and Wheelchair Filtering
    func testUltraCsrTransferRelaxationAndWheelchairFilter() {
        let stops = [
            Stop(40.71, -74.00, 0, 0, 1, 0), // Stop 0
            Stop(40.72, -74.00, 1, 0, 1, 0), // Stop 1
            Stop(40.72, -73.99, 2, 0, 1, 0), // Stop 2 (Accessible transfer target)
            Stop(40.72, -73.98, 3, 0, 1, 0)  // Stop 3 (Non-accessible transfer target)
        ]
        let routes = [Route(0, 0, 1, 2)]
        let trips = [Trip(0, 2, 1)]
        let stopTimes = [
            StopTime(28800, 28800, 0),
            StopTime(29100, 29100, 1)
        ]
        let stopRoutes: [UInt32] = [0, 0]
        let routeStops: [UInt32] = [0, 1]

        let timetableBlob = buildSyntheticTimetable(
            stops: stops, routes: routes, trips: trips,
            stopTimes: stopTimes, transfers: [],
            stopRoutes: stopRoutes, routeStops: routeStops
        )

        // ULTRA CSR shortcuts:
        // From Stop 1:
        // Shortcut A -> Stop 2 (duration 100s, wheelchair accessible = flag 1)
        // Shortcut B -> Stop 3 (duration 50s, not accessible = flag 0)
        let indptr: [UInt64] = [0, 0, 2, 2, 2] // Stop 1 has 2 shortcuts at indices 0, 1
        let targets: [UInt32] = [2, 3]
        let durations: [UInt16] = [100, 50]
        let flags: [UInt8] = [1, 0] // flag 1 = ROUTING_FLAG_WHEELCHAIR_ACCESSIBLE

        let ultraBlob = buildSyntheticUltraCsr(
            numStops: 4,
            indptr: indptr,
            targets: targets,
            durations: durations,
            flags: flags
        )

        var engine = RaptorEngine()
        _ = timetableBlob.withUnsafeBytes { raw in
            engine.load_timetable_blob(raw.baseAddress?.assumingMemoryBound(to: UInt8.self), raw.count)
        }
        let ultraLoaded = ultraBlob.withUnsafeBytes { raw in
            engine.load_ultra_blob(raw.baseAddress?.assumingMemoryBound(to: UInt8.self), raw.count)
        }
        XCTAssertTrue(ultraLoaded)
        XCTAssertTrue(engine.is_ultra_loaded())

        // Query with wheelchair filter to Stop 2 (accessible) -> reachable
        var wheelchairParams = QueryParams(0, 2, 28800, 3)
        wheelchairParams.flags = ROUTING_FLAG_WHEELCHAIR_ACCESSIBLE
        let wheelchairJourneys = engine.compute_journey(wheelchairParams)
        XCTAssertEqual(wheelchairJourneys.size(), 2)
        XCTAssertEqual(wheelchairJourneys[1].exit_stop_id, 2)

        // Query with wheelchair filter to Stop 3 (non-accessible shortcut) -> unreachable
        var nonAccessibleParams = QueryParams(0, 3, 28800, 3)
        nonAccessibleParams.flags = ROUTING_FLAG_WHEELCHAIR_ACCESSIBLE
        let nonAccessibleJourneys = engine.compute_journey(nonAccessibleParams)
        XCTAssertTrue(nonAccessibleJourneys.empty())

        // Standard query without wheelchair filter to Stop 3 -> reachable via faster shortcut
        let standardParams = QueryParams(0, 3, 28800, 3)
        let standardJourneys = engine.compute_journey(standardParams)
        XCTAssertEqual(standardJourneys.size(), 2)
        XCTAssertEqual(standardJourneys[1].exit_stop_id, 3)
    }

    // 7. Early Round Termination & Bounded Max Rounds
    func testEarlyRoundTermination() {
        let stops = [
            Stop(40.71, -74.00, 0, 0, 1, 0),
            Stop(40.73, -74.00, 1, 0, 1, 0)
        ]
        let routes = [Route(0, 0, 1, 2)]
        let trips = [Trip(0, 2, 1)]
        let stopTimes = [
            StopTime(28800, 28800, 0),
            StopTime(29400, 29400, 1)
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

        // Even with max_transfers = 8, engine terminates round 1
        let params = QueryParams(0, 1, 28800, 8)
        let journeys = engine.compute_journey(params)
        XCTAssertEqual(journeys.size(), 1)
    }
}
