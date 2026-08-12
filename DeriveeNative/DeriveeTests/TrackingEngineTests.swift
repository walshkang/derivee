import XCTest
import CoreLocation
@testable import Derivee

final class MockLocationProvider: LocationProvider, @unchecked Sendable {
    private let continuation: AsyncStream<CLLocation>.Continuation
    let updates: AsyncStream<CLLocation>
    
    init() {
        let (stream, cont) = AsyncStream.makeStream(of: CLLocation.self)
        self.updates = stream
        self.continuation = cont
    }
    
    func yield(location: CLLocation) {
        continuation.yield(location)
    }
    
    func finish() {
        continuation.finish()
    }
}

@MainActor
final class TrackingEngineTests: XCTestCase {
    
    var dbManager: SpatialDatabaseManager!
    var locationProvider: MockLocationProvider!
    var engine: AmbientTrackingEngine!
    
    override func setUpWithError() throws {
        dbManager = SpatialDatabaseManager(inMemory: true)
        locationProvider = MockLocationProvider()
        engine = AmbientTrackingEngine(locationProvider: locationProvider, databaseManager: dbManager)
    }
    
    override func tearDown() async throws {
        await engine.stopTracking()
        locationProvider.finish()
    }
    
    func testValidWalkUnlocksHexes() async throws {
        engine.startTracking()
        
        let startDate = Date()
        
        // Columbus circle to central park points, spaced by 5 seconds
        let points = [
            CLLocation(coordinate: CLLocationCoordinate2D(latitude: 40.768075, longitude: -73.981897),
                       altitude: 0, horizontalAccuracy: 5, verticalAccuracy: 5, timestamp: startDate),
            CLLocation(coordinate: CLLocationCoordinate2D(latitude: 40.768344, longitude: -73.981581),
                       altitude: 0, horizontalAccuracy: 5, verticalAccuracy: 5, timestamp: startDate.addingTimeInterval(5)),
            CLLocation(coordinate: CLLocationCoordinate2D(latitude: 40.768614, longitude: -73.981266),
                       altitude: 0, horizontalAccuracy: 5, verticalAccuracy: 5, timestamp: startDate.addingTimeInterval(10))
        ]
        
        for point in points {
            locationProvider.yield(location: point)
        }
        
        // Give detached task time to process H3 and write to DB
        try await Task.sleep(nanoseconds: 200_000_000)
        
        let count = try await dbManager.dbWriter.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM explored_hexes") ?? 0
        }
        
        XCTAssertGreaterThan(count, 0, "Valid walk should unlock hexes in the database.")
        
        // ADDED: Test the reactive pipeline (SpatialStore)
        let store = SpatialStore(
            dbManager: dbManager,
            liveUpdatePriority: .userInitiated,
            observationScheduler: .immediate
        )
        
        // Wait for ValueObservation to fire
        try await Task.sleep(nanoseconds: 500_000_000)
        
        XCTAssertGreaterThan(store.exploredHexes.count, 0, "SpatialStore should reactively update exploredHexes")
        XCTAssertNotNil(store.currentFogShape, "SpatialStore should generate a new fog shape")
    }
    
    func testDriftGateRejectsNoise() async throws {
        engine.startTracking()
        
        let startDate = Date()
        
        let point1 = CLLocation(coordinate: CLLocationCoordinate2D(latitude: 40.768075, longitude: -73.981897),
                                altitude: 0, horizontalAccuracy: 5, verticalAccuracy: 5, timestamp: startDate)
        
        // 100 meters away, but only 1 second later (100 m/s > 12 m/s drift gate)
        // 0.001 deg is approx 111 meters
        let point2 = CLLocation(coordinate: CLLocationCoordinate2D(latitude: 40.769075, longitude: -73.981897),
                                altitude: 0, horizontalAccuracy: 5, verticalAccuracy: 5, timestamp: startDate.addingTimeInterval(1))
        
        locationProvider.yield(location: point1)
        locationProvider.yield(location: point2)
        
        try await Task.sleep(nanoseconds: 200_000_000)
        
        let count = try await dbManager.dbWriter.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM explored_hexes") ?? 0
        }
        
        // Point 1 should be accepted and save a hex. Point 2 should be rejected.
        XCTAssertEqual(count, 1, "The drift gate should reject point 2, resulting in only 1 hex written.")
    }
    
    func testPOIDiscovery() async throws {
        // As per the requirement to test POI Discovery
        let store = SpatialStore(
            dbManager: dbManager,
            liveUpdatePriority: .userInitiated,
            observationScheduler: .immediate
        )
        
        // Wait for SpatialStore init Task to finish loading from DB and overwriting discoveredPOIs
        try await Task.sleep(nanoseconds: 100_000_000)
        
        // Assert initial state is empty
        XCTAssertFalse(store.discoveredPOIs.contains("test_stop"))
        
        // Simulate MapView triggering the discovery manually since Phase transitions are visually driven
        store.discoverPOI(id: "test_stop", name: "Test Stop")
        
        try await Task.sleep(nanoseconds: 200_000_000)
        
        let dbPOIs = try await dbManager.loadDiscoveredPOIs()
        
        XCTAssertTrue(dbPOIs.contains("test_stop"), "POI should transition and be persisted to the database.")
        XCTAssertTrue(store.discoveredPOIs.contains("test_stop"), "SpatialStore should hold the discovered POI.")
    }
    
    func testResumeTrackingIfNeeded() async throws {
        XCTAssertFalse(engine.isTracking)
        XCTAssertFalse(engine.isTrackingEnabled)
        
        // Calling resumeTrackingIfNeeded when isTrackingEnabled is false should do nothing
        engine.resumeTrackingIfNeeded()
        XCTAssertFalse(engine.isTracking)
        
        // Setting isTrackingEnabled to true and calling resumeTrackingIfNeeded should start tracking
        engine.isTrackingEnabled = true
        engine.resumeTrackingIfNeeded()
        XCTAssertTrue(engine.isTracking)
        
        await engine.stopTracking()
        XCTAssertFalse(engine.isTracking)
        XCTAssertFalse(engine.isTrackingEnabled)
    }
    
    func testStopTrackingCleansUpStateAndPersistsDisabledPreference() async throws {
        engine.startTracking()
        XCTAssertTrue(engine.isTracking)
        XCTAssertTrue(engine.isTrackingEnabled)
        
        await engine.stopTracking()
        XCTAssertFalse(engine.isTracking)
        XCTAssertFalse(engine.isTrackingEnabled)
    }
}
