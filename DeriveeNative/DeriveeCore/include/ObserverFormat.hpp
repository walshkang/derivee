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
};
static_assert(sizeof(WalkNode) == 16, "WalkNode layout mismatch");

// Quantized Pedestrian Edge (walk_graph.bin)
struct alignas(4) WalkEdge {
    uint32_t target_node_idx; // Destination node index
    uint16_t distance_cm;     // Distance in centimeters
    uint16_t weight_ms;       // Traversal cost in milliseconds

    constexpr WalkEdge() noexcept
        : target_node_idx(0), distance_cm(0), weight_ms(0) {}
};
static_assert(sizeof(WalkEdge) == 8, "WalkEdge layout mismatch");

} // namespace observer::format
