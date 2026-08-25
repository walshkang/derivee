import XCTest
import CoreLocation
import SwiftProtobuf
@testable import Derivee

final class NearbyBusLensTests: XCTestCase {
    
    func testBusRouteRecognition() {
        XCTAssertTrue(TransitRealtimeService.SubwayFeed.isBusRoute("M15"))
        XCTAssertTrue(TransitRealtimeService.SubwayFeed.isBusRoute("M15-SBS"))
        XCTAssertTrue(TransitRealtimeService.SubwayFeed.isBusRoute("M1"))
        XCTAssertTrue(TransitRealtimeService.SubwayFeed.isBusRoute("B62"))
        XCTAssertTrue(TransitRealtimeService.SubwayFeed.isBusRoute("Bx1"))
        XCTAssertTrue(TransitRealtimeService.SubwayFeed.isBusRoute("Bx12-SBS"))
        XCTAssertTrue(TransitRealtimeService.SubwayFeed.isBusRoute("Q32"))
        XCTAssertTrue(TransitRealtimeService.SubwayFeed.isBusRoute("S79"))
        XCTAssertTrue(TransitRealtimeService.SubwayFeed.isBusRoute("SIM1"))
        XCTAssertTrue(TransitRealtimeService.SubwayFeed.isBusRoute("BUS_001"))
        
        // Subway lines must never be classified as buses
        XCTAssertFalse(TransitRealtimeService.SubwayFeed.isBusRoute("1"))
        XCTAssertFalse(TransitRealtimeService.SubwayFeed.isBusRoute("2"))
        XCTAssertFalse(TransitRealtimeService.SubwayFeed.isBusRoute("3"))
        XCTAssertFalse(TransitRealtimeService.SubwayFeed.isBusRoute("4"))
        XCTAssertFalse(TransitRealtimeService.SubwayFeed.isBusRoute("5"))
        XCTAssertFalse(TransitRealtimeService.SubwayFeed.isBusRoute("6"))
        XCTAssertFalse(TransitRealtimeService.SubwayFeed.isBusRoute("6X"))
        XCTAssertFalse(TransitRealtimeService.SubwayFeed.isBusRoute("7"))
        XCTAssertFalse(TransitRealtimeService.SubwayFeed.isBusRoute("7X"))
        XCTAssertFalse(TransitRealtimeService.SubwayFeed.isBusRoute("A"))
        XCTAssertFalse(TransitRealtimeService.SubwayFeed.isBusRoute("B"))
        XCTAssertFalse(TransitRealtimeService.SubwayFeed.isBusRoute("C"))
        XCTAssertFalse(TransitRealtimeService.SubwayFeed.isBusRoute("D"))
        XCTAssertFalse(TransitRealtimeService.SubwayFeed.isBusRoute("E"))
        XCTAssertFalse(TransitRealtimeService.SubwayFeed.isBusRoute("F"))
        XCTAssertFalse(TransitRealtimeService.SubwayFeed.isBusRoute("FX"))
        XCTAssertFalse(TransitRealtimeService.SubwayFeed.isBusRoute("G"))
        XCTAssertFalse(TransitRealtimeService.SubwayFeed.isBusRoute("J"))
        XCTAssertFalse(TransitRealtimeService.SubwayFeed.isBusRoute("L"))
        XCTAssertFalse(TransitRealtimeService.SubwayFeed.isBusRoute("M"))
        XCTAssertFalse(TransitRealtimeService.SubwayFeed.isBusRoute("N"))
        XCTAssertFalse(TransitRealtimeService.SubwayFeed.isBusRoute("Q"))
        XCTAssertFalse(TransitRealtimeService.SubwayFeed.isBusRoute("R"))
        XCTAssertFalse(TransitRealtimeService.SubwayFeed.isBusRoute("S"))
        XCTAssertFalse(TransitRealtimeService.SubwayFeed.isBusRoute("W"))
        XCTAssertFalse(TransitRealtimeService.SubwayFeed.isBusRoute("Z"))
        XCTAssertFalse(TransitRealtimeService.SubwayFeed.isBusRoute("SIR"))
    }
    
    func testBusFeedUrlResolution() {
        XCTAssertEqual(TransitRealtimeService.SubwayFeed.feed(for: "M15"), .bus)
        XCTAssertEqual(TransitRealtimeService.SubwayFeed.feed(for: "B62"), .bus)
        XCTAssertEqual(TransitRealtimeService.SubwayFeed.feed(for: "Bx1"), .bus)
    }
    
    func testNearbyBusStopQuery() async throws {
        let unionSq = CLLocationCoordinate2D(latitude: 40.7350, longitude: -73.9905)
        let stops = try await SpatialDatabaseManager.shared.fetchNearbyBusStops(coordinate: unionSq, radiusMeters: 400.0)
        
        XCTAssertFalse(stops.isEmpty, "Should find bus stops within 400m of Union Square.")
        XCTAssertLessThanOrEqual(stops.count, 8, "Should cap returned nearby bus stops.")
        
        if stops.count > 1 {
            for i in 0..<(stops.count - 1) {
                XCTAssertLessThanOrEqual(stops[i].distanceMeters, stops[i + 1].distanceMeters, "Bus stops must be sorted by distance ascending.")
            }
        }
        
        // Verify stop properties
        for stop in stops {
            XCTAssertFalse(stop.name.isEmpty)
            XCTAssertFalse(stop.routes.isEmpty)
            XCTAssertLessThanOrEqual(stop.distanceMeters, 400.0, "All returned stops must be within 400m radius.")
        }
    }
    
    func testBusStopDetailsFetching() async throws {
        let details = try await SpatialDatabaseManager.shared.fetchStopDetails(for: "BUS_001")
        XCTAssertEqual(details.routeType, 3, "Route type should be 3 for bus stops.")
        XCTAssertFalse(details.arrivals.isEmpty, "Bus stop details should contain arrivals.")
        XCTAssertNotNil(details.arrivals.first?.direction, "Bus arrival should have direction.")
    }
    
    func testBusProtobufDeserializationWithDirection() throws {
        var feedMessage = TransitRealtime_FeedMessage()
        var header = TransitRealtime_FeedHeader()
        header.gtfsRealtimeVersion = "2.0"
        header.timestamp = 1700000000
        feedMessage.header = header
        
        var entity = TransitRealtime_FeedEntity()
        entity.id = "bus_trip_1"
        
        var tripUpdate = TransitRealtime_TripUpdate()
        var trip = TransitRealtime_TripDescriptor()
        trip.tripID = "trip_M15_001"
        trip.routeID = "M15"
        tripUpdate.trip = trip
        
        let now = Date(timeIntervalSince1970: 1700000000)
        
        var stopUpdate = TransitRealtime_TripUpdate.StopTimeUpdate()
        stopUpdate.stopID = "M15_14ST_S"
        var arrival = TransitRealtime_TripUpdate.StopTimeEvent()
        arrival.time = 1700000000 + 240 // 4 min later
        stopUpdate.arrival = arrival
        
        tripUpdate.stopTimeUpdate = [stopUpdate]
        entity.tripUpdate = tripUpdate
        feedMessage.entity = [entity]
        
        let data = try feedMessage.serializedData()
        let arrivals = try TransitRealtimeService.shared.parseFeedMessage(
            data: data,
            stopId: "M15_14ST_S",
            targetRouteId: "M15",
            referenceDate: now
        )
        
        XCTAssertEqual(arrivals.count, 1)
        XCTAssertEqual(arrivals[0].line, "M15")
        XCTAssertEqual(arrivals[0].minutes, 4)
        XCTAssertTrue(arrivals[0].direction?.contains("Southbound") == true)
        XCTAssertEqual(arrivals[0].destination, "South Ferry - Whitehall St")
    }
    
    func testM10BusTerminalResolution() {
        let (northDest, northDir) = TransitRealtimeService.resolveBusDestination(routeId: "M10", directionId: 0)
        XCTAssertEqual(northDest, "Harlem - 159 St / Frederick Douglass Blvd")
        XCTAssertEqual(northDir, "Uptown & Northbound")
        
        let (southDest, southDir) = TransitRealtimeService.resolveBusDestination(routeId: "M10", directionId: 1)
        XCTAssertEqual(southDest, "Columbus Circle - 58 St / 8 Ave")
        XCTAssertEqual(southDir, "Downtown & Southbound")
    }
    
    func testBusRealtimeHorizonClampingRejects100MinuteArrivals() throws {
        var feedMessage = TransitRealtime_FeedMessage()
        var header = TransitRealtime_FeedHeader()
        header.gtfsRealtimeVersion = "2.0"
        header.timestamp = 1700000000
        feedMessage.header = header
        
        var entity = TransitRealtime_FeedEntity()
        entity.id = "trip_future_100min"
        
        var tripUpdate = TransitRealtime_TripUpdate()
        var trip = TransitRealtime_TripDescriptor()
        trip.tripID = "trip_M10_future"
        trip.routeID = "M10"
        tripUpdate.trip = trip
        
        let now = Date(timeIntervalSince1970: 1700000000)
        
        var stopUpdate = TransitRealtime_TripUpdate.StopTimeUpdate()
        stopUpdate.stopID = "401014"
        var arrival = TransitRealtime_TripUpdate.StopTimeEvent()
        arrival.time = 1700000000 + 6000 // 100 minutes later
        stopUpdate.arrival = arrival
        
        tripUpdate.stopTimeUpdate = [stopUpdate]
        entity.tripUpdate = tripUpdate
        feedMessage.entity = [entity]
        
        let data = try feedMessage.serializedData()
        let arrivals = try TransitRealtimeService.shared.parseFeedMessage(
            data: data,
            stopId: "401014",
            targetRouteId: "M10",
            referenceDate: now
        )
        
        XCTAssertTrue(arrivals.isEmpty, "Arrivals 100 minutes away must be clamped and rejected from live arrival stream.")
    }
    
    func testNoCrossRoutePrefixPollution() throws {
        var feedMessage = TransitRealtime_FeedMessage()
        var header = TransitRealtime_FeedHeader()
        header.gtfsRealtimeVersion = "2.0"
        header.timestamp = 1700000000
        feedMessage.header = header
        
        var entity = TransitRealtime_FeedEntity()
        entity.id = "trip_M104"
        
        var tripUpdate = TransitRealtime_TripUpdate()
        var trip = TransitRealtime_TripDescriptor()
        trip.tripID = "trip_M104_001"
        trip.routeID = "M104"
        tripUpdate.trip = trip
        
        let now = Date(timeIntervalSince1970: 1700000000)
        
        var stopUpdate = TransitRealtime_TripUpdate.StopTimeUpdate()
        stopUpdate.stopID = "401348"
        var arrival = TransitRealtime_TripUpdate.StopTimeEvent()
        arrival.time = 1700000000 + 300 // 5 min later
        stopUpdate.arrival = arrival
        
        tripUpdate.stopTimeUpdate = [stopUpdate]
        entity.tripUpdate = tripUpdate
        feedMessage.entity = [entity]
        
        let data = try feedMessage.serializedData()
        // Querying for target M10 must NOT match M104 trip
        let arrivals = try TransitRealtimeService.shared.parseFeedMessage(
            data: data,
            stopId: "401348",
            targetRouteId: "M10",
            referenceDate: now
        )
        
        XCTAssertTrue(arrivals.isEmpty, "Querying for M10 should not match M104 trip due to prefix collision.")
    }
    
    func testSubwayPlatformsExcludedFromBusLens() {
        let dbManager = SpatialDatabaseManager.shared
        XCTAssertTrue(dbManager.isSubwayPlatformId("125N"))
        XCTAssertTrue(dbManager.isSubwayPlatformId("125S"))
        XCTAssertTrue(dbManager.isSubwayPlatformId("A24N"))
        XCTAssertTrue(dbManager.isSubwayPlatformId("L03N"))
        XCTAssertTrue(dbManager.isSubwayPlatformId("R14S"))
        
        XCTAssertFalse(dbManager.isSubwayPlatformId("401014"))
        XCTAssertFalse(dbManager.isSubwayPlatformId("401348"))
        XCTAssertFalse(dbManager.isSubwayPlatformId("BUS_001"))
        XCTAssertFalse(dbManager.isSubwayPlatformId("STOP_WILLIS"))
    }
    
    @MainActor
    func testTrackingEngineImmediatelyUpdatesLastKnownLocationOnWarmupFix() async throws {
        let suite = "com.derivee.tests.\(UUID().uuidString)"
        let userDefaults = UserDefaults(suiteName: suite)!
        let dbManager = SpatialDatabaseManager.makeForTesting(inMemory: true)
        let locationProvider = MockLocationProvider()
        let engine = AmbientTrackingEngine(locationProvider: locationProvider, databaseManager: dbManager, userDefaults: userDefaults)
        
        XCTAssertNil(engine.lastKnownLocation, "Initial lastKnownLocation should be nil before fixes.")
        
        engine.startTracking()
        
        // Single fix (Warmup 1/2)
        let singleFix = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 40.7143, longitude: -73.9613),
            altitude: 0,
            horizontalAccuracy: 12,
            verticalAccuracy: 5,
            timestamp: Date()
        )
        locationProvider.yield(location: singleFix)
        
        // Give runloop time to process
        try await Task.sleep(nanoseconds: 100_000_000)
        
        XCTAssertNotNil(engine.lastKnownLocation, "Engine should immediately update lastKnownLocation on first valid fix even during warmup.")
        XCTAssertEqual(engine.lastKnownLocation?.coordinate.latitude ?? 0, 40.7143, accuracy: 0.0001)
        XCTAssertEqual(engine.lastKnownLocation?.coordinate.longitude ?? 0, -73.9613, accuracy: 0.0001)
        
        await engine.stopTracking()
        locationProvider.finish()
        userDefaults.removePersistentDomain(forName: suite)
    }
    
    func testNearbyBusStopQueryWilliamsburg() async throws {
        let bedfordWilliamsburg = CLLocationCoordinate2D(latitude: 40.7143, longitude: -73.9613)
        let stops = try await SpatialDatabaseManager.shared.fetchNearbyBusStops(coordinate: bedfordWilliamsburg, radiusMeters: 400.0)
        
        XCTAssertFalse(stops.isEmpty, "Should find bus stops near Bedford Ave Williamsburg.")
        for stop in stops {
            XCTAssertLessThanOrEqual(stop.distanceMeters, 400.0)
        }
    }
    
    func testDistinctStopDetailsForDifferentStops() async throws {
        let details1 = try await SpatialDatabaseManager.shared.fetchStopDetails(for: "BUS_001")
        let details2 = try await SpatialDatabaseManager.shared.fetchStopDetails(for: "BUS_002")
        let details3 = try await SpatialDatabaseManager.shared.fetchStopDetails(for: "BUS_003")
        
        XCTAssertNotEqual(details1.name, details2.name, "BUS_001 and BUS_002 must have distinct stop names.")
        XCTAssertNotEqual(details2.name, details3.name, "BUS_002 and BUS_003 must have distinct stop names.")
        XCTAssertEqual(details1.name, "1 Av & E 14 St")
        XCTAssertEqual(details2.name, "E 14 St & 2 Av")
        XCTAssertEqual(details3.name, "1 Av & E 18 St")
    }
    
    func testRealBusStopsContainExactRoutes() async throws {
        let unionSq = CLLocationCoordinate2D(latitude: 40.7350, longitude: -73.9905)
        let stops = try await SpatialDatabaseManager.shared.fetchNearbyBusStops(coordinate: unionSq, radiusMeters: 400.0)
        
        XCTAssertFalse(stops.isEmpty)
        for stop in stops {
            XCTAssertFalse(stop.routes.isEmpty, "Stop \(stop.name) must have mapped routes.")
            XCTAssertFalse(stop.id.isEmpty)
        }
        
        // Fetch details for the first real stop
        let firstStop = stops[0]
        let details = try await SpatialDatabaseManager.shared.fetchStopDetails(for: firstStop.id)
        XCTAssertEqual(details.name, firstStop.name)
        XCTAssertEqual(details.routeType, 3)
    }
    
    func testDynamicProximitySortingRecalculation() {
        let stopA = SpatialDatabaseManager.NearbyBusStop(
            id: "A",
            name: "Stop A",
            coordinate: CLLocationCoordinate2D(latitude: 40.7300, longitude: -73.9900),
            distanceMeters: 100,
            routes: ["M1"],
            direction: "Northbound"
        )
        let stopB = SpatialDatabaseManager.NearbyBusStop(
            id: "B",
            name: "Stop B",
            coordinate: CLLocationCoordinate2D(latitude: 40.7350, longitude: -73.9900),
            distanceMeters: 200,
            routes: ["M2"],
            direction: "Southbound"
        )
        
        var list = [stopA, stopB]
        XCTAssertEqual(list[0].id, "A")
        
        // User moves to 40.7360 (much closer to Stop B)
        let newLocation = CLLocation(latitude: 40.7360, longitude: -73.9900)
        var updatedList = list.map { stop in
            let loc = CLLocation(latitude: stop.coordinate.latitude, longitude: stop.coordinate.longitude)
            return SpatialDatabaseManager.NearbyBusStop(
                id: stop.id,
                name: stop.name,
                coordinate: stop.coordinate,
                distanceMeters: newLocation.distance(from: loc),
                routes: stop.routes,
                direction: stop.direction
            )
        }
        updatedList.sort { $0.distanceMeters < $1.distanceMeters }
        
        XCTAssertEqual(updatedList[0].id, "B", "Stop B should now be first because user is closer to Stop B.")
        XCTAssertLessThan(updatedList[0].distanceMeters, updatedList[1].distanceMeters)
    }
    
    func testSparseLocationReturnsEmptyWithoutDrift() async throws {
        // Location in the middle of Jamaica Bay far from any bus stops (> 2km)
        let remoteWater = CLLocationCoordinate2D(latitude: 40.6120, longitude: -73.8350)
        let stops = try await SpatialDatabaseManager.shared.fetchNearbyBusStops(coordinate: remoteWater, radiusMeters: 400.0)
        
        XCTAssertTrue(stops.isEmpty, "Sparse coordinates without bus stops must return empty list without fabricating drifting fake stops.")
    }
}
