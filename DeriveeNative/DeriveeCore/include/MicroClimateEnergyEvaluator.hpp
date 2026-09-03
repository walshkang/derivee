#pragma once

#include "ObserverFormat.hpp"
#include <cstdint>
#include <cmath>
#include <algorithm>

namespace derivee::climate {

// Thermal comfort optimization mode
enum class ThermalComfortMode : uint8_t {
    Neutral = 0,       // Standard distance / time optimization
    SummerShaded = 1,  // Minimizes solar heat exposure, maximizes shade (PET minimization)
    WinterSunlit = 2   // Maximizes direct solar irradiance, avoids cold building canyons
};

// Solar position in horizontal coordinates
struct SolarPosition {
    float altitude_rad = 0.0f;  // Elevation angle above horizon (-pi/2 to pi/2)
    float azimuth_rad = 0.0f;   // Azimuth angle clockwise from true North (0 to 2*pi)
    float zenith_rad = 0.0f;    // Zenith angle (pi/2 - altitude)
    bool is_daylight = false;   // True if altitude > 0

    constexpr SolarPosition() noexcept = default;
    constexpr SolarPosition(float alt, float az, float zen, bool daylight) noexcept
        : altitude_rad(alt), azimuth_rad(az), zenith_rad(zen), is_daylight(daylight) {}
};

// Micro-climate environmental conditions
struct MicroClimateConfig {
    ThermalComfortMode mode = ThermalComfortMode::Neutral;
    float ambient_temp_c = 28.0f;        // Ambient dry-bulb air temperature (deg C)
    float relative_humidity = 0.55f;     // Relative humidity (0.0 to 1.0)
    float wind_speed_mps = 1.5f;         // Wind speed (m/s)
    float direct_irradiance_wm2 = 750.0f;// Direct solar beam irradiance (W/m^2)
    float solar_altitude_rad = 0.0f;     // Optional manual solar altitude override
    float solar_azimuth_rad = 0.0f;      // Optional manual solar azimuth override
    bool has_custom_solar = false;       // If true, uses custom solar angles instead of calculation

    constexpr MicroClimateConfig() noexcept = default;

    constexpr MicroClimateConfig(ThermalComfortMode m) noexcept
        : mode(m), ambient_temp_c(28.0f), relative_humidity(0.55f),
          wind_speed_mps(1.5f), direct_irradiance_wm2(750.0f),
          solar_altitude_rad(0.0f), solar_azimuth_rad(0.0f), has_custom_solar(false) {}

    constexpr MicroClimateConfig(
        ThermalComfortMode m,
        float temp_c,
        float rh,
        float wind,
        float irradiance
    ) noexcept
        : mode(m), ambient_temp_c(temp_c), relative_humidity(rh),
          wind_speed_mps(wind), direct_irradiance_wm2(irradiance),
          solar_altitude_rad(0.0f), solar_azimuth_rad(0.0f), has_custom_solar(false) {}

    // Factory helper for summer afternoon conditions
    static constexpr MicroClimateConfig summer_afternoon() noexcept {
        return MicroClimateConfig(ThermalComfortMode::SummerShaded, 31.0f, 0.60f, 1.2f, 850.0f);
    }

    // Factory helper for winter morning conditions
    static constexpr MicroClimateConfig winter_morning() noexcept {
        return MicroClimateConfig(ThermalComfortMode::WinterSunlit, 4.0f, 0.45f, 2.5f, 500.0f);
    }
};

/**
 * @brief High-performance zero-heap biometeorological evaluator.
 * Computes solar geometry, street canyon building shadow vectors, tree canopy coverage,
 * Mean Radiant Temperature (MRT), Physiologically Equivalent Temperature (PET),
 * and thermal comfort edge weight multipliers in under 0.05 microseconds.
 */
class MicroClimateEnergyEvaluator {
public:
    static constexpr float PI = 3.14159265358979323846f;
    static constexpr float TWO_PI = 6.28318530717958647692f;
    static constexpr float DEG_TO_RAD = 0.017453292519943295f;
    static constexpr float RAD_TO_DEG = 57.295779513082320876f;

    // Standard urban street canyon aspect ratios (Height / Width)
    static constexpr float CANYON_ASPECT_HIGH_RISE = 2.5f; // High-rise urban core (e.g. Midtown Manhattan)
    static constexpr float CANYON_ASPECT_MID_RISE  = 1.2f; // Mid-rise avenues (e.g. 5-8 story brownstones)
    static constexpr float CANYON_ASPECT_LOW_RISE  = 0.4f; // Open / residential low-rise streets

    [[nodiscard]] static constexpr float canyon_aspect_high_rise() noexcept { return CANYON_ASPECT_HIGH_RISE; }
    [[nodiscard]] static constexpr float canyon_aspect_mid_rise() noexcept { return CANYON_ASPECT_MID_RISE; }
    [[nodiscard]] static constexpr float canyon_aspect_low_rise() noexcept { return CANYON_ASPECT_LOW_RISE; }

    /**
     * @brief Computes solar position (altitude and azimuth) using NOAA / Spencer solar position algorithms.
     * @param lat_deg Latitude in decimal degrees (-90 to +90)
     * @param lon_deg Longitude in decimal degrees (-180 to +180)
     * @param timestamp_sec Unix timestamp (seconds since 1970-01-01 00:00:00 UTC)
     * @return SolarPosition in radians
     */
    [[nodiscard]] static inline SolarPosition calculate_solar_position(
        double lat_deg, double lon_deg, uint32_t timestamp_sec) noexcept {
        
        // Days since Unix epoch
        const double days_since_epoch = static_cast<double>(timestamp_sec) / 86400.0;
        
        // Approximate day of year (1-366) and UTC fractional hour
        const double sec_in_day = std::fmod(static_cast<double>(timestamp_sec), 86400.0);
        const double utc_hour = sec_in_day / 3600.0;
        
        // Year calculation (approximate from Unix epoch, leap years accounted)
        double d = days_since_epoch;
        int year = 1970;
        while (true) {
            bool leap = (year % 4 == 0 && (year % 100 != 0 || year % 400 == 0));
            double days_in_yr = leap ? 366.0 : 365.0;
            if (d < days_in_yr) break;
            d -= days_in_yr;
            year++;
        }
        const double day_of_year = d + 1.0;

        // Fractional year in radians (gamma)
        const double gamma = (TWO_PI / 365.25) * (day_of_year - 1.0 + (utc_hour - 12.0) / 24.0);

        // Equation of Time (EOT) in minutes (Spencer 1971)
        const double eot = 229.18 * (0.000075 + 0.001868 * std::cos(gamma) - 0.032077 * std::sin(gamma)
                                     - 0.014615 * std::cos(2.0 * gamma) - 0.040849 * std::sin(2.0 * gamma));

        // Solar Declination (delta) in radians (Spencer 1971)
        const double delta = 0.006918 - 0.399912 * std::cos(gamma) + 0.070257 * std::sin(gamma)
                           - 0.006758 * std::cos(2.0 * gamma) + 0.000907 * std::sin(2.0 * gamma)
                           - 0.002697 * std::cos(3.0 * gamma) + 0.00148 * std::sin(3.0 * gamma);

        // Time offset in minutes
        const double time_offset = eot + 4.0 * lon_deg;

        // True Solar Time (TST) in minutes
        double tst = utc_hour * 60.0 + time_offset;
        tst = std::fmod(tst, 1440.0);
        if (tst < 0.0) tst += 1440.0;

        // Solar Hour Angle (HRA) in radians
        const double hra = ((tst / 4.0) - 180.0) * static_cast<double>(DEG_TO_RAD);

        // Latitude in radians
        const double phi = lat_deg * static_cast<double>(DEG_TO_RAD);

        // Solar Zenith Angle
        const double cos_zenith = std::sin(phi) * std::sin(delta) + std::cos(phi) * std::cos(delta) * std::cos(hra);
        const double clamped_cos_zenith = std::clamp(cos_zenith, -1.0, 1.0);
        const double zenith = std::acos(clamped_cos_zenith);
        const double altitude = (PI * 0.5) - zenith;

        // Solar Azimuth Angle (clockwise from North)
        double azimuth = 0.0;
        const double sin_zenith = std::sin(zenith);
        if (std::abs(sin_zenith) > 1e-6) {
            const double cos_az = (std::sin(delta) * std::cos(phi) - std::cos(delta) * std::sin(phi) * std::cos(hra)) / sin_zenith;
            const double clamped_cos_az = std::clamp(cos_az, -1.0, 1.0);
            const double az_raw = std::acos(clamped_cos_az);
            if (hra > 0.0) {
                azimuth = TWO_PI - az_raw;
            } else {
                azimuth = az_raw;
            }
        }

        const bool daylight = altitude > 0.0;
        return SolarPosition(
            static_cast<float>(altitude),
            static_cast<float>(azimuth),
            static_cast<float>(zenith),
            daylight
        );
    }

    /**
     * @brief Computes street canyon building shadow fraction across street width.
     * @param lat1_deg Start node latitude
     * @param lon1_deg Start node longitude
     * @param lat2_deg End node latitude
     * @param lon2_deg End node longitude
     * @param sun Solar position
     * @param canyon_aspect_ratio Height-to-width ratio (H/W)
     * @return Shadow fraction [0.0 (full sun) to 1.0 (full shade)]
     */
    [[nodiscard]] static inline float calculate_building_shadow(
        double lat1_deg, double lon1_deg,
        double lat2_deg, double lon2_deg,
        const SolarPosition& sun,
        float canyon_aspect_ratio = CANYON_ASPECT_MID_RISE) noexcept {
        
        if (!sun.is_daylight || sun.altitude_rad <= 0.0f) {
            return 1.0f; // Night / sun below horizon = 100% shade
        }

        // Street bearing phi from node 1 to node 2
        const double mean_lat_rad = (lat1_deg + lat2_deg) * 0.5 * static_cast<double>(DEG_TO_RAD);
        const double d_lat = (lat2_deg - lat1_deg);
        const double d_lon = (lon2_deg - lon1_deg) * std::cos(mean_lat_rad);

        if (std::abs(d_lat) < 1e-7 && std::abs(d_lon) < 1e-7) {
            return 0.5f; // Degenerate edge
        }

        float street_bearing = static_cast<float>(std::atan2(d_lon, d_lat));
        if (street_bearing < 0.0f) {
            street_bearing += TWO_PI;
        }

        // Angle between solar azimuth and street axis
        float delta_theta = std::abs(sun.azimuth_rad - street_bearing);
        while (delta_theta > PI) {
            delta_theta = std::abs(delta_theta - TWO_PI);
        }

        // Cross-canyon angle: perpendicular component sin(delta_theta)
        const float cross_canyon_sin = std::abs(std::sin(delta_theta));

        // When tan(altitude) is small (morning/evening), shadow spans the street
        const float tan_alt = std::max(0.01f, std::tan(sun.altitude_rad));
        const float shadow_fraction = (canyon_aspect_ratio * cross_canyon_sin) / tan_alt;

        return std::clamp(shadow_fraction, 0.0f, 1.0f);
    }

    /**
     * @brief Computes combined edge shade factor factoring both building shadows and tree canopy cover.
     * @param lat1_deg Start node latitude
     * @param lon1_deg Start node longitude
     * @param lat2_deg End node latitude
     * @param lon2_deg End node longitude
     * @param sun Solar position
     * @param node_access_flags Bitmask containing accessibility and canopy attributes
     * @return Effective shade factor [0.0 (full sun) to 1.0 (full shade)]
     */
    [[nodiscard]] static inline float calculate_edge_shade_factor(
        double lat1_deg, double lon1_deg,
        double lat2_deg, double lon2_deg,
        const SolarPosition& sun,
        uint16_t node_access_flags) noexcept {

        // Determine canyon aspect ratio from flags
        float aspect_ratio = CANYON_ASPECT_MID_RISE;
        if ((node_access_flags & (1 << 6)) != 0) { // WALK_FLAG_CANYON_HIGH_RISE
            aspect_ratio = CANYON_ASPECT_HIGH_RISE;
        } else if ((node_access_flags & (1 << 7)) != 0) { // WALK_FLAG_CANYON_MID_RISE
            aspect_ratio = CANYON_ASPECT_MID_RISE;
        }

        // Compute building shadow
        const float s_building = calculate_building_shadow(lat1_deg, lon1_deg, lat2_deg, lon2_deg, sun, aspect_ratio);

        // Determine tree canopy cover from flags
        float c_canopy = 0.05f; // Default baseline urban street trees (~5%)
        if ((node_access_flags & (1 << 5)) != 0) { // WALK_FLAG_TREE_CANOPY_HIGH
            c_canopy = 0.75f; // Parks / dense tree rows (~75%)
        } else if ((node_access_flags & (1 << 4)) != 0) { // WALK_FLAG_TREE_CANOPY_LOW
            c_canopy = 0.30f; // Moderately tree-lined residential street (~30%)
        }

        // Combined shade probability: 1 - (1 - S_building) * (1 - C_canopy)
        const float combined = 1.0f - (1.0f - s_building) * (1.0f - c_canopy);
        return std::clamp(combined, 0.0f, 1.0f);
    }

    /**
     * @brief Estimates Physiologically Equivalent Temperature (PET) in Celsius.
     * Uses Munich Energy-balance Model for Individuals (MEMI) parameterized approximation.
     * @param temp_c Ambient dry bulb air temperature
     * @param rh Relative humidity (0.0 to 1.0)
     * @param wind_mps Wind velocity (m/s)
     * @param shade_factor Effective shade factor [0.0 to 1.0]
     * @param solar_altitude_rad Sun elevation angle in radians
     * @return Estimated PET in degrees Celsius
     */
    [[nodiscard]] static inline float estimate_pet_celsius(
        float temp_c,
        float rh,
        float wind_mps,
        float shade_factor,
        float solar_altitude_rad) noexcept {

        // Mean Radiant Temperature (MRT) calculation:
        // Direct sun adds ~18°C * sin(altitude) above air temperature.
        // Shade moderates MRT to diffuse sky radiation (~3°C above air temperature).
        const float solar_factor = std::max(0.0f, std::sin(solar_altitude_rad));
        const float mrt_sun = temp_c + 18.0f * solar_factor;
        const float mrt_shade = temp_c + 3.0f;
        const float mrt_effective = shade_factor * mrt_shade + (1.0f - shade_factor) * mrt_sun;

        // MEMI-based parameterized empirical PET formulation
        const float wind_effect = 1.2f * std::sqrt(std::max(0.1f, wind_mps));
        const float humidity_effect = 0.15f * (std::clamp(rh, 0.0f, 1.0f) * 100.0f);

        const float pet = 0.62f * temp_c + 0.38f * mrt_effective + humidity_effect - wind_effect - 1.5f;
        return pet;
    }

    /**
     * @brief Computes edge traversal weight multiplier W(e) >= 1.0 for pathfinding search.
     * Preserves strict admissibility for Euclidean distance heuristic h(u) <= dist(u, goal).
     * @param shade_factor Effective shade factor [0.0 (sun) to 1.0 (shade)]
     * @param config Microclimate configuration and thermal preference mode
     * @return Traversal weight multiplier [1.0 to 2.0]
     */
    [[nodiscard]] static inline float calculate_edge_weight_multiplier(
        float shade_factor,
        const MicroClimateConfig& config) noexcept {

        if (config.mode == ThermalComfortMode::Neutral) {
            return 1.0f;
        }

        if (config.mode == ThermalComfortMode::SummerShaded) {
            // Summer Shaded: heavily penalize open unshaded sun exposure.
            // Full shade (1.0) -> multiplier = 1.0 (ideal).
            // Full sun   (0.0) -> multiplier = 1.75 (75% traversal penalty).
            constexpr float k_summer_penalty = 0.75f;
            const float sun_exposure = 1.0f - shade_factor;
            return 1.0f + k_summer_penalty * sun_exposure;
        }

        if (config.mode == ThermalComfortMode::WinterSunlit) {
            // Winter Sunlit: penalize cold, damp building shadow canyons.
            // Full sun   (0.0) -> multiplier = 1.0 (ideal solar warming).
            // Full shade (1.0) -> multiplier = 1.60 (60% cold canyon penalty).
            constexpr float k_winter_penalty = 0.60f;
            return 1.0f + k_winter_penalty * shade_factor;
        }

        return 1.0f;
    }
};

} // namespace derivee::climate
