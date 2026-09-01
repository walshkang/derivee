import XCTest
import CxxStdlib
@testable import DeriveeCore

final class RaptorEngineInteropTests: XCTestCase {
    
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
        let engine = RaptorEngine()
        
        var params = QueryParams()
        params.origin_stop_id = 10
        params.destination_stop_id = 50
        params.departure_timestamp = 28800 // 08:00:00
        params.max_transfers = 3
        
        // Zero-bridge invocation returning C++ std::vector<JourneySegment> directly to Swift
        let cxxVector = engine.compute_journey(params)
        
        XCTAssertEqual(cxxVector.size(), 1)
        XCTAssertFalse(cxxVector.empty())
        
        // Direct subscript and field access in Swift
        let segment = cxxVector[0]
        XCTAssertEqual(segment.board_stop_id, 10)
        XCTAssertEqual(segment.exit_stop_id, 50)
        XCTAssertEqual(segment.departure_time, 28800)
        XCTAssertEqual(segment.arrival_time, 29400) // 08:10:00
        XCTAssertEqual(segment.route_id, 1)
        
        // Bridging std::vector iteration into Swift Array
        var swiftSegments: [JourneySegment] = []
        for seg in cxxVector {
            swiftSegments.append(seg)
        }
        XCTAssertEqual(swiftSegments.count, 1)
        XCTAssertEqual(swiftSegments.first?.trip_id, 1001)
    }
    
    func testEmptyQueryOnIdenticalOriginDestination() {
        let engine = RaptorEngine()
        
        let params = QueryParams(42, 42, 3600, 2)
        let cxxVector = engine.compute_journey(params)
        
        XCTAssertTrue(cxxVector.empty())
        XCTAssertEqual(cxxVector.size(), 0)
    }
}
