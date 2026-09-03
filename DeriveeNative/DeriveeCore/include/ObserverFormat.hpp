#pragma once

#include <cstdint>
#include <cstddef>
#include <array>
#include <type_traits>

namespace observer::format {

// Magic Identifiers for Observer Assets
constexpr uint32_t MAGIC_TIMETABLE       = 0x31565244; // "DRV1"
constexpr uint32_t MAGIC_ULTRA_TRANSFERS = 0x41525455; // "UTRA"
constexpr uint32_t MAGIC_WALK_GRAPH      = 0x4B4C4157; // "WALK"
constexpr uint32_t MAGIC_WALK_OFFSETS    = 0x53464F57; // "WOFS"
constexpr uint32_t MAGIC_WALK_EDGES      = 0x47444557; // "WEDG"
constexpr uint32_t MAGIC_WALK_RTREE      = 0x54524C57; // "WLRT"
constexpr uint32_t ENDIAN_MARKER         = 0x01020304;
constexpr uint32_t MASTER_HEADER_SIZE    = 232;

// Section Descriptor within TOC
struct alignas(8) SectionDesc {
    uint64_t offset;     // Absolute byte offset in file
    uint64_t size_bytes; // Raw byte length of payload
    uint64_t item_count; // Number of typed elements

    constexpr SectionDesc() noexcept : offset(0), size_bytes(0), item_count(0) {}
    constexpr SectionDesc(uint64_t off, uint64_t size, uint64_t count) noexcept
        : offset(off), size_bytes(size), item_count(count) {}
};
static_assert(sizeof(SectionDesc) == 24, "SectionDesc size mismatch");

// Universal Master File Header (40B fixed fields + 8 x 24B TOC SectionDesc = 232B)
struct alignas(8) MasterHeader {
    uint32_t magic;                 // Asset signature
    uint32_t schema_version;        // Version descriptor
    uint32_t endian_marker;         // Endianness verification
    uint32_t header_size;           // Must be 232
    uint64_t file_size;             // Total payload length
    uint64_t checksum_xxh64;        // Payload hash
    uint32_t num_sections;          // Active sections in TOC (up to 8)
    uint32_t flags;                 // Reserved flags
    std::array<SectionDesc, 8> toc; // Table of Contents

    constexpr MasterHeader() noexcept
        : magic(0), schema_version(0), endian_marker(0), header_size(MASTER_HEADER_SIZE),
          file_size(0), checksum_xxh64(0), num_sections(0), flags(0), toc{} {}
};
static_assert(sizeof(MasterHeader) == 232, "MasterHeader must be exactly 232 bytes");

// RAPTOR Stop Structure (timetable.bin)
struct alignas(8) RaptorStop {
    uint32_t stop_id;
    uint32_t route_index_offset;
    uint32_t route_count;
    uint32_t transfer_offset;
    uint32_t transfer_count;
    uint32_t _reserved; // Explicit 4-byte padding to align struct to 8-byte boundary

    constexpr RaptorStop() noexcept
        : stop_id(0), route_index_offset(0), route_count(0), transfer_offset(0), transfer_count(0), _reserved(0) {}
};
static_assert(sizeof(RaptorStop) == 24, "RaptorStop size layout mismatch");

// Quantized Pedestrian Node (walk_graph.bin)
struct alignas(8) WalkNode {
    int32_t lat_quantized;   // Fixed-point latitude (* 1e7)
    int32_t lon_quantized;   // Fixed-point longitude (* 1e7)
    uint32_t first_edge_idx; // Index into edge payload array
    uint16_t edge_count;     // Outgoing edge count
    uint16_t access_flags;   // Pedestrian accessibility bitmask

    constexpr WalkNode() noexcept
        : lat_quantized(0), lon_quantized(0), first_edge_idx(0), edge_count(0), access_flags(0) {}

    constexpr WalkNode(int32_t lat_q, int32_t lon_q, uint32_t first_edge, uint16_t count, uint16_t flags = 0) noexcept
        : lat_quantized(lat_q), lon_quantized(lon_q), first_edge_idx(first_edge), edge_count(count), access_flags(flags) {}
};
// WalkNode access_flags bitmask definitions
static constexpr uint16_t WALK_FLAG_WALKABLE         = 0x0001; // Bit 0: Walkable pedestrian surface
static constexpr uint16_t WALK_FLAG_WHEELCHAIR       = 0x0002; // Bit 1: Step-free / wheelchair accessible
static constexpr uint16_t WALK_FLAG_IS_STEPS         = 0x0004; // Bit 2: Pedestrian flight of stairs
static constexpr uint16_t WALK_FLAG_IS_ELEVATOR      = 0x0008; // Bit 3: Elevator transit connection
static constexpr uint16_t WALK_FLAG_TRAFFIC_SIGNAL   = 0x0010; // Bit 4: Verified Traffic Signal (Wave N-D.6.1)

static_assert(sizeof(WalkNode) == 16, "WalkNode layout mismatch");

// Quantized Pedestrian Edge (walk_graph.bin)
struct alignas(4) WalkEdge {
    uint32_t target_node_idx; // Destination node index
    uint16_t distance_cm;     // Distance in centimeters
    uint16_t weight_ms;       // Traversal cost in milliseconds

    constexpr WalkEdge() noexcept
        : target_node_idx(0), distance_cm(0), weight_ms(0) {}

    constexpr WalkEdge(uint32_t target, uint16_t dist, uint16_t weight) noexcept
        : target_node_idx(target), distance_cm(dist), weight_ms(weight) {}
};
static_assert(sizeof(WalkEdge) == 8, "WalkEdge layout mismatch");

// Static Packed Hilbert R-Tree Node (walk_rtree.bin)
struct alignas(8) RTreeNodeItem {
    int32_t min_lat_q;     // Minimum latitude * 1e7
    int32_t min_lon_q;     // Minimum longitude * 1e7
    int32_t max_lat_q;     // Maximum latitude * 1e7
    int32_t max_lon_q;     // Maximum longitude * 1e7
    uint32_t child_offset; // Index of first child in array, or NodeIdx if leaf
    uint16_t num_children; // Number of active child items (<= BranchingFactor)
    uint16_t flags;        // 0 = internal branch node, 1 = leaf node

    constexpr RTreeNodeItem() noexcept
        : min_lat_q(0), min_lon_q(0), max_lat_q(0), max_lon_q(0),
          child_offset(0), num_children(0), flags(0) {}
};
static_assert(sizeof(RTreeNodeItem) == 24, "RTreeNodeItem layout mismatch");

// Static Packed Hilbert R-Tree Metadata (walk_rtree.bin)
struct alignas(4) RTreeMetadata {
    int32_t min_lat_q;
    int32_t min_lon_q;
    int32_t max_lat_q;
    int32_t max_lon_q;
    uint32_t branching_factor;
    uint32_t num_levels;
    uint32_t total_nodes;
    uint32_t num_leaves;

    constexpr RTreeMetadata() noexcept
        : min_lat_q(0), min_lon_q(0), max_lat_q(0), max_lon_q(0),
          branching_factor(0), num_levels(0), total_nodes(0), num_leaves(0) {}
};
static_assert(sizeof(RTreeMetadata) == 32, "RTreeMetadata layout mismatch");

} // namespace observer::format
