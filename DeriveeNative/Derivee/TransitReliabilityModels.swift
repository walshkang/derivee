import Foundation

// MARK: - Disruption Models

/// Represents the classification of a transit service disruption.
public enum DisruptionType: String, Sendable, Codable, CaseIterable {
    case suspended = "SUSPENDED"
    case rerouted = "REROUTED"
    case bypassLocal = "BYPASS_LOCAL"
    case delays = "DELAYS"
    case maintenance = "MAINTENANCE"
    case unknown = "UNKNOWN"
    
    public init(rawValueOrUnknown rawValue: String) {
        self = DisruptionType(rawValue: rawValue.uppercased()) ?? .unknown
    }
}

/// A time-bounded transit service disruption record (planned calendar work or dynamic alert).
public struct ServiceDisruptionRecord: Identifiable, Sendable, Codable, Equatable, Hashable {
    public let id: String
    public let routeId: String
    public let stopId: String?
    public let directionId: Int?
    public let startEpoch: Int64
    public let endEpoch: Int64
    public let disruptionType: DisruptionType
    public let summaryText: String?
    
    public init(
        id: String? = nil,
        routeId: String,
        stopId: String? = nil,
        directionId: Int? = nil,
        startEpoch: Int64,
        endEpoch: Int64,
        disruptionType: DisruptionType,
        summaryText: String? = nil
    ) {
        self.id = id ?? "disr_\(routeId)_\(stopId ?? "all")_\(directionId.map(String.init) ?? "all")_\(startEpoch)"
        self.routeId = routeId
        self.stopId = stopId
        self.directionId = directionId
        self.startEpoch = startEpoch
        self.endEpoch = endEpoch
        self.disruptionType = disruptionType
        self.summaryText = summaryText
    }
    
    /// Returns true if the disruption is actively ongoing at the given epoch timestamp.
    public func isActive(at epoch: Int64) -> Bool {
        return epoch >= startEpoch && epoch <= endEpoch
    }
    
    /// Returns true if the disruption is actively ongoing at the given date.
    public func isActive(at date: Date) -> Bool {
        return isActive(at: Int64(date.timeIntervalSince1970))
    }
    
    /// Returns true if this disruption applies to the specified stop and direction.
    public func appliesTo(stopId: String?, directionId: Int?) -> Bool {
        if let targetStop = self.stopId, let checkStop = stopId, targetStop != checkStop {
            return false
        }
        if let targetDir = self.directionId, let checkDir = directionId, targetDir != checkDir {
            return false
        }
        return true
    }
}

/// Dynamic in-memory bitmask of active service disruptions for rapid O(1) checking.
public struct TransitDisruptionBitmask: Sendable, Equatable {
    public let activeDisruptions: [ServiceDisruptionRecord]
    public let disruptedStopIds: Set<String>
    public let disruptedRouteIds: Set<String>
    public let disruptedSegments: Set<String> // "routeId:fromStop:toStop"
    
    public init(disruptions: [ServiceDisruptionRecord]) {
        self.activeDisruptions = disruptions
        
        var stopIds = Set<String>()
        var routeIds = Set<String>()
        var segments = Set<String>()
        
        for d in disruptions {
            if let stop = d.stopId {
                stopIds.insert(stop)
            } else {
                routeIds.insert(d.routeId)
            }
            if d.disruptionType == .suspended && d.stopId == nil {
                routeIds.insert(d.routeId)
            }
        }
        
        self.disruptedStopIds = stopIds
        self.disruptedRouteIds = routeIds
        self.disruptedSegments = segments
    }
    
    /// Returns false if the stop is closed or fully disrupted.
    public func isStopActive(_ stopId: String) -> Bool {
        return !disruptedStopIds.contains(stopId)
    }
    
    /// Returns false if the route segment between two stops is disrupted.
    public func isRouteSegmentActive(routeId: String, fromStop: String, toStop: String) -> Bool {
        if disruptedRouteIds.contains(routeId) {
            return false
        }
        if disruptedStopIds.contains(fromStop) || disruptedStopIds.contains(toStop) {
            return false
        }
        let key = "\(routeId):\(fromStop):\(toStop)"
        return !disruptedSegments.contains(key)
    }
    
    /// Returns false if the entire route is suspended.
    public func isRouteActive(_ routeId: String) -> Bool {
        return !disruptedRouteIds.contains(routeId)
    }
}

// MARK: - 15-Minute Origin Dispatch Slot Profiler Models

/// 15-minute origin dispatch slot profile for GTFS-update-immune duration & regularity stats.
public struct TripSlotProfileRecord: Identifiable, Sendable, Codable, Equatable, Hashable {
    public let routeId: String
    public let directionId: Int
    public let originSlotIndex: Int // 0..95 (15-min intervals from midnight)
    public let stopId: String
    public let dayType: Int          // 0 = Weekday, 1 = Saturday, 2 = Sunday
    public let medianDurationSec: Int
    public let p90DurationSec: Int
    public let regularityPct: Double // 0.0 .. 100.0
    public let sampleCount: Int
    
    public var id: String {
        "\(routeId)_\(directionId)_\(originSlotIndex)_\(stopId)_\(dayType)"
    }
    
    public init(
        routeId: String,
        directionId: Int,
        originSlotIndex: Int,
        stopId: String,
        dayType: Int,
        medianDurationSec: Int,
        p90DurationSec: Int,
        regularityPct: Double,
        sampleCount: Int
    ) {
        self.routeId = routeId
        self.directionId = directionId
        self.originSlotIndex = min(max(0, originSlotIndex), 95)
        self.stopId = stopId
        self.dayType = min(max(0, dayType), 2)
        self.medianDurationSec = medianDurationSec
        self.p90DurationSec = p90DurationSec
        self.regularityPct = regularityPct
        self.sampleCount = sampleCount
    }
    
    // MARK: - Slot Math Helpers
    
    /// Calculates the 15-minute origin slot index (0..95) from seconds past midnight.
    public static func slotIndex(secondsFromMidnight: Int) -> Int {
        let normalizedSec = (secondsFromMidnight % 86400 + 86400) % 86400
        return normalizedSec / 900 // 900s = 15 minutes
    }
    
    /// Calculates the 15-minute origin slot index (0..95) from a Date instance in the local timezone.
    public static func slotIndex(for date: Date, calendar: Calendar = Calendar.current) -> Int {
        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)
        let secondsFromMidnight = hour * 3600 + minute * 60
        return slotIndex(secondsFromMidnight: secondsFromMidnight)
    }
    
    /// Returns the start and end seconds from midnight for a given slot index (0..95).
    public static func slotRange(slotIndex: Int) -> (startSec: Int, endSec: Int) {
        let clampedSlot = min(max(0, slotIndex), 95)
        let start = clampedSlot * 900
        let end = start + 900
        return (startSec: start, endSec: end)
    }
    
    /// Maps a calendar date to a day_type (0 = Weekday, 1 = Saturday, 2 = Sunday).
    public static func dayType(for date: Date, calendar: Calendar = Calendar.current) -> Int {
        let weekday = calendar.component(.weekday, from: date)
        switch weekday {
        case 7: // Saturday
            return 1
        case 1: // Sunday
            return 2
        default: // Monday to Friday (2..6)
            return 0
        }
    }
}

// MARK: - Reliability Quantization & Dequantization

public enum ReliabilityQuantizer {
    /// Quantizes a float/double scalar in seconds to 16-bit unsigned integer (deciseconds offset by +32000).
    /// Range: [-3200.0, +3353.5] seconds -> [0, 65535].
    @inlinable
    public static func quantize(_ val: Double) -> UInt16 {
        let clamped = max(-3200.0, min(3353.5, val))
        let deciseconds = floor((clamped + 3200.0) * 10.0 + 0.5)
        return UInt16(deciseconds)
    }
    
    /// Dequantizes a 16-bit integer back to a Double in seconds with 0.1s precision.
    @inlinable
    public static func dequantize(_ q16: Int32) -> Double {
        return (Double(q16) / 10.0) - 3200.0
    }
    
    /// Dequantizes a 16-bit integer back to a Float in seconds with 0.1s precision.
    @inlinable
    public static func dequantizeFloat(_ q16: Int32) -> Float {
        return (Float(q16) / 10.0) - 3200.0
    }
}

// MARK: - Hourly Reliability & 168-Hour Window Aggregation Models

/// Hourly reliability record stored in `stop_reliability_hourly` with pre-squared moment sums.
public struct HourlyReliabilityRecord: Identifiable, Sendable, Codable, Equatable {
    public let stopId: String
    public let routeId: String
    public let directionId: Int
    public let hourOfDay: Int // 0..23
    public let dayType: Int   // 0 = Weekday, 1 = Saturday, 2 = Sunday (or 0..6 for legacy dayOfWeek)
    
    public let sampleCount: Int
    public let scheduledCount: Int
    
    // O(1) EWT and Variance Aggregation Sums (seconds / squared seconds)
    public let sumActualHeadway: Double
    public let sumSqActualHeadway: Double
    public let sumSchedHeadway: Double
    public let sumSqSchedHeadway: Double
    
    // OTP Bucket Counters
    public let onTimeCount: Int
    public let earlyCount: Int
    public let lateCount: Int
    
    // 16-Bit Quantized Distribution Percentiles
    public let p10DeltaQ16: Int32
    public let p50DeltaQ16: Int32
    public let p90DeltaQ16: Int32
    public let p10HeadwayQ16: Int32
    public let p50HeadwayQ16: Int32
    public let p90HeadwayQ16: Int32
    
    public var id: String {
        "\(routeId)_\(stopId)_\(directionId)_\(dayType)_\(hourOfDay)"
    }
    
    // MARK: - Mathematical Moment Derivations
    
    /// Expected Scheduled Wait Time: SWT = ∑H_sched^2 / (2 * ∑H_sched) in seconds.
    public var swt: Double {
        guard sumSchedHeadway > 0 else { return 0.0 }
        return sumSqSchedHeadway / (2.0 * sumSchedHeadway)
    }
    
    /// Expected Actual Wait Time: AWT = ∑H_actual^2 / (2 * ∑H_actual) in seconds.
    public var awt: Double {
        guard sumActualHeadway > 0 else { return 0.0 }
        return sumSqActualHeadway / (2.0 * sumActualHeadway)
    }
    
    /// Excess Wait Time: EWT = max(0, AWT - SWT) in seconds.
    public var ewt: Double {
        return max(0.0, awt - swt)
    }
    
    /// On-Time Performance ratio [0.0 .. 1.0].
    public var otpRatio: Double {
        let total = onTimeCount + earlyCount + lateCount
        guard total > 0 else {
            return sampleCount > 0 ? 1.0 : 0.0
        }
        return Double(onTimeCount) / Double(total)
    }
    
    /// On-Time Performance percentage [0.0 .. 100.0].
    public var otpPct: Double {
        return otpRatio * 100.0
    }
    
    /// Population Headway Variance: Var(H) = (∑H^2 / N) - (∑H / N)^2.
    public var headwayVariance: Double {
        guard sampleCount > 0 else { return 0.0 }
        let mean = sumActualHeadway / Double(sampleCount)
        let meanSq = sumSqActualHeadway / Double(sampleCount)
        return max(0.0, meanSq - (mean * mean))
    }
    
    /// Headway standard deviation in seconds.
    public var headwayStdDev: Double {
        return sqrt(headwayVariance)
    }
    
    // MARK: - Dequantized Percentile Properties
    
    public var p10DeltaSec: Double { ReliabilityQuantizer.dequantize(p10DeltaQ16) }
    public var p50DeltaSec: Double { ReliabilityQuantizer.dequantize(p50DeltaQ16) }
    public var p90DeltaSec: Double { ReliabilityQuantizer.dequantize(p90DeltaQ16) }
    public var p10HeadwaySec: Double { ReliabilityQuantizer.dequantize(p10HeadwayQ16) }
    public var p50HeadwaySec: Double { ReliabilityQuantizer.dequantize(p50HeadwayQ16) }
    public var p90HeadwaySec: Double { ReliabilityQuantizer.dequantize(p90HeadwayQ16) }
    
    public init(
        stopId: String,
        routeId: String,
        directionId: Int = 0,
        hourOfDay: Int,
        dayType: Int,
        sampleCount: Int,
        scheduledCount: Int,
        sumActualHeadway: Double,
        sumSqActualHeadway: Double,
        sumSchedHeadway: Double,
        sumSqSchedHeadway: Double,
        onTimeCount: Int,
        earlyCount: Int,
        lateCount: Int,
        p10DeltaQ16: Int32 = 32000,
        p50DeltaQ16: Int32 = 32000,
        p90DeltaQ16: Int32 = 32000,
        p10HeadwayQ16: Int32 = 35000,
        p50HeadwayQ16: Int32 = 35000,
        p90HeadwayQ16: Int32 = 35000
    ) {
        self.stopId = stopId
        self.routeId = routeId
        self.directionId = directionId
        self.hourOfDay = min(max(0, hourOfDay), 23)
        self.dayType = dayType
        self.sampleCount = sampleCount
        self.scheduledCount = scheduledCount
        self.sumActualHeadway = sumActualHeadway
        self.sumSqActualHeadway = sumSqActualHeadway
        self.sumSchedHeadway = sumSchedHeadway
        self.sumSqSchedHeadway = sumSqSchedHeadway
        self.onTimeCount = onTimeCount
        self.earlyCount = earlyCount
        self.lateCount = lateCount
        self.p10DeltaQ16 = p10DeltaQ16
        self.p50DeltaQ16 = p50DeltaQ16
        self.p90DeltaQ16 = p90DeltaQ16
        self.p10HeadwayQ16 = p10HeadwayQ16
        self.p50HeadwayQ16 = p50HeadwayQ16
        self.p90HeadwayQ16 = p90HeadwayQ16
    }
}

/// Aggregated reliability summary across multi-hour periods or 168-hour rolling windows.
public struct ReliabilityAggregationSummary: Sendable, Codable, Equatable {
    public let sampleCount: Int
    public let scheduledCount: Int
    public let sumActualHeadway: Double
    public let sumSqActualHeadway: Double
    public let sumSchedHeadway: Double
    public let sumSqSchedHeadway: Double
    public let onTimeCount: Int
    public let earlyCount: Int
    public let lateCount: Int
    
    public let swt: Double
    public let awt: Double
    public let ewt: Double
    public let otpRatio: Double
    public let otpPct: Double
    public let headwayVariance: Double
    public let headwayStdDev: Double
    public let p10DeltaSec: Double
    public let p50DeltaSec: Double
    public let p90DeltaSec: Double
    public let p50HeadwaySec: Double
    
    public init(records: [HourlyReliabilityRecord]) {
        guard !records.isEmpty else {
            self.sampleCount = 0
            self.scheduledCount = 0
            self.sumActualHeadway = 0.0
            self.sumSqActualHeadway = 0.0
            self.sumSchedHeadway = 0.0
            self.sumSqSchedHeadway = 0.0
            self.onTimeCount = 0
            self.earlyCount = 0
            self.lateCount = 0
            self.swt = 0.0
            self.awt = 0.0
            self.ewt = 0.0
            self.otpRatio = 0.0
            self.otpPct = 0.0
            self.headwayVariance = 0.0
            self.headwayStdDev = 0.0
            self.p10DeltaSec = 0.0
            self.p50DeltaSec = 0.0
            self.p90DeltaSec = 0.0
            self.p50HeadwaySec = 0.0
            return
        }
        
        var totalSamples = 0
        var totalScheduled = 0
        var sumActH = 0.0
        var sumSqActH = 0.0
        var sumSchH = 0.0
        var sumSqSchH = 0.0
        var onTime = 0
        var early = 0
        var late = 0
        
        var weightedP10Delta = 0.0
        var weightedP50Delta = 0.0
        var weightedP90Delta = 0.0
        var weightedP50Headway = 0.0
        var weightSum = 0.0
        
        for r in records {
            totalSamples += r.sampleCount
            totalScheduled += r.scheduledCount
            sumActH += r.sumActualHeadway
            sumSqActH += r.sumSqActualHeadway
            sumSchH += r.sumSchedHeadway
            sumSqSchH += r.sumSqSchedHeadway
            onTime += r.onTimeCount
            early += r.earlyCount
            late += r.lateCount
            
            let weight = max(1.0, Double(r.sampleCount))
            weightedP10Delta += r.p10DeltaSec * weight
            weightedP50Delta += r.p50DeltaSec * weight
            weightedP90Delta += r.p90DeltaSec * weight
            weightedP50Headway += r.p50HeadwaySec * weight
            weightSum += weight
        }
        
        self.sampleCount = totalSamples
        self.scheduledCount = totalScheduled
        self.sumActualHeadway = sumActH
        self.sumSqActualHeadway = sumSqActH
        self.sumSchedHeadway = sumSchH
        self.sumSqSchedHeadway = sumSqSchH
        self.onTimeCount = onTime
        self.earlyCount = early
        self.lateCount = late
        
        let calculatedSwt = sumSchH > 0 ? (sumSqSchH / (2.0 * sumSchH)) : 0.0
        let calculatedAwt = sumActH > 0 ? (sumSqActH / (2.0 * sumActH)) : 0.0
        self.swt = calculatedSwt
        self.awt = calculatedAwt
        self.ewt = max(0.0, calculatedAwt - calculatedSwt)
        
        let totalOtp = onTime + early + late
        self.otpRatio = totalOtp > 0 ? (Double(onTime) / Double(totalOtp)) : (totalSamples > 0 ? 1.0 : 0.0)
        self.otpPct = self.otpRatio * 100.0
        
        if totalSamples > 0 {
            let mean = sumActH / Double(totalSamples)
            let meanSq = sumSqActH / Double(totalSamples)
            self.headwayVariance = max(0.0, meanSq - (mean * mean))
        } else {
            self.headwayVariance = 0.0
        }
        self.headwayStdDev = sqrt(self.headwayVariance)
        
        if weightSum > 0 {
            self.p10DeltaSec = weightedP10Delta / weightSum
            self.p50DeltaSec = weightedP50Delta / weightSum
            self.p90DeltaSec = weightedP90Delta / weightSum
            self.p50HeadwaySec = weightedP50Headway / weightSum
        } else {
            self.p10DeltaSec = 0.0
            self.p50DeltaSec = 0.0
            self.p90DeltaSec = 0.0
            self.p50HeadwaySec = 0.0
        }
    }
}

// MARK: - 120Hz Immediate-Mode Canvas Reliability Buffer Container

/// Contiguous memory buffer container packing 4,320 Float32 elements for the 120Hz Canvas render loop.
public final class CanvasReliabilityBufferContainer: Sendable {
    public static let bufferElementCount = 4320
    
    // Contiguous memory buffer backing the 120Hz SwiftUI Canvas render loop
    public let floatBuffer: UnsafeMutableBufferPointer<Float>
    
    public init() {
        self.floatBuffer = UnsafeMutableBufferPointer<Float>.allocate(capacity: Self.bufferElementCount)
        self.floatBuffer.initialize(repeating: 0.0)
    }
    
    deinit {
        self.floatBuffer.deallocate()
    }
    
    @inline(__always)
    public static func calculateOffset(hour: Int, dayType: Int, direction: Int, metricIndex: Int) -> Int {
        let clampedH = min(max(0, hour), 23)
        let clampedDay = min(max(0, dayType), 2)
        let clampedDir = min(max(0, direction), 1)
        let clampedMetric = min(max(0, metricIndex), 29)
        return (clampedH * 180) + (clampedDay * 60) + (clampedDir * 30) + clampedMetric
    }
    
    /// Populates the memory buffer from an array of HourlyReliabilityRecord items.
    public func populate(from records: [HourlyReliabilityRecord]) {
        guard let basePtr = self.floatBuffer.baseAddress else { return }
        
        // Zero-fill reset
        memset(basePtr, 0, Self.bufferElementCount * MemoryLayout<Float>.size)
        
        for r in records {
            guard r.hourOfDay >= 0 && r.hourOfDay < 24,
                  r.dayType >= 0 && r.dayType < 3,
                  r.directionId >= 0 && r.directionId < 2 else {
                continue
            }
            
            let baseOffset = Self.calculateOffset(hour: r.hourOfDay, dayType: r.dayType, direction: r.directionId, metricIndex: 0)
            
            basePtr[baseOffset + 0] = Float(r.ewt)
            basePtr[baseOffset + 1] = Float(r.otpRatio)
            basePtr[baseOffset + 2] = Float(r.awt)
            basePtr[baseOffset + 3] = Float(r.swt)
            basePtr[baseOffset + 4] = Float(r.headwayVariance)
            basePtr[baseOffset + 5] = ReliabilityQuantizer.dequantizeFloat(r.p10DeltaQ16)
            basePtr[baseOffset + 6] = ReliabilityQuantizer.dequantizeFloat(r.p50DeltaQ16)
            basePtr[baseOffset + 7] = ReliabilityQuantizer.dequantizeFloat(r.p90DeltaQ16)
            basePtr[baseOffset + 8] = ReliabilityQuantizer.dequantizeFloat(r.p10HeadwayQ16)
            basePtr[baseOffset + 9] = ReliabilityQuantizer.dequantizeFloat(r.p50HeadwayQ16)
            basePtr[baseOffset + 10] = ReliabilityQuantizer.dequantizeFloat(r.p90HeadwayQ16)
        }
    }
    
    /// Copies buffer contents into a Swift Float array.
    public func toArray() -> [Float] {
        return Array(self.floatBuffer)
    }
}
