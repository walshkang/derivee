#pragma once

#include "TimetableStructs.hpp"
#include "ObserverFormat.hpp"
#include "BinaryPayloadView.hpp"
#include "MicroClimateEnergyEvaluator.hpp"
#include <span>
#include <vector>
#include <cstdint>
#include <cmath>
#include <algorithm>
#include <functional>
#include <cstring>

#pragma pack(push, 1)

// CandidateStop: Represents a transit stop reachable via walking access from query coordinates (30 Bytes)
struct CandidateStop {
    uint32_t stop_id;
    float distance_meters;
    uint32_t walk_duration_sec;
    float latitude;
    float longitude;
    uint16_t flags;
    float shade_percentage;
    float pet_index_celsius;

    constexpr CandidateStop() noexcept
        : stop_id(0), distance_meters(0.0f), walk_duration_sec(0),
          latitude(0.0f), longitude(0.0f), flags(0),
          shade_percentage(0.0f), pet_index_celsius(0.0f) {}

    constexpr CandidateStop(uint32_t id, float dist, uint32_t duration,
                            float lat, float lon, uint16_t f) noexcept
        : stop_id(id), distance_meters(dist), walk_duration_sec(duration),
          latitude(lat), longitude(lon), flags(f),
          shade_percentage(0.0f), pet_index_celsius(0.0f) {}

    constexpr CandidateStop(uint32_t id, float dist, uint32_t duration,
                            float lat, float lon, uint16_t f,
                            float shade, float pet) noexcept
        : stop_id(id), distance_meters(dist), walk_duration_sec(duration),
          latitude(lat), longitude(lon), flags(f),
          shade_percentage(shade), pet_index_celsius(pet) {}
};
static_assert(sizeof(CandidateStop) == 30, "CandidateStop layout must be exactly 30 bytes");

// DirectWalkResult: Point-to-point bounded pedestrian routing result (20 Bytes)
struct DirectWalkResult {
    float distance_meters;
    uint32_t walk_duration_sec;
    bool path_found;
    float shade_percentage;
    float pet_index_celsius;
    uint8_t _padding[3];

    constexpr DirectWalkResult() noexcept
        : distance_meters(0.0f), walk_duration_sec(0), path_found(false),
          shade_percentage(0.0f), pet_index_celsius(0.0f), _padding{0, 0, 0} {}

    constexpr DirectWalkResult(float dist, uint32_t dur, bool found) noexcept
        : distance_meters(dist), walk_duration_sec(dur), path_found(found),
          shade_percentage(0.0f), pet_index_celsius(0.0f), _padding{0, 0, 0} {}

    constexpr DirectWalkResult(float dist, uint32_t dur, bool found,
                               float shade, float pet) noexcept
        : distance_meters(dist), walk_duration_sec(dur), path_found(found),
          shade_percentage(shade), pet_index_celsius(pet), _padding{0, 0, 0} {}
};
static_assert(sizeof(DirectWalkResult) == 20, "DirectWalkResult layout must be exactly 20 bytes");

#pragma pack(pop)

// Accessibility & Feature Flags for Pedestrian Edges/Nodes
constexpr uint16_t WALK_FLAG_WALKABLE              = 1 << 0;
constexpr uint16_t WALK_FLAG_WHEELCHAIR_ACCESSIBLE = 1 << 1;
constexpr uint16_t WALK_FLAG_IS_STEPS              = 1 << 2;
constexpr uint16_t WALK_FLAG_IS_ELEVATOR           = 1 << 3;
constexpr uint16_t WALK_FLAG_TREE_CANOPY_LOW       = 1 << 4; // ~30% tree canopy cover
constexpr uint16_t WALK_FLAG_TREE_CANOPY_HIGH      = 1 << 5; // ~75% tree canopy cover (parks/greenways)
constexpr uint16_t WALK_FLAG_CANYON_HIGH_RISE      = 1 << 6; // H/W ~ 2.5 (Midtown high-rise canyon)
constexpr uint16_t WALK_FLAG_CANYON_MID_RISE       = 1 << 7; // H/W ~ 1.2 (Mid-rise brownstone avenue)

/**
 * @brief Zero-copy reader and validator for binary pedestrian walk graph (walk_graph.bin).
 */
class WalkGraphStore {
private:
    const uint8_t* raw_blob_ptr_ = nullptr;
    size_t raw_blob_size_ = 0;
    bool is_loaded_ = false;

    std::span<const observer::format::WalkNode> nodes_{};
    std::span<const observer::format::WalkEdge> edges_{};
    observer::format::MasterHeader header_{};

public:
    WalkGraphStore() noexcept = default;

    bool load_blob(const uint8_t* buffer_ptr, size_t length_bytes) noexcept;
    void reset() noexcept;

    [[nodiscard]] bool is_loaded() const noexcept { return is_loaded_; }
    [[nodiscard]] std::span<const observer::format::WalkNode> nodes() const noexcept { return nodes_; }
    [[nodiscard]] std::span<const observer::format::WalkEdge> edges() const noexcept { return edges_; }
    [[nodiscard]] size_t node_count() const noexcept { return nodes_.size(); }
    [[nodiscard]] size_t edge_count() const noexcept { return edges_.size(); }
    [[nodiscard]] const observer::format::MasterHeader& header() const noexcept { return header_; }
};

/**
 * @brief 2D uniform grid spatial index over quantized walk nodes.
 * Provides sub-0.05ms nearest-neighbor snapping with zero heap allocation during queries.
 */
class WalkSpatialGrid {
public:
    static constexpr int32_t CELL_SIZE_Q = 25000; // ~0.0025 degrees (~250m)
    static constexpr uint32_t NIL_NODE = 0xFFFFFFFF;

private:
    int32_t min_gx_ = 0;
    int32_t max_gx_ = 0;
    int32_t min_gy_ = 0;
    int32_t max_gy_ = 0;
    int32_t width_cells_ = 0;
    int32_t height_cells_ = 0;

    std::vector<uint32_t> cell_offsets_;
    std::vector<uint32_t> node_indices_;
    std::span<const observer::format::WalkNode> nodes_{};

public:
    WalkSpatialGrid() noexcept = default;

    void build(std::span<const observer::format::WalkNode> nodes);
    inline void build(const observer::format::WalkNode* nodes_ptr, size_t count) {
        if (nodes_ptr && count > 0) {
            build(std::span<const observer::format::WalkNode>(nodes_ptr, count));
        }
    }
    void clear() noexcept;

    [[nodiscard]] bool is_built() const noexcept { return !node_indices_.empty(); }

    [[nodiscard]] uint32_t find_nearest_node(
        int32_t lat_q, int32_t lon_q, float max_radius_m, uint32_t* out_dist_cm = nullptr) const noexcept;

    // Fast sub-millimeter fixed-point Euclidean geodesic distance approximation (in centimeters)
    [[nodiscard]] static inline uint32_t calculate_distance_cm(
        int32_t lat1_q, int32_t lon1_q, int32_t lat2_q, int32_t lon2_q) noexcept {
        constexpr double deg2rad = 0.017453292519943295;
        double mean_lat_rad = (static_cast<double>(lat1_q + lat2_q) * 0.5 * 1e-7) * deg2rad;
        double cos_lat = std::cos(mean_lat_rad);
        double d_lat = static_cast<double>(lat2_q - lat1_q) * 1e-7 * 111139.0;
        double d_lon = static_cast<double>(lon2_q - lon1_q) * 1e-7 * 111139.0 * cos_lat;
        double dist_m = std::sqrt(d_lat * d_lat + d_lon * d_lon);
        return static_cast<uint32_t>(std::round(dist_m * 100.0));
    }
};

/**
 * @brief Bounded One-to-Many Dijkstra and A* Walk Router.
 * Supports:
 * 1. Initial/final transfer leg discovery (<3ms budget, r <= 800m).
 * 2. Euclidean distance heuristic pruning.
 * 3. Step-free / wheelchair accessibility filtering.
 * 4. Point-to-point bounded A* for direct walking legs.
 */
class BoundedAStarRouter {
public:
    static constexpr float DEFAULT_WALK_SPEED_MPS = 1.3f; // ~4.68 km/h (80 m/min)
    static constexpr float DEFAULT_MAX_RADIUS_METERS = 1000.0f; // 1,000m search envelope
    static constexpr float METERS_PER_DEGREE_LAT = 111139.0f;
    static constexpr uint32_t INF_DIST_CM = 0xFFFFFFFF;

    struct NodeState {
        uint32_t dist_cm;
        uint32_t gen;
        uint32_t actual_dist_cm;
        uint32_t shaded_dist_cm;
    };

    struct HeapEntry {
        uint32_t node_idx;
        uint32_t dist_cm;

        constexpr bool operator>(const HeapEntry& other) const noexcept {
            return dist_cm > other.dist_cm;
        }
    };

    struct AStarHeapEntry {
        uint32_t node_idx;
        uint32_t f_score;
        uint32_t g_score;

        constexpr bool operator>(const AStarHeapEntry& other) const noexcept {
            return f_score > other.f_score;
        }
    };

private:
    WalkGraphStore walk_store_{};
    WalkSpatialGrid spatial_grid_{};
    std::span<const Stop> stops_{};

    // Stop-to-Node Snapping Arrays
    std::vector<uint32_t> stop_to_walk_node_;
    std::vector<uint16_t> stop_snap_dist_cm_;

    // Inverted CSR Index: WalkNode -> Snapped Transit Stops
    std::vector<uint32_t> walk_node_stop_offsets_;
    std::vector<uint32_t> snapped_stops_;

    // Pre-allocated traversal state for zero heap allocations in hot loop
    mutable std::vector<NodeState> node_states_;
    mutable uint32_t current_gen_ = 1;
    mutable std::vector<HeapEntry> pq_;
    mutable std::vector<AStarHeapEntry> astar_pq_;

    void snap_stops_internal();
    void reset_dijkstra() const noexcept;

    [[nodiscard]] inline uint32_t get_node_dist(uint32_t u) const noexcept {
        if (u >= node_states_.size() || node_states_[u].gen != current_gen_) {
            return INF_DIST_CM;
        }
        return node_states_[u].dist_cm;
    }

    inline void set_node_dist(uint32_t u, uint32_t d) const noexcept {
        if (u < node_states_.size()) {
            node_states_[u].dist_cm = d;
            node_states_[u].actual_dist_cm = d;
            node_states_[u].shaded_dist_cm = 0;
            node_states_[u].gen = current_gen_;
        }
    }

    inline void set_node_state(uint32_t u, uint32_t weighted_d, uint32_t actual_d, uint32_t shaded_d) const noexcept {
        if (u < node_states_.size()) {
            node_states_[u].dist_cm = weighted_d;
            node_states_[u].actual_dist_cm = actual_d;
            node_states_[u].shaded_dist_cm = shaded_d;
            node_states_[u].gen = current_gen_;
        }
    }

public:
    BoundedAStarRouter() = default;
    ~BoundedAStarRouter() = default;

    // Movable, non-copyable
    BoundedAStarRouter(const BoundedAStarRouter&) = delete;
    BoundedAStarRouter& operator=(const BoundedAStarRouter&) = delete;
    BoundedAStarRouter(BoundedAStarRouter&&) noexcept = default;
    BoundedAStarRouter& operator=(BoundedAStarRouter&&) noexcept = default;

    // Load binary walk graph blob
    bool load_walk_graph_blob(const uint8_t* buffer_ptr, size_t length_bytes) noexcept;

    // Bind timetable stops and trigger snapping
    void bind_stops(std::span<const Stop> stops) noexcept;
    inline void bind_stops(const Stop* stops_ptr, size_t count) noexcept {
        if (stops_ptr && count > 0) {
            bind_stops(std::span<const Stop>(stops_ptr, count));
        }
    }

    // State inspection
    [[nodiscard]] bool is_walk_graph_loaded() const noexcept { return walk_store_.is_loaded(); }
    [[nodiscard]] size_t walk_nodes_count() const noexcept { return walk_store_.node_count(); }
    [[nodiscard]] size_t walk_edges_count() const noexcept { return walk_store_.edge_count(); }

    // Core Bounded One-to-Many SSSP search over quantized walk graph
    [[nodiscard]] inline std::vector<CandidateStop> find_reachable_stops(
        float query_lat,
        float query_lon,
        float max_radius_meters,
        uint16_t required_flags,
        size_t max_results) const noexcept {
        return find_reachable_stops(query_lat, query_lon, max_radius_meters, required_flags, max_results, derivee::climate::MicroClimateConfig{});
    }

    [[nodiscard]] std::vector<CandidateStop> find_reachable_stops(
        float query_lat,
        float query_lon,
        float max_radius_meters,
        uint16_t required_flags,
        size_t max_results,
        const derivee::climate::MicroClimateConfig& microclimate) const noexcept;

    // Direct walk leg evaluation via bounded A*
    [[nodiscard]] inline DirectWalkResult compute_direct_walk(
        float lat1,
        float lon1,
        float lat2,
        float lon2,
        float max_distance_meters,
        uint16_t flags) const noexcept {
        return compute_direct_walk(lat1, lon1, lat2, lon2, max_distance_meters, flags, derivee::climate::MicroClimateConfig{});
    }

    [[nodiscard]] DirectWalkResult compute_direct_walk(
        float lat1,
        float lon1,
        float lat2,
        float lon2,
        float max_distance_meters,
        uint16_t flags,
        const derivee::climate::MicroClimateConfig& microclimate) const noexcept;

    // Flat-Earth geodesic distance approximation (meters)
    [[nodiscard]] static inline float calculate_distance_meters(
        float lat1, float lon1, float lat2, float lon2) noexcept {
        constexpr float deg2rad = 0.017453292519943295f;
        float mean_lat_rad = ((lat1 + lat2) * 0.5f) * deg2rad;
        float cos_lat = std::cos(mean_lat_rad);
        
        float d_lat = (lat2 - lat1) * METERS_PER_DEGREE_LAT;
        float d_lon = (lon2 - lon1) * METERS_PER_DEGREE_LAT * cos_lat;
        
        return std::sqrt(d_lat * d_lat + d_lon * d_lon);
    }

    // Walk duration calculation given distance and pedestrian velocity
    [[nodiscard]] static inline uint32_t calculate_walk_duration_sec(
        float distance_meters, float speed_mps = DEFAULT_WALK_SPEED_MPS) noexcept {
        if (distance_meters <= 0.0f) {
            return 0;
        }
        double speed = (speed_mps > 0.1f) ? static_cast<double>(speed_mps) : static_cast<double>(DEFAULT_WALK_SPEED_MPS);
        return static_cast<uint32_t>(std::round(static_cast<double>(distance_meters) / speed));
    }

    // Static fallback candidate stop discovery (Euclidean distance)
    [[nodiscard]] static inline std::vector<CandidateStop> find_candidate_stops(
        const Stop* stops_ptr,
        size_t count,
        float lat,
        float lon,
        float max_radius_meters = DEFAULT_MAX_RADIUS_METERS,
        uint16_t required_flags = 0,
        size_t max_results = 16) noexcept {
        if (!stops_ptr || count == 0) {
            return {};
        }
        return find_candidate_stops(std::span<const Stop>(stops_ptr, count), lat, lon, max_radius_meters, required_flags, max_results);
    }

    // Static fallback candidate stop discovery (Euclidean distance)
    [[nodiscard]] static inline std::vector<CandidateStop> find_candidate_stops(
        std::span<const Stop> stops,
        float lat,
        float lon,
        float max_radius_meters = DEFAULT_MAX_RADIUS_METERS,
        uint16_t required_flags = 0,
        size_t max_results = 16) noexcept {
        std::vector<CandidateStop> candidates;
        if (stops.empty() || max_results == 0) {
            return candidates;
        }

        float radius = (max_radius_meters > 0.0f) ? max_radius_meters : DEFAULT_MAX_RADIUS_METERS;
        candidates.reserve(std::min(max_results * 2, stops.size()));

        for (uint32_t stop_id = 0; stop_id < static_cast<uint32_t>(stops.size()); ++stop_id) {
            const auto& s = stops[stop_id];
            
            // Quick bounding box check before sqrt
            float lat_diff_m = std::abs(s.latitude - lat) * METERS_PER_DEGREE_LAT;
            if (lat_diff_m > radius) {
                continue;
            }

            float dist = calculate_distance_meters(lat, lon, s.latitude, s.longitude);
            if (dist <= radius) {
                uint32_t walk_duration = calculate_walk_duration_sec(dist, DEFAULT_WALK_SPEED_MPS);
                candidates.emplace_back(stop_id, dist, walk_duration, s.latitude, s.longitude, required_flags);
            }
        }

        std::sort(candidates.begin(), candidates.end(), [](const CandidateStop& a, const CandidateStop& b) {
            return a.distance_meters < b.distance_meters;
        });

        if (candidates.size() > max_results) {
            candidates.resize(max_results);
        }

        return candidates;
    }
};
