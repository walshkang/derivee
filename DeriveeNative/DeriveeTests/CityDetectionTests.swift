import XCTest
import CoreLocation
@testable import Derivee

/// Mock geocoder for deterministic testing of offline and fallback resolution.
private struct MockCityGeocoder: CityGeocoder {
    let mockLocality: String?
    let shouldThrow: Bool
    
    init(mockLocality: String? = nil, shouldThrow: Bool = false) {
        self.mockLocality = mockLocality
        self.shouldThrow = shouldThrow
    }
    
    func reverseGeocode(coordinate: CLLocationCoordinate2D) async throws -> String? {
        if shouldThrow {
            throw NSError(domain: "MockGeocoderError", code: -1, userInfo: nil)
        }
        return mockLocality
    }
}

@MainActor
final class CityDetectionTests: XCTestCase {
    private var testUserDefaults: UserDefaults!
    private let testSuiteName = "com.derivee.test.citydetection"
    
    override func setUp() {
        super.setUp()
        testUserDefaults = UserDefaults(suiteName: testSuiteName)
        testUserDefaults.removePersistentDomain(forName: testSuiteName)
    }
    
    override func tearDown() {
        testUserDefaults.removePersistentDomain(forName: testSuiteName)
        testUserDefaults = nil
        super.tearDown()
    }
    
    // MARK: - Bounding Box Containment Math
    
    func testBoundingBoxContainment() {
        let nycBounds = CityConfig.nycDefault.bounds
        let manhattan = CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060)
        let brooklyn = CLLocationCoordinate2D(latitude: 40.6782, longitude: -73.9442)
        let boston = CLLocationCoordinate2D(latitude: 42.3601, longitude: -71.0589)
        
        XCTAssertTrue(nycBounds.contains(coordinate: manhattan), "Manhattan should be within NYC bounds")
        XCTAssertTrue(nycBounds.contains(coordinate: brooklyn), "Brooklyn should be within NYC bounds")
        XCTAssertFalse(nycBounds.contains(coordinate: boston), "Boston should NOT be within NYC bounds")
        
        let bosBounds = CityConfig.bostonDefault.bounds
        let beaconHill = CLLocationCoordinate2D(latitude: 42.3588, longitude: -71.0707)
        XCTAssertTrue(bosBounds.contains(coordinate: beaconHill), "Beacon Hill should be within Boston bounds")
        XCTAssertFalse(bosBounds.contains(coordinate: manhattan), "Manhattan should NOT be within Boston bounds")
    }
    
    func testBoundingBoxClampingAndRubberBand() {
        let bosBounds = CityConfig.bostonDefault.bounds
        let farNorth = CLLocationCoordinate2D(latitude: 42.60, longitude: -71.00)
        
        XCTAssertFalse(bosBounds.contains(coordinate: farNorth))
        let clamped = bosBounds.clampedCoordinate(for: farNorth)
        XCTAssertEqual(clamped.latitude, bosBounds.maxLatitude, accuracy: 1e-6)
        XCTAssertEqual(clamped.longitude, -71.00, accuracy: 1e-6)
        
        let nearNorth = CLLocationCoordinate2D(latitude: bosBounds.maxLatitude + 0.02, longitude: -71.00)
        XCTAssertTrue(bosBounds.isWithinRubberBandLimit(nearNorth, margin: 0.05))
    }
    
    // MARK: - Manifest Lookups
    
    func testManifestLookups() {
        let manifest = CityManifest.defaultManifest
        
        let nyc = manifest.findCity(bySlug: "nyc")
        XCTAssertNotNil(nyc)
        XCTAssertEqual(nyc?.displayName, "New York City")
        XCTAssertTrue(nyc?.isBundled ?? false)
        
        let bos = manifest.findCity(bySlug: "bos")
        XCTAssertNotNil(bos)
        XCTAssertEqual(bos?.displayName, "Boston")
        XCTAssertFalse(bos?.isBundled ?? true)
        
        let backBay = CLLocationCoordinate2D(latitude: 42.3503, longitude: -71.0810)
        let foundCity = manifest.findCity(containing: backBay)
        XCTAssertEqual(foundCity?.slug, "bos")
    }
    
    // MARK: - City Detection Pipeline
    
    func testActiveCityNoSwitch() {
        let service = CityDetectionService(userDefaults: testUserDefaults)
        XCTAssertEqual(service.activeCitySlug, "nyc")
        
        // Location in Manhattan
        let manhattanLoc = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060),
            altitude: 10,
            horizontalAccuracy: 5.0,
            verticalAccuracy: 5.0,
            timestamp: Date()
        )
        
        service.evaluateLocation(manhattanLoc)
        
        XCTAssertEqual(service.activeCitySlug, "nyc")
        XCTAssertNil(service.promptCity, "Should not prompt when already in active city")
        XCTAssertNil(service.autoSwitchToast, "Should not toast when already in active city")
    }
    
    func testUninstalledCityTriggersPromptSheet() {
        let service = CityDetectionService(userDefaults: testUserDefaults)
        XCTAssertEqual(service.activeCitySlug, "nyc")
        XCTAssertFalse(service.isCityInstalled("bos"))
        
        // Boston GPS fix
        let bostonLoc = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 42.3601, longitude: -71.0589),
            altitude: 10,
            horizontalAccuracy: 8.0,
            verticalAccuracy: 5.0,
            timestamp: Date()
        )
        
        service.evaluateLocation(bostonLoc)
        
        XCTAssertEqual(service.activeCitySlug, "nyc", "Active city should not switch until installed")
        XCTAssertEqual(service.promptCity?.slug, "bos", "Prompt sheet should target Boston")
        XCTAssertNil(service.autoSwitchToast, "Should not show auto-switch toast for uninstalled pack")
    }
    
    func testInstalledCityTriggersSilentAutoSwitchAndToast() {
        let service = CityDetectionService(userDefaults: testUserDefaults)
        service.markCityInstalled("bos")
        XCTAssertTrue(service.isCityInstalled("bos"))
        
        var callbackFired = false
        service.onActiveCityChanged = { slug in
            if slug == "bos" { callbackFired = true }
        }
        
        let bostonLoc = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 42.3601, longitude: -71.0589),
            altitude: 10,
            horizontalAccuracy: 12.0,
            verticalAccuracy: 5.0,
            timestamp: Date()
        )
        
        service.evaluateLocation(bostonLoc)
        
        XCTAssertEqual(service.activeCitySlug, "bos", "Active city should automatically switch to Boston")
        XCTAssertNil(service.promptCity, "Should not prompt when already installed")
        XCTAssertNotNil(service.autoSwitchToast, "Should display auto-switch toast")
        XCTAssertEqual(service.autoSwitchToast?.cityName, "Boston")
        XCTAssertEqual(service.autoSwitchToast?.message, "Welcome to Boston • Switched active city")
        XCTAssertTrue(callbackFired, "Active city change callback should fire")
    }
    
    // MARK: - 7-Day Nag Snooze Logic
    
    func testSevenDayNagSnooze() {
        let service = CityDetectionService(userDefaults: testUserDefaults)
        let bostonLoc = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 42.3601, longitude: -71.0589),
            altitude: 10,
            horizontalAccuracy: 10.0,
            verticalAccuracy: 5.0,
            timestamp: Date()
        )
        
        // Initial detection shows prompt
        service.evaluateLocation(bostonLoc)
        XCTAssertEqual(service.promptCity?.slug, "bos")
        
        // User taps "Not Now" -> snoozes for 7 days
        let now = Date()
        service.snoozeCity(slug: "bos", from: now)
        XCTAssertNil(service.promptCity, "Prompt sheet should clear on snooze")
        XCTAssertTrue(service.isSnoozed(slug: "bos", referenceDate: now))
        
        // Next GPS fix 2 days later -> should NOT prompt
        let twoDaysLater = now.addingTimeInterval(2 * 86400)
        XCTAssertTrue(service.isSnoozed(slug: "bos", referenceDate: twoDaysLater))
        
        service.evaluateLocation(bostonLoc)
        XCTAssertNil(service.promptCity, "Should not prompt while snoozed")
        
        // 8 days later -> snooze expired -> should prompt again
        let eightDaysLater = now.addingTimeInterval(8 * 86400)
        XCTAssertFalse(service.isSnoozed(slug: "bos", referenceDate: eightDaysLater))
        
        // Clear snooze manually
        service.clearSnooze(slug: "bos")
        XCTAssertFalse(service.isSnoozed(slug: "bos"))
        service.evaluateLocation(bostonLoc)
        XCTAssertEqual(service.promptCity?.slug, "bos", "Prompt sheet should reappear after snooze cleared")
    }
    
    // MARK: - Inaccurate Fix Ignored
    
    func testInaccurateGPSFixIgnored() {
        let service = CityDetectionService(userDefaults: testUserDefaults)
        
        // Boston coordinate with poor 50m accuracy (> 25m threshold)
        let inaccurateLoc = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 42.3601, longitude: -71.0589),
            altitude: 10,
            horizontalAccuracy: 50.0,
            verticalAccuracy: 5.0,
            timestamp: Date()
        )
        
        service.evaluateLocation(inaccurateLoc)
        XCTAssertNil(service.promptCity, "Inaccurate GPS fix should be dropped by city detection")
        XCTAssertEqual(service.activeCitySlug, "nyc")
    }
    
    // MARK: - Geocoder Fallback
    
    func testGeocoderFallbackOutsideKnownBounds() async {
        let mockGeocoder = MockCityGeocoder(mockLocality: "Boston")
        let service = CityDetectionService(userDefaults: testUserDefaults, geocoder: mockGeocoder)
        
        // Outside the hard box (e.g. out at sea or border zone)
        let borderLoc = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 42.55, longitude: -70.85),
            altitude: 10,
            horizontalAccuracy: 15.0,
            verticalAccuracy: 5.0,
            timestamp: Date()
        )
        
        service.evaluateLocation(borderLoc)
        
        // Give background Task time to run
        try? await Task.sleep(nanoseconds: 100_000_000)
        
        XCTAssertEqual(service.promptCity?.slug, "bos", "Geocoder fallback should resolve locality to Boston manifest entry")
    }
}
