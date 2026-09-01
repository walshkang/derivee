#pragma once

#include "ObserverFormat.hpp"
#include <cstdint>
#include <cstddef>
#include <stdexcept>
#include <string>

#if __has_include(<span>) && (defined(__cpp_lib_span) || (defined(__cplusplus) && __cplusplus >= 202002L))
#include <span>
#else
namespace std {
template <typename T>
class span {
private:
    const T* ptr_ = nullptr;
    size_t size_ = 0;
public:
    constexpr span() noexcept : ptr_(nullptr), size_(0) {}
    constexpr span(const T* ptr, size_t size) noexcept : ptr_(ptr), size_(size) {}
    [[nodiscard]] constexpr const T* data() const noexcept { return ptr_; }
    [[nodiscard]] constexpr size_t size() const noexcept { return size_; }
    [[nodiscard]] constexpr bool empty() const noexcept { return size_ == 0; }
    [[nodiscard]] constexpr const T& operator[](size_t idx) const noexcept { return ptr_[idx]; }
    [[nodiscard]] constexpr const T* begin() const noexcept { return ptr_; }
    [[nodiscard]] constexpr const T* end() const noexcept { return ptr_ + size_; }
};
}
#endif

namespace observer::engine {

class BinaryPayloadView {
private:
    const uint8_t* buffer_ptr_ = nullptr;
    size_t length_bytes_ = 0;
    const format::MasterHeader* header_ = nullptr;

public:
    BinaryPayloadView() noexcept = default;

    BinaryPayloadView(const uint8_t* buffer_ptr, size_t length_bytes, uint32_t expected_magic, uint32_t expected_version)
        : buffer_ptr_(buffer_ptr), length_bytes_(length_bytes) {
        
        if (!buffer_ptr_ || length_bytes_ < sizeof(format::MasterHeader)) {
            throw std::runtime_error("Invalid buffer pointer or size smaller than MasterHeader requirement");
        }

        // 1. Pointer alignment validation
        auto raw_ptr = reinterpret_cast<uintptr_t>(buffer_ptr_);
        if (raw_ptr % alignof(format::MasterHeader) != 0) {
            throw std::runtime_error("Buffer address failed 64-byte alignment check");
        }

        header_ = reinterpret_cast<const format::MasterHeader*>(buffer_ptr_);

        // 2. Validate Magic & Header Metadata
        if (header_->magic != expected_magic) {
            throw std::runtime_error("Magic identifier validation failed");
        }
        if (header_->schema_version != expected_version) {
            throw std::runtime_error("Schema version mismatch detected");
        }
        if (header_->endian_marker != format::ENDIAN_MARKER) {
            throw std::runtime_error("Host endianness mismatch detected");
        }
        if (header_->header_size != sizeof(format::MasterHeader)) {
            throw std::runtime_error("Malformed header size parameter");
        }

        // 3. Strict Bounds Checking against physical file size
        if (header_->file_size > length_bytes_) {
            throw std::runtime_error("Header reports file_size larger than physical buffer");
        }
    }

    [[nodiscard]] bool is_valid() const noexcept {
        return header_ != nullptr && buffer_ptr_ != nullptr;
    }

    [[nodiscard]] const format::MasterHeader* header() const noexcept {
        return header_;
    }

    [[nodiscard]] size_t size() const noexcept {
        return length_bytes_;
    }

    // Typed Section View Generation with Bounds Verification
    template <typename T>
    [[nodiscard]] std::span<const T> get_section_span(size_t section_index) const {
        if (!header_ || section_index >= header_->num_sections) {
            throw std::out_of_range("Requested section_index exceeds TOC section bounds");
        }

        const auto& desc = header_->toc[section_index];
        
        // Overflow safety check on offset and size sum
        if (desc.offset + desc.size_bytes > header_->file_size) {
            throw std::out_of_range("TOC section offset + length exceeds physical binary size");
        }

        // Alignment validation for target type
        if (desc.offset % alignof(T) != 0) {
            throw std::runtime_error("Section payload offset fails target type alignment requirement");
        }

        // Element capacity validation
        if (desc.size_bytes < desc.item_count * sizeof(T)) {
            throw std::runtime_error("Section size smaller than item_count * sizeof(T)");
        }

        const T* typed_ptr = reinterpret_cast<const T*>(buffer_ptr_ + desc.offset);
        return std::span<const T>(typed_ptr, static_cast<size_t>(desc.item_count));
    }
};

} // namespace observer::engine
