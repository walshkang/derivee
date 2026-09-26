#pragma once

#include <iostream>
#include <vector>
#include <string>
#include <cmath>
#include <algorithm>
#include <optional>
#include <chrono>
#include <memory>
#include <cstdint>
#include <cassert>

namespace Derivee::Transit {

/// 2D geographic coordinate representation (WGS-84 degrees).
struct GeoCoordinate {
    double latitude{0.0};
    double longitude{0.0};

    constexpr GeoCoordinate() noexcept = default;
    constexpr GeoCoordinate(double lat, double lon) noexcept
        : latitude(lat), longitude(lon) {}
};

/// 2D Cartesian point in conformal planar coordinates (meters).
struct Point2D {
    double x{0.0};
    double y{0.0};

    constexpr Point2D() noexcept = default;
    constexpr Point2D(double x_val, double y_val) noexcept
        : x(x_val), y(y_val) {}

    [[nodiscard]] double distance_to(const Point2D& other) const noexcept {
        return std::hypot(x - other.x, y - other.y);
    }
};

/// Polyline vertex with cumulative geodesic distance from origin (meters).
struct PolylineVertex {
    Point2D point;
    double cumulative_distance{0.0};

    constexpr PolylineVertex() noexcept = default;
    constexpr PolylineVertex(Point2D pt, double cum_dist) noexcept
        : point(pt), cumulative_distance(cum_dist) {}
};

/// Consist visual tracking state per Research Doc 17 (§4).
enum class VisualState : uint8_t {
    BOARDING_TERMINAL = 0,
    STOPPED_IN_STATION = 1,
    HOLDING_STATION = 2,
    TRANSITING_NOMINAL = 3,
    APPROACHING_STATION = 4,
    HOLDING_MID_TUNNEL = 5,
    TELEMETRY_STALE = 6
};

/// Standard GTFS-RT vehicle stop status.
enum class GTFSVehicleStatus : uint8_t {
    INCOMING_AT = 0,
    STOPPED_AT = 1,
    IN_TRANSIT_TO = 2
};

/// Ingested transit telemetry payload for a single consist run.
struct IngestedTelemetry {
    std::string trip_id;
    std::string route_id;
    uint32_t stop_sequence{0};
    std::string stop_id;
    GTFSVehicleStatus current_status{GTFSVehicleStatus::STOPPED_AT};
    bool is_assigned{false};

    std::chrono::system_clock::time_point departure_time;
    std::chrono::system_clock::time_point arrival_time_next;
    std::chrono::system_clock::time_point feed_timestamp;

    double origin_platform_dist{0.0};
    double target_platform_dist{0.0};

    IngestedTelemetry() noexcept = default;

    /// Epoch-seconds convenience constructor for zero-overhead Swift-C++ interop.
    IngestedTelemetry(
        std::string trip,
        std::string route,
        uint32_t seq,
        std::string stop,
        GTFSVehicleStatus status,
        bool assigned,
        double departure_sec,
        double arrival_next_sec,
        double feed_sec,
        double origin_dist,
        double target_dist
    ) noexcept
        : trip_id(std::move(trip)),
          route_id(std::move(route)),
          stop_sequence(seq),
          stop_id(std::move(stop)),
          current_status(status),
          is_assigned(assigned),
          departure_time(from_epoch_seconds(departure_sec)),
          arrival_time_next(from_epoch_seconds(arrival_next_sec)),
          feed_timestamp(from_epoch_seconds(feed_sec)),
          origin_platform_dist(origin_dist),
          target_platform_dist(target_dist) {}

    static std::chrono::system_clock::time_point from_epoch_seconds(double sec) noexcept {
        const auto dur = std::chrono::duration<double>(sec);
        return std::chrono::system_clock::time_point(
            std::chrono::duration_cast<std::chrono::system_clock::duration>(dur)
        );
    }

    static double to_epoch_seconds(std::chrono::system_clock::time_point tp) noexcept {
        return std::chrono::duration<double>(tp.time_since_epoch()).count();
    }
};

/// Kinematic spatial estimate resulting from polyline evaluation.
struct ConsistSpatialEstimate {
    Point2D coordinates;
    double latitude{0.0};
    double longitude{0.0};
    double heading_radians{0.0};
    double heading_degrees{0.0};
    double linear_progress{0.0};
    VisualState visual_state{VisualState::STOPPED_IN_STATION};
    bool is_holding{false};

    constexpr ConsistSpatialEstimate() noexcept = default;
};

/// Snapped geographic result for surface vehicles (Research Doc 17 & Wave Pre-T.8c).
struct SnappedPointResult {
    GeoCoordinate snapped_coordinate{0.0, 0.0};
    double cumulative_distance{0.0};
    double perpendicular_distance{0.0};
    double heading_degrees{0.0};
    bool is_on_corridor{false};

    constexpr SnappedPointResult() noexcept = default;
    constexpr SnappedPointResult(
        GeoCoordinate coord,
        double cum_dist,
        double perp_dist,
        double heading_deg,
        bool on_corridor
    ) noexcept
        : snapped_coordinate(coord),
          cumulative_distance(cum_dist),
          perpendicular_distance(perp_dist),
          heading_degrees(heading_deg),
          is_on_corridor(on_corridor) {}
};

/// High-precision kinematic interpolator and orthogonal polyline linear referencing core.
class SubwayPositionInterpolator {
public:
    static constexpr double DEFAULT_ACCEL = 1.15; // m/s^2 (~2.57 mph/s)
    static constexpr double DEFAULT_DECEL = 1.25; // m/s^2 (~2.80 mph/s)
    static constexpr double STALE_FEED_THRESHOLD_SEC = 90.0;
    static constexpr double STATION_HOLD_THRESHOLD_SEC = 120.0;
    static constexpr double APPROACH_PROGRESS_CEILING = 0.85;
    static constexpr double EARTH_RADIUS_METERS = 6371000.0;

    static double default_accel() noexcept { return DEFAULT_ACCEL; }
    static double default_decel() noexcept { return DEFAULT_DECEL; }
    static double stale_feed_threshold_sec() noexcept { return STALE_FEED_THRESHOLD_SEC; }
    static double station_hold_threshold_sec() noexcept { return STATION_HOLD_THRESHOLD_SEC; }
    static double approach_progress_ceiling() noexcept { return APPROACH_PROGRESS_CEILING; }
    static double earth_radius_meters() noexcept { return EARTH_RADIUS_METERS; }

    /// Default constructor creating an empty geometry.
    SubwayPositionInterpolator() noexcept = default;

    /// Constructs an interpolator from a pre-projected Cartesian polyline vector.
    explicit SubwayPositionInterpolator(
        std::vector<Point2D> shape_points,
        double ref_lat = 40.7128,
        double ref_lon = -74.0060
    ) noexcept;

    /// Constructs an interpolator from a contiguous buffer of Cartesian points.
    SubwayPositionInterpolator(
        const Point2D* shape_points,
        size_t count,
        double ref_lat = 40.7128,
        double ref_lon = -74.0060
    ) noexcept;

    /// Factory method constructing an interpolator directly from WGS-84 geographic coordinates vector.
    [[nodiscard]] static SubwayPositionInterpolator from_geographic_shape(
        const std::vector<GeoCoordinate>& coords,
        double ref_lat = 40.7128,
        double ref_lon = -74.0060
    ) noexcept;

    /// Factory method constructing an interpolator directly from a contiguous buffer of WGS-84 geographic coordinates.
    [[nodiscard]] static SubwayPositionInterpolator from_geographic_coords(
        const GeoCoordinate* coords,
        size_t count,
        double ref_lat = 40.7128,
        double ref_lon = -74.0060
    ) noexcept;

    /// Projects an arbitrary Cartesian point onto the polyline (Eq. 88–98 in Doc 17).
    /// Returns cumulative linear distance along the line string.
    [[nodiscard]] double project_point(const Point2D& pt) const noexcept;

    /// Projects an arbitrary Cartesian point onto the polyline, also outputting perpendicular distance.
    [[nodiscard]] double project_point_with_distance(
        const Point2D& pt,
        double& out_perp_dist
    ) const noexcept;

    /// Projects geographic coordinates onto the polyline, returning cumulative linear distance.
    [[nodiscard]] double project_geographic_point(double lat, double lon) const noexcept;

    /// Projects geographic coordinates onto the polyline, returning cumulative linear distance and perpendicular offset.
    [[nodiscard]] double project_geographic_point_with_distance(
        double lat,
        double lon,
        double& out_perp_dist
    ) const noexcept;

    /// Interpolates a Cartesian point and heading at a given linear distance along the polyline.
    [[nodiscard]] Point2D interpolate_point_at_distance(
        double d,
        double& out_heading
    ) const noexcept;

    /// Evaluates kinematic motion progress in [0.0, 1.0] using trapezoidal profile or quintic Hermite fallback.
    [[nodiscard]] double solve_kinematic_progress(
        double elapsed_sec,
        double total_dur_sec,
        double distance_m,
        double a = DEFAULT_ACCEL,
        double d = DEFAULT_DECEL
    ) const noexcept;

    /// Primary telemetry evaluation function taking system clock time point.
    [[nodiscard]] ConsistSpatialEstimate update(
        const IngestedTelemetry& telemetry,
        std::chrono::system_clock::time_point now
    ) const noexcept;

    /// Epoch-seconds overload of primary evaluation function for Swift interop ergonomics.
    [[nodiscard]] ConsistSpatialEstimate update(
        const IngestedTelemetry& telemetry,
        double now_epoch_sec
    ) const noexcept;

    /// Forward conformal transform: WGS-84 degrees -> Conformal Cartesian meters.
    [[nodiscard]] Point2D to_conformal(const GeoCoordinate& geo) const noexcept;

    /// Inverse conformal transform: Conformal Cartesian meters -> WGS-84 degrees.
    [[nodiscard]] GeoCoordinate to_geographic(const Point2D& pt) const noexcept;

    /// Snaps an arbitrary WGS-84 geographic coordinate to the polyline centerline with corridor gating.
    /// If perpendicular distance <= max_corridor_dist_m, returns the projected point on the polyline.
    /// If perpendicular distance > max_corridor_dist_m (or geometry empty), returns the raw (lat, lon) with is_on_corridor = false.
    [[nodiscard]] SnappedPointResult snap_geographic_point(
        double lat,
        double lon,
        double max_corridor_dist_m = 50.0
    ) const noexcept;

    /// Returns total cumulative length of the polyline in meters.
    [[nodiscard]] double total_shape_distance() const noexcept {
        return total_shape_distance_;
    }

    /// Returns the number of vertices in the loaded geometry.
    [[nodiscard]] size_t vertex_count() const noexcept {
        return geometry_.size();
    }

    /// Returns reference latitude for conformal projection.
    [[nodiscard]] double reference_latitude() const noexcept {
        return ref_lat_;
    }

    /// Returns reference longitude for conformal projection.
    [[nodiscard]] double reference_longitude() const noexcept {
        return ref_lon_;
    }

private:
    std::vector<PolylineVertex> geometry_{};
    double total_shape_distance_{0.0};
    double ref_lat_{40.7128};
    double ref_lon_{-74.0060};

    void build_cumulative_geometry(std::vector<Point2D> pts) noexcept;
    void populate_geographic_and_heading(ConsistSpatialEstimate& estimate) const noexcept;
};

} // namespace Derivee::Transit

namespace derivee::transit {
    using namespace Derivee::Transit;
}

using Derivee::Transit::SubwayPositionInterpolator;
using Derivee::Transit::Point2D;
using Derivee::Transit::GeoCoordinate;
using Derivee::Transit::PolylineVertex;
using Derivee::Transit::VisualState;
using Derivee::Transit::GTFSVehicleStatus;
using Derivee::Transit::IngestedTelemetry;
using Derivee::Transit::ConsistSpatialEstimate;
using Derivee::Transit::SnappedPointResult;
