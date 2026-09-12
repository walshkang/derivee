import XCTest
import CoreLocation
import GRDB
@testable import Derivee

final class StopNameSanitizationTests: XCTestCase {
    
    private var dbManager: SpatialDatabaseManager!
    
    override func setUp() async throws {
        try await super.setUp()
        dbManager = SpatialDatabaseManager.shared
    }
    
    // MARK: - 1. Standalone Terminal Bay Patterns
    
    func testStandaloneTerminalBayPatternMatches() {
        // Standalone bay patterns like Bay <number> or Bay <letter> must be classified as generic
        let genericBays = ["Bay 3", "BAY 3", "Bay 12", "BAY 101", "Bay A", "BAY B", "Bay C", "Bay Z"]
        for bay in genericBays {
            XCTAssertTrue(
                dbManager.isGenericStopName(bay, stopId: "101"),
                "Standalone terminal bay '\(bay)' must be classified as generic."
            )
        }
        
        // Exact generic stop words
        XCTAssertTrue(dbManager.isGenericStopName("BAY", stopId: "101"))
        XCTAssertTrue(dbManager.isGenericStopName("Bay", stopId: "101"))
    }
    
    // MARK: - 2. Real Bay Streets & Subway Stations Protected
    
    func testBayStreetNamesNotGeneric() {
        // Real streets and stations beginning with "Bay " must NEVER be classified as generic
        let realBayStops = [
            "Bay St & Victory Blvd",
            "Bay Ridge Av",
            "Bay Pkwy",
            "Baychester Av",
            "Bay 50 St",
            "Bay Terrace",
            "Prince's Bay",
            "Sheepshead Bay",
            "Pelham Bay Park",
            "Bay St",
            "Bay Ridge Pkwy & 4 Av",
            "Bay Ridge Av & 13 Av"
        ]
        
        for stop in realBayStops {
            XCTAssertFalse(
                dbManager.isGenericStopName(stop, stopId: "STOP_XYZ"),
                "Real street or station '\(stop)' must NOT be classified as generic."
            )
        }
    }
    
    // MARK: - 3. Street Intersections & Suffixes Protected
    
    func testStreetIntersectionsAndSuffixesProtected() {
        // Intersections containing & or /
        XCTAssertFalse(dbManager.isGenericStopName("1 Av & E 14 St", stopId: "BUS_001"))
        XCTAssertFalse(dbManager.isGenericStopName("WILLIS AV/E 138 ST", stopId: "101014"))
        XCTAssertFalse(dbManager.isGenericStopName("Dock St & Water St", stopId: "DOCK_01"))
        XCTAssertFalse(dbManager.isGenericStopName("Gate Ave & Fulton St", stopId: "GATE_01"))
        
        // Named streets with standard street suffixes even if prefix resembles a generic keyword
        XCTAssertFalse(dbManager.isGenericStopName("Gate Ave", stopId: "101"))
        XCTAssertFalse(dbManager.isGenericStopName("Dock St", stopId: "101"))
        XCTAssertFalse(dbManager.isGenericStopName("Track Way", stopId: "101"))
        XCTAssertFalse(dbManager.isGenericStopName("Platform Rd", stopId: "101"))
        
        // Meanwhile, actual generic prefixes without street suffixes remain generic
        XCTAssertTrue(dbManager.isGenericStopName("Gate 201", stopId: "101"))
        XCTAssertTrue(dbManager.isGenericStopName("Platform A", stopId: "101"))
        XCTAssertTrue(dbManager.isGenericStopName("Stop #402", stopId: "101"))
        XCTAssertTrue(dbManager.isGenericStopName("Track 4", stopId: "101"))
        XCTAssertTrue(dbManager.isGenericStopName("Dock 2", stopId: "101"))
    }
    
    // MARK: - 4. Dispatch Noise Sanitization
    
    func testDispatchNoiseSanitization() {
        let noiseTokens = [
            "Ramp B S51 & S81",
            "Ramp A S62 & S92",
            "Ramp C S46 & S96",
            "Ramp D S44 & S94",
            "Ramp A S66",
            "Ramp B",
            "Ramp C",
            "Ramp D",
            "Saint George Ferry & Ramp B S51 & S81",
            "Saint George Ferry & Ramp A S62 & S92",
            "Saint George Ferry & Ramp C S46 & S96",
            "Saint George Ferry & Ramp D S44 & S94",
            "Saint George Ferry & Ramp B",
            "St George Ferry & Ramp B S51 & S81",
            "St. George Ferry & Ramp B S51 & S81"
        ]
        
        for token in noiseTokens {
            let sanitized = dbManager.sanitizeStopName(token)
            XCTAssertEqual(
                sanitized,
                "St George Ferry Terminal",
                "Noise token '\(token)' must sanitize to 'St George Ferry Terminal'."
            )
            
            // Sanitized token should not be considered generic
            XCTAssertFalse(
                dbManager.isGenericStopName(token, stopId: "203637"),
                "Noise token '\(token)' (which maps to 'St George Ferry Terminal') must not be generic."
            )
        }
    }
    
    // MARK: - 5. Legitimate Roadway Ramps Preserved
    
    func testLegitimateRoadwayRampsPreserved() {
        let realRamps = [
            "Main Rdwy & Exit Ramp",
            "Triboro Br & Ramp",
            "Parking Ramp & Access Rd",
            "University Av & G WB Bridge Entrance Ramp"
        ]
        
        for ramp in realRamps {
            let sanitized = dbManager.sanitizeStopName(ramp)
            XCTAssertEqual(
                sanitized,
                ramp,
                "Real roadway ramp '\(ramp)' must pass through unmodified."
            )
            XCTAssertFalse(
                dbManager.isGenericStopName(ramp, stopId: "RAMP_01"),
                "Real roadway ramp '\(ramp)' must not be generic."
            )
        }
    }
    
    // MARK: - 6. Database Integration: Bay St & Victory Blvd
    
    func testDatabaseStopDetailsBayStVictoryBlvd() async throws {
        // Stop 200153 is Bay St & Victory Blvd on Staten Island
        let details = try await dbManager.fetchStopDetails(for: "200153")
        XCTAssertEqual(
            details.name,
            "Bay St & Victory Blvd",
            "Stop 200153 must resolve directly to 'Bay St & Victory Blvd' without falling back to a nearby stop or placeholder."
        )
        XCTAssertFalse(details.name.contains("Area"), "Stop name must not have 'Area' suffix appended.")
    }
    
    // MARK: - 7. Database Integration: St George Ferry Terminal Ramps
    
    func testDatabaseStopDetailsStGeorgeFerryTerminal() async throws {
        // Stop 203637 is 'Saint George Ferry & Ramp B S51 & S81' in raw GTFS static
        let details = try await dbManager.fetchStopDetails(for: "203637")
        XCTAssertEqual(
            details.name,
            "St George Ferry Terminal",
            "Stop 203637 must resolve to sanitized 'St George Ferry Terminal'."
        )
    }
    
    // MARK: - 8. Database Integration: Subway Bay Stations
    
    func testDatabaseStopDetailsSubwayBayStations() async throws {
        // R42: Bay Ridge Av (R train)
        let r42 = try await dbManager.fetchStopDetails(for: "R42")
        XCTAssertEqual(r42.name, "Bay Ridge Av", "R42 must resolve to 'Bay Ridge Av'.")
        
        // B21: Bay Pkwy (D train)
        let b21 = try await dbManager.fetchStopDetails(for: "B21")
        XCTAssertEqual(b21.name, "Bay Pkwy", "B21 must resolve to 'Bay Pkwy'.")
        
        // 502: Baychester Av (5 train)
        let s502 = try await dbManager.fetchStopDetails(for: "502")
        XCTAssertEqual(s502.name, "Baychester Av", "502 must resolve to 'Baychester Av'.")
        
        // B23: Bay 50 St (D train)
        let b23 = try await dbManager.fetchStopDetails(for: "B23")
        XCTAssertEqual(b23.name, "Bay 50 St", "B23 must resolve to 'Bay 50 St'.")
    }
}
