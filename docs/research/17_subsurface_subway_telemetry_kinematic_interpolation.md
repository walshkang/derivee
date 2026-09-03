# High-Precision Sub-Meter Polyline Snapping and Kinematic Interpolation for Subsurface Subway Telemetry

## 1. Telemetry Architecture and NYCT Subsurface Infrastructure

Subsurface rail transit networks operate in an environment devoid of Global Positioning System signals. Consequently, real-time train tracking cannot rely on continuous latitude and longitude coordinates transmitted from vehicle-mounted receivers. The New York City Subway network, operated by MTA New York City Transit (NYCT), bridges this localization challenge by publishing event-driven, spatially quantized telemetry streams derived from legacy wayside signaling and modern computer-based train monitoring infrastructure.

```
+-----------------------------------------------------------------------------------+
|               NYCT Subsurface Signaling & Telemetry Architecture                  |
+-----------------------------------------------------------------------------------+
|  A Division (Lines 1-6, 42nd St S)        |  B Division (Canarsie Line L, 7 Line) |
|  - ATS-A Server Interlocking Polls        |  - CBTC Zone Controllers              |
|  - Relay Room PLCs & Track Circuits       |  - Wayside Transponders (RF Beacons)  |
|  - 30-Second Polled Feed Generation       |  - Moving-Block Precise Localization  |
+-------------------------------------------+---------------------------------------+
                     |                                          |
                     +--------------------+---------------------+
                                          |
                                          v
+-----------------------------------------------------------------------------------+
|                        MTA GTFS-RT Ingestion Engine                               |
|  - Standard GTFS-RT (TripUpdate, VehiclePosition)                                 |
|  - nyct-subway.proto Extensions (NyctTripDescriptor, NyctStopTimeUpdate)          |
+-----------------------------------------------------------------------------------+
                                          |
                                          v
+-----------------------------------------------------------------------------------+
|                   SubwayPositionInterpolator (Client Core)                        |
|  - High-Precision Polyline Linear Referencing (shapes.txt)                        |
|  - Kinematic Progress Solver (Trapezoidal / Quintic Hermite Curves)               |
|  - ATS Anomaly, Terminal Dwell, and Mid-Tunnel Signal Hold State Machine          |
+-----------------------------------------------------------------------------------+
```

### Signaling Divisions and Hardware Sensing
The underlying sensing hardware is bifurcated along historical divisional and operational lines:
- **A Division (IRT Numbered Routes 1–6 and 42nd St Shuttle):** Relies on the Automatic Train Supervision (ATS-A) office system. ATS-A captures train movements through relay drops across fixed single-rail or double-rail alternating current track circuits. When the steel wheelsets of a train shunt the rails, the signal circuit de-energizes, transmitting binary block occupancy data via relay room Programmable Logic Controllers (PLCs) to the Rail Control Center (RCC). Because fixed blocks span lengths from 100 to 300 meters, position tracking is inherently discretized.
- **B Division (CBTC Lines L and 7):** Utilizes Communications-Based Train Control (CBTC). CBTC tracks trains continuously via wayside zone controllers, transponders (RF beacons), and onboard wheel tachometers paired with Doppler radar, achieving moving-block resolution within sub-meter tolerances.
- **B Division (Legacy Lettered Lines B, D, N, Q, R, etc.):** Combines legacy track circuits, optical station stop sensors, and radio-frequency identification transponders reporting to the Interactive Train Register Activity Console (I-TRAC).

### Discretization in GTFS-RT
Despite the high spatial fidelity of CBTC internally, public-facing and internal GTFS-RT feed generators normalize all subway telemetry into uniform, discrete entity structures: `TripUpdate` and `VehiclePosition` messages refreshed on approximate 30-second cycles. Spatial progress is not emitted as coordinate pairs; instead, it is manifested through discrete updates to `VehiclePosition.current_status`—specifically `STOPPED_AT`, `INCOMING_AT`, and `IN_TRANSIT_TO`—accompanied by station-level arrival and departure predictions within `TripUpdate.StopTimeUpdate`.

When a train vacates a station, the NYCT feed drops the completed stop from the `StopTimeUpdate` array, causing the subsequent downstream station to become the head of the sequence. To construct continuous, visually realistic real-time positions along track geometries in `shapes.txt`, an intermediate software layer must snap discrete station sequence intervals to polyline geometries, compute continuous kinematic motion, and handle subsurface transmission artifacts.

### Comparison Across Signaling Infrastructures

| Signaling Dimension | A Division (ATS-A: Routes 1–6, S) | B Division CBTC (Routes L, 7) | B Division Legacy / Interlined (Routes B, D, N, Q, R) |
|:---|:---|:---|:---|
| **Sensing Technology** | Fixed-block AC track circuits and relay logic | Wayside RF transponders and carborne odometry | Relay PLCs, station beacons, and I-TRAC manual logs |
| **Spatial Resolution** | Fixed block boundaries (100–300 m) | Continuous moving-block internal; discretized for GTFS-RT | Quantized to interlockings and platform limits |
| **Feed Ingestion Cycle**| Polled snapshot every 30 seconds | Polled snapshot every 30 seconds | Polled snapshot every 30 seconds |
| **Protocol Extensions** | Full `NyctTripDescriptor` with assigned train IDs | Standard GTFS-RT with partial NYCT extensions | Heterogeneous; variable track and trip assignment flags |
| **Terminal Status** | Explicit `is_assigned` bit toggle by ATS dispatcher | Automated dispatch assignment via CBTC route init | Variable latency based on manual dispatcher punch |

---

## 2. Mathematical Formulation of Kinematic Progress and Polyline Geometry

A transit consist cannot instantaneously change its velocity. Utilizing simple linear interpolation where normalized progress is computed as $\lambda_{\text{linear}}(t) = \frac{t - t_{\text{dep}}}{t_{\text{arr}} - t_{\text{dep}}}$ induces severe visual and physical defects. Specifically, linear interpolation imposes an infinite acceleration impulse at the departure timestamp $t_{\text{dep}}$ and an infinite deceleration impulse upon arrival at $t_{\text{arr}}$, causing trains to start and stop abruptly on visual displays. Developing a continuous, smooth spatial interpolator requires projecting station platforms onto the polyline, calculating an acceleration-constrained kinematic motion profile, and applying status-aware boundary clamping.

```
Progress
  λ ^
1.0 |                                                ...---* (Arrival)
    |                                         ..---''   ..
    |                                   ...--''     ..''
    |                             ...--''       ..''
    |                       ...--''         ..''
    |                 ...--''           ..''  <--- Quintic Hermite / S-Curve
    |           ...--''             ..''           (Zero-jerk entry/exit)
    |     ...--''               ..''
0.0 *---''.................---''              <--- Raw Linear (Abrupt velocity jumps)
    +-------------------------------------------------------->
   t_dep                                                    t_arr
```

### Orthogonal Polyline Projection and Linear Referencing
The route path geometry obtained from `shapes.txt` is modeled as an ordered line string $\mathcal{L}$ of $M$ discrete Cartesian vertices in projected coordinates:
$$\mathcal{L} = \left\{ \mathbf{p}_1, \mathbf{p}_2, \dots, \mathbf{p}_M \right\}, \quad \mathbf{p}_k = (x_k, y_k) \in \mathbb{R}^2$$

Geographic coordinates $(\phi, \psi)$ representing latitude and longitude from `shapes.txt` and `stops.txt` are projected into local conformal coordinates, such as New York State Plane Long Island Zone (EPSG:2263, in meters) or localized equirectangular coordinates using reference latitude $\phi_0 \approx 40.7128^\circ \text{ N}$:
$$x = R \cdot (\psi - \psi_0) \cos\left(\frac{\phi + \phi_0}{2}\right), \quad y = R \cdot (\phi - \phi_0)$$

The cumulative polyline distance $D_k$ to vertex $k$ along $\mathcal{L}$ is defined as:
$$D_1 = 0, \quad D_k = D_{k-1} + \left\Vert \mathbf{p}_k - \mathbf{p}_{k-1} \right\Vert_2 \quad (k \ge 2)$$

Given a station platform centroid $\mathbf{s} = (x_s, y_s)$ from `stops.txt`, the orthogonal projection onto each segment $\mathbf{e}_k = \mathbf{p}_{k+1} - \mathbf{p}_k$ is determined by the projection scalar:
$$u_k = \frac{(\mathbf{s} - \mathbf{p}_k) \cdot \mathbf{e}_k}{\left\Vert \mathbf{e}_k \right\Vert_2^2}$$

Clamping the scalar to the segment boundaries via $\hat{u}_k = \max(0.0, \min(1.0, u_k))$ yields the nearest point on segment $k$:
$$\mathbf{q}_k = \mathbf{p}_k + \hat{u}_k \mathbf{e}_k$$

The optimal segment index $k^*$ minimizes Euclidean distance to the platform center:
$$k^* = \arg\min_k \left\Vert \mathbf{s} - \mathbf{q}_k \right\Vert_2$$

The absolute linear distance of the station platform along the polyline $\mathcal{L}$ is given by:
$$d_S = D_{k^*} + \left\Vert \mathbf{q}_{k^*} - \mathbf{p}_{k^*} \right\Vert_2$$

For a pair of consecutive stops $S_N$ and $S_{N+1}$, this projection yields cumulative distances $d_N$ and $d_{N+1}$. The inter-station run distance is $L = d_{N+1} - d_N$. Given departure time $t_{\text{dep}}$ at $S_N$ and estimated arrival time $t_{\text{arr}}$ at $S_{N+1}$, total transit duration is $T = t_{\text{arr}} - t_{\text{dep}}$. The elapsed duration at query time $t$ is $\Delta t = t - t_{\text{dep}}$, defining the normalized time parameter $\tau = \frac{\Delta t}{T} \in [0.0, 1.0]$.

### Analytical Trapezoidal Kinematic Model
A train accelerating out of a station platform, cruising at track speed, and executing service braking into a downstream station follows a trapezoidal velocity profile. Modern NYCT rolling stock (Kawasaki R160 and Bombardier R142 fleets) operates with:
- Service acceleration $a \approx 1.15 \text{ m/s}^2$ ($2.57 \text{ mph/s}$)
- Service braking deceleration $d \approx 1.25 \text{ m/s}^2$ ($2.80 \text{ mph/s}$)

Let $\alpha$ represent the combined kinematic acceleration-braking constant:
$$\alpha = \frac{1}{2}\left(\frac{1}{a} + \frac{1}{d}\right)$$

During inter-station transit, acceleration duration is $t_a = \frac{v_c}{a}$, deceleration duration is $t_d = \frac{v_c}{d}$, and cruising duration is $t_c = T - (t_a + t_d) = T - 2\alpha v_c$, where $v_c$ is cruising velocity. Total distance $L$ equates to the area under the velocity trapezoid:
$$L = \frac{1}{2} a t_a^2 + v_c t_c + \frac{1}{2} d t_d^2 = \frac{v_c^2}{2a} + v_c(T - 2\alpha v_c) + \frac{v_c^2}{2d} = v_c T - \alpha v_c^2$$

Rearranging terms generates a quadratic equation in $v_c$:
$$\alpha v_c^2 - T v_c + L = 0 \quad \implies \quad v_c = \frac{T - \sqrt{T^2 - 4\alpha L}}{2\alpha}$$

A real, non-negative cruising velocity exists if and only if:
$$T^2 \ge 4\alpha L \quad \implies \quad T \ge 2\sqrt{\alpha L}$$

When this condition is met and $t_c \ge 0$, cumulative distance traversed $s(\Delta t)$ is calculated piecewise across phases:
$$s(\Delta t) = \begin{cases} \frac{1}{2} a (\Delta t)^2 & 0 \le \Delta t < t_a \\ \frac{1}{2} a t_a^2 + v_c (\Delta t - t_a) & t_a \le \Delta t < t_a + t_c \\ L - \frac{1}{2} d (T - \Delta t)^2 & t_a + t_c \le \Delta t \le T \end{cases}$$

The kinematic progress parameter is evaluated as $\lambda_{\text{trap}}(\Delta t) = \frac{s(\Delta t)}{L}$.

### Polynomial S-Curve Fallback (Quintic Hermite Smootherstep)
When operational delays cause reported runtime $T < 2\sqrt{\alpha L}$, the quadratic discriminant becomes negative, meaning the train cannot traverse distance $L$ within time $T$ under nominal acceleration and braking parameters. Rather than reverting to unconstrained linear velocity, the interpolator falls back to a $C^2$-continuous Quintic Hermite polynomial curve (smootherstep):
$$\lambda_{\text{quint}}(\tau) = 6\tau^5 - 15\tau^4 + 10\tau^3, \quad \tau = \frac{\Delta t}{T} \in [0.0, 1.0]$$

Differentiating $\lambda_{\text{quint}}(\tau)$ confirms that boundary velocities and accelerations remain zero:
$$\frac{d\lambda_{\text{quint}}}{d\tau} = 30\tau^2(1 - \tau)^2, \quad \left. \frac{d\lambda}{d\tau} \right\vert_{\tau=0, 1} = 0, \quad \left. \frac{d^2\lambda}{d\tau^2} \right\vert_{\tau=0, 1} = 0$$

Peak velocity occurs precisely at midpoint $\tau = 0.5$, yielding $\left.\frac{d\lambda}{d\tau}\right|_{\tau=0.5} = 1.875$. Visual speed along the polyline never exceeds $1.875 \times \frac{L}{T}$, effectively dampening visual jumps.

### Status-Dependent Boundary Clamping
$$\lambda_{\text{final}}(t) = \begin{cases} 0.0 & \text{if } \text{status} = \text{STOPPED\_AT} \\ \min\left(\lambda(t), 0.85\right) & \text{if } \text{status} = \text{IN\_TRANSIT\_TO} \\ \max\left(0.85, \min\left(\lambda(t), 0.995\right)\right) & \text{if } \text{status} = \text{INCOMING\_AT} \\ 1.0 & \text{if } \text{status} = \text{STOPPED\_AT at } S_{N+1} \end{cases}$$

This ensures that a train flagged as `IN_TRANSIT_TO` does not drift past the home signal approach circuit ($\lambda = 0.85$) until wayside track circuits confirm ingress by emitting `INCOMING_AT` or `STOPPED_AT`.

---

## 3. Telemetry Anomaly Mitigation in Subsurface Rail Networks

| Anomaly State | Infrastructure Root Cause | Real-Time Telemetry Signature | Visual Failure Mode if Unhandled | Algorithmic Resolution |
|:---|:---|:---|:---|:---|
| **Terminal Origin Dwell** | Train staged at bumper block awaiting departure clearance. | `is_assigned: true`, `stop_sequence: 1`, `status: STOPPED_AT`. | Consist drifts out of terminal before actual physical dispatch. | Anchor $\lambda \equiv 0.0$ at terminal vertex until status transitions to `IN_TRANSIT_TO`. |
| **Station Platform Dwell Hold** | Passenger door obstructions, medical delays, terminal throttling. | `status: STOPPED_AT`, current time exceeds departure by $> 120\text{ s}$. | Telemetry predicts overdue departure; interpolator advances into tunnel. | Freeze at platform vertex $d_N$, set $\lambda \equiv 0.0$, transition to `HOLDING_STATION`. |
| **Mid-Tunnel Signal Stop** | Preceding consist occupying block; automatic signal at red. | `status: IN_TRANSIT_TO`, $t_{\text{arr}}$ repeatedly deferred in feed. | Consist glides through downstream station, then abruptly snaps back. | Decelerate and clamp progress at $\lambda = 0.85$; enter `HOLDING_MID_TUNNEL` state. |
| **Telemetry Drop / Stale Feed** | Network packet loss between relay room PLC and ATS gateway. | Feed header timestamp age exceeds $90\text{ s}$; update absent. | Consist runs on dead reckoning past destination into unmapped territory. | Freeze consist at last confirmed coordinate; transition state to `TELEMETRY_STALE`. |
| **Track Divergence / Reroute** | Tower operator switches consist from local to express track. | `actual_track` in `NyctStopTimeUpdate` differs from schedule. | Consist icon visually jumps across tracks or snaps to incorrect polyline. | Dynamically switch polyline geometry to match the assigned `actual_track` identifier. |

---

## 4. Algorithmic Specification: SubwayPositionInterpolator (C++20)

```cpp
#pragma once
#include <iostream>
#include <vector>
#include <string>
#include <cmath>
#include <algorithm>
#include <optional>
#include <chrono>
#include <memory>
#include <cassert>

namespace Derivee::Transit {

struct Point2D {
    double x{0.0};
    double y{0.0};

    [[nodiscard]] double distance_to(const Point2D& other) const noexcept {
        return std::hypot(x - other.x, y - other.y);
    }
};

struct PolylineVertex {
    Point2D point;
    double cumulative_distance{0.0};
};

enum class VisualState {
    BOARDING_TERMINAL,
    STOPPED_IN_STATION,
    HOLDING_STATION,
    TRANSITING_NOMINAL,
    APPROACHING_STATION,
    HOLDING_MID_TUNNEL,
    TELEMETRY_STALE
};

enum class GTFSVehicleStatus {
    INCOMING_AT = 0,
    STOPPED_AT = 1,
    IN_TRANSIT_TO = 2
};

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
};

struct ConsistSpatialEstimate {
    Point2D coordinates;
    double heading_radians{0.0};
    double linear_progress{0.0};
    VisualState visual_state{VisualState::STOPPED_IN_STATION};
    bool is_holding{false};
};

class SubwayPositionInterpolator {
public:
    static constexpr double DEFAULT_ACCEL = 1.15; // m/s^2 (~2.57 mph/s)
    static constexpr double DEFAULT_DECEL = 1.25; // m/s^2 (~2.80 mph/s)
    static constexpr double STALE_FEED_THRESHOLD_SEC = 90.0;
    static constexpr double STATION_HOLD_THRESHOLD_SEC = 120.0;
    static constexpr double APPROACH_PROGRESS_CEILING = 0.85;

    explicit SubwayPositionInterpolator(std::vector<Point2D> shape_points) {
        build_cumulative_geometry(std::move(shape_points));
    }

    [[nodiscard]] ConsistSpatialEstimate update(
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
            estimate.visual_state = VisualState::STOPPED_IN_STATION;
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
        return estimate;
    }

private:
    std::vector<PolylineVertex> geometry_;
    double total_shape_distance_{0.0};

    void build_cumulative_geometry(std::vector<Point2D> pts) {
        if (pts.empty()) return;
        
        geometry_.reserve(pts.size());
        double accum = 0.0;
        geometry_.push_back({pts.front(), 0.0});

        for (size_t i = 1; i < pts.size(); ++i) {
            accum += pts[i].distance_to(pts[i - 1]);
            geometry_.push_back({pts[i], accum});
        }
        total_shape_distance_ = accum;
    }

    [[nodiscard]] double solve_kinematic_progress(
        double elapsed_sec,
        double total_dur_sec,
        double distance_m,
        double a,
        double d
    ) const noexcept {
        if (elapsed_sec <= 0.0) return 0.0;
        if (elapsed_sec >= total_dur_sec) return 1.0;

        const double alpha = 0.5 * (1.0 / a + 1.0 / d);
        const double discriminant = (total_dur_sec * total_dur_sec) - (4.0 * alpha * distance_m);

        if (discriminant < 0.0) {
            const double tau = std::clamp(elapsed_sec / total_dur_sec, 0.0, 1.0);
            return (tau * tau * tau) * (tau * (tau * 6.0 - 15.0) + 10.0);
        }

        const double vc = (total_dur_sec - std::sqrt(discriminant)) / (2.0 * alpha);
        const double ta = vc / a;
        const double td = vc / d;
        const double tc = total_dur_sec - (ta + td);

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
            const double sa = 0.5 * a * ta * ta;
            const double sc = vc * tc;
            const double dt_brake = elapsed_sec - (ta + tc);
            s = sa + sc + (vc * dt_brake - 0.5 * d * dt_brake * dt_brake);
        }

        return std::clamp(s / distance_m, 0.0, 1.0);
    }

    [[nodiscard]] Point2D interpolate_point_at_distance(double d, double& out_heading) const noexcept {
        if (geometry_.empty()) return {0.0, 0.0};
        
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
            out_heading = (geometry_.size() > 1) 
                ? std::atan2(geometry_[1].point.x - geometry_[0].point.x, geometry_[1].point.y - geometry_[0].point.y)
                : 0.0;
            return geometry_.front().point;
        }

        if (it == geometry_.end()) {
            const size_t last_idx = geometry_.size() - 1;
            out_heading = (geometry_.size() > 1)
                ? std::atan2(geometry_[last_idx].point.x - geometry_[last_idx - 1].point.x,
                             geometry_[last_idx].point.y - geometry_[last_idx - 1].point.y)
                : 0.0;
            return geometry_.back().point;
        }

        const size_t idx1 = std::distance(geometry_.begin(), it);
        const size_t idx0 = idx1 - 1;
        const auto& v0 = geometry_[idx0];
        const auto& v1 = geometry_[idx1];

        const double seg_len = v1.cumulative_distance - v0.cumulative_distance;
        const double seg_mu = (seg_len > 0.0) ? (clamped_d - v0.cumulative_distance) / seg_len : 0.0;

        out_heading = std::atan2(v1.point.x - v0.point.x, v1.point.y - v0.point.y);

        return {
            v0.point.x + seg_mu * (v1.point.x - v0.point.x),
            v0.point.y + seg_mu * (v1.point.y - v0.point.y)
        };
    }
};

} // namespace Derivee::Transit
```
