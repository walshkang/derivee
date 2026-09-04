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
    
    /// Total VRAM allocated by this custom layer in bytes.
    /// Strictly guarantees <= 1,024 bytes (3 x 256-byte uniform buffers), preserving the < 10 MB budget.
    public var currentVRAMUsageBytes: Int {
        return uniformBuffers.reduce(0) { $0 + $1.length }
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

fragment float4 fragmentFogAperture(
    RasterizerData             in       [[stage_in]],
    constant MetalFogUniforms& uniforms [[buffer(0)]]
) {
    float4 clipPos = float4(in.ndcCoord, 0.0f, 1.0f);
    float4 worldSpacePos = uniforms.invProjMatrix * clipPos;
    if (abs(worldSpacePos.w) < 1e-6f) {
        return float4(0.0f);
    }
    float2 mercatorUV = worldSpacePos.xy / worldSpacePos.w;
    if (mercatorUV.x < 0.0f || mercatorUV.x > 1.0f || mercatorUV.y < 0.0f || mercatorUV.y > 1.0f) {
        return float4(0.0f);
    }
    float coverage = 1.0f;
    float2 grad = float2(dfdx(coverage), dfdy(coverage));
    float gradMag = length(grad);
    float aaWidth = max(0.7071f * gradMag, 0.0001f);
    float T = uniforms.threshold;
    float fogAlphaMask = smoothstep(T - aaWidth, T + aaWidth, coverage);
    float effectiveFogAlpha = fogAlphaMask * uniforms.fogOpacity;
    float glowOuter = smoothstep(T - uniforms.outerGlowWidth, T, coverage);
    float glowInner = smoothstep(T + uniforms.innerGlowWidth, T, coverage);
    float glowFactor = glowOuter * glowInner;
    float3 slateRGB = uniforms.fogColor.rgb;
    float3 amberRGB = uniforms.glowColor.rgb;
    float glowIntensity = glowFactor * uniforms.glowColor.a;
    float totalAlpha = clamp(effectiveFogAlpha + glowIntensity, 0.0f, 1.0f);
    float3 blendedRGB = mix(slateRGB, amberRGB, glowIntensity / max(totalAlpha, 0.0001f));
    return float4(blendedRGB * totalAlpha, totalAlpha);
}
"""
