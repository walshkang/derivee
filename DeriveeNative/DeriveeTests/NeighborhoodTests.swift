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
        dbManager = SpatialDatabaseManager(inMemory: true)
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
            XCTAssertGreaterThan(firstStat.totalHexes, 0)
            XCTAssertNotEqual(firstStat.centroidLat, 0.0, "Centroid latitude should be populated.")
            XCTAssertNotEqual(firstStat.centroidLng, 0.0, "Centroid longitude should be populated.")
        }
    }
}
