import Foundation
import SwiftUI

// MARK: - Risk & Disutility Tier

/// Statistical variance disutility tier indicating transit reliability and schedule confidence.
public enum ConfidenceRiskTier: String, Sendable, Equatable, Hashable, CaseIterable {
    case low       // Low variance (< 2.5m uncertainty) - Emerald / Green
    case moderate  // Moderate variance (2.5m - 6.0m uncertainty) - Electric Amber
    case high      // High variance (> 6.0m uncertainty) - Coral / Red
    
    public var title: String {
        switch self {
        case .low:
            return "RELIABLE"
        case .moderate:
            return "MODERATE RISK"
        case .high:
            return "HIGH UNCERTAINTY"
        }
    }
    
    public var accentColor: Color {
        switch self {
        case .low:
            return Color(hex: "#10B981") // Emerald Green
        case .moderate:
            return Color(hex: "#FFB300") // Electric Amber
        case .high:
            return Color(hex: "#EF4444") // Coral Red
        }
    }
    
    public var tintColorHex: String {
        switch self {
        case .low:
            return "#10B981"
        case .moderate:
            return "#FFB300"
        case .high:
            return "#EF4444"
        }
    }
    
    public static func tier(forVariance variance: Float) -> ConfidenceRiskTier {
        if variance < 2.5 {
            return .low
        } else if variance <= 6.0 {
            return .moderate
        } else {
            return .high
        }
    }
}

// MARK: - Discrete Confidence Point

/// A single discrete time observation point with $P_{10}, P_{50}, P_{90}$ statistical quantiles.
public struct ConfidenceDataPoint: Identifiable, Sendable, Equatable, Hashable {
    public let id: Int
    public let minuteOfDay: Int
    public let p10: Float
    public let p50: Float
    public let p90: Float
    public let label: String?
    
    public init(
        id: Int? = nil,
        minuteOfDay: Int,
        p10: Float,
        p50: Float,
        p90: Float,
        label: String? = nil
    ) {
        self.id = id ?? minuteOfDay
        self.minuteOfDay = (minuteOfDay % 1440 + 1440) % 1440
        self.p10 = max(0.0, p10)
        self.p50 = max(self.p10, p50)
        self.p90 = max(self.p50, p90)
        self.label = label
    }
    
    public var variance: Float {
        max(0.0, p90 - p10)
    }
    
    public var riskTier: ConfidenceRiskTier {
        ConfidenceRiskTier.tier(forVariance: variance)
    }
    
    public var formattedClockTime: String {
        let h24 = minuteOfDay / 60
        let m = minuteOfDay % 60
        let period = h24 >= 12 ? "PM" : "AM"
        let h12 = h24 == 0 ? 12 : (h24 > 12 ? h24 - 12 : h24)
        return String(format: "%d:%02d %@", h12, m, period)
    }
}

// MARK: - Confidence Band Slice (Contiguous Memory Buffer)

/// Cache-coherent contiguous Float32 buffer holding $P_{10}, P_{50}, P_{90}$ statistical channels
/// across a designated time window ($N$ slots).
///
/// Designed for zero-heap 120Hz immediate-mode drawing in `ConfidenceBandCanvas`.
public struct ConfidenceBandSlice: Equatable, Sendable {
    public static let channels = 3
    public static let p10Channel = 0
    public static let p50Channel = 1
    public static let p90Channel = 2
    
    public let slotCount: Int
    public let startMinute: Int
    public let stepMinutes: Int
    
    /// Flat contiguous array of `slotCount * 3` Float32 values.
    public var values: [Float]
    
    public init(
        slotCount: Int,
        startMinute: Int = 0,
        stepMinutes: Int = 1,
        values: [Float]
    ) {
        self.slotCount = max(1, slotCount)
        self.startMinute = (startMinute % 1440 + 1440) % 1440
        self.stepMinutes = max(1, stepMinutes)
        
        let requiredCount = self.slotCount * Self.channels
        if values.count == requiredCount {
            self.values = values
        } else if values.count < requiredCount {
            var padded = values
            padded.append(contentsOf: Array(repeating: 0.0, count: requiredCount - values.count))
            self.values = padded
        } else {
            self.values = Array(values.prefix(requiredCount))
        }
    }
    
    // MARK: - Index Offset & Subscripts
    
    @inlinable
    public func offset(slot: Int, channel: Int) -> Int {
        let clampedSlot = min(max(0, slot), slotCount - 1)
        let clampedChannel = min(max(0, channel), 2)
        return clampedSlot * Self.channels + clampedChannel
    }
    
    @inlinable
    public subscript(slot: Int, channel: Int) -> Float {
        get {
            let idx = offset(slot: slot, channel: channel)
            return values[idx]
        }
        set {
            let idx = offset(slot: slot, channel: channel)
            values[idx] = newValue
        }
    }
    
    @inlinable
    public func quantiles(slot: Int) -> (p10: Float, p50: Float, p90: Float) {
        let p10 = self[slot, Self.p10Channel]
        let p50 = self[slot, Self.p50Channel]
        let p90 = self[slot, Self.p90Channel]
        return (p10, p50, p90)
    }
    
    @inlinable
    public func minuteForSlot(_ slot: Int) -> Int {
        let clampedSlot = min(max(0, slot), slotCount - 1)
        return (startMinute + clampedSlot * stepMinutes) % 1440
    }
    
    @inlinable
    public func varianceDisutility(slot: Int) -> Float {
        let q = quantiles(slot: slot)
        return max(0.0, q.p90 - q.p10)
    }
    
    @inlinable
    public func riskTier(slot: Int) -> ConfidenceRiskTier {
        ConfidenceRiskTier.tier(forVariance: varianceDisutility(slot: slot))
    }
    
    // MARK: - Statistical Summaries
    
    public var meanP50: Float {
        guard slotCount > 0 else { return 0.0 }
        var sum: Float = 0.0
        for i in 0..<slotCount {
            sum += self[i, Self.p50Channel]
        }
        return sum / Float(slotCount)
    }
    
    public var meanUncertainty: Float {
        guard slotCount > 0 else { return 0.0 }
        var sum: Float = 0.0
        for i in 0..<slotCount {
            sum += varianceDisutility(slot: i)
        }
        return sum / Float(slotCount)
    }
    
    public var peakUncertainty: Float {
        guard slotCount > 0 else { return 0.0 }
        var peak: Float = 0.0
        for i in 0..<slotCount {
            peak = max(peak, varianceDisutility(slot: i))
        }
        return peak
    }
    
    public var maxBound: Float {
        guard slotCount > 0 else { return 10.0 }
        var maxVal: Float = 0.0
        for i in 0..<slotCount {
            maxVal = max(maxVal, self[i, Self.p90Channel])
        }
        return max(2.0, maxVal)
    }
    
    public var overallRiskTier: ConfidenceRiskTier {
        ConfidenceRiskTier.tier(forVariance: meanUncertainty)
    }
    
    // MARK: - Factory Constructors
    
    /// An empty slice of designated slot length.
    public static func empty(slotCount: Int = 60, startMinute: Int = 0, stepMinutes: Int = 1) -> ConfidenceBandSlice {
        ConfidenceBandSlice(
            slotCount: slotCount,
            startMinute: startMinute,
            stepMinutes: stepMinutes,
            values: [Float](repeating: 0.0, count: slotCount * channels)
        )
    }
    
    /// Constructs a slice from discrete `ConfidenceDataPoint` records.
    public static func fromPoints(_ points: [ConfidenceDataPoint], stepMinutes: Int = 1) -> ConfidenceBandSlice {
        guard !points.isEmpty else {
            return .empty()
        }
        let sorted = points.sorted { $0.minuteOfDay < $1.minuteOfDay }
        let startMin = sorted.first?.minuteOfDay ?? 0
        var raw = [Float](repeating: 0.0, count: sorted.count * channels)
        
        for (idx, pt) in sorted.enumerated() {
            let base = idx * channels
            raw[base + p10Channel] = pt.p10
            raw[base + p50Channel] = pt.p50
            raw[base + p90Channel] = pt.p90
        }
        
        return ConfidenceBandSlice(
            slotCount: sorted.count,
            startMinute: startMin,
            stepMinutes: stepMinutes,
            values: raw
        )
    }
    
    // MARK: - Synthetic Fixtures
    
    /// Highly reliable rapid transit fixture (e.g. NYC subway L line) with tight confidence bands (<2m).
    public static func reliableSubwayFixture(slotCount: Int = 60, startMinute: Int = 480) -> ConfidenceBandSlice {
        var raw = [Float](repeating: 0.0, count: slotCount * channels)
        for i in 0..<slotCount {
            let minOfDay = startMinute + i
            let wave = sin(Float(minOfDay) * .pi / 30.0) * 0.4
            let p50 = 3.5 + wave
            let p10 = max(0.8, p50 - 0.8)
            let p90 = p50 + 1.2
            
            let base = i * channels
            raw[base + p10Channel] = p10
            raw[base + p50Channel] = p50
            raw[base + p90Channel] = p90
        }
        return ConfidenceBandSlice(slotCount: slotCount, startMinute: startMinute, stepMinutes: 1, values: raw)
    }
    
    /// Volatile bus corridor fixture with wide delay spread and high variance disutility (>6m).
    public static func volatileBusFixture(slotCount: Int = 60, startMinute: Int = 480) -> ConfidenceBandSlice {
        var raw = [Float](repeating: 0.0, count: slotCount * channels)
        for i in 0..<slotCount {
            let minOfDay = startMinute + i
            let wave = sin(Float(minOfDay) * .pi / 20.0) * 2.0
            let p50 = 8.5 + wave
            let p10 = max(1.5, p50 - 3.5)
            let p90 = p50 + 7.0 + (Float(i) * 0.05)
            
            let base = i * channels
            raw[base + p10Channel] = p10
            raw[base + p50Channel] = p50
            raw[base + p90Channel] = p90
        }
        return ConfidenceBandSlice(slotCount: slotCount, startMinute: startMinute, stepMinutes: 1, values: raw)
    }
    
    /// Moderate rush-hour fixture with gradual evening peak crowding (2.5m - 5m variance).
    public static func moderateRushHourFixture(slotCount: Int = 120, startMinute: Int = 420) -> ConfidenceBandSlice {
        var raw = [Float](repeating: 0.0, count: slotCount * channels)
        for i in 0..<slotCount {
            let progress = Float(i) / Float(slotCount)
            let peakFactor = sin(progress * .pi) * 3.0
            let p50 = 4.0 + peakFactor
            let p10 = max(1.0, p50 - 1.2 - (peakFactor * 0.3))
            let p90 = p50 + 2.2 + (peakFactor * 0.8)
            
            let base = i * channels
            raw[base + p10Channel] = p10
            raw[base + p50Channel] = p50
            raw[base + p90Channel] = p90
        }
        return ConfidenceBandSlice(slotCount: slotCount, startMinute: startMinute, stepMinutes: 1, values: raw)
    }
}
