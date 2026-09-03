import Foundation

/// Represents a single 16-byte aligned slot inside the GPU spatial hash table in `MTLBuffer`.
/// Directly matches the MSL `H3HashSlot` and C++ `H3HashSlot` ABI layouts.
@frozen
public struct H3HashSlot: Sendable, Equatable, Hashable {
    public var h3Index: UInt64          // Uber H3 Res-11 Index (0 if empty)
    public var unlockTimestamp: UInt32  // Unix epoch timestamp of exploration
    public var flags: UInt32            // Slot state flags (0x0 = Empty, 0x1 = Occupied)

    @inlinable
    public init(h3Index: UInt64 = 0, unlockTimestamp: UInt32 = 0, flags: UInt32 = 0) {
        self.h3Index = h3Index
        self.unlockTimestamp = unlockTimestamp
        self.flags = flags
    }
}

/// Header buffer governing GPU hash table metadata (64 bytes, 16-byte aligned).
/// Matches the MSL `H3HashTableHeader` and C++ `H3HashTableHeader` ABI layouts.
@frozen
public struct H3HashTableHeader: Sendable, Equatable {
    public var capacity: UInt32          // Total slot capacity (power of 2, e.g. 262,144)
    public var capacityMask: UInt32      // Capacity minus 1 (e.g. 262,143) for bitwise modulo
    public var activeCount: UInt32       // Count of currently inserted unique keys
    public var maxProbeDepth: UInt32     // Worst-case linear probe depth
    public var deltaCount: UInt32        // Pending delta updates in staging buffer
    public var res11Resolution: UInt32   // Resolution verifier (11)
    public var padding: (UInt64, UInt64, UInt64, UInt64, UInt64) = (0, 0, 0, 0, 0) // 40 bytes padding

    @inlinable
    public init(capacity: UInt32, deltaCount: UInt32 = 0) {
        self.capacity = capacity
        self.capacityMask = capacity > 0 ? capacity - 1 : 0
        self.activeCount = 0
        self.maxProbeDepth = 0
        self.deltaCount = deltaCount
        self.res11Resolution = 11
        self.padding = (0, 0, 0, 0, 0)
    }

    public static func == (lhs: H3HashTableHeader, rhs: H3HashTableHeader) -> Bool {
        return lhs.capacity == rhs.capacity &&
            lhs.capacityMask == rhs.capacityMask &&
            lhs.activeCount == rhs.activeCount &&
            lhs.maxProbeDepth == rhs.maxProbeDepth &&
            lhs.deltaCount == rhs.deltaCount &&
            lhs.res11Resolution == rhs.res11Resolution
    }
}

/// Staging slot for streaming updates from SQLite to GPU (16 bytes, 16-byte aligned).
@frozen
public struct H3DeltaUpdate: Sendable, Equatable, Hashable {
    public var h3Index: UInt64
    public var unlockTimestamp: UInt32
    public var reserved: UInt32

    @inlinable
    public init(h3Index: UInt64, unlockTimestamp: UInt32, reserved: UInt32 = 0) {
        self.h3Index = h3Index
        self.unlockTimestamp = unlockTimestamp
        self.reserved = reserved
    }
}

/// ABI layout validation and bitwise math helpers for H3 spatial memory structures.
public enum H3ABIVerifier {
    
    /// Verifies that Swift memory layouts strictly match Apple Silicon MSL/C++ ABI requirements.
    public static func verifyLayouts() {
        assert(MemoryLayout<H3HashSlot>.size == 16, "H3HashSlot size must be 16 bytes")
        assert(MemoryLayout<H3HashSlot>.stride == 16, "H3HashSlot stride must be 16 bytes")
        
        assert(MemoryLayout<H3HashTableHeader>.size == 64, "H3HashTableHeader size must be 64 bytes")
        assert(MemoryLayout<H3HashTableHeader>.stride == 64, "H3HashTableHeader stride must be 64 bytes")
        
        assert(MemoryLayout<H3DeltaUpdate>.size == 16, "H3DeltaUpdate size must be 16 bytes")
        assert(MemoryLayout<H3DeltaUpdate>.stride == 16, "H3DeltaUpdate stride must be 16 bytes")
    }
    
    /// 64-to-32 bit MurmurHash3 finalizer matching the MSL `hash64_to_32` implementation.
    @inlinable
    public static func hash64To32(_ key: UInt64) -> UInt32 {
        var k = key
        k ^= k >> 33
        k = k &* 0xff51afd7ed558ccd
        k ^= k >> 33
        k = k &* 0xc4ceb9fe1a85ec53
        k ^= k >> 33
        return UInt32(truncatingIfNeeded: k)
    }
    
    /// In-shader bitwise parent LOD aggregator converting a Resolution 11 H3 index
    /// to coarser parent resolutions (Res 10, 9, 8, 5, 0) dynamically without extra memory buffers.
    @inlinable
    public static func convertH3ToParent(h3Index11: UInt64, targetRes: UInt32) -> UInt64 {
        guard targetRes < 11 else { return h3Index11 }
        
        // Mask off Resolution Bits (55-52) and insert target resolution
        var base = h3Index11 & ~(UInt64(0xF) << 52)
        base |= (UInt64(targetRes) << 52)
        
        // Child digits for resolutions lower than targetRes start at bit 12
        let bitCount = (11 - targetRes) * 3
        let startBit = 12
        let unusedMask = ((UInt64(1) << bitCount) - 1) << startBit
        
        // Set child digits to all 1s (digit 7, matching unused resolution representation)
        base |= unusedMask
        return base
    }
}
