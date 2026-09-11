import XCTest
import WidgetKit
import SwiftUI
@testable import Derivee

@MainActor
final class ExplorationWidgetTests: XCTestCase {
    private var testSuiteName: String!
    private var testDefaults: UserDefaults!
    private var ipcService: AmbientTrackingIPCService!
    private var originalIPC: AmbientTrackingIPCService!
    
    override func setUpWithError() throws {
        testSuiteName = "com.derivee.test.widget.\(UUID().uuidString)"
        testDefaults = UserDefaults(suiteName: testSuiteName)!
        testDefaults.removePersistentDomain(forName: testSuiteName)
        originalIPC = AmbientTrackingIPCService.shared
        ipcService = AmbientTrackingIPCService(userDefaults: testDefaults)
        AmbientTrackingIPCService.shared = ipcService
    }
    
    override func tearDownWithError() throws {
        ipcService.stopListening()
        AmbientTrackingIPCService.shared = originalIPC
        if let suite = testSuiteName {
            testDefaults?.removePersistentDomain(forName: suite)
        }
    }
    
    // MARK: - ControlWidget Value Provider Tests
    
    func testTrackingControlValueProvider_InactiveAndActive() async throws {
        guard #available(iOS 18.0, *) else {
            throw XCTSkip("ControlWidget requires iOS 18.0+")
        }
        
        let provider = TrackingControlValueProvider()
        XCTAssertTrue(provider.previewValue, "Preview value should default to true for demonstration")
        
        // Initial inactive state
        testDefaults.set(false, forKey: AppGroupKeys.isTrackingActive)
        let inactiveValue = try await provider.currentValue()
        XCTAssertFalse(inactiveValue, "Control value should reflect inactive state")
        
        // Active state with hexes
        ipcService.publishEngineState(
            isActive: true,
            sessionHexCount: 14,
            sessionDistanceMeters: 1850.0,
            activeNeighborhood: "Nolita"
        )
        let activeValue = try await provider.currentValue()
        XCTAssertTrue(activeValue, "Control value should reflect active state")
    }
    
    // MARK: - Timeline Provider Tests
    
    func testExplorationTimelineProvider_PlaceholderAndSnapshot() {
        let provider = ExplorationTimelineProvider()
        
        // Test default placeholder
        let placeholder = ExplorationTimelineProvider.defaultPlaceholder
        XCTAssertTrue(placeholder.status.isActive)
        XCTAssertEqual(placeholder.status.sessionHexCount, 12)
        XCTAssertEqual(placeholder.status.activeNeighborhood, "SoHo")
        
        // Test snapshot when paused
        testDefaults.set(false, forKey: AppGroupKeys.isTrackingActive)
        testDefaults.set(0, forKey: AppGroupKeys.sessionHexCount)
        
        let pausedSnapshot = provider.createSnapshot()
        XCTAssertFalse(pausedSnapshot.status.isActive)
        XCTAssertEqual(pausedSnapshot.status.sessionHexCount, 0)
    }
    
    func testExplorationTimelineProvider_TimelineGeneration() {
        let provider = ExplorationTimelineProvider()
        
        ipcService.publishEngineState(
            isActive: true,
            sessionHexCount: 23,
            sessionDistanceMeters: 3200.0,
            activeNeighborhood: "DUMBO"
        )
        
        let timeline = provider.createTimeline()
        XCTAssertEqual(timeline.entries.count, 1)
        guard let entry = timeline.entries.first else {
            XCTFail("Timeline should contain at least 1 entry")
            return
        }
        XCTAssertTrue(entry.status.isActive)
        XCTAssertEqual(entry.status.sessionHexCount, 23)
        XCTAssertEqual(entry.status.sessionDistanceMeters, 3200.0)
        XCTAssertEqual(entry.status.activeNeighborhood, "DUMBO")
        XCTAssertEqual(timeline.policy, .never, "Timeline policy should be .never since updates are driven reactively via WidgetCenter")
    }
    
    // MARK: - Entry Views & Layout Formatting Tests
    
    func testExplorationWidgetEntryView_Instantiation() {
        let status = AmbientTrackingStatus(
            isEnabled: true,
            isActive: true,
            sessionHexCount: 8,
            sessionDistanceMeters: 950.0,
            activeNeighborhood: "West Village",
            lastUpdated: Date()
        )
        let entry = ExplorationWidgetEntry(date: Date(), status: status)
        let view = ExplorationWidgetEntryView(entry: entry)
        
        XCTAssertNotNil(view.body)
        XCTAssertEqual(entry.status.sessionHexCount, 8)
        XCTAssertEqual(entry.status.activeNeighborhood, "West Village")
    }
    
    func testExplorationMetricsWidgetConfigurationProperties() {
        let widget = ExplorationMetricsWidget()
        XCTAssertEqual(ExplorationMetricsWidget.kind, "com.derivee.ExplorationMetricsWidget")
        XCTAssertNotNil(widget.body)
    }
    
    func testTrackingControlWidgetConfigurationProperties() {
        guard #available(iOS 18.0, *) else {
            return
        }
        let controlWidget = TrackingControlWidget()
        XCTAssertEqual(TrackingControlWidget.kind, "com.derivee.TrackingControlWidget")
        XCTAssertNotNil(controlWidget.body)
    }
    
    func testDistanceFormattingThresholds() {
        let statusMeters = AmbientTrackingStatus(
            isEnabled: true,
            isActive: true,
            sessionHexCount: 1,
            sessionDistanceMeters: 450.0,
            activeNeighborhood: "Chelsea",
            lastUpdated: Date()
        )
        let entryMeters = ExplorationWidgetEntry(date: Date(), status: statusMeters)
        XCTAssertEqual(entryMeters.status.sessionDistanceMeters, 450.0)
        
        let statusKm = AmbientTrackingStatus(
            isEnabled: true,
            isActive: true,
            sessionHexCount: 10,
            sessionDistanceMeters: 2450.0,
            activeNeighborhood: "Chelsea",
            lastUpdated: Date()
        )
        let entryKm = ExplorationWidgetEntry(date: Date(), status: statusKm)
        XCTAssertEqual(entryKm.status.sessionDistanceMeters, 2450.0)
    }
}
