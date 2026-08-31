import XCTest
import CoreLocation
import GRDB
@testable import Derivee

final class MultiCityStatsTests: XCTestCase {
    private var tempDirectoryURL: URL!
    private var mockTransitURL: URL!
    private var dbManager: SpatialDatabaseManager!
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDirectoryURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectoryURL, withIntermediateDirectories: true)
        
        mockTransitURL = tempDirectoryURL.appendingPathComponent("transit_delta.sqlite")
        let dbQueue = try DatabaseQueue(path: mockTransitURL.path)
        try dbQueue.write { db in
            try db.execute(sql: """
            CREATE TABLE stops (
                stop_id TEXT PRIMARY KEY,
                stop_name TEXT NOT NULL,
                stop_lat REAL NOT NULL,
                stop_lon REAL NOT NULL,
                location_type INTEGER NOT NULL DEFAULT 0
            );
            
            INSERT INTO stops (stop_id, stop_name, stop_lat, stop_lon, location_type) VALUES
            ('stop_bedford', 'Bedford Av', 40.7169, -73.9567, 1),
            ('stop_union_sq', '14 St - Union Sq', 40.7347, -73.9907, 1);
            """)
        }
        
        dbManager = SpatialDatabaseManager.makeForTesting(inMemory: true, customTransitURL: mockTransitURL)
    }
    
    override func tearDownWithError() throws {
        dbManager = nil
        if let temp = tempDirectoryURL {
            try? FileManager.default.removeItem(at: temp)
        }
        try super.tearDownWithError()
    }
    
    func testMultiCityTableCreationAndCounts() async throws {
        let nycHexes = ["8b2a1072cb00fff", "8b2a1072cb01fff", "8b2a1072cb02fff"]
        let bosHexes = ["8b2a100d2840fff", "8b2a100d2841fff"]
        
        try await dbManager.insertHexesBatch(h3Indices: nycHexes, citySlug: "nyc")
        try await dbManager.insertHexesBatch(h3Indices: bosHexes, citySlug: "bos")
        
        let nyCount = try await dbManager.fetchExploredHexCount(citySlug: "nyc")
        let bosCount = try await dbManager.fetchExploredHexCount(citySlug: "bos")
        let chiCount = try await dbManager.fetchExploredHexCount(citySlug: "chi")
        
        XCTAssertEqual(nyCount, 3)
        XCTAssertEqual(bosCount, 2)
        XCTAssertEqual(chiCount, 0)
    }
    
    func testAllMetrosSummaryAggregation() async throws {
        let nycHexes = ["8b2a1072cb00fff", "8b2a1072cb01fff", "8b2a1072cb02fff"]
        let bosHexes = ["8b2a100d2840fff", "8b2a100d2841fff"]
        
        try await dbManager.insertHexesBatch(h3Indices: nycHexes, citySlug: "nyc")
        try await dbManager.insertHexesBatch(h3Indices: bosHexes, citySlug: "bos")
        
        let manifest = CityManifest.defaultManifest
        let summary = try await dbManager.fetchAllMetrosSummary(installedSlugs: ["nyc", "bos"], manifest: manifest)
        
        XCTAssertEqual(summary.totalGlobalClearedHexes, 5)
        XCTAssertEqual(summary.citiesExploredCount, 2)
        XCTAssertEqual(summary.totalCitiesCount, 3)
        XCTAssertGreaterThan(summary.totalDriftDistanceKm, 0.2)
        
        let nycOverview = try XCTUnwrap(summary.cityOverviews.first(where: { $0.slug == "nyc" }))
        XCTAssertEqual(nycOverview.clearedHexes, 3)
        XCTAssertTrue(nycOverview.isInstalled)
        
        let bosOverview = try XCTUnwrap(summary.cityOverviews.first(where: { $0.slug == "bos" }))
        XCTAssertEqual(bosOverview.clearedHexes, 2)
        XCTAssertTrue(bosOverview.isInstalled)
        
        let chiOverview = try XCTUnwrap(summary.cityOverviews.first(where: { $0.slug == "chi" }))
        XCTAssertEqual(chiOverview.clearedHexes, 0)
        XCTAssertFalse(chiOverview.isInstalled)
    }
    
    func testCityScopedJournalAndNeighborhoodProgression() async throws {
        try await dbManager.insertHexesBatch(h3Indices: ["8b2a1072cb00fff"], citySlug: "nyc")
        try await dbManager.insertHexesBatch(h3Indices: ["8b2a100d2840fff"], citySlug: "bos")
        
        let nycJournal = try await dbManager.fetchExplorationJournalData(citySlug: "nyc")
        XCTAssertEqual(nycJournal.totalClearedHexes, 1)
        
        let bosJournal = try await dbManager.fetchExplorationJournalData(citySlug: "bos")
        XCTAssertEqual(bosJournal.totalClearedHexes, 1)
        XCTAssertTrue(bosJournal.boroughProgress.isEmpty, "Non-NYC metros must have empty borough progress until M.5.5")
        XCTAssertTrue(bosJournal.landmarks.isEmpty, "Non-NYC metros must have empty landmarks list until curated catalogs are added")
        XCTAssertEqual(bosJournal.totalCityHexes, 115000, "Boston total hex estimate must be 115,000")
        
        let nycProgression = try await dbManager.fetchNeighborhoodProgression(citySlug: "nyc")
        XCTAssertNotNil(nycProgression)
        
        let bosProgression = try await dbManager.fetchNeighborhoodProgression(citySlug: "bos")
        XCTAssertTrue(bosProgression.isEmpty, "Boston must return empty neighborhood list without leaking NYC neighborhoods")
    }
}
