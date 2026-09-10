import XCTest
import CoreLocation
import GRDB
@testable import Derivee

final class ComplexDepartureTests: XCTestCase {
    
    var departureService: ComplexDepartureService!
    var spatialManager: SpatialDatabaseManager!
    
    override func setUp() async throws {
        try await super.setUp()
        spatialManager = SpatialDatabaseManager.shared
        _ = try? CityPackManager.shared.ensureBundledPackExtracted()
        
        let transitURL: URL = {
            if let custom = spatialManager.currentTransitDBURL, FileManager.default.fileExists(atPath: custom.path) {
                return custom
            }
            let packURL = CityPackManager.shared.transitDatabaseURL(for: "nyc")
            if FileManager.default.fileExists(atPath: packURL.path) {
                return packURL
            }
            return Bundle.main.url(forResource: "derivee_transit", withExtension: "sqlite") ?? packURL
        }()
        
        departureService = ComplexDepartureService(databasePath: transitURL.path)
    }
    
    // MARK: - 1. Schema & Clustered Index Verification (Doc 16 §2)
    
    func testSchemaAndClusteredIndexStructure() async throws {
        try await spatialManager.dbWriter.read { db in
            try self.spatialManager.ensureTransitAttached(in: db)
            
            // 1. Verify realtime_departures table DDL
            guard let tableRow = try Row.fetchOne(db, sql: """
                SELECT sql FROM transit.sqlite_master 
                WHERE type='table' AND name='realtime_departures'
            """) else {
                XCTFail("realtime_departures table must exist in transit schema")
                return
            }
            
            let ddl: String = tableRow["sql"]
            XCTAssertTrue(ddl.contains("WITHOUT ROWID"), "realtime_departures MUST be declared WITHOUT ROWID")
            XCTAssertTrue(ddl.contains("PRIMARY KEY (complex_id, departure_time, feed_id, child_stop_id, trip_id)"),
                          "Primary key must be clustered on (complex_id, departure_time, feed_id, child_stop_id, trip_id)")
            
            // 2. Verify TTL index exists
            let indexRow = try Row.fetchOne(db, sql: """
                SELECT name FROM transit.sqlite_master 
                WHERE type='index' AND name='idx_realtime_departures_ttl'
            """)
            XCTAssertNotNil(indexRow, "idx_realtime_departures_ttl must exist for background garbage collection")
        }
    }
    
    // MARK: - 2. Zero Temporary B-Tree Query Plan (Doc 16 §3)
    
    func testExplainQueryPlanZeroTempBTree() throws {
        let plan = try departureService.explainQueryPlan(complexId: 602, cutoffTime: 0, limit: 30)
        print("📋 Query Plan:\n\(plan)")
        
        // Assert leading-edge clustered index scan
        XCTAssertTrue(plan.contains("PRIMARY KEY") && plan.contains("complex_id=?"),
                      "Query plan must use clustered PRIMARY KEY range scan: \(plan)")
        
        // Assert strict absence of temporary B-tree sorting
        XCTAssertFalse(plan.contains("USE TEMP B-TREE"),
                       "CRITICAL GUARDRAIL: Query plan must not use temporary B-tree for sorting: \(plan)")
    }
    
    // MARK: - 3. Sub-0.10ms (40–70µs) Latency Benchmark (Doc 16 §3)
    
    func testSubMillisecondLatencyBenchmark() throws {
        let pool = try departureService.ensurePool()
        
        // Warm up query & statement cache
        _ = try departureService.fetchDepartures(complexId: 602, cutoffTime: 0, limit: 30)
        
        let iterations = 1000
        
        // 1. Benchmark pure statement & clustered index traversal on active connection (Doc 16 §3 target: 40–70µs)
        try pool.read { db in
            let startPure = CFAbsoluteTimeGetCurrent()
            var totalCount = 0
            for _ in 0..<iterations {
                let departures = try departureService.fetchDepartures(complexId: 602, cutoffTime: 0, limit: 30, in: db)
                totalCount += departures.count
            }
            let elapsedPure = CFAbsoluteTimeGetCurrent() - startPure
            let avgPureMicroseconds = (elapsedPure / Double(iterations)) * 1_000_000.0
            print("⚡ Direct Query Latency Benchmark: \(String(format: "%.2f", avgPureMicroseconds)) µs per query (\(iterations) runs)")
            
            XCTAssertGreaterThan(totalCount, 0)
            // Assert pure statement execution is sub-0.10ms (100µs) on device / sub-millisecond in debug simulator (< 180µs)
            XCTAssertLessThan(avgPureMicroseconds, 180.0,
                              "Pure query execution latency must be sub-millisecond, measured \(avgPureMicroseconds)µs")
        }
        
        // 2. Benchmark end-to-end pool checkout + transaction + query execution (sub-millisecond: < 250µs)
        let startE2E = CFAbsoluteTimeGetCurrent()
        var totalE2ECount = 0
        for _ in 0..<iterations {
            let departures = try departureService.fetchDepartures(complexId: 602, cutoffTime: 0, limit: 30)
            totalE2ECount += departures.count
        }
        let elapsedE2E = CFAbsoluteTimeGetCurrent() - startE2E
        let avgE2EMicroseconds = (elapsedE2E / Double(iterations)) * 1_000_000.0
        print("⚡ End-to-End Pool Checkout Latency: \(String(format: "%.2f", avgE2EMicroseconds)) µs per query (\(iterations) runs)")
        
        XCTAssertGreaterThan(totalE2ECount, 0)
        XCTAssertLessThan(avgE2EMicroseconds, 250.0,
                          "End-to-end query latency must be sub-millisecond (< 250µs), measured \(avgE2EMicroseconds)µs")
    }
    
    // MARK: - 4. Multi-Platform Clustered Departures Consolidation (Union Sq 602)
    
    func testComplexDepartureFetchForUnionSquare() throws {
        let departures = try departureService.fetchDepartures(complexId: 602, cutoffTime: 0, limit: 30)
        XCTAssertFalse(departures.isEmpty, "Union Square (602) must contain departures")
        XCTAssertLessThanOrEqual(departures.count, 30)
        
        // 1. Verify complexId invariant
        for d in departures {
            XCTAssertEqual(d.complexId, 602, "All departures must belong to complex 602")
        }
        
        // 2. Verify strict chronological ordering directly from clustered index leaf scan
        for i in 0..<(departures.count - 1) {
            XCTAssertLessThanOrEqual(departures[i].departureTime, departures[i + 1].departureTime,
                                     "Departures must be strictly non-decreasing by departure_time")
        }
        
        // 3. Verify multi-line consolidation across platforms
        let routes = Set(departures.map(\.routeShortName))
        XCTAssertGreaterThan(routes.count, 1, "Must consolidate multiple routes at complex hub")
        
        let childStops = Set(departures.map(\.childStopId))
        XCTAssertGreaterThan(childStops.count, 1, "Must span multiple child platforms at complex hub")
    }
    
    // MARK: - 5. Track & Express Resolution (Doc 16 §4)
    
    func testExpressAndTrackInvariants() throws {
        let departures = try departureService.fetchDepartures(complexId: 602, cutoffTime: 0, limit: 100)
        
        let expressDepartures = departures.filter { $0.isExpress }
        XCTAssertFalse(expressDepartures.isEmpty, "Should find express service runs")
        
        for exp in expressDepartures {
            XCTAssertTrue(["2", "3", "M"].contains(exp.track) || ["4", "5", "A", "D", "N", "Q"].contains(exp.routeShortName),
                          "Express departures should occupy express tracks or routes: \(exp.routeShortName) on track \(exp.track)")
        }
    }
    
    // MARK: - 6. Unified Serving Routes Resolution (Doc 16 §3)
    
    func testUnifiedServingRoutesResolution() throws {
        let servingRoutes = try departureService.fetchServingRoutes(complexId: 602)
        XCTAssertFalse(servingRoutes.isEmpty, "Union Square (602) must have serving routes")
        
        let routeNames = Set(servingRoutes.map(\.routeShortName))
        print("🚇 Serving routes at Union Sq (602): \(routeNames.sorted())")
        
        // Union Square serves Lexington (4/5/6), Broadway (N/Q/R/W), and Canarsie (L)
        XCTAssertTrue(routeNames.contains("4") || routeNames.contains("6"), "Must include Lexington line")
        XCTAssertTrue(routeNames.contains("L"), "Must include Canarsie L line")
        XCTAssertTrue(routeNames.contains("N") || routeNames.contains("Q") || routeNames.contains("R"), "Must include Broadway line")
    }
    
    // MARK: - 7. TTL Garbage Collection Pruning
    
    func testTTLGarbageCollectionPruning() throws {
        // Create an ephemeral in-memory database to test mutation & TTL pruning
        let queue = try DatabaseQueue()
        try queue.write { db in
            try ComplexDepartureService.createTableIfNeeded(in: db)
            
            let now = Int64(Date().timeIntervalSince1970)
            let testDepartures = [
                ComplexDeparture(
                    complexId: 9999, departureTime: now - 3600, feedId: "subway",
                    parentStationId: "TEST", childStopId: "TEST_S", tripId: "PAST_1",
                    routeId: "1", routeShortName: "1", directionId: 0, track: "1", updatedAt: now
                ),
                ComplexDeparture(
                    complexId: 9999, departureTime: now - 1800, feedId: "subway",
                    parentStationId: "TEST", childStopId: "TEST_S", tripId: "PAST_2",
                    routeId: "1", routeShortName: "1", directionId: 0, track: "1", updatedAt: now
                ),
                ComplexDeparture(
                    complexId: 9999, departureTime: now + 600, feedId: "subway",
                    parentStationId: "TEST", childStopId: "TEST_S", tripId: "FUTURE_1",
                    routeId: "1", routeShortName: "1", directionId: 0, track: "1", updatedAt: now
                )
            ]
            
            let service = ComplexDepartureService()
            try service.materializeDepartures(testDepartures, in: db)
            
            let countBefore = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM realtime_departures WHERE complex_id = 9999")
            XCTAssertEqual(countBefore, 3)
            
            // Prune expired departures older than now
            try service.purgeExpiredDepartures(before: now, in: db)
            
            let countAfter = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM realtime_departures WHERE complex_id = 9999")
            XCTAssertEqual(countAfter, 1, "Only the future departure should survive TTL pruning")
            
            let remaining = try Row.fetchOne(db, sql: "SELECT trip_id FROM realtime_departures WHERE complex_id = 9999")
            XCTAssertEqual(remaining?["trip_id"], "FUTURE_1")
        }
    }
    
    // MARK: - 8. SpatialDatabaseManager Facade Integration
    
    func testSpatialDatabaseManagerIntegration() async throws {
        let departures = try await spatialManager.fetchComplexDepartures(complexId: 602, cutoffTime: 0, limit: 15)
        XCTAssertFalse(departures.isEmpty)
        XCTAssertEqual(departures.first?.complexId, 602)
        
        let routes = try await spatialManager.fetchComplexServingRoutes(complexId: 602)
        XCTAssertFalse(routes.isEmpty)
    }
    
    // MARK: - 9. Two-Phase Swap Memory Release Safety (Wave L & Q)
    
    func testTwoPhaseSwapMemoryRelease() {
        // Calling prepareForCitySwap must release pool handles and memory without deadlock or throw
        departureService.prepareForCitySwap()
        
        // Subsequent fetch should safely recreate the pool on demand
        XCTAssertNoThrow(try departureService.fetchDepartures(complexId: 602, cutoffTime: 0, limit: 5))
    }
}
