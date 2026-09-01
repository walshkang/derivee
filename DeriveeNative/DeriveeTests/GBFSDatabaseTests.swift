import XCTest
import CoreLocation
import GRDB
@testable import Derivee

final class GBFSDatabaseTests: XCTestCase {
    var dbManager: GBFSDatabaseManager!
    
    override func setUpWithError() throws {
        super.setUp()
        dbManager = GBFSDatabaseManager.makeForTesting(inMemory: true)
    }
    
    override func tearDownWithError() throws {
        dbManager.releaseMemory()
        dbManager = nil
        super.tearDown()
    }
    
    func testSchemaCreationAndIndexing() async throws {
        let count = try await dbManager.stationCount()
        XCTAssertEqual(count, 0, "New ephemeral database should have 0 stations")
        
        let all = try await dbManager.fetchAllStations()
        XCTAssertTrue(all.isEmpty)
    }
    
    func testIngestStationInfoAndStatus() async throws {
        let infoRecords = [
            GBFSStationInfoRecord(
                stationId: "STATION_1",
                name: "Broadway & W 42nd St",
                lat: 40.7558,
                lon: -73.9865,
                capacity: 30,
                regionId: "NYC",
                hasKiosk: true
            ),
            GBFSStationInfoRecord(
                stationId: "STATION_2",
                name: "8th Ave & W 31st St",
                lat: 40.7505,
                lon: -73.9940,
                capacity: 45,
                regionId: "NYC",
                hasKiosk: false
            )
        ]
        
        try await dbManager.upsertStationInfo(infoRecords, systemId: "citi_bike_nyc")
        let stationCount = try await dbManager.stationCount()
        XCTAssertEqual(stationCount, 2)
        
        let nowEpoch = Int(Date().timeIntervalSince1970)
        let statusRecords = [
            GBFSStationStatusRecord(
                stationId: "STATION_1",
                numBikesAvailable: 12,
                numEbikesAvailable: 5,
                numDocksAvailable: 18,
                isInstalled: true,
                isRenting: true,
                isReturning: true,
                lastReported: nowEpoch
            ),
            GBFSStationStatusRecord(
                stationId: "STATION_2",
                numBikesAvailable: 0,
                numEbikesAvailable: 0,
                numDocksAvailable: 45,
                isInstalled: true,
                isRenting: true,
                isReturning: true,
                lastReported: nowEpoch
            )
        ]
        
        try await dbManager.upsertStationStatus(statusRecords)
        
        let station1 = try await dbManager.fetchStation(by: "STATION_1")
        XCTAssertNotNil(station1)
        XCTAssertEqual(station1?.name, "Broadway & W 42nd St")
        XCTAssertEqual(station1?.numBikesAvailable, 12)
        XCTAssertEqual(station1?.numEbikesAvailable, 5)
        XCTAssertEqual(station1?.numStandardBikesAvailable, 7)
        XCTAssertEqual(station1?.numDocksAvailable, 18)
        XCTAssertTrue(station1?.hasKiosk ?? false)
        XCTAssertTrue(station1?.isInstalled ?? false)
        XCTAssertTrue(station1?.isRenting ?? false)
        XCTAssertTrue(station1?.isReturning ?? false)
    }
    
    func testUpsertConflictResolution() async throws {
        let initialInfo = [
            GBFSStationInfoRecord(stationId: "S1", name: "Old Name", lat: 40.75, lon: -73.98, capacity: 20)
        ]
        try await dbManager.upsertStationInfo(initialInfo, systemId: "nyc")
        
        let updatedInfo = [
            GBFSStationInfoRecord(stationId: "S1", name: "New Name", lat: 40.751, lon: -73.981, capacity: 25)
        ]
        try await dbManager.upsertStationInfo(updatedInfo, systemId: "nyc")
        
        let station = try await dbManager.fetchStation(by: "S1")
        XCTAssertEqual(station?.name, "New Name")
        XCTAssertEqual(station?.capacity, 25)
        let count = try await dbManager.stationCount()
        XCTAssertEqual(count, 1)
    }
    
    func testSpatialBoundingBoxAndDistancePruning() async throws {
        // Reference point: Times Square (40.7580, -73.9855)
        let timesSquare = CLLocationCoordinate2D(latitude: 40.7580, longitude: -73.9855)
        
        let nearbyStation = GBFSStationInfoRecord(
            stationId: "NEARBY_1",
            name: "7th Ave & W 41st St", // ~150m away
            lat: 40.7565,
            lon: -73.9868,
            capacity: 35
        )
        let mediumStation = GBFSStationInfoRecord(
            stationId: "MEDIUM_1",
            name: "6th Ave & W 44th St", // ~400m away
            lat: 40.7560,
            lon: -73.9815,
            capacity: 25
        )
        let farStation = GBFSStationInfoRecord(
            stationId: "FAR_1",
            name: "Wall Street & Broadway", // ~5.5km away
            lat: 40.7075,
            lon: -74.0112,
            capacity: 40
        )
        
        try await dbManager.upsertStationInfo([nearbyStation, mediumStation, farStation], systemId: "citi_bike_nyc")
        
        // 1. Search radius 300m -> Should only find nearbyStation
        let results300m = try await dbManager.fetchCandidateStations(near: timesSquare, radiusMeters: 300.0)
        XCTAssertEqual(results300m.count, 1)
        XCTAssertEqual(results300m.first?.stationId, "NEARBY_1")
        XCTAssertLessThan(results300m.first?.distanceMeters ?? 9999, 300.0)
        
        // 2. Search radius 600m -> Should find nearbyStation and mediumStation, sorted by distance
        let results600m = try await dbManager.fetchCandidateStations(near: timesSquare, radiusMeters: 600.0)
        XCTAssertEqual(results600m.count, 2)
        XCTAssertEqual(results600m[0].stationId, "NEARBY_1")
        XCTAssertEqual(results600m[1].stationId, "MEDIUM_1")
        XCTAssertLessThan(results600m[0].distanceMeters ?? 0, results600m[1].distanceMeters ?? 0)
        
        // 3. Far station should NOT be included in 600m search
        XCTAssertFalse(results600m.contains { $0.stationId == "FAR_1" })
    }
    
    func testSpatialQueryPerformanceBenchmark() async throws {
        // Populate 100 synthetic stations across a 5km bounding box
        var syntheticStations: [GBFSStationInfoRecord] = []
        syntheticStations.reserveCapacity(100)
        
        let baseLat = 40.7500
        let baseLon = -73.9800
        
        for i in 0..<100 {
            let offsetLat = Double(i % 10) * 0.005
            let offsetLon = Double(i / 10) * 0.005
            syntheticStations.append(
                GBFSStationInfoRecord(
                    stationId: "BENCH_\(i)",
                    name: "Bench Station \(i)",
                    lat: baseLat + offsetLat,
                    lon: baseLon + offsetLon,
                    capacity: 30
                )
            )
        }
        try await dbManager.upsertStationInfo(syntheticStations, systemId: "benchmark")
        
        let queryCoord = CLLocationCoordinate2D(latitude: 40.7600, longitude: -73.9700)
        
        // Warm up query plan
        _ = try await dbManager.fetchCandidateStations(near: queryCoord, radiusMeters: 800.0)
        
        // Benchmark execution
        let start = CFAbsoluteTimeGetCurrent()
        let iterations = 20
        for _ in 0..<iterations {
            _ = try await dbManager.fetchCandidateStations(near: queryCoord, radiusMeters: 800.0)
        }
        let totalElapsed = CFAbsoluteTimeGetCurrent() - start
        let avgPerQueryMs = (totalElapsed / Double(iterations)) * 1000.0
        
        print("⚡ [GBFSDatabaseTests] Average spatial query time over \(iterations) iterations: \(String(format: "%.3f", avgPerQueryMs)) ms")
        XCTAssertLessThan(avgPerQueryMs, 10.0, "Spatial bounding box query must execute in < 10ms in test environment")
    }
    
    func testPurgeStaleRecordsAndClearCache() async throws {
        let oldEpoch = 1000
        let freshEpoch = 2000
        
        let info = [
            GBFSStationInfoRecord(stationId: "S_OLD", name: "Old", lat: 40.7, lon: -73.9),
            GBFSStationInfoRecord(stationId: "S_FRESH", name: "Fresh", lat: 40.8, lon: -73.8)
        ]
        try await dbManager.upsertStationInfo(info, systemId: "test")
        
        let status = [
            GBFSStationStatusRecord(stationId: "S_OLD", numBikesAvailable: 5, lastReported: oldEpoch),
            GBFSStationStatusRecord(stationId: "S_FRESH", numBikesAvailable: 8, lastReported: freshEpoch)
        ]
        try await dbManager.upsertStationStatus(status)
        
        try await dbManager.purgeStaleRecords(olderThanEpoch: 1500)
        
        let oldStatus = try await dbManager.fetchStationStatus(for: "S_OLD")
        XCTAssertNil(oldStatus, "Stale station status should be deleted")
        
        let freshStatus = try await dbManager.fetchStationStatus(for: "S_FRESH")
        XCTAssertNotNil(freshStatus, "Fresh station status should be retained")
        
        try await dbManager.clearCache()
        let finalCount = try await dbManager.stationCount()
        XCTAssertEqual(finalCount, 0)
    }
}
