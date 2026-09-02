import XCTest
import SwiftProtobuf
@testable import Derivee

final class GTFSRealtimeStreamProcessorTests: XCTestCase {
    
    var processor: GTFSRealtimeStreamProcessor!
    
    override func setUp() async throws {
        try await super.setUp()
        processor = GTFSRealtimeStreamProcessor()
    }
    
    override func tearDown() async throws {
        await processor.reset()
        processor = nil
        try await super.tearDown()
    }
    
    // MARK: - Ingestion & Summary Tests
    
    func testBasicFeedIngestionAndSummary() async throws {
        var feedMessage = TransitRealtime_FeedMessage()
        var header = TransitRealtime_FeedHeader()
        header.gtfsRealtimeVersion = "2.0"
        header.timestamp = 1700000000
        feedMessage.header = header
        
        var entity1 = TransitRealtime_FeedEntity()
        entity1.id = "e1"
        var tripUpdate1 = TransitRealtime_TripUpdate()
        var trip1 = TransitRealtime_TripDescriptor()
        trip1.tripID = "TRIP_A1"
        trip1.routeID = "A"
        tripUpdate1.trip = trip1
        tripUpdate1.delay = 120 // 2 min delay
        
        var stop1 = TransitRealtime_TripUpdate.StopTimeUpdate()
        stop1.stopID = "A01"
        stop1.stopSequence = 1
        var arr1 = TransitRealtime_TripUpdate.StopTimeEvent()
        arr1.time = 1700000120
        arr1.delay = 120
        stop1.arrival = arr1
        
        var stop2 = TransitRealtime_TripUpdate.StopTimeUpdate()
        stop2.stopID = "A02"
        stop2.stopSequence = 2
        var arr2 = TransitRealtime_TripUpdate.StopTimeEvent()
        arr2.time = 1700000300
        arr2.delay = 180
        stop2.arrival = arr2
        
        tripUpdate1.stopTimeUpdate = [stop1, stop2]
        entity1.tripUpdate = tripUpdate1
        feedMessage.entity = [entity1]
        
        let data = try feedMessage.serializedData()
        let summary = try await processor.ingestFeedMessage(data: data)
        
        XCTAssertEqual(summary.processedTripsCount, 1)
        XCTAssertEqual(summary.totalStopTimeUpdatesCount, 2)
        XCTAssertEqual(summary.maxDelaySeconds, 180)
        XCTAssertEqual(summary.minDelaySeconds, 120)
        XCTAssertEqual(summary.averageDelaySeconds, 150.0)
        XCTAssertEqual(summary.activeDisruptionsCount, 0)
        
        let delay = await processor.getDelay(tripId: "TRIP_A1")
        XCTAssertEqual(delay, 180) // latest running delay
        
        let stop1Delay = await processor.getDelay(tripId: "TRIP_A1", stopId: "A01")
        XCTAssertEqual(stop1Delay, 120)
        
        let stop2Delay = await processor.getDelay(tripId: "TRIP_A1", stopId: "A02")
        XCTAssertEqual(stop2Delay, 180)
    }
    
    // MARK: - Downstream Delay Propagation Tests
    
    func testDownstreamDelayPropagation() async throws {
        var tripUpdate = TransitRealtime_TripUpdate()
        var trip = TransitRealtime_TripDescriptor()
        trip.tripID = "TRIP_PROP_1"
        trip.routeID = "L"
        tripUpdate.trip = trip
        
        // Stop 1 has explicit delay (+240s)
        var s1 = TransitRealtime_TripUpdate.StopTimeUpdate()
        s1.stopID = "L01"
        s1.stopSequence = 1
        var arr1 = TransitRealtime_TripUpdate.StopTimeEvent()
        arr1.time = 1700000300
        arr1.delay = 240
        s1.arrival = arr1
        
        // Stop 2 has time but NO delay field
        var s2 = TransitRealtime_TripUpdate.StopTimeUpdate()
        s2.stopID = "L02"
        s2.stopSequence = 2
        var arr2 = TransitRealtime_TripUpdate.StopTimeEvent()
        arr2.time = 1700000600
        s2.arrival = arr2
        
        // Stop 3 has time but NO delay field
        var s3 = TransitRealtime_TripUpdate.StopTimeUpdate()
        s3.stopID = "L03"
        s3.stopSequence = 3
        var arr3 = TransitRealtime_TripUpdate.StopTimeEvent()
        arr3.time = 1700000900
        s3.arrival = arr3
        
        tripUpdate.stopTimeUpdate = [s1, s2, s3]
        
        await processor.ingestTripUpdates([tripUpdate], headerTimestamp: 1700000000)
        
        let fetchedTrip = await processor.getTripUpdate(tripId: "TRIP_PROP_1")
        XCTAssertNotNil(fetchedTrip)
        
        let stops = fetchedTrip!.stopTimeUpdates
        XCTAssertEqual(stops.count, 3)
        
        // Stop 1: explicit
        XCTAssertEqual(stops[0].stopId, "L01")
        XCTAssertEqual(stops[0].effectiveDelaySeconds, 240)
        XCTAssertEqual(stops[0].effectiveDelayMinutes, 4)
        XCTAssertFalse(stops[0].isPropagated)
        
        // Stop 2: propagated
        XCTAssertEqual(stops[1].stopId, "L02")
        XCTAssertEqual(stops[1].effectiveDelaySeconds, 240)
        XCTAssertEqual(stops[1].effectiveDelayMinutes, 4)
        XCTAssertTrue(stops[1].isPropagated)
        
        // Stop 3: propagated
        XCTAssertEqual(stops[2].stopId, "L03")
        XCTAssertEqual(stops[2].effectiveDelaySeconds, 240)
        XCTAssertEqual(stops[2].effectiveDelayMinutes, 4)
        XCTAssertTrue(stops[2].isPropagated)
    }
    
    func testDownstreamDelayOverrideMidTrip() async throws {
        var tripUpdate = TransitRealtime_TripUpdate()
        var trip = TransitRealtime_TripDescriptor()
        trip.tripID = "TRIP_OVERRIDE"
        trip.routeID = "7"
        tripUpdate.trip = trip
        
        // Stop 1: +60s
        var s1 = TransitRealtime_TripUpdate.StopTimeUpdate()
        s1.stopID = "701"
        s1.stopSequence = 1
        var arr1 = TransitRealtime_TripUpdate.StopTimeEvent()
        arr1.delay = 60
        s1.arrival = arr1
        
        // Stop 2: No delay (+60s propagated)
        var s2 = TransitRealtime_TripUpdate.StopTimeUpdate()
        s2.stopID = "702"
        s2.stopSequence = 2
        var arr2 = TransitRealtime_TripUpdate.StopTimeEvent()
        arr2.time = 1700000500
        s2.arrival = arr2
        
        // Stop 3: Explicit +360s override
        var s3 = TransitRealtime_TripUpdate.StopTimeUpdate()
        s3.stopID = "703"
        s3.stopSequence = 3
        var arr3 = TransitRealtime_TripUpdate.StopTimeEvent()
        arr3.delay = 360
        s3.arrival = arr3
        
        // Stop 4: No delay (+360s propagated)
        var s4 = TransitRealtime_TripUpdate.StopTimeUpdate()
        s4.stopID = "704"
        s4.stopSequence = 4
        var arr4 = TransitRealtime_TripUpdate.StopTimeEvent()
        arr4.time = 1700001000
        s4.arrival = arr4
        
        tripUpdate.stopTimeUpdate = [s1, s2, s3, s4]
        
        await processor.ingestTripUpdates([tripUpdate], headerTimestamp: 1700000000)
        
        guard let fetched = await processor.getTripUpdate(tripId: "TRIP_OVERRIDE") else {
            XCTFail("Trip should be present")
            return
        }
        
        XCTAssertEqual(fetched.stopTimeUpdates[0].effectiveDelaySeconds, 60)
        XCTAssertFalse(fetched.stopTimeUpdates[0].isPropagated)
        
        XCTAssertEqual(fetched.stopTimeUpdates[1].effectiveDelaySeconds, 60)
        XCTAssertTrue(fetched.stopTimeUpdates[1].isPropagated)
        
        XCTAssertEqual(fetched.stopTimeUpdates[2].effectiveDelaySeconds, 360)
        XCTAssertFalse(fetched.stopTimeUpdates[2].isPropagated)
        
        XCTAssertEqual(fetched.stopTimeUpdates[3].effectiveDelaySeconds, 360)
        XCTAssertTrue(fetched.stopTimeUpdates[3].isPropagated)
    }
    
    // MARK: - Circular Delay Calculation From ScheduledTime
    
    func testCircularDelayResolutionFromScheduledTime() async throws {
        var tripUpdate = TransitRealtime_TripUpdate()
        var trip = TransitRealtime_TripDescriptor()
        trip.tripID = "TRIP_CIRCULAR_1"
        trip.routeID = "N"
        tripUpdate.trip = trip
        
        // Scheduled: 1700000000 (00:00:00), Live: 1700000150 (00:02:30) -> +150s (+2.5m)
        var s1 = TransitRealtime_TripUpdate.StopTimeUpdate()
        s1.stopID = "N01"
        s1.stopSequence = 1
        var arr1 = TransitRealtime_TripUpdate.StopTimeEvent()
        arr1.time = 1700000150
        arr1.scheduledTime = 1700000000
        s1.arrival = arr1
        
        tripUpdate.stopTimeUpdate = [s1]
        await processor.ingestTripUpdates([tripUpdate], headerTimestamp: 1700000000)
        
        let fetched = await processor.getTripUpdate(tripId: "TRIP_CIRCULAR_1")
        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched!.stopTimeUpdates[0].effectiveDelaySeconds, 150)
        XCTAssertEqual(fetched!.stopTimeUpdates[0].effectiveDelayMinutes, 3)
    }
    
    // MARK: - Disruptions and Disrupted Stops
    
    func testDisruptionsAndCancellations() async throws {
        var tripUpdate1 = TransitRealtime_TripUpdate()
        var trip1 = TransitRealtime_TripDescriptor()
        trip1.tripID = "TRIP_CANCELED"
        trip1.routeID = "F"
        trip1.scheduleRelationship = .canceled
        tripUpdate1.trip = trip1
        
        var s1 = TransitRealtime_TripUpdate.StopTimeUpdate()
        s1.stopID = "F01"
        var s2 = TransitRealtime_TripUpdate.StopTimeUpdate()
        s2.stopID = "F02"
        tripUpdate1.stopTimeUpdate = [s1, s2]
        
        var tripUpdate2 = TransitRealtime_TripUpdate()
        var trip2 = TransitRealtime_TripDescriptor()
        trip2.tripID = "TRIP_SKIPPED_STOP"
        trip2.routeID = "F"
        tripUpdate2.trip = trip2
        
        var s3 = TransitRealtime_TripUpdate.StopTimeUpdate()
        s3.stopID = "F03"
        s3.scheduleRelationship = .skipped
        var s4 = TransitRealtime_TripUpdate.StopTimeUpdate()
        s4.stopID = "F04"
        tripUpdate2.stopTimeUpdate = [s3, s4]
        
        let summary = await processor.ingestTripUpdates([tripUpdate1, tripUpdate2], headerTimestamp: 1700000000)
        XCTAssertEqual(summary.activeDisruptionsCount, 2)
        
        let disruptedStops = await processor.getDisruptedStops()
        XCTAssertTrue(disruptedStops.contains("F01"))
        XCTAssertTrue(disruptedStops.contains("F02"))
        XCTAssertTrue(disruptedStops.contains("F03"))
        XCTAssertFalse(disruptedStops.contains("F04"))
    }
    
    // MARK: - Query APIs
    
    func testQueryAPIs() async throws {
        var tripUpdate = TransitRealtime_TripUpdate()
        var trip = TransitRealtime_TripDescriptor()
        trip.tripID = "TRIP_Q1"
        trip.routeID = "Q"
        tripUpdate.trip = trip
        
        var s1 = TransitRealtime_TripUpdate.StopTimeUpdate()
        s1.stopID = "Q01"
        s1.stopSequence = 1
        var arr1 = TransitRealtime_TripUpdate.StopTimeEvent()
        arr1.time = 1700000500
        arr1.delay = 100
        s1.arrival = arr1
        
        var s2 = TransitRealtime_TripUpdate.StopTimeUpdate()
        s2.stopID = "Q02"
        s2.stopSequence = 2
        var arr2 = TransitRealtime_TripUpdate.StopTimeEvent()
        arr2.time = 1700000800
        arr2.delay = 150
        s2.arrival = arr2
        
        tripUpdate.stopTimeUpdate = [s1, s2]
        await processor.ingestTripUpdates([tripUpdate], headerTimestamp: 1700000000)
        
        // Departures for stop Q01
        let departuresQ01 = await processor.getLiveDepartures(forStop: "Q01")
        XCTAssertEqual(departuresQ01.count, 1)
        XCTAssertEqual(departuresQ01[0].tripId, "TRIP_Q1")
        XCTAssertEqual(departuresQ01[0].effectiveDelaySeconds, 100)
        
        // Trips for route Q
        let routeTrips = await processor.getTrips(forRoute: "Q")
        XCTAssertEqual(routeTrips.count, 1)
        XCTAssertEqual(routeTrips[0].tripId, "TRIP_Q1")
        
        // Active delays dictionary
        let delays = await processor.getActiveTripDelays()
        XCTAssertEqual(delays["TRIP_Q1"], 150)
    }
    
    // MARK: - Stale Eviction
    
    func testStaleTripEviction() async throws {
        let baseDate = Date(timeIntervalSince1970: 1700000000)
        
        var tripUpdate = TransitRealtime_TripUpdate()
        var trip = TransitRealtime_TripDescriptor()
        trip.tripID = "TRIP_OLD"
        trip.routeID = "G"
        tripUpdate.trip = trip
        
        var s1 = TransitRealtime_TripUpdate.StopTimeUpdate()
        s1.stopID = "G01"
        tripUpdate.stopTimeUpdate = [s1]
        
        await processor.ingestTripUpdates([tripUpdate], headerTimestamp: 1700000000, referenceDate: baseDate)
        
        // Before pruning
        let tripBefore = await processor.getTripUpdate(tripId: "TRIP_OLD")
        XCTAssertNotNil(tripBefore)
        
        // Prune older than 60s at baseDate + 120s
        let evicted = await processor.pruneStale(olderThanSeconds: 60, referenceDate: baseDate.addingTimeInterval(120))
        XCTAssertEqual(evicted, 1)
        
        // After pruning
        let tripAfter = await processor.getTripUpdate(tripId: "TRIP_OLD")
        XCTAssertNil(tripAfter)
        
        let departures = await processor.getLiveDepartures(forStop: "G01")
        XCTAssertTrue(departures.isEmpty)
        
        let routeTrips = await processor.getTrips(forRoute: "G")
        XCTAssertTrue(routeTrips.isEmpty)
    }
    
    // MARK: - Concurrency & Race Condition Safety
    
    func testConcurrentFeedIngestion() async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            for i in 0..<20 {
                group.addTask {
                    var tripUpdate = TransitRealtime_TripUpdate()
                    var trip = TransitRealtime_TripDescriptor()
                    trip.tripID = "CONCURRENT_TRIP_\(i)"
                    trip.routeID = "R\(i % 5)"
                    tripUpdate.trip = trip
                    tripUpdate.delay = Int32(i * 10)
                    
                    var stop = TransitRealtime_TripUpdate.StopTimeUpdate()
                    stop.stopID = "STOP_\(i)"
                    var arr = TransitRealtime_TripUpdate.StopTimeEvent()
                    arr.delay = Int32(i * 10)
                    stop.arrival = arr
                    tripUpdate.stopTimeUpdate = [stop]
                    
                    await self.processor.ingestTripUpdates([tripUpdate], headerTimestamp: UInt64(1700000000 + i))
                }
            }
            try await group.waitForAll()
        }
        
        let allDelays = await processor.getActiveTripDelays()
        XCTAssertEqual(allDelays.count, 20)
    }
}
