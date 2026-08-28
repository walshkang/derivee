# Zero-Copy Binary File Header Format Specification for Apple Silicon ARM64

## 1. Architectural Foundation & Memory Alignment Mechanics

Low-latency routing engines operating on spatial-temporal networks demand predictable, microsecond-level data access. In the Observer backend payload pipeline, binary assets (`timetable.bin`, `ultra_transfers.csr`, and `walk_graph.bin`) are serialized on Linux ARM64 build servers inside compressed payloads (`.pack.zst`) and mapped directly into host virtual address space on iOS client devices via `mmap` system calls.

Achieving true zero-copy deserialization requires that the in-memory byte representation on disk maps identically to C++20 object representations consumed by the routing algorithm, eliminating parsing overhead, heap allocations, and pointer swizzling.

### Dual Alignment Granularities on Apple Silicon ARM64

Native performance engineering on Apple Silicon ARM64 architectures requires satisfying two distinct hardware alignment thresholds simultaneously:
- **Virtual Memory Page Boundaries (16 KiB / 16,384 Bytes / `0x4000`):** Unlike standard x86-64 architectures and conventional 4 KiB Linux ARM64 kernel builds, Apple Silicon hardware (M-series and A-series processors) operates on a 16 KiB translation granule enforced by the Memory Management Unit (MMU) and DART (Device Address Resolution Table) IOMMU. When memory-mapping binary assets or sharing mapped regions with hardware subsystems—such as Metal GPU compute buffers using `makeBuffer(bytesNoCopy:length:)`—the starting file offset of any mmapped section must strictly align to 16 KiB boundaries. Violating 16 KiB alignment causes kernel memory loader failures, segmentation faults, or forces costly intermediate kernel memory copies.
- **CPU Cache Line Granularity (64 Bytes):** The L1 and L2 data cache subsystems of ARM64 cores fetch and invalidate memory in 64-byte lines. If a fixed-size entity structure straddles a 64-byte line, execution units must issue two separate memory bus transactions to load a single logical struct. Aligning fixed-size structural elements and internal payload offsets to 64-byte boundaries (`alignas(64)`) eliminates split-cache-line penalties, maximizing cache hit rates during high-frequency graph traversal loops.

| Memory Layer | Boundary Alignment | Hardware Mechanism | Failure Mode / Penalty |
|:---|:---:|:---|:---|
| **Virtual Memory Baseline** | 16 KiB (`0x4000`) | MMU / DART IOMMU Translation Granule | `mmap` allocation failure, `SIGSEGV`, or kernel copy fallback |
| **CPU Cache Line** | 64 Bytes (`0x0040`) | L1/L2 Data Cache Line Interleave | Split-cache read penalties, instruction stall during traversal |
| **Double-Word Integer** | 8 Bytes (`0x0008`) | ARM64 64-Bit Register Load (`LDR x0`) | Hardware bus fixup overhead or unaligned access fault |
| **Single-Word Integer** | 4 Bytes (`0x0004`) | ARM64 32-Bit Register Load (`LDR w0`) | Misaligned instruction fetch or micro-architectural stall |

### Eliminating Pointer Swizzling via Offset Indirection

Traditional dynamic structures rely on absolute 64-bit pointers to link memory nodes. When mapped into host memory via `mmap`, absolute pointers become invalid because the operating system kernel maps the binary at a non-deterministic virtual base address. Converting raw file pointers to host virtual address pointers at runtime ("pointer swizzling") requires mutating mapped memory pages. This mutation triggers Copy-on-Write (CoW) page faults, corrupting shared memory state, allocating physical RAM, and invalidating the kernel's read-only page cache.

To preserve zero-copy invariants, all graph relationships within `timetable.bin`, `ultra_transfers.csr`, and `walk_graph.bin` reject absolute pointers entirely. Inter-entity connections are modeled exclusively through array indices (e.g., `uint32_t` stop indices) or byte offsets relative to section baselines (`uint32_t` or `uint64_t`). Mapped pages remain completely read-only (`PROT_READ`), allowing multiple concurrent routing worker threads to share identical physical RAM frames across process boundaries without memory growth.

---

## 2. Universal 128-Byte Binary Header Layout Specification

Every generated binary asset encapsulates a fixed 128-byte header aligned to a 64-byte cache-line boundary. The header encodes binary identification, schema compatibility metadata, endianness markers, integrity checksums, and a dynamic Table of Contents (TOC) describing internal payload section offsets.

```
Universal 128-Byte Binary Master Header:
┌─────────────────────────────────────────────────────────────────────────────┐
│ 0x00: magic (u32)        │ 0x04: schema_version (u32)                       │
│ 0x08: endian_marker (u32)│ 0x0C: header_size = 128 (u32)                    │
├─────────────────────────────────────────────────────────────────────────────┤
│ 0x10: file_size (u64)                                                       │
│ 0x18: checksum_xxh64 (u64)                                                  │
├─────────────────────────────────────────────────────────────────────────────┤
│ 0x20: num_sections (u32) │ 0x24: flags (u32)                                │
├─────────────────────────────────────────────────────────────────────────────┤
│ 0x28: toc[0] (SectionDesc: offset u64, size_bytes u64, item_count u64 = 24B)│
│ 0x40: toc[1] (SectionDesc: offset u64, size_bytes u64, item_count u64 = 24B)│
│ 0x58: toc[2] (SectionDesc: offset u64, size_bytes u64, item_count u64 = 24B)│
│ 0x70: toc[3] (SectionDesc: offset u64, size_bytes u64, item_count u64 = 24B)│
└─────────────────────────────────────────────────────────────────────────────┘
```

### Header Layout Specification

| Byte Offset | Field Identifier | Type | Alignment | Description & Validation Target |
|:---|:---|:---|:---:|:---|
| `0x00 - 0x03` | `magic` | `uint32_t` | 4 Bytes | Asset identification constant (`DRV1`, `UTRA`, `WALK`) |
| `0x04 - 0x07` | `schema_version` | `uint32_t` | 4 Bytes | Binary schema revision. Must match client compilation version |
| `0x08 - 0x0B` | `endian_marker` | `uint32_t` | 4 Bytes | Set strictly to `0x01020304`. Validates host endianness match |
| `0x0C - 0x0F` | `header_size` | `uint32_t` | 4 Bytes | Total header size in bytes. Strictly set to `128` (`0x80`) |
| `0x10 - 0x17` | `file_size` | `uint64_t` | 8 Bytes | Total binary payload byte size including header and padding |
| `0x18 - 0x1F` | `checksum_xxh64`| `uint64_t` | 8 Bytes | 64-bit hash (XXH64) computed over all bytes following header |
| `0x20 - 0x23` | `num_sections` | `uint32_t` | 4 Bytes | Number of active section descriptors in TOC (Maximum 4) |
| `0x24 - 0x27` | `flags` | `uint32_t` | 4 Bytes | Bitmask reserved for runtime asset flags |
| `0x28 - 0x3F` | `toc[0]` | `SectionDesc`| 8 Bytes | Section 0 descriptor (`offset`, `size_bytes`, `item_count`) |
| `0x40 - 0x57` | `toc[1]` | `SectionDesc`| 8 Bytes | Section 1 descriptor (`offset`, `size_bytes`, `item_count`) |
| `0x58 - 0x6F` | `toc[2]` | `SectionDesc`| 8 Bytes | Section 2 descriptor (`offset`, `size_bytes`, `item_count`) |
| `0x70 - 0x87` | `toc[3]` | `SectionDesc`| 8 Bytes | Section 3 descriptor (`offset`, `size_bytes`, `item_count`) |

### Table of Contents (TOC) Section Descriptor Layout
Each payload section is indexed by a 24-byte `SectionDesc` structure:

| Byte Offset | Field Identifier | Type | Alignment | Description |
|:---|:---|:---|:---:|:---|
| `0x00 - 0x07` | `offset` | `uint64_t` | 8 Bytes | Absolute byte offset from file baseline (64B or 16 KiB aligned) |
| `0x08 - 0x0F` | `size_bytes` | `uint64_t` | 8 Bytes | Raw payload byte size excluding trailing alignment padding |
| `0x10 - 0x17` | `item_count` | `uint64_t` | 8 Bytes | Total element count contained within typed section array |

---

## 3. Cross-Platform Compilation Compatibility (C++20 & Go)

To guarantee byte-level binary compatibility between Linux ARM64 (Go serializer) and iOS ARM64 (C++20 reader), all structural definitions adhere to three structural rules:
1. **Strict Monotonic Size Ordering:** Fields within structs are ordered by descending scalar type size: 64-bit types (`uint64_t`, `double`), followed by 32-bit types (`uint32_t`, `float`), 16-bit types (`uint16_t`), and finally 8-bit types (`uint8_t`, `bool`).
2. **Explicit Padding Fields:** Any structural gap required to align a field to its natural type size boundary is explicitly declared as a reserved padding field (e.g., `uint32_t _reserved`) in both Go and C++ declarations.
3. **Rejection of Packed Compiler Directives (`#pragma pack(1)`):** While `#pragma pack(push, 1)` forces zero byte gaps, it unaligns 32-bit and 64-bit integers on non-4-byte boundaries. Accessing unaligned integers on ARM64 architectures degrades CPU execution throughput by forcing hardware bus fixup routines or triggering fault traps. Native explicit alignment is preserved across all structural types.

### Native Structural Declarations (`ObserverFormat.hpp`)

```cpp
#pragma once

#include <cstdint>
#include <cstddef>
#include <span>
#include <array>
#include <type_traits>

namespace observer::format {

// Magic Identifiers for Observer Assets
constexpr uint32_t MAGIC_TIMETABLE       = 0x31565244; // "DRV1"
constexpr uint32_t MAGIC_ULTRA_TRANSFERS = 0x41525455; // "UTRA"
constexpr uint32_t MAGIC_WALK_GRAPH      = 0x4B4C4157; // "WALK"
constexpr uint32_t ENDIAN_MARKER         = 0x01020304;

// Section Descriptor within TOC
struct alignas(8) SectionDesc {
    uint64_t offset;     // Absolute byte offset in file
    uint64_t size_bytes; // Raw byte length of payload
    uint64_t item_count; // Number of typed elements
};
static_assert(sizeof(SectionDesc) == 24, "SectionDesc size mismatch");

// Universal 128-Byte Master File Header
struct alignas(64) MasterHeader {
    uint32_t magic;                 // Asset signature
    uint32_t schema_version;        // Version descriptor
    uint32_t endian_marker;         // Endianness verification
    uint32_t header_size;           // Must be 128
    uint64_t file_size;             // Total payload length
    uint64_t checksum_xxh64;        // Payload hash
    uint32_t num_sections;          // Active sections in TOC
    uint32_t flags;                 // Reserved flags
    std::array<SectionDesc, 4> toc; // Table of Contents
};
static_assert(sizeof(MasterHeader) == 128, "MasterHeader must be exactly 128 bytes");

// -----------------------------------------------------------------------------
// Asset Specific Structures (Fixed Layouts)
// -----------------------------------------------------------------------------

// RAPTOR Stop Structure (timetable.bin)
struct alignas(8) RaptorStop {
    uint32_t stop_id;
    uint32_t route_index_offset;
    uint32_t route_count;
    uint32_t transfer_offset;
    uint32_t transfer_count;
    uint32_t _reserved; // Explicit 4-byte padding to align struct to 8-byte boundary
};
static_assert(sizeof(RaptorStop) == 24, "RaptorStop size layout mismatch");

// Quantized Pedestrian Node (walk_graph.bin)
struct alignas(8) WalkNode {
    int32_t lat_quantized;   // Fixed-point latitude (* 1e7)
    int32_t lon_quantized;   // Fixed-point longitude (* 1e7)
    uint32_t first_edge_idx; // Index into edge payload array
    uint16_t edge_count;     // Outgoing edge count
    uint16_t access_flags;   // Pedestrian accessibility bitmask
};
static_assert(sizeof(WalkNode) == 16, "WalkNode layout mismatch");

// Quantized Pedestrian Edge (walk_graph.bin)
struct alignas(4) WalkEdge {
    uint32_t target_node_idx; // Destination node index
    uint16_t distance_cm;     // Distance in centimeters
    uint16_t weight_ms;       // Traversal cost in milliseconds
};
static_assert(sizeof(WalkEdge) == 8, "WalkEdge layout mismatch");

} // namespace observer::format
```

### Go Serialization Engine (`serializer.go`)

```go
package observer

import (
	"fmt"
	"io"
	"unsafe"
)

const (
	MagicTimetable      uint32 = 0x31565244 // "DRV1"
	MagicUltraTransfers uint32 = 0x41525455 // "UTRA"
	MagicWalkGraph      uint32 = 0x4B4C4157 // "WALK"
	EndianMarker        uint32 = 0x01020304
	MasterHeaderSize    uint32 = 128
)

type SectionDesc struct {
	Offset    uint64
	SizeBytes uint64
	ItemCount uint64
}

type MasterHeader struct {
	Magic         uint32
	SchemaVersion uint32
	EndianMarker  uint32
	HeaderSize    uint32
	FileSize      uint64
	ChecksumXXH64 uint64
	NumSections   uint32
	Flags         uint32
	TOC           [4]SectionDesc
}

type RaptorStop struct {
	StopID           uint32
	RouteIndexOffset uint32
	RouteCount       uint32
	TransferOffset   uint32
	TransferCount    uint32
	Reserved         uint32 // Explicit padding matching C++ 8-byte alignment
}

type WalkNode struct {
	LatQuantized int32
	LonQuantized int32
	FirstEdgeIdx uint32
	EdgeCount    uint16
	AccessFlags  uint16
}

type WalkEdge struct {
	TargetNodeIdx uint32
	DistanceCM    uint16
	WeightMS      uint16
}

// LayoutValidator performs static runtime size verification matching C++ static_assert checks
func LayoutValidator() error {
	if unsafe.Sizeof(MasterHeader{}) != 128 {
		return fmt.Errorf("Go MasterHeader size != 128 bytes")
	}
	if unsafe.Sizeof(RaptorStop{}) != 24 {
		return fmt.Errorf("Go RaptorStop size != 24 bytes")
	}
	if unsafe.Sizeof(WalkNode{}) != 16 {
		return fmt.Errorf("Go WalkNode size != 16 bytes")
	}
	if unsafe.Sizeof(WalkEdge{}) != 8 {
		return fmt.Errorf("Go WalkEdge size != 8 bytes")
	}
	return nil
}

// ZeroCopyWrite writes typed struct slices directly as raw contiguous byte streams
func ZeroCopyWrite[T any](w io.Writer, data []T) (uint64, error) {
	if len(data) == 0 {
		return 0, nil
	}
	var element T
	elementSize := int(unsafe.Sizeof(element))
	totalBytes := len(data) * elementSize

	// Reinterpret slice memory directly to byte stream without heap allocation
	byteSlice := unsafe.Slice((*byte)(unsafe.Pointer(&data[0])), totalBytes)
	n, err := w.Write(byteSlice)
	return uint64(n), err
}
```

---

## 4. Header Validation, Bounds Checking, and Ingestion Logic

Ingestion routines perform validation before casting mapped memory buffers to typed C++20 `std::span` instances:

```cpp
#pragma once

#include "ObserverFormat.hpp"
#include <fcntl.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>
#include <stdexcept>
#include <string>
#include <system_error>

namespace observer::engine {

class MmappedBuffer {
private:
    void* data_ptr_ = nullptr;
    size_t length_ = 0;

public:
    explicit MmappedBuffer(const std::string& path) {
        int fd = ::open(path.c_str(), O_RDONLY);
        if (fd < 0) {
            throw std::system_error(errno, std::generic_category(), "Failed to open file: " + path);
        }

        struct stat sb;
        if (::fstat(fd, &sb) < 0) {
            ::close(fd);
            throw std::system_error(errno, std::generic_category(), "Failed to stat file");
        }
        length_ = static_cast<size_t>(sb.st_size);

        if (length_ < sizeof(format::MasterHeader)) {
            ::close(fd);
            throw std::runtime_error("File size smaller than MasterHeader requirement");
        }

        // Map private read-only buffer
        void* addr = ::mmap(nullptr, length_, PROT_READ, MAP_PRIVATE, fd, 0);
        ::close(fd); // File descriptor closed safely post-mmap

        if (addr == MAP_FAILED) {
            throw std::system_error(errno, std::generic_category(), "mmap execution failed");
        }

        data_ptr_ = addr;
    }

    ~MmappedBuffer() {
        if (data_ptr_ && data_ptr_ != MAP_FAILED) {
            ::munmap(data_ptr_, length_);
        }
    }

    MmappedBuffer(const MmappedBuffer&) = delete;
    MmappedBuffer& operator=(const MmappedBuffer&) = delete;

    [[nodiscard]] const uint8_t* data() const { return static_cast<const uint8_t*>(data_ptr_); }
    [[nodiscard]] size_t size() const { return length_; }
};

class BinaryPayloadView {
private:
    MmappedBuffer buffer_;
    const format::MasterHeader* header_;

public:
    BinaryPayloadView(const std::string& path, uint32_t expected_magic, uint32_t expected_version)
        : buffer_(path) {
        
        // 1. Pointer alignment validation
        auto raw_ptr = reinterpret_cast<uintptr_t>(buffer_.data());
        if (raw_ptr % alignof(format::MasterHeader) != 0) {
            throw std::runtime_error("mmap baseline address failed 64-byte alignment check");
        }

        header_ = reinterpret_cast<const format::MasterHeader*>(buffer_.data());

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
        if (header_->file_size > buffer_.size()) {
            throw std::runtime_error("Header reports file_size larger than physical file buffer");
        }
    }

    // Typed Section View Generation with Bounds Verification
    template <typename T>
    [[nodiscard]] std::span<const T> get_section_span(size_t section_index) const {
        if (section_index >= header_->num_sections) {
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

        const T* typed_ptr = reinterpret_cast<const T*>(buffer_.data() + desc.offset);
        return std::span<const T>(typed_ptr, static_cast<size_t>(desc.item_count));
    }
};

} // namespace observer::engine
```

---

## 5. Asset-Specific Section Layouts & Indirection Schemas

### Timetable Asset Specification (`timetable.bin`)
- **Magic:** `0x31565244` (`"DRV1"`)
- **Section 0:** `RaptorStop` Array (`alignas(8)`, 24B) — Stops containing offset indices into route/transfer sections.
- **Section 1:** `uint32_t` Route Windows (`alignas(4)`) — Indirection array mapping stops to route IDs.
- **Section 2:** `uint32_t` Trip Headways (`alignas(4)`) — Contiguous departure timestamps in seconds past midnight.
- **Section 3:** `uint32_t` Stop Times (`alignas(4)`) — Arrival/departure timestamp pairs ordered by trip and stop sequence.

```cpp
struct TimetableAssets {
    std::span<const observer::format::RaptorStop> stops;
    std::span<const uint32_t> route_indexes;
    std::span<const uint32_t> trip_headways;
    std::span<const uint32_t> stop_times;

    explicit TimetableAssets(const observer::engine::BinaryPayloadView& view) {
        stops         = view.get_section_span<observer::format::RaptorStop>(0);
        route_indexes = view.get_section_span<uint32_t>(1);
        trip_headways = view.get_section_span<uint32_t>(2);
        stop_times    = view.get_section_span<uint32_t>(3);
    }
};
```

### Ultra Transfers CSR Asset Specification (`ultra_transfers.csr`)
- **Magic:** `0x41525455` (`"UTRA"`)
- **Section 0:** `uint32_t` Row Offsets (`alignas(4)`) — CSR row offsets array of length `NumStops + 1`.
- **Section 1:** `uint32_t` Target Stops (`alignas(4)`) — CSR column indices containing destination stop IDs.
- **Section 2:** `uint16_t` Durations (`alignas(2)`) — Transfer traversal costs stored in seconds.

```cpp
struct UltraTransfersCSR {
    std::span<const uint32_t> row_offsets;
    std::span<const uint32_t> column_targets;
    std::span<const uint16_t> edge_weights;

    explicit UltraTransfersCSR(const observer::engine::BinaryPayloadView& view) {
        row_offsets    = view.get_section_span<uint32_t>(0);
        column_targets = view.get_section_span<uint32_t>(1);
        edge_weights   = view.get_section_span<uint16_t>(2);
    }

    [[nodiscard]] std::span<const uint32_t> get_targets(size_t stop_id) const {
        uint32_t start = row_offsets[stop_id];
        uint32_t end   = row_offsets[stop_id + 1];
        return column_targets.subspan(start, end - start);
    }
};
```

### Walk Graph Asset Specification (`walk_graph.bin`)
- **Magic:** `0x4B4C4157` (`"WALK"`)
- **Section 0:** `WalkNode` Array (`alignas(8)`, 16B) — Node array containing quantized coordinates ($10^7$ fixed-point) and edge pointers.
- **Section 1:** `WalkEdge` Array (`alignas(4)`, 8B) — Outgoing edges containing target node indices, distance, and weight scalars.

$$\text{Lat}_{\text{quantized}} = \text{int32}\left(\text{Latitude} \times 10^7\right)$$
$$\text{Lon}_{\text{quantized}} = \text{int32}\left(\text{Longitude} \times 10^7\right)$$
$$\text{Latitude} = \text{double}\left(\text{Lat}_{\text{quantized}}\right) \times 1.0\text{e-}7$$

---

## 6. Architectural Synthesis & System Guarantees

1. **Zero Heap Allocations:** Coupling `mmap` with C++20 `std::span` views ingests binary payloads with zero dynamic heap allocations.
2. **Sub-5 Microsecond Asset Startup:** Zero runtime deserialization or pointer swizzling allows instantaneous routing engine readiness upon memory mapping.
3. **Clean Page Eviction:** Read-only mappings (`PROT_READ`, `MAP_PRIVATE`) allow the iOS Darwin kernel to purge clean pages under memory pressure without swap write-backs, avoiding Jetsam termination.
4. **Metal GPU Compute Ready:** Aligning binary payload sections to 16 KiB boundaries satisfies Apple Silicon requirements for zero-copy memory sharing with Metal compute pipelines (`bytesNoCopy`).
