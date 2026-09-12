import XCTest
@testable import Derivee

final class StatenIslandRailwayTests: XCTestCase {
    
    // MARK: - 1. Feed Endpoint Resolution
    
    func testSIRFeedUrlResolution() {
        // Both "SI" and "SIR" must map to .sir endpoint (nyct%2Fgtfs-si), never defaulting to .l
        let feedSI = TransitRealtimeService.SubwayFeed.feed(for: "SI")
        let feedSIR = TransitRealtimeService.SubwayFeed.feed(for: "SIR")
        
        XCTAssertEqual(feedSI, .sir)
        XCTAssertEqual(feedSIR, .sir)
        XCTAssertEqual(feedSI.rawValue, "https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/nyct%2Fgtfs-si")
        XCTAssertEqual(feedSIR.rawValue, "https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/nyct%2Fgtfs-si")
    }
    
    // MARK: - 2. Canonical Route Identity & Official MTA SIR Blue
    
    func testSIRRouteIdentityAndOfficialColor() {
        let infoSI = TransitRouteData.lineInfo(for: "SI")
        let infoSIR = TransitRouteData.lineInfo(for: "SIR")
        
        // Both must be branded "SIR"
        XCTAssertEqual(infoSI.name, "SIR")
        XCTAssertEqual(infoSIR.name, "SIR")
        
        // Official MTA SIR Blue #08179C (not light blue #0078C6 and not amber fallthrough #FFB300)
        XCTAssertEqual(infoSI.colorHex, "#08179C")
        XCTAssertEqual(infoSIR.colorHex, "#08179C")
        XCTAssertEqual(infoSI.textColorHex, "#FFFFFF")
        XCTAssertEqual(infoSIR.textColorHex, "#FFFFFF")
        
        // Rail classification
        XCTAssertEqual(infoSI.modalClass, .subway)
        XCTAssertEqual(infoSIR.modalClass, .subway)
        XCTAssertEqual(infoSI.routeType, 2)
        XCTAssertEqual(infoSIR.routeType, 2)
    }
    
    func testSIRRouteInference() {
        XCTAssertEqual(TransitRouteData.inferRouteId(from: "SI"), "SIR")
        XCTAssertEqual(TransitRouteData.inferRouteId(from: "SIR"), "SIR")
        XCTAssertEqual(TransitRouteData.inferRouteId(from: "S31"), "SIR")
        XCTAssertEqual(TransitRouteData.inferRouteId(from: "S09"), "SIR")
        XCTAssertEqual(TransitRouteData.inferRouteId(from: "S28"), "SIR")
    }
    
    // MARK: - 3. Standard Terminals & Name Resolution
    
    func testSubwayStationRegistrySIRTerminals() {
        // Verify "SI" and "SIR" standard terminals in SubwayStationRegistry
        let terminalsSI = SubwayStationRegistry.standardTerminals["SI"]
        let terminalsSIR = SubwayStationRegistry.standardTerminals["SIR"]
        
        XCTAssertNotNil(terminalsSI)
        XCTAssertNotNil(terminalsSIR)
        
        XCTAssertTrue(terminalsSI?.north.contains("S31") == true)
        XCTAssertTrue(terminalsSI?.south.contains("S09") == true)
        XCTAssertTrue(terminalsSIR?.north.contains("S31") == true)
        XCTAssertTrue(terminalsSIR?.south.contains("S09") == true)
        
        // Terminal name resolution
        XCTAssertEqual(SubwayStationRegistry.resolveStationName(for: "S31"), "St George")
        XCTAssertEqual(SubwayStationRegistry.resolveStationName(for: "S31N"), "St George")
        XCTAssertEqual(SubwayStationRegistry.resolveStationName(for: "S09"), "Tottenville")
        XCTAssertEqual(SubwayStationRegistry.resolveStationName(for: "S09S"), "Tottenville")
        
        // Default terminal inference for route "SI" and "SIR"
        let northDefSI = SubwayStationRegistry.defaultTerminal(route: "SI", isNorthbound: true)
        let southDefSI = SubwayStationRegistry.defaultTerminal(route: "SI", isNorthbound: false)
        XCTAssertEqual(northDefSI.stopId, "S31")
        XCTAssertEqual(northDefSI.name, "St George")
        XCTAssertEqual(southDefSI.stopId, "S09")
        XCTAssertEqual(southDefSI.name, "Tottenville")
        
        let northDefSIR = SubwayStationRegistry.defaultTerminal(route: "SIR", isNorthbound: true)
        let southDefSIR = SubwayStationRegistry.defaultTerminal(route: "SIR", isNorthbound: false)
        XCTAssertEqual(northDefSIR.stopId, "S31")
        XCTAssertEqual(northDefSIR.name, "St George")
        XCTAssertEqual(southDefSIR.stopId, "S09")
        XCTAssertEqual(southDefSIR.name, "Tottenville")
    }
    
    // MARK: - 4. Direction Labels & Modulo Mapping
    
    func testSIRDirectionLabels() {
        var trip = TransitRealtime_TripDescriptor()
        trip.routeID = "SI"
        var tu = TransitRealtime_TripUpdate()
        tu.trip = trip
        
        // Northbound direction label (Inbound without period)
        let nbSI = TransitRealtimeService.shared.resolveDirection(tripUpdate: tu, line: "SI", stopId: "S31N")
        let nbSIR = TransitRealtimeService.shared.resolveDirection(tripUpdate: tu, line: "SIR", stopId: "S31N")
        XCTAssertEqual(nbSI, "Inbound (St George)")
        XCTAssertEqual(nbSIR, "Inbound (St George)")
        
        // Southbound direction label (Outbound)
        let sbSI = TransitRealtimeService.shared.resolveDirection(tripUpdate: tu, line: "SI", stopId: "S09S")
        let sbSIR = TransitRealtimeService.shared.resolveDirection(tripUpdate: tu, line: "SIR", stopId: "S09S")
        XCTAssertEqual(sbSI, "Outbound (Tottenville)")
        XCTAssertEqual(sbSIR, "Outbound (Tottenville)")
    }
    
    func testResolvedDirectionId() {
        let arrInbound = SpatialDatabaseManager.ArrivalInfo(
            line: "SIR", destination: "St George", minutes: 5, direction: "Inbound (St George)"
        )
        XCTAssertEqual(arrInbound.resolvedDirectionId, 0)
        
        let arrOutbound = SpatialDatabaseManager.ArrivalInfo(
            line: "SIR", destination: "Tottenville", minutes: 12, direction: "Outbound (Tottenville)"
        )
        XCTAssertEqual(arrOutbound.resolvedDirectionId, 1)
        
        let arrBareTottenville = SpatialDatabaseManager.ArrivalInfo(
            line: "SIR", destination: "Tottenville", minutes: 12, direction: "Tottenville"
        )
        XCTAssertEqual(arrBareTottenville.resolvedDirectionId, 1)
        
        let arrBareStGeorge = SpatialDatabaseManager.ArrivalInfo(
            line: "SIR", destination: "St George", minutes: 5, direction: "St George"
        )
        XCTAssertEqual(arrBareStGeorge.resolvedDirectionId, 0)
    }
    
    // MARK: - 5. Terminal Directional Filtering
    
    func testStGeorgeTerminalDirectionalFiltering() async throws {
        // 1. Available directions at St George must suppress Direction 0 (Inbound/Northbound)
        let dirs = try await SpatialDatabaseManager.shared.fetchAvailableDirections(for: "S31", routeId: "SI")
        XCTAssertEqual(dirs, Set([1]), "St George terminal must only offer Outbound (Tottenville) departures")
        
        // 2. generateArrivals at St George must only contain the Outbound Tottenville departure
        let arrivals = SpatialDatabaseManager.shared.generateArrivals(for: "SI", stopId: "S31")
        XCTAssertEqual(arrivals.count, 1)
        XCTAssertEqual(arrivals.first?.destination, "Tottenville")
        XCTAssertEqual(arrivals.first?.direction, "Outbound (Tottenville)")
        XCTAssertEqual(arrivals.first?.resolvedDirectionId, 1)
        
        // 3. fetchTimetableResult at St George for Direction 0 must return 0 departures (suppressed)
        let resultDir0 = try await SpatialDatabaseManager.shared.fetchTimetableResult(for: "S31", routeId: "SI", directionId: 0)
        let totalDepsDir0 = resultDir0.records.reduce(0) { $0 + $1.departures.count }
        XCTAssertEqual(totalDepsDir0, 0, "Northbound departures from St George terminal must be strictly 0")
        
        // 4. Direction 1 at St George must have scheduled departures
        let resultDir1 = try await SpatialDatabaseManager.shared.fetchTimetableResult(for: "S31", routeId: "SI", directionId: 1)
        let totalDepsDir1 = resultDir1.records.reduce(0) { $0 + $1.departures.count }
        XCTAssertGreaterThan(totalDepsDir1, 0, "Outbound departures from St George must be populated")
    }
    
    func testTottenvilleTerminalDirectionalFiltering() async throws {
        // 1. Available directions at Tottenville must suppress Direction 1 (Outbound/Southbound)
        let dirs = try await SpatialDatabaseManager.shared.fetchAvailableDirections(for: "S09", routeId: "SI")
        XCTAssertEqual(dirs, Set([0]), "Tottenville terminal must only offer Inbound (St George) departures")
        
        // 2. generateArrivals at Tottenville must only contain the Inbound St George departure
        let arrivals = SpatialDatabaseManager.shared.generateArrivals(for: "SI", stopId: "S09")
        XCTAssertEqual(arrivals.count, 1)
        XCTAssertEqual(arrivals.first?.destination, "St George")
        XCTAssertEqual(arrivals.first?.direction, "Inbound (St George)")
        XCTAssertEqual(arrivals.first?.resolvedDirectionId, 0)
        
        // 3. fetchTimetableResult at Tottenville for Direction 1 must return 0 departures (suppressed)
        let resultDir1 = try await SpatialDatabaseManager.shared.fetchTimetableResult(for: "S09", routeId: "SI", directionId: 1)
        let totalDepsDir1 = resultDir1.records.reduce(0) { $0 + $1.departures.count }
        XCTAssertEqual(totalDepsDir1, 0, "Southbound departures from Tottenville terminal must be strictly 0")
        
        // 4. Direction 0 at Tottenville must have scheduled departures
        let resultDir0 = try await SpatialDatabaseManager.shared.fetchTimetableResult(for: "S09", routeId: "SI", directionId: 0)
        let totalDepsDir0 = resultDir0.records.reduce(0) { $0 + $1.departures.count }
        XCTAssertGreaterThan(totalDepsDir0, 0, "Inbound departures from Tottenville must be populated")
    }
    
    func testIntermediateStationOffersBothDirections() async throws {
        // S28 (Clifton) is an intermediate station on Staten Island Railway
        let arrivals = SpatialDatabaseManager.shared.generateArrivals(for: "SI", stopId: "S28")
        XCTAssertEqual(arrivals.count, 2)
        
        let destinations = Set(arrivals.map { $0.destination })
        XCTAssertTrue(destinations.contains("St George"))
        XCTAssertTrue(destinations.contains("Tottenville"))
    }
    
    func testLiveArrivalsTerminalFiltering() throws {
        let referenceDate = Date(timeIntervalSince1970: 1700000000)
        
        var feedMessage = TransitRealtime_FeedMessage()
        var header = TransitRealtime_FeedHeader()
        header.gtfsRealtimeVersion = "2.0"
        header.timestamp = 1700000000
        feedMessage.header = header
        
        // Entity 1: Inbound train terminating at St George (destination St George)
        var entityInbound = TransitRealtime_FeedEntity()
        entityInbound.id = "trip_inbound_terminating"
        var tuInbound = TransitRealtime_TripUpdate()
        var tripInbound = TransitRealtime_TripDescriptor()
        tripInbound.tripID = "SIR_INBOUND_01"
        tripInbound.routeID = "SI"
        tuInbound.trip = tripInbound
        
        var stuInboundPrev = TransitRealtime_TripUpdate.StopTimeUpdate()
        stuInboundPrev.stopID = "S30N" // Tompkinsville
        var arrPrev = TransitRealtime_TripUpdate.StopTimeEvent()
        arrPrev.time = 1700000100
        stuInboundPrev.arrival = arrPrev
        
        var stuInboundTerm = TransitRealtime_TripUpdate.StopTimeUpdate()
        stuInboundTerm.stopID = "S31N" // St George arrival platform
        var arrTerm = TransitRealtime_TripUpdate.StopTimeEvent()
        arrTerm.time = 1700000300
        stuInboundTerm.arrival = arrTerm
        
        tuInbound.stopTimeUpdate = [stuInboundPrev, stuInboundTerm]
        entityInbound.tripUpdate = tuInbound
        
        // Entity 2: Outbound train originating at St George (destination Tottenville)
        var entityOutbound = TransitRealtime_FeedEntity()
        entityOutbound.id = "trip_outbound_origin"
        var tuOutbound = TransitRealtime_TripUpdate()
        var tripOutbound = TransitRealtime_TripDescriptor()
        tripOutbound.tripID = "SIR_OUTBOUND_01"
        tripOutbound.routeID = "SI"
        tuOutbound.trip = tripOutbound
        
        var stuOutboundOrig = TransitRealtime_TripUpdate.StopTimeUpdate()
        stuOutboundOrig.stopID = "S31S" // St George departure platform
        var depOrig = TransitRealtime_TripUpdate.StopTimeEvent()
        depOrig.time = 1700000400
        stuOutboundOrig.departure = depOrig
        
        var stuOutboundNext = TransitRealtime_TripUpdate.StopTimeUpdate()
        stuOutboundNext.stopID = "S09S" // Tottenville terminus
        var arrNext = TransitRealtime_TripUpdate.StopTimeEvent()
        arrNext.time = 1700002000
        stuOutboundNext.arrival = arrNext
        
        tuOutbound.stopTimeUpdate = [stuOutboundOrig, stuOutboundNext]
        entityOutbound.tripUpdate = tuOutbound
        
        feedMessage.entity = [entityInbound, entityOutbound]
        let data = try feedMessage.serializedData()
        
        // Parse feed for stop S31 with target route "SIR" (aliasing test)
        let arrivals = try TransitRealtimeService.shared.parseFeedMessage(
            data: data,
            stopId: "S31",
            targetRouteId: "SIR",
            referenceDate: referenceDate
        )
        
        // Only the outbound trip to Tottenville should be present!
        // The terminating inbound trip must be suppressed by terminal directional filtering.
        XCTAssertEqual(arrivals.count, 1)
        XCTAssertEqual(arrivals.first?.destination, "SIR to Tottenville")
        XCTAssertEqual(arrivals.first?.direction, "Outbound (Tottenville)")
    }
}
