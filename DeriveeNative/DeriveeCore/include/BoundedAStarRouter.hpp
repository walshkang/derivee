#pragma once

#include "TimetableStructs.hpp"
#include "ObserverFormat.hpp"
#include "BinaryPayloadView.hpp"
#include <span>
#include <vector>
#include <cstdint>
#include <cmath>
#include <algorithm>

#pragma pack(push, 1)

// CandidateStop: Represents a transit stop reachable via walking access from query coordinates (22 Bytes)
struct CandidateStop {
    uint32_t stop_id;
    float distance_meters;
    uint32_t walk_duration_sec;
    float latitude;
    float longitude;
    uint16_t flags;

    constexpr CandidateStop() noexcept
        : stop_id(0), distance_meters(0.0f), walk_duration_sec(0),
          latitude(0.0f), longitude(0.0f), flags(0) {}

    constexpr CandidateStop(uint32_t id, float dist, uint32_t duration,
                            float lat, float lon, uint16_t f = 0) noexcept
        : stop_id(id), distance_meters(dist), walk_duration_sec(duration),
          latitude(lat), longitude(lon), flags(f) {}
};
static_assert(sizeof(CandidateStop) == 22, "CandidateStop layout must be exactly 22 bytes");

#pragma pack(pop)

class BoundedAStarRouter {
public:
    static constexpr float DEFAULT_WALK_SPEED_MPS = 1.3f; // ~4.68 km/h (80 m/min)
    static constexpr float DEFAULT_MAX_RADIUS_METERS = 1000.0f; // 1,000m search envelope
    static constexpr float METERS_PER_DEGREE_LAT = 111139.0f;

    // Sub-millisecond flat-Earth geodesic distance approximation
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

    // Find candidate boarding/alighting stops within radius around (lat, lon)
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

    // Find candidate boarding/alighting stops within radius around (lat, lon)
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

        // Sort by distance ascending
        std::sort(candidates.begin(), candidates.end(), [](const CandidateStop& a, const CandidateStop& b) {
            return a.distance_meters < b.distance_meters;
        });

        if (candidates.size() > max_results) {
            candidates.resize(max_results);
        }

        return candidates;
    }
};
