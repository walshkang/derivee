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
        // Wait for detached Task stopTracking teardown
        for _ in 0..<20 {
            if !trackingEngine.isTracking { break }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
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
    
    // MARK: - 4. Wave PE.10 Layout Integrity & Chrome Clearance Tests
    
    func testAmbientDriftControlCard_PE10HeaderGrabberClearance() throws {
        let filePath = #filePath
        let testsDir = URL(fileURLWithPath: filePath).deletingLastPathComponent()
        let cardFile = testsDir.deletingLastPathComponent().appendingPathComponent("Derivee/AmbientDriftControlCard.swift")
        let content = try String(contentsOf: cardFile, encoding: .utf8)
        
        // Assert header top padding is 24pt (>= 20pt per FC-11) to eliminate grabber collision
        XCTAssertTrue(
            content.contains(".padding(.top, 24)"),
            "AmbientDriftControlCard header must have 24pt top padding for system grabber clearance (PE.10 / FC-11)"
        )
        XCTAssertFalse(
            content.contains(".padding(.top, 2)"),
            "AmbientDriftControlCard must eliminate legacy 2pt header top padding grabber collision"
        )
    }
    
    func testAmbientDriftControlCard_PE10EscalationBannerNonTruncatingLayout() throws {
        let filePath = #filePath
        let testsDir = URL(fileURLWithPath: filePath).deletingLastPathComponent()
        let cardFile = testsDir.deletingLastPathComponent().appendingPathComponent("Derivee/AmbientDriftControlCard.swift")
        let content = try String(contentsOf: cardFile, encoding: .utf8)
        
        XCTAssertTrue(
            content.contains(".fixedSize(horizontal: false, vertical: true)"),
            "escalationBanner Text must specify .fixedSize(horizontal: false, vertical: true) for multi-line expansion (PE.10 / FC-12)"
        )
        XCTAssertTrue(
            content.contains(".layoutPriority(1)"),
            "escalationBanner Text must specify .layoutPriority(1) to prevent horizontal truncation"
        )
        XCTAssertTrue(
            content.contains("HStack(spacing: 8)"),
            "escalationBanner must optimize horizontal spacing with 8pt spacing"
        )
        XCTAssertTrue(
            content.contains("Spacer(minLength: 4)"),
            "escalationBanner must specify compact Spacer(minLength: 4) to maximize text layout room"
        )
    }
    
    func testAmbientDriftControlCard_PE10RenderedGeometryWithEscalationBanner() {
        let userDefaults = UserDefaults(suiteName: "test.pe10.geometry.\(UUID().uuidString)")!
        let trackingEngine = AmbientTrackingEngine(
            locationProvider: MockLocationProvider(),
            databaseManager: .shared,
            userDefaults: userDefaults
        )
        
        // Degraded authorization status triggers escalation banner
        trackingEngine.authorizationStatus = .authorizedWhenInUse
        
        let card = AmbientDriftControlCard(trackingEngine: trackingEngine)
        let hosting = UIHostingController(rootView: card)
        
        // Test on standard 375pt (iPhone SE / mini) width
        let size375 = hosting.sizeThatFits(in: CGSize(width: 375, height: CGFloat.greatestFiniteMagnitude))
        XCTAssertGreaterThan(size375.height, 300, "Card with escalation banner must measure > 300pt height")
        XCTAssertLessThan(size375.height, 500, "Card with escalation banner + safe areas must fit within 500pt bounds")
        
        // Test on 393pt (standard iPhone) width
        let size393 = hosting.sizeThatFits(in: CGSize(width: 393, height: CGFloat.greatestFiniteMagnitude))
        XCTAssertGreaterThan(size393.height, 300)
        
        // Compare with non-degraded card (authorizedAlways)
        let nonDegradedEngine = AmbientTrackingEngine(
            locationProvider: MockLocationProvider(),
            databaseManager: .shared,
            userDefaults: UserDefaults(suiteName: "test.pe10.nondegraded.\(UUID().uuidString)")!
        )
        nonDegradedEngine.authorizationStatus = .authorizedAlways
        let nonDegradedCard = AmbientDriftControlCard(trackingEngine: nonDegradedEngine)
        let nonDegradedHosting = UIHostingController(rootView: nonDegradedCard)
        let nonDegradedSize = nonDegradedHosting.sizeThatFits(in: CGSize(width: 375, height: CGFloat.greatestFiniteMagnitude))
        
        XCTAssertGreaterThan(
            size375.height, nonDegradedSize.height,
            "Degraded card with 2-line escalation banner must dynamically expand beyond non-degraded card"
        )
    }
}
