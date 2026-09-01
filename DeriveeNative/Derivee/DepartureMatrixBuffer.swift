import Foundation

/// High-performance contiguous memory buffer representing a 24-hour by 60-minute departure matrix
/// with 3 statistical channels ($P_{10}$, $P_{50}$, $P_{90}$) packed into exactly 4,320 Float32 elements (~17.28 KB).
///
/// Designed to fit entirely within the 64 KB L1 data cache of Apple Silicon for zero-copy 120Hz immediate-mode drawing.
public struct DepartureMatrixBuffer: Equatable, Sendable {
    public static let hours = 24
    public static let minutesPerHour = 60
    public static let totalMinutes = 1440
    public static let channels = 3
    public static let totalElements = 4320
    
    public static let p10Channel = 0
    public static let p50Channel = 1
    public static let p90Channel = 2
    
    /// Flat contiguous array of 4,320 Float32 values.
    public var values: [Float]
    
    public init(values: [Float]) {
        if values.count == Self.totalElements {
            self.values = values
        } else if values.count < Self.totalElements {
            var padded = values
            padded.append(contentsOf: Array(repeating: 0.0, count: Self.totalElements - values.count))
            self.values = padded
        } else {
            self.values = Array(values.prefix(Self.totalElements))
        }
    }
    
    /// Stride offset calculation: Offset(h, m, p) = (h * 60 + m) * 3 + p
    @inlinable
    public static func offset(hour: Int, minute: Int, channel: Int) -> Int {
        let clampedH = (hour % 24 + 24) % 24
        let clampedM = (minute % 60 + 60) % 60
        let clampedC = min(max(0, channel), 2)
        return (clampedH * 60 + clampedM) * 3 + clampedC
    }
    
    @inlinable
    public static func offset(minuteOfDay: Int, channel: Int) -> Int {
        let clampedM = (minuteOfDay % 1440 + 1440) % 1440
        let clampedC = min(max(0, channel), 2)
        return clampedM * 3 + clampedC
    }
    
    @inlinable
    public subscript(hour: Int, minute: Int, channel: Int) -> Float {
        get {
            let idx = Self.offset(hour: hour, minute: minute, channel: channel)
            return values[idx]
        }
        set {
            let idx = Self.offset(hour: hour, minute: minute, channel: channel)
            values[idx] = newValue
        }
    }
    
    @inlinable
    public subscript(minuteOfDay: Int, channel: Int) -> Float {
        get {
            let idx = Self.offset(minuteOfDay: minuteOfDay, channel: channel)
            return values[idx]
        }
        set {
            let idx = Self.offset(minuteOfDay: minuteOfDay, channel: channel)
            values[idx] = newValue
        }
    }
    
    @inlinable
    public func quantiles(hour: Int, minute: Int) -> (p10: Float, p50: Float, p90: Float) {
        let p10 = self[hour, minute, Self.p10Channel]
        let p50 = self[hour, minute, Self.p50Channel]
        let p90 = self[hour, minute, Self.p90Channel]
        return (p10, p50, p90)
    }
    
    @inlinable
    public func quantiles(minuteOfDay: Int) -> (p10: Float, p50: Float, p90: Float) {
        let p10 = self[minuteOfDay, Self.p10Channel]
        let p50 = self[minuteOfDay, Self.p50Channel]
        let p90 = self[minuteOfDay, Self.p90Channel]
        return (p10, p50, p90)
    }
    
    @inlinable
    public func varianceDisutility(hour: Int, minute: Int) -> Float {
        let q = quantiles(hour: hour, minute: minute)
        return max(0.0, q.p90 - q.p10)
    }
    
    @inlinable
    public func varianceDisutility(minuteOfDay: Int) -> Float {
        let q = quantiles(minuteOfDay: minuteOfDay)
        return max(0.0, q.p90 - q.p10)
    }
    
    // MARK: - Factory Constructors
    
    /// An empty buffer filled with 0.0 values.
    public static func empty() -> DepartureMatrixBuffer {
        DepartureMatrixBuffer(values: [Float](repeating: 0.0, count: totalElements))
    }
    
    /// Constructs a DepartureMatrixBuffer from static / real-time scheduled hour records.
    ///
    /// Generates departure impulses at scheduled minutes, applies circular von Mises smoothing to compute
    /// expected wait time density $P_{50}$, and estimates $P_{10}$ and $P_{90}$ confidence intervals.
    public static func fromScheduleRecords(
        _ records: [SpatialDatabaseManager.HourScheduleRecord],
        defaultHeadway: Float = 6.0
    ) -> DepartureMatrixBuffer {
        var rawImpulses = [Float](repeating: 0.0, count: totalMinutes)
        
        for hourRec in records {
            let h = hourRec.hourOfDay
            for dep in hourRec.departures {
                let m = dep.minute
                let minuteOfDay = (h * 60 + m) % totalMinutes
                rawImpulses[minuteOfDay] += 1.0
            }
        }
        
        // Circular kernel density smoothing
        let smoothedDensity = CircularDensitySmoother.convolveCircular(
            sparseSignal: rawImpulses,
            kernelRadius: 15,
            kappa: 250.0
        )
        
        // Find max density for normalization
        let maxDensity = smoothedDensity.max() ?? 1.0
        let densityScale: Float = maxDensity > 0.0001 ? (1.0 / maxDensity) : 1.0
        
        var buffer = [Float](repeating: 0.0, count: totalElements)
        
        // Build 1,440 slots with calculated wait quantiles
        for minOfDay in 0..<totalMinutes {
            let density = smoothedDensity[minOfDay] * densityScale
            let expectedHeadway: Float = density > 0.05 ? max(2.0, defaultHeadway / max(0.1, density)) : 20.0
            
            // P50 = median wait ≈ headway / 2
            let p50 = expectedHeadway * 0.5
            // P10 = optimistic wait ≈ 0.25 * P50
            let p10 = max(0.5, p50 * 0.3)
            // P90 = pessimistic wait with variance
            let p90 = p50 + max(1.5, expectedHeadway * 0.6)
            
            let baseIdx = minOfDay * 3
            buffer[baseIdx + p10Channel] = p10
            buffer[baseIdx + p50Channel] = p50
            buffer[baseIdx + p90Channel] = p90
        }
        
        return DepartureMatrixBuffer(values: buffer)
    }
    
    /// Constructs a DepartureMatrixBuffer from hourly reliability records ($SWT$, $AWT$, $EWT$, $OTP$).
    public static func fromHourlyReliability(
        _ records: [SpatialDatabaseManager.HourlyReliabilityRecord]
    ) -> DepartureMatrixBuffer {
        var hourMap: [Int: SpatialDatabaseManager.HourlyReliabilityRecord] = [:]
        for r in records {
            hourMap[r.hourOfDay] = r
        }
        
        var buffer = [Float](repeating: 0.0, count: totalElements)
        
        for hour in 0..<24 {
            let rec = hourMap[hour]
            let medianWait = Float(rec?.medianHeadwaySec ?? 360) / 120.0 // minutes
            let stdDev = Float(rec?.headwayStdDevSec ?? 60) / 60.0 // minutes
            let p90Delay = Float(rec?.p90DelaySec ?? 180) / 60.0 // minutes
            
            for minute in 0..<60 {
                let minOfDay = hour * 60 + minute
                let baseIdx = minOfDay * 3
                
                let p10 = max(0.5, medianWait * 0.4)
                let p50 = max(1.0, medianWait)
                let p90 = p50 + max(stdDev * 1.645, p90Delay * 0.5)
                
                buffer[baseIdx + p10Channel] = p10
                buffer[baseIdx + p50Channel] = p50
                buffer[baseIdx + p90Channel] = p90
            }
        }
        
        return DepartureMatrixBuffer(values: buffer)
    }
    
    /// Synthetic fixture for testing, snapshots, and previews.
    public static func syntheticFixture(lowVariance: Bool = false) -> DepartureMatrixBuffer {
        var buffer = [Float](repeating: 0.0, count: totalElements)
        
        for hour in 0..<24 {
            let isRushHour = (hour >= 7 && hour <= 9) || (hour >= 17 && hour <= 19)
            let isLateNight = hour >= 1 && hour <= 5
            
            let baseHeadway: Float = isRushHour ? 3.5 : (isLateNight ? 15.0 : 6.5)
            let varianceFactor: Float = lowVariance ? 0.2 : (isLateNight ? 0.8 : 0.45)
            
            for minute in 0..<60 {
                let minOfDay = hour * 60 + minute
                let baseIdx = minOfDay * 3
                
                // Add micro-variation across the hour
                let micro = sin(Float(minute) * .pi / 30.0) * 0.5
                let p50 = max(1.0, (baseHeadway * 0.5) + micro)
                let p10 = max(0.4, p50 * (1.0 - varianceFactor))
                let p90 = p50 * (1.0 + varianceFactor * 2.0)
                
                buffer[baseIdx + p10Channel] = p10
                buffer[baseIdx + p50Channel] = p50
                buffer[baseIdx + p90Channel] = p90
            }
        }
        
        return DepartureMatrixBuffer(values: buffer)
    }
}
