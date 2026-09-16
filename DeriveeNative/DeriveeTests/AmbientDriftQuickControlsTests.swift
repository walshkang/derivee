import XCTest
import SwiftUI
import CoreLocation
@testable import Derivee

@MainActor
final class AmbientDriftQuickControlsTests: XCTestCase {
    
    // MARK: - 1. AmbientDriftFAB & DriftStatusPill Rendering Tests
    
    func testAmbientDriftFAB_ActiveStateRenders() {
        var didTap = false
        let fab = AmbientDriftFAB(isTracking: true) {
            didTap = true
        }
        
        let hosting = UIHostingController(rootView: fab)
        XCTAssertNotNil(hosting.view)
        XCTAssertFalse(didTap)
    }
    
    func testAmbientDriftFAB_PausedStateRenders() {
        var didTap = false
        let fab = AmbientDriftFAB(isTracking: false) {
            didTap = true
        }
        
        let hosting = UIHostingController(rootView: fab)
        XCTAssertNotNil(hosting.view)
        XCTAssertFalse(didTap)
    }
    
    func testDriftStatusPill_ActiveAndPausedState() {
        var didTap = false
        let pillActive = DriftStatusPill(isTracking: true) {
            didTap = true
        }
        let pillPaused = DriftStatusPill(isTracking: false) {
            didTap = true
        }
        
        let hostingActive = UIHostingController(rootView: pillActive)
        let hostingPaused = UIHostingController(rootView: pillPaused)
        XCTAssertNotNil(hostingActive.view)
        XCTAssertNotNil(hostingPaused.view)
    }
    
    // MARK: - 2. AmbientDriftControlCard Telemetry & Switch Tests
    
    func testAmbientDriftControlCard_InitializesAndRenders() {
        let userDefaults = UserDefaults(suiteName: "test.quickcontrols.\(UUID().uuidString)")!
        let trackingEngine = AmbientTrackingEngine(
            locationProvider: MockLocationProvider(),
            databaseManager: .shared,
            userDefaults: userDefaults
        )
        
        let card = AmbientDriftControlCard(trackingEngine: trackingEngine)
        let hosting = UIHostingController(rootView: card)
        XCTAssertNotNil(hosting.view)
    }
    
    func testAmbientTrackingEngine_ToggleTrackingCycle() async {
        let userDefaults = UserDefaults(suiteName: "test.quickcontrols.toggle.\(UUID().uuidString)")!
        let trackingEngine = AmbientTrackingEngine(
            locationProvider: MockLocationProvider(),
            databaseManager: .shared,
            userDefaults: userDefaults
        )
        
        // Initial state
        XCTAssertFalse(trackingEngine.isTracking)
        
        // Toggle ON
        trackingEngine.toggleTracking()
        XCTAssertTrue(trackingEngine.isTracking)
        XCTAssertTrue(trackingEngine.isTrackingEnabled)
        
        // Toggle OFF
        trackingEngine.toggleTracking()
        // Wait briefly for Task detached teardown
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertFalse(trackingEngine.isTracking)
        XCTAssertFalse(trackingEngine.isTrackingEnabled)
    }
    
    func testAmbientTrackingEngine_LiveActivityPreferenceSync() {
        let userDefaults = UserDefaults(suiteName: "test.quickcontrols.liveactivity.\(UUID().uuidString)")!
        let trackingEngine = AmbientTrackingEngine(
            locationProvider: MockLocationProvider(),
            databaseManager: .shared,
            userDefaults: userDefaults
        )
        
        trackingEngine.updateLiveActivityPreference(enabled: false)
        XCTAssertFalse(trackingEngine.isLiveActivityEnabled)
        XCTAssertFalse(userDefaults.bool(forKey: AppStorageKeys.isLiveActivityEnabled))
        
        trackingEngine.updateLiveActivityPreference(enabled: true)
        XCTAssertTrue(trackingEngine.isLiveActivityEnabled)
        XCTAssertTrue(userDefaults.bool(forKey: AppStorageKeys.isLiveActivityEnabled))
    }
    
    // MARK: - 3. Invariant FC-5 & FC-2 Static Audits
    
    func testAmbientDriftControlCard_FC5ZeroNestedSheets() throws {
        let filePath = #filePath
        let testsDir = URL(fileURLWithPath: filePath).deletingLastPathComponent()
        let cardFile = testsDir.deletingLastPathComponent().appendingPathComponent("Derivee/AmbientDriftControlCard.swift")
        let content = try String(contentsOf: cardFile, encoding: .utf8)
        
        XCTAssertFalse(
            content.contains(".sheet("),
            "AmbientDriftControlCard must have zero nested sheets (FC-5 invariant)"
        )
    }
    
    func testAmbientDriftControlCard_FC2ZeroRawTelemetry() throws {
        let filePath = #filePath
        let testsDir = URL(fileURLWithPath: filePath).deletingLastPathComponent()
        let cardFile = testsDir.deletingLastPathComponent().appendingPathComponent("Derivee/AmbientDriftControlCard.swift")
        let content = try String(contentsOf: cardFile, encoding: .utf8)
        
        XCTAssertFalse(content.contains("TRIP "), "FC-2: Zero raw TRIP keys in user copy")
        XCTAssertFalse(content.contains("REALTIME"), "FC-2: Zero REALTIME jargon in user copy")
        XCTAssertFalse(content.contains("trip_id"), "FC-2: Zero trip_id in user copy")
        
        // Assert human operational subtitles are present
        XCTAssertTrue(content.contains("Active • Background GPS"), "Operational active status present")
        XCTAssertTrue(content.contains("Paused • Battery Preserved"), "Operational paused status present")
        XCTAssertTrue(content.contains("Dynamic Island Glance"), "Dynamic Island glance title present")
    }
}
