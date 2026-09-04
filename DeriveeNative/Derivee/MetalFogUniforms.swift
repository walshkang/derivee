import Foundation
import simd

/// Uniform buffer structure matching Metal Shading Language layout (128 bytes, 16-byte aligned).
/// Strictly implements the research specifications in `docs/research/07_metal_layer_injection_compositing_maplibre.md`
/// and `docs/research/09_metal_shading_pipeline_sdf_edge_glow.md`.
public struct MetalFogUniforms {
    /// Clip-space NDC [-1, 1] to Normalized Mercator [0, 1] transformation matrix (64 bytes).
    public var invProjMatrix: simd_float4x4
    
    /// Slate fog base color (16 bytes, #1C1C1E -> r:0.1098, g:0.1098, b:0.1176, a:1.0).
    public var fogColor: simd_float4
    
    /// Electric Amber analytical border glow color (16 bytes, #FFB300 -> r:1.0, g:0.7020, b:0.0, a:1.0).
    public var glowColor: simd_float4
    
    /// Outer glow spread factor bleeding into unexplored slate fog (4 bytes, e.g. 0.06).
    public var outerGlowWidth: Float
    
    /// Inner glow spread factor bleeding into transparent aperture (4 bytes, e.g. 0.04).
    public var innerGlowWidth: Float
    
    /// Master fog opacity multiplier [0.0, 1.0] (4 bytes, default 0.85).
    public var fogOpacity: Float
    
    /// Aperture coverage threshold (4 bytes, default 0.5).
    public var threshold: Float
    
    /// Camera zoom level for H3 multi-resolution LOD aggregation (4 bytes).
    public var cameraZoom: Float
    
    /// Explicit padding to ensure strict 16-byte MSL alignment and 128-byte stride (12 bytes).
    public var padding0: Float = 0.0
    public var padding1: Float = 0.0
    public var padding2: Float = 0.0
    
    public init(
        invProjMatrix: simd_float4x4 = matrix_identity_float4x4,
        fogColor: simd_float4 = simd_float4(0.1098, 0.1098, 0.1176, 1.0),
        glowColor: simd_float4 = simd_float4(1.0, 0.7020, 0.0, 1.0),
        outerGlowWidth: Float = 0.06,
        innerGlowWidth: Float = 0.04,
        fogOpacity: Float = 0.85,
        threshold: Float = 0.5,
        cameraZoom: Float = 14.0
    ) {
        self.invProjMatrix = invProjMatrix
        self.fogColor = fogColor
        self.glowColor = glowColor
        self.outerGlowWidth = outerGlowWidth
        self.innerGlowWidth = innerGlowWidth
        self.fogOpacity = fogOpacity
        self.threshold = threshold
        self.cameraZoom = cameraZoom
        self.padding0 = 0.0
        self.padding1 = 0.0
        self.padding2 = 0.0
    }
}

/// Runtime verifier confirming ABI alignment and stride matching Metal Shading Language.
public enum MetalFogUniformsVerifier {
    public static func verify() {
        assert(MemoryLayout<MetalFogUniforms>.size == 128, "MetalFogUniforms size must be exactly 128 bytes")
        assert(MemoryLayout<MetalFogUniforms>.stride == 128, "MetalFogUniforms stride must be exactly 128 bytes")
        assert(MemoryLayout<MetalFogUniforms>.alignment == 16, "MetalFogUniforms alignment must be 16 bytes")
    }
}
