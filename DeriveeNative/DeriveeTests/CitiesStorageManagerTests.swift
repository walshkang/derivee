import XCTest
import SwiftUI
import CoreLocation
import SnapshotTesting
@testable import Derivee

final class CitiesStorageManagerTests: XCTestCase {
    var fileManager: FileManager!
    var tempDirectoryURL: URL!
    var manager: CityPackManager!
    var dbManager: SpatialDatabaseManager!
    
    override func setUpWithError() throws {
        super.setUp()
        fileManager = FileManager.default
        tempDirectoryURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("StorageManagerTests_\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: tempDirectoryURL, withIntermediateDirectories: true, attributes: nil)
        
        manager = CityPackManager(
            fileManager: fileManager,
            remoteManifestURL: URL(string: "https://cdn.derivee.app/cities.json")!
        )
        dbManager = SpatialDatabaseManager.shared
    }
    
    override func tearDownWithError() throws {
        if let temp = tempDirectoryURL, fileManager.fileExists(atPath: temp.path) {
            try? fileManager.removeItem(at: temp)
        }
        super.tearDown()
    }
    
    // MARK: - Disk Breakdown Tests
    
    func testComponentDiskBreakdownCalculation() throws {
        let slug = "test_metro_\(UUID().uuidString.prefix(6))"
        let packDir = manager.packDirectoryURL(for: slug)
        try fileManager.createDirectory(at: packDir, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: packDir) }
        
        let sampleConfig = CityConfig(
            version: 1,
            slug: slug,
            displayName: "Test Metro",
            region: "Testland",
            bounds: CityBounds(minLatitude: 40.0, maxLatitude: 41.0, minLongitude: -74.0, maxLongitude: -73.0),
            center: CityCenter(latitude: 40.5, longitude: -73.5)
        )
        
        let configData = try JSONEncoder().encode(sampleConfig)
        let transitData = Data(repeating: 0x42, count: 50_000) // 50 KB
        let geojsonData = Data(repeating: 0x24, count: 20_000) // 20 KB
        
        try configData.write(to: manager.configURL(for: slug))
        try transitData.write(to: manager.transitDatabaseURL(for: slug))
        try geojsonData.write(to: manager.transitLinesGeoJSONURL(for: slug))
        
        let breakdown = manager.calculateDiskBreakdown(slug: slug)
        
        XCTAssertEqual(breakdown.configBytes, Int64(configData.count))
        XCTAssertEqual(breakdown.transitDatabaseBytes, 50_000)
        XCTAssertEqual(breakdown.transitLinesGeoJSONBytes, 20_000)
        XCTAssertEqual(breakdown.totalBytes, Int64(configData.count + 50_000 + 20_000))
        
        XCTAssertFalse(breakdown.formattedTotal.isEmpty)
        XCTAssertFalse(breakdown.formattedTransitDB.isEmpty)
        XCTAssertFalse(breakdown.formattedTransitLines.isEmpty)
        XCTAssertFalse(breakdown.formattedConfig.isEmpty)
    }
    
    // MARK: - Version Comparison Tests
    
    func testVersionComparisonAndUpdateAvailability() {
        let entry = CityManifestEntry(
            slug: "bos",
            displayName: "Boston",
            region: "Massachusetts, USA",
            compressedSizeBytes: 9_400_000,
            uncompressedSizeBytes: 22_100_000,
            isBundled: false,
            version: "1.2.0"
        )
        
        XCTAssertTrue(entry.isNewerThan(installedVersion: "1.1.0"))
        XCTAssertTrue(entry.isNewerThan(installedVersion: "1.0.0"))
        XCTAssertFalse(entry.isNewerThan(installedVersion: "1.2.0"))
        XCTAssertFalse(entry.isNewerThan(installedVersion: "1.3.0"))
        XCTAssertFalse(entry.isNewerThan(installedVersion: "2.0.0"))
        
        XCTAssertEqual(CityManifestEntry.compareVersionStrings(remote: "2.0.0", installed: "1.9.9"), 1)
        XCTAssertEqual(CityManifestEntry.compareVersionStrings(remote: "1.0.0", installed: "1.0.0"), 0)
        XCTAssertEqual(CityManifestEntry.compareVersionStrings(remote: "1.0.1", installed: "1.1.0"), -1)
    }
    
    // MARK: - Decoupled Deletion & Exploration Preservation
    
    func testDecoupledDeletionPreservesExplorationData() async throws {
        let testSlug = "bos"
        let testHexes = ["892a100d2b7ffff", "892a100d2b3ffff", "892a100d2a7ffff"]
        
        // 1. Insert explored hexes for Boston into SQLite database
        try await dbManager.insertHexesBatch(h3Indices: testHexes, citySlug: testSlug)
        
        let hexesBefore = try await dbManager.fetchExploredHexes(citySlug: testSlug)
        XCTAssertEqual(hexesBefore.count, 3)
        
        // 2. Create mock static pack assets on disk
        let packDir = manager.packDirectoryURL(for: testSlug)
        try fileManager.createDirectory(at: packDir, withIntermediateDirectories: true)
        
        let sampleConfig = CityConfig.bostonDefault
        let configData = try JSONEncoder().encode(sampleConfig)
        try configData.write(to: manager.configURL(for: testSlug))
        try "dummy_transit".data(using: .utf8)!.write(to: manager.transitDatabaseURL(for: testSlug))
        
        XCTAssertTrue(manager.isPackInstalled(slug: testSlug))
        
        // 3. Perform decoupled deletion of pack assets
        try manager.deletePack(slug: testSlug)
        
        // 4. Verify static assets removed from disk
        XCTAssertFalse(manager.isPackInstalled(slug: testSlug))
        XCTAssertFalse(fileManager.fileExists(atPath: packDir.path))
        
        // 5. Verify SQLite exploration history remains 100% intact
        let hexesAfter = try await dbManager.fetchExploredHexes(citySlug: testSlug)
        XCTAssertEqual(hexesAfter.count, 3, "Explored hexes must remain in SQLite after static pack deletion")
        XCTAssertEqual(hexesAfter, Set(testHexes))
    }
    
    // MARK: - NYC Core Protection
    
    func testNYCCoreProtection() {
        XCTAssertThrowsError(try manager.deletePack(slug: "nyc")) { error in
            guard case CityPackError.coreMetroDeletionBlocked = error else {
                XCTFail("Expected coreMetroDeletionBlocked error, got \(error)")
                return
            }
        }
    }
    
    // MARK: - Attributions Aggregation
    
    func testDynamicAgencyAttributionsAggregation() {
        let attributions = manager.allInstalledAttributions()
        // NYC default pack should contribute MTA attributions
        if let mtaList = attributions["Metropolitan Transportation Authority"] {
            XCTAssertFalse(mtaList.isEmpty)
            XCTAssertTrue(mtaList.contains(where: { $0.contains("MTA") }))
        }
    }
    
    // MARK: - City Detection Service State Synchronization
    
    @MainActor
    func testCityDetectionServiceStateSyncOnDownloadAndDeletion() {
        let testDefaults = UserDefaults(suiteName: "com.derivee.test.storagemanager")!
        testDefaults.removePersistentDomain(forName: "com.derivee.test.storagemanager")
        defer { testDefaults.removePersistentDomain(forName: "com.derivee.test.storagemanager") }
        
        let detectionService = CityDetectionService(userDefaults: testDefaults)
        XCTAssertFalse(detectionService.isCityInstalled("bos"))
        
        // Mark installed on download completion
        detectionService.markCityInstalled("bos")
        XCTAssertTrue(detectionService.isCityInstalled("bos"))
        
        // Mark uninstalled on deletion
        detectionService.markCityUninstalled("bos")
        XCTAssertFalse(detectionService.isCityInstalled("bos"))
    }
    
    @MainActor
    func testSwitchActiveMetro() {
        let testDefaults = UserDefaults(suiteName: "com.derivee.test.storageswitch")!
        testDefaults.removePersistentDomain(forName: "com.derivee.test.storageswitch")
        defer { testDefaults.removePersistentDomain(forName: "com.derivee.test.storageswitch") }
        
        let detectionService = CityDetectionService(userDefaults: testDefaults)
        XCTAssertEqual(detectionService.activeCitySlug, "nyc")
        
        var callbackFired = false
        detectionService.onActiveCityChanged = { slug in
            if slug == "bos" { callbackFired = true }
        }
        
        let bostonEntry = CityManifest.defaultManifest.findCity(bySlug: "bos")!
        detectionService.performAutoSwitch(to: bostonEntry)
        
        XCTAssertEqual(detectionService.activeCitySlug, "bos")
        XCTAssertTrue(callbackFired)
        XCTAssertEqual(detectionService.autoSwitchToast?.cityName, "Boston")
    }
    
    // MARK: - Visual Snapshot Test
    
    @MainActor
    func testCitiesStorageManagerViewSnapshot() {
        let testDefaults = UserDefaults(suiteName: "com.derivee.test.storagesnapshot")!
        testDefaults.removePersistentDomain(forName: "com.derivee.test.storagesnapshot")
        let detectionService = CityDetectionService(userDefaults: testDefaults)
        
        let view = NavigationStack {
            CitiesStorageManagerView(
                packManager: manager,
                spatialDatabaseManager: dbManager,
                cityDetectionService: detectionService
            )
        }
        .frame(width: 393, height: 852)
        
        let vc = UIHostingController(rootView: view)
        vc.overrideUserInterfaceStyle = .light
        assertSnapshot(of: vc, as: .image(on: ViewImageConfig(size: CGSize(width: 393, height: 852)), precision: 0.98))
    }
}
