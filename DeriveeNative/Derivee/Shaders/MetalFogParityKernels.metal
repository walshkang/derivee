#include <metal_stdlib>
using namespace metal;

/// Metal compute kernel computing Root Mean Square Deviation (RMSD) squared differences across two offscreen textures.
/// Conforms to `docs/research/08_empirical_performance_benchmarking_metalfogengine.md §7`.
kernel void rmsd_texture_comparison(
    texture2d<float, access::read>  texA         [[texture(0)]],
    texture2d<float, access::read>  texB         [[texture(1)]],
    texture2d<float, access::write> diffTex      [[texture(2)]],
    device float*                   partialSums  [[buffer(0)]],
    threadgroup float*              sharedMem    [[threadgroup(0)]],
    uint2                           gid          [[thread_position_in_grid]],
    uint2                           tid          [[thread_position_in_threadgroup]],
    uint2                           tgSize       [[threads_per_threadgroup]],
    uint2                           tgIndex      [[threadgroup_position_in_grid]],
    uint2                           numGroups    [[threadgroups_per_grid]]
) {
    uint width = texA.get_width();
    uint height = texA.get_height();
    
    float sqDiff = 0.0f;
    if (gid.x < width && gid.y < height) {
        float4 colorA = texA.read(gid);
        float4 colorB = texB.read(gid);
        float4 diff = colorA - colorB;
        sqDiff = dot(diff, diff);
        
        // Write absolute difference map for diagnostic inspection
        diffTex.write(float4(abs(diff.rgb), abs(diff.a)), gid);
    }
    
    uint linearThread = tid.y * tgSize.x + tid.x;
    sharedMem[linearThread] = sqDiff;
    threadgroup_barrier(mem_flags::mem_threadgroup);
    
    // Threadgroup parallel reduction (16x16 = 256 threads)
    uint totalThreads = tgSize.x * tgSize.y;
    for (uint stride = totalThreads / 2; stride > 0; stride >>= 1) {
        if (linearThread < stride) {
            sharedMem[linearThread] += sharedMem[linearThread + stride];
        }
        threadgroup_barrier(mem_flags::mem_threadgroup);
    }
    
    if (linearThread == 0) {
        uint linearGroupIndex = tgIndex.y * numGroups.x + tgIndex.x;
        partialSums[linearGroupIndex] = sharedMem[0];
    }
}
