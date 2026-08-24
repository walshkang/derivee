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
    var userDefaults: UserDefaults!
    var suiteName: String!
    
    override func setUpWithError() throws {
        suiteName = "com.derivee.tests.\(UUID().uuidString)"
        userDefaults = UserDefaults(suiteName: suiteName)!
        dbManager = SpatialDatabaseManager.makeForTesting(inMemory: true)
        locationProvider = MockLocationProvider()
        engine = AmbientTrackingEngine(locationProvider: locationProvider, databaseManager: dbManager, userDefaults: userDefaults)
    }
    
    override func tearDown() async throws {
        await engine.stopTracking()
        locationProvider.finish()
        if let suite = suiteName {
            userDefaults?.removePersistentDomain(forName: suite)
        }
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
        
        // Warmup fix 1
        let point1 = CLLocation(coordinate: CLLocationCoordinate2D(latitude: 40.768075, longitude: -73.981897),
                                altitude: 0, horizontalAccuracy: 5, verticalAccuracy: 5, timestamp: startDate)
        // Warmup fix 2 (completes warmup, unlocks hex 1)
        let point1b = CLLocation(coordinate: CLLocationCoordinate2D(latitude: 40.768080, longitude: -73.981897),
                                 altitude: 0, horizontalAccuracy: 5, verticalAccuracy: 5, timestamp: startDate.addingTimeInterval(1))
        
        // 100 meters away, but only 1 second later (100 m/s > 12 m/s drift gate)
        // 0.001 deg is approx 111 meters
        let point2 = CLLocation(coordinate: CLLocationCoordinate2D(latitude: 40.769075, longitude: -73.981897),
                                altitude: 0, horizontalAccuracy: 5, verticalAccuracy: 5, timestamp: startDate.addingTimeInterval(2))
        
        locationProvider.yield(location: point1)
        locationProvider.yield(location: point1b)
        locationProvider.yield(location: point2)
        
        try await Task.sleep(nanoseconds: 200_000_000)
        
        let count = try await dbManager.dbWriter.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM explored_hexes") ?? 0
        }
        
        // Point 1b completes warmup and saves a hex. Point 2 should be rejected by the drift gate.
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
        XCTAssertTrue(engine.isTrackingEnabled, "isTrackingEnabled defaults to true in a clean environment")
        
        // Disabling isTrackingEnabled and calling resumeTrackingIfNeeded should do nothing
        engine.isTrackingEnabled = false
        engine.resumeTrackingIfNeeded()
        XCTAssertFalse(engine.isTracking)
        
        // Setting isTrackingEnabled to true and calling resumeTrackingIfNeeded should start tracking
        engine.isTrackingEnabled = true
        engine.resumeTrackingIfNeeded()
        XCTAssertTrue(engine.isTracking)
        
        await engine.stopTracking()
        XCTAssertFalse(engine.isTracking)
        XCTAssertTrue(engine.isTrackingEnabled, "stopTracking only halts runtime execution and preserves user preference")
    }
    
    func testStopTrackingCleansUpStateAndPreservesPersistentTrackingPreference() async throws {
        engine.startTracking()
        XCTAssertTrue(engine.isTracking)
        XCTAssertTrue(engine.isTrackingEnabled)
        
        await engine.stopTracking()
        XCTAssertFalse(engine.isTracking)
        XCTAssertTrue(engine.isTrackingEnabled, "isTrackingEnabled preference must remain true after runtime stopTracking()")
    }
    
    func testOrphanedLiveActivityCleanup() async throws {
        // Calling cleanUpOrphanedLiveActivities on cold start or engine transitions should execute safely
        engine.cleanUpOrphanedLiveActivities()
        
        engine.startTracking()
        XCTAssertTrue(engine.isTracking)
        
        await engine.stopTracking()
        XCTAssertFalse(engine.isTracking)
    }
    
    func testGPXLocationProviderStreamsLocationsToEngine() async throws {
        let coords = [
            GPXCoordinate(latitude: 40.768075, longitude: -73.981897, timestamp: Date()),
            GPXCoordinate(latitude: 40.768344, longitude: -73.981581, timestamp: Date().addingTimeInterval(5)),
            GPXCoordinate(latitude: 40.768614, longitude: -73.981266, timestamp: Date().addingTimeInterval(10))
        ]
        
        let gpxProvider = GPXLocationProvider(coordinates: coords, pacing: .immediate)
        let gpxEngine = AmbientTrackingEngine(locationProvider: gpxProvider, databaseManager: dbManager, userDefaults: userDefaults)
        
        gpxEngine.startTracking()
        
        // Allow time for coordinates to stream and database writes to commit
        try await Task.sleep(nanoseconds: 300_000_000)
        
        let count = try await dbManager.dbWriter.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM explored_hexes") ?? 0
        }
        
        XCTAssertGreaterThan(count, 0, "GPXLocationProvider should stream coordinates through the engine to unlock hexes.")
        await gpxEngine.stopTracking()
    }
    
    func testAppTerminationPreservesPersistentTrackingPreference() async throws {
        engine.startTracking()
        XCTAssertTrue(engine.isTracking)
        XCTAssertTrue(engine.isTrackingEnabled)
        
        // Simulating UIApplication.willTerminateNotification lifecycle execution
        engine.handleAppTermination()
        
        // Calling cleanUpOrphanedLiveActivities should run safely
        engine.cleanUpOrphanedLiveActivities()
        
        // Runtime tracking is halted, but persistent user preference remains enabled
        XCTAssertFalse(engine.isTracking)
        XCTAssertTrue(engine.isTrackingEnabled, "isTrackingEnabled must remain true across app termination so cold launches auto-resume.")
        
        // On next launch, resumeTrackingIfNeeded should successfully re-engage tracking
        engine.resumeTrackingIfNeeded()
        XCTAssertTrue(engine.isTracking)
        
        await engine.stopTracking()
        XCTAssertFalse(engine.isTracking)
        XCTAssertTrue(engine.isTrackingEnabled)
    }
    
    func testColdFixInNewNeighborhoodWithUndeterminedSpeedUnlocksHex() async throws {
        engine.startTracking()
        
        let startDate = Date()
        // 1. Initial fixes in Brooklyn (DUMBO) with speed = -1 (undetermined hardware speed on cold start)
        let dumboLoc1 = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 40.7033, longitude: -73.9890),
            altitude: 0,
            horizontalAccuracy: 5,
            verticalAccuracy: 5,
            course: -1,
            speed: -1,
            timestamp: startDate
        )
        let dumboLoc2 = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 40.70331, longitude: -73.9890),
            altitude: 0,
            horizontalAccuracy: 5,
            verticalAccuracy: 5,
            course: -1,
            speed: -1,
            timestamp: startDate.addingTimeInterval(1)
        )
        locationProvider.yield(location: dumboLoc1)
        locationProvider.yield(location: dumboLoc2)
        try await Task.sleep(nanoseconds: 150_000_000)
        
        var count = try await dbManager.dbWriter.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM explored_hexes") ?? 0
        }
        XCTAssertEqual(count, 1, "Cold start fixes in Brooklyn should complete warmup and unlock 1 hex.")
        
        // 2. Teleport fix in Central Park 30 seconds later (e.g. subway arrival / app reopened) with speed = -1
        let centralParkLoc = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 40.7829, longitude: -73.9654),
            altitude: 0,
            horizontalAccuracy: 5,
            verticalAccuracy: 5,
            course: -1,
            speed: -1,
            timestamp: startDate.addingTimeInterval(30)
        )
        locationProvider.yield(location: centralParkLoc)
        try await Task.sleep(nanoseconds: 150_000_000)
        
        count = try await dbManager.dbWriter.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM explored_hexes") ?? 0
        }
        XCTAssertEqual(count, 2, "Second fix in Central Park after 30s time gap must not be dropped by drift gate and should unlock 2nd hex.")
    }
    
    func testLiveActivityDecoupledPreference() async throws {
        // 1. Disable Live Activity but keep Ambient Tracking enabled
        engine.isLiveActivityEnabled = false
        engine.startTracking()
        XCTAssertTrue(engine.isTracking)
        XCTAssertTrue(engine.isTrackingEnabled)
        XCTAssertFalse(engine.isLiveActivityEnabled)
        
        // 2. Dynamically enable Live Activity during tracking
        engine.updateLiveActivityPreference(enabled: true)
        XCTAssertTrue(engine.isLiveActivityEnabled)
        
        // 3. Dynamically disable Live Activity during tracking
        engine.updateLiveActivityPreference(enabled: false)
        XCTAssertFalse(engine.isLiveActivityEnabled)
        XCTAssertTrue(engine.isTracking, "Tracking must remain active when Live Activity is toggled off.")
        
        // 4. Stop tracking
        await engine.stopTracking()
        XCTAssertFalse(engine.isTracking)
    }
    
    func testStationaryColdStartUnlocksAfterDwell() async throws {
        engine.startTracking()
        
        let startDate = Date()
        // Intermediate accuracy fix (hAcc = 18m) -> requires dwell
        let point = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 40.768075, longitude: -73.981897),
            altitude: 0,
            horizontalAccuracy: 18.0,
            verticalAccuracy: 5.0,
            timestamp: startDate
        )
        locationProvider.yield(location: point)
        
        // 1. Immediately (100ms later), hex is in dwell window and should not be committed yet
        try await Task.sleep(nanoseconds: 100_000_000)
        var count = try await dbManager.dbWriter.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM explored_hexes") ?? 0
        }
        XCTAssertEqual(count, 0, "Hex must not be unlocked while waiting in the 3s dwell window.")
        
        // 2. Wait for the 3.0s dwell timer to fire (+ 250ms processing leeway)
        try await Task.sleep(nanoseconds: 3_250_000_000)
        
        count = try await dbManager.dbWriter.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM explored_hexes") ?? 0
        }
        XCTAssertEqual(count, 1, "Hex must unlock automatically after stationary 3s dwell timer expires.")
    }
    
    func testMovingWalkResolvesIntermediateAccuracyBeforeDwellExpires() async throws {
        engine.startTracking()
        
        let startDate = Date()
        // Fix 1: Intermediate accuracy fix (hAcc = 18m) -> requires dwell
        let point1 = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 40.768075, longitude: -73.981897),
            altitude: 0,
            horizontalAccuracy: 18.0,
            verticalAccuracy: 5.0,
            timestamp: startDate
        )
        // Fix 2: 1s later, 3m away with high accuracy (hAcc = 8m)
        let point2 = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 40.768095, longitude: -73.981897),
            altitude: 0,
            horizontalAccuracy: 8.0,
            verticalAccuracy: 5.0,
            timestamp: startDate.addingTimeInterval(1.0)
        )
        
        locationProvider.yield(location: point1)
        try await Task.sleep(nanoseconds: 100_000_000)
        locationProvider.yield(location: point2)
        
        // Give 200ms to process without waiting for 3s dwell
        try await Task.sleep(nanoseconds: 200_000_000)
        
        let count = try await dbManager.dbWriter.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM explored_hexes") ?? 0
        }
        XCTAssertEqual(count, 1, "Moving pedestrian fix should resolve dwell early and unlock hex immediately.")
    }
}

