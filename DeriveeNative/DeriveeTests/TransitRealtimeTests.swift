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
        
        let now = Date(timeIntervalSince1970: 1700000000)
        
        var entity1 = TransitRealtime_FeedEntity()
        entity1.id = "trip_1"
        var tripUpdate1 = TransitRealtime_TripUpdate()
        var trip1 = TransitRealtime_TripDescriptor()
        trip1.tripID = "trip_L_001"
        trip1.routeID = "L"
        tripUpdate1.trip = trip1
        
        var stopUpdate1 = TransitRealtime_TripUpdate.StopTimeUpdate()
        stopUpdate1.stopID = "L08N"
        var arrival1 = TransitRealtime_TripUpdate.StopTimeEvent()
        arrival1.time = 1700000000 + 180 // 3 min later
        stopUpdate1.arrival = arrival1
        
        var stopUpdate1Term = TransitRealtime_TripUpdate.StopTimeUpdate()
        stopUpdate1Term.stopID = "L01N" // 8 Av
        var arrival1Term = TransitRealtime_TripUpdate.StopTimeEvent()
        arrival1Term.time = 1700000000 + 600
        stopUpdate1Term.arrival = arrival1Term
        tripUpdate1.stopTimeUpdate = [stopUpdate1, stopUpdate1Term]
        entity1.tripUpdate = tripUpdate1
        
        var entity2 = TransitRealtime_FeedEntity()
        entity2.id = "trip_2"
        var tripUpdate2 = TransitRealtime_TripUpdate()
        var trip2 = TransitRealtime_TripDescriptor()
        trip2.tripID = "trip_L_002"
        trip2.routeID = "L"
        tripUpdate2.trip = trip2
        
        var stopUpdate2 = TransitRealtime_TripUpdate.StopTimeUpdate()
        stopUpdate2.stopID = "L08S"
        var arrival2 = TransitRealtime_TripUpdate.StopTimeEvent()
        arrival2.time = 1700000000 + 480 // 8 min later
        stopUpdate2.arrival = arrival2
        
        var stopUpdate2Term = TransitRealtime_TripUpdate.StopTimeUpdate()
        stopUpdate2Term.stopID = "L29S" // Canarsie-Rockaway Pkwy
        var arrival2Term = TransitRealtime_TripUpdate.StopTimeEvent()
        arrival2Term.time = 1700000000 + 1200
        stopUpdate2Term.arrival = arrival2Term
        tripUpdate2.stopTimeUpdate = [stopUpdate2, stopUpdate2Term]
        entity2.tripUpdate = tripUpdate2
        
        feedMessage.entity = [entity1, entity2]
        
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
        XCTAssertEqual(arrivals[0].destination, "L to 8 Av")
        
        XCTAssertEqual(arrivals[1].line, "L")
        XCTAssertEqual(arrivals[1].minutes, 8)
        XCTAssertEqual(arrivals[1].destination, "L to Canarsie-Rockaway Pkwy")
    }

    func testDynamicTerminalResolutionStandardExpress() throws {
        var tripUpdate = TransitRealtime_TripUpdate()
        var trip = TransitRealtime_TripDescriptor()
        trip.routeID = "4"
        tripUpdate.trip = trip
        
        var u1 = TransitRealtime_TripUpdate.StopTimeUpdate()
        u1.stopID = "414N" // 161 St-Yankee Stadium
        var u2 = TransitRealtime_TripUpdate.StopTimeUpdate()
        u2.stopID = "401N" // Woodlawn
        tripUpdate.stopTimeUpdate = [u1, u2]
        
        let destination = TransitRealtimeService.shared.resolveDestination(
            tripUpdate: tripUpdate,
            line: "4",
            stopId: "414N",
            matchingUpdate: u1
        )
        XCTAssertEqual(destination, "4 to Woodlawn EXP")
    }
    
    func testPhysicalExpressTrackDetection() throws {
        var tripUpdate = TransitRealtime_TripUpdate()
        var trip = TransitRealtime_TripDescriptor()
        trip.routeID = "6"
        tripUpdate.trip = trip
        
        var u1 = TransitRealtime_TripUpdate.StopTimeUpdate()
        u1.stopID = "631N" // Grand Central
        var nyctStop = TransitRealtime_NyctStopTimeUpdate()
        nyctStop.actualTrack = "3" // Northbound Express track
        u1.TransitRealtime_nyctStopTimeUpdate = nyctStop
        
        var u2 = TransitRealtime_TripUpdate.StopTimeUpdate()
        u2.stopID = "601N" // Pelham Bay Park
        tripUpdate.stopTimeUpdate = [u1, u2]
        
        let destination = TransitRealtimeService.shared.resolveDestination(
            tripUpdate: tripUpdate,
            line: "6",
            stopId: "631N",
            matchingUpdate: u1
        )
        XCTAssertEqual(destination, "6 to Pelham Bay Park EXP")
    }
    
    func testLocalTrackOverrideOnExpressRoute() throws {
        var tripUpdate = TransitRealtime_TripUpdate()
        var trip = TransitRealtime_TripDescriptor()
        trip.routeID = "4"
        tripUpdate.trip = trip
        
        var u1 = TransitRealtime_TripUpdate.StopTimeUpdate()
        u1.stopID = "414N"
        var nyctStop = TransitRealtime_NyctStopTimeUpdate()
        nyctStop.actualTrack = "4" // Northbound Local track override!
        u1.TransitRealtime_nyctStopTimeUpdate = nyctStop
        
        var u2 = TransitRealtime_TripUpdate.StopTimeUpdate()
        u2.stopID = "401N" // Woodlawn
        tripUpdate.stopTimeUpdate = [u1, u2]
        
        let destination = TransitRealtimeService.shared.resolveDestination(
            tripUpdate: tripUpdate,
            line: "4",
            stopId: "414N",
            matchingUpdate: u1
        )
        XCTAssertEqual(destination, "4 to Woodlawn Local")
    }
    
    func testDynamicTerminalResolutionShortTurn() throws {
        var tripUpdate = TransitRealtime_TripUpdate()
        var trip = TransitRealtime_TripDescriptor()
        trip.routeID = "5"
        tripUpdate.trip = trip
        
        var u1 = TransitRealtime_TripUpdate.StopTimeUpdate()
        u1.stopID = "631S" // Grand Central-42 St
        var u2 = TransitRealtime_TripUpdate.StopTimeUpdate()
        u2.stopID = "420S" // Bowling Green (Short turn for Line 5)
        tripUpdate.stopTimeUpdate = [u1, u2]
        
        let destination = TransitRealtimeService.shared.resolveDestination(
            tripUpdate: tripUpdate,
            line: "5",
            stopId: "631S",
            matchingUpdate: u1
        )
        XCTAssertEqual(destination, "5 to Bowling Green (Short Turn) EXP")
    }
    
    func testTrainIDPrefixShortTurnAndExpress() throws {
        // Test train_id prefix $ triggers short-turn
        var tripUpdate1 = TransitRealtime_TripUpdate()
        var trip1 = TransitRealtime_TripDescriptor()
        trip1.routeID = "6"
        var nyctTrip1 = TransitRealtime_NyctTripDescriptor()
        nyctTrip1.trainID = "$6_001"
        trip1.TransitRealtime_nyctTripDescriptor = nyctTrip1
        tripUpdate1.trip = trip1
        
        var u1 = TransitRealtime_TripUpdate.StopTimeUpdate()
        u1.stopID = "601N" // Standard terminal, but $ trainID marks dispatch turn
        tripUpdate1.stopTimeUpdate = [u1]
        
        let dest1 = TransitRealtimeService.shared.resolveDestination(
            tripUpdate: tripUpdate1,
            line: "6",
            stopId: "631N",
            matchingUpdate: u1
        )
        XCTAssertEqual(dest1, "6 to Pelham Bay Park (Short Turn)")
        
        // Test train_id prefix / triggers express
        var tripUpdate2 = TransitRealtime_TripUpdate()
        var trip2 = TransitRealtime_TripDescriptor()
        trip2.routeID = "1"
        var nyctTrip2 = TransitRealtime_NyctTripDescriptor()
        nyctTrip2.trainID = "/1_002"
        trip2.TransitRealtime_nyctTripDescriptor = nyctTrip2
        tripUpdate2.trip = trip2
        
        var u2 = TransitRealtime_TripUpdate.StopTimeUpdate()
        u2.stopID = "101N"
        tripUpdate2.stopTimeUpdate = [u2]
        
        let dest2 = TransitRealtimeService.shared.resolveDestination(
            tripUpdate: tripUpdate2,
            line: "1",
            stopId: "125N",
            matchingUpdate: u2
        )
        XCTAssertEqual(dest2, "1 to Van Cortlandt Park-242 St EXP")
    }
    
    func testSkippedStopsTerminalInference() throws {
        var tripUpdate = TransitRealtime_TripUpdate()
        var trip = TransitRealtime_TripDescriptor()
        trip.routeID = "L"
        tripUpdate.trip = trip
        
        var u1 = TransitRealtime_TripUpdate.StopTimeUpdate()
        u1.stopID = "L08S" // Bedford Av
        
        var u2 = TransitRealtime_TripUpdate.StopTimeUpdate()
        u2.stopID = "L17S" // Myrtle-Wyckoff Avs (Active short-turn terminus)
        
        var u3 = TransitRealtime_TripUpdate.StopTimeUpdate()
        u3.stopID = "L29S" // Canarsie-Rockaway Pkwy (Cancelled / Skipped)
        u3.scheduleRelationship = .skipped
        
        tripUpdate.stopTimeUpdate = [u1, u2, u3]
        
        let destination = TransitRealtimeService.shared.resolveDestination(
            tripUpdate: tripUpdate,
            line: "L",
            stopId: "L08S",
            matchingUpdate: u1
        )
        XCTAssertEqual(destination, "L to Myrtle-Wyckoff Avs (Short Turn)")
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

    func testBusDestinationResolutionB32() {
        let nb = TransitRealtimeService.resolveBusDestination(routeId: "B32", directionId: 0)
        XCTAssertEqual(nb.destination, "Long Island City - Queens Plaza")
        XCTAssertEqual(nb.direction, "Northbound & Queens")
        
        let sb = TransitRealtimeService.resolveBusDestination(routeId: "B32", directionId: 1)
        XCTAssertEqual(sb.destination, "Williamsburg Bridge Plaza")
        XCTAssertEqual(sb.direction, "Southbound & Williamsburg")
    }

    func testWilliamsburgBusDestinations() {
        let b24 = TransitRealtimeService.resolveBusDestination(routeId: "B24", directionId: 0)
        XCTAssertEqual(b24.destination, "Greenpoint - Manhattan Ave")
        
        let b43 = TransitRealtimeService.resolveBusDestination(routeId: "B43", directionId: 0)
        XCTAssertEqual(b43.destination, "Greenpoint - Box St")
        
        let q54 = TransitRealtimeService.resolveBusDestination(routeId: "Q54", directionId: 0)
        XCTAssertEqual(q54.destination, "Jamaica - 170 St / Jamaica Ave")
        
        let q59 = TransitRealtimeService.resolveBusDestination(routeId: "Q59", directionId: 0)
        XCTAssertEqual(q59.destination, "Rego Park - 63 Dr / Queens Blvd")
    }

    // MARK: - Wave M.1: VehicleStopStatus & Terminus Dwell Tests

    func testVehiclePositionTerminusDwellStoppedAt() throws {
        let nowEpoch: Int64 = 1700000000
        let refDate = Date(timeIntervalSince1970: TimeInterval(nowEpoch))
        
        var feedMessage = TransitRealtime_FeedMessage()
        var header = TransitRealtime_FeedHeader()
        header.gtfsRealtimeVersion = "2.0"
        header.timestamp = UInt64(nowEpoch)
        feedMessage.header = header
        
        // Entity 1: TripUpdate with origin at L01 and downstream stops L02, L03
        var ent1 = TransitRealtime_FeedEntity()
        ent1.id = "TU_L_001"
        var tu = TransitRealtime_TripUpdate()
        var trip = TransitRealtime_TripDescriptor()
        trip.tripID = "TRIP_L_DWELL_001"
        trip.routeID = "L"
        tu.trip = trip
        
        var stu1 = TransitRealtime_TripUpdate.StopTimeUpdate()
        stu1.stopID = "L01N"
        stu1.stopSequence = 1
        var arr1 = TransitRealtime_TripUpdate.StopTimeEvent()
        arr1.time = nowEpoch + 180 // 3m
        stu1.arrival = arr1
        stu1.departure = arr1
        
        var stu2 = TransitRealtime_TripUpdate.StopTimeUpdate()
        stu2.stopID = "L02N"
        stu2.stopSequence = 2
        var arr2 = TransitRealtime_TripUpdate.StopTimeEvent()
        arr2.time = nowEpoch + 360 // 6m
        stu2.arrival = arr2
        stu2.departure = arr2
        
        var stu3 = TransitRealtime_TripUpdate.StopTimeUpdate()
        stu3.stopID = "L03N"
        stu3.stopSequence = 3
        var arr3 = TransitRealtime_TripUpdate.StopTimeEvent()
        arr3.time = nowEpoch + 540 // 9m
        stu3.arrival = arr3
        stu3.departure = arr3
        
        tu.stopTimeUpdate = [stu1, stu2, stu3]
        ent1.tripUpdate = tu
        
        // Entity 2: VehiclePosition dwelling at origin terminal (STOPPED_AT, seq 1)
        var ent2 = TransitRealtime_FeedEntity()
        ent2.id = "VP_L_001"
        var vp = TransitRealtime_VehiclePosition()
        vp.trip = trip
        vp.currentStatus = .stoppedAt
        vp.currentStopSequence = 1
        vp.stopID = "L01N"
        ent2.vehicle = vp
        
        feedMessage.entity = [ent1, ent2]
        let data = try feedMessage.serializedData()
        
        // 1. Querying origin terminal (L01)
        let originArrivals = try TransitRealtimeService.shared.parseFeedMessage(
            data: data,
            stopId: "L01",
            targetRouteId: "L",
            referenceDate: refDate
        )
        XCTAssertEqual(originArrivals.count, 1)
        XCTAssertEqual(originArrivals[0].minutes, 3)
        XCTAssertEqual(originArrivals[0].distanceDescription, "At Terminus")
        
        // 2. Querying downstream station 2 stops away (L03) while vehicle is still dwelling at origin
        let downstreamArrivals = try TransitRealtimeService.shared.parseFeedMessage(
            data: data,
            stopId: "L03",
            targetRouteId: "L",
            referenceDate: refDate
        )
        XCTAssertEqual(downstreamArrivals.count, 1)
        XCTAssertEqual(downstreamArrivals[0].minutes, 9)
        XCTAssertEqual(downstreamArrivals[0].distanceDescription, "At Terminus", "Downstream stops must render 'At Terminus' while vehicle is dwelling at origin terminal.")
    }

    func testVehiclePositionTransitionToInTransitTo() throws {
        let nowEpoch: Int64 = 1700000000
        let refDate = Date(timeIntervalSince1970: TimeInterval(nowEpoch))
        
        var feedMessage = TransitRealtime_FeedMessage()
        var header = TransitRealtime_FeedHeader()
        header.gtfsRealtimeVersion = "2.0"
        header.timestamp = UInt64(nowEpoch)
        feedMessage.header = header
        
        var ent1 = TransitRealtime_FeedEntity()
        ent1.id = "TU_L_002"
        var tu = TransitRealtime_TripUpdate()
        var trip = TransitRealtime_TripDescriptor()
        trip.tripID = "TRIP_L_MOVING_002"
        trip.routeID = "L"
        tu.trip = trip
        
        var stu1 = TransitRealtime_TripUpdate.StopTimeUpdate()
        stu1.stopID = "L01N"
        stu1.stopSequence = 1
        var arr1 = TransitRealtime_TripUpdate.StopTimeEvent()
        arr1.time = nowEpoch + 60
        stu1.departure = arr1
        
        var stu2 = TransitRealtime_TripUpdate.StopTimeUpdate()
        stu2.stopID = "L02N"
        stu2.stopSequence = 2
        var arr2 = TransitRealtime_TripUpdate.StopTimeEvent()
        arr2.time = nowEpoch + 240
        stu2.arrival = arr2
        
        var stu3 = TransitRealtime_TripUpdate.StopTimeUpdate()
        stu3.stopID = "L03N"
        stu3.stopSequence = 3
        var arr3 = TransitRealtime_TripUpdate.StopTimeEvent()
        arr3.time = nowEpoch + 420
        stu3.arrival = arr3
        
        tu.stopTimeUpdate = [stu1, stu2, stu3]
        ent1.tripUpdate = tu
        
        // Vehicle has transitioned to IN_TRANSIT_TO from terminal
        var ent2 = TransitRealtime_FeedEntity()
        ent2.id = "VP_L_002"
        var vp = TransitRealtime_VehiclePosition()
        vp.trip = trip
        vp.currentStatus = .inTransitTo
        vp.currentStopSequence = 1
        vp.stopID = "L01N"
        ent2.vehicle = vp
        
        feedMessage.entity = [ent1, ent2]
        let data = try feedMessage.serializedData()
        
        // Downstream stops must now show active stops countdown
        let arrAtL02 = try TransitRealtimeService.shared.parseFeedMessage(
            data: data,
            stopId: "L02",
            targetRouteId: "L",
            referenceDate: refDate
        )
        XCTAssertEqual(arrAtL02[0].distanceDescription, "1 stop away")
        
        let arrAtL03 = try TransitRealtimeService.shared.parseFeedMessage(
            data: data,
            stopId: "L03",
            targetRouteId: "L",
            referenceDate: refDate
        )
        XCTAssertEqual(arrAtL03[0].distanceDescription, "2 stops away")
    }

    func testVehiclePositionAdvancingSequence() throws {
        let nowEpoch: Int64 = 1700000000
        let refDate = Date(timeIntervalSince1970: TimeInterval(nowEpoch))
        
        var feedMessage = TransitRealtime_FeedMessage()
        var header = TransitRealtime_FeedHeader()
        header.gtfsRealtimeVersion = "2.0"
        header.timestamp = UInt64(nowEpoch)
        feedMessage.header = header
        
        var ent1 = TransitRealtime_FeedEntity()
        ent1.id = "TU_L_003"
        var tu = TransitRealtime_TripUpdate()
        var trip = TransitRealtime_TripDescriptor()
        trip.tripID = "TRIP_L_ADVANCING_003"
        trip.routeID = "L"
        tu.trip = trip
        
        var stu1 = TransitRealtime_TripUpdate.StopTimeUpdate()
        stu1.stopID = "L01N"; stu1.stopSequence = 1
        var stu2 = TransitRealtime_TripUpdate.StopTimeUpdate()
        stu2.stopID = "L02N"; stu2.stopSequence = 2
        var arr2 = TransitRealtime_TripUpdate.StopTimeEvent()
        arr2.time = nowEpoch + 120
        stu2.arrival = arr2
        var stu3 = TransitRealtime_TripUpdate.StopTimeUpdate()
        stu3.stopID = "L03N"; stu3.stopSequence = 3
        var arr3 = TransitRealtime_TripUpdate.StopTimeEvent()
        arr3.time = nowEpoch + 300
        stu3.arrival = arr3
        
        tu.stopTimeUpdate = [stu1, stu2, stu3]
        ent1.tripUpdate = tu
        
        // Vehicle has reached sequence 2 (STOPPED_AT L02N)
        var ent2 = TransitRealtime_FeedEntity()
        ent2.id = "VP_L_003"
        var vp = TransitRealtime_VehiclePosition()
        vp.trip = trip
        vp.currentStatus = .stoppedAt
        vp.currentStopSequence = 2
        vp.stopID = "L02N"
        ent2.vehicle = vp
        
        feedMessage.entity = [ent1, ent2]
        let data = try feedMessage.serializedData()
        
        let arrAtL03 = try TransitRealtimeService.shared.parseFeedMessage(
            data: data,
            stopId: "L03",
            targetRouteId: "L",
            referenceDate: refDate
        )
        XCTAssertEqual(arrAtL03[0].distanceDescription, "1 stop away", "Vehicle at sequence 2 should be 1 stop away from sequence 3.")
    }

    func testScheduledFutureDepartureWithoutTelemetry() throws {
        let nowEpoch: Int64 = 1700000000
        let refDate = Date(timeIntervalSince1970: TimeInterval(nowEpoch))
        
        var feedMessage = TransitRealtime_FeedMessage()
        var header = TransitRealtime_FeedHeader()
        header.gtfsRealtimeVersion = "2.0"
        header.timestamp = UInt64(nowEpoch)
        feedMessage.header = header
        
        var ent = TransitRealtime_FeedEntity()
        ent.id = "TU_L_SCHED"
        var tu = TransitRealtime_TripUpdate()
        var trip = TransitRealtime_TripDescriptor()
        trip.tripID = "TRIP_L_SCHED_FUTURE"
        trip.routeID = "L"
        tu.trip = trip
        
        // Origin departure is 15 minutes in the future
        var stu1 = TransitRealtime_TripUpdate.StopTimeUpdate()
        stu1.stopID = "L01N"
        stu1.stopSequence = 1
        var dep1 = TransitRealtime_TripUpdate.StopTimeEvent()
        dep1.time = nowEpoch + 900 // 15m
        stu1.departure = dep1
        
        var stu2 = TransitRealtime_TripUpdate.StopTimeUpdate()
        stu2.stopID = "L03N"
        stu2.stopSequence = 3
        var arr2 = TransitRealtime_TripUpdate.StopTimeEvent()
        arr2.time = nowEpoch + 1200 // 20m
        stu2.arrival = arr2
        
        tu.stopTimeUpdate = [stu1, stu2]
        ent.tripUpdate = tu
        feedMessage.entity = [ent]
        let data = try feedMessage.serializedData()
        
        // Origin query
        let originArr = try TransitRealtimeService.shared.parseFeedMessage(
            data: data,
            stopId: "L01",
            targetRouteId: "L",
            referenceDate: refDate
        )
        XCTAssertEqual(originArr[0].distanceDescription, "Scheduled")
        
        // Downstream query
        let downstreamArr = try TransitRealtimeService.shared.parseFeedMessage(
            data: data,
            stopId: "L03",
            targetRouteId: "L",
            referenceDate: refDate
        )
        XCTAssertEqual(downstreamArr[0].distanceDescription, "Scheduled", "Future departure without active vehicle telemetry should render 'Scheduled'.")
    }

    func testOriginStopIncomingAtAndBoarding() throws {
        let nowEpoch: Int64 = 1700000000
        let refDate = Date(timeIntervalSince1970: TimeInterval(nowEpoch))
        
        var feedMessage = TransitRealtime_FeedMessage()
        var header = TransitRealtime_FeedHeader()
        header.gtfsRealtimeVersion = "2.0"
        header.timestamp = UInt64(nowEpoch)
        feedMessage.header = header
        
        var ent1 = TransitRealtime_FeedEntity()
        ent1.id = "TU_L_004"
        var tu = TransitRealtime_TripUpdate()
        var trip = TransitRealtime_TripDescriptor()
        trip.tripID = "TRIP_L_INCOMING"
        trip.routeID = "L"
        tu.trip = trip
        
        var stu1 = TransitRealtime_TripUpdate.StopTimeUpdate()
        stu1.stopID = "L01N"
        var arr1 = TransitRealtime_TripUpdate.StopTimeEvent()
        arr1.time = nowEpoch + 45 // 45s away
        stu1.arrival = arr1
        tu.stopTimeUpdate = [stu1]
        ent1.tripUpdate = tu
        
        var ent2 = TransitRealtime_FeedEntity()
        ent2.id = "VP_L_004"
        var vp = TransitRealtime_VehiclePosition()
        vp.trip = trip
        vp.currentStatus = .incomingAt
        vp.stopID = "L01N"
        ent2.vehicle = vp
        
        feedMessage.entity = [ent1, ent2]
        let data = try feedMessage.serializedData()
        
        let arrivals = try TransitRealtimeService.shared.parseFeedMessage(
            data: data,
            stopId: "L01",
            targetRouteId: "L",
            referenceDate: refDate
        )
        XCTAssertEqual(arrivals[0].distanceDescription, "Approaching")
    }
}
