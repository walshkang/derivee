# Architectural Research Library & Engineering Master Index

> **Notice for AI Agents & Engineers:**  
> This directory houses the primary technical research specifications, mathematical proofs, ABI layouts, and performance contracts for Dérivée. **Mandatory Pre-Flight:** Before designing, proposing, implementing, or refactoring code touching binary serialization, routing algorithms, walk graphs, reliability profiling, MapLibre-to-Metal synchronization, GPU spatial memory/hashing, custom layer injection, or benchmarking, you **must** consult the corresponding research document.

---

## 🗺️ Master Subsystem Dispatch Table

| Subsystem / Problem Domain | Target Wave | Research Specification Document | Primary Structs & Key Symbols | Hard Constraints & Invariants |
|:---|:---:|:---|:---|:---|
| **Binary Serialization & Apple Silicon Memory Mapping** | Wave N.1 | [`01_binary_serialization_contracts.md`](01_binary_serialization_contracts.md) | Universal 128B Header, `SectionDesc`, `toc[]` | 16 KiB page alignment (`0x4000`), 64B cache alignment (`0x0040`), zero-copy `mmap` |
| **ULTRA Shortcut Precomputation & CSR Layout** | Wave N.1 | [`02_ultra_precomputation_architecture.md`](02_ultra_precomputation_architecture.md) | `StopOffset` (8B), `TransferShortcut` (8B), `flat_transfers` | Flat CSR array scan; zero live Dijkstra during RAPTOR round relaxation; $\le 8\text{ MB}$ |
| **Quantized Walk Graph & Bounded Dijkstra** | Wave N.1 | [`03_walk_graph_runtime_memory.md`](03_walk_graph_runtime_memory.md) | `QuantizedWalkNode` (8B), `QuantizedWalkEdge` (8B), `EdgeFlags` | Fixed-point $\times 10^7$ coords; stripped OSM metadata; $\le 25\text{ MB}$ memory budget |
| **Historical Reliability & Variance Profiling** | Wave N.2 | [`04_reliability_population_pipeline.md`](04_reliability_population_pipeline.md) | `TripSlotProfile`, `ServiceDisruption`, `ScheduledStopEvent` | 15-minute origin slot buckets; pre-squared sum variance aggregation; $O(1)$ query |
| **MapLibre-to-Metal Projection & Synchronization** | Wave O | [`05_maplibre_metal_view_synchronization.md`](05_maplibre_metal_view_synchronization.md) | `MapCameraState`, `MapProjectionMath`, `MetalFogEngineRenderer` | EPSG:3857 $\rightarrow$ Metal NDC; Relative-to-Center (RTC) precision; 0-frame lag |
| **Sparse GPU Spatial Memory & H3 Coverage Hashing** | Wave O | [`06_sparse_gpu_spatial_memory_h3_buffering.md`](06_sparse_gpu_spatial_memory_h3_buffering.md) | `H3HashSlot` (16B), `H3HashTableHeader` (64B), `H3DeltaUpdate` | Open-addressing GPU hash table; $\le 4.26\text{ MB}$ VRAM for 100k hexes ($< 10\text{ MB}$ cap) |
| **Metal Layer Injection & Compositing in MapLibre** | Wave O | [`07_metal_layer_injection_compositing_maplibre.md`](07_metal_layer_injection_compositing_maplibre.md) | `MLNCustomFogLayer` (`MLNCustomStyleLayer`), `CustomFogUniforms` | Direct `MTLRenderCommandEncoder` reuse; z-index insertion below `MLNSymbolStyleLayer` |
| **Empirical Performance Benchmarking & Telemetry** | Wave O | [`08_empirical_performance_benchmarking_metalfogengine.md`](08_empirical_performance_benchmarking_metalfogengine.md) | `TelemetryCollector`, `FogEngineBenchmarkSuite`, `PerformanceReport` | 120 FPS locked ($\ge 118\text{ FPS}$); $\text{P99} \le 8.33\text{ms}$; 0% CPU geometry; $\text{RMSD} < 0.001$ |
| **MSL Shader Pipeline: SDFs, Bilinear Sampling & Glow** | Wave O | [`09_metal_shading_pipeline_sdf_edge_glow.md`](09_metal_shading_pipeline_sdf_edge_glow.md) | `vertexFogQuad`, `fragmentFogAperture`, `MSLFogStyleLayer` | 4-vertex full-screen quad ($O(1)$ vertex load); screen derivatives `dfdx`/`dfdy`; single-pass Amber glow ($<0.3\text{ms}$) |
| **Hybrid RAPTOR Core Algorithm & C++20 Interop** | Wave N.2 | [`10_hybrid_raptor_algorithm_cpp20_interop.md`](10_hybrid_raptor_algorithm_cpp20_interop.md) | `StopTime` (12B), `Trip` (8B), `Route` (12B), `Stop` (20B), `RaptorEngine` | `#pragma pack(push, 1)` AoS layout; 17.58MB memory footprint (<30MB Jetsam); <15ms latency on Apple Silicon |
| **Real-Time GBFS Micro-Mobility & Dock Gating** | Wave N.3 | [`11_gbfs_micromobility_dock_gating.md`](11_gbfs_micromobility_dock_gating.md) | `GBFSRealtimeService`, `gbfs_cache.sqlite` (`DatabaseQueue`) | Ephemeral SQLite in `NSTemporaryDirectory()`; dock gating ($G(e) = g_{\text{pick}} \cdot g_{\text{drop}}$); $0.12\text{ms}$ spatial query; zero `0xdead10cc` risk |
| **120Hz Immediate-Mode Canvas & Reliability Heatmap** | Wave N.4 | [`12_immediate_mode_canvas_reliability_heatmap.md`](12_immediate_mode_canvas_reliability_heatmap.md) | `ImmediateDepartureMatrixCanvas`, `CircularDensitySmoother` | `Canvas(rendersAsynchronously: true)` + `.drawingGroup()`; flat 4,320 `[Float]` array (17.28KB L1 cache); von Mises circular convolution in $<0.07\text{ms}$ via vDSP |
| **Automated GIS Multi-City Compiler & Bridge Masking** | Wave M/L | [`13_automated_gis_city_pack_compiler.md`](13_automated_gis_city_pack_compiler.md) | `SpatialProcessor`, `WriteAlignedHeader`, `performAtomicDatabaseSwap` | $\text{Walkable} = (\text{Neighborhood} \setminus \text{Water}) \cup \text{Bridges}$; 16 KiB page-aligned `.pack.zst`; `WITHOUT ROWID` clustered tables; atomic POSIX `rename()` |

---

## 🏛️ Architectural Wave Alignment

```
┌─────────────────────────────────────────────────────────────────────────┐
│ Wave M: Multi-City Navigation & Cartographic Hardening                   │
│   • GIS Bridge Preservation & City Packs: Doc 13                        │
│   • Global World Fog Envelope: M5.1 / Doc 05                            │
└────────────────────────────────────┬────────────────────────────────────┘
                                     │
┌────────────────────────────────────▼────────────────────────────────────┐
│ Wave N: On-Device Multimodal Routing Engine (C++20 & GRDB)              │
│   • Track A (Binary Serialization & ULTRA CSR): Docs 01, 02, 03, 04     │
│   • Track B (Hybrid RAPTOR Hot Loop & C++ Interop): Doc 10              │
│   • Track C (GBFS Micro-Mobility & Dynamic GTFS-RT): Docs 04, 11        │
│   • Track D (120Hz Departure Matrix Canvas): Doc 12                     │
└────────────────────────────────────┬────────────────────────────────────┘
                                     │
┌────────────────────────────────────▼────────────────────────────────────┐
│ Wave O: MetalFogEngine (GPU Alpha Masking & Spatial Hashing)            │
│   • Coordinate Projection & RTC Matrix: Doc 05                          │
│   • Open-Addressing GPU Hash Table in MTLBuffer: Doc 06                 │
│   • In-Pipeline MLNCustomStyleLayer Injection: Doc 07                   │
│   • MSL Shader Pipeline & Amber Glow: Doc 09                            │
│   • Empirical 120Hz Telemetry Benchmark Suite: Doc 08                   │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## 📋 Document Summaries & Invariant Quick-Reference

### [01. Zero-Copy Binary Serialization Contracts](01_binary_serialization_contracts.md)
* **Scope:** Universal file layout for `timetable.bin`, `ultra_transfers.csr`, and `walk_graph.bin`.
* **Key Invariants:** 128-byte fixed header; 16 KiB Apple Silicon page alignment (`0x4000`); 64-byte CPU cache-line alignment (`0x0040`); zero pointer swizzling (offset/index indirection only); read-only `mmap` sharing.

### [02. ULTRA Precomputation Architecture](02_ultra_precomputation_architecture.md)
* **Scope:** Offline generation of transit transfer shortcuts in Compressed Sparse Row (CSR) layout.
* **Key Invariants:** Pareto-optimal shortcut pruning; $\le 8\text{ MB}$ footprint; flat CSR binary scan during RAPTOR rounds (prohibits live Dijkstra).

### [03. Walk Graph Runtime Memory](03_walk_graph_runtime_memory.md)
* **Scope:** Compact pedestrian routing graph compiled from OpenStreetMap PBF extracts.
* **Key Invariants:** 32-bit fixed-point coordinates ($\times 10^7$); `EdgeFlags` bitmask (Walkable, Wheelchair, Steps, Elevator); strict $\le 25\text{ MB}$ memory budget; bounded one-to-many Dijkstra search.

### [04. Reliability Population Pipeline](04_reliability_population_pipeline.md)
* **Scope:** 15-minute origin dispatch slot profiling and pre-squared variance aggregation from GTFS-RT.
* **Key Invariants:** 15-minute temporal slot indexing (672 weekly slots); pre-squared sum variance formula; circular modular delay mapping ($[-720, +720]$ min); zero-latency SQL read via indexed coverage.

### [05. MapLibre-to-Metal Synchronization](05_maplibre_metal_view_synchronization.md)
* **Scope:** Mathematical projection pipeline from Web Mercator (EPSG:3857) to Metal NDC.
* **Key Invariants:** $S(z) = 512 \cdot 2^z$ scale factor; Relative-to-Center (RTC) precision delta mitigating float32 jitter at $z \ge 18$; zero-lag VSync frame synchronization.

### [06. Sparse GPU Spatial Memory & H3 Buffering](06_sparse_gpu_spatial_memory_h3_buffering.md)
* **Scope:** Storing and querying 100k H3 Res-11 hexes in an open-addressing GPU hash table inside `MTLBuffer`.
* **Key Invariants:** 16-byte aligned `H3HashSlot`; 64-byte `H3HashTableHeader`; $4.26\text{ MB}$ total VRAM for 100k hexes ($< 10\text{ MB}$ cap); `.storageModeShared` zero-copy CPU pointer writes; in-shader bitwise parent LOD aggregation.

### [07. Metal Layer Injection & Compositing in MapLibre](07_metal_layer_injection_compositing_maplibre.md)
* **Scope:** Architectural evaluation of `MLNCustomStyleLayer` vs external `MTKView` overlay.
* **Key Invariants:** Direct `id<MTLRenderCommandEncoder>` reuse; z-index insertion below `MLNSymbolStyleLayer` preserving station/street label legibility; $0\text{ MB}$ auxiliary texture overhead.

### [08. Empirical Performance Benchmarking Harness](08_empirical_performance_benchmarking_metalfogengine.md)
* **Scope:** Automated, headless XCTest benchmark suite for `MetalFogEngine`.
* **Key Invariants:** 120 FPS locked ($\ge 118\text{ FPS}$); $\text{P99} \le 8.33\text{ms}$; peak $\text{GPU} \le 8.33\text{ms}$; total $\text{VRAM} < 10\text{ MB}$; 0% CPU geometry time ($\le 0.05\text{ms}$ uniform write); $\text{RMSD} < 0.001$ visual parity.

### [09. Metal Shading Language Pipeline: Analytical SDFs & Glow](09_metal_shading_pipeline_sdf_edge_glow.md)
* **Scope:** Full-screen quad fragment shader architecture, screen-space derivative anti-aliasing, and single-pass Electric Amber (`#FFB300`) edge glow.
* **Key Invariants:** 4-vertex full-screen quad ($O(1)$ constant geometry); screen-space partial derivatives (`dfdx`, `dfdy`) for constant 1.0–1.5px boundary anti-aliasing across $z0 \dots z18$; single-pass analytical Hermite glow ($I_{\text{glow}}(C)$); premultiplied alpha blend pipeline (`.one`, `.oneMinusSourceAlpha`, `.add`); $< 0.3\text{ ms}$ fragment execution on Apple Silicon.

### [10. Hybrid RAPTOR Algorithm & C++20 Swift Interoperability](10_hybrid_raptor_algorithm_cpp20_interop.md)
* **Scope:** On-device packed timetable memory layout, 4D Pareto multi-criteria optimization, and zero-bridge Swift C++20 interop for Apple Silicon.
* **Key Invariants:** `#pragma pack(push, 1)` AoS layout (`StopTime` 12B, `Trip` 8B, `Route` 12B, `Stop` 20B, `Transfer` 8B); 17.58 MB NYC MTA network memory footprint ($41.4\%$ below 30 MB Jetsam ceiling); 4D Pareto label pruning ($\tau_{\text{arr}}, N_{\text{trans}}, D_{\text{walk}}, R_{\text{risk}}$); circular midnight Euclidean modulo; $< 15\text{ ms}$ query latency; zero-bridge Swift-C++ interop via `-cxx-interoperability-mode=default` and `SWIFT_SELF_CONTAINED` / `[[clang::lifetimebound]]`.

### [11. Real-Time GBFS Micro-Mobility & Multi-Modal Dock Gating](11_gbfs_micromobility_dock_gating.md)
* **Scope:** Ephemeral SQLite caching in `NSTemporaryDirectory()`, dual database isolation, flat-Earth bounding box spatial querying, and dock-gated McRAPTOR routing.
* **Key Invariants:** Ephemeral `gbfs_cache.sqlite` accessed via GRDB `DatabaseQueue` (isolated from static `transit.sqlite` `DatabasePool`); complete avoidance of iOS `0xdead10cc` background termination crashes; two-phase flat-Earth bounding box queries executing in $0.12\text{–}0.35\text{ ms}$; dynamic dock gating product $G(e) = g_{\text{pick}} \cdot g_{\text{drop}}$ with $r_{\text{fallback}} \le 300\text{m}$ alternative dock reallocation; structured actor-based Swift 5.9+ polling (`GBFSRealtimeService`) with exponential backoff ($15\text{s}–120\text{s}$) and HTTP conditional GET (`ETag`).

### [12. 120Hz Immediate-Mode SwiftUI Canvas & Circular Reliability Heatmap](12_immediate_mode_canvas_reliability_heatmap.md)
* **Scope:** Immediate-mode GPU Canvas architecture, flat contiguous float buffer topologies, von Mises circular kernel density smoothing, and sheet gesture disambiguation.
* **Key Invariants:** `Canvas(rendersAsynchronously: true)` + `.drawingGroup()` compiling on background threads; contiguous 4,320 `[Float]` array buffer (17.28 KB fitting in 64 KB L1 CPU cache); zero transient heap allocations inside render loop; von Mises circular smoothing preserving continuity across midnight ($23:59 \rightarrow 00:00$) via vectorized Accelerate `vDSP_conv` executing in $< 0.07\text{ ms}$; spatial gesture tangent locking ($|\Delta x| / |\Delta y| > 1.732$); locked 120 FPS frame rate on Apple ProMotion.

### [13. Automated Multi-City GIS Compilation & Pedestrian Bridge Subtraction](13_automated_gis_city_pack_compiler.md)
* **Scope:** Boolean GIS set algebra, OpenStreetMap Overpass pedestrian bridge extraction, H3 Res 11 polyfill validation, SQLite `WITHOUT ROWID` optimization, and 16 KiB page-aligned Zstandard stream packaging.
* **Key Invariants:** Pedestrian bridge preservation formula $\text{Walkable} = (\text{Neighborhood} \setminus \text{Water}) \cup \text{Pedestrian\_Bridges}$; "Quiet Water Gliding" open-water cell purging ($-30\%$ index cardinality); `WITHOUT ROWID` clustered tables reducing cold queries to $1.8\text{ ms}$ ($-87.3\%$ latency); 16 KiB page-aligned Zstandard Skippable Frames (`0x184D2A50`) enabling zero-copy `mmap` ($2.1\text{ MB}$ client RAM, $-94.5\%$); atomic POSIX `rename()` swaps in $4.2\text{ ms}$ with zero downtime.
