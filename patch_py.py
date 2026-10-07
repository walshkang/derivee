import sys

with open('DeriveeNative/DeriveeCore/src/RaptorEngine.cpp', 'r') as f:
    content = f.read()

bike_logic = """
    // Bike Share Dynamic Transfers
    if (!bike_docks_.empty() && from_stop_id < stop_to_docks_.size()) {
        const auto& origin_docks = stop_to_docks_[from_stop_id];
        for (const auto& od : origin_docks) {
            const auto& origin_dock = bike_docks_[od.dock_idx];
            if (origin_dock.num_bikes_available == 0 && origin_dock.num_ebikes_available == 0) continue;

            float speed = origin_dock.num_ebikes_available > 0 ? 6.7056f : 3.57632f; // 15 mph vs 8 mph

            for (uint32_t dd_idx = 0; dd_idx < bike_docks_.size(); ++dd_idx) {
                if (dd_idx == od.dock_idx) continue;
                const auto& dest_dock = bike_docks_[dd_idx];
                if (dest_dock.num_docks_available == 0) continue;

                float dist_m = haversine_m(origin_dock.latitude, origin_dock.longitude, dest_dock.latitude, dest_dock.longitude);
                uint32_t bike_time = static_cast<uint32_t>(dist_m / speed);
                uint32_t arr_at_dest_dock = current_arrival_sec + od.duration_sec + bike_time;

                for (const auto& ds : dock_to_stops_[dd_idx]) {
                    uint32_t target_stop = ds.stop_id;
                    if (!is_stop_active(target_stop)) continue;

                    uint32_t tr_arrival = arr_at_dest_dock + ds.duration_sec;

                    if (tr_arrival >= best_tau[target_stop] && tr_arrival >= tau_k[target_stop]) continue;

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
                            od.distance_meters + static_cast<uint16_t>(dist_m) + ds.distance_meters,
                            true
                        );
                        marked_stops_next.push_back(target_stop);
                    }
                }
            }
        }
    }
}
"""

content = content.replace("""            marked_stops_next.push_back(target_stop);
        }
    }
}""", """            marked_stops_next.push_back(target_stop);
        }
    }""" + bike_logic, 1)

with open('DeriveeNative/DeriveeCore/src/RaptorEngine.cpp', 'w') as f:
    f.write(content)

