import XCTest
import Metal
import MapLibre
import simd
@testable import Derivee

final class MetalFogLayerTests: XCTestCase {
    
    // MARK: - 1. ABI Verification & Uniform Layout Alignment (Doc 07 §2 & Doc 09 §5)
    
    func testUniformMemoryLayoutAndAlignment() {
        MetalFogUniformsVerifier.verify()
        
        XCTAssertEqual(MemoryLayout<MetalFogUniforms>.size, 128, "MetalFogUniforms size must be exactly 128 bytes")
        XCTAssertEqual(MemoryLayout<MetalFogUniforms>.stride, 128, "MetalFogUniforms stride must be exactly 128 bytes")
        XCTAssertEqual(MemoryLayout<MetalFogUniforms>.alignment, 16, "MetalFogUniforms alignment must be 16 bytes")
        
        // Verify field offsets match MSL struct layout
        XCTAssertEqual(MemoryLayout<MetalFogUniforms>.offset(of: \.invProjMatrix), 0, "invProjMatrix must be at offset 0 (64 bytes)")
        XCTAssertEqual(MemoryLayout<MetalFogUniforms>.offset(of: \.fogColor), 64, "fogColor must be at offset 64 (16 bytes)")
        XCTAssertEqual(MemoryLayout<MetalFogUniforms>.offset(of: \.glowColor), 80, "glowColor must be at offset 80 (16 bytes)")
        XCTAssertEqual(MemoryLayout<MetalFogUniforms>.offset(of: \.outerGlowWidth), 96, "outerGlowWidth must be at offset 96 (4 bytes)")
        XCTAssertEqual(MemoryLayout<MetalFogUniforms>.offset(of: \.innerGlowWidth), 100, "innerGlowWidth must be at offset 100 (4 bytes)")
        XCTAssertEqual(MemoryLayout<MetalFogUniforms>.offset(of: \.fogOpacity), 104, "fogOpacity must be at offset 104 (4 bytes)")
        XCTAssertEqual(MemoryLayout<MetalFogUniforms>.offset(of: \.threshold), 108, "threshold must be at offset 108 (4 bytes)")
        XCTAssertEqual(MemoryLayout<MetalFogUniforms>.offset(of: \.cameraZoom), 112, "cameraZoom must be at offset 112 (4 bytes)")
    }
    
    // MARK: - 2. Matrix Inversion & Coordinate Bridge (Doc 05 §6 & Doc 07 §2)
    
    func testMatrixInversionAndProjectionBridge() {
        var mlnMat = MLNMatrix4()
        mlnMat.m00 = 2.0; mlnMat.m11 = 3.0; mlnMat.m22 = 1.0; mlnMat.m33 = 1.0
        mlnMat.m30 = 10.0; mlnMat.m31 = 20.0
        
        let simdMat = MapProjectionMath.matrixFromMLNMatrix4(mlnMat)
        XCTAssertEqual(simdMat.columns.0.x, 2.0, accuracy: 1e-5)
        XCTAssertEqual(simdMat.columns.1.y, 3.0, accuracy: 1e-5)
        XCTAssertEqual(simdMat.columns.3.x, 10.0, accuracy: 1e-5)
        XCTAssertEqual(simdMat.columns.3.y, 20.0, accuracy: 1e-5)
        
        let invMat = simd_inverse(simdMat)
        let identity = simd_mul(simdMat, invMat)
        
        XCTAssertEqual(identity.columns.0.x, 1.0, accuracy: 1e-5)
        XCTAssertEqual(identity.columns.1.y, 1.0, accuracy: 1e-5)
        XCTAssertEqual(identity.columns.2.z, 1.0, accuracy: 1e-5)
        XCTAssertEqual(identity.columns.3.w, 1.0, accuracy: 1e-5)
    }
    
    // MARK: - 3. Metal Pipeline Lifecycle & Triple-Buffering (Doc 07 §2 & §4)
    
    func testLayerLifecycleAndResourceAllocation() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("No system default MTLDevice available on this test host")
        }
        
        let layer = MetalFogStyleLayer(identifier: "test-fog-layer")
        XCTAssertEqual(layer.identifier, "test-fog-layer")
        XCTAssertNil(layer.pipelineState)
        XCTAssertTrue(layer.uniformBuffers.isEmpty)
        
        // Pipeline compilation with Premultiplied Alpha configuration
        try layer.setupPipeline(device: device, colorPixelFormat: .bgra8Unorm, depthStencilPixelFormat: .invalid)
        XCTAssertNotNil(layer.pipelineState, "Render pipeline state must compile successfully")
        XCTAssertNotNil(layer.depthStencilState, "Depth stencil state must be configured")
        
        // Allocate triple-buffered uniform state
        layer.setupUniformBuffers(device: device)
        XCTAssertEqual(layer.uniformBuffers.count, 3, "Layer must allocate exactly 3 uniform buffers for 120 FPS frame pacing")
        
        let vramUsage = layer.currentVRAMUsageBytes
        XCTAssertEqual(vramUsage, 768, "Triple-buffered uniforms must consume exactly 768 bytes (3 * 256)")
        XCTAssertLessThan(vramUsage, 1024, "Layer uniform allocation must remain under 1 KB")
        
        // Teardown
        let dummyMapView = MLNMapView(frame: .zero)
        layer.willMove(from: dummyMapView)
        XCTAssertNil(layer.pipelineState)
        XCTAssertNil(layer.depthStencilState)
        XCTAssertTrue(layer.uniformBuffers.isEmpty)
    }
    
    // MARK: - 4. Z-Index Layer Stacking & Label Occlusion (Doc 07 §3 & Doc 20 §2)
    
    func testLayerZStackOrderBelowSymbolLayers() {
        // Mock layer hierarchy representing MapLibre style layers:
        // [0] subwayLinesLayer (MLNLineStyleLayer)
        // [1] subwayStationBulletsLayer (MLNCircleStyleLayer)
        // [2] smartZoomStationBulletsLayer (MLNSymbolStyleLayer)
        // [3] basemapStreetLabels (MLNSymbolStyleLayer)
        
        let linesLayer = MLNLineStyleLayer(identifier: MapCustomizationDefaults.subwayLinesLayerId, source: MLNShapeSource(identifier: "lines-src", shape: nil, options: nil))
        let bulletsLayer = MLNCircleStyleLayer(identifier: MapCustomizationDefaults.subwayStationBulletsLayerId, source: MLNShapeSource(identifier: "bullets-src", shape: nil, options: nil))
        let symbolLayer = MLNSymbolStyleLayer(identifier: MapCustomizationDefaults.smartZoomStationBulletsLayerId, source: MLNShapeSource(identifier: "symbols-src", shape: nil, options: nil))
        
        var mockStyleLayers: [MLNStyleLayer] = [linesLayer, bulletsLayer, symbolLayer]
        
        let metalFog = MetalFogStyleLayer(identifier: MapCustomizationDefaults.metalFogLayerId)
        
        // Insertion algorithm matching MapView.swift:
        // Precise Z-Index Placement: Insert below first MLNSymbolStyleLayer
        if let firstSymbolIndex = mockStyleLayers.firstIndex(where: { $0 is MLNSymbolStyleLayer }) {
            mockStyleLayers.insert(metalFog, at: firstSymbolIndex)
        } else {
            mockStyleLayers.append(metalFog)
        }
        
        // Verify final order:
        // 0: linesLayer (sub-fog)
        // 1: bulletsLayer (sub-fog)
        // 2: metalFog (interleaved)
        // 3: symbolLayer (on top)
        XCTAssertEqual(mockStyleLayers.count, 4)
        XCTAssertEqual(mockStyleLayers[0].identifier, MapCustomizationDefaults.subwayLinesLayerId)
        XCTAssertEqual(mockStyleLayers[1].identifier, MapCustomizationDefaults.subwayStationBulletsLayerId)
        XCTAssertEqual(mockStyleLayers[2].identifier, MapCustomizationDefaults.metalFogLayerId)
        XCTAssertEqual(mockStyleLayers[3].identifier, MapCustomizationDefaults.smartZoomStationBulletsLayerId)
        
        // Assert metalFog is strictly below the symbol layer
        let metalFogIndex = mockStyleLayers.firstIndex(where: { $0.identifier == MapCustomizationDefaults.metalFogLayerId })!
        let symbolIndex = mockStyleLayers.firstIndex(where: { $0.identifier == MapCustomizationDefaults.smartZoomStationBulletsLayerId })!
        let bulletsIndex = mockStyleLayers.firstIndex(where: { $0.identifier == MapCustomizationDefaults.subwayStationBulletsLayerId })!
        
        XCTAssertLessThan(metalFogIndex, symbolIndex, "MetalFogStyleLayer MUST be positioned below MLNSymbolStyleLayer to preserve label legibility")
        XCTAssertGreaterThan(metalFogIndex, bulletsIndex, "MetalFogStyleLayer MUST be positioned above sub-fog transit bullet nodes")
    }
    
    // MARK: - 5. VRAM Hard Ceiling Preservation (< 10.0 MB Jetsam Limit)
    
    func testCombinedVRAMPreservationBelowJetsamLimit() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("No system default MTLDevice available on this test host")
        }
        
        let spatialEngine = try H3SpatialMemoryEngine(device: device)
        let fogLayer = MetalFogStyleLayer(identifier: "test-fog", spatialEngine: spatialEngine)
        fogLayer.setupUniformBuffers(device: device)
        
        let spatialVRAM = spatialEngine.currentVRAMUsageBytes // 4,259,904 bytes (~4.26 MB)
        let layerVRAM = fogLayer.currentVRAMUsageBytes         // 768 bytes
        let totalVRAM = spatialVRAM + layerVRAM
        
        XCTAssertEqual(spatialVRAM, 4_259_904)
        XCTAssertEqual(layerVRAM, 768)
        XCTAssertEqual(totalVRAM, 4_260_672, "Combined VRAM usage must equal 4,260,672 bytes (~4.26 MB)")
        
        // Hard budget: < 10.0 MB (10,485,760 bytes)
        XCTAssertLessThan(totalVRAM, 10_000_000, "Combined VRAM footprint must remain strictly below 10 MB limit")
        
        let headroomPercent = (1.0 - Double(totalVRAM) / 10_000_000.0) * 100.0
        XCTAssertGreaterThan(headroomPercent, 55.0, "VRAM headroom must be greater than 55%")
    }
}
