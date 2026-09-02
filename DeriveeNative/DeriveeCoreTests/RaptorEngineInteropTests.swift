import XCTest
import CxxStdlib
@testable import DeriveeCore

final class RaptorEngineInteropTests: XCTestCase {

    private func buildSyntheticTimetable() -> Data {
        func align64(_ offset: Int) -> Int {
            let rem = offset % 64
            return rem == 0 ? offset : offset + (64 - rem)
        }

        let stops = [
            Stop(40.71, -74.00, 0, 0, 1, 0), // Stop 0 (ID 10 placeholder -> index 0)
            Stop(40.75, -74.00, 1, 0, 1, 0)  // Stop 1 (ID 50 placeholder -> index 1)
        ]
        let routes = [Route(0, 0, 1, 2)]
        let trips = [Trip(0, 2, 1)]
        let stopTimes = [
            StopTime(28800, 28800, 0),
            StopTime(29400, 29400, 1)
        ]
        let stopRoutes: [UInt32] = [0, 0]
        let routeStops: [UInt32] = [0, 1]

        let headerSize = 232
        let lenS0 = stops.count * MemoryLayout<Stop>.size
        let lenS1 = routes.count * MemoryLayout<Route>.size
        let lenS2 = trips.count * MemoryLayout<Trip>.size
        let lenS3 = stopTimes.count * MemoryLayout<StopTime>.size
        let lenS4 = 0
        let lenS5 = stopRoutes.count * MemoryLayout<UInt32>.size
        let lenS6 = routeStops.count * MemoryLayout<UInt32>.size

        let offS0 = align64(headerSize)
        let offS1 = align64(offS0 + lenS0)
        let offS2 = align64(offS1 + lenS1)
        let offS3 = align64(offS2 + lenS2)
        let offS4 = align64(offS3 + lenS3)
        let offS5 = align64(offS4 + lenS4)
        let offS6 = align64(offS5 + lenS5)
        let totalSize = align64(offS6 + lenS6)

        var data = Data(count: totalSize)
        data.withUnsafeMutableBytes { rawBuf in
            let ptr = rawBuf.baseAddress!
            ptr.storeBytes(of: UInt32(0x31565244), toByteOffset: 0, as: UInt32.self)
            ptr.storeBytes(of: UInt32(1), toByteOffset: 4, as: UInt32.self)
            ptr.storeBytes(of: UInt32(0x01020304), toByteOffset: 8, as: UInt32.self)
            ptr.storeBytes(of: UInt32(232), toByteOffset: 12, as: UInt32.self)
            ptr.storeBytes(of: UInt64(totalSize), toByteOffset: 16, as: UInt64.self)
            ptr.storeBytes(of: UInt64(0), toByteOffset: 24, as: UInt64.self)
            ptr.storeBytes(of: UInt32(7), toByteOffset: 32, as: UInt32.self)
            ptr.storeBytes(of: UInt32(0), toByteOffset: 36, as: UInt32.self)

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
            writeTOC(index: 4, offset: offS4, size: lenS4, count: 0)
            writeTOC(index: 5, offset: offS5, size: lenS5, count: stopRoutes.count)
            writeTOC(index: 6, offset: offS6, size: lenS6, count: routeStops.count)

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
            for (i, sr) in stopRoutes.enumerated() {
                ptr.storeBytes(of: sr, toByteOffset: offS5 + i * MemoryLayout<UInt32>.size, as: UInt32.self)
            }
            for (i, rs) in routeStops.enumerated() {
                ptr.storeBytes(of: rs, toByteOffset: offS6 + i * MemoryLayout<UInt32>.size, as: UInt32.self)
            }
        }
        return data
    }
    
    func testEngineLifecycleAndDelayRegistration() {
        var engine = RaptorEngine()
        XCTAssertFalse(engine.is_loaded())
        XCTAssertEqual(engine.registered_delays_count(), 0)
        
        // Dynamic real-time GTFS-RT delay updates
        engine.update_realtime_delay(101, 180) // +3 min delay
        engine.update_realtime_delay(102, -60) // -1 min early
        
        XCTAssertEqual(engine.registered_delays_count(), 2)
        XCTAssertEqual(engine.get_realtime_delay(101), 180)
        XCTAssertEqual(engine.get_realtime_delay(102), -60)
        XCTAssertEqual(engine.get_realtime_delay(999), 0, "Unregistered trip should return 0 delay")
    }
    
    func testQueryExecutionAndVectorBridging() {
        var engine = RaptorEngine()
        let blob = buildSyntheticTimetable()
        let loaded = blob.withUnsafeBytes { raw in
            engine.load_timetable_blob(raw.baseAddress?.assumingMemoryBound(to: UInt8.self), raw.count)
        }
        XCTAssertTrue(loaded)
        
        var params = QueryParams()
        params.origin_stop_id = 0
        params.destination_stop_id = 1
        params.departure_timestamp = 28800 // 08:00:00
        params.max_transfers = 3
        
        // Zero-bridge invocation returning C++ std::vector<JourneySegment> directly to Swift
        let cxxVector = engine.compute_journey(params)
        
        XCTAssertEqual(cxxVector.size(), 1)
        XCTAssertFalse(cxxVector.empty())
        
        // Direct subscript and field access in Swift
        let segment = cxxVector[0]
        XCTAssertEqual(segment.board_stop_id, 0)
        XCTAssertEqual(segment.exit_stop_id, 1)
        XCTAssertEqual(segment.departure_time, 28800)
        XCTAssertEqual(segment.arrival_time, 29400) // 08:10:00
        XCTAssertEqual(segment.route_id, 0)
        
        // Bridging std::vector iteration into Swift Array
        var swiftSegments: [JourneySegment] = []
        for seg in cxxVector {
            swiftSegments.append(seg)
        }
        XCTAssertEqual(swiftSegments.count, 1)
        XCTAssertEqual(swiftSegments.first?.trip_id, 0)
    }
    
    func testEmptyQueryOnIdenticalOriginDestination() {
        let engine = RaptorEngine()
        
        let params = QueryParams(42, 42, 3600, 2)
        let cxxVector = engine.compute_journey(params)
        
        XCTAssertTrue(cxxVector.empty())
        XCTAssertEqual(cxxVector.size(), 0)
    }

    func testRangeQueryExecutionAndParetoSetBridging() {
        var engine = RaptorEngine()
        let blob = buildSyntheticTimetable()
        _ = blob.withUnsafeBytes { raw in
            engine.load_timetable_blob(raw.baseAddress?.assumingMemoryBound(to: UInt8.self), raw.count)
        }

        let rangeParams = RangeQueryParams(0, 1, 28800, 32400, 3)
        let paretoSet = engine.compute_range_journeys(rangeParams)

        XCTAssertFalse(paretoSet.empty())
        XCTAssertEqual(paretoSet.size(), 1)

        let journey = paretoSet[0]
        XCTAssertEqual(journey.departure_time_sec, 28800)
        XCTAssertEqual(journey.cost.arrival_time_sec, 29400)
        XCTAssertEqual(journey.cost.transfer_count, 0)
    }
}
