import XCTest
@testable import DeriveeCore

final class TimetableStructTests: XCTestCase {
    
    func testStructMemoryLayouts() {
        // Core Timetable Structs per Wave N Research Specifications
        XCTAssertEqual(MemoryLayout<StopTime>.size, 12, "StopTime must be exactly 12 bytes")
        XCTAssertEqual(MemoryLayout<Trip>.size, 8, "Trip must be exactly 8 bytes")
        XCTAssertEqual(MemoryLayout<Route>.size, 12, "Route must be exactly 12 bytes")
        XCTAssertEqual(MemoryLayout<Stop>.size, 20, "Stop must be exactly 20 bytes")
        XCTAssertEqual(MemoryLayout<Transfer>.size, 8, "Transfer must be exactly 8 bytes")
        XCTAssertEqual(MemoryLayout<StochasticWeight>.size, 4, "StochasticWeight must be exactly 4 bytes")
        XCTAssertEqual(MemoryLayout<JourneySegment>.size, 24, "JourneySegment must be exactly 24 bytes")
        
        // Observer Format Structs per Research Doc 01
        XCTAssertEqual(MemoryLayout<observer.format.SectionDesc>.size, 24, "SectionDesc must be exactly 24 bytes")
        XCTAssertEqual(MemoryLayout<observer.format.MasterHeader>.size, 232, "MasterHeader must be exactly 232 bytes")
        XCTAssertEqual(MemoryLayout<observer.format.RaptorStop>.size, 24, "RaptorStop must be exactly 24 bytes")
        XCTAssertEqual(MemoryLayout<observer.format.WalkNode>.size, 16, "WalkNode must be exactly 16 bytes")
        XCTAssertEqual(MemoryLayout<observer.format.WalkEdge>.size, 8, "WalkEdge must be exactly 8 bytes")
    }
    
    func testStopTimeFieldAccess() {
        var stopTime = StopTime()
        stopTime.arrival_time_sec = 28800   // 08:00:00
        stopTime.departure_time_sec = 28830 // 08:00:30
        stopTime.stop_id = 42
        
        XCTAssertEqual(stopTime.arrival_time_sec, 28800)
        XCTAssertEqual(stopTime.departure_time_sec, 28830)
        XCTAssertEqual(stopTime.stop_id, 42)
    }
    
    func testTripAndRouteFieldAccess() {
        let trip = Trip(100, 35, 1)
        XCTAssertEqual(trip.stop_times_offset, 100)
        XCTAssertEqual(trip.stop_times_count, 35)
        XCTAssertEqual(trip.service_id, 1)
        
        let route = Route(50, 200, 10, 30)
        XCTAssertEqual(route.trips_offset, 50)
        XCTAssertEqual(route.route_stops_offset, 200)
        XCTAssertEqual(route.trip_count, 10)
        XCTAssertEqual(route.stop_count, 30)
    }
    
    func testStopAndTransferFieldAccess() {
        let stop = Stop(40.7128, -74.0060, 5, 12, 4, 8)
        XCTAssertEqual(stop.latitude, 40.7128, accuracy: 0.0001)
        XCTAssertEqual(stop.longitude, -74.0060, accuracy: 0.0001)
        XCTAssertEqual(stop.routes_offset, 5)
        XCTAssertEqual(stop.transfers_offset, 12)
        XCTAssertEqual(stop.route_count, 4)
        XCTAssertEqual(stop.transfer_count, 8)
        
        let transfer = Transfer(105, 180, 250)
        XCTAssertEqual(transfer.target_stop_id, 105)
        XCTAssertEqual(transfer.duration_sec, 180)
        XCTAssertEqual(transfer.distance_meters, 250)
    }

    func testParetoCostAndRangeQueryParamsFieldAccess() {
        let cost = ParetoCost(30000, 2, 240, 15, 12)
        XCTAssertEqual(cost.arrival_time_sec, 30000)
        XCTAssertEqual(cost.transfer_count, 2)
        XCTAssertEqual(cost.effort_duration_sec, 240)
        XCTAssertEqual(cost.layover_penalty, 15)
        XCTAssertEqual(cost.variance_disutility, 12)

        let rangeParams = RangeQueryParams(10, 50, 28800, 32400, 3, ROUTING_FLAG_WHEELCHAIR_ACCESSIBLE)
        XCTAssertEqual(rangeParams.origin_stop_id, 10)
        XCTAssertEqual(rangeParams.destination_stop_id, 50)
        XCTAssertEqual(rangeParams.departure_start_timestamp, 28800)
        XCTAssertEqual(rangeParams.departure_end_timestamp, 32400)
        XCTAssertEqual(rangeParams.max_transfers, 3)
        XCTAssertEqual(rangeParams.flags, ROUTING_FLAG_WHEELCHAIR_ACCESSIBLE)
        XCTAssertEqual(rangeParams.stochastic_horizon_sec, 2700)
        XCTAssertEqual(rangeParams.sampling_step_sec, 60)
    }
}

