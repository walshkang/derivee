#include "BoundedAStarRouter.hpp"
#include <climits>
#include <cmath>
#include <algorithm>
#include <cstring>

// MARK: - WalkGraphStore

bool WalkGraphStore::load_blob(const uint8_t* buffer_ptr, size_t length_bytes) noexcept {
    reset();
    if (!buffer_ptr || length_bytes < sizeof(observer::format::MasterHeader)) {
        return false;
    }

    // 64-byte alignment check
    if (reinterpret_cast<uintptr_t>(buffer_ptr) % 64 != 0) {
        return false;
    }

    const auto* hdr = reinterpret_cast<const observer::format::MasterHeader*>(buffer_ptr);
    if (hdr->magic != observer::format::MAGIC_WALK_GRAPH ||
        hdr->schema_version != 1 ||
        hdr->endian_marker != observer::format::ENDIAN_MARKER ||
        hdr->header_size != sizeof(observer::format::MasterHeader) ||
        hdr->file_size > length_bytes ||
        hdr->num_sections < 2) {
        return false;
    }

    // TOC Section 0: Nodes
    const auto& s0 = hdr->toc[0];
    if (s0.offset + s0.size_bytes > hdr->file_size ||
        s0.size_bytes < s0.item_count * sizeof(observer::format::WalkNode) ||
        s0.offset % alignof(observer::format::WalkNode) != 0) {
        return false;
    }

    // TOC Section 1: Edges
    const auto& s1 = hdr->toc[1];
    if (s1.offset + s1.size_bytes > hdr->file_size ||
        s1.size_bytes < s1.item_count * sizeof(observer::format::WalkEdge) ||
        s1.offset % alignof(observer::format::WalkEdge) != 0) {
        return false;
    }

    header_ = *hdr;
    nodes_ = std::span<const observer::format::WalkNode>(
        reinterpret_cast<const observer::format::WalkNode*>(buffer_ptr + s0.offset),
        static_cast<size_t>(s0.item_count)
    );
    edges_ = std::span<const observer::format::WalkEdge>(
        reinterpret_cast<const observer::format::WalkEdge*>(buffer_ptr + s1.offset),
        static_cast<size_t>(s1.item_count)
    );

    raw_blob_ptr_ = buffer_ptr;
    raw_blob_size_ = length_bytes;
    is_loaded_ = true;
    return true;
}

void WalkGraphStore::reset() noexcept {
    raw_blob_ptr_ = nullptr;
    raw_blob_size_ = 0;
    is_loaded_ = false;
    nodes_ = {};
    edges_ = {};
    header_ = {};
}

// MARK: - WalkSpatialGrid

void WalkSpatialGrid::build(std::span<const observer::format::WalkNode> nodes) {
    clear();
    nodes_ = nodes;
    if (nodes.empty()) return;

    min_gx_ = INT32_MAX;
    max_gx_ = INT32_MIN;
    min_gy_ = INT32_MAX;
    max_gy_ = INT32_MIN;

    // Pass 1: compute bounding box in grid space
    for (const auto& n : nodes) {
        int32_t gx = (n.lon_quantized >= 0) ? (n.lon_quantized / CELL_SIZE_Q) : ((n.lon_quantized - CELL_SIZE_Q + 1) / CELL_SIZE_Q);
        int32_t gy = (n.lat_quantized >= 0) ? (n.lat_quantized / CELL_SIZE_Q) : ((n.lat_quantized - CELL_SIZE_Q + 1) / CELL_SIZE_Q);
        if (gx < min_gx_) min_gx_ = gx;
        if (gx > max_gx_) max_gx_ = gx;
        if (gy < min_gy_) min_gy_ = gy;
        if (gy > max_gy_) max_gy_ = gy;
    }

    width_cells_ = std::max(1, max_gx_ - min_gx_ + 1);
    height_cells_ = std::max(1, max_gy_ - min_gy_ + 1);
    uint64_t total_cells_64 = static_cast<uint64_t>(width_cells_) * static_cast<uint64_t>(height_cells_);

    // Guard against coordinate outliers or astronomical dimensions
    if (total_cells_64 > 2000000ULL) {
        width_cells_ = 1;
        height_cells_ = 1;
        total_cells_64 = 1;
        min_gx_ = 0;
        max_gx_ = 0;
        min_gy_ = 0;
        max_gy_ = 0;
    }
    size_t total_cells = static_cast<size_t>(total_cells_64);

    cell_offsets_.assign(total_cells + 1, 0);
    node_indices_.resize(nodes.size());

    // Pass 2: Count entries per cell
    for (const auto& n : nodes) {
        int32_t gx = (n.lon_quantized >= 0) ? (n.lon_quantized / CELL_SIZE_Q) : ((n.lon_quantized - CELL_SIZE_Q + 1) / CELL_SIZE_Q);
        int32_t gy = (n.lat_quantized >= 0) ? (n.lat_quantized / CELL_SIZE_Q) : ((n.lat_quantized - CELL_SIZE_Q + 1) / CELL_SIZE_Q);
        if (gx >= min_gx_ && gx <= max_gx_ && gy >= min_gy_ && gy <= max_gy_) {
            uint32_t cell_idx = static_cast<uint32_t>((gy - min_gy_) * width_cells_ + (gx - min_gx_));
            cell_offsets_[cell_idx + 1]++;
        }
    }

    // Prefix sum to compute offsets
    for (size_t i = 0; i < total_cells; ++i) {
        cell_offsets_[i + 1] += cell_offsets_[i];
    }

    std::vector<uint32_t> current_pos = cell_offsets_;

    // Pass 3: Insert node indices
    for (uint32_t i = 0; i < static_cast<uint32_t>(nodes.size()); ++i) {
        const auto& n = nodes[i];
        int32_t gx = (n.lon_quantized >= 0) ? (n.lon_quantized / CELL_SIZE_Q) : ((n.lon_quantized - CELL_SIZE_Q + 1) / CELL_SIZE_Q);
        int32_t gy = (n.lat_quantized >= 0) ? (n.lat_quantized / CELL_SIZE_Q) : ((n.lat_quantized - CELL_SIZE_Q + 1) / CELL_SIZE_Q);
        if (gx >= min_gx_ && gx <= max_gx_ && gy >= min_gy_ && gy <= max_gy_) {
            uint32_t cell_idx = static_cast<uint32_t>((gy - min_gy_) * width_cells_ + (gx - min_gx_));
            node_indices_[current_pos[cell_idx]++] = i;
        }
    }
}

void WalkSpatialGrid::clear() noexcept {
    min_gx_ = 0;
    max_gx_ = 0;
    min_gy_ = 0;
    max_gy_ = 0;
    width_cells_ = 0;
    height_cells_ = 0;
    cell_offsets_.clear();
    node_indices_.clear();
    nodes_ = {};
}

uint32_t WalkSpatialGrid::find_nearest_node(
    int32_t lat_q, int32_t lon_q, float max_radius_m, uint32_t* out_dist_cm) const noexcept {
    if (node_indices_.empty() || nodes_.empty()) {
        return NIL_NODE;
    }

    uint32_t max_dist_cm = static_cast<uint32_t>(std::round(max_radius_m * 100.0f));
    int32_t search_radius_cells = static_cast<int32_t>(std::ceil(max_radius_m / 200.0f));
    search_radius_cells = std::max(1, std::min(search_radius_cells, 5));

    int32_t center_gx = (lon_q >= 0) ? (lon_q / CELL_SIZE_Q) : ((lon_q - CELL_SIZE_Q + 1) / CELL_SIZE_Q);
    int32_t center_gy = (lat_q >= 0) ? (lat_q / CELL_SIZE_Q) : ((lat_q - CELL_SIZE_Q + 1) / CELL_SIZE_Q);

    uint32_t best_node = NIL_NODE;
    uint32_t best_dist_cm = UINT32_MAX;

    for (int32_t dy = -search_radius_cells; dy <= search_radius_cells; ++dy) {
        int32_t gy = center_gy + dy;
        if (gy < min_gy_ || gy > max_gy_) continue;

        for (int32_t dx = -search_radius_cells; dx <= search_radius_cells; ++dx) {
            int32_t gx = center_gx + dx;
            if (gx < min_gx_ || gx > max_gx_) continue;

            uint32_t cell_idx = static_cast<uint32_t>((gy - min_gy_) * width_cells_ + (gx - min_gx_));
            uint32_t start_idx = cell_offsets_[cell_idx];
            uint32_t end_idx = cell_offsets_[cell_idx + 1];

            for (uint32_t i = start_idx; i < end_idx; ++i) {
                uint32_t node_idx = node_indices_[i];
                const auto& n = nodes_[node_idx];
                uint32_t dist_cm = calculate_distance_cm(lat_q, lon_q, n.lat_quantized, n.lon_quantized);
                if (dist_cm <= max_dist_cm && dist_cm < best_dist_cm) {
                    best_dist_cm = dist_cm;
                    best_node = node_idx;
                }
            }
        }
    }

    if (best_node != NIL_NODE && out_dist_cm) {
        *out_dist_cm = best_dist_cm;
    }
    return best_node;
}

// MARK: - BoundedAStarRouter

bool BoundedAStarRouter::load_walk_graph_blob(const uint8_t* buffer_ptr, size_t length_bytes) noexcept {
    if (!walk_store_.load_blob(buffer_ptr, length_bytes)) {
        return false;
    }

    spatial_grid_.build(walk_store_.nodes());
    node_states_.assign(walk_store_.node_count(), NodeState{ 0, 0 });
    current_gen_ = 1;
    pq_.reserve(4096);
    astar_pq_.reserve(4096);

    snap_stops_internal();
    return true;
}

void BoundedAStarRouter::bind_stops(std::span<const Stop> stops) noexcept {
    stops_ = stops;
    snap_stops_internal();
}

void BoundedAStarRouter::snap_stops_internal() {
    stop_to_walk_node_.clear();
    stop_snap_dist_cm_.clear();
    walk_node_stop_offsets_.clear();
    snapped_stops_.clear();

    if (!spatial_grid_.is_built() || stops_.empty()) {
        return;
    }

    const size_t num_stops = stops_.size();
    const size_t num_nodes = walk_store_.node_count();

    stop_to_walk_node_.assign(num_stops, WalkSpatialGrid::NIL_NODE);
    stop_snap_dist_cm_.assign(num_stops, 0);

    std::vector<uint32_t> stop_counts_per_node(num_nodes, 0);

    for (uint32_t s = 0; s < static_cast<uint32_t>(num_stops); ++s) {
        const auto& stop = stops_[s];
        int32_t lat_q = static_cast<int32_t>(std::round(static_cast<double>(stop.latitude) * 1e7));
        int32_t lon_q = static_cast<int32_t>(std::round(static_cast<double>(stop.longitude) * 1e7));

        uint32_t snap_dist_cm = 0;
        uint32_t nearest = spatial_grid_.find_nearest_node(lat_q, lon_q, 400.0f, &snap_dist_cm);
        if (nearest != WalkSpatialGrid::NIL_NODE) {
            stop_to_walk_node_[s] = nearest;
            stop_snap_dist_cm_[s] = static_cast<uint16_t>(std::min<uint32_t>(snap_dist_cm, UINT16_MAX));
            stop_counts_per_node[nearest]++;
        }
    }

    walk_node_stop_offsets_.assign(num_nodes + 1, 0);
    for (size_t i = 0; i < num_nodes; ++i) {
        walk_node_stop_offsets_[i + 1] = walk_node_stop_offsets_[i] + stop_counts_per_node[i];
    }

    snapped_stops_.resize(walk_node_stop_offsets_[num_nodes]);
    std::vector<uint32_t> current_pos = walk_node_stop_offsets_;

    for (uint32_t s = 0; s < static_cast<uint32_t>(num_stops); ++s) {
        uint32_t node = stop_to_walk_node_[s];
        if (node != WalkSpatialGrid::NIL_NODE) {
            snapped_stops_[current_pos[node]++] = s;
        }
    }
}

void BoundedAStarRouter::reset_dijkstra() const noexcept {
    current_gen_++;
    if (current_gen_ == 0) {
        std::memset(node_states_.data(), 0, node_states_.size() * sizeof(NodeState));
        current_gen_ = 1;
    }
}

std::vector<CandidateStop> BoundedAStarRouter::find_reachable_stops(
    float query_lat,
    float query_lon,
    float max_radius_meters,
    uint16_t required_flags,
    size_t max_results,
    const derivee::climate::MicroClimateConfig& microclimate) const noexcept {
    if (!walk_store_.is_loaded() || stops_.empty()) {
        return find_candidate_stops(stops_, query_lat, query_lon, max_radius_meters, required_flags, max_results);
    }

    int32_t lat_q = static_cast<int32_t>(std::round(static_cast<double>(query_lat) * 1e7));
    int32_t lon_q = static_cast<int32_t>(std::round(static_cast<double>(query_lon) * 1e7));

    uint32_t snap_dist_cm = 0;
    uint32_t start_node = spatial_grid_.find_nearest_node(lat_q, lon_q, 500.0f, &snap_dist_cm);
    if (start_node == WalkSpatialGrid::NIL_NODE) {
        return find_candidate_stops(stops_, query_lat, query_lon, max_radius_meters, required_flags, max_results);
    }

    uint32_t max_radius_cm = static_cast<uint32_t>(std::round(max_radius_meters * 100.0f));
    if (snap_dist_cm > max_radius_cm) {
        return {};
    }

    // Determine solar position for microclimate evaluation
    derivee::climate::SolarPosition sun;
    if (microclimate.has_custom_solar) {
        sun = derivee::climate::SolarPosition(
            microclimate.solar_altitude_rad,
            microclimate.solar_azimuth_rad,
            derivee::climate::MicroClimateEnergyEvaluator::PI * 0.5f - microclimate.solar_altitude_rad,
            microclimate.solar_altitude_rad > 0.0f
        );
    } else {
        uint32_t ts = 1751472000; // July 2, 2025 ~12:00 EDT default
        if (microclimate.mode == derivee::climate::ThermalComfortMode::WinterSunlit) {
            ts = 1736956800; // Jan 15, 2025 ~11:00 EST
        }
        sun = derivee::climate::MicroClimateEnergyEvaluator::calculate_solar_position(
            static_cast<double>(query_lat),
            static_cast<double>(query_lon),
            ts
        );
    }

    reset_dijkstra();

    set_node_state(start_node, snap_dist_cm, snap_dist_cm, snap_dist_cm / 2);
    pq_.clear();
    pq_.push_back({ start_node, snap_dist_cm });
    std::push_heap(pq_.begin(), pq_.end(), std::greater<HeapEntry>());

    std::vector<CandidateStop> results;
    results.reserve(max_results * 2);

    const auto nodes = walk_store_.nodes();
    const auto edges = walk_store_.edges();

    while (!pq_.empty()) {
        std::pop_heap(pq_.begin(), pq_.end(), std::greater<HeapEntry>());
        HeapEntry top = pq_.back();
        pq_.pop_back();

        uint32_t u = top.node_idx;
        uint32_t d_u = top.dist_cm;

        if (d_u > get_node_dist(u)) {
            continue;
        }

        if (d_u > max_radius_cm) {
            break; // Bounded search cutoff
        }

        // Check if node u has transit stops
        if (u < walk_node_stop_offsets_.size() - 1) {
            uint32_t start_stop_idx = walk_node_stop_offsets_[u];
            uint32_t end_stop_idx = walk_node_stop_offsets_[u + 1];

            for (uint32_t k = start_stop_idx; k < end_stop_idx; ++k) {
                uint32_t stop_id = snapped_stops_[k];
                uint32_t actual_cm = node_states_[u].actual_dist_cm + stop_snap_dist_cm_[stop_id];
                uint32_t shaded_cm = node_states_[u].shaded_dist_cm + (stop_snap_dist_cm_[stop_id] / 2);
                
                if (actual_cm <= max_radius_cm) {
                    float dist_m = static_cast<float>(actual_cm) * 0.01f;
                    uint32_t dur_sec = calculate_walk_duration_sec(dist_m, DEFAULT_WALK_SPEED_MPS);
                    float shade_pct = actual_cm > 0 ? (static_cast<float>(shaded_cm) / static_cast<float>(actual_cm)) * 100.0f : 0.0f;
                    float pet_c = derivee::climate::MicroClimateEnergyEvaluator::estimate_pet_celsius(
                        microclimate.ambient_temp_c,
                        microclimate.relative_humidity,
                        microclimate.wind_speed_mps,
                        shade_pct * 0.01f,
                        sun.altitude_rad
                    );
                    const auto& s = stops_[stop_id];
                    results.emplace_back(stop_id, dist_m, dur_sec, s.latitude, s.longitude, required_flags, shade_pct, pet_c);
                }
            }
        }

        // Relax outgoing edges from u
        const auto& node = nodes[u];
        uint32_t edge_start = node.first_edge_idx;
        uint32_t edge_end = edge_start + node.edge_count;

        const double lat_u = static_cast<double>(node.lat_quantized) * 1e-7;
        const double lon_u = static_cast<double>(node.lon_quantized) * 1e-7;

        for (uint32_t e = edge_start; e < edge_end && e < edges.size(); ++e) {
            const auto& edge = edges[e];
            uint32_t v = edge.target_node_idx;
            if (v >= nodes.size()) continue;

            // Accessibility filtering
            if ((required_flags & ROUTING_FLAG_WHEELCHAIR_ACCESSIBLE) != 0) {
                if (nodes[v].access_flags & WALK_FLAG_IS_STEPS) {
                    continue;
                }
            }

            const double lat_v = static_cast<double>(nodes[v].lat_quantized) * 1e-7;
            const double lon_v = static_cast<double>(nodes[v].lon_quantized) * 1e-7;

            const uint16_t edge_flags = nodes[u].access_flags | nodes[v].access_flags;
            const float shade = derivee::climate::MicroClimateEnergyEvaluator::calculate_edge_shade_factor(
                lat_u, lon_u, lat_v, lon_v, sun, edge_flags
            );
            const float weight_mult = derivee::climate::MicroClimateEnergyEvaluator::calculate_edge_weight_multiplier(
                shade, microclimate
            );

            const uint32_t edge_dist_cm = edge.distance_cm;
            const uint32_t weighted_edge_cm = static_cast<uint32_t>(std::round(static_cast<float>(edge_dist_cm) * weight_mult));
            const uint32_t new_weighted_dist = d_u + weighted_edge_cm;
            if (new_weighted_dist > max_radius_cm) {
                continue; // Prune search exceeding radius
            }

            if (new_weighted_dist < get_node_dist(v)) {
                const uint32_t new_actual = node_states_[u].actual_dist_cm + edge_dist_cm;
                const uint32_t new_shaded = node_states_[u].shaded_dist_cm + static_cast<uint32_t>(std::round(static_cast<float>(edge_dist_cm) * shade));
                set_node_state(v, new_weighted_dist, new_actual, new_shaded);
                pq_.push_back({ v, new_weighted_dist });
                std::push_heap(pq_.begin(), pq_.end(), std::greater<HeapEntry>());
            }
        }
    }

    // Sort by distance ascending
    std::sort(results.begin(), results.end(), [](const CandidateStop& a, const CandidateStop& b) {
        return a.distance_meters < b.distance_meters;
    });

    // Deduplicate by stop_id (preserving shortest distance)
    std::vector<CandidateStop> unique_results;
    unique_results.reserve(results.size());
    std::vector<bool> seen(stops_.size(), false);
    for (const auto& c : results) {
        if (!seen[c.stop_id]) {
            seen[c.stop_id] = true;
            unique_results.push_back(c);
            if (unique_results.size() >= max_results) break;
        }
    }

    return unique_results;
}

DirectWalkResult BoundedAStarRouter::compute_direct_walk(
    float lat1,
    float lon1,
    float lat2,
    float lon2,
    float max_distance_meters,
    uint16_t flags,
    const derivee::climate::MicroClimateConfig& microclimate) const noexcept {
    float straight_dist = calculate_distance_meters(lat1, lon1, lat2, lon2);

    // Determine solar position for microclimate evaluation
    derivee::climate::SolarPosition sun;
    if (microclimate.has_custom_solar) {
        sun = derivee::climate::SolarPosition(
            microclimate.solar_altitude_rad,
            microclimate.solar_azimuth_rad,
            derivee::climate::MicroClimateEnergyEvaluator::PI * 0.5f - microclimate.solar_altitude_rad,
            microclimate.solar_altitude_rad > 0.0f
        );
    } else {
        uint32_t ts = 1751472000; // July 2, 2025 ~12:00 EDT
        if (microclimate.mode == derivee::climate::ThermalComfortMode::WinterSunlit) {
            ts = 1736956800; // Jan 15, 2025 ~11:00 EST
        }
        sun = derivee::climate::MicroClimateEnergyEvaluator::calculate_solar_position(
            static_cast<double>(lat1),
            static_cast<double>(lon1),
            ts
        );
    }

    const float default_pet = derivee::climate::MicroClimateEnergyEvaluator::estimate_pet_celsius(
        microclimate.ambient_temp_c, microclimate.relative_humidity, microclimate.wind_speed_mps, 0.5f, sun.altitude_rad
    );

    if (!walk_store_.is_loaded() || !spatial_grid_.is_built()) {
        uint32_t dur = calculate_walk_duration_sec(straight_dist, DEFAULT_WALK_SPEED_MPS);
        return DirectWalkResult(straight_dist, dur, false, 50.0f, default_pet);
    }

    int32_t lat1_q = static_cast<int32_t>(std::round(static_cast<double>(lat1) * 1e7));
    int32_t lon1_q = static_cast<int32_t>(std::round(static_cast<double>(lon1) * 1e7));
    int32_t lat2_q = static_cast<int32_t>(std::round(static_cast<double>(lat2) * 1e7));
    int32_t lon2_q = static_cast<int32_t>(std::round(static_cast<double>(lon2) * 1e7));

    uint32_t snap1_cm = 0;
    uint32_t snap2_cm = 0;
    uint32_t start_node = spatial_grid_.find_nearest_node(lat1_q, lon1_q, 500.0f, &snap1_cm);
    uint32_t goal_node = spatial_grid_.find_nearest_node(lat2_q, lon2_q, 500.0f, &snap2_cm);

    if (start_node == WalkSpatialGrid::NIL_NODE || goal_node == WalkSpatialGrid::NIL_NODE) {
        uint32_t dur = calculate_walk_duration_sec(straight_dist, DEFAULT_WALK_SPEED_MPS);
        return DirectWalkResult(straight_dist, dur, false, 50.0f, default_pet);
    }

    if (start_node == goal_node) {
        float total_m = static_cast<float>(snap1_cm + snap2_cm) * 0.01f;
        uint32_t dur = calculate_walk_duration_sec(total_m, DEFAULT_WALK_SPEED_MPS);
        return DirectWalkResult(total_m, dur, true, 50.0f, default_pet);
    }

    uint32_t max_dist_cm = static_cast<uint32_t>(std::round(max_distance_meters * 100.0f));
    reset_dijkstra();

    const auto nodes = walk_store_.nodes();
    const auto edges = walk_store_.edges();
    const auto& goal_node_ref = nodes[goal_node];

    auto h_func = [&](uint32_t u) noexcept -> uint32_t {
        return WalkSpatialGrid::calculate_distance_cm(
            nodes[u].lat_quantized, nodes[u].lon_quantized,
            goal_node_ref.lat_quantized, goal_node_ref.lon_quantized
        );
    };

    uint32_t initial_h = h_func(start_node);
    set_node_state(start_node, snap1_cm, snap1_cm, snap1_cm / 2);

    astar_pq_.clear();
    astar_pq_.push_back({ start_node, snap1_cm + initial_h, snap1_cm });
    std::push_heap(astar_pq_.begin(), astar_pq_.end(), std::greater<AStarHeapEntry>());

    bool reached = false;

    while (!astar_pq_.empty()) {
        std::pop_heap(astar_pq_.begin(), astar_pq_.end(), std::greater<AStarHeapEntry>());
        AStarHeapEntry top = astar_pq_.back();
        astar_pq_.pop_back();

        uint32_t u = top.node_idx;
        uint32_t g_u = top.g_score;

        if (g_u > get_node_dist(u)) continue;

        if (u == goal_node) {
            reached = true;
            break;
        }

        if (top.f_score > max_dist_cm) {
            break;
        }

        const auto& node = nodes[u];
        uint32_t edge_start = node.first_edge_idx;
        uint32_t edge_end = edge_start + node.edge_count;

        const double lat_u = static_cast<double>(node.lat_quantized) * 1e-7;
        const double lon_u = static_cast<double>(node.lon_quantized) * 1e-7;

        for (uint32_t e = edge_start; e < edge_end && e < edges.size(); ++e) {
            const auto& edge = edges[e];
            uint32_t v = edge.target_node_idx;
            if (v >= nodes.size()) continue;

            if ((flags & ROUTING_FLAG_WHEELCHAIR_ACCESSIBLE) != 0) {
                if (nodes[v].access_flags & WALK_FLAG_IS_STEPS) continue;
            }

            const double lat_v = static_cast<double>(nodes[v].lat_quantized) * 1e-7;
            const double lon_v = static_cast<double>(nodes[v].lon_quantized) * 1e-7;

            const uint16_t edge_flags = nodes[u].access_flags | nodes[v].access_flags;
            const float shade = derivee::climate::MicroClimateEnergyEvaluator::calculate_edge_shade_factor(
                lat_u, lon_u, lat_v, lon_v, sun, edge_flags
            );
            const float weight_mult = derivee::climate::MicroClimateEnergyEvaluator::calculate_edge_weight_multiplier(
                shade, microclimate
            );

            const uint32_t edge_dist_cm = edge.distance_cm;
            const uint32_t weighted_edge_cm = static_cast<uint32_t>(std::round(static_cast<float>(edge_dist_cm) * weight_mult));
            const uint32_t new_g = g_u + weighted_edge_cm;
            if (new_g > max_dist_cm) continue;

            if (new_g < get_node_dist(v)) {
                const uint32_t new_actual = node_states_[u].actual_dist_cm + edge_dist_cm;
                const uint32_t new_shaded = node_states_[u].shaded_dist_cm + static_cast<uint32_t>(std::round(static_cast<float>(edge_dist_cm) * shade));
                set_node_state(v, new_g, new_actual, new_shaded);
                uint32_t f = new_g + h_func(v);
                astar_pq_.push_back({ v, f, new_g });
                std::push_heap(astar_pq_.begin(), astar_pq_.end(), std::greater<AStarHeapEntry>());
            }
        }
    }

    if (reached) {
        uint32_t total_actual_cm = node_states_[goal_node].actual_dist_cm + snap2_cm;
        uint32_t total_shaded_cm = node_states_[goal_node].shaded_dist_cm + (snap2_cm / 2);
        float total_m = static_cast<float>(total_actual_cm) * 0.01f;
        uint32_t dur = calculate_walk_duration_sec(total_m, DEFAULT_WALK_SPEED_MPS);
        float shade_pct = total_actual_cm > 0 ? (static_cast<float>(total_shaded_cm) / static_cast<float>(total_actual_cm)) * 100.0f : 0.0f;
        float pet_c = derivee::climate::MicroClimateEnergyEvaluator::estimate_pet_celsius(
            microclimate.ambient_temp_c,
            microclimate.relative_humidity,
            microclimate.wind_speed_mps,
            shade_pct * 0.01f,
            sun.altitude_rad
        );
        return DirectWalkResult(total_m, dur, true, shade_pct, pet_c);
    }

    uint32_t dur = calculate_walk_duration_sec(straight_dist, DEFAULT_WALK_SPEED_MPS);
    return DirectWalkResult(straight_dist, dur, false, 50.0f, default_pet);
}
