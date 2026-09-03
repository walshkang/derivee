import Foundation
import Metal
import GRDB

/// High-throughput Metal spatial memory engine managing the open-addressing H3 GPU hash table in `MTLBuffer`.
/// Strictly adheres to the < 10.0 MB VRAM budget (allocates exactly 4.26 MB) and provides zero-copy
/// CPU-to-GPU streaming via Apple Silicon Unified Memory Architecture (`.storageModeShared`).
public final class H3SpatialMemoryEngine: @unchecked Sendable {
    
    public let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    
    private let insertPipelineState: MTLComputePipelineState
    private let clearPipelineState: MTLComputePipelineState
    private let queryPipelineState: MTLComputePipelineState
    
    public private(set) var hashTableBuffer: MTLBuffer!
    public private(set) var headerBuffer: MTLBuffer!
    public private(set) var deltaBuffer: MTLBuffer!
    
    /// Total hash table capacity (2^18 = 262,144 slots / 4.00 MiB)
    public let tableCapacity: UInt32
    
    /// Maximum delta updates processed in a single compute kernel dispatch (64 KiB staging buffer)
    public let maxDeltaBatchSize: Int = 4_096
    
    public init(device: MTLDevice? = nil, tableCapacity: UInt32 = 262_144) throws {
        guard let mtlDevice = device ?? MTLCreateSystemDefaultDevice() else {
            throw NSError(
                domain: "H3SpatialMemoryEngineError",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to obtain system default MTLDevice"]
            )
        }
        self.device = mtlDevice
        self.tableCapacity = tableCapacity
        
        guard let queue = mtlDevice.makeCommandQueue() else {
            throw NSError(
                domain: "H3SpatialMemoryEngineError",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "Failed to create MTLCommandQueue"]
            )
        }
        self.commandQueue = queue
        
        // 1. Dual library loader: Try app bundle, test bundle, default library, or fallback compile
        let library: MTLLibrary
        if let bundleLib = try? mtlDevice.makeDefaultLibrary(bundle: Bundle.main) {
            library = bundleLib
        } else if let frameworkLib = try? mtlDevice.makeDefaultLibrary(bundle: Bundle(for: H3SpatialMemoryEngine.self)) {
            library = frameworkLib
        } else if let defaultLib = try? mtlDevice.makeDefaultLibrary() {
            library = defaultLib
        } else {
            library = try mtlDevice.makeLibrary(source: H3SpatialKernelsEmbeddedSource, options: nil)
        }
        
        // 2. Resolve compute pipelines
        guard let insertFunc = library.makeFunction(name: "insert_h3_deltas") else {
            throw NSError(
                domain: "H3SpatialMemoryEngineError",
                code: -3,
                userInfo: [NSLocalizedDescriptionKey: "Compute kernel 'insert_h3_deltas' not found"]
            )
        }
        self.insertPipelineState = try mtlDevice.makeComputePipelineState(function: insertFunc)
        
        guard let clearFunc = library.makeFunction(name: "clear_h3_hash_table") else {
            throw NSError(
                domain: "H3SpatialMemoryEngineError",
                code: -4,
                userInfo: [NSLocalizedDescriptionKey: "Compute kernel 'clear_h3_hash_table' not found"]
            )
        }
        self.clearPipelineState = try mtlDevice.makeComputePipelineState(function: clearFunc)
        
        guard let queryFunc = library.makeFunction(name: "query_h3_coverage_batch") else {
            throw NSError(
                domain: "H3SpatialMemoryEngineError",
                code: -5,
                userInfo: [NSLocalizedDescriptionKey: "Compute kernel 'query_h3_coverage_batch' not found"]
            )
        }
        self.queryPipelineState = try mtlDevice.makeComputePipelineState(function: queryFunc)
        
        // 3. Allocate shared unified memory buffers
        try allocateBuffers()
    }
    
    private func allocateBuffers() throws {
        H3ABIVerifier.verifyLayouts()
        
        // Main Hash Table Buffer: 262,144 slots * 16 bytes = 4,194,304 bytes (4.00 MiB)
        let hashByteSize = Int(tableCapacity) * MemoryLayout<H3HashSlot>.stride
        guard let hTable = device.makeBuffer(length: hashByteSize, options: .storageModeShared) else {
            throw NSError(
                domain: "H3SpatialMemoryEngineError",
                code: -6,
                userInfo: [NSLocalizedDescriptionKey: "Failed to allocate hashTableBuffer (\(hashByteSize) bytes)"]
            )
        }
        self.hashTableBuffer = hTable
        memset(hashTableBuffer.contents(), 0, hashByteSize)
        
        // Header Buffer: 64 bytes (16-byte aligned)
        let headerSize = MemoryLayout<H3HashTableHeader>.stride
        guard let headBuf = device.makeBuffer(length: headerSize, options: .storageModeShared) else {
            throw NSError(
                domain: "H3SpatialMemoryEngineError",
                code: -7,
                userInfo: [NSLocalizedDescriptionKey: "Failed to allocate headerBuffer (\(headerSize) bytes)"]
            )
        }
        self.headerBuffer = headBuf
        var initialHeader = H3HashTableHeader(capacity: tableCapacity)
        memcpy(headerBuffer.contents(), &initialHeader, headerSize)
        
        // Staging Delta Buffer: 4,096 slots * 16 bytes = 65,536 bytes (64 KiB)
        let deltaByteSize = maxDeltaBatchSize * MemoryLayout<H3DeltaUpdate>.stride
        guard let dBuf = device.makeBuffer(length: deltaByteSize, options: .storageModeShared) else {
            throw NSError(
                domain: "H3SpatialMemoryEngineError",
                code: -8,
                userInfo: [NSLocalizedDescriptionKey: "Failed to allocate deltaBuffer (\(deltaByteSize) bytes)"]
            )
        }
        self.deltaBuffer = dBuf
        memset(deltaBuffer.contents(), 0, deltaByteSize)
    }
    
    // MARK: - Memory Telemetry (< 10.0 MB Hard Budget)
    
    /// Total VRAM allocated across all spatial buffers in bytes.
    /// Strictly guarantees 4,259,904 bytes (~4.26 MB), maintaining a 57.4% safety margin below 10 MB.
    public var currentVRAMUsageBytes: Int {
        return (hashTableBuffer?.length ?? 0) + (headerBuffer?.length ?? 0) + (deltaBuffer?.length ?? 0)
    }
    
    /// Reads the atomic header state directly from unified memory.
    public func readHeader() -> H3HashTableHeader {
        let ptr = headerBuffer.contents().bindMemory(to: H3HashTableHeader.self, capacity: 1)
        return ptr.pointee
    }
    
    // MARK: - Zero-Copy Ingestion Pipeline
    
    /// Ingests an arbitrary array of `H3DeltaUpdate` structs into the GPU hash table.
    /// Automatically partitions deltas into 4,096-slot chunks, writes directly into `.storageModeShared` memory,
    /// and executes parallel lock-free atomic Compare-And-Swap insertions on the GPU.
    public func ingestDeltas(_ deltas: [H3DeltaUpdate]) async throws {
        guard !deltas.isEmpty else { return }
        
        var offset = 0
        let total = deltas.count
        
        while offset < total {
            let chunkCount = min(total - offset, maxDeltaBatchSize)
            let chunk = Array(deltas[offset..<(offset + chunkCount)])
            
            // Direct zero-copy write to staging buffer
            let destPtr = deltaBuffer.contents().bindMemory(to: H3DeltaUpdate.self, capacity: chunkCount)
            _ = chunk.withUnsafeBufferPointer { srcPtr in
                if let srcAddress = srcPtr.baseAddress {
                    destPtr.update(from: srcAddress, count: chunkCount)
                }
            }
            
            // Update deltaCount in header
            let headerPtr = headerBuffer.contents().bindMemory(to: H3HashTableHeader.self, capacity: 1)
            headerPtr.pointee.deltaCount = UInt32(chunkCount)
            
            // Dispatch atomic insertion compute kernel
            guard let commandBuffer = commandQueue.makeCommandBuffer(),
                  let encoder = commandBuffer.makeComputeCommandEncoder() else {
                throw NSError(
                    domain: "H3SpatialMemoryEngineError",
                    code: -9,
                    userInfo: [NSLocalizedDescriptionKey: "Failed to create Metal compute command encoder"]
                )
            }
            
            encoder.setComputePipelineState(insertPipelineState)
            encoder.setBuffer(hashTableBuffer, offset: 0, index: 0)
            encoder.setBuffer(headerBuffer, offset: 0, index: 1)
            encoder.setBuffer(deltaBuffer, offset: 0, index: 2)
            
            let threadgroupWidth = min(chunkCount, insertPipelineState.maxTotalThreadsPerThreadgroup)
            let threadgroupSize = MTLSize(width: threadgroupWidth, height: 1, depth: 1)
            let gridSize = MTLSize(width: chunkCount, height: 1, depth: 1)
            
            encoder.dispatchThreads(gridSize, threadsPerThreadgroup: threadgroupSize)
            encoder.endEncoding()
            
            commandBuffer.commit()
            commandBuffer.waitUntilCompleted()
            
            offset += chunkCount
        }
    }
    
    /// Convenience ingestion method for native `(UInt64, UInt32)` index and timestamp pairs.
    public func ingestHexIndices(_ indices: [(h3Index: UInt64, timestamp: UInt32)]) async throws {
        let deltas = indices.map { H3DeltaUpdate(h3Index: $0.h3Index, unlockTimestamp: $0.timestamp) }
        try await ingestDeltas(deltas)
    }
    
    /// Convenience ingestion method converting 15-character hex strings into 64-bit integer keys.
    public func ingestExploredHexStrings(_ hexes: [(hex: String, timestamp: UInt32)]) async throws {
        var deltas: [H3DeltaUpdate] = []
        deltas.reserveCapacity(hexes.count)
        
        for item in hexes {
            if let index = UInt64(item.hex, radix: 16) {
                deltas.append(H3DeltaUpdate(h3Index: index, unlockTimestamp: item.timestamp))
            }
        }
        
        try await ingestDeltas(deltas)
    }
    
    /// Resets all slots in the hash table buffer to 0 and clears the header counters.
    public func reset() async throws {
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder() else {
            throw NSError(
                domain: "H3SpatialMemoryEngineError",
                code: -10,
                userInfo: [NSLocalizedDescriptionKey: "Failed to create clear command encoder"]
            )
        }
        
        encoder.setComputePipelineState(clearPipelineState)
        encoder.setBuffer(hashTableBuffer, offset: 0, index: 0)
        encoder.setBuffer(headerBuffer, offset: 0, index: 1)
        
        let totalSlots = Int(tableCapacity)
        let threadgroupWidth = min(totalSlots, clearPipelineState.maxTotalThreadsPerThreadgroup)
        let threadgroupSize = MTLSize(width: threadgroupWidth, height: 1, depth: 1)
        let gridSize = MTLSize(width: totalSlots, height: 1, depth: 1)
        
        encoder.dispatchThreads(gridSize, threadsPerThreadgroup: threadgroupSize)
        encoder.endEncoding()
        
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
    }
    
    // MARK: - Batch GPU Query Pipeline (Testing & Evaluation)
    
    /// Evaluates spatial coverage across a batch of H3 cell indices on the GPU.
    /// When `cameraZoom` is zoomed out (<14.0), the GPU dynamically aggregates indices into parent LODs
    /// via in-shader bitwise operations without extra memory allocations.
    public func queryCoverage(indices: [UInt64], cameraZoom: Float = 18.0) async throws -> [Bool] {
        guard !indices.isEmpty else { return [] }
        
        let count = indices.count
        let queryByteSize = count * MemoryLayout<UInt64>.stride
        guard let queryInputBuffer = device.makeBuffer(bytes: indices, length: queryByteSize, options: .storageModeShared) else {
            throw NSError(
                domain: "H3SpatialMemoryEngineError",
                code: -11,
                userInfo: [NSLocalizedDescriptionKey: "Failed to allocate queryInputBuffer"]
            )
        }
        
        let resultByteSize = count * MemoryLayout<UInt32>.stride
        guard let resultBuffer = device.makeBuffer(length: resultByteSize, options: .storageModeShared) else {
            throw NSError(
                domain: "H3SpatialMemoryEngineError",
                code: -12,
                userInfo: [NSLocalizedDescriptionKey: "Failed to allocate query resultBuffer"]
            )
        }
        
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder() else {
            throw NSError(
                domain: "H3SpatialMemoryEngineError",
                code: -13,
                userInfo: [NSLocalizedDescriptionKey: "Failed to create query encoder"]
            )
        }
        
        var queryCount = UInt32(count)
        var zoom = cameraZoom
        
        encoder.setComputePipelineState(queryPipelineState)
        encoder.setBuffer(hashTableBuffer, offset: 0, index: 0)
        encoder.setBuffer(headerBuffer, offset: 0, index: 1)
        encoder.setBuffer(queryInputBuffer, offset: 0, index: 2)
        encoder.setBuffer(resultBuffer, offset: 0, index: 3)
        encoder.setBytes(&queryCount, length: MemoryLayout<UInt32>.stride, index: 4)
        encoder.setBytes(&zoom, length: MemoryLayout<Float>.stride, index: 5)
        
        let threadgroupWidth = min(count, queryPipelineState.maxTotalThreadsPerThreadgroup)
        let threadgroupSize = MTLSize(width: threadgroupWidth, height: 1, depth: 1)
        let gridSize = MTLSize(width: count, height: 1, depth: 1)
        
        encoder.dispatchThreads(gridSize, threadsPerThreadgroup: threadgroupSize)
        encoder.endEncoding()
        
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        
        let resultPtr = resultBuffer.contents().bindMemory(to: UInt32.self, capacity: count)
        var results = [Bool](repeating: false, count: count)
        for i in 0..<count {
            results[i] = resultPtr[i] == 1
        }
        return results
    }
    
    // MARK: - SQLite Database Hydration Bridge
    
    /// Hydrates the GPU hash table directly from the active metro's `explored_hexes_{slug}` table.
    /// Executes an async non-blocking read against `DatabaseWriter` and streams all rows via zero-copy deltas.
    @discardableResult
    public func hydrateFromDatabase(dbWriter: DatabaseWriter, citySlug: String) async throws -> Int {
        let tableName = SpatialDatabaseManager.tableName(for: citySlug)
        let hexStrings: [String] = try await dbWriter.read { db in
            guard try db.tableExists(tableName) else { return [] }
            return try String.fetchAll(db, sql: "SELECT h3_index FROM \(tableName)")
        }
        
        guard !hexStrings.isEmpty else { return 0 }
        
        let now = UInt32(Date().timeIntervalSince1970)
        let items = hexStrings.map { (hex: $0, timestamp: now) }
        try await ingestExploredHexStrings(items)
        return hexStrings.count
    }
}

// MARK: - Fallback Embedded MSL Shader Source
// Provides seamless compilation in headless unit tests where default.metallib is not pre-packaged.
private let H3SpatialKernelsEmbeddedSource = """
#include <metal_stdlib>
using namespace metal;

struct H3HashSlot {
    uint64_t h3Index;
    uint32_t unlockTimestamp;
    atomic_uint flags;
};

struct H3HashTableHeader {
    uint capacity;
    uint capacityMask;
    atomic_uint activeCount;
    atomic_uint maxProbeDepth;
    uint deltaCount;
    uint res11Resolution;
    uint padding[10];
};

struct H3DeltaUpdate {
    uint64_t h3Index;
    uint32_t unlockTimestamp;
    uint32_t reserved;
};

inline uint hash64_to_32(uint64_t key) {
    key ^= key >> 33;
    key *= 0xff51afd7ed558ccdULL;
    key ^= key >> 33;
    key *= 0xc4ceb9fe1a85ec53ULL;
    key ^= key >> 33;
    return static_cast<uint>(key);
}

inline uint64_t convert_h3_to_parent(uint64_t h3Index11, uint targetRes) {
    if (targetRes >= 11) return h3Index11;
    uint64_t base = h3Index11 & ~(0xFULL << 52);
    base |= (static_cast<uint64_t>(targetRes) << 52);
    uint bitCount = (11 - targetRes) * 3;
    uint startBit = 12;
    uint64_t unusedMask = ((1ULL << bitCount) - 1ULL) << startBit;
    base |= unusedMask;
    return base;
}

kernel void insert_h3_deltas(
    device   H3HashSlot*        hashTable   [[buffer(0)]],
    device   H3HashTableHeader& header      [[buffer(1)]],
    constant H3DeltaUpdate*     deltaArray  [[buffer(2)]],
    uint                        id          [[thread_position_in_grid]]
) {
    if (id >= header.deltaCount) return;

    H3DeltaUpdate update = deltaArray[id];
    uint64_t key = update.h3Index;
    if (key == 0ULL) return;

    uint hash = hash64_to_32(key);
    uint capacityMask = header.capacityMask;
    uint slotIndex = hash & capacityMask;
    uint probeDepth = 0;

    while (probeDepth < 128) {
        uint currentSlot = (slotIndex + probeDepth) & capacityMask;
        uint state = atomic_load_explicit(&(hashTable[currentSlot].flags), memory_order_relaxed);

        if (state == 2) {
            if (hashTable[currentSlot].h3Index == key) {
                hashTable[currentSlot].unlockTimestamp = max(hashTable[currentSlot].unlockTimestamp, update.unlockTimestamp);
                return;
            }
        } else if (state == 0) {
            uint expected = 0;
            bool success = atomic_compare_exchange_weak_explicit(
                &(hashTable[currentSlot].flags),
                &expected,
                1,
                memory_order_relaxed,
                memory_order_relaxed
            );

            if (success) {
                hashTable[currentSlot].h3Index = key;
                hashTable[currentSlot].unlockTimestamp = update.unlockTimestamp;
                atomic_store_explicit(&(hashTable[currentSlot].flags), 2, memory_order_relaxed);
                atomic_fetch_add_explicit(&(header.activeCount), 1, memory_order_relaxed);
                atomic_fetch_max_explicit(&(header.maxProbeDepth), probeDepth + 1, memory_order_relaxed);
                return;
            }
        }

        probeDepth++;
    }
}

kernel void clear_h3_hash_table(
    device H3HashSlot*        hashTable [[buffer(0)]],
    device H3HashTableHeader& header    [[buffer(1)]],
    uint                      id        [[thread_position_in_grid]]
) {
    if (id < header.capacity) {
        hashTable[id].h3Index = 0ULL;
        hashTable[id].unlockTimestamp = 0;
        atomic_store_explicit(&(hashTable[id].flags), 0, memory_order_relaxed);
    }
    if (id == 0) {
        atomic_store_explicit(&(header.activeCount), 0, memory_order_relaxed);
        atomic_store_explicit(&(header.maxProbeDepth), 0, memory_order_relaxed);
        header.deltaCount = 0;
    }
}

inline bool query_h3_spatial_coverage(
    device const H3HashSlot* hashTable,
    constant H3HashTableHeader& header,
    uint64_t targetH3Index
) {
    if (targetH3Index == 0ULL) return false;

    uint hash = hash64_to_32(targetH3Index);
    uint capacityMask = header.capacityMask;
    uint slotIndex = hash & capacityMask;
    uint probeDepth = 0;

    while (probeDepth < 64) {
        uint currentSlot = (slotIndex + probeDepth) & capacityMask;
        uint state = atomic_load_explicit(&(hashTable[currentSlot].flags), memory_order_relaxed);

        if (state == 2 && hashTable[currentSlot].h3Index == targetH3Index) {
            return true;
        }
        if (state == 0) {
            return false;
        }
        probeDepth++;
    }
    return false;
}

kernel void query_h3_coverage_batch(
    device const H3HashSlot*    hashTable    [[buffer(0)]],
    constant H3HashTableHeader& header       [[buffer(1)]],
    constant uint64_t*          queryIndices [[buffer(2)]],
    device   uint32_t*          results      [[buffer(3)]],
    constant uint32_t&          queryCount   [[buffer(4)]],
    constant float&             cameraZoom   [[buffer(5)]],
    uint                        id           [[thread_position_in_grid]]
) {
    if (id >= queryCount) return;

    uint64_t rawHex = queryIndices[id];
    uint targetRes = 11;
    if (cameraZoom < 6.0f) {
        targetRes = 5;
    } else if (cameraZoom < 11.0f) {
        targetRes = 8;
    } else if (cameraZoom < 14.0f) {
        targetRes = 10;
    }

    uint64_t queryKey = (targetRes == 11) ? rawHex : convert_h3_to_parent(rawHex, targetRes);
    bool hit = query_h3_spatial_coverage(hashTable, header, queryKey);
    results[id] = hit ? 1 : 0;
}
"""
