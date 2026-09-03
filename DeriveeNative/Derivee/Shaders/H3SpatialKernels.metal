#include <metal_stdlib>
using namespace metal;

struct H3HashSlot {
    uint64_t h3Index;
    uint32_t unlockTimestamp;
    atomic_uint flags; // 0x0 = Empty, 0x1 = Claiming, 0x2 = Occupied
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

// Integer hash function (MurmurHash3 64-to-32 bit finalizer adaptation)
inline uint hash64_to_32(uint64_t key) {
    key ^= key >> 33;
    key *= 0xff51afd7ed558ccdULL;
    key ^= key >> 33;
    key *= 0xc4ceb9fe1a85ec53ULL;
    key ^= key >> 33;
    return static_cast<uint>(key);
}

// In-Shader Bitwise Parent LOD Aggregator converting Res-11 index to parent resolutions
inline uint64_t convert_h3_to_parent(uint64_t h3Index11, uint targetRes) {
    if (targetRes >= 11) return h3Index11;

    // Mask off Resolution Bits (55-52) and insert target resolution
    uint64_t base = h3Index11 & ~(0xFULL << 52);
    base |= (static_cast<uint64_t>(targetRes) << 52);

    // Child digits for resolutions lower than targetRes start at bit 12
    uint bitCount = (11 - targetRes) * 3;
    uint startBit = 12;
    uint64_t unusedMask = ((1ULL << bitCount) - 1ULL) << startBit;

    // Set child digits to all 1s (digit 7)
    base |= unusedMask;

    return base;
}

// Lock-Free Parallel Atomic Insertion Kernel
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
        device atomic_uint* slotFlagsPtr = reinterpret_cast<device atomic_uint*>(&(hashTable[currentSlot].flags));
        uint expected = 0;
        
        // Attempt lock-free insertion using Compare-And-Swap (CAS) on slot flags
        bool success = atomic_compare_exchange_weak_explicit(
            slotFlagsPtr,
            &expected,
            1,
            memory_order_relaxed,
            memory_order_relaxed
        );

        if (success) {
            hashTable[currentSlot].h3Index = key;
            hashTable[currentSlot].unlockTimestamp = update.unlockTimestamp;
            atomic_store_explicit(slotFlagsPtr, 2, memory_order_relaxed);
            atomic_fetch_add_explicit(reinterpret_cast<device atomic_uint*>(&(header.activeCount)), 1, memory_order_relaxed);
            atomic_fetch_max_explicit(reinterpret_cast<device atomic_uint*>(&(header.maxProbeDepth)), probeDepth + 1, memory_order_relaxed);
            return;
        } else if (hashTable[currentSlot].h3Index == key) {
            hashTable[currentSlot].unlockTimestamp = max(hashTable[currentSlot].unlockTimestamp, update.unlockTimestamp);
            return;
        }

        probeDepth++;
    }
}

// Fast parallel clearing kernel for resetting table state
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

// Query Helper: Evaluates whether an H3 cell index exists in the GPU hash table
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
            return true; // Hex is unlocked
        }
        if (state == 0) {
            return false; // Reached empty slot; key does not exist
        }

        probeDepth++;
    }

    return false;
}

// Compute Kernel: Batch GPU query evaluation for automated testing and telemetry
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

// Fragment Shader for Adaptive Coverage Rendering
fragment float4 render_adaptive_h3_coverage(
    float4                      screenPos   [[position]],
    device const H3HashSlot*    hashTable   [[buffer(0)]],
    constant H3HashTableHeader& header      [[buffer(1)]],
    constant uint64_t&          rawRes11Hex [[buffer(2)]],
    constant float&             cameraZoom  [[buffer(3)]]
) {
    uint targetRes = 11;
    if (cameraZoom < 6.0f) {
        targetRes = 5;
    } else if (cameraZoom < 11.0f) {
        targetRes = 8;
    } else if (cameraZoom < 14.0f) {
        targetRes = 10;
    }

    uint64_t queryKey = (targetRes == 11) ? rawRes11Hex : convert_h3_to_parent(rawRes11Hex, targetRes);
    bool isExplored = query_h3_spatial_coverage(hashTable, header, queryKey);

    if (isExplored) {
        return float4(0.0, 0.85, 0.95, 0.40); // Unlocked aperture tint
    }
    
    discard_fragment();
    return float4(0.0);
}
