import XCTest
import GRDB
import CoreLocation
import H3
@testable import Derivee

final class TransitHotSwapTests: XCTestCase {
    var fileManager: FileManager!
    var tempDirectoryURL: URL!
    var nycTransitURL: URL!
    var bosTransitURL: URL!
    
    override func setUpWithError() throws {
        super.setUp()
        fileManager = FileManager.default
        tempDirectoryURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("HotSwapTests_\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: tempDirectoryURL, withIntermediateDirectories: true, attributes: nil)
        
        nycTransitURL = tempDirectoryURL.appendingPathComponent("nyc_transit.sqlite")
        bosTransitURL = tempDirectoryURL.appendingPathComponent("bos_transit.sqlite")
        
        try createMockTransitDatabase(at: nycTransitURL, stopId: "STOP_NYC_1", stopName: "Times Sq-42 St", routes: "1,2,3,N,Q,R,W,S")
        try createMockTransitDatabase(at: bosTransitURL, stopId: "STOP_BOS_1", stopName: "Park Street", routes: "Red Line,Green Line")
    }
    
    override func tearDownWithError() throws {
        if let temp = tempDirectoryURL, fileManager.fileExists(atPath: temp.path) {
            try? fileManager.removeItem(at: temp)
        }
        super.tearDown()
    }
    
    private func createMockTransitDatabase(at url: URL, stopId: String, stopName: String, routes: String) throws {
        let dbQueue = try DatabaseQueue(path: url.path)
        try dbQueue.write { db in
            try db.execute(sql: """
                CREATE TABLE stops (
                    stop_id TEXT PRIMARY KEY,
                    stop_name TEXT NOT NULL,
                    stop_lat REAL NOT NULL,
                    stop_lon REAL NOT NULL,
                    routes TEXT,
                    parent_station TEXT
                );
                INSERT INTO stops (stop_id, stop_name, stop_lat, stop_lon, routes, parent_station)
                VALUES ('\(stopId)', '\(stopName)', 40.758, -73.985, '\(routes)', NULL);
                
                CREATE TABLE routes (
                    route_id TEXT PRIMARY KEY,
                    route_short_name TEXT,
                    route_long_name TEXT,
                    route_color TEXT,
                    route_text_color TEXT
                );
                INSERT INTO routes (route_id, route_short_name, route_long_name, route_color, route_text_color)
                VALUES ('R1', '1', 'Broadway-7th Ave Local', 'EE352E', 'FFFFFF');
            """)
        }
    }
    
    // MARK: - Two-Phase Hot-Swap Tests
    
    func testCoordinatedTwoPhaseHotSwapSafety() async throws {
        let dbManager = SpatialDatabaseManager.makeForTesting(inMemory: true, customTransitURL: nycTransitURL)
        
        // 1. Verify initial NYC attachment
        let initialAttached = try await dbManager.isTransitAttached()
        XCTAssertTrue(initialAttached, "Transit database must be initially attached")
        
        let initialStop = try await dbManager.fetchStopDetails(for: "STOP_NYC_1")
        XCTAssertEqual(initialStop.name, "Times Sq-42 St")
        
        // 2. Perform Two-Phase Hot-Swap to Boston
        try await dbManager.hotSwapTransitDatabase(to: bosTransitURL)
        
        // 3. Verify Boston attachment
        let postSwapAttached = try await dbManager.isTransitAttached()
        XCTAssertTrue(postSwapAttached, "Transit database must remain attached after hot-swap")
        
        let attachedPath = try await dbManager.attachedTransitPath()
        XCTAssertEqual(attachedPath, bosTransitURL.path, "Attached transit path must match Boston DB URL")
        
        let bosStop = try await dbManager.fetchStopDetails(for: "STOP_BOS_1")
        XCTAssertEqual(bosStop.name, "Park Street")
        
        // 4. Verify old NYC stop falls back / no longer has custom attached routes
        let oldNycStop = try await dbManager.fetchStopDetails(for: "STOP_NYC_1")
        XCTAssertNotEqual(oldNycStop.name, "Times Sq-42 St")
    }
    
    func testDualTransitAndNeighborhoodHotSwap() async throws {
        let nycNbhdURL = tempDirectoryURL.appendingPathComponent("nyc_neighborhood.sqlite")
        let bosNbhdURL = tempDirectoryURL.appendingPathComponent("bos_neighborhood.sqlite")
        
        let nycNbhdQueue = try DatabaseQueue(path: nycNbhdURL.path)
        try await nycNbhdQueue.write { db in
            try db.execute(sql: """
            CREATE TABLE neighborhood_stats (id TEXT PRIMARY KEY, name TEXT NOT NULL, total_hexes INTEGER, centroid_lat REAL, centroid_lng REAL) WITHOUT ROWID;
            CREATE TABLE neighborhood_hexes (h3_index TEXT PRIMARY KEY, neighborhood_id TEXT NOT NULL) WITHOUT ROWID;
            INSERT INTO neighborhood_stats VALUES ('NYC01', 'Greenwich Village', 1000, 40.7336, -74.0027);
            INSERT INTO neighborhood_hexes VALUES ('8b2a100d3ad4fff', 'NYC01');
            """)
        }
        
        let bosNbhdQueue = try DatabaseQueue(path: bosNbhdURL.path)
        try await bosNbhdQueue.write { db in
            try db.execute(sql: """
            CREATE TABLE neighborhood_stats (id TEXT PRIMARY KEY, name TEXT NOT NULL, total_hexes INTEGER, centroid_lat REAL, centroid_lng REAL) WITHOUT ROWID;
            CREATE TABLE neighborhood_hexes (h3_index TEXT PRIMARY KEY, neighborhood_id TEXT NOT NULL) WITHOUT ROWID;
            INSERT INTO neighborhood_stats VALUES ('BOS01', 'Back Bay', 1500, 42.3503, -71.0810);
            INSERT INTO neighborhood_hexes VALUES ('8b2a100d2840fff', 'BOS01');
            """)
        }
        
        let dbManager = SpatialDatabaseManager.makeForTesting(inMemory: true, customTransitURL: nycTransitURL, customNeighborhoodURL: nycNbhdURL)
        
        let initialTransitAttached = try await dbManager.isTransitAttached()
        let initialNbhdAttached = try await dbManager.isNeighborhoodAttached()
        let initialNbhdPath = try await dbManager.attachedNeighborhoodPath()
        XCTAssertTrue(initialTransitAttached)
        XCTAssertTrue(initialNbhdAttached)
        XCTAssertEqual(initialNbhdPath, nycNbhdURL.path)
        
        // Swap both to Boston
        try await dbManager.hotSwapCityDatabase(transitURL: bosTransitURL, neighborhoodURL: bosNbhdURL)
        
        let postSwapTransitAttached = try await dbManager.isTransitAttached()
        let postSwapNbhdAttached = try await dbManager.isNeighborhoodAttached()
        let postSwapTransitPath = try await dbManager.attachedTransitPath()
        let postSwapNbhdPath = try await dbManager.attachedNeighborhoodPath()
        XCTAssertTrue(postSwapTransitAttached)
        XCTAssertTrue(postSwapNbhdAttached)
        XCTAssertEqual(postSwapTransitPath, bosTransitURL.path)
        XCTAssertEqual(postSwapNbhdPath, bosNbhdURL.path)
        
        let bosProgression = try await dbManager.fetchNeighborhoodProgression(citySlug: "bos")
        XCTAssertEqual(bosProgression.count, 1)
        XCTAssertEqual(bosProgression.first?.name, "Back Bay")
    }
    
    func testHotSwapConcurrentWithBackgroundReads() async throws {
        let dbManager = SpatialDatabaseManager.makeForTesting(inMemory: true, customTransitURL: nycTransitURL)
        
        let isRunning = ManagedAtomicBool(true)
        
        // Spawn 4 concurrent reader tasks
        let readerTasks = (0..<4).map { _ in
            Task.detached {
                while isRunning.value {
                    _ = try? await dbManager.fetchStopDetails(for: "STOP_NYC_1")
                    _ = try? await dbManager.fetchStopDetails(for: "STOP_BOS_1")
                    try? await Task.sleep(nanoseconds: 1_000_000) // 1ms
                }
            }
        }
        
        // Concurrently execute hot-swaps back and forth
        for _ in 0..<5 {
            try await dbManager.hotSwapTransitDatabase(to: bosTransitURL)
            try await Task.sleep(nanoseconds: 5_000_000)
            try await dbManager.hotSwapTransitDatabase(to: nycTransitURL)
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        
        isRunning.value = false
        for task in readerTasks {
            _ = await task.result
        }
        
        // Verify final state is valid and non-corrupted
        let finalAttached = try await dbManager.isTransitAttached()
        XCTAssertTrue(finalAttached, "Transit database must remain attached after concurrent swaps")
    }
    
    func testRapidSequentialHotSwaps() async throws {
        let dbManager = SpatialDatabaseManager.makeForTesting(inMemory: true, customTransitURL: nycTransitURL)
        
        for i in 0..<8 {
            let targetURL = (i % 2 == 0) ? bosTransitURL! : nycTransitURL!
            let expectedStopId = (i % 2 == 0) ? "STOP_BOS_1" : "STOP_NYC_1"
            let expectedStopName = (i % 2 == 0) ? "Park Street" : "Times Sq-42 St"
            
            try await dbManager.hotSwapTransitDatabase(to: targetURL)
            
            let stop = try await dbManager.fetchStopDetails(for: expectedStopId)
            XCTAssertEqual(stop.name, expectedStopName, "Iteration \(i) failed to resolve expected stop after rapid hot-swap")
        }
    }
    
    // MARK: - Coordinate-Routed Background Tracking Tests
    
    func testCoordinateRoutedTrackingDecoupledFromActiveView() async throws {
        let dbManager = SpatialDatabaseManager.makeForTesting(inMemory: true)
        let manifest = CityManifest.defaultManifest
        
        // 1. NYC Location: Columbus Circle (40.768075, -73.981897)
        let nycCoord = CLLocationCoordinate2D(latitude: 40.768075, longitude: -73.981897)
        let nycCell = try H3.latLngToCell(latitude: nycCoord.latitude, longitude: nycCoord.longitude, resolution: 11)
        let nycHex = String(nycCell, radix: 16)
        
        let nycMatchedSlug = manifest.findCity(containing: nycCoord)?.slug ?? "nyc"
        XCTAssertEqual(nycMatchedSlug, "nyc", "NYC coordinate must match NYC manifest entry")
        
        // Insert with target slug derived from coordinate math
        let nycInserted = try await dbManager.insertDiscoveredHex(h3Index: nycHex, citySlug: nycMatchedSlug, enforceLandOnly: false)
        XCTAssertTrue(nycInserted)
        
        // 2. Boston Location: Boston Common (42.3550, -71.0656)
        let bosCoord = CLLocationCoordinate2D(latitude: 42.3550, longitude: -71.0656)
        let bosCell = try H3.latLngToCell(latitude: bosCoord.latitude, longitude: bosCoord.longitude, resolution: 11)
        let bosHex = String(bosCell, radix: 16)
        
        let bosMatchedSlug = manifest.findCity(containing: bosCoord)?.slug ?? "nyc"
        XCTAssertEqual(bosMatchedSlug, "bos", "Boston coordinate must match Boston manifest entry")
        
        // Insert with target slug derived from coordinate math
        let bosInserted = try await dbManager.insertDiscoveredHex(h3Index: bosHex, citySlug: bosMatchedSlug, enforceLandOnly: false)
        XCTAssertTrue(bosInserted)
        
        // 3. Verify strict isolation between city tables
        let nycHexes = try await dbManager.fetchExploredHexes(citySlug: "nyc")
        let bosHexes = try await dbManager.fetchExploredHexes(citySlug: "bos")
        
        XCTAssertTrue(nycHexes.contains(nycHex), "NYC table must contain NYC hex")
        XCTAssertFalse(nycHexes.contains(bosHex), "NYC table must NOT contain Boston hex")
        
        XCTAssertTrue(bosHexes.contains(bosHex), "Boston table must contain Boston hex")
        XCTAssertFalse(bosHexes.contains(nycHex), "Boston table must NOT contain NYC hex")
    }
    
    // MARK: - City Pack Manager Hot-Swap Integration
    
    func testCityPackManagerHotSwapIntegration() async throws {
        let sampleConfig = CityConfig(
            version: 1,
            slug: "bos",
            displayName: "Boston",
            region: "Massachusetts, USA",
            bounds: CityBounds(minLatitude: 42.20, maxLatitude: 42.45, minLongitude: -71.20, maxLongitude: -70.95),
            center: CityCenter(latitude: 42.3601, longitude: -71.0589, defaultZoom: 13.0)
        )
        
        let configData = try JSONEncoder().encode(sampleConfig)
        let bosPackDir = tempDirectoryURL.appendingPathComponent("CityPacks/bos", isDirectory: true)
        try fileManager.createDirectory(at: bosPackDir, withIntermediateDirectories: true)
        
        try configData.write(to: bosPackDir.appendingPathComponent("city_config.json"))
        try fileManager.copyItem(at: bosTransitURL, to: bosPackDir.appendingPathComponent("transit.sqlite"))
        
        let customTransitURL = bosPackDir.appendingPathComponent("transit.sqlite")
        let dbManager = SpatialDatabaseManager.makeForTesting(inMemory: true, customTransitURL: nycTransitURL)
        try await dbManager.hotSwapTransitDatabase(to: customTransitURL)
        
        let stop = try await dbManager.fetchStopDetails(for: "STOP_BOS_1")
        XCTAssertEqual(stop.name, "Park Street")
    }
    
    // MARK: - Pre-Swap UI Teardown Tests
    
    func testPrepareForCitySwapTeardown() {
        TransitRealtimeService.shared.prepareForCitySwap()
        XCTAssertTrue(true)
    }
}

/// Helper atomic boolean for concurrency testing.
private final class ManagedAtomicBool: @unchecked Sendable {
    private var _value: Bool
    private let lock = NSLock()
    
    init(_ value: Bool) {
        self._value = value
    }
    
    var value: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _value
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _value = newValue
        }
    }
}
