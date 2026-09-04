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
// Strictly follows docs/research/07_metal_layer_injection_compositing_maplibre.md and
// docs/research/09_metal_shading_pipeline_sdf_edge_glow.md
fragment float4 fragmentFogAperture(
    RasterizerData             in       [[stage_in]],
    constant MetalFogUniforms& uniforms [[buffer(0)]]
) {
    // 1. Transform Clip-Space NDC (-1 to 1) to Normalized Mercator space (0 to 1)
    float4 clipPos = float4(in.ndcCoord, 0.0f, 1.0f);
    float4 worldSpacePos = uniforms.invProjMatrix * clipPos;
    
    if (abs(worldSpacePos.w) < 1e-6f) {
        return float4(0.0f);
    }
    
    float2 mercatorUV = worldSpacePos.xy / worldSpacePos.w;
    
    // Discard fragments outside valid world map boundaries
    if (mercatorUV.x < 0.0f || mercatorUV.x > 1.0f || mercatorUV.y < 0.0f || mercatorUV.y > 1.0f) {
        return float4(0.0f);
    }
    
    // Baseline coverage evaluation (1.0 = unexplored solid fog, 0.0 = explored hole)
    // In Wave O.4, this samples the H3 spatial texture / coverage buffer.
    float coverage = 1.0f;
    
    // 2. Compute screen-space partial derivatives for zoom-invariant anti-aliasing
    float2 grad = float2(dfdx(coverage), dfdy(coverage));
    float gradMag = length(grad);
    float aaWidth = max(0.7071f * gradMag, 0.0001f);
    
    // 3. Analytical anti-aliased aperture mask (Smoothstep Hermite filter)
    float T = uniforms.threshold;
    float fogAlphaMask = smoothstep(T - aaWidth, T + aaWidth, coverage);
    float effectiveFogAlpha = fogAlphaMask * uniforms.fogOpacity;
    
    // 4. Analytical single-pass Electric Amber border glow calculation
    float glowOuter = smoothstep(T - uniforms.outerGlowWidth, T, coverage);
    float glowInner = smoothstep(T + uniforms.innerGlowWidth, T, coverage);
    float glowFactor = glowOuter * glowInner; // Peaks at boundary threshold T
    
    // 5. Color Compositing (Slate Fog + Electric Amber Glow)
    float3 slateRGB = uniforms.fogColor.rgb;
    float3 amberRGB = uniforms.glowColor.rgb;
    float glowIntensity = glowFactor * uniforms.glowColor.a;
    
    float totalAlpha = clamp(effectiveFogAlpha + glowIntensity, 0.0f, 1.0f);
    float3 blendedRGB = mix(slateRGB, amberRGB, glowIntensity / max(totalAlpha, 0.0001f));
    
    // 6. Output Premultiplied Alpha for Hardware Blending Unit
    return float4(blendedRGB * totalAlpha, totalAlpha);
}
