cat << 'INNER_EOF' >> DeriveeNative/DeriveeCore/src/RaptorEngine.cpp
#include <cmath>

static inline float haversine_m(float lat1, float lon1, float lat2, float lon2) {
    constexpr float R = 6371000.0f;
    float p1 = lat1 * M_PI / 180.0f;
    float p2 = lat2 * M_PI / 180.0f;
    float dp = (lat2 - lat1) * M_PI / 180.0f;
    float dl = (lon2 - lon1) * M_PI / 180.0f;
    float a = std::sin(dp / 2) * std::sin(dp / 2) + std::cos(p1) * std::cos(p2) * std::sin(dl / 2) * std::sin(dl / 2);
    float c = 2.0f * std::atan2(std::sqrt(a), std::sqrt(1.0f - a));
    return R * c;
}

void RaptorEngine::load_bike_docks(const BikeDock* docks, size_t count) noexcept {
    bike_docks_.assign(docks, docks + count);
    station_id_to_dock_idx_.clear();
    for (size_t i = 0; i < bike_docks_.size(); ++i) {
        station_id_to_dock_idx_[bike_docks_[i].station_id] = i;
    }

    constexpr float MAX_WALK_M = 400.0f;
    constexpr float WALK_SPEED = 1.34f;
    stop_to_docks_.assign(stops_.size(), std::vector<DockWalk>());
    dock_to_stops_.assign(bike_docks_.size(), std::vector<StopWalk>());

    for (size_t s = 0; s < stops_.size(); ++s) {
        for (size_t d = 0; d < bike_docks_.size(); ++d) {
            float dist = haversine_m(stops_[s].latitude, stops_[s].longitude, bike_docks_[d].latitude, bike_docks_[d].longitude);
            if (dist <= MAX_WALK_M) {
                uint16_t dur = static_cast<uint16_t>(dist / WALK_SPEED);
                stop_to_docks_[s].push_back({static_cast<uint32_t>(d), dur, static_cast<uint16_t>(dist)});
                dock_to_stops_[d].push_back({static_cast<uint32_t>(s), dur, static_cast<uint16_t>(dist)});
            }
        }
    }
}

void RaptorEngine::update_dock_availability(uint32_t station_id, uint16_t bikes, uint16_t ebikes, uint16_t docks) noexcept {
    auto it = station_id_to_dock_idx_.find(station_id);
    if (it != station_id_to_dock_idx_.end()) {
        auto& d = bike_docks_[it->second];
        d.num_bikes_available = bikes;
        d.num_ebikes_available = ebikes;
        d.num_docks_available = docks;
    }
}
INNER_EOF
