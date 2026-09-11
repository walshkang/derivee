import XCTest
import AppIntents
@testable import Derivee

@MainActor
final class AppIntentSuiteTests: XCTestCase {
    private var testSuiteName: String!
    private var testDefaults: UserDefaults!
    private var ipcService: AmbientTrackingIPCService!
    private var originalIPC: AmbientTrackingIPCService!
    
    override func setUpWithError() throws {
        testSuiteName = "com.derivee.test.appintents.\(UUID().uuidString)"
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
    
    func testToggleAmbientTrackingIntent() async throws {
        let intent = ToggleAmbientTrackingIntent()
        
        // Start from known state (disabled)
        testDefaults.set(false, forKey: AppGroupKeys.isTrackingEnabled)
        
        // Toggle once (should turn on)
        _ = try await intent.perform()
        XCTAssertTrue(testDefaults.bool(forKey: AppGroupKeys.isTrackingEnabled))
        
        // Toggle again (should turn off)
        _ = try await intent.perform()
        XCTAssertFalse(testDefaults.bool(forKey: AppGroupKeys.isTrackingEnabled))
    }
    
    func testSetAmbientTrackingIntent() async throws {
        var intent = SetAmbientTrackingIntent()
        
        // Set explicitly to true
        intent.value = true
        _ = try await intent.perform()
        XCTAssertTrue(testDefaults.bool(forKey: AppGroupKeys.isTrackingEnabled))
        
        // Set explicitly to false
        intent.value = false
        _ = try await intent.perform()
        XCTAssertFalse(testDefaults.bool(forKey: AppGroupKeys.isTrackingEnabled))
    }
    
    func testStartAndStopAmbientTrackingIntents() async throws {
        let startIntent = StartAmbientTrackingIntent()
        let stopIntent = StopAmbientTrackingIntent()
        
        // Execute start intent
        _ = try await startIntent.perform()
        XCTAssertTrue(testDefaults.bool(forKey: AppGroupKeys.isTrackingEnabled))
        
        // Execute stop intent
        _ = try await stopIntent.perform()
        XCTAssertFalse(testDefaults.bool(forKey: AppGroupKeys.isTrackingEnabled))
    }
    
    func testGetAmbientTrackingStatusIntent() async throws {
        let intent = GetAmbientTrackingStatusIntent()
        
        // Inactive state
        testDefaults.set(false, forKey: AppGroupKeys.isTrackingActive)
        testDefaults.set(0, forKey: AppGroupKeys.sessionHexCount)
        testDefaults.removeObject(forKey: AppGroupKeys.activeNeighborhood)
        
        let resultInactive = try await intent.perform()
        XCTAssertEqual(resultInactive.value, false)
        
        // Active state with discoveries
        testDefaults.set(true, forKey: AppGroupKeys.isTrackingActive)
        testDefaults.set(7, forKey: AppGroupKeys.sessionHexCount)
        testDefaults.set(1250.0, forKey: AppGroupKeys.sessionDistanceMeters)
        testDefaults.set("SoHo", forKey: AppGroupKeys.activeNeighborhood)
        
        let resultActive = try await intent.perform()
        XCTAssertEqual(resultActive.value, true)
    }
    
    func testDeriveeShortcutsRegistration() {
        let shortcuts = DeriveeShortcuts.appShortcuts
        XCTAssertEqual(shortcuts.count, 4, "AppShortcutsProvider should declare 4 primary shortcuts.")
    }
}
