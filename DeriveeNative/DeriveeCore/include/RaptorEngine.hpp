#pragma once

#include "TimetableStructs.hpp"
#include "ObserverFormat.hpp"
#include "BinaryPayloadView.hpp"
#include "TransitTime.hpp"
#include "ULTRADataStore.hpp"
#include "BoundedAStarRouter.hpp"
#include <vector>
#include <unordered_map>
#include <unordered_set>
#include <cstdint>
#include <memory>
#include <span>

class RaptorEngine {
public:
    static constexpr uint32_t MAX_ROUNDS = 8;
    static constexpr uint32_t INF_TIME   = 0xFFFFFFFF;

private:
    const uint8_t* timetable_blob_ptr_ = nullptr;
    size_t timetable_blob_size_ = 0;
    bool is_loaded_ = false;

    // Timetable typed section spans
    std::span<const Stop> stops_{};
    std::span<const Route> routes_{};
    std::span<const Trip> trips_{};
    std::span<const StopTime> stop_times_{};
    std::span<const Transfer> transfers_{};
    std::span<const uint32_t> stop_routes_{};
    std::span<const uint32_t> route_stops_{};
    std::span<const StochasticWeight> stochastic_weights_{};

    // External ULTRA CSR Transfer Data Store
    ULTRADataStore ultra_store_{};

    // External Bounded Walk Router
    BoundedAStarRouter walk_router_{};

    // Real-time GTFS-RT delays: trip_id -> delay in seconds
    std::unordered_map<uint32_t, int32_t> realtime_delays_;

    // Dynamic Disruption Bitmask: 1 bit per stop_id (true = active, false = disrupted)
    std::vector<uint8_t> stop_active_bitmask_;

    // Disrupted route segments: packed 64-bit key: (route_id << 32) | (from_stop << 16) | to_stop
    std::unordered_set<uint64_t> disrupted_segments_;

    // Helper: Relax intra-timetable transfers when ULTRA CSR is not loaded
    void relax_intra_transfers(
        uint32_t from_stop_id,
        uint32_t current_arrival_sec,
        uint16_t query_flags,
        std::span<uint32_t> tau_k,
        std::span<uint32_t> best_tau,
        std::span<ParentPointer> parents,
        std::vector<uint32_t>& marked_stops_next
    ) const noexcept;

public:
    RaptorEngine();
    ~RaptorEngine();

    // Disable copy constructors to prevent unintended engine duplicates
    RaptorEngine(const RaptorEngine&) = delete;
    RaptorEngine& operator=(const RaptorEngine&) = delete;

    // Enable move semantics
    RaptorEngine(RaptorEngine&& other) noexcept;
    RaptorEngine& operator=(RaptorEngine&& other) noexcept;

    // Load binary timetable blob directly from memory-mapped disk buffer
    bool load_timetable_blob(const uint8_t* buffer_ptr, size_t length_bytes) noexcept;

    // Load binary ULTRA transfer shortcuts blob (.csr)
    bool load_ultra_blob(const uint8_t* buffer_ptr, size_t length_bytes) noexcept;

    // Load binary walk graph blob (walk_graph.bin)
    bool load_walk_graph_blob(const uint8_t* buffer_ptr, size_t length_bytes) noexcept;

    // Apply real-time delay updates to dynamic trip arrays
    void update_realtime_delay(uint32_t trip_id, int32_t delay_seconds) noexcept;
    void clear_realtime_delays() noexcept;

    // Query real-time delay for a trip
    [[nodiscard]] int32_t get_realtime_delay(uint32_t trip_id) const noexcept;

    // Dynamic Disruption Bitmask methods (O(1) checks)
    void set_stop_disrupted(uint32_t stop_id, bool disrupted) noexcept;
    [[nodiscard]] bool is_stop_active(uint32_t stop_id) const noexcept;

    void set_route_segment_disrupted(uint32_t route_id, uint32_t from_stop, uint32_t to_stop, bool disrupted) noexcept;
    [[nodiscard]] bool is_route_segment_active(uint32_t route_id, uint32_t from_stop, uint32_t to_stop) const noexcept;

    void clear_disruptions() noexcept;

    // Execute multi-criteria single-query RAPTOR search
    [[nodiscard]] std::vector<JourneySegment> compute_journey(
        const QueryParams& params) const noexcept;

    // Execute Range-RAPTOR continuous departure window sweep returning ParetoSet
    [[nodiscard]] ParetoSet compute_range_journeys(
        const RangeQueryParams& params) const noexcept;

    // Helpers for Pareto metrics and stochastic costs
    [[nodiscard]] uint32_t calculate_layover_penalty(
        const std::vector<JourneySegment>& segments) const noexcept;

    [[nodiscard]] uint32_t calculate_effort_duration(
        const std::vector<JourneySegment>& segments) const noexcept;

    [[nodiscard]] uint32_t calculate_variance_disutility(
        const std::vector<JourneySegment>& segments,
        uint32_t departure_time_sec,
        uint32_t base_time_sec,
        uint32_t horizon_sec) const noexcept;

    [[nodiscard]] static uint32_t calculate_probabilistic_wait_time(
        uint32_t headway_sec,
        uint32_t variance_sec_sq) noexcept;

    [[nodiscard]] std::vector<uint32_t> extract_range_departures(
        uint32_t origin_stop_id,
        uint32_t start_time,
        uint32_t end_time,
        uint32_t sampling_step) const noexcept;

    // Direct span access to outgoing transfers
    [[nodiscard]] std::span<const Transfer> get_outgoing_transfers(
        uint32_t stop_id) const noexcept;

    // Stop and spatial accessors
    [[nodiscard]] std::span<const Stop> get_stops() const noexcept { return stops_; }
    [[nodiscard]] Stop get_stop(uint32_t stop_id) const noexcept;
    [[nodiscard]] std::vector<CandidateStop> find_candidate_stops(
        float lat,
        float lon,
        float max_radius_meters = BoundedAStarRouter::DEFAULT_MAX_RADIUS_METERS,
        uint16_t required_flags = 0,
        size_t max_results = 16) const noexcept;

    // State inspections
    [[nodiscard]] bool is_loaded() const noexcept { return is_loaded_; }
    [[nodiscard]] bool is_ultra_loaded() const noexcept { return ultra_store_.is_loaded(); }
    [[nodiscard]] bool is_walk_graph_loaded() const noexcept;
    [[nodiscard]] size_t walk_nodes_count() const noexcept;
    [[nodiscard]] size_t walk_edges_count() const noexcept;
    [[nodiscard]] DirectWalkResult compute_direct_walk(
        float lat1, float lon1, float lat2, float lon2,
        float max_distance_meters = 2000.0f, uint16_t flags = 0) const noexcept;
    [[nodiscard]] size_t registered_delays_count() const noexcept { return realtime_delays_.size(); }
    [[nodiscard]] size_t stops_count() const noexcept { return stops_.size(); }
    [[nodiscard]] size_t routes_count() const noexcept { return routes_.size(); }
    [[nodiscard]] size_t trips_count() const noexcept { return trips_.size(); }
    [[nodiscard]] size_t stop_times_count() const noexcept { return stop_times_.size(); }
    [[nodiscard]] size_t transfers_count() const noexcept { return transfers_.size(); }
};

