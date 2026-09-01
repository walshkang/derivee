#pragma once

#include "TimetableStructs.hpp"
#include "ObserverFormat.hpp"
#include "BinaryPayloadView.hpp"
#include <vector>
#include <unordered_map>
#include <cstdint>
#include <memory>

class RaptorEngine {
private:
    const uint8_t* timetable_blob_ptr_ = nullptr;
    size_t timetable_blob_size_ = 0;
    bool is_loaded_ = false;
    std::unordered_map<uint32_t, int32_t> realtime_delays_;

public:
    RaptorEngine();
    ~RaptorEngine();

    // Disable copy constructors to prevent unintended engine duplicates
    RaptorEngine(const RaptorEngine&) = delete;
    RaptorEngine& operator=(const RaptorEngine&) = delete;

    // Enable move semantics
    RaptorEngine(RaptorEngine&& other) noexcept;
    RaptorEngine& operator=(RaptorEngine&& other) noexcept;

    // Load binary timetable blob directly from memory-mapped disk buffer
    bool load_timetable_blob(const uint8_t* buffer_ptr, size_t length_bytes) noexcept;

    // Apply real-time delay updates to dynamic trip arrays
    void update_realtime_delay(uint32_t trip_id, int32_t delay_seconds) noexcept;

    // Query real-time delay for a trip
    [[nodiscard]] int32_t get_realtime_delay(uint32_t trip_id) const noexcept;

    // Execute multi-criteria journey search
    [[nodiscard]] std::vector<JourneySegment> compute_journey(
        const QueryParams& params) const noexcept;

    // Direct span access to outgoing transfers
    [[nodiscard]] std::span<const Transfer> get_outgoing_transfers(
        uint32_t stop_id) const noexcept;

    [[nodiscard]] bool is_loaded() const noexcept { return is_loaded_; }
    [[nodiscard]] size_t registered_delays_count() const noexcept { return realtime_delays_.size(); }
};
