import XCTest
import CoreLocation
import GRDB
@testable import Derivee

final class MultiCityGPXImportTests: XCTestCase {
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
    
    func testMultiCityGPXAutoPartitioningAndAtomicInsert() async throws {
        let processor = GPXProcessor(dbManager: dbManager)
        
        // Coordinates spanning NYC (Lower Manhattan) and Boston (Boston Common)
        let coordinates = [
            GPXCoordinate(latitude: 40.7128, longitude: -74.0060),
            GPXCoordinate(latitude: 40.7130, longitude: -74.0065),
            GPXCoordinate(latitude: 40.7135, longitude: -74.0070),
            GPXCoordinate(latitude: 42.3601, longitude: -71.0589),
            GPXCoordinate(latitude: 42.3550, longitude: -71.0650)
        ]
        
        let manifest = CityManifest.defaultManifest
        
        let expectation = XCTestExpectation(description: "Multi-city GPX import completes")
        var importResult: MultiCityImportResult?
        
        processor.processAndInsertMultiCity(
            coordinates: coordinates,
            manifest: manifest,
            defaultCitySlug: "nyc",
            userLocation: nil,
            onProgress: { _ in },
            onComplete: { result in
                importResult = result
                expectation.fulfill()
            }
        )
        
        await fulfillment(of: [expectation], timeout: 5.0)
        
        let result = try XCTUnwrap(importResult)
        XCTAssertEqual(result.totalHexesImported, 5)
        XCTAssertEqual(result.cityHexCounts["nyc"], 3)
        XCTAssertEqual(result.cityHexCounts["bos"], 2)
        XCTAssertEqual(result.citiesCount, 2)
        
        let nyCount = try await dbManager.fetchExploredHexCount(citySlug: "nyc")
        let bosCount = try await dbManager.fetchExploredHexCount(citySlug: "bos")
        
        XCTAssertEqual(nyCount, 3)
        XCTAssertEqual(bosCount, 2)
    }
    
    func testEmptyGPXCoordinatesHandling() async throws {
        let processor = GPXProcessor(dbManager: dbManager)
        let expectation = XCTestExpectation(description: "Empty GPX handling completes")
        var importResult: MultiCityImportResult?
        
        processor.processAndInsertMultiCity(
            coordinates: [],
            manifest: .defaultManifest,
            defaultCitySlug: "nyc",
            userLocation: nil,
            onProgress: { _ in },
            onComplete: { result in
                importResult = result
                expectation.fulfill()
            }
        )
        
        await fulfillment(of: [expectation], timeout: 5.0)
        let result = try XCTUnwrap(importResult)
        XCTAssertEqual(result.totalHexesImported, 0)
        XCTAssertEqual(result.citiesCount, 0)
    }
}
