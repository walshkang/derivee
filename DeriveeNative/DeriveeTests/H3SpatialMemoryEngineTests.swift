import XCTest
import Metal
import GRDB
@testable import Derivee

final class H3SpatialMemoryEngineTests: XCTestCase {
    
    var engine: H3SpatialMemoryEngine!
    
    override func setUp() async throws {
        try await super.setUp()
        // Skip test if no Metal device is available in current test host
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("No system default MTLDevice available on this host")
        }
        engine = try H3SpatialMemoryEngine(device: device)
    }
    
    override func tearDown() async throws {
        engine = nil
        try await super.tearDown()
    }
    
    // MARK: - 1. ABI Verification & Hard VRAM Budget Constraint (Doc 06 §2 & §3)
    
    func testABIVerification() {
        H3ABIVerifier.verifyLayouts()
        
        XCTAssertEqual(MemoryLayout<H3HashSlot>.size, 16)
        XCTAssertEqual(MemoryLayout<H3HashSlot>.stride, 16)
        
        XCTAssertEqual(MemoryLayout<H3HashTableHeader>.size, 64)
        XCTAssertEqual(MemoryLayout<H3HashTableHeader>.stride, 64)
        
        XCTAssertEqual(MemoryLayout<H3DeltaUpdate>.size, 16)
        XCTAssertEqual(MemoryLayout<H3DeltaUpdate>.stride, 16)
    }
    
    func testVRAMHardBudgetConstraint() {
        let vramBytes = engine.currentVRAMUsageBytes
        
        // Exact mathematical proof from Doc 06:
        // Hash Table (262,144 * 16) = 4,194,304 bytes
        // Delta Buffer (4,096 * 16) = 65,536 bytes
        // Header Buffer = 64 bytes
        // Total = 4,259,904 bytes (~4.26 MB)
        XCTAssertEqual(vramBytes, 4_259_904, "VRAM usage must exactly equal 4,259,904 bytes (4.26 MB)")
        
        // Hard operational ceiling: < 10.0 MB (10,485,760 bytes)
        XCTAssertLessThan(vramBytes, 10_000_000, "VRAM must remain strictly under the 10 MB Jetsam limit")
    }
    
    // MARK: - 2. Ingestion & Atomic Compare-and-Swap Idempotency (Doc 06 §4 & §5)
    
    func testSingleAndBatchDeltaIngestion() async throws {
        try await engine.reset()
        
        let testDeltas: [H3DeltaUpdate] = [
            H3DeltaUpdate(h3Index: 0x8b2a100d213ffff, unlockTimestamp: 1725380001),
            H3DeltaUpdate(h3Index: 0x8b2a100d214ffff, unlockTimestamp: 1725380002),
            H3DeltaUpdate(h3Index: 0x8b2a100d215ffff, unlockTimestamp: 1725380003)
        ]
        
        try await engine.ingestDeltas(testDeltas)
        
        let header = engine.readHeader()
        XCTAssertEqual(header.activeCount, 3, "Active count must equal 3 after inserting 3 unique hexes")
        XCTAssertGreaterThan(header.maxProbeDepth, 0, "Max probe depth must be >= 1")
        XCTAssertLessThanOrEqual(header.maxProbeDepth, 16, "Initial probe depth should be small")
    }
    
    func testAtomicCASIdempotency() async throws {
        try await engine.reset()
        
        let hex: UInt64 = 0x8b2a100d213ffff
        let firstDelta = [H3DeltaUpdate(h3Index: hex, unlockTimestamp: 100)]
        try await engine.ingestDeltas(firstDelta)
        
        var header = engine.readHeader()
        XCTAssertEqual(header.activeCount, 1)
        
        // Re-inserting the same hex with a newer timestamp should NOT duplicate active count
        let secondDelta = [H3DeltaUpdate(h3Index: hex, unlockTimestamp: 200)]
        try await engine.ingestDeltas(secondDelta)
        
        header = engine.readHeader()
        XCTAssertEqual(header.activeCount, 1, "Re-inserting duplicate hex must remain idempotent (activeCount == 1)")
    }
    
    // MARK: - 3. GPU Spatial Coverage Query Accuracy (Doc 06 §5)
    
    func testGPUQueryCoverageAccuracy() async throws {
        try await engine.reset()
        
        let insertedHexes: [UInt64] = [
            0x8b2a100d213ffff,
            0x8b2a100d214ffff,
            0x8b2a100d215ffff,
            0x8b2a100d216ffff,
            0x8b2a100d217ffff
        ]
        
        let deltas = insertedHexes.map { H3DeltaUpdate(h3Index: $0, unlockTimestamp: 1725380000) }
        try await engine.ingestDeltas(deltas)
        
        let unvisitedHexes: [UInt64] = [
            0x8b2a100d220ffff,
            0x8b2a100d221ffff,
            0x8b2a100d222ffff
        ]
        
        // Query inserted keys -> expect true
        let hits = try await engine.queryCoverage(indices: insertedHexes, cameraZoom: 18.0)
        XCTAssertEqual(hits, [true, true, true, true, true], "All inserted hexes must return true")
        
        // Query unvisited keys -> expect false
        let misses = try await engine.queryCoverage(indices: unvisitedHexes, cameraZoom: 18.0)
        XCTAssertEqual(misses, [false, false, false], "All unvisited hexes must return false")
    }
    
    // MARK: - 4. In-Shader Bitwise Parent LOD Aggregation (Doc 06 §6)
    
    func testInShaderBitwiseParentLODAggregation() async throws {
        try await engine.reset()
        
        // Res 11 hex (Times Square area)
        let res11Hex: UInt64 = 0x8b2a100d213ffff
        
        // Convert to Res 8 and Res 5 parent using bitwise helper
        let res8Parent = H3ABIVerifier.convertH3ToParent(h3Index11: res11Hex, targetRes: 8)
        let res5Parent = H3ABIVerifier.convertH3ToParent(h3Index11: res11Hex, targetRes: 5)
        
        // Insert ONLY the Res-8 parent into the table (simulating coarse parent store or parent queries)
        let delta = [H3DeltaUpdate(h3Index: res8Parent, unlockTimestamp: 1725380000)]
        try await engine.ingestDeltas(delta)
        
        // Querying the raw Res 11 index at zoom 18 (street level, targetRes=11) -> false (table only has res 8)
        let streetHits = try await engine.queryCoverage(indices: [res11Hex], cameraZoom: 18.0)
        XCTAssertEqual(streetHits, [false])
        
        // Querying the raw Res 11 index at zoom 10 (district level, targetRes=8) -> true!
        // In-shader bitwise aggregation dynamically masks to Res 8 on the GPU hot path.
        let districtHits = try await engine.queryCoverage(indices: [res11Hex], cameraZoom: 10.0)
        XCTAssertEqual(districtHits, [true], "In-shader bitwise parent LOD must dynamically hit the parent slot at zoom 10")
    }
    
    // MARK: - 5. High-Throughput Batch Stress Test (Doc 06 §4)
    
    func testHighThroughputBatchIngestion() async throws {
        try await engine.reset()
        
        let batchSize = 10_000
        var syntheticDeltas: [H3DeltaUpdate] = []
        syntheticDeltas.reserveCapacity(batchSize)
        
        let baseIndex: UInt64 = 0x8b2a10000000000
        for i in 0..<batchSize {
            // Synthesize unique H3 indices with low-order bits set to 7 (unused)
            let uniqueKey = baseIndex | (UInt64(i) << 12) | 0xFFF
            syntheticDeltas.append(H3DeltaUpdate(h3Index: uniqueKey, unlockTimestamp: UInt32(i)))
        }
        
        let startTime = CFAbsoluteTimeGetCurrent()
        try await engine.ingestDeltas(syntheticDeltas)
        let duration = CFAbsoluteTimeGetCurrent() - startTime
        
        let header = engine.readHeader()
        XCTAssertEqual(header.activeCount, UInt32(batchSize), "All 10,000 synthetic hexes must be inserted")
        XCTAssertLessThanOrEqual(header.maxProbeDepth, 64, "Worst-case linear probe depth must remain <= 64")
        
        let keysPerSec = Double(batchSize) / max(duration, 0.0001)
        XCTAssertGreaterThan(keysPerSec, 50_000, "GPU ingestion throughput must exceed 50k keys/sec")
    }
    
    // MARK: - 6. SQLite Database Hydration Bridge (Doc 06 §4)
    
    func testDatabaseHydrationBridge() async throws {
        try await engine.reset()
        
        let dbQueue = try DatabaseQueue()
        try await dbQueue.write { db in
            try db.execute(sql: """
                CREATE TABLE explored_hexes_nyc (
                    h3_index TEXT PRIMARY KEY
                );
                INSERT INTO explored_hexes_nyc VALUES ('8b2a100d213ffff');
                INSERT INTO explored_hexes_nyc VALUES ('8b2a100d214ffff');
                INSERT INTO explored_hexes_nyc VALUES ('8b2a100d215ffff');
            """)
        }
        
        let count = try await engine.hydrateFromDatabase(dbWriter: dbQueue, citySlug: "nyc")
        XCTAssertEqual(count, 3, "Hydration should report 3 hexes ingested from SQLite")
        
        let header = engine.readHeader()
        XCTAssertEqual(header.activeCount, 3, "Header active count must equal 3 after database hydration")
        
        let hits = try await engine.queryCoverage(
            indices: [0x8b2a100d213ffff, 0x8b2a100d214ffff, 0x8b2a100d215ffff],
            cameraZoom: 18.0
        )
        XCTAssertEqual(hits, [true, true, true], "All hydrated hexes must query successfully on the GPU")
    }
}
