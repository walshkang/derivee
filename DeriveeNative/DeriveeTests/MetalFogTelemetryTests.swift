import XCTest
import Metal
import QuartzCore
import simd
import CoreLocation
@testable import Derivee

final class MetalFogTelemetryTests: XCTestCase {
    
    private var device: MTLDevice!
    private var mockEngine: MockMetalFogEngine!
    private var benchmarkSuite: FogEngineBenchmarkSuite!
    
    override func setUp() {
        super.setUp()
        guard let sysDevice = MTLCreateSystemDefaultDevice() else {
            return
        }
        self.device = sysDevice
        self.mockEngine = MockMetalFogEngine(device: device)
        self.benchmarkSuite = FogEngineBenchmarkSuite(device: device, engine: mockEngine)
    }
    
    // MARK: - 1. 100k Hex Stress Test Performance Regression (Doc 08 §3 & §6)
    
    func test100KHexPerformanceRegression() throws {
        guard let device = device else {
            throw XCTSkip("No system default MTLDevice available on this test host")
        }
        
        let report = benchmarkSuite.runBenchmarkSequence(hexCount: 100_000, durationSeconds: 2.0, simulatedHeadless: true)
        
        // 1. Target Frame Rate Assertion (120 FPS ProMotion Pacing)
        XCTAssertGreaterThanOrEqual(
            report.averageFPS, 118.0,
            "Average FPS dropped below ProMotion threshold: \(report.averageFPS)"
        )
        XCTAssertLessThanOrEqual(
            report.p99FrameTimeMs, 8.334,
            "P99 frame time exceeded ProMotion 8.333ms deadline: \(report.p99FrameTimeMs)ms"
        )
        
        // 2. Hardware GPU Render Time Assertion (<= 8.333ms per-frame ceiling)
        XCTAssertLessThanOrEqual(
            report.maxGpuTimeMs, 8.333,
            "Peak GPU render time exceeded budget: \(report.maxGpuTimeMs)ms"
        )
        
        // 3. Total VRAM Footprint Assertion (< 10 MB Jetsam Hard Budget)
        let maxVRAMAllowed: UInt64 = 10 * 1024 * 1024
        XCTAssertLessThan(
            report.peakVRAMBytes, maxVRAMAllowed,
            "VRAM consumption exceeded 10MB limit: \(report.peakVRAMBytes) bytes"
        )
        
        // 4. Zero CPU Geometry Overhead Assertion (<= 0.05ms uniform write only)
        XCTAssertLessThanOrEqual(
            report.maxCpuGeometryTimeMs, 0.05,
            "CPU geometry overhead detected during camera movement: \(report.maxCpuGeometryTimeMs)ms"
        )
        
        // 5. Zero Dropped Frame Tolerance
        XCTAssertEqual(
            report.droppedFrameCount, 0,
            "Dropped frames detected during 100k hex execution: \(report.droppedFrameCount)"
        )
        
        // 6. JSON Export & Attachment
        attachReportArtifact(report, filename: "PerformanceReport_100k.json")
    }
    
    // MARK: - 2. Workload Scaling Invariance (Doc 08 §1 & §3)
    
    func testWorkloadScalingInvariance() throws {
        guard device != nil else {
            throw XCTSkip("No system default MTLDevice available on this test host")
        }
        
        let workloads = [10_000, 50_000, 100_000]
        var reports: [PerformanceReport] = []
        
        for count in workloads {
            let rep = benchmarkSuite.runBenchmarkSequence(hexCount: count, durationSeconds: 0.5, simulatedHeadless: true)
            reports.append(rep)
            
            // Assert CPU geometry overhead remains invariant at <= 0.05ms regardless of density
            XCTAssertLessThanOrEqual(
                rep.maxCpuGeometryTimeMs, 0.05,
                "CPU geometry overhead must remain <= 0.05ms for \(count) hexes (measured \(rep.maxCpuGeometryTimeMs)ms)"
            )
            
            // Assert VRAM stays strictly below 10 MB budget
            XCTAssertLessThan(
                rep.peakVRAMBytes, 10 * 1024 * 1024,
                "Peak VRAM for \(count) hexes must stay < 10 MB (measured \(rep.peakVRAMBytes) bytes)"
            )
            
            // Assert zero dropped frames
            XCTAssertEqual(rep.droppedFrameCount, 0, "Zero dropped frames allowed for \(count) hexes")
        }
        
        // Verify VRAM scales predictably with workload
        XCTAssertLessThanOrEqual(reports[0].peakVRAMBytes, reports[1].peakVRAMBytes)
        XCTAssertLessThanOrEqual(reports[1].peakVRAMBytes, reports[2].peakVRAMBytes)
    }
    
    // MARK: - 3. Production MetalFogStyleLayer Adapter Benchmark (Doc 08 §4)
    
    func testProductionEngineAdapterOffscreenPerformance() throws {
        guard let device = device else {
            throw XCTSkip("No system default MTLDevice available on this test host")
        }
        
        let spatialEngine = try H3SpatialMemoryEngine(device: device)
        let fogLayer = MetalFogStyleLayer(identifier: "benchmark-fog-layer", spatialEngine: spatialEngine)
        try fogLayer.setupPipeline(device: device, colorPixelFormat: .bgra8Unorm, depthStencilPixelFormat: .invalid)
        fogLayer.setupUniformBuffers(device: device)
        try fogLayer.setupSampler(device: device)
        try fogLayer.setupCoverageTexture(device: device, width: 1024, height: 1024)
        
        let adapter = MetalFogEngineAdapter(layer: fogLayer, device: device, width: 1024, height: 1024)
        let liveBenchmark = FogEngineBenchmarkSuite(device: device, engine: adapter)
        
        let report = liveBenchmark.runBenchmarkSequence(hexCount: 10_000, durationSeconds: 1.0, simulatedHeadless: true)
        
        XCTAssertGreaterThanOrEqual(report.averageFPS, 118.0)
        XCTAssertLessThanOrEqual(report.p99FrameTimeMs, 8.334)
        XCTAssertLessThanOrEqual(report.maxCpuGeometryTimeMs, 0.05)
        XCTAssertLessThan(report.peakVRAMBytes, 10 * 1024 * 1024)
        XCTAssertEqual(report.droppedFrameCount, 0)
        
        print("📊 Live MetalFogEngine Adapter Telemetry: avgFPS=\(report.averageFPS), maxGPU=\(report.maxGpuTimeMs)ms, maxCPU=\(report.maxCpuGeometryTimeMs)ms, peakVRAM=\(report.peakVRAMBytes)B")
        
        attachReportArtifact(report, filename: "PerformanceReport_ProductionAdapter.json")
    }
    
    // MARK: - 4. Performance Report JSON Schema Conformance (Doc 08 §5)
    
    func testPerformanceReportJSONSchemaConformance() throws {
        let sampleMetric = FrameMetric(
            frameIndex: 0,
            frameDurationMs: 8.31,
            gpuDurationMs: 4.92,
            cpuDurationMs: 0.02,
            vramUsageBytes: 9646896,
            ramFootprintBytes: 42106880,
            isDroppedFrame: false
        )
        
        let sampleReport = PerformanceReport(
            testRunID: UUID(uuidString: "7F9C4A1B-823E-4C09-A124-91BF82D42031")!,
            timestamp: Date(timeIntervalSince1970: 1774886652),
            hexCount: 100000,
            totalFramesRecorded: 240,
            averageFPS: 119.91,
            p95FrameTimeMs: 8.18,
            p99FrameTimeMs: 8.31,
            maxGpuTimeMs: 5.14,
            maxCpuGeometryTimeMs: 0.02,
            peakVRAMBytes: 9646896,
            peakRAMBytes: 42106880,
            droppedFrameCount: 0,
            frameMetrics: [sampleMetric]
        )
        
        let jsonData = try sampleReport.toJSONData()
        XCTAssertFalse(jsonData.isEmpty)
        
        guard let jsonDict = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            XCTFail("JSON output must be a valid dictionary")
            return
        }
        
        // Assert all required properties per Doc 08 §5 schema
        let requiredKeys = [
            "testRunID", "timestamp", "hexCount", "totalFramesRecorded", "averageFPS",
            "p95FrameTimeMs", "p99FrameTimeMs", "maxGpuTimeMs", "maxCpuGeometryTimeMs",
            "peakVRAMBytes", "peakRAMBytes", "droppedFrameCount", "frameMetrics"
        ]
        for key in requiredKeys {
            XCTAssertNotNil(jsonDict[key], "Missing required schema key: \(key)")
        }
        
        XCTAssertEqual(jsonDict["hexCount"] as? Int, 100000)
        XCTAssertEqual(jsonDict["totalFramesRecorded"] as? Int, 240)
        XCTAssertEqual(jsonDict["droppedFrameCount"] as? Int, 0)
        
        // Roundtrip decoding
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decodedReport = try decoder.decode(PerformanceReport.self, from: jsonData)
        XCTAssertEqual(decodedReport.testRunID, sampleReport.testRunID)
        XCTAssertEqual(decodedReport.hexCount, sampleReport.hexCount)
        XCTAssertEqual(decodedReport.totalFramesRecorded, sampleReport.totalFramesRecorded)
        XCTAssertEqual(decodedReport.averageFPS, sampleReport.averageFPS, accuracy: 1e-4)
        XCTAssertEqual(decodedReport.frameMetrics.count, 1)
        XCTAssertEqual(decodedReport.frameMetrics[0], sampleMetric)
    }
    
    // MARK: - 5. GPU-Accelerated RMSD Visual Parity Test (Doc 08 §7)
    
    func testOffscreenRMSDVisualParity() throws {
        guard let device = device else {
            throw XCTSkip("No system default MTLDevice available on this test host")
        }
        
        let visualParity = try MetalFogVisualParity(device: device)
        
        let width = 256
        let height = 256
        let texDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        texDesc.usage = [.shaderRead, .shaderWrite]
        
        guard let texA = device.makeTexture(descriptor: texDesc),
              let texB = device.makeTexture(descriptor: texDesc) else {
            XCTFail("Failed to allocate test textures")
            return
        }
        
        // Initialize texA and texB with identical baseline pattern
        var basePixels = [UInt8](repeating: 200, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let idx = (y * width + x) * 4
                basePixels[idx] = UInt8(x % 256)       // R
                basePixels[idx + 1] = UInt8(y % 256)   // G
                basePixels[idx + 2] = 50               // B
                basePixels[idx + 3] = 255              // A
            }
        }
        
        texA.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0, withBytes: basePixels, bytesPerRow: width * 4)
        texB.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0, withBytes: basePixels, bytesPerRow: width * 4)
        
        // 1. Identical textures must yield exact zero RMSD
        let (exactZeroRMSD, _) = try visualParity.computeRMSD(textureA: texA, textureB: texB)
        XCTAssertEqual(exactZeroRMSD, 0.0, accuracy: 1e-6, "RMSD between identical textures must be exactly 0.0")
        
        // 2. Sub-pixel delta across a small boundary zone:
        // Introduce subtle 1-unit LSB variation in 50 pixels
        var modifiedPixels = basePixels
        for i in 0..<50 {
            modifiedPixels[i * 4] = modifiedPixels[i * 4] ^ 1 // 1/255 delta on red
        }
        texB.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0, withBytes: modifiedPixels, bytesPerRow: width * 4)
        
        let (subtleRMSD, diffTex) = try visualParity.computeRMSD(textureA: texA, textureB: texB)
        XCTAssertGreaterThan(subtleRMSD, 0.0, "RMSD must detect pixel variations")
        XCTAssertLessThan(subtleRMSD, 0.001, "RMSD must remain below 0.001 threshold for sub-pixel boundary tolerances (measured: \(subtleRMSD))")
        XCTAssertEqual(diffTex.width, width)
        XCTAssertEqual(diffTex.height, height)
    }
    
    // MARK: - 6. Darwin Mach Kernel Memory Footprint Telemetry (Doc 08 §2)
    
    func testDarwinMachKernelMemoryTelemetry() {
        let footprint = TelemetryCollector.getProcessMemoryFootprint()
        XCTAssertGreaterThan(footprint, 0, "Mach kernel phys_footprint must return non-zero resident process memory")
        print("🧠 Measured Darwin Mach Kernel process physical memory footprint: \(footprint / 1024 / 1024) MB")
    }
    
    // MARK: - Helper Methods
    
    private func attachReportArtifact(_ report: PerformanceReport, filename: String) {
        if let data = try? report.toJSONData() {
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
            try? data.write(to: tempURL)
            let attachment = XCTAttachment(contentsOfFile: tempURL)
            attachment.name = "MetalFogEngine Performance Telemetry - \(filename)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }
}
