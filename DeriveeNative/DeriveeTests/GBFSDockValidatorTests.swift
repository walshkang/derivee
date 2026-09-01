import XCTest
import CoreLocation
@testable import Derivee

final class GBFSDockValidatorTests: XCTestCase {
    var dbManager: GBFSDatabaseManager!
    var validator: GBFSDockValidator!
    
    override func setUpWithError() throws {
        super.setUp()
        dbManager = GBFSDatabaseManager.makeForTesting(inMemory: true)
        validator = GBFSDockValidator(
            databaseManager: dbManager,
            defaultStalenessThresholdSeconds: 600.0,
            defaultMinBikes: 2,
            defaultMinDocks: 2,
            defaultFallbackRadiusMeters: 300.0,
            defaultDiversionPenaltySeconds: 120.0
        )
    }
    
    override func tearDownWithError() throws {
        dbManager.releaseMemory()
        validator = nil
        dbManager = nil
        super.tearDown()
    }
    
    // MARK: - Origin Dock Gating Tests (g_pick)
    
    func testOriginDockGatingSuccess() async throws {
        let now = Date()
        let nowEpoch = Int(now.timeIntervalSince1970)
        
        try await dbManager.upsertStationInfo([
            GBFSStationInfoRecord(stationId: "ORIGIN_1", name: "Grand Central", lat: 40.7527, lon: -73.9772, capacity: 40)
        ], systemId: "citi_bike_nyc")
        
        try await dbManager.upsertStationStatus([
            GBFSStationStatusRecord(
                stationId: "ORIGIN_1",
                numBikesAvailable: 8,
                numEbikesAvailable: 3,
                numDocksAvailable: 32,
                isInstalled: true,
                isRenting: true,
                isReturning: true,
                lastReported: nowEpoch - 30 // 30s ago
            )
        ])
        
        // 1. Any bike preference
        let anyResult = try await validator.validateOriginDock(stationId: "ORIGIN_1", preference: .anyBike, referenceDate: now)
        XCTAssertTrue(anyResult.isValid)
        XCTAssertTrue(anyResult.rejectionReasons.isEmpty)
        XCTAssertEqual(anyResult.metrics.availableBikes, 8)
        XCTAssertEqual(anyResult.metrics.availableEbikes, 3)
        XCTAssertEqual(anyResult.metrics.stalenessSeconds, 30)
        
        // 2. Electric only preference (3 available >= 2 min)
        let ebikeResult = try await validator.validateOriginDock(stationId: "ORIGIN_1", preference: .electricOnly, referenceDate: now)
        XCTAssertTrue(ebikeResult.isValid)
        
        // 3. Standard only preference (8 - 3 = 5 standard >= 2 min)
        let standardResult = try await validator.validateOriginDock(stationId: "ORIGIN_1", preference: .standardOnly, referenceDate: now)
        XCTAssertTrue(standardResult.isValid)
    }
    
    func testOriginDockGatingInsufficientBikes() async throws {
        let now = Date()
        let nowEpoch = Int(now.timeIntervalSince1970)
        
        try await dbManager.upsertStationInfo([
            GBFSStationInfoRecord(stationId: "LOW_BIKES", name: "Low Bikes", lat: 40.75, lon: -73.98)
        ], systemId: "nyc")
        
        // Only 1 bike available (fails min 2 requirement)
        try await dbManager.upsertStationStatus([
            GBFSStationStatusRecord(
                stationId: "LOW_BIKES",
                numBikesAvailable: 1,
                numEbikesAvailable: 0,
                numDocksAvailable: 29,
                isInstalled: true,
                isRenting: true,
                isReturning: true,
                lastReported: nowEpoch
            )
        ])
        
        let result = try await validator.validateOriginDock(stationId: "LOW_BIKES", minBikes: 2, referenceDate: now)
        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.rejectionReasons.contains(.insufficientBikes))
    }
    
    func testOriginDockGatingElectricPreferenceFailure() async throws {
        let now = Date()
        let nowEpoch = Int(now.timeIntervalSince1970)
        
        try await dbManager.upsertStationInfo([
            GBFSStationInfoRecord(stationId: "NO_EBIKES", name: "No Ebikes", lat: 40.75, lon: -73.98)
        ], systemId: "nyc")
        
        // 10 standard bikes, 0 ebikes
        try await dbManager.upsertStationStatus([
            GBFSStationStatusRecord(
                stationId: "NO_EBIKES",
                numBikesAvailable: 10,
                numEbikesAvailable: 0,
                numDocksAvailable: 10,
                lastReported: nowEpoch
            )
        ])
        
        let result = try await validator.validateOriginDock(stationId: "NO_EBIKES", preference: .electricOnly, minBikes: 2, referenceDate: now)
        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.rejectionReasons.contains(.insufficientEbikes))
    }
    
    func testOriginDockGatingDisabledAndStale() async throws {
        let now = Date()
        let nowEpoch = Int(now.timeIntervalSince1970)
        
        try await dbManager.upsertStationInfo([
            GBFSStationInfoRecord(stationId: "NOT_RENTING", name: "Not Renting", lat: 40.75, lon: -73.98),
            GBFSStationInfoRecord(stationId: "STALE_STATION", name: "Stale", lat: 40.75, lon: -73.98)
        ], systemId: "nyc")
        
        try await dbManager.upsertStationStatus([
            // Not renting
            GBFSStationStatusRecord(
                stationId: "NOT_RENTING",
                numBikesAvailable: 10,
                isInstalled: true,
                isRenting: false,
                isReturning: true,
                lastReported: nowEpoch
            ),
            // Stale reported 700s ago (> 600s threshold)
            GBFSStationStatusRecord(
                stationId: "STALE_STATION",
                numBikesAvailable: 10,
                isInstalled: true,
                isRenting: true,
                isReturning: true,
                lastReported: nowEpoch - 700
            )
        ])
        
        let notRentingResult = try await validator.validateOriginDock(stationId: "NOT_RENTING", referenceDate: now)
        XCTAssertFalse(notRentingResult.isValid)
        XCTAssertTrue(notRentingResult.rejectionReasons.contains(.notRenting))
        
        let staleResult = try await validator.validateOriginDock(stationId: "STALE_STATION", referenceDate: now)
        XCTAssertFalse(staleResult.isValid)
        XCTAssertTrue(staleResult.rejectionReasons.contains(.dataStale))
    }
    
    // MARK: - Destination Dock Gating Tests (g_drop)
    
    func testDestinationDockGatingSuccess() async throws {
        let now = Date()
        let nowEpoch = Int(now.timeIntervalSince1970)
        
        try await dbManager.upsertStationInfo([
            GBFSStationInfoRecord(stationId: "DEST_1", name: "Union Square", lat: 40.7359, lon: -73.9911, capacity: 50)
        ], systemId: "nyc")
        
        try await dbManager.upsertStationStatus([
            GBFSStationStatusRecord(
                stationId: "DEST_1",
                numBikesAvailable: 20,
                numDocksAvailable: 30,
                isInstalled: true,
                isRenting: true,
                isReturning: true,
                lastReported: nowEpoch - 45
            )
        ])
        
        let result = try await validator.validateDestinationDock(stationId: "DEST_1", minDocks: 2, referenceDate: now)
        XCTAssertTrue(result.isValid)
        XCTAssertEqual(result.metrics.availableDocks, 30)
        XCTAssertEqual(result.metrics.stalenessSeconds, 45)
    }
    
    func testDestinationDockGatingInsufficientDocks() async throws {
        let now = Date()
        let nowEpoch = Int(now.timeIntervalSince1970)
        
        try await dbManager.upsertStationInfo([
            GBFSStationInfoRecord(stationId: "FULL_STATION", name: "Full Station", lat: 40.73, lon: -73.99)
        ], systemId: "nyc")
        
        // Only 1 dock open (fails min 2 requirement)
        try await dbManager.upsertStationStatus([
            GBFSStationStatusRecord(
                stationId: "FULL_STATION",
                numBikesAvailable: 29,
                numDocksAvailable: 1,
                isInstalled: true,
                isRenting: true,
                isReturning: true,
                lastReported: nowEpoch
            )
        ])
        
        let result = try await validator.validateDestinationDock(stationId: "FULL_STATION", minDocks: 2, referenceDate: now)
        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.rejectionReasons.contains(.insufficientDocks))
    }
    
    // MARK: - Composite Edge & Fallback Tests (G(e) = g_pick * g_drop)
    
    func testCompositeGatingBothValid() async throws {
        let now = Date()
        let nowEpoch = Int(now.timeIntervalSince1970)
        
        try await dbManager.upsertStationInfo([
            GBFSStationInfoRecord(stationId: "PICK_1", name: "Pickup", lat: 40.75, lon: -73.98),
            GBFSStationInfoRecord(stationId: "DROP_1", name: "Dropoff", lat: 40.74, lon: -73.98)
        ], systemId: "nyc")
        
        try await dbManager.upsertStationStatus([
            GBFSStationStatusRecord(stationId: "PICK_1", numBikesAvailable: 5, numDocksAvailable: 10, lastReported: nowEpoch),
            GBFSStationStatusRecord(stationId: "DROP_1", numBikesAvailable: 5, numDocksAvailable: 10, lastReported: nowEpoch)
        ])
        
        let compositeResult = try await validator.evaluateTransferEdge(
            originStationId: "PICK_1",
            destinationStationId: "DROP_1",
            referenceDate: now
        )
        XCTAssertTrue(compositeResult.isValid)
        XCTAssertNil(compositeResult.fallbackStation)
    }
    
    func testCompositeGatingFallbackOnExhaustedDestination() async throws {
        let now = Date()
        let nowEpoch = Int(now.timeIntervalSince1970)
        
        // Origin Station (40.7580, -73.9855)
        let origin = GBFSStationInfoRecord(stationId: "PICK_OK", name: "Times Square", lat: 40.7580, lon: -73.9855, capacity: 30)
        
        // Primary Destination Station (40.7400, -73.9900) - 0 open docks (full)
        let targetDrop = GBFSStationInfoRecord(stationId: "DROP_FULL", name: "14th St Target", lat: 40.7400, lon: -73.9900, capacity: 40)
        
        // Alternative Station ~120m away (40.7410, -73.9905) - 15 open docks
        let fallbackDrop = GBFSStationInfoRecord(stationId: "DROP_FALLBACK", name: "15th St Fallback", lat: 40.7410, lon: -73.9905, capacity: 35)
        
        // Distant Station ~1.5km away (40.7250, -73.9950) - Should be excluded by 300m radius
        let distantDrop = GBFSStationInfoRecord(stationId: "DROP_FAR", name: "SoHo Far", lat: 40.7250, lon: -73.9950, capacity: 30)
        
        try await dbManager.upsertStationInfo([origin, targetDrop, fallbackDrop, distantDrop], systemId: "nyc")
        
        try await dbManager.upsertStationStatus([
            GBFSStationStatusRecord(stationId: "PICK_OK", numBikesAvailable: 8, numDocksAvailable: 10, lastReported: nowEpoch),
            GBFSStationStatusRecord(stationId: "DROP_FULL", numBikesAvailable: 40, numDocksAvailable: 0, lastReported: nowEpoch), // Gated!
            GBFSStationStatusRecord(stationId: "DROP_FALLBACK", numBikesAvailable: 5, numDocksAvailable: 15, lastReported: nowEpoch),
            GBFSStationStatusRecord(stationId: "DROP_FAR", numBikesAvailable: 5, numDocksAvailable: 20, lastReported: nowEpoch)
        ])
        
        let result = try await validator.evaluateTransferEdge(
            originStationId: "PICK_OK",
            destinationStationId: "DROP_FULL",
            referenceDate: now,
            attemptFallbackIfDestinationGated: true
        )
        
        XCTAssertTrue(result.isValid, "Composite evaluation should pass using the fallback station")
        XCTAssertNotNil(result.fallbackStation)
        XCTAssertEqual(result.fallbackStation?.stationId, "DROP_FALLBACK")
    }
}
