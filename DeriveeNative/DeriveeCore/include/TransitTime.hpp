#pragma once

#include <cstdint>

class TransitTime {
public:
    static constexpr uint32_t SECONDS_PER_DAY = 86400;

    // Euclidean Modulo function ensuring non-negative results across midnight
    [[nodiscard]] static constexpr int32_t euclidean_mod(int32_t a, int32_t b) noexcept {
        if (b == 0) return 0;
        int32_t r = a % b;
        return r < 0 ? r + (b > 0 ? b : -b) : r;
    }

    // Normalizes real-time departure seconds relative to absolute service epoch
    [[nodiscard]] static constexpr uint32_t normalize_schedule_time(
        int32_t raw_seconds_from_epoch, 
        int32_t gtfs_rt_delay_sec) noexcept 
    {
        int32_t adjusted_time = raw_seconds_from_epoch + gtfs_rt_delay_sec;
        return adjusted_time < 0 ? 0 : static_cast<uint32_t>(adjusted_time);
    }

    // Computes wait duration across midnight transitions (within a 24h window)
    [[nodiscard]] static constexpr uint32_t calculate_wait_time(
        uint32_t arrival_time_sec, 
        uint32_t departure_time_sec) noexcept 
    {
        if (departure_time_sec >= arrival_time_sec) {
            return departure_time_sec - arrival_time_sec;
        }
        return (departure_time_sec + SECONDS_PER_DAY) - arrival_time_sec;
    }

    // Computes signed circular delay constrained to [-720, +720] minutes on a 1440m clock face
    [[nodiscard]] static constexpr int32_t calculate_signed_circular_delay_minutes(
        int32_t live_time_minutes,
        int32_t scheduled_time_minutes) noexcept
    {
        int32_t diff = euclidean_mod(live_time_minutes - scheduled_time_minutes + 720, 1440) - 720;
        return diff;
    }
};
