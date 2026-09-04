#include <metal_stdlib>
using namespace metal;

// Structure matching Swift MetalFogUniforms layout (128 bytes, 16-byte aligned)
struct MetalFogUniforms {
    float4x4 invProjMatrix;     // Clip-space NDC to Normalized Mercator (0-1) matrix (64 bytes)
    float4   fogColor;          // Slate fog base color (#1C1C1E -> r:0.1098, g:0.1098, b:0.1176, a:1.0)
    float4   glowColor;         // Electric Amber glow color (#FFB300 -> r:1.0, g:0.7020, b:0.0, a:1.0)
    float    outerGlowWidth;    // Glow spread factor outside threshold (e.g., 0.06)
    float    innerGlowWidth;    // Glow spread factor inside threshold (e.g., 0.04)
    float    fogOpacity;        // Master fog alpha multiplier [0.0 - 1.0]
    float    threshold;         // Coverage aperture boundary threshold (default 0.5)
    float    cameraZoom;        // Camera zoom level
    float    padding0;
    float    padding1;
    float    padding2;
};

// Rasterizer data passed from vertex shader to fragment shader
struct RasterizerData {
    float4 position [[position]]; // Clip-space output position
    float2 ndcCoord;              // Normalized Device Coordinates [-1, 1]
};

// Vertex Shader: Generates a full-screen quad via triangle strip (4 vertices, O(1) constant overhead)
// Strictly follows docs/research/09_metal_shading_pipeline_sdf_edge_glow.md §5
vertex RasterizerData vertexFogQuad(uint vertexID [[vertex_id]]) {
    RasterizerData out;
    
    const float2 positions[4] = {
        float2(-1.0f, -1.0f), // Bottom-Left
        float2( 1.0f, -1.0f), // Bottom-Right
        float2(-1.0f,  1.0f), // Top-Left
        float2( 1.0f,  1.0f)  // Top-Right
    };
    
    float2 pos = positions[vertexID];
    out.position = float4(pos, 0.0f, 1.0f);
    out.ndcCoord = pos;
    
    return out;
}

// Fragment Shader: Evaluates coverage, analytical AA SDF, and synthetic amber glow
// Strictly follows docs/research/07_metal_layer_injection_compositing_maplibre.md,
// docs/research/09_metal_shading_pipeline_sdf_edge_glow.md, and Apple Silicon TBDR invariants:
// - Zero discard_fragment() to preserve TBDR Hidden Surface Removal (HSR) and tile write-back.
// - Strict 16-bit half precision ALU throughput on A12+ dual-issue floating point units.
// - Unconditional dfdx/dfdy evaluation to prevent quad helper divergence and compiler homogenization.
fragment half4 fragmentFogAperture(
    RasterizerData             in            [[stage_in]],
    texture2d<float>           coverageTex   [[texture(0)]],
    sampler                    linearSampler [[sampler(0)]],
    constant MetalFogUniforms& uniforms      [[buffer(0)]]
) {
    // 1. High-precision coordinate unprojection in float32 to prevent jitter at z >= 18
    float4 clipPos = float4(in.ndcCoord, 0.0f, 1.0f);
    float4 worldSpacePos = uniforms.invProjMatrix * clipPos;
    
    float invW = (abs(worldSpacePos.w) > 1e-6f) ? (1.0f / worldSpacePos.w) : 0.0f;
    float2 mercatorUV = worldSpacePos.xy * invW;
    
    // Mathematical world bounds validity mask (0.0 outside [0, 1]^2, 1.0 inside)
    // Avoids branch divergence and preserves 2x2 SIMD quad lane execution.
    half inBounds = (mercatorUV.x >= 0.0f && mercatorUV.x <= 1.0f && 
                     mercatorUV.y >= 0.0f && mercatorUV.y <= 1.0f) ? half(1.0) : half(0.0);
    
    // 2. Hardware bilinear sample from single-channel coverage texture (.r8Unorm)
    float rawCoverage = coverageTex.sample(linearSampler, mercatorUV).r;
    half coverage = half(rawCoverage);
    
    // 3. Unconditional screen-space derivatives for zoom-invariant anti-aliasing (1.0-1.5px)
    half2 grad = half2(dfdx(coverage), dfdy(coverage));
    half gradMag = length(grad);
    half aaWidth = max(half(0.7071) * gradMag, half(0.0001));
    
    // 4. Analytical anti-aliased aperture mask (Smoothstep Hermite filter in half precision)
    half T = half(uniforms.threshold);
    half fogAlphaMask = smoothstep(T - aaWidth, T + aaWidth, coverage);
    half effectiveFogAlpha = fogAlphaMask * half(uniforms.fogOpacity);
    
    // 5. Analytical single-pass Electric Amber border glow calculation (#FFB300)
    half glowOuter = smoothstep(T - half(uniforms.outerGlowWidth), T, coverage);
    half glowInner = smoothstep(T + half(uniforms.innerGlowWidth), T, coverage);
    half glowFactor = glowOuter * glowInner; // Peaks strictly at boundary threshold T
    half glowIntensity = glowFactor * half(uniforms.glowColor.a);
    
    // 6. Color Compositing (Slate Fog + Electric Amber Glow)
    half3 slateRGB = half3(uniforms.fogColor.rgb);
    half3 amberRGB = half3(uniforms.glowColor.rgb);
    
    // Total alpha modulated by inBounds mask
    half totalAlpha = clamp(effectiveFogAlpha + glowIntensity, half(0.0), half(1.0)) * inBounds;
    half denom = max(totalAlpha, half(0.0001));
    half3 blendedRGB = mix(slateRGB, amberRGB, glowIntensity / denom);
    
    // 7. Output Premultiplied Alpha for Hardware Blending Unit (.one, .oneMinusSourceAlpha)
    // Zero discard_fragment() preserves Apple TBDR tile write-back efficiency.
    return half4(blendedRGB * totalAlpha, totalAlpha);
}

