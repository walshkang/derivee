#include "RaptorEngine.hpp"
#include <cstring>
#include <algorithm>

RaptorEngine::RaptorEngine() = default;

RaptorEngine::~RaptorEngine() = default;

RaptorEngine::RaptorEngine(RaptorEngine&& other) noexcept
    : timetable_blob_ptr_(other.timetable_blob_ptr_),
      timetable_blob_size_(other.timetable_blob_size_),
      is_loaded_(other.is_loaded_),
      realtime_delays_(std::move(other.realtime_delays_)) {
    other.timetable_blob_ptr_ = nullptr;
    other.timetable_blob_size_ = 0;
    other.is_loaded_ = false;
}

RaptorEngine& RaptorEngine::operator=(RaptorEngine&& other) noexcept {
    if (this != &other) {
        timetable_blob_ptr_ = other.timetable_blob_ptr_;
        timetable_blob_size_ = other.timetable_blob_size_;
        is_loaded_ = other.is_loaded_;
        realtime_delays_ = std::move(other.realtime_delays_);

        other.timetable_blob_ptr_ = nullptr;
        other.timetable_blob_size_ = 0;
        other.is_loaded_ = false;
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
        timetable_blob_ptr_ = buffer_ptr;
        timetable_blob_size_ = length_bytes;
        is_loaded_ = true;
        return true;
    } catch (...) {
        timetable_blob_ptr_ = nullptr;
        timetable_blob_size_ = 0;
        is_loaded_ = false;
        return false;
    }
}

void RaptorEngine::update_realtime_delay(uint32_t trip_id, int32_t delay_seconds) noexcept {
    realtime_delays_[trip_id] = delay_seconds;
}

int32_t RaptorEngine::get_realtime_delay(uint32_t trip_id) const noexcept {
    auto it = realtime_delays_.find(trip_id);
    if (it != realtime_delays_.end()) {
        return it->second;
    }
    return 0;
}

std::vector<JourneySegment> RaptorEngine::compute_journey(const QueryParams& params) const noexcept {
    std::vector<JourneySegment> results;

    if (params.origin_stop_id == params.destination_stop_id) {
        return results;
    }

    // Baseline scaffold result for testing interop bridge
    // Wave N-B.2 will replace this with full multi-round RAPTOR scanning loop
    uint32_t dep = params.departure_timestamp;
    uint32_t arr = dep + 600; // 10 minutes nominal travel time

    results.emplace_back(
        params.origin_stop_id,
        params.destination_stop_id,
        1001, // synthetic trip_id
        dep,
        arr,
        1,    // route_id
        0     // transfer_distance_m
    );

    return results;
}

std::span<const Transfer> RaptorEngine::get_outgoing_transfers(uint32_t /*stop_id*/) const noexcept {
    return {};
}
