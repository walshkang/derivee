#pragma once

#include "TimetableStructs.hpp"
#include "BinaryPayloadView.hpp"
#include <cstdint>
#include <cstddef>
#include <vector>
#include <functional>
#include <stdexcept>
#include <algorithm>

#pragma pack(push, 1)
struct UltraCsrHeader {
    uint32_t magic_bytes;     // 0x554C5452 ("ULTR")
    uint32_t version;         // Format version = 1
    uint32_t num_stops;       // Number of transit stops (S)
    uint64_t total_shortcuts; // Total serialized shortcuts (N)
    uint32_t tau_max;         // Bounded cutoff limit in seconds
    uint32_t reserved[2];     // Zero-padded alignment space (8B)

    constexpr UltraCsrHeader() noexcept
        : magic_bytes(0x554C5452), version(1), num_stops(0), total_shortcuts(0), tau_max(900), reserved{0, 0} {}
};
#pragma pack(pop)
static_assert(sizeof(UltraCsrHeader) == 32, "UltraCsrHeader layout must be exactly 32 bytes.");

class ULTRADataStore {
private:
    const uint8_t* raw_blob_ptr_ = nullptr;
    size_t raw_blob_size_ = 0;
    bool is_loaded_ = false;

    UltraCsrHeader header_{};
    std::span<const uint64_t> indptr_{};
    std::span<const uint32_t> target_stops_{};
    std::span<const uint16_t> durations_sec_{};
    std::span<const uint8_t> flags_{}; // Optional accessibility flags

public:
    ULTRADataStore() noexcept = default;

    bool load_ultra_blob(const uint8_t* buffer_ptr, size_t length_bytes) noexcept {
        if (!buffer_ptr || length_bytes < sizeof(UltraCsrHeader)) {
            is_loaded_ = false;
            return false;
        }

        auto raw_header = reinterpret_cast<const UltraCsrHeader*>(buffer_ptr);
        if (raw_header->magic_bytes != 0x554C5452 || raw_header->version != 1) {
            is_loaded_ = false;
            return false;
        }

        uint32_t s = raw_header->num_stops;
        uint64_t n = raw_header->total_shortcuts;

        size_t expected_indptr_bytes = (static_cast<size_t>(s) + 1) * sizeof(uint64_t);
        size_t expected_targets_bytes = static_cast<size_t>(n) * sizeof(uint32_t);
        size_t expected_durations_bytes = static_cast<size_t>(n) * sizeof(uint16_t);

        size_t offset_indptr = sizeof(UltraCsrHeader);
        size_t offset_targets = offset_indptr + expected_indptr_bytes;
        size_t offset_durations = offset_targets + expected_targets_bytes;
        size_t min_total_size = offset_durations + expected_durations_bytes;

        if (length_bytes < min_total_size) {
            is_loaded_ = false;
            return false;
        }

        header_ = *raw_header;
        indptr_ = std::span<const uint64_t>(
            reinterpret_cast<const uint64_t*>(buffer_ptr + offset_indptr),
            s + 1
        );
        target_stops_ = std::span<const uint32_t>(
            reinterpret_cast<const uint32_t*>(buffer_ptr + offset_targets),
            static_cast<size_t>(n)
        );
        durations_sec_ = std::span<const uint16_t>(
            reinterpret_cast<const uint16_t*>(buffer_ptr + offset_durations),
            static_cast<size_t>(n)
        );

        // Optional flags array if buffer has extra payload
        size_t offset_flags = offset_durations + expected_durations_bytes;
        size_t expected_flags_bytes = static_cast<size_t>(n) * sizeof(uint8_t);
        if (length_bytes >= offset_flags + expected_flags_bytes) {
            flags_ = std::span<const uint8_t>(
                buffer_ptr + offset_flags,
                static_cast<size_t>(n)
            );
        } else {
            flags_ = {};
        }

        raw_blob_ptr_ = buffer_ptr;
        raw_blob_size_ = length_bytes;
        is_loaded_ = true;
        return true;
    }

    [[nodiscard]] bool is_loaded() const noexcept { return is_loaded_; }
    [[nodiscard]] uint32_t num_stops() const noexcept { return header_.num_stops; }
    [[nodiscard]] uint64_t total_shortcuts() const noexcept { return header_.total_shortcuts; }

    // Relax transfers for a given marked stop
    template <typename StopActivePredicate>
    void RelaxTransfers(
        uint32_t from_stop_id,
        uint32_t current_arrival_sec,
        uint16_t query_flags,
        StopActivePredicate&& is_stop_active,
        std::span<uint32_t> tau_k,
        std::span<uint32_t> best_tau,
        std::span<ParentPointer> parents,
        std::vector<uint32_t>& marked_stops_next
    ) const noexcept {
        if (!is_loaded_ || from_stop_id >= header_.num_stops) {
            return;
        }

        uint64_t start_idx = indptr_[from_stop_id];
        uint64_t end_idx = indptr_[from_stop_id + 1];

        bool require_wheelchair = (query_flags & ROUTING_FLAG_WHEELCHAIR_ACCESSIBLE) != 0;

        for (uint64_t i = start_idx; i < end_idx; ++i) {
            uint32_t target_stop = target_stops_[i];
            uint16_t duration = durations_sec_[i];

            // Wheelchair filtering
            if (require_wheelchair && !flags_.empty()) {
                uint8_t flag = flags_[i];
                if ((flag & ROUTING_FLAG_WHEELCHAIR_ACCESSIBLE) == 0) {
                    continue;
                }
            }

            // Check if target stop is disrupted
            if (!is_stop_active(target_stop)) {
                continue;
            }

            uint32_t transfer_arrival = current_arrival_sec + duration;

            // Early pruning check
            if (transfer_arrival >= best_tau[target_stop] && transfer_arrival >= tau_k[target_stop]) {
                continue;
            }

            // Relaxation improvement
            if (transfer_arrival < best_tau[target_stop]) {
                best_tau[target_stop] = transfer_arrival;
            }
            if (transfer_arrival < tau_k[target_stop]) {
                tau_k[target_stop] = transfer_arrival;
                parents[target_stop] = ParentPointer(
                    from_stop_id,
                    0, // trip_id = 0 represents transfer edge
                    current_arrival_sec,
                    transfer_arrival,
                    0,
                    static_cast<uint16_t>(duration * 1.3f), // Approx distance in meters (~1.3 m/s)
                    true
                );
                marked_stops_next.push_back(target_stop);
            }
        }
    }
};
