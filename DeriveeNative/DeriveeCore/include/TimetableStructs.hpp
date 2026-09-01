#pragma once

#include <cstdint>
#include <type_traits>

#pragma pack(push, 1)

// StopTime Struct: Represents an arrival/departure event at a specific stop (12 Bytes)
struct StopTime {
    uint32_t arrival_time_sec;    // Seconds relative to daily epoch (supports > 86400)
    uint32_t departure_time_sec;  // Departure time in seconds relative to daily epoch
    uint32_t stop_id;             // 32-bit index into global contiguous Stop array

    constexpr StopTime() noexcept 
        : arrival_time_sec(0), departure_time_sec(0), stop_id(0) {}
        
    constexpr StopTime(uint32_t arr, uint32_t dep, uint32_t stop) noexcept
        : arrival_time_sec(arr), departure_time_sec(dep), stop_id(stop) {}
};
static_assert(sizeof(StopTime) == 12, "StopTime layout must be exactly 12 bytes");

// Trip Struct: Represents an individual vehicle journey (8 Bytes)
struct Trip {
    uint32_t stop_times_offset;   // Index offset into global contiguous StopTime array
    uint16_t stop_times_count;    // Number of stops served by this trip
    uint16_t service_id;          // Bitmask / ID for calendar service operational mask

    constexpr Trip() noexcept 
        : stop_times_offset(0), stop_times_count(0), service_id(0) {}

    constexpr Trip(uint32_t offset, uint16_t count, uint16_t service) noexcept
        : stop_times_offset(offset), stop_times_count(count), service_id(service) {}
};
static_assert(sizeof(Trip) == 8, "Trip layout must be exactly 8 bytes");

// Route Struct: Groups trips operating on identical stop sequences (12 Bytes)
struct Route {
    uint32_t trips_offset;        // Index offset into global contiguous Trip array
    uint32_t route_stops_offset;  // Index offset into global Route-Stops index array
    uint16_t trip_count;          // Total number of trips scheduled on this route
    uint16_t stop_count;          // Number of stops along this route sequence

    constexpr Route() noexcept 
        : trips_offset(0), route_stops_offset(0), trip_count(0), stop_count(0) {}

    constexpr Route(uint32_t trips_off, uint32_t stops_off, uint16_t trips_cnt, uint16_t stops_cnt) noexcept
        : trips_offset(trips_off), route_stops_offset(stops_off), trip_count(trips_cnt), stop_count(stops_cnt) {}
};
static_assert(sizeof(Route) == 12, "Route layout must be exactly 12 bytes");

// Stop Struct: Represents a physical station or transit stop (20 Bytes)
struct Stop {
    float latitude;               // IEEE 754 32-bit floating point coordinate
    float longitude;              // IEEE 754 32-bit floating point coordinate
    uint32_t routes_offset;       // Index offset into global Stop-Routes inverted index
    uint32_t transfers_offset;    // Index offset into global Transfer CSR array
    uint16_t route_count;         // Number of transit routes serving this stop
    uint16_t transfer_count;      // Number of outgoing ULTRA transfer shortcuts

    constexpr Stop() noexcept 
        : latitude(0.0f), longitude(0.0f), routes_offset(0), 
          transfers_offset(0), route_count(0), transfer_count(0) {}

    constexpr Stop(float lat, float lon, uint32_t routes_off, uint32_t transfers_off, uint16_t routes_cnt, uint16_t transfers_cnt) noexcept
        : latitude(lat), longitude(lon), routes_offset(routes_off),
          transfers_offset(transfers_off), route_count(routes_cnt), transfer_count(transfers_cnt) {}
};
static_assert(sizeof(Stop) == 20, "Stop layout must be exactly 20 bytes");

// Transfer Struct: Compressed Sparse Row outgoing transfer edge (8 Bytes)
struct Transfer {
    uint32_t target_stop_id;      // 32-bit index to destination stop
    uint16_t duration_sec;        // Walking / transfer duration in seconds
    uint16_t distance_meters;     // Physical distance in meters

    constexpr Transfer() noexcept 
        : target_stop_id(0), duration_sec(0), distance_meters(0) {}

    constexpr Transfer(uint32_t target, uint16_t duration, uint16_t distance) noexcept
        : target_stop_id(target), duration_sec(duration), distance_meters(distance) {}
};
static_assert(sizeof(Transfer) == 8, "Transfer layout must be exactly 8 bytes");

// StochasticWeight: Quantized expected wait time and variance penalty per (DoW x Hour) slot (4 Bytes)
struct StochasticWeight {
    uint16_t expected_wait_sec; // Expected wait time E[wait] = h/2 + sigma^2/(2h) in seconds
    uint16_t variance_penalty;  // Quantized variance risk score (0-1000)

    constexpr StochasticWeight() noexcept 
        : expected_wait_sec(0), variance_penalty(0) {}

    constexpr StochasticWeight(uint16_t wait, uint16_t penalty) noexcept
        : expected_wait_sec(wait), variance_penalty(penalty) {}
};
static_assert(sizeof(StochasticWeight) == 4, "StochasticWeight layout must be exactly 4 bytes");

// JourneySegment: Represents an individual transit or transfer leg in a computed route (22 Bytes)
struct JourneySegment {
    uint32_t board_stop_id;
    uint32_t exit_stop_id;
    uint32_t trip_id;
    uint32_t departure_time;
    uint32_t arrival_time;
    uint16_t route_id;
    uint16_t transfer_distance_m;

    constexpr JourneySegment() noexcept
        : board_stop_id(0), exit_stop_id(0), trip_id(0),
          departure_time(0), arrival_time(0), route_id(0), transfer_distance_m(0) {}

    constexpr JourneySegment(uint32_t board, uint32_t exit, uint32_t trip,
                             uint32_t dep, uint32_t arr, uint16_t route, uint16_t dist) noexcept
        : board_stop_id(board), exit_stop_id(exit), trip_id(trip),
          departure_time(dep), arrival_time(arr), route_id(route), transfer_distance_m(dist) {}
};
static_assert(sizeof(JourneySegment) == 24, "JourneySegment layout must be exactly 24 bytes");

// Routing Flag Constants
constexpr uint16_t ROUTING_FLAG_NONE                  = 0;
constexpr uint16_t ROUTING_FLAG_WHEELCHAIR_ACCESSIBLE = 1 << 0;
constexpr uint16_t ROUTING_FLAG_AVOID_TRANSFERS       = 1 << 1;

#pragma pack(pop)

struct QueryParams {
    uint32_t origin_stop_id;
    uint32_t destination_stop_id;
    uint32_t departure_timestamp;
    uint16_t max_transfers;
    uint16_t flags;

    constexpr QueryParams() noexcept
        : origin_stop_id(0), destination_stop_id(0), departure_timestamp(0), max_transfers(4), flags(ROUTING_FLAG_NONE) {}

    constexpr QueryParams(uint32_t origin, uint32_t dest, uint32_t dep, uint16_t max_t) noexcept
        : origin_stop_id(origin), destination_stop_id(dest), departure_timestamp(dep), max_transfers(max_t), flags(ROUTING_FLAG_NONE) {}

    constexpr QueryParams(uint32_t origin, uint32_t dest, uint32_t dep, uint16_t max_t, uint16_t f) noexcept
        : origin_stop_id(origin), destination_stop_id(dest), departure_timestamp(dep), max_transfers(max_t), flags(f) {}
};

struct ParentPointer {
    uint32_t from_stop_id = 0;
    uint32_t trip_id = 0;        // 0 for transfer edge
    uint32_t departure_time = 0;
    uint32_t arrival_time = 0;
    uint16_t route_id = 0;
    uint16_t transfer_distance_m = 0;
    bool is_transfer = false;

    constexpr ParentPointer() noexcept = default;

    constexpr ParentPointer(uint32_t from_stop, uint32_t trip, uint32_t dep, uint32_t arr,
                          uint16_t route, uint16_t dist, bool transfer) noexcept
        : from_stop_id(from_stop), trip_id(trip), departure_time(dep), arrival_time(arr),
          route_id(route), transfer_distance_m(dist), is_transfer(transfer) {}
};

struct ParetoLabel {
    uint32_t arrival_time;      // Criterion 1: Earliest Arrival Time (seconds)
    uint16_t transfer_count;    // Criterion 2: Number of Transfers
    uint16_t walk_distance;     // Criterion 3: Total Walking Distance (meters)
    uint16_t reliability_risk;  // Criterion 4: Historical Reliability Risk Score (0-1000)

    constexpr ParetoLabel() noexcept
        : arrival_time(0), transfer_count(0), walk_distance(0), reliability_risk(0) {}

    constexpr ParetoLabel(uint32_t arr, uint16_t transfers, uint16_t walk, uint16_t risk) noexcept
        : arrival_time(arr), transfer_count(transfers), walk_distance(walk), reliability_risk(risk) {}

    // Inline Pareto Dominance Check
    [[nodiscard]] inline bool dominates(const ParetoLabel& o) const noexcept {
        return (arrival_time <= o.arrival_time) &&
               (transfer_count <= o.transfer_count) &&
               (walk_distance <= o.walk_distance) &&
               (reliability_risk <= o.reliability_risk) &&
               (arrival_time < o.arrival_time || transfer_count < o.transfer_count ||
                walk_distance < o.walk_distance || reliability_risk < o.reliability_risk);
    }
};
