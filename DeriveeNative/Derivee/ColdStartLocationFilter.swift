import CoreLocation
import Foundation

/// Multi-stage baseband signal filter and contextual drift gate for ambient location tracking.
/// Handles CoreLocation cold-start convergence, stale cache rejection, Rayleigh error bounding for H3 Res 11,
/// and classification between urban canyon multipath noise vs. legitimate subway emergence discontinuities.
public struct ColdStartLocationFilter: Sendable {
    
    public enum FilterResult: Sendable, Equatable {
        /// Fix passed all gates and is accepted for spatial hashing & persistence.
        case accepted(location: CLLocation, isFirstAcceptedFix: Bool, stepDistance: CLLocationDistance)
        /// Dropped because the timestamp reflects a historical cached fix or invalid clock drift.
        case discardedStale(age: TimeInterval)
        /// Dropped because horizontal uncertainty exceeds the maximum allowed threshold for H3 Res 11.
        case discardedUncertain(accuracy: CLLocationAccuracy)
        /// Buffered during the warmup epoch to seed baseline coordinates before committing hex unlocks.
        case warmingUp(currentFix: Int, target: Int)
        /// Dropped because the calculated or hardware velocity indicates a multipath GPS bounce.
        case discardedExcessiveSpeed(speed: Double)
    }
    
    private var lastValidLocation: CLLocation?
    private var isWarmingUp: Bool = true
    private var validFixCount: Int = 0
    private var consecutiveExcessiveSpeedDrops: Int = 0
    
    public let maxStaleness: TimeInterval
    public let targetAccuracy: CLLocationAccuracy
    public let requiredWarmupFixes: Int
    public let maxPedestrianSpeed: Double
    public let temporalGapThreshold: TimeInterval
    
    /// Initializes the filter with specified convergence and gating parameters.
    /// - Parameters:
    ///   - maxStaleness: Maximum allowed fix age in seconds (default: 5.0s).
    ///   - targetAccuracy: Maximum allowed horizontalAccuracy in meters (default: 25.0m).
    ///   - requiredWarmupFixes: Number of valid fixes required to complete cold-start warmup (default: 2).
    ///   - maxPedestrianSpeed: Maximum allowable speed in m/s (~12 m/s / 27 mph).
    ///   - temporalGapThreshold: Time gap in seconds that indicates subway emergence / discontinuity (default: 15.0s).
    public init(
        maxStaleness: TimeInterval = 5.0,
        targetAccuracy: CLLocationAccuracy = 25.0,
        requiredWarmupFixes: Int = 2,
        maxPedestrianSpeed: Double = 12.0,
        temporalGapThreshold: TimeInterval = 15.0
    ) {
        self.maxStaleness = maxStaleness
        self.targetAccuracy = targetAccuracy
        self.requiredWarmupFixes = requiredWarmupFixes
        self.maxPedestrianSpeed = maxPedestrianSpeed
        self.temporalGapThreshold = temporalGapThreshold
    }
    
    /// Evaluates a location fix through the multi-stage filter.
    /// - Parameters:
    ///   - location: The incoming `CLLocation` fix from CoreLocation.
    ///   - now: The current reference timestamp (defaults to `Date()`, injectable for deterministic unit testing).
    /// - Returns: A `FilterResult` detailing acceptance or discard rationale.
    public mutating func process(location: CLLocation, now: Date = Date()) -> FilterResult {
        // Stage 1: Staleness Check (reject cached fixes older than maxStaleness)
        let age = now.timeIntervalSince(location.timestamp)
        guard age <= maxStaleness else {
            return .discardedStale(age: age)
        }
        
        // Stage 2: Accuracy Convergence Check
        guard location.horizontalAccuracy >= 0,
              location.horizontalAccuracy <= targetAccuracy else {
            return .discardedUncertain(accuracy: location.horizontalAccuracy)
        }
        
        // Stage 3 & 4: Velocity Consistency, Discontinuity & Warmup State Machine
        guard let previous = lastValidLocation else {
            lastValidLocation = location
            validFixCount = 1
            consecutiveExcessiveSpeedDrops = 0
            if requiredWarmupFixes <= 1 {
                isWarmingUp = false
                return .accepted(location: location, isFirstAcceptedFix: true, stepDistance: 0)
            }
            return .warmingUp(currentFix: 1, target: requiredWarmupFixes)
        }
        
        let deltaTime = location.timestamp.timeIntervalSince(previous.timestamp)
        let deltaDistance = location.distance(from: previous)
        
        // Discontinuity / Temporal Gap (Subway emergence, background wake, cold resume)
        if deltaTime >= temporalGapThreshold {
            lastValidLocation = location
            consecutiveExcessiveSpeedDrops = 0
            if isWarmingUp {
                validFixCount = 1
                return .warmingUp(currentFix: 1, target: requiredWarmupFixes)
            }
            // Accept the point and reset velocity baseline without treating the jump as walked distance
            return .accepted(location: location, isFirstAcceptedFix: false, stepDistance: 0)
        }
        
        // Continuous Tracking - reject non-positive time deltas
        guard deltaTime > 0 else {
            return .discardedStale(age: 0)
        }
        
        let effectiveSpeed: Double
        if location.speed >= 0 {
            effectiveSpeed = location.speed
        } else {
            effectiveSpeed = deltaDistance / deltaTime
        }
        
        guard effectiveSpeed <= maxPedestrianSpeed else {
            consecutiveExcessiveSpeedDrops += 1
            // If multiple consecutive fixes occur at the new location (e.g. teleport or vehicular emergence),
            // reset baseline so we don't stay wedged forever
            if consecutiveExcessiveSpeedDrops >= 2 {
                consecutiveExcessiveSpeedDrops = 0
                lastValidLocation = location
                if isWarmingUp {
                    validFixCount += 1
                    if validFixCount >= requiredWarmupFixes {
                        isWarmingUp = false
                        return .accepted(location: location, isFirstAcceptedFix: true, stepDistance: 0)
                    }
                    return .warmingUp(currentFix: validFixCount, target: requiredWarmupFixes)
                }
                return .accepted(location: location, isFirstAcceptedFix: false, stepDistance: 0)
            }
            return .discardedExcessiveSpeed(speed: effectiveSpeed)
        }
        
        consecutiveExcessiveSpeedDrops = 0
        lastValidLocation = location
        
        if isWarmingUp {
            validFixCount += 1
            if validFixCount >= requiredWarmupFixes {
                isWarmingUp = false
                return .accepted(location: location, isFirstAcceptedFix: true, stepDistance: 0)
            }
            return .warmingUp(currentFix: validFixCount, target: requiredWarmupFixes)
        }
        
        return .accepted(location: location, isFirstAcceptedFix: false, stepDistance: deltaDistance)
    }
    
    /// Resets warmup and baseline tracking state on session start/stop.
    public mutating func reset() {
        lastValidLocation = nil
        isWarmingUp = true
        validFixCount = 0
        consecutiveExcessiveSpeedDrops = 0
    }
}
