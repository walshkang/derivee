import Foundation
import Accelerate

/// Vectorized circular kernel density estimation using Accelerate vDSP for the 1,440-minute circular timeline.
/// Maps the periodic 24-hour time domain onto angular space [0, 2π) to eliminate midnight edge bias.
public enum CircularDensitySmoother {
    
    /// Convolves a 1,440-element sparse departure impulse signal with a discretized von Mises kernel.
    ///
    /// - Parameters:
    ///   - sparseSignal: Exactly 1,440 single-precision Float elements corresponding to minute slots in a 24-hour cycle.
    ///   - kernelRadius: Filter radius `k` in minute slots (total kernel length = `2 * k + 1`). Default is 15 minutes.
    ///   - kappa: Concentration parameter $\kappa > 0$ controlling smoothing bandwidth ($\kappa \approx (1440 / (2\pi \sigma_m))^2$). Default is 350.0.
    /// - Returns: A smoothed 1,440-element density array with continuous wrapping at midnight ($23:59 \rightarrow 00:00$).
    public static func convolveCircular(
        sparseSignal: [Float],
        kernelRadius k: Int = 15,
        kappa: Float = 350.0
    ) -> [Float] {
        let N = 1440
        guard sparseSignal.count == N else {
            // If input size differs, fallback or resize
            return sparseSignal
        }
        
        let P = 2 * k + 1
        
        // 1. Construct discretized symmetric von Mises kernel using stable relative exponent exp(kappa * (cos(theta) - 1))
        var kernel = [Float](repeating: 0.0, count: P)
        var kernelSum: Float = 0.0
        for j in 0..<P {
            let minuteOffset = Float(j - k)
            let angleOffset = (2.0 * .pi * minuteOffset) / Float(N)
            let val = exp(kappa * (cos(angleOffset) - 1.0))
            kernel[j] = val
            kernelSum += val
        }
        
        // Normalize kernel so total discrete weight sums to 1.0
        if kernelSum > 1e-6 {
            let invSum = 1.0 / kernelSum
            for j in 0..<P {
                kernel[j] *= invSum
            }
        }
        
        // 3. Construct Padded Circular Buffer (Length = N + 2k)
        var paddedSignal = [Float](repeating: 0.0, count: N + 2 * k)
        
        // Copy tail segment to head padding
        paddedSignal[0..<k] = sparseSignal[(N - k)..<N]
        // Copy main signal body
        paddedSignal[k..<(N + k)] = sparseSignal[0..<N]
        // Copy head segment to tail padding
        paddedSignal[(N + k)..<(N + 2 * k)] = sparseSignal[0..<k]
        
        var output = [Float](repeating: 0.0, count: N)
        
        // 4. Execute Vectorized Circular Convolution using Accelerate vDSP
        kernel.withUnsafeBufferPointer { kernelPtr in
            paddedSignal.withUnsafeBufferPointer { signalPtr in
                guard let kernelBase = kernelPtr.baseAddress,
                      let signalBase = signalPtr.baseAddress else { return }
                
                let filterEndPointer = kernelBase.advanced(by: P - 1)
                
                vDSP_conv(
                    signalBase, 1,            // Input signal pointer & stride
                    filterEndPointer, -1,     // Kernel end pointer & negative stride for convolution
                    &output, 1,               // Output destination & stride
                    vDSP_Length(N),           // Result length
                    vDSP_Length(P)            // Kernel length
                )
            }
        }
        
        return output
    }
}
