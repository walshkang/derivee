import XCTest
import CoreLocation
@testable import Derivee

@MainActor
final class AmbientTrackingIPCTests: XCTestCase {
    private var testSuiteName: String!
    private var testDefaults: UserDefaults!
    private var ipcService: AmbientTrackingIPCService!
    
    override func setUpWithError() throws {
        testSuiteName = "com.derivee.test.ipc.\(UUID().uuidString)"
        testDefaults = UserDefaults(suiteName: testSuiteName)!
        testDefaults.removePersistentDomain(forName: testSuiteName)
        ipcService = AmbientTrackingIPCService(userDefaults: testDefaults)
    }
    
    override func tearDownWithError() throws {
        ipcService.stopListening()
        if let suite = testSuiteName {
            testDefaults?.removePersistentDomain(forName: suite)
        }
    }
    
    func testPublishEngineStateAndStatusSnapshot() {
        // Initially empty
        let initial = ipcService.currentStatus()
        XCTAssertTrue(initial.isEnabled)
        XCTAssertFalse(initial.isActive)
        XCTAssertEqual(initial.sessionHexCount, 0)
        XCTAssertNil(initial.activeNeighborhood)
        XCTAssertTrue(initial.dialogSummary.contains("paused"))
        
        // Publish active state with neighborhood
        ipcService.publishEngineState(
            isActive: true,
            sessionHexCount: 5,
            sessionDistanceMeters: 800.0,
            activeNeighborhood: "Tribeca"
        )
        
        let activeStatus = ipcService.currentStatus()
        XCTAssertTrue(activeStatus.isActive)
        XCTAssertTrue(activeStatus.isEnabled)
        XCTAssertEqual(activeStatus.sessionHexCount, 5)
        XCTAssertEqual(activeStatus.sessionDistanceMeters, 800.0)
        XCTAssertEqual(activeStatus.activeNeighborhood, "Tribeca")
        XCTAssertTrue(activeStatus.dialogSummary.contains("5 hexes"))
        XCTAssertTrue(activeStatus.dialogSummary.contains("Tribeca"))
        
        // Publish inactive state
        ipcService.publishEngineState(
            isActive: false,
            sessionHexCount: 0,
            sessionDistanceMeters: 0.0,
            activeNeighborhood: nil
        )
        
        let inactiveStatus = ipcService.currentStatus()
        XCTAssertFalse(inactiveStatus.isActive)
        XCTAssertEqual(inactiveStatus.sessionHexCount, 0)
        XCTAssertNil(inactiveStatus.activeNeighborhood)
        XCTAssertTrue(inactiveStatus.dialogSummary.contains("paused"))
    }
    
    func testDarwinCommandNotificationDispatchAndReceipt() {
        let expectation = expectation(description: "Darwin command notification received")
        
        ipcService.registerCommandHandler(queue: .main) { requestedState in
            XCTAssertEqual(requestedState, true)
            expectation.fulfill()
        }
        
        // Dispatch command
        ipcService.sendCommand(enable: true)
        
        wait(for: [expectation], timeout: 2.0)
    }
    
    func testDarwinStatusNotificationDispatchAndReceipt() {
        let expectation = expectation(description: "Darwin status notification received")
        
        ipcService.registerStatusHandler(queue: .main) { status in
            if status.isActive && status.sessionHexCount == 3 {
                expectation.fulfill()
            }
        }
        
        ipcService.publishEngineState(isActive: true, sessionHexCount: 3, sessionDistanceMeters: 450.0, activeNeighborhood: "SoHo")
        
        wait(for: [expectation], timeout: 2.0)
    }
    
    func testCrossProcessStateSyncWithAmbientTrackingEngine() async throws {
        let mockLocationProvider = MockLocationProvider()
        let dbManager = SpatialDatabaseManager.makeForTesting(inMemory: true)
        let engine = AmbientTrackingEngine(
            locationProvider: mockLocationProvider,
            databaseManager: dbManager,
            userDefaults: testDefaults,
            ipcService: ipcService
        )
        
        XCTAssertFalse(engine.isTracking)
        
        // Simulate out-of-process command to start tracking
        let startExpectation = expectation(description: "Engine starts tracking via Darwin IPC")
        ipcService.registerStatusHandler(queue: .main) { status in
            if status.isActive {
                startExpectation.fulfill()
            }
        }
        
        ipcService.sendCommand(enable: true)
        await fulfillment(of: [startExpectation], timeout: 2.0)
        XCTAssertTrue(engine.isTracking)
        XCTAssertTrue(engine.isTrackingEnabled)
        
        // Simulate out-of-process command to stop tracking
        let stopExpectation = expectation(description: "Engine stops tracking via Darwin IPC")
        ipcService.registerStatusHandler(queue: .main) { status in
            if !status.isActive {
                stopExpectation.fulfill()
            }
        }
        
        ipcService.sendCommand(enable: false)
        await fulfillment(of: [stopExpectation], timeout: 2.0)
        XCTAssertFalse(engine.isTracking)
        XCTAssertFalse(engine.isTrackingEnabled)
        
        await engine.stopTracking()
        mockLocationProvider.finish()
    }
    
    func testColdLaunchIsolationLatencyBudget() {
        let start = CACurrentMediaTime()
        let isolatedDefaults = UserDefaults(suiteName: "com.derivee.test.coldlaunch.\(UUID().uuidString)")!
        let isolatedIPC = AmbientTrackingIPCService(userDefaults: isolatedDefaults)
        let status = isolatedIPC.currentStatus()
        let elapsedMs = (CACurrentMediaTime() - start) * 1000.0
        
        XCTAssertFalse(status.isActive)
        XCTAssertLessThan(elapsedMs, 15.0, "Headless IPC status check must execute under 15ms without initializing MapLibre")
    }
}
