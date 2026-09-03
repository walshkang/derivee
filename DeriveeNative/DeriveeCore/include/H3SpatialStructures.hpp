#ifndef H3SpatialStructures_hpp
#define H3SpatialStructures_hpp

#include <cstdint>
#include <type_traits>

#pragma pack(push, 16)

/// Represents a single slot inside the GPU spatial hash table.
/// Total size: 16 bytes. Alignment: 16 bytes.
struct alignas(16) H3HashSlot {
    uint64_t h3Index;          // Uber H3 Res-11 Index (0 if slot is empty)
    uint32_t unlockTimestamp;  // Unix epoch timestamp of exploration
    uint32_t flags;            // Slot state flags (0x0 = Empty, 0x1 = Occupied)
};

/// Header state buffer governing GPU hash table metadata.
/// Total size: 64 bytes. Alignment: 16 bytes.
struct alignas(16) H3HashTableHeader {
    uint32_t capacity;          // Total slot capacity (power of 2, e.g., 262144)
    uint32_t capacityMask;      // Capacity minus 1 (e.g., 262143) for fast bitwise modulo
    uint32_t activeCount;       // Atomic count of currently inserted keys
    uint32_t maxProbeDepth;     // Metric tracking worst-case linear probe depth
    
    uint32_t deltaCount;        // Pending delta updates in staging buffer
    uint32_t res11Resolution;   // Hardcoded resolution verifier (11)
    uint8_t  padding[40];       // Padding to complete 64-byte boundary
};

/// Staging slot for streaming updates from SQLite to GPU.
/// Total size: 16 bytes. Alignment: 16 bytes.
struct alignas(16) H3DeltaUpdate {
    uint64_t h3Index;
    uint32_t unlockTimestamp;
    uint32_t reserved;
};

#pragma pack(pop)

// Static assertions proving ABI layout invariants
static_assert(sizeof(H3HashSlot) == 16, "H3HashSlot must be exactly 16 bytes");
static_assert(alignof(H3HashSlot) == 16, "H3HashSlot alignment must be 16 bytes");
static_assert(sizeof(H3HashTableHeader) == 64, "H3HashTableHeader must be exactly 64 bytes");
static_assert(alignof(H3HashTableHeader) == 16, "H3HashTableHeader alignment must be 16 bytes");
static_assert(sizeof(H3DeltaUpdate) == 16, "H3DeltaUpdate must be exactly 16 bytes");
static_assert(alignof(H3DeltaUpdate) == 16, "H3DeltaUpdate alignment must be 16 bytes");

#endif /* H3SpatialStructures_hpp */
