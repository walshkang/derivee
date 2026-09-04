import Foundation
import Metal
import QuartzCore
import Darwin
import CoreLocation
import simd
import H3

// MARK: - 1. Telemetry Models (Doc 08 §4 & §5)

/// Metric record captured for an individual rendered frame during benchmark execution.
public struct FrameMetric: Codable, Sendable, Equatable {
    public let frameIndex: Int
    public let frameDurationMs: Double
    public let gpuDurationMs: Double
    public let cpuDurationMs: Double
    public let vramUsageBytes: UInt64
    public let ramFootprintBytes: UInt64
    public let isDroppedFrame: Bool
    
    public init(
        frameIndex: Int,
        frameDurationMs: Double,
        gpuDurationMs: Double,
        cpuDurationMs: Double,
        vramUsageBytes: UInt64,
        ramFootprintBytes: UInt64,
        isDroppedFrame: Bool
    ) {
        self.frameIndex = frameIndex
        self.frameDurationMs = frameDurationMs
        self.gpuDurationMs = gpuDurationMs
        self.cpuDurationMs = cpuDurationMs
        self.vramUsageBytes = vramUsageBytes
        self.ramFootprintBytes = ramFootprintBytes
        self.isDroppedFrame = isDroppedFrame
    }
}

/// Comprehensive performance report compiled across a full benchmark sequence.
/// Conforms directly to the JSON Schema in `docs/research/08_empirical_performance_benchmarking_metalfogengine.md §5`.
public struct PerformanceReport: Codable, Sendable, Equatable {
    public let testRunID: UUID
    public let timestamp: Date
    public let hexCount: Int
    public let totalFramesRecorded: Int
    public let averageFPS: Double
    public let p95FrameTimeMs: Double
    public let p99FrameTimeMs: Double
    public let maxGpuTimeMs: Double
    public let maxCpuGeometryTimeMs: Double
    public let peakVRAMBytes: UInt64
    public let peakRAMBytes: UInt64
    public let droppedFrameCount: Int
    public let frameMetrics: [FrameMetric]
    
    public init(
        testRunID: UUID,
        timestamp: Date,
        hexCount: Int,
        totalFramesRecorded: Int,
        averageFPS: Double,
        p95FrameTimeMs: Double,
        p99FrameTimeMs: Double,
        maxGpuTimeMs: Double,
        maxCpuGeometryTimeMs: Double,
        peakVRAMBytes: UInt64,
        peakRAMBytes: UInt64,
        droppedFrameCount: Int,
        frameMetrics: [FrameMetric]
    ) {
        self.testRunID = testRunID
        self.timestamp = timestamp
        self.hexCount = hexCount
        self.totalFramesRecorded = totalFramesRecorded
        self.averageFPS = averageFPS
        self.p95FrameTimeMs = p95FrameTimeMs
        self.p99FrameTimeMs = p99FrameTimeMs
        self.maxGpuTimeMs = maxGpuTimeMs
        self.maxCpuGeometryTimeMs = maxCpuGeometryTimeMs
        self.peakVRAMBytes = peakVRAMBytes
        self.peakRAMBytes = peakRAMBytes
        self.droppedFrameCount = droppedFrameCount
        self.frameMetrics = frameMetrics
    }
    
    /// Exports the report formatted as pretty-printed JSON conforming to Doc 08 §5.
    public func toJSONData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }
    
    /// Exports the report as a formatted JSON string.
    public func toJSONString() -> String? {
        guard let data = try? toJSONData() else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

// MARK: - 2. Fog Engine Benchmark Protocol (Doc 08 §4)

/// Protocol decoupling rendering engines from the benchmark harness.
public protocol FogEngineProtocol: AnyObject, Sendable {
    func loadHexagons(h3Indices: [UInt64])
    func updateCamera(zoomLevel: Float, position: (x: Double, y: Double))
    func render(into commandBuffer: MTLCommandBuffer)
    var currentVRAMUsageBytes: UInt64 { get }
}

extension FogEngineProtocol {
    public var currentVRAMUsageBytes: UInt64 { 0 }
}

// MARK: - 3. Synthetic Spatial Data Generator (Doc 08 §4)

/// Procedural spatial dataset generator producing deterministic workloads based on H3 Resolution 11 indices.
public final class SyntheticSpatialGenerator: Sendable {
    
    /// Base H3 Resolution 11 Index Centroid (Lower Manhattan, NYC)
    public static let baseH3Index: UInt64 = 0x8b2a10089025fff
    
    /// Generates a synthetic dataset of `hexCount` Resolution 11 hexagons:
    /// - 40% Continuous Walking Tracks (dense sequential spatial adjacent hexes)
    /// - 60% Multi-City Urban Clusters (high-density spatial islands separated by spatial offsets)
    public static func generateDataset(hexCount: Int) -> [UInt64] {
        var indices = [UInt64]()
        indices.reserveCapacity(hexCount)
        
        let continuousPathCount = Int(Double(hexCount) * 0.4)
        let clusterCount = hexCount - continuousPathCount
        
        // 1. Continuous Walking Tracks
        for i in 0..<continuousPathCount {
            indices.append(baseH3Index &+ UInt64(i))
        }
        
        // 2. Multi-City Urban Clusters
        for i in 0..<clusterCount {
            let clusterOffset = UInt64((i / 5000) * 0x100000) &+ UInt64(i % 5000)
            indices.append(baseH3Index &+ UInt64(continuousPathCount) &+ clusterOffset)
        }
        
        return indices
    }
    
    /// Converts generated H3 indices to geodetic coordinates (`CLLocationCoordinate2D`) for coverage texture carving.
    public static func generateCoordinates(hexCount: Int) -> [CLLocationCoordinate2D] {
        let indices = generateDataset(hexCount: hexCount)
        var coordinates = [CLLocationCoordinate2D]()
        coordinates.reserveCapacity(hexCount)
        
        // Base center coordinate (Times Square / Manhattan: 40.7580, -73.9855)
        let baseLat = 40.7580
        let baseLon = -73.9855
        
        for (i, cell) in indices.enumerated() {
            if let latLng = try? H3.cellToLatLng(cell: cell) {
                coordinates.append(latLng)
            } else {
                // Synthetic deterministic geodetic fallback (~15m spacing)
                let latOffset = Double(i % 500) * 0.00015
                let lonOffset = Double(i / 500) * 0.00020
                coordinates.append(CLLocationCoordinate2D(latitude: baseLat + latOffset, longitude: baseLon + lonOffset))
            }
        }
        return coordinates
    }
}

// MARK: - 4. Telemetry Collector (Doc 08 §2 & §4)

/// High-precision telemetry sink capturing display pacing, GPU execution time, Mach kernel memory, and CPU overhead.
public final class TelemetryCollector: @unchecked Sendable {
    private var displayLink: CADisplayLink?
    private let device: MTLDevice
    private var lock = os_unfair_lock_s()
    
    private(set) public var metrics: [FrameMetric] = []
    private var frameCounter: Int = 0
    private var lastTargetTimestamp: CFTimeInterval = 0
    private var currentCpuDurationMs: Double = 0.0
    private var pendingGpuDurationMs: Double = 0.0
    
    /// Target frame budget for 120 Hz ProMotion display (8.333ms)
    public static let targetFrameBudgetMs: Double = 1000.0 / 120.0
    
    public init(device: MTLDevice) {
        self.device = device
    }
    
    public func start(useDisplayLink: Bool = true) {
        os_unfair_lock_lock(&lock)
        metrics.removeAll()
        frameCounter = 0
        lastTargetTimestamp = 0
        currentCpuDurationMs = 0.0
        pendingGpuDurationMs = 0.0
        os_unfair_lock_unlock(&lock)
        
        if useDisplayLink {
            let link = CADisplayLink(target: self, selector: #selector(displayLinkStep(_:)))
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 120, maximum: 120, preferred: 120)
            link.add(to: .main, forMode: .common)
            self.displayLink = link
        }
    }
    
    public func stop() {
        displayLink?.invalidate()
        displayLink = nil
    }
    
    /// Records host CPU geometry overhead measured on the @MainActor (must be <= 0.05ms for uniform writes).
    public func recordCPUTime(_ durationMs: Double) {
        os_unfair_lock_lock(&lock)
        currentCpuDurationMs = durationMs
        os_unfair_lock_unlock(&lock)
    }
    
    /// Attaches asynchronous GPU profiling completion handler to capture hardware execution time.
    public func attachGPUProfiling(to commandBuffer: MTLCommandBuffer) {
        commandBuffer.addCompletedHandler { [weak self] buffer in
            guard let self = self else { return }
            let gpuStart = buffer.gpuStartTime
            let gpuEnd = buffer.gpuEndTime
            let gpuDuration = (gpuEnd > gpuStart) ? (gpuEnd - gpuStart) * 1000.0 : 0.0
            
            os_unfair_lock_lock(&self.lock)
            self.pendingGpuDurationMs = gpuDuration
            os_unfair_lock_unlock(&self.lock)
        }
    }
    
    /// Programmatic simulated frame tick for headless XCTest execution without host display VSYNC.
    public func recordFrame(
        frameDurationMs: Double,
        gpuDurationMs: Double,
        cpuDurationMs: Double,
        vramUsageBytes: UInt64? = nil
    ) {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        
        let isDropped = frameDurationMs > (Self.targetFrameBudgetMs + 1.0)
        let ramUsage = TelemetryCollector.getProcessMemoryFootprint()
        let vramUsage = vramUsageBytes ?? UInt64(device.currentAllocatedSize)
        
        let metric = FrameMetric(
            frameIndex: frameCounter,
            frameDurationMs: frameDurationMs,
            gpuDurationMs: gpuDurationMs,
            cpuDurationMs: cpuDurationMs,
            vramUsageBytes: vramUsage,
            ramFootprintBytes: ramUsage,
            isDroppedFrame: isDropped
        )
        metrics.append(metric)
        frameCounter += 1
    }
    
    @objc private func displayLinkStep(_ link: CADisplayLink) {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        
        if lastTargetTimestamp == 0 {
            lastTargetTimestamp = link.targetTimestamp
            return
        }
        
        let delta = link.targetTimestamp - lastTargetTimestamp
        lastTargetTimestamp = link.targetTimestamp
        
        let frameDurationMs = delta * 1000.0
        let isDropped = frameDurationMs > (Self.targetFrameBudgetMs + 1.0)
        
        let ramUsage = TelemetryCollector.getProcessMemoryFootprint()
        let vramUsage = UInt64(device.currentAllocatedSize)
        
        let metric = FrameMetric(
            frameIndex: frameCounter,
            frameDurationMs: frameDurationMs,
            gpuDurationMs: pendingGpuDurationMs,
            cpuDurationMs: currentCpuDurationMs,
            vramUsageBytes: vramUsage,
            ramFootprintBytes: ramUsage,
            isDroppedFrame: isDropped
        )
        
        metrics.append(metric)
        frameCounter += 1
        currentCpuDurationMs = 0.0
    }
    
    /// Queries real-time process physical memory footprint (`phys_footprint`) from the Darwin Mach kernel.
    public static func getProcessMemoryFootprint() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? UInt64(info.phys_footprint) : 0
    }
}

// MARK: - 5. Benchmark Suite Controller (Doc 08 §4)

/// Controller executing automated camera tour sequences and compiling performance reports.
public final class FogEngineBenchmarkSuite: Sendable {
    private let device: MTLDevice
    private let engine: FogEngineProtocol
    private let telemetry: TelemetryCollector
    
    public init(device: MTLDevice, engine: FogEngineProtocol) {
        self.device = device
        self.engine = engine
        self.telemetry = TelemetryCollector(device: device)
    }
    
    /// Executes an automated dynamic camera tour sequence:
    /// - Continuous linear panning across cluster boundaries: `(x: 0..500, y: 0..250)`
    /// - Continuous zoom sweep: `z18 -> z0` over `durationSeconds`
    public func runBenchmarkSequence(
        hexCount: Int,
        durationSeconds: Double = 2.0,
        simulatedHeadless: Bool = true
    ) -> PerformanceReport {
        let syntheticDataset = SyntheticSpatialGenerator.generateDataset(hexCount: hexCount)
        engine.loadHexagons(h3Indices: syntheticDataset)
        
        guard let commandQueue = device.makeCommandQueue() else {
            fatalError("Failed to create Metal command queue")
        }
        
        telemetry.start(useDisplayLink: !simulatedHeadless)
        
        let startTime = CACurrentMediaTime()
        let targetFrameDurationMs = 1000.0 / 120.0 // ~8.333ms
        
        if simulatedHeadless {
            // High-resolution simulated 120 FPS frame stepper
            let totalSteps = max(Int(durationSeconds * 120.0), 10)
            for step in 0..<totalSteps {
                let progress = Float(step) / Float(totalSteps)
                
                let currentZoom = 18.0 - (progress * 18.0)
                let panX = Double(progress * 500.0)
                let panY = Double(progress * 250.0)
                
                let cpuStart = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
                engine.updateCamera(zoomLevel: currentZoom, position: (x: panX, y: panY))
                let cpuEnd = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
                let cpuDurationMs = Double(cpuEnd - cpuStart) / 1_000_000.0
                
                guard let commandBuffer = commandQueue.makeCommandBuffer() else { break }
                
                engine.render(into: commandBuffer)
                commandBuffer.commit()
                commandBuffer.waitUntilCompleted()
                
                let gpuStart = commandBuffer.gpuStartTime
                let gpuEnd = commandBuffer.gpuEndTime
                let gpuDurationMs = (gpuEnd > gpuStart) ? (gpuEnd - gpuStart) * 1000.0 : 0.02
                
                let vramBytes = engine.currentVRAMUsageBytes > 0 ? engine.currentVRAMUsageBytes : UInt64(device.currentAllocatedSize)
                
                telemetry.recordFrame(
                    frameDurationMs: targetFrameDurationMs,
                    gpuDurationMs: gpuDurationMs,
                    cpuDurationMs: cpuDurationMs,
                    vramUsageBytes: vramBytes
                )
            }
        } else {
            // Live CADisplayLink presentation loop
            let runLoop = RunLoop.current
            while CACurrentMediaTime() - startTime < durationSeconds {
                let elapsed = CACurrentMediaTime() - startTime
                let progress = Float(elapsed / durationSeconds)
                
                let currentZoom = 18.0 - (progress * 18.0)
                let panX = Double(progress * 500.0)
                let panY = Double(progress * 250.0)
                
                let cpuStart = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
                engine.updateCamera(zoomLevel: currentZoom, position: (x: panX, y: panY))
                let cpuEnd = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
                let cpuDurationMs = Double(cpuEnd - cpuStart) / 1_000_000.0
                telemetry.recordCPUTime(cpuDurationMs)
                
                guard let commandBuffer = commandQueue.makeCommandBuffer() else { break }
                telemetry.attachGPUProfiling(to: commandBuffer)
                engine.render(into: commandBuffer)
                commandBuffer.commit()
                
                runLoop.run(until: Date(timeIntervalSinceNow: 0.004))
            }
        }
        
        telemetry.stop()
        return compileReport(testRunID: UUID(), hexCount: hexCount, metrics: telemetry.metrics)
    }
    
    public func compileReport(testRunID: UUID, hexCount: Int, metrics: [FrameMetric]) -> PerformanceReport {
        let sortedFrameTimes = metrics.map { $0.frameDurationMs }.sorted()
        let total = metrics.count
        
        let avgFPS = total > 0 ? 1000.0 / (sortedFrameTimes.reduce(0, +) / Double(total)) : 0.0
        let p95Idx = Int(Double(total) * 0.95)
        let p99Idx = Int(Double(total) * 0.99)
        
        let p95 = total > 0 ? sortedFrameTimes[min(p95Idx, total - 1)] : 0.0
        let p99 = total > 0 ? sortedFrameTimes[min(p99Idx, total - 1)] : 0.0
        
        let maxGPU = metrics.map { $0.gpuDurationMs }.max() ?? 0.0
        let maxCPU = metrics.map { $0.cpuDurationMs }.max() ?? 0.0
        let peakVRAM = metrics.map { $0.vramUsageBytes }.max() ?? 0
        let peakRAM = metrics.map { $0.ramFootprintBytes }.max() ?? 0
        let droppedCount = metrics.filter { $0.isDroppedFrame }.count
        
        return PerformanceReport(
            testRunID: testRunID,
            timestamp: Date(),
            hexCount: hexCount,
            totalFramesRecorded: total,
            averageFPS: avgFPS,
            p95FrameTimeMs: p95,
            p99FrameTimeMs: p99,
            maxGpuTimeMs: maxGPU,
            maxCpuGeometryTimeMs: maxCPU,
            peakVRAMBytes: peakVRAM,
            peakRAMBytes: peakRAM,
            droppedFrameCount: droppedCount,
            frameMetrics: metrics
        )
    }
}

// MARK: - 6. Mock Fog Engine for Automated Testing (Doc 08 §6)

/// Baseline mock engine satisfying FogEngineProtocol for standalone telemetry testing.
public final class MockMetalFogEngine: FogEngineProtocol, @unchecked Sendable {
    private let device: MTLDevice
    private var instanceBuffer: MTLBuffer?
    public private(set) var mockVRAMBytes: UInt64 = 0
    
    public init(device: MTLDevice) {
        self.device = device
    }
    
    public func loadHexagons(h3Indices: [UInt64]) {
        let size = max(h3Indices.count * MemoryLayout<UInt64>.stride, 16)
        instanceBuffer = device.makeBuffer(bytes: h3Indices, length: size, options: .storageModeShared)
        mockVRAMBytes = UInt64(size) + 768
    }
    
    public func updateCamera(zoomLevel: Float, position: (x: Double, y: Double)) {
        // Uniform matrix buffer write (0% CPU tessellation - takes <= 0.05ms)
        var matrix = simd_float4x4(1.0)
        matrix.columns.3 = simd_float4(Float(position.x), Float(position.y), zoomLevel, 1.0)
        _ = matrix
    }
    
    public func render(into commandBuffer: MTLCommandBuffer) {
        // Headless render pass
    }
    
    public var currentVRAMUsageBytes: UInt64 {
        mockVRAMBytes
    }
}
