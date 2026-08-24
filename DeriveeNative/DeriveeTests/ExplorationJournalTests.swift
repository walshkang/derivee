import XCTest
import CoreLocation
import GRDB
import SnapshotTesting
import SwiftUI
@testable import Derivee

final class ExplorationJournalTests: XCTestCase {
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
            
            INSERT INTO stops (stop_id, stop_name, stop_lat, stop_lon, location_type) VALUES
            ('stop_bedford', 'Bedford Av', 40.7169, -73.9567, 1),
            ('stop_lorimer', 'Lorimer St', 40.7142, -73.9489, 1),
            ('stop_1av', 'First Avenue', 40.7308, -73.9816, 1),
            ('stop_3av', 'Third Avenue', 40.7328, -73.9860, 1),
            ('stop_union_sq', '14 St - Union Sq', 40.7347, -73.9907, 1);
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
    
    func testExplorationJournalDataAggregationPerformanceUnder12ms() async throws {
        // Insert sample explored hexes
        try await dbManager.insertDiscoveredHex(h3Index: "8b2a1072cb00fff")
        try await dbManager.insertDiscoveredHex(h3Index: "8b2a1072cb01fff")
        try await dbManager.insertDiscoveredPOI("stop_bedford")
        
        // Warm up connection
        _ = try await dbManager.fetchExplorationJournalData()
        
        let startTime = CFAbsoluteTimeGetCurrent()
        let journalData = try await dbManager.fetchExplorationJournalData()
        let elapsedMs = (CFAbsoluteTimeGetCurrent() - startTime) * 1000.0
        
        print("Exploration journal aggregation executed in \(elapsedMs)ms")
        XCTAssertLessThan(elapsedMs, 12.0, "Journal milestone queries must execute under 12ms")
        XCTAssertGreaterThan(journalData.totalClearedHexes, 0)
        XCTAssertEqual(journalData.milestoneCards.count, 3)
        XCTAssertEqual(journalData.boroughProgress.count, 5)
        XCTAssertEqual(journalData.landmarks.count, 20)
    }
    
    func testTransitHubsMilestoneEvaluation() async throws {
        // Initial state: 0 stations unlocked
        var journalData = try await dbManager.fetchExplorationJournalData()
        let initialTransitCard = try XCTUnwrap(journalData.milestoneCards.first(where: { $0.category == .transitHubs }))
        XCTAssertEqual(initialTransitCard.currentCount, 0)
        XCTAssertEqual(initialTransitCard.unlockedTierCount, 0)
        
        // Unlock 1 station via discovered_pois
        try await dbManager.insertDiscoveredPOI("stop_bedford")
        journalData = try await dbManager.fetchExplorationJournalData()
        let updatedTransitCard = try XCTUnwrap(journalData.milestoneCards.first(where: { $0.category == .transitHubs }))
        XCTAssertEqual(updatedTransitCard.currentCount, 1)
        XCTAssertEqual(updatedTransitCard.unlockedTierCount, 1)
        XCTAssertEqual(updatedTransitCard.tiers[0].title, "First Connection")
        XCTAssertTrue(updatedTransitCard.tiers[0].isUnlocked)
        XCTAssertFalse(updatedTransitCard.tiers[1].isUnlocked)
    }
    
    func testHistoricLandmarkDiscoveryMatching() async throws {
        // Target: Grand Central Terminal
        let gct = try XCTUnwrap(HistoricLandmarkCatalog.landmarks.first(where: { $0.id == "landmark_grand_central" }))
        let gctHex = gct.h3Index
        XCTAssertFalse(gctHex.isEmpty)
        
        // Before discovery
        var journalData = try await dbManager.fetchExplorationJournalData()
        var gctDiscovery = try XCTUnwrap(journalData.landmarks.first(where: { $0.id == gct.id }))
        XCTAssertFalse(gctDiscovery.isDiscovered)
        
        let landmarkCardInitial = try XCTUnwrap(journalData.milestoneCards.first(where: { $0.category == .historicLandmarks }))
        XCTAssertEqual(landmarkCardInitial.unlockedTierCount, 0)
        
        // Discover Grand Central Terminal by walking into its hex
        try await dbManager.insertDiscoveredHex(h3Index: gctHex)
        
        journalData = try await dbManager.fetchExplorationJournalData()
        gctDiscovery = try XCTUnwrap(journalData.landmarks.first(where: { $0.id == gct.id }))
        XCTAssertTrue(gctDiscovery.isDiscovered)
        
        let landmarkCardUpdated = try XCTUnwrap(journalData.milestoneCards.first(where: { $0.category == .historicLandmarks }))
        XCTAssertEqual(landmarkCardUpdated.currentCount, 1)
        XCTAssertEqual(landmarkCardUpdated.unlockedTierCount, 1)
        XCTAssertEqual(landmarkCardUpdated.tiers[0].title, "Sightseer")
        XCTAssertTrue(landmarkCardUpdated.tiers[0].isUnlocked)
    }
    
    func testNeighborhoodVoyagerBoroughAggregation() async throws {
        let journalData = try await dbManager.fetchExplorationJournalData()
        XCTAssertEqual(journalData.boroughProgress.count, 5)
        
        let boroughCodes = Set(journalData.boroughProgress.map { $0.id })
        XCTAssertTrue(boroughCodes.contains("MN"))
        XCTAssertTrue(boroughCodes.contains("BK"))
        XCTAssertTrue(boroughCodes.contains("QN"))
        XCTAssertTrue(boroughCodes.contains("BX"))
        XCTAssertTrue(boroughCodes.contains("SI"))
        
        let voyagerCard = try XCTUnwrap(journalData.milestoneCards.first(where: { $0.category == .neighborhoodVoyager }))
        XCTAssertEqual(voyagerCard.tiers.count, 5)
    }
    
    func testMilestoneModelsCalculations() {
        let tiers = [
            MilestoneTier(category: .transitHubs, tierNumber: 1, title: "T1", requirementDescription: "Req 1", targetCount: 1, badgeIconName: "icon1", isUnlocked: true),
            MilestoneTier(category: .transitHubs, tierNumber: 2, title: "T2", requirementDescription: "Req 2", targetCount: 10, badgeIconName: "icon2", isUnlocked: false)
        ]
        
        let progress = MilestoneProgress(category: .transitHubs, currentCount: 5, totalCount: 20, tiers: tiers)
        XCTAssertEqual(progress.percentage, 25.0)
        XCTAssertEqual(progress.unlockedTierCount, 1)
        XCTAssertEqual(progress.currentTier?.title, "T1")
        XCTAssertEqual(progress.nextTier?.title, "T2")
    }
    
    @MainActor
    func testStatsViewJournalSnapshot() {
        let mockLocationProvider = MockLocationProvider()
        let engine = AmbientTrackingEngine(locationProvider: mockLocationProvider, databaseManager: dbManager)
        let store = SpatialStore(dbManager: dbManager)
        
        let targetCoordBinding = Binding<CLLocationCoordinate2D?>(get: { nil }, set: { _ in })
        let view = StatsView(trackingEngine: engine, spatialStore: store, targetCoordinate: targetCoordBinding)
            .environment(\.colorScheme, .light)
            .frame(width: 393, height: 852)
        
        let vc = UIHostingController(rootView: view)
        assertSnapshot(of: vc, as: .image(on: ViewImageConfig(size: CGSize(width: 393, height: 852)), precision: 0.98))
    }
}
