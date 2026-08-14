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
}
