import XCTest
import GRDB
@testable import Derivee

final class NeighborhoodTests: XCTestCase {
    
    private var tempDirectoryURL: URL!
    private var dbManager: SpatialDatabaseManager!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDirectoryURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectoryURL, withIntermediateDirectories: true)
        dbManager = SpatialDatabaseManager.makeForTesting(inMemory: true)
    }

    override func tearDownWithError() throws {
        dbManager = nil
        if let tempURL = tempDirectoryURL {
            try? FileManager.default.removeItem(at: tempURL)
        }
        try super.tearDownWithError()
    }

    func testFetchNeighborhoodProgression() async throws {
        let stats = try await dbManager.fetchNeighborhoodProgression()
        XCTAssertFalse(stats.isEmpty, "Neighborhood progression should load non-empty neighborhood stats from bundled database.")
        
        if let firstStat = stats.first {
            XCTAssertFalse(firstStat.id.isEmpty)
            XCTAssertFalse(firstStat.name.isEmpty)
            XCTAssertGreaterThan(firstStat.totalHexes, 10, "Total hexes for a neighborhood should be realistic (>10), not fallback 1.")
            XCTAssertNotEqual(firstStat.centroidLat, 0.0, "Centroid latitude should be populated.")
            XCTAssertNotEqual(firstStat.centroidLng, 0.0, "Centroid longitude should be populated.")
        }
    }
    
    func testNeighborhoodProgressionWithClearedHex() async throws {
        // Insert Williamsburg hex: 8b2a100d3ad4fff
        let testHex = "8b2a100d3ad4fff"
        _ = try await dbManager.insertDiscoveredHex(h3Index: testHex)
        
        let stats = try await dbManager.fetchNeighborhoodProgression()
        let wburg = stats.first(where: { $0.id == "BK0102" || $0.name == "Williamsburg" })
        XCTAssertNotNil(wburg, "Williamsburg should be in neighborhood stats.")
        
        if let nbhd = wburg {
            XCTAssertEqual(nbhd.clearedHexes, 1, "Williamsburg cleared hexes should reflect the inserted hex.")
            XCTAssertGreaterThan(nbhd.totalHexes, 100, "Williamsburg total hexes should be around 1243.")
            XCTAssertGreaterThan(nbhd.percentage, 0.0, "Percentage should be greater than 0.")
        }
    }
    
    private func getBostonNeighborhoodURL() throws -> URL {
        let bundleURL = Bundle.main.url(forResource: "bos_neighborhood", withExtension: "sqlite")
        if let bundleURL = bundleURL, FileManager.default.fileExists(atPath: bundleURL.path) {
            return bundleURL
        }
        let projectSourceURL = URL(fileURLWithPath: #file).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Derivee/bos_neighborhood.sqlite")
        if FileManager.default.fileExists(atPath: projectSourceURL.path) {
            return projectSourceURL
        }
        // Fallback: create mock Boston neighborhood DB in temp directory
        let mockURL = tempDirectoryURL.appendingPathComponent("mock_bos_neighborhood.sqlite")
        let dbQueue = try DatabaseQueue(path: mockURL.path)
        try dbQueue.write { db in
            try db.execute(sql: """
            CREATE TABLE neighborhood_stats (
                id TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                total_hexes INTEGER NOT NULL,
                centroid_lat REAL NOT NULL,
                centroid_lng REAL NOT NULL
            ) WITHOUT ROWID;
            
            CREATE TABLE neighborhood_hexes (
                h3_index TEXT PRIMARY KEY,
                neighborhood_id TEXT NOT NULL
            ) WITHOUT ROWID;
            
            INSERT INTO neighborhood_stats VALUES
            ('BOS01', 'Back Bay', 1500, 42.3503, -71.0810),
            ('BOS02', 'Beacon Hill', 800, 42.3588, -71.0707),
            ('BOS03', 'South End', 1800, 42.3388, -71.0765);
            
            INSERT INTO neighborhood_hexes VALUES
            ('8b2a100d2840fff', 'BOS01'),
            ('8b2a100d2841fff', 'BOS02');
            """)
        }
        return mockURL
    }
    
    func testBostonNeighborhoodProgressionDynamicMounting() async throws {
        let bosNbhdURL = try getBostonNeighborhoodURL()
        let bosTransitURL = tempDirectoryURL.appendingPathComponent("mock_bos_transit.sqlite")
        let dbQueue = try DatabaseQueue(path: bosTransitURL.path)
        try await dbQueue.write { db in
            try db.execute(sql: "CREATE TABLE stops (stop_id TEXT PRIMARY KEY, stop_name TEXT NOT NULL, stop_lat REAL NOT NULL, stop_lon REAL NOT NULL, location_type INTEGER DEFAULT 0);")
        }
        
        let customManager = SpatialDatabaseManager.makeForTesting(inMemory: true, customTransitURL: bosTransitURL, customNeighborhoodURL: bosNbhdURL)
        
        let stats = try await customManager.fetchNeighborhoodProgression(citySlug: "bos")
        XCTAssertFalse(stats.isEmpty, "Boston neighborhood progression should return non-empty list of neighborhoods.")
        
        if stats.count >= 25 {
            // Real compiled Boston dataset
            XCTAssertEqual(stats.count, 25, "Boston should contain exactly 25 official neighborhoods.")
            let backBay = stats.first(where: { $0.name == "Back Bay" })
            XCTAssertNotNil(backBay, "Back Bay should exist in Boston dataset.")
            let beaconHill = stats.first(where: { $0.name == "Beacon Hill" })
            XCTAssertNotNil(beaconHill, "Beacon Hill should exist in Boston dataset.")
        }
    }
    
    func testBostonProgressionWithClearedHex() async throws {
        let bosNbhdURL = try getBostonNeighborhoodURL()
        let bosTransitURL = tempDirectoryURL.appendingPathComponent("mock_bos_transit2.sqlite")
        let dbQueue = try DatabaseQueue(path: bosTransitURL.path)
        try await dbQueue.write { db in
            try db.execute(sql: "CREATE TABLE stops (stop_id TEXT PRIMARY KEY, stop_name TEXT NOT NULL, stop_lat REAL NOT NULL, stop_lon REAL NOT NULL, location_type INTEGER DEFAULT 0);")
        }
        
        let customManager = SpatialDatabaseManager.makeForTesting(inMemory: true, customTransitURL: bosTransitURL, customNeighborhoodURL: bosNbhdURL)
        
        // Find a hex in the attached Boston database
        let sampleHexRow: (h3: String, nid: String)? = try await customManager.dbWriter.read { db in
            try Row.fetchOne(db, sql: "SELECT h3_index, neighborhood_id FROM neighborhood.neighborhood_hexes LIMIT 1").map {
                ($0["h3_index"], $0["neighborhood_id"])
            }
        }
        
        if let sample = sampleHexRow {
            _ = try await customManager.insertDiscoveredHex(h3Index: sample.h3, citySlug: "bos", enforceLandOnly: false)
            
            let stats = try await customManager.fetchNeighborhoodProgression(citySlug: "bos")
            let targetNbhd = stats.first(where: { $0.id == sample.nid })
            XCTAssertNotNil(targetNbhd)
            XCTAssertEqual(targetNbhd?.clearedHexes, 1)
            XCTAssertGreaterThan(targetNbhd?.percentage ?? 0, 0.0)
        }
    }
    
    func testMultiCityNeighborhoodIsolation() async throws {
        let bosNbhdURL = try getBostonNeighborhoodURL()
        let bosTransitURL = tempDirectoryURL.appendingPathComponent("mock_bos_transit3.sqlite")
        let dbQueue = try DatabaseQueue(path: bosTransitURL.path)
        try await dbQueue.write { db in
            try db.execute(sql: "CREATE TABLE stops (stop_id TEXT PRIMARY KEY, stop_name TEXT NOT NULL, stop_lat REAL NOT NULL, stop_lon REAL NOT NULL, location_type INTEGER DEFAULT 0);")
        }
        
        let customManager = SpatialDatabaseManager.makeForTesting(inMemory: true, customTransitURL: bosTransitURL, customNeighborhoodURL: bosNbhdURL)
        
        // Insert hex only into NYC table
        _ = try await customManager.insertDiscoveredHex(h3Index: "8b2a100d3ad4fff", citySlug: "nyc", enforceLandOnly: false)
        
        // Query Boston progression: must be 0 cleared
        let bosStats = try await customManager.fetchNeighborhoodProgression(citySlug: "bos")
        let totalBosCleared = bosStats.reduce(0) { $0 + $1.clearedHexes }
        XCTAssertEqual(totalBosCleared, 0, "Boston progression must not count NYC explored hexes.")
    }
}
