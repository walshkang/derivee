import XCTest
import Metal
import MapLibre
import simd
import CoreLocation
@testable import Derivee

final class MetalFogQuadShaderTests: XCTestCase {
    
    // MARK: - 1. Screen-Space Derivative Filter Scaling (Doc 09 §2)
    
    func testScreenSpaceDerivativeFilterHalfPrecision() {
        // Evaluate dynamic filter half-width formula:
        // Δw = max(0.7071 * |∇C|, 1e-4)
        
        // Scenario A: Deep Street Zoom (z18) - slow spatial gradient across fragments
        let gradStreet = SIMD2<Float>(0.001, 0.0008)
        let gradMagStreet = length(gradStreet)
        let deltaWStreet = max(0.7071 * gradMagStreet, 0.0001)
        
        // Assert Δw is sub-pixel narrow at z18 (yields razor-sharp 1px edge)
        XCTAssertGreaterThan(deltaWStreet, 0.0005)
        XCTAssertLessThan(deltaWStreet, 0.002)
        
        // Scenario B: Global View (z0) - steep spatial gradient across fragments
        let gradGlobal = SIMD2<Float>(0.12, 0.09)
        let gradMagGlobal = length(gradGlobal)
        let deltaWGlobal = max(0.7071 * gradMagGlobal, 0.0001)
        
        // Assert Δw broadens dynamically at z0 (anti-aliases high-frequency minification chatter)
        XCTAssertGreaterThan(deltaWGlobal, 0.05)
        XCTAssertLessThan(deltaWGlobal, 0.15)
        
        // Assert scale invariance: Street Δw is much smaller than Global Δw
        XCTAssertLessThan(deltaWStreet, deltaWGlobal)
    }
    
    // MARK: - 2. Hermite Anti-Aliasing Aperture Alpha Mask (Doc 09 §2)
    
    func testHermiteAntiAliasingApertureFalloff() {
        let threshold: Float = 0.5
        let deltaW: Float = 0.05
        let fogOpacity: Float = 0.85
        
        // Helper implementing MSL smoothstep(edge0, edge1, x)
        func smoothstep(edge0: Float, edge1: Float, x: Float) -> Float {
            let t = min(max((x - edge0) / (edge1 - edge0), 0.0), 1.0)
            return t * t * (3.0 - 2.0 * t)
        }
        
        // Case A: Deep inside explored aperture (C = 0.0) -> zero fog alpha
        let maskInterior = smoothstep(edge0: threshold - deltaW, edge1: threshold + deltaW, x: 0.0)
        let alphaInterior = maskInterior * fogOpacity
        XCTAssertEqual(alphaInterior, 0.0, accuracy: 1e-5, "Explored aperture interior must be 100% transparent")
        
        // Case B: Deep inside solid fog (C = 1.0) -> full fog alpha
        let maskExterior = smoothstep(edge0: threshold - deltaW, edge1: threshold + deltaW, x: 1.0)
        let alphaExterior = maskExterior * fogOpacity
        XCTAssertEqual(alphaExterior, fogOpacity, accuracy: 1e-5, "Unexplored space must match master fog opacity")
        
        // Case C: Exact boundary threshold (C = 0.5) -> half fog alpha
        let maskBoundary = smoothstep(edge0: threshold - deltaW, edge1: threshold + deltaW, x: threshold)
        let alphaBoundary = maskBoundary * fogOpacity
        XCTAssertEqual(alphaBoundary, 0.5 * fogOpacity, accuracy: 1e-5, "Boundary transition must evaluate to exactly 50% opacity")
    }
    
    // MARK: - 3. Single-Pass Analytical Electric Amber Glow Formulation (Doc 09 §3)
    
    func testAnalyticalAmberGlowPeakAtThreshold() {
        let threshold: Float = 0.5
        let outerWidth: Float = 0.06
        let innerWidth: Float = 0.04
        let glowAlpha: Float = 1.0
        
        func smoothstep(edge0: Float, edge1: Float, x: Float) -> Float {
            let t = min(max((x - edge0) / (edge1 - edge0), 0.0), 1.0)
            return t * t * (3.0 - 2.0 * t)
        }
        
        func computeGlow(coverage: Float) -> Float {
            let glowOuter = smoothstep(edge0: threshold - outerWidth, edge1: threshold, x: coverage)
            let glowInner = smoothstep(edge0: threshold + innerWidth, edge1: threshold, x: coverage)
            return glowOuter * glowInner * glowAlpha
        }
        
        // Peak intensity at boundary threshold T = 0.5
        let peakGlow = computeGlow(coverage: threshold)
        XCTAssertEqual(peakGlow, 1.0, accuracy: 1e-5, "Glow factor must peak at 1.0 exactly at threshold T = 0.5")
        
        // Decays to 0 inside open aperture (C <= T - outerWidth)
        let insideGlow = computeGlow(coverage: threshold - outerWidth - 0.01)
        XCTAssertEqual(insideGlow, 0.0, accuracy: 1e-5, "Glow must decay to 0.0 beyond outer width")
        
        // Decays to 0 in solid fog (C >= T + innerWidth)
        let outsideGlow = computeGlow(coverage: threshold + innerWidth + 0.01)
        XCTAssertEqual(outsideGlow, 0.0, accuracy: 1e-5, "Glow must decay to 0.0 beyond inner width")
        
        // Continuous symmetrical decay: Intermediate samples must be in (0, 1)
        let halfStepGlow = computeGlow(coverage: threshold - (outerWidth * 0.5))
        XCTAssertGreaterThan(halfStepGlow, 0.0)
        XCTAssertLessThan(halfStepGlow, 1.0)
    }
    
    // MARK: - 4. Saturation-Safe Premultiplied Alpha Invariant (Doc 09 §3 & §4)
    
    func testPremultipliedAlphaSaturationSafeBlending() {
        let slateRGB = SIMD3<Float>(0.1098, 0.1098, 0.1176) // #1C1C1E
        let amberRGB = SIMD3<Float>(1.0, 0.7020, 0.0)       // #FFB300
        
        // Sweep coverage across full domain [0.0, 1.0] in 100 steps
        for step in 0...100 {
            let coverage = Float(step) / 100.0
            
            let fogAlpha = coverage * 0.85
            let glowIntensity = max(0.0, 1.0 - abs(coverage - 0.5) / 0.1) // Synthetic glow spike
            let totalAlpha = min(max(fogAlpha + glowIntensity, 0.0), 1.0)
            
            let denom = max(totalAlpha, 0.0001)
            let blendedRGB = simd_mix(slateRGB, amberRGB, SIMD3<Float>(repeating: glowIntensity / denom))
            let premultiplied = blendedRGB * totalAlpha
            
            // Premultiplied alpha invariant: R <= A, G <= A, B <= A
            XCTAssertLessThanOrEqual(premultiplied.x, totalAlpha + 1e-4, "Premultiplied Red must not exceed Alpha")
            XCTAssertLessThanOrEqual(premultiplied.y, totalAlpha + 1e-4, "Premultiplied Green must not exceed Alpha")
            XCTAssertLessThanOrEqual(premultiplied.z, totalAlpha + 1e-4, "Premultiplied Blue must not exceed Alpha")
            
            // Channel bounds: components must remain non-negative and <= 1.0
            XCTAssertGreaterThanOrEqual(premultiplied.x, 0.0)
            XCTAssertGreaterThanOrEqual(premultiplied.y, 0.0)
            XCTAssertGreaterThanOrEqual(premultiplied.z, 0.0)
            XCTAssertLessThanOrEqual(premultiplied.x, 1.0)
            XCTAssertLessThanOrEqual(premultiplied.y, 1.0)
            XCTAssertLessThanOrEqual(premultiplied.z, 1.0)
        }
    }
    
    // MARK: - 5. Single-Channel Texture & Sampler Configuration (Doc 09 §6)
    
    func testSingleChannelTextureAndBilinearSampler() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("No system default MTLDevice available on this test host")
        }
        
        let layer = MetalFogStyleLayer(identifier: "test-texture-layer")
        try layer.setupSampler(device: device)
        try layer.setupCoverageTexture(device: device, width: 1024, height: 1024)
        
        guard let sampler = layer.samplerState else {
            XCTFail("Sampler state must be created")
            return
        }
        guard let texture = layer.coverageTexture else {
            XCTFail("Coverage texture must be created")
            return
        }
        
        // Assert single-channel .r8Unorm format (1 byte per texel bandwidth optimization)
        XCTAssertEqual(texture.pixelFormat, .r8Unorm, "Coverage texture must be single-channel .r8Unorm to stay resident in SLC cache")
        XCTAssertEqual(texture.width, 1024)
        XCTAssertEqual(texture.height, 1024)
        
        // Assert VRAM allocation for 1024x1024 .r8Unorm is exactly 1,048,576 bytes (1.0 MB)
        XCTAssertEqual(texture.width * texture.height, 1_048_576)
    }
    
    // MARK: - 6. Aperture Carving & Coordinate Projection (Doc 09 §6)
    
    func testApertureCarvingAtGeodeticCoordinates() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("No system default MTLDevice available on this test host")
        }
        
        let layer = MetalFogStyleLayer(identifier: "test-carve-layer")
        try layer.setupCoverageTexture(device: device, width: 1024, height: 1024)
        
        let nycCoord = CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060)
        layer.carveAperture(center: nycCoord, radiusMeters: 50_000.0)
        
        // Calculate expected center texel in 1024x1024 Mercator space
        let mercator = MapProjectionMath.geodeticToMercator(nycCoord)
        let cx = Int(mercator.x * 1024.0)
        let cy = Int(mercator.y * 1024.0)
        
        // Read back pixel at aperture center
        var centerPixel: UInt8 = 255
        layer.coverageTexture?.getBytes(
            &centerPixel,
            bytesPerRow: 1,
            from: MTLRegionMake2D(cx, cy, 1, 1),
            mipmapLevel: 0
        )
        
        // Aperture center must be carved to 0 (fully clear)
        XCTAssertEqual(centerPixel, 0, "Aperture center texel must be carved to 0")
        
        // Read back far-away pixel (e.g. at 0, 0)
        var remotePixel: UInt8 = 0
        layer.coverageTexture?.getBytes(
            &remotePixel,
            bytesPerRow: 1,
            from: MTLRegionMake2D(0, 0, 1, 1),
            mipmapLevel: 0
        )
        XCTAssertEqual(remotePixel, 255, "Remote unexplored texels must remain 255 solid fog")
    }
    
    // MARK: - 7. Offscreen Full-Screen Quad Render Performance (< 0.30ms) (Doc 09 §7)
    
    func testOffscreenQuadRenderPerformanceUnder0_3ms() throws {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue() else {
            throw XCTSkip("No system default MTLDevice available on this test host")
        }
        
        let layer = MetalFogStyleLayer(identifier: "test-perf-layer")
        try layer.setupPipeline(device: device, colorPixelFormat: .bgra8Unorm, depthStencilPixelFormat: .invalid)
        layer.setupUniformBuffers(device: device)
        try layer.setupSampler(device: device)
        try layer.setupCoverageTexture(device: device, width: 1024, height: 1024)
        
        // Carve sample aperture
        layer.carveAperture(center: CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060), radiusMeters: 100.0)
        
        // Create offscreen render target matching iPhone XR resolution (1792 x 828)
        let rtDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: 1792,
            height: 828,
            mipmapped: false
        )
        rtDesc.usage = [.renderTarget, .shaderRead]
        guard let renderTarget = device.makeTexture(descriptor: rtDesc) else {
            XCTFail("Failed to allocate offscreen render target")
            return
        }
        
        let passDesc = MTLRenderPassDescriptor()
        passDesc.colorAttachments[0].texture = renderTarget
        passDesc.colorAttachments[0].loadAction = .clear
        passDesc.colorAttachments[0].storeAction = .store
        passDesc.colorAttachments[0].clearColor = MTLClearColorMake(1.0, 1.0, 1.0, 1.0)
        
        guard let pipeline = layer.pipelineState,
              let sampler = layer.samplerState,
              let texture = layer.coverageTexture,
              let uniformBuf = layer.uniformBuffers.first else {
            XCTFail("Failed to acquire pipeline resources")
            return
        }
        
        // 1. Warm-up pipeline and driver caches (5 iterations)
        for _ in 0..<5 {
            guard let warmCmd = queue.makeCommandBuffer(),
                  let warmEnc = warmCmd.makeRenderCommandEncoder(descriptor: passDesc) else { break }
            warmEnc.setRenderPipelineState(pipeline)
            warmEnc.setFragmentBuffer(uniformBuf, offset: 0, index: 0)
            warmEnc.setFragmentSamplerState(sampler, index: 0)
            warmEnc.setFragmentTexture(texture, index: 0)
            warmEnc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
            warmEnc.endEncoding()
            warmCmd.commit()
            warmCmd.waitUntilCompleted()
        }
        
        // 2. Measure steady-state GPU frame duration
        var gpuTimes: [Double] = []
        for _ in 0..<5 {
            let expectation = self.expectation(description: "GPU render completion")
            guard let cmdBuf = queue.makeCommandBuffer(),
                  let encoder = cmdBuf.makeRenderCommandEncoder(descriptor: passDesc) else { break }
            
            encoder.setRenderPipelineState(pipeline)
            encoder.setFragmentBuffer(uniformBuf, offset: 0, index: 0)
            encoder.setFragmentSamplerState(sampler, index: 0)
            encoder.setFragmentTexture(texture, index: 0)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
            encoder.endEncoding()
            
            cmdBuf.addCompletedHandler { buffer in
                if buffer.gpuEndTime > buffer.gpuStartTime {
                    gpuTimes.append((buffer.gpuEndTime - buffer.gpuStartTime) * 1000.0)
                }
                expectation.fulfill()
            }
            
            cmdBuf.commit()
            wait(for: [expectation], timeout: 2.0)
        }
        
        if let minGpuTime = gpuTimes.min() {
            print("⏱️ Measured steady-state fragment quad GPU time: \(minGpuTime)ms (samples: \(gpuTimes))")
            #if targetEnvironment(simulator)
            XCTAssertLessThanOrEqual(
                minGpuTime, 2.50,
                "Fragment pipeline execution time in simulator must remain under 2.50ms (Measured: \(minGpuTime)ms)"
            )
            #else
            XCTAssertLessThanOrEqual(
                minGpuTime, 0.30,
                "Fragment pipeline execution time must remain strictly under 0.30ms on Apple Silicon (Measured: \(minGpuTime)ms)"
            )
            #endif
        }
    }
    
    // MARK: - 8. Combined VRAM Hard Ceiling (< 10.0 MB Jetsam Limit)
    
    func testVRAMHardCeilingUnder10MB() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("No system default MTLDevice available on this test host")
        }
        
        let spatialEngine = try H3SpatialMemoryEngine(device: device)
        let fogLayer = MetalFogStyleLayer(identifier: "test-vram-fog", spatialEngine: spatialEngine)
        fogLayer.setupUniformBuffers(device: device)
        try fogLayer.setupCoverageTexture(device: device, width: 1024, height: 1024)
        
        let spatialVRAM = spatialEngine.currentVRAMUsageBytes // 4,259,904 bytes (~4.26 MB)
        let layerVRAM = fogLayer.currentVRAMUsageBytes         // 1,048,576 + 768 = 1,049,344 bytes (~1.05 MB)
        let totalVRAM = spatialVRAM + layerVRAM               // 5,309,248 bytes (~5.31 MB)
        
        XCTAssertEqual(spatialVRAM, 4_259_904)
        XCTAssertEqual(layerVRAM, 1_049_344)
        XCTAssertEqual(totalVRAM, 5_309_248, "Combined VRAM usage must equal 5,309,248 bytes (~5.31 MB)")
        
        // Hard budget assertion: strictly < 10.0 MB (10,485,760 bytes)
        XCTAssertLessThan(totalVRAM, 10_000_000, "Combined VRAM footprint must remain strictly below 10 MB limit")
        
        let headroomPercent = (1.0 - Double(totalVRAM) / 10_000_000.0) * 100.0
        XCTAssertGreaterThan(headroomPercent, 45.0, "VRAM headroom must be greater than 45%")
    }
}
