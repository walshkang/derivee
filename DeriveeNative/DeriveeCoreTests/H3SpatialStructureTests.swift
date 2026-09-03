import XCTest
@testable import DeriveeCore

final class H3SpatialStructureTests: XCTestCase {
    
    // MARK: - 1. C++20 ABI Memory Layout & Alignment Tests (Doc 06 §2 & §3)
    
    func testH3SpatialStructuresMemoryLayout() {
        // H3HashSlot: 16 bytes, 16-byte aligned
        XCTAssertEqual(MemoryLayout<H3HashSlot>.size, 16, "H3HashSlot size must be exactly 16 bytes")
        XCTAssertEqual(MemoryLayout<H3HashSlot>.stride, 16, "H3HashSlot stride must be exactly 16 bytes")
        
        // H3HashTableHeader: 64 bytes (cache line boundary), 16-byte aligned
        XCTAssertEqual(MemoryLayout<H3HashTableHeader>.size, 64, "H3HashTableHeader size must be exactly 64 bytes")
        XCTAssertEqual(MemoryLayout<H3HashTableHeader>.stride, 64, "H3HashTableHeader stride must be exactly 64 bytes")
        
        // H3DeltaUpdate: 16 bytes, 16-byte aligned
        XCTAssertEqual(MemoryLayout<H3DeltaUpdate>.size, 16, "H3DeltaUpdate size must be exactly 16 bytes")
        XCTAssertEqual(MemoryLayout<H3DeltaUpdate>.stride, 16, "H3DeltaUpdate stride must be exactly 16 bytes")
    }
    
    func testH3HashSlotFieldAccess() {
        var slot = H3HashSlot()
        slot.h3Index = 0x8b2a100d213ffff
        slot.unlockTimestamp = 1725380000
        slot.flags = 1
        
        XCTAssertEqual(slot.h3Index, 0x8b2a100d213ffff)
        XCTAssertEqual(slot.unlockTimestamp, 1725380000)
        XCTAssertEqual(slot.flags, 1)
    }
    
    func testH3HashTableHeaderFieldAccess() {
        var header = H3HashTableHeader()
        header.capacity = 262144
        header.capacityMask = 262143
        header.activeCount = 42
        header.maxProbeDepth = 3
        header.deltaCount = 100
        header.res11Resolution = 11
        
        XCTAssertEqual(header.capacity, 262144)
        XCTAssertEqual(header.capacityMask, 262143)
        XCTAssertEqual(header.activeCount, 42)
        XCTAssertEqual(header.maxProbeDepth, 3)
        XCTAssertEqual(header.deltaCount, 100)
        XCTAssertEqual(header.res11Resolution, 11)
    }
    
    func testH3DeltaUpdateFieldAccess() {
        var delta = H3DeltaUpdate()
        delta.h3Index = 0x8b2a100d213ffff
        delta.unlockTimestamp = 1725381234
        delta.reserved = 0
        
        XCTAssertEqual(delta.h3Index, 0x8b2a100d213ffff)
        XCTAssertEqual(delta.unlockTimestamp, 1725381234)
        XCTAssertEqual(delta.reserved, 0)
    }
    
    // MARK: - 2. MurmurHash3 Finalizer Distribution Tests
    
    func testMurmurHash3Deterministic() {
        func hash64To32(_ key: UInt64) -> UInt32 {
            var k = key
            k ^= k >> 33
            k = k &* 0xff51afd7ed558ccd
            k ^= k >> 33
            k = k &* 0xc4ceb9fe1a85ec53
            k ^= k >> 33
            return UInt32(truncatingIfNeeded: k)
        }
        
        let hex1: UInt64 = 0x8b2a100d213ffff
        let hex2: UInt64 = 0x8b2a100d214ffff
        
        let h1a = hash64To32(hex1)
        let h1b = hash64To32(hex1)
        let h2 = hash64To32(hex2)
        
        XCTAssertEqual(h1a, h1b, "MurmurHash3 must be strictly deterministic")
        XCTAssertNotEqual(h1a, h2, "Different H3 keys should hash to different 32-bit values")
    }
}
