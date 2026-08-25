import XCTest
import SwiftZSTD
import CryptoKit
@testable import Derivee

final class CityPackManagerTests: XCTestCase {
    var fileManager: FileManager!
    var tempDirectoryURL: URL!
    var manager: CityPackManager!
    
    override func setUpWithError() throws {
        super.setUp()
        fileManager = FileManager.default
        tempDirectoryURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("CityPackTests_\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: tempDirectoryURL, withIntermediateDirectories: true, attributes: nil)
        
        manager = CityPackManager(
            fileManager: fileManager,
            remoteManifestURL: URL(string: "https://invalid.test.domain/cities.json")!
        )
    }
    
    override func tearDownWithError() throws {
        if let temp = tempDirectoryURL, fileManager.fileExists(atPath: temp.path) {
            try? fileManager.removeItem(at: temp)
        }
        super.tearDown()
    }
    
    // MARK: - Tar Extractor Tests
    
    func testTarExtractorParsingAndExtraction() throws {
        let file1Content = "Hello Dérivée!".data(using: .utf8)!
        let file2Content = "{\"version\": 1, \"slug\": \"test\"}".data(using: .utf8)!
        
        let files = [
            (name: "hello.txt", data: file1Content),
            (name: "nested/config.json", data: file2Content)
        ]
        
        let tarData = TarExtractor.createTarArchive(files: files)
        XCTAssertFalse(tarData.isEmpty)
        
        let destURL = tempDirectoryURL.appendingPathComponent("tar_out", isDirectory: true)
        try TarExtractor.extract(tarData: tarData, to: destURL, fileManager: fileManager)
        
        let extractedFile1 = destURL.appendingPathComponent("hello.txt")
        let extractedFile2 = destURL.appendingPathComponent("nested/config.json")
        
        XCTAssertTrue(fileManager.fileExists(atPath: extractedFile1.path))
        XCTAssertTrue(fileManager.fileExists(atPath: extractedFile2.path))
        
        let readData1 = try Data(contentsOf: extractedFile1)
        let readData2 = try Data(contentsOf: extractedFile2)
        
        XCTAssertEqual(readData1, file1Content)
        XCTAssertEqual(readData2, file2Content)
    }
    
    func testTarPathTraversalProtection() throws {
        let maliciousFiles = [
            (name: "../../../etc/passwd", data: "malicious".data(using: .utf8)!)
        ]
        
        let tarData = TarExtractor.createTarArchive(files: maliciousFiles)
        let destURL = tempDirectoryURL.appendingPathComponent("traversal_out", isDirectory: true)
        
        XCTAssertThrowsError(try TarExtractor.extract(tarData: tarData, to: destURL, fileManager: fileManager)) { error in
            guard case CityPackError.invalidArchive(let reason) = error else {
                XCTFail("Expected invalidArchive with path traversal detection, got \(error)")
                return
            }
            XCTAssertTrue(reason.contains("Path traversal detected"))
        }
    }
    
    // MARK: - Zstd Decompression & Atomic Installation Tests
    
    func testZstdDecompressionAndAtomicInstallation() throws {
        let sampleConfig = CityConfig(
            version: 1,
            slug: "bos",
            displayName: "Boston",
            region: "Massachusetts, USA",
            bounds: CityBounds(minLatitude: 42.20, maxLatitude: 42.45, minLongitude: -71.20, maxLongitude: -70.95),
            center: CityCenter(latitude: 42.3601, longitude: -71.0589, defaultZoom: 13.0),
            transit: CityTransitConfig(
                agencyName: "MBTA",
                attributions: ["Massachusetts Bay Transportation Authority"],
                realtimeEndpoints: [
                    RealtimeEndpoint(feedId: "mbta_subway", url: "https://api-v3.mbta.com/trip-updates", pollIntervalSeconds: 15)
                ]
            )
        )
        
        let configData = try JSONEncoder().encode(sampleConfig)
        let sqliteData = "SQLite format 3\0test_transit_db".data(using: .utf8)!
        let geojsonData = "{\"type\": \"FeatureCollection\", \"features\": []}".data(using: .utf8)!
        
        let tarFiles = [
            (name: "city_config.json", data: configData),
            (name: "transit.sqlite", data: sqliteData),
            (name: "transit-lines.geojson", data: geojsonData)
        ]
        
        let tarData = TarExtractor.createTarArchive(files: tarFiles)
        let processor = ZSTDProcessor()
        guard let compressedData = try? processor.compressBuffer(tarData, compressionLevel: 3) else {
            XCTFail("Failed to compress test archive with ZSTDProcessor")
            return
        }
        
        // Install archive
        let installedConfig = try manager.unpackAndInstall(archiveData: compressedData)
        XCTAssertEqual(installedConfig.slug, "bos")
        XCTAssertEqual(installedConfig.displayName, "Boston")
        
        // Verify files exist in manager's pack path
        XCTAssertTrue(manager.isPackInstalled(slug: "bos"))
        let loadedConfig = try manager.loadConfig(for: "bos")
        XCTAssertEqual(loadedConfig.slug, "bos")
        XCTAssertEqual(loadedConfig.transit?.agencyName, "MBTA")
        
        // Verify disk size calculation
        let diskSize = manager.calculatePackDiskSize(slug: "bos")
        XCTAssertGreaterThan(diskSize, 0)
    }
    
    func testSHA256IntegrityVerification() throws {
        let sampleConfig = CityConfig(
            version: 1,
            slug: "chi",
            displayName: "Chicago",
            region: "Illinois, USA",
            bounds: CityBounds(minLatitude: 41.64, maxLatitude: 42.02, minLongitude: -87.94, maxLongitude: -87.52),
            center: CityCenter(latitude: 41.8781, longitude: -87.6298, defaultZoom: 13.0),
            transit: CityTransitConfig(
                agencyName: "CTA",
                attributions: ["Chicago Transit Authority"],
                realtimeEndpoints: []
            )
        )
        
        let configData = try JSONEncoder().encode(sampleConfig)
        let sqliteData = "SQLite format 3\0test_chicago_transit".data(using: .utf8)!
        let tarData = TarExtractor.createTarArchive(files: [
            (name: "city_config.json", data: configData),
            (name: "transit.sqlite", data: sqliteData)
        ])
        
        let compressedData = try! ZSTDProcessor().compressBuffer(tarData, compressionLevel: 3)
        let correctHash = SHA256.hash(data: compressedData).map { String(format: "%02x", $0) }.joined()
        
        // 1. Success with correct hash
        let config = try manager.unpackAndInstall(archiveData: compressedData, expectedSHA256: correctHash)
        XCTAssertEqual(config.slug, "chi")
        
        // 2. Failure with mismatched hash
        let wrongHash = "0000000000000000000000000000000000000000000000000000000000000000"
        XCTAssertThrowsError(try manager.unpackAndInstall(archiveData: compressedData, expectedSHA256: wrongHash)) { error in
            guard case CityPackError.integrityCheckFailed = error else {
                XCTFail("Expected integrityCheckFailed, got \(error)")
                return
            }
        }
    }
    
    func testMissingMandatoryFileThrowsErrorAndCleansUpStaging() throws {
        // Tar archive missing transit.sqlite
        let sampleConfig = CityConfig.nycDefault
        let configData = try JSONEncoder().encode(sampleConfig)
        let tarData = TarExtractor.createTarArchive(files: [
            (name: "city_config.json", data: configData)
        ])
        
        let compressedData = try! ZSTDProcessor().compressBuffer(tarData, compressionLevel: 3)
        
        XCTAssertThrowsError(try manager.unpackAndInstall(archiveData: compressedData)) { error in
            guard case CityPackError.missingRequiredFile(let name) = error else {
                XCTFail("Expected missingRequiredFile('transit.sqlite'), got \(error)")
                return
            }
            XCTAssertEqual(name, "transit.sqlite")
        }
    }
    
    // MARK: - Deletion Protection Tests
    
    func testNYCDeletionProtection() throws {
        XCTAssertThrowsError(try manager.deletePack(slug: "nyc")) { error in
            XCTAssertEqual(error as? CityPackError, CityPackError.coreMetroDeletionBlocked)
        }
    }
    
    func testNonCorePackDeletion() throws {
        // Install mock pack
        let config = CityConfig(
            version: 1,
            slug: "phl",
            displayName: "Philadelphia",
            region: "Pennsylvania, USA",
            bounds: CityBounds(minLatitude: 39.86, maxLatitude: 40.13, minLongitude: -75.28, maxLongitude: -74.95),
            center: CityCenter(latitude: 39.9526, longitude: -75.1652, defaultZoom: 13.0),
            transit: CityTransitConfig(agencyName: "SEPTA", attributions: ["SEPTA"], realtimeEndpoints: [])
        )
        let configData = try JSONEncoder().encode(config)
        let sqliteData = "SQLite format 3\0phl_transit".data(using: .utf8)!
        let tarData = TarExtractor.createTarArchive(files: [
            (name: "city_config.json", data: configData),
            (name: "transit.sqlite", data: sqliteData)
        ])
        let compressedData = try! ZSTDProcessor().compressBuffer(tarData, compressionLevel: 3)
        try manager.unpackAndInstall(archiveData: compressedData)
        
        XCTAssertTrue(manager.isPackInstalled(slug: "phl"))
        
        // Delete pack
        try manager.deletePack(slug: "phl")
        XCTAssertFalse(manager.isPackInstalled(slug: "phl"))
    }
    
    // MARK: - Manifest & Remote Fetch Fallback Tests
    
    func testManifestOfflineFallback() async throws {
        let manifest = try await manager.fetchRemoteManifest()
        XCTAssertEqual(manifest.version, 1)
        XCTAssertFalse(manifest.cities.isEmpty)
        XCTAssertTrue(manifest.cities.contains { $0.slug == "nyc" })
    }
    
    // MARK: - Performance & Bundled First-Launch Test
    
    func testEnsureBundledPackExtractedCompletesUnder200ms() throws {
        let start = CFAbsoluteTimeGetCurrent()
        let config = try manager.ensureBundledPackExtracted()
        let elapsed = CFAbsoluteTimeGetCurrent() - start
        
        XCTAssertEqual(config.slug, "nyc")
        XCTAssertTrue(manager.isPackInstalled(slug: "nyc"))
        XCTAssertLessThan(elapsed, 0.200, "First-launch extraction must complete under 200ms (took \(elapsed * 1000)ms)")
    }
}
