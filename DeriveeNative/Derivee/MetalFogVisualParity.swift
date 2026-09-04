import Foundation
import Metal
import CoreGraphics
import CoreLocation
import simd
import MapLibre

// MARK: - Embedded MSL Source for Resilient Test/Headless Compilation

public let MetalFogParityKernelsEmbeddedSource = """
#include <metal_stdlib>
using namespace metal;

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
        diffTex.write(float4(abs(diff.rgb), abs(diff.a)), gid);
    }
    
    uint linearThread = tid.y * tgSize.x + tid.x;
    sharedMem[linearThread] = sqDiff;
    threadgroup_barrier(mem_flags::mem_threadgroup);
    
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
"""

// MARK: - Visual Parity Engine (Doc 08 §7)

/// GPU-accelerated visual parity comparator calculating Root Mean Square Deviation (RMSD)
/// between reference polygon representations and candidate MetalFog fragment renders.
public final class MetalFogVisualParity: @unchecked Sendable {
    
    public let device: MTLDevice
    public let commandQueue: MTLCommandQueue
    private let rmsdComputePipelineState: MTLComputePipelineState
    
    public init(device: MTLDevice? = nil) throws {
        guard let mtlDevice = device ?? MTLCreateSystemDefaultDevice() else {
            throw NSError(
                domain: "MetalFogVisualParityError",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "No MTLDevice available"]
            )
        }
        self.device = mtlDevice
        
        guard let queue = mtlDevice.makeCommandQueue() else {
            throw NSError(
                domain: "MetalFogVisualParityError",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "Failed to create MTLCommandQueue"]
            )
        }
        self.commandQueue = queue
        
        // Resolve compute pipeline via dual-source loader
        let library: MTLLibrary
        if let bundleLib = try? mtlDevice.makeDefaultLibrary(bundle: Bundle.main) {
            library = bundleLib
        } else if let testLib = try? mtlDevice.makeDefaultLibrary(bundle: Bundle(for: MetalFogVisualParity.self)) {
            library = testLib
        } else if let defaultLib = try? mtlDevice.makeDefaultLibrary() {
            library = defaultLib
        } else {
            library = try mtlDevice.makeLibrary(source: MetalFogParityKernelsEmbeddedSource, options: nil)
        }
        
        guard let function = library.makeFunction(name: "rmsd_texture_comparison") else {
            throw NSError(
                domain: "MetalFogVisualParityError",
                code: -3,
                userInfo: [NSLocalizedDescriptionKey: "Compute function 'rmsd_texture_comparison' not found"]
            )
        }
        
        self.rmsdComputePipelineState = try mtlDevice.makeComputePipelineState(function: function)
    }
    
    /// Computes the Root Mean Square Deviation (RMSD) across all four color channels (R, G, B, A)
    /// between two textures of identical dimensions.
    ///
    /// $$RMSD = \\sqrt{\\frac{1}{W \\cdot H} \\sum_{x=0}^{W-1} \\sum_{y=0}^{H-1} ((R_A - R_B)^2 + (G_A - G_B)^2 + (B_A - B_B)^2 + (A_A - A_B)^2)}$$
    public func computeRMSD(
        textureA: MTLTexture,
        textureB: MTLTexture
    ) throws -> (rmsd: Double, diffTexture: MTLTexture) {
        guard textureA.width == textureB.width && textureA.height == textureB.height else {
            throw NSError(
                domain: "MetalFogVisualParityError",
                code: -4,
                userInfo: [NSLocalizedDescriptionKey: "Texture dimensions must match for RMSD parity comparison"]
            )
        }
        
        let width = textureA.width
        let height = textureA.height
        
        // Allocate diff texture for diagnostic inspection
        let diffDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        diffDesc.usage = [.shaderRead, .shaderWrite]
        guard let diffTexture = device.makeTexture(descriptor: diffDesc) else {
            throw NSError(
                domain: "MetalFogVisualParityError",
                code: -5,
                userInfo: [NSLocalizedDescriptionKey: "Failed to allocate difference texture"]
            )
        }
        
        let threadgroupSize = MTLSize(width: 16, height: 16, depth: 1)
        let threadgroupsPerGrid = MTLSize(
            width: (width + threadgroupSize.width - 1) / threadgroupSize.width,
            height: (height + threadgroupSize.height - 1) / threadgroupSize.height,
            depth: 1
        )
        
        let numThreadgroups = threadgroupsPerGrid.width * threadgroupsPerGrid.height
        let partialSumsBufferSize = max(numThreadgroups * MemoryLayout<Float>.stride, 16)
        guard let partialSumsBuffer = device.makeBuffer(length: partialSumsBufferSize, options: .storageModeShared) else {
            throw NSError(
                domain: "MetalFogVisualParityError",
                code: -6,
                userInfo: [NSLocalizedDescriptionKey: "Failed to allocate partialSumsBuffer"]
            )
        }
        memset(partialSumsBuffer.contents(), 0, partialSumsBufferSize)
        
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder() else {
            throw NSError(
                domain: "MetalFogVisualParityError",
                code: -7,
                userInfo: [NSLocalizedDescriptionKey: "Failed to create Metal compute command encoder"]
            )
        }
        
        encoder.setComputePipelineState(rmsdComputePipelineState)
        encoder.setTexture(textureA, index: 0)
        encoder.setTexture(textureB, index: 1)
        encoder.setTexture(diffTexture, index: 2)
        encoder.setBuffer(partialSumsBuffer, offset: 0, index: 0)
        
        // 256 threads * 4 bytes/float = 1,024 bytes shared memory
        let sharedMemorySize = threadgroupSize.width * threadgroupSize.height * MemoryLayout<Float>.stride
        encoder.setThreadgroupMemoryLength(sharedMemorySize, index: 0)
        
        encoder.dispatchThreadgroups(threadgroupsPerGrid, threadsPerThreadgroup: threadgroupSize)
        encoder.endEncoding()
        
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        
        // Read back partial sums
        let pointer = partialSumsBuffer.contents().bindMemory(to: Float.self, capacity: numThreadgroups)
        var totalSquaredError: Double = 0.0
        for i in 0..<numThreadgroups {
            totalSquaredError += Double(pointer[i])
        }
        
        let totalPixels = Double(width * height)
        let meanSquaredDeviation = totalSquaredError / totalPixels
        let rmsd = sqrt(meanSquaredDeviation)
        
        return (rmsd: rmsd, diffTexture: diffTexture)
    }
}
