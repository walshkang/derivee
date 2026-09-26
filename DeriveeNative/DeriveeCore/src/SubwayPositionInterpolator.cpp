#include "SubwayPositionInterpolator.hpp"
#include <limits>

namespace Derivee::Transit {

SubwayPositionInterpolator::SubwayPositionInterpolator(
    std::vector<Point2D> shape_points,
    double ref_lat,
    double ref_lon
) noexcept
    : ref_lat_(ref_lat), ref_lon_(ref_lon) {
    build_cumulative_geometry(std::move(shape_points));
}

SubwayPositionInterpolator::SubwayPositionInterpolator(
    const Point2D* shape_points,
    size_t count,
    double ref_lat,
    double ref_lon
) noexcept
    : ref_lat_(ref_lat), ref_lon_(ref_lon) {
    std::vector<Point2D> pts;
    if (shape_points != nullptr && count > 0) {
        pts.assign(shape_points, shape_points + count);
    }
    build_cumulative_geometry(std::move(pts));
}

SubwayPositionInterpolator SubwayPositionInterpolator::from_geographic_shape(
    const std::vector<GeoCoordinate>& coords,
    double ref_lat,
    double ref_lon
) noexcept {
    SubwayPositionInterpolator interpolator(std::vector<Point2D>{}, ref_lat, ref_lon);
    std::vector<Point2D> pts;
    pts.reserve(coords.size());
    for (const auto& geo : coords) {
        pts.push_back(interpolator.to_conformal(geo));
    }
    interpolator.build_cumulative_geometry(std::move(pts));
    return interpolator;
}

SubwayPositionInterpolator SubwayPositionInterpolator::from_geographic_coords(
    const GeoCoordinate* coords,
    size_t count,
    double ref_lat,
    double ref_lon
) noexcept {
    SubwayPositionInterpolator interpolator(std::vector<Point2D>{}, ref_lat, ref_lon);
    std::vector<Point2D> pts;
    if (coords != nullptr && count > 0) {
        pts.reserve(count);
        for (size_t i = 0; i < count; ++i) {
            pts.push_back(interpolator.to_conformal(coords[i]));
        }
    }
    interpolator.build_cumulative_geometry(std::move(pts));
    return interpolator;
}

Point2D SubwayPositionInterpolator::to_conformal(const GeoCoordinate& geo) const noexcept {
    constexpr double deg_to_rad = M_PI / 180.0;
    const double phi = geo.latitude * deg_to_rad;
    const double phi0 = ref_lat_ * deg_to_rad;
    const double psi = geo.longitude * deg_to_rad;
    const double psi0 = ref_lon_ * deg_to_rad;
    const double phi_mid = 0.5 * (phi + phi0);

    const double x = EARTH_RADIUS_METERS * (psi - psi0) * std::cos(phi_mid);
    const double y = EARTH_RADIUS_METERS * (phi - phi0);
    return Point2D{x, y};
}

GeoCoordinate SubwayPositionInterpolator::to_geographic(const Point2D& pt) const noexcept {
    constexpr double rad_to_deg = 180.0 / M_PI;
    constexpr double deg_to_rad = M_PI / 180.0;
    const double phi0 = ref_lat_ * deg_to_rad;
    const double psi0 = ref_lon_ * deg_to_rad;

    const double phi = phi0 + (pt.y / EARTH_RADIUS_METERS);
    const double phi_mid = 0.5 * (phi + phi0);
    double cos_mid = std::cos(phi_mid);
    if (std::abs(cos_mid) < 1e-7) {
        cos_mid = (cos_mid >= 0.0) ? 1e-7 : -1e-7;
    }
    const double psi = psi0 + (pt.x / (EARTH_RADIUS_METERS * cos_mid));

    return GeoCoordinate{phi * rad_to_deg, psi * rad_to_deg};
}

void SubwayPositionInterpolator::build_cumulative_geometry(std::vector<Point2D> pts) noexcept {
    geometry_.clear();
    total_shape_distance_ = 0.0;
    if (pts.empty()) return;

    geometry_.reserve(pts.size());
    double accum = 0.0;
    geometry_.emplace_back(pts.front(), 0.0);

    for (size_t i = 1; i < pts.size(); ++i) {
        accum += pts[i].distance_to(pts[i - 1]);
        geometry_.emplace_back(pts[i], accum);
    }
    total_shape_distance_ = accum;
}

double SubwayPositionInterpolator::project_point_with_distance(
    const Point2D& pt,
    double& out_perp_dist
) const noexcept {
    if (geometry_.empty()) {
        out_perp_dist = 0.0;
        return 0.0;
    }
    if (geometry_.size() == 1) {
        out_perp_dist = pt.distance_to(geometry_.front().point);
        return 0.0;
    }

    double best_dist_sq = std::numeric_limits<double>::infinity();
    double best_linear_dist = 0.0;

    for (size_t k = 0; k < geometry_.size() - 1; ++k) {
        const auto& p_k = geometry_[k].point;
        const auto& p_next = geometry_[k + 1].point;
        const double e_x = p_next.x - p_k.x;
        const double e_y = p_next.y - p_k.y;
        const double seg_len_sq = e_x * e_x + e_y * e_y;

        double u_hat = 0.0;
        if (seg_len_sq > 1e-12) {
            const double u = ((pt.x - p_k.x) * e_x + (pt.y - p_k.y) * e_y) / seg_len_sq;
            u_hat = std::clamp(u, 0.0, 1.0);
        }

        const Point2D q_k{p_k.x + u_hat * e_x, p_k.y + u_hat * e_y};
        const double dx = pt.x - q_k.x;
        const double dy = pt.y - q_k.y;
        const double dist_sq = dx * dx + dy * dy;

        if (dist_sq < best_dist_sq) {
            best_dist_sq = dist_sq;
            const double seg_len = std::sqrt(seg_len_sq);
            best_linear_dist = geometry_[k].cumulative_distance + (u_hat * seg_len);
        }
    }

    out_perp_dist = std::sqrt(best_dist_sq);
    return best_linear_dist;
}

double SubwayPositionInterpolator::project_point(const Point2D& pt) const noexcept {
    double perp = 0.0;
    return project_point_with_distance(pt, perp);
}

double SubwayPositionInterpolator::project_geographic_point(double lat, double lon) const noexcept {
    double perp = 0.0;
    return project_geographic_point_with_distance(lat, lon, perp);
}

double SubwayPositionInterpolator::project_geographic_point_with_distance(
    double lat,
    double lon,
    double& out_perp_dist
) const noexcept {
    const Point2D pt = to_conformal(GeoCoordinate{lat, lon});
    return project_point_with_distance(pt, out_perp_dist);
}

SnappedPointResult SubwayPositionInterpolator::snap_geographic_point(
    double lat,
    double lon,
    double max_corridor_dist_m
) const noexcept {
    if (geometry_.empty()) {
        return SnappedPointResult(GeoCoordinate(lat, lon), 0.0, 0.0, 0.0, false);
    }

    const Point2D pt = to_conformal(GeoCoordinate{lat, lon});
    double perp_dist = 0.0;
    const double best_linear_dist = project_point_with_distance(pt, perp_dist);

    const bool on_corridor = (perp_dist <= max_corridor_dist_m);

    if (on_corridor) {
        double heading_rad = 0.0;
        const Point2D snapped_pt = interpolate_point_at_distance(best_linear_dist, heading_rad);
        const GeoCoordinate snapped_geo = to_geographic(snapped_pt);
        
        double heading_deg = heading_rad * (180.0 / M_PI);
        if (heading_deg < 0.0) heading_deg += 360.0;
        if (heading_deg >= 360.0) heading_deg -= 360.0;

        return SnappedPointResult(
            snapped_geo,
            best_linear_dist,
            perp_dist,
            heading_deg,
            true
        );
    } else {
        return SnappedPointResult(
            GeoCoordinate(lat, lon),
            best_linear_dist,
            perp_dist,
            0.0,
            false
        );
    }
}

Point2D SubwayPositionInterpolator::interpolate_point_at_distance(
    double d,
    double& out_heading
) const noexcept {
    if (geometry_.empty()) {
        out_heading = 0.0;
        return Point2D{0.0, 0.0};
    }
    if (geometry_.size() == 1) {
        out_heading = 0.0;
        return geometry_.front().point;
    }

    const double clamped_d = std::clamp(d, 0.0, total_shape_distance_);

    auto it = std::upper_bound(
        geometry_.begin(),
        geometry_.end(),
        clamped_d,
        [](double val, const PolylineVertex& v) noexcept {
            return val < v.cumulative_distance;
        }
    );

    if (it == geometry_.begin()) {
        out_heading = std::atan2(geometry_[1].point.x - geometry_[0].point.x,
                                 geometry_[1].point.y - geometry_[0].point.y);
        return geometry_.front().point;
    }

    if (it == geometry_.end()) {
        const size_t last_idx = geometry_.size() - 1;
        out_heading = std::atan2(geometry_[last_idx].point.x - geometry_[last_idx - 1].point.x,
                                 geometry_[last_idx].point.y - geometry_[last_idx - 1].point.y);
        return geometry_.back().point;
    }

    const size_t idx1 = std::distance(geometry_.begin(), it);
    const size_t idx0 = idx1 - 1;
    const auto& v0 = geometry_[idx0];
    const auto& v1 = geometry_[idx1];

    const double seg_len = v1.cumulative_distance - v0.cumulative_distance;
    const double seg_mu = (seg_len > 0.0) ? (clamped_d - v0.cumulative_distance) / seg_len : 0.0;

    out_heading = std::atan2(v1.point.x - v0.point.x, v1.point.y - v0.point.y);

    return Point2D{
        v0.point.x + seg_mu * (v1.point.x - v0.point.x),
        v0.point.y + seg_mu * (v1.point.y - v0.point.y)
    };
}

double SubwayPositionInterpolator::solve_kinematic_progress(
    double elapsed_sec,
    double total_dur_sec,
    double distance_m,
    double a,
    double d
) const noexcept {
    if (elapsed_sec <= 0.0) return 0.0;
    if (total_dur_sec <= 0.0 || distance_m <= 0.0) return 1.0;
    if (elapsed_sec >= total_dur_sec) return 1.0;

    const double alpha = 0.5 * (1.0 / a + 1.0 / d);
    const double discriminant = (total_dur_sec * total_dur_sec) - (4.0 * alpha * distance_m);

    // Negative discriminant: schedule compressed beyond physical acceleration/braking limits
    if (discriminant < 0.0) {
        const double tau = std::clamp(elapsed_sec / total_dur_sec, 0.0, 1.0);
        return (tau * tau * tau) * (tau * (tau * 6.0 - 15.0) + 10.0);
    }

    const double vc = (total_dur_sec - std::sqrt(discriminant)) / (2.0 * alpha);
    const double ta = vc / a;
    const double td = vc / d;
    const double tc = total_dur_sec - (ta + td);

    // If cruising duration is negative, triangular limit exceeded; fall back to quintic Hermite
    if (tc < 0.0) {
        const double tau = std::clamp(elapsed_sec / total_dur_sec, 0.0, 1.0);
        return (tau * tau * tau) * (tau * (tau * 6.0 - 15.0) + 10.0);
    }

    double s = 0.0;
    if (elapsed_sec < ta) {
        s = 0.5 * a * elapsed_sec * elapsed_sec;
    } else if (elapsed_sec < (ta + tc)) {
        const double sa = 0.5 * a * ta * ta;
        s = sa + vc * (elapsed_sec - ta);
    } else {
        const double dt_brake = total_dur_sec - elapsed_sec;
        s = distance_m - 0.5 * d * dt_brake * dt_brake;
    }

    return std::clamp(s / distance_m, 0.0, 1.0);
}

void SubwayPositionInterpolator::populate_geographic_and_heading(ConsistSpatialEstimate& estimate) const noexcept {
    double deg = estimate.heading_radians * (180.0 / M_PI);
    if (deg < 0.0) deg += 360.0;
    if (deg >= 360.0) deg -= 360.0;
    estimate.heading_degrees = deg;

    const GeoCoordinate geo = to_geographic(estimate.coordinates);
    estimate.latitude = geo.latitude;
    estimate.longitude = geo.longitude;
}

ConsistSpatialEstimate SubwayPositionInterpolator::update(
    const IngestedTelemetry& telemetry,
    std::chrono::system_clock::time_point now
) const noexcept {
    ConsistSpatialEstimate estimate;

    // 1. Telemetry Staleness Assessment
    const auto feed_age = std::chrono::duration<double>(now - telemetry.feed_timestamp).count();
    const bool is_telemetry_stale = (feed_age > STALE_FEED_THRESHOLD_SEC);

    // 2. Terminal Origin Holding Logic (is_assigned: true, sequence <= 1, STOPPED_AT)
    if (telemetry.is_assigned && telemetry.stop_sequence <= 1 &&
        telemetry.current_status == GTFSVehicleStatus::STOPPED_AT) {
        estimate.linear_progress = 0.0;
        estimate.coordinates = interpolate_point_at_distance(telemetry.origin_platform_dist, estimate.heading_radians);
        populate_geographic_and_heading(estimate);

        const auto dwell_delay = std::chrono::duration<double>(now - telemetry.departure_time).count();
        if (dwell_delay > STATION_HOLD_THRESHOLD_SEC) {
            estimate.visual_state = VisualState::HOLDING_STATION;
            estimate.is_holding = true;
        } else {
            estimate.visual_state = VisualState::BOARDING_TERMINAL;
            estimate.is_holding = false;
        }
        return estimate;
    }

    // 3. Platform Station Dwell Logic (Intermediate Stops)
    if (telemetry.current_status == GTFSVehicleStatus::STOPPED_AT) {
        estimate.linear_progress = 0.0;
        estimate.coordinates = interpolate_point_at_distance(telemetry.origin_platform_dist, estimate.heading_radians);
        populate_geographic_and_heading(estimate);

        const auto dwell_time = std::chrono::duration<double>(now - telemetry.departure_time).count();
        if (dwell_time > STATION_HOLD_THRESHOLD_SEC) {
            estimate.visual_state = VisualState::HOLDING_STATION;
            estimate.is_holding = true;
        } else {
            estimate.visual_state = VisualState::STOPPED_IN_STATION;
            estimate.is_holding = false;
        }
        return estimate;
    }

    // 4. Inter-Station Transit Geometry Validation
    const double inter_station_dist = telemetry.target_platform_dist - telemetry.origin_platform_dist;
    if (inter_station_dist <= 0.0) {
        estimate.linear_progress = 0.0;
        estimate.coordinates = interpolate_point_at_distance(telemetry.origin_platform_dist, estimate.heading_radians);
        populate_geographic_and_heading(estimate);
        estimate.visual_state = VisualState::STOPPED_IN_STATION;
        estimate.is_holding = false;
        return estimate;
    }

    const auto total_transit_dur = std::chrono::duration<double>(
        telemetry.arrival_time_next - telemetry.departure_time
    ).count();

    const auto elapsed_transit_dur = std::chrono::duration<double>(
        now - telemetry.departure_time
    ).count();

    // 5. Mid-Tunnel Signal Stop and Feed Dropout Arrest
    if (elapsed_transit_dur > (total_transit_dur + 30.0) || is_telemetry_stale) {
        estimate.linear_progress = APPROACH_PROGRESS_CEILING;
        const double current_dist = telemetry.origin_platform_dist + (estimate.linear_progress * inter_station_dist);
        estimate.coordinates = interpolate_point_at_distance(current_dist, estimate.heading_radians);
        populate_geographic_and_heading(estimate);
        estimate.visual_state = is_telemetry_stale ? VisualState::TELEMETRY_STALE : VisualState::HOLDING_MID_TUNNEL;
        estimate.is_holding = true;
        return estimate;
    }

    // 6. Kinematic Motion Profile Execution
    double raw_lambda = 0.0;
    if (total_transit_dur > 0.0 && elapsed_transit_dur > 0.0) {
        raw_lambda = solve_kinematic_progress(
            elapsed_transit_dur,
            total_transit_dur,
            inter_station_dist,
            DEFAULT_ACCEL,
            DEFAULT_DECEL
        );
    }

    // 7. Status-Dependent Boundary Clamping
    if (telemetry.current_status == GTFSVehicleStatus::IN_TRANSIT_TO) {
        estimate.linear_progress = std::clamp(raw_lambda, 0.0, APPROACH_PROGRESS_CEILING);
        if (estimate.linear_progress >= APPROACH_PROGRESS_CEILING) {
            estimate.visual_state = VisualState::APPROACHING_STATION;
        } else {
            estimate.visual_state = VisualState::TRANSITING_NOMINAL;
        }
        estimate.is_holding = false;
    } else if (telemetry.current_status == GTFSVehicleStatus::INCOMING_AT) {
        estimate.linear_progress = std::clamp(raw_lambda, APPROACH_PROGRESS_CEILING, 0.995);
        estimate.visual_state = VisualState::APPROACHING_STATION;
        estimate.is_holding = false;
    }

    const double current_distance = telemetry.origin_platform_dist + (estimate.linear_progress * inter_station_dist);
    estimate.coordinates = interpolate_point_at_distance(current_distance, estimate.heading_radians);
    populate_geographic_and_heading(estimate);
    return estimate;
}

ConsistSpatialEstimate SubwayPositionInterpolator::update(
    const IngestedTelemetry& telemetry,
    double now_epoch_sec
) const noexcept {
    return update(telemetry, IngestedTelemetry::from_epoch_seconds(now_epoch_sec));
}

} // namespace Derivee::Transit
