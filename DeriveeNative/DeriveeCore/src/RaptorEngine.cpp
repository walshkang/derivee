#include "RaptorEngine.hpp"
#include <cstring>
#include <algorithm>
#include <limits>
#include <cmath>

RaptorEngine::RaptorEngine() = default;

RaptorEngine::~RaptorEngine() = default;

RaptorEngine::RaptorEngine(RaptorEngine&& other) noexcept
    : timetable_blob_ptr_(other.timetable_blob_ptr_),
      timetable_blob_size_(other.timetable_blob_size_),
      is_loaded_(other.is_loaded_),
      stops_(other.stops_),
      routes_(other.routes_),
      trips_(other.trips_),
      stop_times_(other.stop_times_),
      transfers_(other.transfers_),
      stop_routes_(other.stop_routes_),
      route_stops_(other.route_stops_),
      stochastic_weights_(other.stochastic_weights_),
      ultra_store_(std::move(other.ultra_store_)),
      realtime_delays_(std::move(other.realtime_delays_)),
      stop_active_bitmask_(std::move(other.stop_active_bitmask_)),
      disrupted_segments_(std::move(other.disrupted_segments_)) {
    other.timetable_blob_ptr_ = nullptr;
    other.timetable_blob_size_ = 0;
    other.is_loaded_ = false;
    other.stops_ = {};
    other.routes_ = {};
    other.trips_ = {};
    other.stop_times_ = {};
    other.transfers_ = {};
    other.stop_routes_ = {};
    other.route_stops_ = {};
    other.stochastic_weights_ = {};
}

RaptorEngine& RaptorEngine::operator=(RaptorEngine&& other) noexcept {
    if (this != &other) {
        timetable_blob_ptr_ = other.timetable_blob_ptr_;
        timetable_blob_size_ = other.timetable_blob_size_;
        is_loaded_ = other.is_loaded_;
        stops_ = other.stops_;
        routes_ = other.routes_;
        trips_ = other.trips_;
        stop_times_ = other.stop_times_;
        transfers_ = other.transfers_;
        stop_routes_ = other.stop_routes_;
        route_stops_ = other.route_stops_;
        stochastic_weights_ = other.stochastic_weights_;
        ultra_store_ = std::move(other.ultra_store_);
        realtime_delays_ = std::move(other.realtime_delays_);
        stop_active_bitmask_ = std::move(other.stop_active_bitmask_);
        disrupted_segments_ = std::move(other.disrupted_segments_);

        other.timetable_blob_ptr_ = nullptr;
        other.timetable_blob_size_ = 0;
        other.is_loaded_ = false;
        other.stops_ = {};
        other.routes_ = {};
        other.trips_ = {};
        other.stop_times_ = {};
        other.transfers_ = {};
        other.stop_routes_ = {};
        other.route_stops_ = {};
        other.stochastic_weights_ = {};
    }
    return *this;
}

bool RaptorEngine::load_timetable_blob(const uint8_t* buffer_ptr, size_t length_bytes) noexcept {
    if (!buffer_ptr || length_bytes < sizeof(observer::format::MasterHeader)) {
        is_loaded_ = false;
        return false;
    }

    try {
        observer::engine::BinaryPayloadView view(
            buffer_ptr, 
            length_bytes, 
            observer::format::MAGIC_TIMETABLE, 
            1 // Schema version 1
        );

        if (view.header()->num_sections < 7) {
            is_loaded_ = false;
            return false;
        }

        stops_ = view.get_section_span<Stop>(0);
        routes_ = view.get_section_span<Route>(1);
        trips_ = view.get_section_span<Trip>(2);
        stop_times_ = view.get_section_span<StopTime>(3);
        transfers_ = view.get_section_span<Transfer>(4);
        stop_routes_ = view.get_section_span<uint32_t>(5);
        route_stops_ = view.get_section_span<uint32_t>(6);

        if (view.header()->num_sections >= 8) {
            stochastic_weights_ = view.get_section_span<StochasticWeight>(7);
        } else {
            stochastic_weights_ = {};
        }

        // Initialize Dynamic Disruption Bitmask (all active by default)
        size_t bitmask_size = (stops_.size() + 7) / 8;
        stop_active_bitmask_.assign(bitmask_size, 0xFF);
        disrupted_segments_.clear();

        timetable_blob_ptr_ = buffer_ptr;
        timetable_blob_size_ = length_bytes;
        is_loaded_ = true;
        return true;
    } catch (...) {
        timetable_blob_ptr_ = nullptr;
        timetable_blob_size_ = 0;
        is_loaded_ = false;
        stops_ = {};
        routes_ = {};
        trips_ = {};
        stop_times_ = {};
        transfers_ = {};
        stop_routes_ = {};
        route_stops_ = {};
        stochastic_weights_ = {};
        stop_active_bitmask_.clear();
        disrupted_segments_.clear();
        return false;
    }
}

bool RaptorEngine::load_ultra_blob(const uint8_t* buffer_ptr, size_t length_bytes) noexcept {
    return ultra_store_.load_ultra_blob(buffer_ptr, length_bytes);
}

void RaptorEngine::update_realtime_delay(uint32_t trip_id, int32_t delay_seconds) noexcept {
    realtime_delays_[trip_id] = delay_seconds;
}

void RaptorEngine::clear_realtime_delays() noexcept {
    realtime_delays_.clear();
}

int32_t RaptorEngine::get_realtime_delay(uint32_t trip_id) const noexcept {
    auto it = realtime_delays_.find(trip_id);
    if (it != realtime_delays_.end()) {
        return it->second;
    }
    return 0;
}

void RaptorEngine::set_stop_disrupted(uint32_t stop_id, bool disrupted) noexcept {
    if (stop_id >= stops_.size()) return;
    size_t byte_idx = stop_id / 8;
    uint8_t bit_mask = static_cast<uint8_t>(1 << (stop_id % 8));
    if (byte_idx < stop_active_bitmask_.size()) {
        if (disrupted) {
            stop_active_bitmask_[byte_idx] &= ~bit_mask;
        } else {
            stop_active_bitmask_[byte_idx] |= bit_mask;
        }
    }
}

bool RaptorEngine::is_stop_active(uint32_t stop_id) const noexcept {
    if (stop_id >= stops_.size()) return false;
    size_t byte_idx = stop_id / 8;
    if (byte_idx >= stop_active_bitmask_.size()) return true;
    uint8_t bit_mask = static_cast<uint8_t>(1 << (stop_id % 8));
    return (stop_active_bitmask_[byte_idx] & bit_mask) != 0;
}

void RaptorEngine::set_route_segment_disrupted(uint32_t route_id, uint32_t from_stop, uint32_t to_stop, bool disrupted) noexcept {
    uint64_t key = (static_cast<uint64_t>(route_id) << 32) |
                   (static_cast<uint64_t>(from_stop & 0xFFFF) << 16) |
                   static_cast<uint64_t>(to_stop & 0xFFFF);
    if (disrupted) {
        disrupted_segments_.insert(key);
    } else {
        disrupted_segments_.erase(key);
    }
}

bool RaptorEngine::is_route_segment_active(uint32_t route_id, uint32_t from_stop, uint32_t to_stop) const noexcept {
    uint64_t key = (static_cast<uint64_t>(route_id) << 32) |
                   (static_cast<uint64_t>(from_stop & 0xFFFF) << 16) |
                   static_cast<uint64_t>(to_stop & 0xFFFF);
    return disrupted_segments_.find(key) == disrupted_segments_.end();
}

void RaptorEngine::clear_disruptions() noexcept {
    std::fill(stop_active_bitmask_.begin(), stop_active_bitmask_.end(), 0xFF);
    disrupted_segments_.clear();
}

std::span<const Transfer> RaptorEngine::get_outgoing_transfers(uint32_t stop_id) const noexcept {
    if (!is_loaded_ || stop_id >= stops_.size()) {
        return {};
    }
    const auto& s = stops_[stop_id];
    if (s.transfers_offset + s.transfer_count > transfers_.size()) {
        return {};
    }
    return transfers_.subspan(s.transfers_offset, s.transfer_count);
}

void RaptorEngine::relax_intra_transfers(
    uint32_t from_stop_id,
    uint32_t current_arrival_sec,
    uint16_t query_flags,
    std::span<uint32_t> tau_k,
    std::span<uint32_t> best_tau,
    std::span<ParentPointer> parents,
    std::vector<uint32_t>& marked_stops_next
) const noexcept {
    if (from_stop_id >= stops_.size()) return;
    const auto& s = stops_[from_stop_id];
    uint32_t start_off = s.transfers_offset;
    uint32_t count = s.transfer_count;

    for (uint32_t i = start_off; i < start_off + count && i < transfers_.size(); ++i) {
        const auto& tr = transfers_[i];
        uint32_t target_stop = tr.target_stop_id;

        if (!is_stop_active(target_stop)) continue;

        uint32_t tr_arrival = current_arrival_sec + tr.duration_sec;

        if (tr_arrival >= best_tau[target_stop] && tr_arrival >= tau_k[target_stop]) {
            continue;
        }

        if (tr_arrival < best_tau[target_stop]) {
            best_tau[target_stop] = tr_arrival;
        }
        if (tr_arrival < tau_k[target_stop]) {
            tau_k[target_stop] = tr_arrival;
            parents[target_stop] = ParentPointer(
                from_stop_id,
                TRIP_TRANSFER,
                current_arrival_sec,
                tr_arrival,
                ROUTE_TRANSFER,
                tr.distance_meters,
                true
            );
            marked_stops_next.push_back(target_stop);
        }
    }
}

std::vector<JourneySegment> RaptorEngine::compute_journey(const QueryParams& params) const noexcept {
    std::vector<JourneySegment> results;

    if (!is_loaded_ || stops_.empty()) {
        return results;
    }

    if (params.origin_stop_id == params.destination_stop_id) {
        return results;
    }

    uint32_t n_stops = static_cast<uint32_t>(stops_.size());
    if (params.origin_stop_id >= n_stops || params.destination_stop_id >= n_stops) {
        return results;
    }

    if (!is_stop_active(params.origin_stop_id) || !is_stop_active(params.destination_stop_id)) {
        return results;
    }

    uint32_t rounds_count = std::min<uint32_t>(params.max_transfers + 1, MAX_ROUNDS);

    // Multi-round state matrices
    // tau[k][p]: arrival time at stop p in round k
    std::vector<std::vector<uint32_t>> tau(rounds_count + 1, std::vector<uint32_t>(n_stops, INF_TIME));
    // best_tau[p]: overall best known arrival time at stop p across any round <= k
    std::vector<uint32_t> best_tau(n_stops, INF_TIME);
    // parents[k][p]: parent pointer used to reach stop p in round k
    std::vector<std::vector<ParentPointer>> parents(rounds_count + 1, std::vector<ParentPointer>(n_stops));

    std::vector<uint32_t> marked_stops;
    std::vector<bool> is_marked(n_stops, false);

    // --- Round 0: Origin Initialization ---
    tau[0][params.origin_stop_id] = params.departure_timestamp;
    best_tau[params.origin_stop_id] = params.departure_timestamp;
    marked_stops.push_back(params.origin_stop_id);
    is_marked[params.origin_stop_id] = true;

    // Initial transfer relaxation from origin
    std::vector<uint32_t> initial_transfers;
    if (ultra_store_.is_loaded()) {
        ultra_store_.RelaxTransfers(
            params.origin_stop_id,
            params.departure_timestamp,
            params.flags,
            [this](uint32_t s) { return is_stop_active(s); },
            std::span<uint32_t>(tau[0]),
            std::span<uint32_t>(best_tau),
            std::span<ParentPointer>(parents[0]),
            initial_transfers
        );
    } else {
        relax_intra_transfers(
            params.origin_stop_id,
            params.departure_timestamp,
            params.flags,
            std::span<uint32_t>(tau[0]),
            std::span<uint32_t>(best_tau),
            std::span<ParentPointer>(parents[0]),
            initial_transfers
        );
    }

    for (uint32_t s : initial_transfers) {
        if (!is_marked[s]) {
            marked_stops.push_back(s);
            is_marked[s] = true;
        }
    }

    // --- Rounds 1 to K ---
    for (uint32_t k = 1; k <= rounds_count; ++k) {
        // Copy previous round's arrival labels
        std::copy(tau[k - 1].begin(), tau[k - 1].end(), tau[k].begin());

        if (marked_stops.empty()) {
            break; // Early round termination
        }

        // Step 1: Accumulate routes serving marked stops
        // Map: route_id -> earliest marked sequence index along that route
        std::unordered_map<uint32_t, uint32_t> routes_to_scan;

        for (uint32_t p : marked_stops) {
            if (p >= n_stops) continue;
            const auto& s = stops_[p];
            uint32_t start_r = s.routes_offset;
            uint32_t r_cnt = s.route_count;

            for (uint32_t ri = start_r; ri < start_r + r_cnt && ri < stop_routes_.size(); ++ri) {
                uint32_t r_id = stop_routes_[ri];
                if (r_id >= routes_.size()) continue;

                const auto& r = routes_[r_id];
                uint32_t start_s = r.route_stops_offset;
                uint32_t s_cnt = r.stop_count;

                // Find sequence index of stop p on route r_id
                for (uint32_t seq = 0; seq < s_cnt && (start_s + seq) < route_stops_.size(); ++seq) {
                    if (route_stops_[start_s + seq] == p) {
                        auto it = routes_to_scan.find(r_id);
                        if (it == routes_to_scan.end() || seq < it->second) {
                            routes_to_scan[r_id] = seq;
                        }
                        break;
                    }
                }
            }
        }

        marked_stops.clear();
        std::fill(is_marked.begin(), is_marked.end(), false);

        std::vector<uint32_t> route_marked_stops;

        // Step 2: Route Scanning
        for (const auto& [r_id, start_seq_idx] : routes_to_scan) {
            const auto& route = routes_[r_id];
            uint32_t start_stops = route.route_stops_offset;
            uint32_t s_cnt = route.stop_count;
            uint32_t start_trips = route.trips_offset;
            uint32_t t_cnt = route.trip_count;

            if (t_cnt == 0 || s_cnt == 0) continue;

            int32_t boarded_trip_idx = -1;
            uint32_t board_stop_id = 0;
            uint32_t board_time = 0;

            for (uint32_t seq = start_seq_idx; seq < s_cnt && (start_stops + seq) < route_stops_.size(); ++seq) {
                uint32_t stop_id = route_stops_[start_stops + seq];

                // 2a. Update arrival at stop_id if currently boarded on a trip
                if (boarded_trip_idx >= 0) {
                    uint32_t prev_stop_id = (seq > 0) ? route_stops_[start_stops + seq - 1] : board_stop_id;

                    bool is_disrupted = !is_stop_active(stop_id) ||
                                        !is_route_segment_active(r_id, board_stop_id, stop_id) ||
                                        !is_route_segment_active(r_id, prev_stop_id, stop_id);

                    if (!is_disrupted && !disrupted_segments_.empty()) {
                        for (uint64_t d_key : disrupted_segments_) {
                            if ((d_key >> 32) == r_id) {
                                uint32_t d_from = static_cast<uint32_t>((d_key >> 16) & 0xFFFF);
                                uint32_t d_to = static_cast<uint32_t>(d_key & 0xFFFF);
                                uint32_t d_from_seq = UINT32_MAX;
                                uint32_t d_to_seq = UINT32_MAX;
                                for (uint32_t s_idx = 0; s_idx < s_cnt && (start_stops + s_idx) < route_stops_.size(); ++s_idx) {
                                    uint32_t sid = route_stops_[start_stops + s_idx];
                                    if (sid == d_from && d_from_seq == UINT32_MAX) d_from_seq = s_idx;
                                    if (sid == d_to) d_to_seq = s_idx;
                                }
                                if (d_from_seq != UINT32_MAX && d_to_seq != UINT32_MAX && d_from_seq < d_to_seq) {
                                    if (seq > d_from_seq && seq <= d_to_seq) {
                                        is_disrupted = true;
                                        break;
                                    }
                                }
                            }
                        }
                    }

                    if (is_disrupted) {
                        boarded_trip_idx = -1; // Segment or station disrupted, trip dropped
                    } else {
                        const auto& curr_trip = trips_[boarded_trip_idx];
                        if (seq < curr_trip.stop_times_count) {
                            uint32_t st_idx = curr_trip.stop_times_offset + seq;
                            if (st_idx < stop_times_.size()) {
                                const auto& st = stop_times_[st_idx];
                                int32_t delay = get_realtime_delay(boarded_trip_idx);
                                uint32_t eff_arr = TransitTime::normalize_schedule_time(st.arrival_time_sec, delay);

                                // Destination pruning
                                if (eff_arr < best_tau[stop_id] || eff_arr < tau[k][stop_id]) {
                                    if (eff_arr < best_tau[stop_id]) {
                                        best_tau[stop_id] = eff_arr;
                                    }
                                    tau[k][stop_id] = eff_arr;
                                    parents[k][stop_id] = ParentPointer(
                                        board_stop_id,
                                        boarded_trip_idx,
                                        board_time,
                                        eff_arr,
                                        static_cast<uint16_t>(r_id),
                                        0,
                                        false
                                    );
                                    route_marked_stops.push_back(stop_id);
                                }
                            }
                        }
                    }
                }

                // 2b. Check if an earlier/eligible trip can be boarded at stop_id
                if (tau[k - 1][stop_id] < INF_TIME && is_stop_active(stop_id)) {
                    uint32_t arr_k_minus_1 = tau[k - 1][stop_id];

                    // Find earliest trip departing >= arr_k_minus_1
                    for (uint32_t ti = start_trips; ti < start_trips + t_cnt && ti < trips_.size(); ++ti) {
                        const auto& cand_trip = trips_[ti];
                        if (seq >= cand_trip.stop_times_count) continue;

                        uint32_t cand_st_idx = cand_trip.stop_times_offset + seq;
                        if (cand_st_idx >= stop_times_.size()) continue;

                        const auto& cand_st = stop_times_[cand_st_idx];
                        int32_t cand_delay = get_realtime_delay(ti);
                        uint32_t cand_eff_dep = TransitTime::normalize_schedule_time(cand_st.departure_time_sec, cand_delay);

                        if (cand_eff_dep >= arr_k_minus_1) {
                            if (boarded_trip_idx < 0) {
                                boarded_trip_idx = static_cast<int32_t>(ti);
                                board_stop_id = stop_id;
                                board_time = cand_eff_dep;
                            } else {
                                // Switch to candidate trip if it departs earlier
                                uint32_t curr_st_idx = trips_[boarded_trip_idx].stop_times_offset + seq;
                                uint32_t curr_dep = TransitTime::normalize_schedule_time(
                                    stop_times_[curr_st_idx].departure_time_sec,
                                    get_realtime_delay(boarded_trip_idx)
                                );
                                if (cand_eff_dep < curr_dep) {
                                    boarded_trip_idx = static_cast<int32_t>(ti);
                                    board_stop_id = stop_id;
                                    board_time = cand_eff_dep;
                                }
                            }
                            break; // Trips are chronologically ordered
                        }
                    }
                }
            }
        }

        // Step 3: Transfer Relaxation
        std::vector<uint32_t> transfer_marked_stops;
        for (uint32_t u : route_marked_stops) {
            if (!is_marked[u]) {
                marked_stops.push_back(u);
                is_marked[u] = true;
            }

            if (ultra_store_.is_loaded()) {
                ultra_store_.RelaxTransfers(
                    u,
                    tau[k][u],
                    params.flags,
                    [this](uint32_t s) { return is_stop_active(s); },
                    std::span<uint32_t>(tau[k]),
                    std::span<uint32_t>(best_tau),
                    std::span<ParentPointer>(parents[k]),
                    transfer_marked_stops
                );
            } else {
                relax_intra_transfers(
                    u,
                    tau[k][u],
                    params.flags,
                    std::span<uint32_t>(tau[k]),
                    std::span<uint32_t>(best_tau),
                    std::span<ParentPointer>(parents[k]),
                    transfer_marked_stops
                );
            }
        }

        for (uint32_t v : transfer_marked_stops) {
            if (!is_marked[v]) {
                marked_stops.push_back(v);
                is_marked[v] = true;
            }
        }
    }

    // --- Journey Reconstruction ---
    uint32_t dest = params.destination_stop_id;
    uint32_t best_dest_arr = best_tau[dest];
    if (best_dest_arr == INF_TIME) {
        return results; // Unreachable
    }

    // Find best round achieving best_dest_arr
    int32_t best_k = -1;
    for (uint32_t k = 0; k <= rounds_count; ++k) {
        if (tau[k][dest] == best_dest_arr) {
            best_k = static_cast<int32_t>(k);
            break;
        }
    }

    if (best_k < 0) {
        return results;
    }

    // Backtrack from destination to origin
    uint32_t curr_stop = dest;
    int32_t curr_round = best_k;

    while (curr_stop != params.origin_stop_id && curr_round >= 0) {
        const auto& ptr = parents[curr_round][curr_stop];
        if (ptr.from_stop_id == curr_stop && ptr.departure_time == 0 && ptr.arrival_time == 0) {
            if (curr_round > 0) {
                --curr_round;
                continue;
            }
            break;
        }

        results.emplace_back(
            ptr.from_stop_id,
            curr_stop,
            ptr.trip_id,
            ptr.departure_time,
            ptr.arrival_time,
            ptr.route_id,
            ptr.transfer_distance_m
        );

        curr_stop = ptr.from_stop_id;
        if (!ptr.is_transfer && curr_round > 0) {
            --curr_round;
        }
    }

    std::reverse(results.begin(), results.end());
    return results;
}

uint32_t RaptorEngine::calculate_layover_penalty(const std::vector<JourneySegment>& segments) const noexcept {
    if (segments.size() <= 1) {
        return 0;
    }

    uint32_t total_penalty = 0;
    constexpr uint32_t S_IDEAL = 180; // 180 seconds (3 min) ideal transfer buffer
    constexpr float ALPHA = 0.001f;

    for (size_t i = 0; i + 1 < segments.size(); ++i) {
        const auto& leg1 = segments[i];
        const auto& leg2 = segments[i + 1];

        // Connection slack = leg2 departure - leg1 arrival
        if (leg2.departure_time >= leg1.arrival_time) {
            uint32_t raw_slack = leg2.departure_time - leg1.arrival_time;
            if (raw_slack < S_IDEAL) {
                uint32_t deficit = S_IDEAL - raw_slack;
                uint32_t p = static_cast<uint32_t>(std::ceil(ALPHA * static_cast<float>(deficit * deficit)));
                total_penalty += std::min<uint32_t>(p, 10000);
            }
        } else {
            // Negative slack / missed connection: severely penalized
            total_penalty += 10000;
        }
    }

    return total_penalty;
}

uint32_t RaptorEngine::calculate_effort_duration(const std::vector<JourneySegment>& segments) const noexcept {
    uint32_t effort = 0;
    for (const auto& seg : segments) {
        if (seg.is_transfer_leg()) {
            if (seg.arrival_time >= seg.departure_time) {
                effort += (seg.arrival_time - seg.departure_time);
            } else if (seg.transfer_distance_m > 0) {
                effort += static_cast<uint32_t>(seg.transfer_distance_m / 1.3f);
            }
        }
    }
    return effort;
}

uint32_t RaptorEngine::calculate_probabilistic_wait_time(uint32_t headway_sec, uint32_t variance_sec_sq) noexcept {
    if (headway_sec == 0) return 0;
    // Osuna-Newell formula: E[wait] = h / 2 + sigma^2 / (2 * h)
    double h = static_cast<double>(headway_sec);
    double var = static_cast<double>(variance_sec_sq);
    double e_wait = (h / 2.0) + (var / (2.0 * h));
    return static_cast<uint32_t>(std::ceil(e_wait));
}

uint32_t RaptorEngine::calculate_variance_disutility(
    const std::vector<JourneySegment>& segments,
    uint32_t departure_time_sec,
    uint32_t base_time_sec,
    uint32_t horizon_sec
) const noexcept {
    uint32_t total_disutility = 0;
    bool is_beyond_horizon = (departure_time_sec > base_time_sec + horizon_sec);

    if (!stochastic_weights_.empty()) {
        uint32_t hour = (departure_time_sec / 3600) % 24;
        uint32_t day_of_week = (departure_time_sec / 86400) % 7;
        uint32_t slot_base = (day_of_week * 24 + hour);

        for (const auto& seg : segments) {
            if (!seg.is_transfer_leg() && seg.board_stop_id < stops_.size()) {
                size_t weight_idx = (slot_base * stops_.size() + seg.board_stop_id) % stochastic_weights_.size();
                const auto& sw = stochastic_weights_[weight_idx];
                total_disutility += sw.variance_penalty;

                if (is_beyond_horizon) {
                    total_disutility += (sw.expected_wait_sec / 10);
                }
            }
        }
    } else {
        // Fallback default variance penalty when stochastic weights table is not bundled
        for (const auto& seg : segments) {
            if (!seg.is_transfer_leg()) {
                total_disutility += is_beyond_horizon ? 25 : 5;
            }
        }
    }

    return total_disutility;
}

std::vector<uint32_t> RaptorEngine::extract_range_departures(
    uint32_t origin_stop_id,
    uint32_t start_time,
    uint32_t end_time,
    uint32_t sampling_step
) const noexcept {
    std::vector<uint32_t> departures;
    std::unordered_set<uint32_t> seen;

    if (!is_loaded_ || origin_stop_id >= stops_.size()) {
        return departures;
    }

    // Direct route departures from origin stop
    const auto& s = stops_[origin_stop_id];
    for (uint32_t ri = s.routes_offset; ri < s.routes_offset + s.route_count && ri < stop_routes_.size(); ++ri) {
        uint32_t r_id = stop_routes_[ri];
        if (r_id >= routes_.size()) continue;

        const auto& route = routes_[r_id];
        uint32_t origin_seq = UINT32_MAX;
        for (uint32_t seq = 0; seq < route.stop_count && (route.route_stops_offset + seq) < route_stops_.size(); ++seq) {
            if (route_stops_[route.route_stops_offset + seq] == origin_stop_id) {
                origin_seq = seq;
                break;
            }
        }

        if (origin_seq == UINT32_MAX) continue;

        for (uint32_t ti = route.trips_offset; ti < route.trips_offset + route.trip_count && ti < trips_.size(); ++ti) {
            const auto& tr = trips_[ti];
            if (origin_seq < tr.stop_times_count) {
                uint32_t st_idx = tr.stop_times_offset + origin_seq;
                if (st_idx < stop_times_.size()) {
                    uint32_t dep = TransitTime::normalize_schedule_time(
                        stop_times_[st_idx].departure_time_sec,
                        get_realtime_delay(ti)
                    );
                    if (dep >= start_time && dep <= end_time) {
                        if (seen.insert(dep).second) {
                            departures.push_back(dep);
                        }
                    }
                }
            }
        }
    }

    // Also include initial transfer targets departures
    auto transfers = get_outgoing_transfers(origin_stop_id);
    for (const auto& tr : transfers) {
        uint32_t target_s = tr.target_stop_id;
        if (target_s >= stops_.size()) continue;
        const auto& ts = stops_[target_s];
        for (uint32_t ri = ts.routes_offset; ri < ts.routes_offset + ts.route_count && ri < stop_routes_.size(); ++ri) {
            uint32_t r_id = stop_routes_[ri];
            if (r_id >= routes_.size()) continue;
            const auto& route = routes_[r_id];
            uint32_t target_seq = UINT32_MAX;
            for (uint32_t seq = 0; seq < route.stop_count && (route.route_stops_offset + seq) < route_stops_.size(); ++seq) {
                if (route_stops_[route.route_stops_offset + seq] == target_s) {
                    target_seq = seq;
                    break;
                }
            }
            if (target_seq == UINT32_MAX) continue;

            for (uint32_t ti = route.trips_offset; ti < route.trips_offset + route.trip_count && ti < trips_.size(); ++ti) {
                const auto& trip = trips_[ti];
                if (target_seq < trip.stop_times_count) {
                    uint32_t st_idx = trip.stop_times_offset + target_seq;
                    if (st_idx < stop_times_.size()) {
                        uint32_t target_dep = TransitTime::normalize_schedule_time(
                            stop_times_[st_idx].departure_time_sec,
                            get_realtime_delay(ti)
                        );
                        if (target_dep >= tr.duration_sec) {
                            uint32_t origin_dep = target_dep - tr.duration_sec;
                            if (origin_dep >= start_time && origin_dep <= end_time) {
                                if (seen.insert(origin_dep).second) {
                                    departures.push_back(origin_dep);
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // Fallback: if no discrete timetable departures were identified, sample window with step
    if (departures.empty()) {
        uint32_t step = (sampling_step > 0) ? sampling_step : 60;
        for (uint32_t t = start_time; t <= end_time; t += step) {
            departures.push_back(t);
        }
    } else {
        // Ensure boundary start_time is present
        if (seen.insert(start_time).second) {
            departures.push_back(start_time);
        }
    }

    // Sort descending for Range-RAPTOR backward sweep: latest departure first
    std::sort(departures.begin(), departures.end(), std::greater<uint32_t>());
    return departures;
}

ParetoSet RaptorEngine::compute_range_journeys(const RangeQueryParams& params) const noexcept {
    ParetoSet pareto_set;

    if (!is_loaded_ || stops_.empty()) {
        return pareto_set;
    }

    if (params.origin_stop_id == params.destination_stop_id) {
        return pareto_set;
    }

    uint32_t n_stops = static_cast<uint32_t>(stops_.size());
    if (params.origin_stop_id >= n_stops || params.destination_stop_id >= n_stops) {
        return pareto_set;
    }

    if (!is_stop_active(params.origin_stop_id) || !is_stop_active(params.destination_stop_id)) {
        return pareto_set;
    }

    uint32_t start_time = params.departure_start_timestamp;
    uint32_t end_time = std::max(params.departure_end_timestamp, start_time);

    // Extract discrete departures within [start_time, end_time], sorted descending
    std::vector<uint32_t> departure_times = extract_range_departures(
        params.origin_stop_id,
        start_time,
        end_time,
        params.sampling_step_sec
    );

    // Range-RAPTOR backward sweep loop
    for (uint32_t dep_time : departure_times) {
        QueryParams single_params(
            params.origin_stop_id,
            params.destination_stop_id,
            dep_time,
            params.max_transfers,
            params.flags
        );

        auto segments = compute_journey(single_params);
        if (segments.empty()) {
            continue;
        }

        uint32_t arrival_time = segments.back().arrival_time;

        // Count vehicle transfers: number of transit segments minus 1
        uint16_t transfers_count = 0;
        uint16_t transit_legs = 0;
        for (const auto& seg : segments) {
            if (!seg.is_transfer_leg()) {
                transit_legs++;
            }
        }
        if (transit_legs > 1) {
            transfers_count = transit_legs - 1;
        }

        uint32_t effort_dur = calculate_effort_duration(segments);
        uint32_t layover_pen = calculate_layover_penalty(segments);
        uint32_t var_dis = calculate_variance_disutility(
            segments,
            dep_time,
            start_time,
            params.stochastic_horizon_sec
        );

        ParetoCost cost(
            arrival_time,
            transfers_count,
            effort_dur,
            layover_pen,
            var_dis
        );

        ParetoJourney journey(cost, dep_time, std::move(segments));
        pareto_set.insert(journey);
    }

    return pareto_set;
}

