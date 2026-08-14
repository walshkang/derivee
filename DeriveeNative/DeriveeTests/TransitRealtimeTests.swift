import XCTest
import SwiftProtobuf
import CoreLocation
@testable import Derivee

final class TransitRealtimeTests: XCTestCase {

    func testProtobufFeedMessageDeserialization() throws {
        var feedMessage = TransitRealtime_FeedMessage()
        
        var header = TransitRealtime_FeedHeader()
        header.gtfsRealtimeVersion = "2.0"
        header.timestamp = 1700000000
        feedMessage.header = header
        
        var entity1 = TransitRealtime_FeedEntity()
        entity1.id = "trip_1"
        
        var tripUpdate1 = TransitRealtime_TripUpdate()
        var trip1 = TransitRealtime_TripDescriptor()
        trip1.tripID = "trip_L_001"
        trip1.routeID = "L"
        tripUpdate1.trip = trip1
        
        let now = Date(timeIntervalSince1970: 1700000000)
        
        var stopUpdate1 = TransitRealtime_TripUpdate.StopTimeUpdate()
        stopUpdate1.stopID = "L08N"
        var arrival1 = TransitRealtime_TripUpdate.StopTimeEvent()
        arrival1.time = 1700000000 + 180 // 3 min later
        stopUpdate1.arrival = arrival1
        
        var stopUpdate2 = TransitRealtime_TripUpdate.StopTimeUpdate()
        stopUpdate2.stopID = "L08S"
        var arrival2 = TransitRealtime_TripUpdate.StopTimeEvent()
        arrival2.time = 1700000000 + 480 // 8 min later
        stopUpdate2.arrival = arrival2
        
        tripUpdate1.stopTimeUpdate = [stopUpdate1, stopUpdate2]
        entity1.tripUpdate = tripUpdate1
        
        feedMessage.entity = [entity1]
        
        let serializedData = try feedMessage.serializedData()
        XCTAssertFalse(serializedData.isEmpty, "Serialized protobuf payload should not be empty.")
        
        let arrivals = try TransitRealtimeService.shared.parseFeedMessage(
            data: serializedData,
            stopId: "L08",
            targetRouteId: "L",
            referenceDate: now
        )
        
        XCTAssertEqual(arrivals.count, 2)
        XCTAssertEqual(arrivals[0].line, "L")
        XCTAssertEqual(arrivals[0].minutes, 3)
        XCTAssertEqual(arrivals[0].destination, "Manhattan - 8th Ave")
        
        XCTAssertEqual(arrivals[1].line, "L")
        XCTAssertEqual(arrivals[1].minutes, 8)
        XCTAssertEqual(arrivals[1].destination, "Brooklyn - Canarsie / Rockaway Pkwy")
    }

    func testSubwayFeedUrlResolution() {
        XCTAssertEqual(TransitRealtimeService.SubwayFeed.feed(for: "1"), .numbered)
        XCTAssertEqual(TransitRealtimeService.SubwayFeed.feed(for: "6X"), .numbered)
        XCTAssertEqual(TransitRealtimeService.SubwayFeed.feed(for: "7"), .numbered)
        XCTAssertEqual(TransitRealtimeService.SubwayFeed.feed(for: "A"), .ace)
        XCTAssertEqual(TransitRealtimeService.SubwayFeed.feed(for: "C"), .ace)
        XCTAssertEqual(TransitRealtimeService.SubwayFeed.feed(for: "B"), .bdfm)
        XCTAssertEqual(TransitRealtimeService.SubwayFeed.feed(for: "F"), .bdfm)
        XCTAssertEqual(TransitRealtimeService.SubwayFeed.feed(for: "G"), .g)
        XCTAssertEqual(TransitRealtimeService.SubwayFeed.feed(for: "J"), .jz)
        XCTAssertEqual(TransitRealtimeService.SubwayFeed.feed(for: "N"), .nqrw)
        XCTAssertEqual(TransitRealtimeService.SubwayFeed.feed(for: "Q"), .nqrw)
        XCTAssertEqual(TransitRealtimeService.SubwayFeed.feed(for: "L"), .l)
        XCTAssertEqual(TransitRealtimeService.SubwayFeed.feed(for: "SIR"), .sir)
    }

    func testPastArrivalsAreFilteredOut() throws {
        var feedMessage = TransitRealtime_FeedMessage()
        var header = TransitRealtime_FeedHeader()
        header.gtfsRealtimeVersion = "2.0"
        header.timestamp = 1700000000
        feedMessage.header = header
        
        var entity = TransitRealtime_FeedEntity()
        entity.id = "trip_past"
        
        var tripUpdate = TransitRealtime_TripUpdate()
        var trip = TransitRealtime_TripDescriptor()
        trip.routeID = "G"
        tripUpdate.trip = trip
        
        let now = Date(timeIntervalSince1970: 1700000000)
        
        // Past arrival (5 minutes ago)
        var pastStop = TransitRealtime_TripUpdate.StopTimeUpdate()
        pastStop.stopID = "G22N"
        var pastArrival = TransitRealtime_TripUpdate.StopTimeEvent()
        pastArrival.time = 1700000000 - 300
        pastStop.arrival = pastArrival
        
        // Future arrival (4 minutes from now)
        var futureStop = TransitRealtime_TripUpdate.StopTimeUpdate()
        futureStop.stopID = "G22N"
        var futureArrival = TransitRealtime_TripUpdate.StopTimeEvent()
        futureArrival.time = 1700000000 + 240
        futureStop.arrival = futureArrival
        
        tripUpdate.stopTimeUpdate = [pastStop, futureStop]
        entity.tripUpdate = tripUpdate
        feedMessage.entity = [entity]
        
        let data = try feedMessage.serializedData()
        let arrivals = try TransitRealtimeService.shared.parseFeedMessage(
            data: data,
            stopId: "G22",
            targetRouteId: "G",
            referenceDate: now
        )
        
        XCTAssertEqual(arrivals.count, 1)
        XCTAssertEqual(arrivals[0].minutes, 4)
    }

    func testTransitRouteDataPolylineGeneration() async {
        let lines = ["1", "4", "7", "A", "F", "G", "J", "L", "N", "S", "SIR"]
        
        for line in lines {
            let coords = await TransitRouteData.loadRouteCoordinates(for: line)
            XCTAssertGreaterThanOrEqual(coords.count, 2, "Route \(line) should have at least 2 coordinates.")
            
            // Verify coordinates are in NYC metropolitan area bounds (lat: 40.4..41.0, lon: -74.3..-73.6)
            for coord in coords {
                XCTAssertGreaterThan(coord.latitude, 40.4, "Latitude out of bounds for route \(line)")
                XCTAssertLessThan(coord.latitude, 41.0, "Latitude out of bounds for route \(line)")
                XCTAssertGreaterThan(coord.longitude, -74.3, "Longitude out of bounds for route \(line)")
                XCTAssertLessThan(coord.longitude, -73.6, "Longitude out of bounds for route \(line)")
            }
        }
    }

    func testPollingCancellationLifecycle() async throws {
        let task = Task {
            while !Task.isCancelled {
                try await Task.sleep(nanoseconds: 50_000_000)
            }
        }
        
        XCTAssertFalse(task.isCancelled)
        task.cancel()
        XCTAssertTrue(task.isCancelled)
        
        // Verify task exits cleanly upon cancellation
        let result = await task.result
        switch result {
        case .success:
            XCTAssertTrue(task.isCancelled)
        case .failure(let error):
            XCTAssertTrue(error is CancellationError)
        }
    }
}
