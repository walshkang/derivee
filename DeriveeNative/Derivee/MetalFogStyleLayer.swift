import Foundation
import Metal
import MetalKit
import simd
import MapLibre

/// Hardware-accelerated Metal custom style layer executing directly inside MapLibre Native's iOS render pass.
/// Reuses the active `id<MTLRenderCommandEncoder>` (`self.renderEncoder`), inserts below `MLNSymbolStyleLayer`
/// to preserve label legibility, and guarantees zero auxiliary framebuffer allocations (< 10 MB VRAM ceiling).
/// Strictly adheres to `docs/research/07_metal_layer_injection_compositing_maplibre.md` and
/// `docs/research/09_metal_shading_pipeline_sdf_edge_glow.md`.
public final class MetalFogStyleLayer: MLNCustomStyleLayer, @unchecked Sendable {
    
    public static let defaultLayerIdentifier = "metal-fog-layer"
    
    // MARK: - Spatial Memory Engine Reference
    
    public weak var spatialEngine: H3SpatialMemoryEngine?
    
    // MARK: - Metal Pipeline Objects
    
    public private(set) var pipelineState: MTLRenderPipelineState?
    public private(set) var depthStencilState: MTLDepthStencilState?
    public private(set) var coverageTexture: MTLTexture?
    public private(set) var samplerState: MTLSamplerState?
    public let coverageResolution: Int = 1024
    private var coverageData: [UInt8] = []
    
    /// Triple-buffered uniform ring buffers (3 in-flight frames) to prevent CPU/GPU execution stalls at 120 FPS.
    public private(set) var uniformBuffers: [MTLBuffer] = []
    public private(set) var uniformBufferIndex: Int = 0
    private let uniformBufferCount = 3
    private let uniformBufferSize = 256
    
    // MARK: - Dynamic Styling Parameters
    
    public var fogSlateColor = simd_float4(0.1098, 0.1098, 0.1176, 1.0) // #1C1C1E
    public var electricAmberColor = simd_float4(1.0, 0.7020, 0.0, 1.0)  // #FFB300
    public var fogOpacity: Float = 0.85
    public var outerGlowWidth: Float = 0.06
    public var innerGlowWidth: Float = 0.04
    public var threshold: Float = 0.5
    
    // MARK: - Initializers
    
    public init(identifier: String = defaultLayerIdentifier, spatialEngine: H3SpatialMemoryEngine? = nil) {
        self.spatialEngine = spatialEngine
        super.init(identifier: identifier)
    }
    
    // MARK: - MLNCustomStyleLayer Lifecycle
    
    public override func didMove(to mapView: MLNMapView) {
        super.didMove(to: mapView)
        
        let backendResource = mapView.backendResource()
        guard let device = backendResource.device ?? MTLCreateSystemDefaultDevice() else {
            print("[MetalFogStyleLayer] Warning: No MTLDevice available.")
            return
        }
        
        let colorPixelFormat = backendResource.mtkView?.colorPixelFormat ?? .bgra8Unorm
        let depthStencilPixelFormat = backendResource.mtkView?.depthStencilPixelFormat ?? .depth32Float_stencil8
        
        do {
            try setupPipeline(
                device: device,
                colorPixelFormat: colorPixelFormat,
                depthStencilPixelFormat: depthStencilPixelFormat
            )
            setupUniformBuffers(device: device)
            try setupSampler(device: device)
            try setupCoverageTexture(device: device, width: coverageResolution, height: coverageResolution)
        } catch {
            print("[MetalFogStyleLayer] Failed to initialize Metal pipeline: \(error)")
        }
    }
    
    public override func draw(in mapView: MLNMapView, with context: MLNStyleLayerDrawingContext) {
        guard let pipelineState = pipelineState,
              !uniformBuffers.isEmpty else { return }
        
        // Retrieve active MTLRenderCommandEncoder exposed directly on MLNCustomStyleLayer
        guard let encoder = self.renderEncoder as? (any MTLRenderCommandEncoder) else { return }
        
        // 1. Convert context projection matrix to simd_float4x4
        let projMatrix = MapProjectionMath.matrixFromMLNMatrix4(context.projectionMatrix)
        let invProjMatrix = simd_inverse(projMatrix)
        
        // 2. Advance uniform buffer ring index
        uniformBufferIndex = (uniformBufferIndex + 1) % uniformBufferCount
        let currentUniformBuffer = uniformBuffers[uniformBufferIndex]
        
        // 3. Populate uniform parameters
        var uniforms = MetalFogUniforms(
            invProjMatrix: invProjMatrix,
            fogColor: fogSlateColor,
            glowColor: electricAmberColor,
            outerGlowWidth: outerGlowWidth,
            innerGlowWidth: innerGlowWidth,
            fogOpacity: fogOpacity,
            threshold: threshold,
            cameraZoom: Float(context.zoomLevel)
        )
        memcpy(currentUniformBuffer.contents(), &uniforms, MemoryLayout<MetalFogUniforms>.stride)
        
        // 4. Encode draw commands directly into MapLibre's active pass
        encoder.setRenderPipelineState(pipelineState)
        if let depthState = depthStencilState {
            encoder.setDepthStencilState(depthState)
        }
        
        encoder.setVertexBuffer(currentUniformBuffer, offset: 0, index: 0)
        encoder.setFragmentBuffer(currentUniformBuffer, offset: 0, index: 0)
        
        if let sampler = samplerState {
            encoder.setFragmentSamplerState(sampler, index: 0)
        }
        if let texture = coverageTexture {
            encoder.setFragmentTexture(texture, index: 0)
        }
        
        if let engine = spatialEngine {
            if let hashTable = engine.hashTableBuffer {
                encoder.setFragmentBuffer(hashTable, offset: 0, index: 1)
            }
            if let header = engine.headerBuffer {
                encoder.setFragmentBuffer(header, offset: 0, index: 2)
            }
        }
        
        // Draw 4 vertices of full-screen quad via triangle strip (O(1) constant vertex load)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
    }
    
    public override func willMove(from mapView: MLNMapView) {
        super.willMove(from: mapView)
        pipelineState = nil
        depthStencilState = nil
        samplerState = nil
        coverageTexture = nil
        coverageData.removeAll()
        uniformBuffers.removeAll()
    }
    
    // MARK: - Pipeline & Resource Setup
    
    public func setupPipeline(
        device: MTLDevice,
        colorPixelFormat: MTLPixelFormat,
        depthStencilPixelFormat: MTLPixelFormat = .depth32Float_stencil8
    ) throws {
        MetalFogUniformsVerifier.verify()
        
        // Dual-source library resolution: Bundle.main -> Framework Bundle -> default -> embedded MSL
        let library: MTLLibrary
        if let bundleLib = try? device.makeDefaultLibrary(bundle: Bundle.main) {
            library = bundleLib
        } else if let frameworkLib = try? device.makeDefaultLibrary(bundle: Bundle(for: MetalFogStyleLayer.self)) {
            library = frameworkLib
        } else if let defaultLib = try? device.makeDefaultLibrary() {
            library = defaultLib
        } else {
            library = try device.makeLibrary(source: MetalFogShaderEmbeddedSource, options: nil)
        }
        
        guard let vertexFunction = library.makeFunction(name: "vertexFogQuad") else {
            throw NSError(
                domain: "MetalFogStyleLayerError",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Vertex function 'vertexFogQuad' not found"]
            )
        }
        
        guard let fragmentFunction = library.makeFunction(name: "fragmentFogAperture") else {
            throw NSError(
                domain: "MetalFogStyleLayerError",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "Fragment function 'fragmentFogAperture' not found"]
            )
        }
        
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.label = "Metal Fog Style Layer Pipeline"
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        
        // Premultiplied Alpha Blend Configuration (Doc 09 §4)
        if let colorAttachment = pipelineDescriptor.colorAttachments[0] {
            colorAttachment.pixelFormat = colorPixelFormat
            colorAttachment.isBlendingEnabled = true
            
            colorAttachment.sourceRGBBlendFactor = .one
            colorAttachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
            colorAttachment.rgbBlendOperation = .add
            
            colorAttachment.sourceAlphaBlendFactor = .one
            colorAttachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha
            colorAttachment.alphaBlendOperation = .add
        }
        
        if depthStencilPixelFormat != .invalid {
            pipelineDescriptor.depthAttachmentPixelFormat = depthStencilPixelFormat
        }
        
        self.pipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        
        // Depth-Stencil state: depth write disabled to preserve depth buffer for subsequent symbol layers
        let depthDescriptor = MTLDepthStencilDescriptor()
        depthDescriptor.depthCompareFunction = .lessEqual
        depthDescriptor.isDepthWriteEnabled = false
        self.depthStencilState = device.makeDepthStencilState(descriptor: depthDescriptor)
    }
    
    public func setupUniformBuffers(device: MTLDevice) {
        uniformBuffers.removeAll()
        for _ in 0..<uniformBufferCount {
            if let buf = device.makeBuffer(length: uniformBufferSize, options: .storageModeShared) {
                uniformBuffers.append(buf)
            }
        }
    }
    
    public func setupSampler(device: MTLDevice) throws {
        let descriptor = MTLSamplerDescriptor()
        descriptor.minFilter = .linear
        descriptor.magFilter = .linear
        descriptor.mipFilter = .notMipmapped
        descriptor.sAddressMode = .clampToEdge
        descriptor.tAddressMode = .clampToEdge
        guard let state = device.makeSamplerState(descriptor: descriptor) else {
            throw NSError(
                domain: "MetalFogStyleLayerError",
                code: -3,
                userInfo: [NSLocalizedDescriptionKey: "Failed to create MTLSamplerState"]
            )
        }
        self.samplerState = state
    }
    
    public func setupCoverageTexture(device: MTLDevice, width: Int = 1024, height: Int = 1024) throws {
        let textureDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        textureDesc.usage = [.shaderRead, .shaderWrite]
        textureDesc.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: textureDesc) else {
            throw NSError(
                domain: "MetalFogStyleLayerError",
                code: -4,
                userInfo: [NSLocalizedDescriptionKey: "Failed to allocate coverageTexture (.r8Unorm)"]
            )
        }
        self.coverageTexture = texture
        self.coverageData = [UInt8](repeating: 255, count: width * height)
        resetCoverageTexture()
    }
    
    public func resetCoverageTexture() {
        guard let texture = coverageTexture else { return }
        let width = texture.width
        let height = texture.height
        if coverageData.count != width * height {
            coverageData = [UInt8](repeating: 255, count: width * height)
        } else {
            coverageData.withUnsafeMutableBufferPointer { ptr in
                if let base = ptr.baseAddress {
                    memset(base, 255, width * height)
                }
            }
        }
        texture.replace(
            region: MTLRegionMake2D(0, 0, width, height),
            mipmapLevel: 0,
            withBytes: coverageData,
            bytesPerRow: width
        )
    }
    
    /// Carves a single circular aperture into the coverage texture at the given geodetic coordinate.
    public func carveAperture(center: CLLocationCoordinate2D, radiusMeters: Double = 35.0) {
        guard let texture = coverageTexture else { return }
        let width = texture.width
        let height = texture.height
        let mercator = MapProjectionMath.geodeticToMercator(center)
        
        let cosLat = max(cos(center.latitude * .pi / 180.0), 0.01)
        let mercatorRadius = radiusMeters / (40_075_016.6856 * cosLat)
        
        let cx = mercator.x * Double(width)
        let cy = mercator.y * Double(height)
        let rx = max(mercatorRadius * Double(width), 2.0)
        let ry = rx
        
        let minX = max(0, Int(floor(cx - rx)))
        let maxX = min(width - 1, Int(ceil(cx + rx)))
        let minY = max(0, Int(floor(cy - ry)))
        let maxY = min(height - 1, Int(ceil(cy + ry)))
        
        guard maxX >= minX && maxY >= minY else { return }
        
        var modified = false
        for y in minY...maxY {
            let dy = Double(y) - cy
            let dy2 = dy * dy
            let rowOffset = y * width
            for x in minX...maxX {
                let dx = Double(x) - cx
                let dist = sqrt(dx * dx + dy2)
                if dist < rx {
                    let val: UInt8
                    if dist <= 0.5 {
                        val = 0
                    } else {
                        let factor = (dist - 0.5) / max(rx - 0.5, 0.001)
                        val = UInt8(Swift.min(Swift.max(factor * 255.0, 0.0), 255.0))
                    }
                    let idx = rowOffset + x
                    if val < coverageData[idx] {
                        coverageData[idx] = val
                        modified = true
                    }
                }
            }
        }
        
        if modified {
            let regionWidth = maxX - minX + 1
            let regionHeight = maxY - minY + 1
            var subData = [UInt8](repeating: 0, count: regionWidth * regionHeight)
            for y in 0..<regionHeight {
                let srcStart = (minY + y) * width + minX
                let dstStart = y * regionWidth
                for x in 0..<regionWidth {
                    subData[dstStart + x] = coverageData[srcStart + x]
                }
            }
            texture.replace(
                region: MTLRegionMake2D(minX, minY, regionWidth, regionHeight),
                mipmapLevel: 0,
                withBytes: subData,
                bytesPerRow: regionWidth
            )
        }
    }
    
    /// Batch-carves multiple aperture centers into the coverage texture with a single subregion texture update.
    public func updateCoverage(from coordinates: [CLLocationCoordinate2D], radiusMeters: Double = 35.0) {
        guard let texture = coverageTexture, !coordinates.isEmpty else { return }
        let width = texture.width
        let height = texture.height
        
        var globalMinX = width
        var globalMaxX = -1
        var globalMinY = height
        var globalMaxY = -1
        
        for center in coordinates {
            let mercator = MapProjectionMath.geodeticToMercator(center)
            let cosLat = max(cos(center.latitude * .pi / 180.0), 0.01)
            let mercatorRadius = radiusMeters / (40_075_016.6856 * cosLat)
            
            let cx = mercator.x * Double(width)
            let cy = mercator.y * Double(height)
            let rx = max(mercatorRadius * Double(width), 2.0)
            
            let minX = max(0, Int(floor(cx - rx)))
            let maxX = min(width - 1, Int(ceil(cx + rx)))
            let minY = max(0, Int(floor(cy - rx)))
            let maxY = min(height - 1, Int(ceil(cy + rx)))
            
            guard maxX >= minX && maxY >= minY else { continue }
            
            globalMinX = min(globalMinX, minX)
            globalMaxX = max(globalMaxX, maxX)
            globalMinY = min(globalMinY, minY)
            globalMaxY = max(globalMaxY, maxY)
            
            for y in minY...maxY {
                let dy = Double(y) - cy
                let dy2 = dy * dy
                let rowOffset = y * width
                for x in minX...maxX {
                    let dx = Double(x) - cx
                    let dist = sqrt(dx * dx + dy2)
                    if dist < rx {
                        let val: UInt8
                        if dist <= 0.5 {
                            val = 0
                        } else {
                            let factor = (dist - 0.5) / max(rx - 0.5, 0.001)
                            val = UInt8(Swift.min(Swift.max(factor * 255.0, 0.0), 255.0))
                        }
                        let idx = rowOffset + x
                        if val < coverageData[idx] {
                            coverageData[idx] = val
                        }
                    }
                }
            }
        }
        
        if globalMaxX >= globalMinX && globalMaxY >= globalMinY {
            let regionWidth = globalMaxX - globalMinX + 1
            let regionHeight = globalMaxY - globalMinY + 1
            var subData = [UInt8](repeating: 0, count: regionWidth * regionHeight)
            for y in 0..<regionHeight {
                let srcStart = (globalMinY + y) * width + globalMinX
                let dstStart = y * regionWidth
                for x in 0..<regionWidth {
                    subData[dstStart + x] = coverageData[srcStart + x]
                }
            }
            texture.replace(
                region: MTLRegionMake2D(globalMinX, globalMinY, regionWidth, regionHeight),
                mipmapLevel: 0,
                withBytes: subData,
                bytesPerRow: regionWidth
            )
        }
    }
    
    /// Total VRAM allocated by this custom layer in bytes.
    /// Strictly guarantees <= 1.05 MB (1.0 MB coverage texture + 768 bytes uniform buffers),
    /// keeping the combined engine footprint under 5.30 MB (< 10 MB Jetsam budget).
    public var currentVRAMUsageBytes: Int {
        let uniforms = uniformBuffers.reduce(0) { $0 + $1.length }
        let texture = coverageTexture != nil ? (coverageResolution * coverageResolution) : 0
        return uniforms + texture
    }
}

// MARK: - Embedded MSL Fallback Source

private let MetalFogShaderEmbeddedSource = """
#include <metal_stdlib>
using namespace metal;

struct MetalFogUniforms {
    float4x4 invProjMatrix;
    float4   fogColor;
    float4   glowColor;
    float    outerGlowWidth;
    float    innerGlowWidth;
    float    fogOpacity;
    float    threshold;
    float    cameraZoom;
    float    padding0;
    float    padding1;
    float    padding2;
};

struct RasterizerData {
    float4 position [[position]];
    float2 ndcCoord;
};

vertex RasterizerData vertexFogQuad(uint vertexID [[vertex_id]]) {
    RasterizerData out;
    const float2 positions[4] = {
        float2(-1.0f, -1.0f),
        float2( 1.0f, -1.0f),
        float2(-1.0f,  1.0f),
        float2( 1.0f,  1.0f)
    };
    float2 pos = positions[vertexID];
    out.position = float4(pos, 0.0f, 1.0f);
    out.ndcCoord = pos;
    return out;
}

fragment half4 fragmentFogAperture(
    RasterizerData             in            [[stage_in]],
    texture2d<float>           coverageTex   [[texture(0)]],
    sampler                    linearSampler [[sampler(0)]],
    constant MetalFogUniforms& uniforms      [[buffer(0)]]
) {
    float4 clipPos = float4(in.ndcCoord, 0.0f, 1.0f);
    float4 worldSpacePos = uniforms.invProjMatrix * clipPos;
    float invW = (abs(worldSpacePos.w) > 1e-6f) ? (1.0f / worldSpacePos.w) : 0.0f;
    float2 mercatorUV = worldSpacePos.xy * invW;
    half inBounds = (mercatorUV.x >= 0.0f && mercatorUV.x <= 1.0f && 
                     mercatorUV.y >= 0.0f && mercatorUV.y <= 1.0f) ? half(1.0) : half(0.0);
    float rawCoverage = coverageTex.sample(linearSampler, mercatorUV).r;
    half coverage = half(rawCoverage);
    half2 grad = half2(dfdx(coverage), dfdy(coverage));
    half gradMag = length(grad);
    half aaWidth = max(half(0.7071) * gradMag, half(0.0001));
    half T = half(uniforms.threshold);
    half fogAlphaMask = smoothstep(T - aaWidth, T + aaWidth, coverage);
    half effectiveFogAlpha = fogAlphaMask * half(uniforms.fogOpacity);
    half glowOuter = smoothstep(T - half(uniforms.outerGlowWidth), T, coverage);
    half glowInner = smoothstep(T + half(uniforms.innerGlowWidth), T, coverage);
    half glowFactor = glowOuter * glowInner;
    half glowIntensity = glowFactor * half(uniforms.glowColor.a);
    half3 slateRGB = half3(uniforms.fogColor.rgb);
    half3 amberRGB = half3(uniforms.glowColor.rgb);
    half totalAlpha = clamp(effectiveFogAlpha + glowIntensity, half(0.0), half(1.0)) * inBounds;
    half denom = max(totalAlpha, half(0.0001));
    half3 blendedRGB = mix(slateRGB, amberRGB, glowIntensity / denom);
    return half4(blendedRGB * totalAlpha, totalAlpha);
}
"""

