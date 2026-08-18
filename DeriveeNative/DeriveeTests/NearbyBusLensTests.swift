import XCTest
import CoreLocation
import SwiftProtobuf
@testable import Derivee

final class NearbyBusLensTests: XCTestCase {
    
    func testBusRouteRecognition() {
        XCTAssertTrue(TransitRealtimeService.SubwayFeed.isBusRoute("M15"))
        XCTAssertTrue(TransitRealtimeService.SubwayFeed.isBusRoute("M15-SBS"))
        XCTAssertTrue(TransitRealtimeService.SubwayFeed.isBusRoute("B62"))
        XCTAssertTrue(TransitRealtimeService.SubwayFeed.isBusRoute("Bx1"))
        XCTAssertTrue(TransitRealtimeService.SubwayFeed.isBusRoute("Q32"))
        XCTAssertTrue(TransitRealtimeService.SubwayFeed.isBusRoute("S79"))
        
        XCTAssertFalse(TransitRealtimeService.SubwayFeed.isBusRoute("1"))
        XCTAssertFalse(TransitRealtimeService.SubwayFeed.isBusRoute("A"))
        XCTAssertFalse(TransitRealtimeService.SubwayFeed.isBusRoute("L"))
        XCTAssertFalse(TransitRealtimeService.SubwayFeed.isBusRoute("G"))
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
        
        // Ensure stops are sorted by proximity ascending
        for i in 0..<(stops.count - 1) {
            XCTAssertLessThanOrEqual(stops[i].distanceMeters, stops[i + 1].distanceMeters, "Bus stops must be sorted by distance ascending.")
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
        XCTAssertEqual(arrivals[0].direction, "Southbound")
    }
    
    @MainActor
    func testTrackingEngineImmediatelyUpdatesLastKnownLocationOnWarmupFix() async throws {
        let dbManager = SpatialDatabaseManager.makeForTesting(inMemory: true)
        let locationProvider = MockLocationProvider()
        let engine = AmbientTrackingEngine(locationProvider: locationProvider, databaseManager: dbManager)
        
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
    }
    
    func testNearbyBusStopQueryWilliamsburg() async throws {
        let bedfordWilliamsburg = CLLocationCoordinate2D(latitude: 40.7143, longitude: -73.9613)
        let stops = try await SpatialDatabaseManager.shared.fetchNearbyBusStops(coordinate: bedfordWilliamsburg, radiusMeters: 400.0)
        
        XCTAssertFalse(stops.isEmpty, "Should find bus stops near Bedford Ave Williamsburg.")
        for stop in stops {
            XCTAssertLessThanOrEqual(stop.distanceMeters, 400.0)
        }
    }
}
