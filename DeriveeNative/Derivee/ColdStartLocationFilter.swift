import CoreLocation
import Foundation

/// Multi-stage baseband signal filter and contextual drift gate for ambient location tracking.
/// Handles CoreLocation cold-start convergence, stale cache rejection, Rayleigh error bounding for H3 Res 11,
/// stationary dwell auto-unlocking, and classification between urban canyon multipath noise vs. legitimate subway emergence discontinuities.
public struct ColdStartLocationFilter: Sendable {
    
    public enum FilterResult: Sendable, Equatable {
        /// Fix passed all gates and is accepted for spatial hashing & persistence.
        case accepted(location: CLLocation, isFirstAcceptedFix: Bool, stepDistance: CLLocationDistance)
        /// Fix has intermediate accuracy and requires a stationary dwell window before hex commit.
        case requiresDwell(location: CLLocation, dwellDuration: TimeInterval)
        /// Dropped because the timestamp reflects a historical cached fix or invalid clock drift.
        case discardedStale(age: TimeInterval)
        /// Dropped because horizontal uncertainty exceeds the maximum allowed threshold for H3 Res 11.
        case discardedUncertain(accuracy: CLLocationAccuracy)
        /// Dropped because the calculated or hardware velocity indicates a multipath GPS bounce.
        case discardedExcessiveSpeed(speed: Double)
    }
    
    private var lastValidLocation: CLLocation?
    private var isWarmingUp: Bool = true
    private var consecutiveExcessiveSpeedDrops: Int = 0
    
    public let maxStaleness: TimeInterval
    public let targetAccuracy: CLLocationAccuracy
    public let highAccuracyThreshold: CLLocationAccuracy
    public let dwellDuration: TimeInterval
    public let maxPedestrianSpeed: Double
    public let temporalGapThreshold: TimeInterval
    
    /// Initializes the filter with specified convergence and gating parameters.
    /// - Parameters:
    ///   - maxStaleness: Maximum allowed fix age in seconds (default: 5.0s).
    ///   - targetAccuracy: Maximum allowed horizontalAccuracy in meters (default: 25.0m).
    ///   - highAccuracyThreshold: Maximum horizontalAccuracy to unlock immediately without dwell (default: 12.0m).
    ///   - dwellDuration: Stationary dwell duration in seconds for intermediate accuracy fixes (default: 3.0s).
    ///   - maxPedestrianSpeed: Maximum allowable speed in m/s (~12 m/s / 27 mph).
    ///   - temporalGapThreshold: Time gap in seconds that indicates subway emergence / discontinuity (default: 15.0s).
    public init(
        maxStaleness: TimeInterval = 5.0,
        targetAccuracy: CLLocationAccuracy = 25.0,
        highAccuracyThreshold: CLLocationAccuracy = 12.0,
        dwellDuration: TimeInterval = 3.0,
        maxPedestrianSpeed: Double = 12.0,
        temporalGapThreshold: TimeInterval = 15.0
    ) {
        self.maxStaleness = maxStaleness
        self.targetAccuracy = targetAccuracy
        self.highAccuracyThreshold = highAccuracyThreshold
        self.dwellDuration = dwellDuration
        self.maxPedestrianSpeed = maxPedestrianSpeed
        self.temporalGapThreshold = temporalGapThreshold
    }
    
    /// Evaluates a location fix through the multi-stage filter.
    /// - Parameters:
    ///   - location: The incoming `CLLocation` fix from CoreLocation.
    ///   - now: The current reference timestamp (defaults to `Date()`, injectable for deterministic unit testing).
    /// - Returns: A `FilterResult` detailing acceptance, dwell requirement, or discard rationale.
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
        
        // Stage 3 & 4: Velocity Consistency, Discontinuity & Warmup / Dwell State Machine
        guard let previous = lastValidLocation else {
            lastValidLocation = location
            consecutiveExcessiveSpeedDrops = 0
            
            if location.horizontalAccuracy <= highAccuracyThreshold {
                isWarmingUp = false
                return .accepted(location: location, isFirstAcceptedFix: true, stepDistance: 0)
            } else {
                isWarmingUp = true
                return .requiresDwell(location: location, dwellDuration: dwellDuration)
            }
        }
        
        let deltaTime = location.timestamp.timeIntervalSince(previous.timestamp)
        let deltaDistance = location.distance(from: previous)
        
        // Discontinuity / Temporal Gap (Subway emergence, background wake, cold resume)
        if deltaTime >= temporalGapThreshold {
            lastValidLocation = location
            consecutiveExcessiveSpeedDrops = 0
            
            if location.horizontalAccuracy <= highAccuracyThreshold {
                isWarmingUp = false
                return .accepted(location: location, isFirstAcceptedFix: false, stepDistance: 0)
            } else {
                isWarmingUp = true
                return .requiresDwell(location: location, dwellDuration: dwellDuration)
            }
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
                
                if location.horizontalAccuracy <= highAccuracyThreshold {
                    isWarmingUp = false
                    return .accepted(location: location, isFirstAcceptedFix: false, stepDistance: 0)
                } else {
                    isWarmingUp = true
                    return .requiresDwell(location: location, dwellDuration: dwellDuration)
                }
            }
            return .discardedExcessiveSpeed(speed: effectiveSpeed)
        }
        
        consecutiveExcessiveSpeedDrops = 0
        let wasWarmingUp = isWarmingUp
        isWarmingUp = false
        lastValidLocation = location
        
        return .accepted(location: location, isFirstAcceptedFix: wasWarmingUp, stepDistance: deltaDistance)
    }
    
    /// Commits the pending dwell candidate when the dwell timer expires without contradiction.
    public mutating func commitDwell() {
        isWarmingUp = false
        consecutiveExcessiveSpeedDrops = 0
    }
    
    /// Resets warmup and baseline tracking state on session start/stop.
    public mutating func reset() {
        lastValidLocation = nil
        isWarmingUp = true
        consecutiveExcessiveSpeedDrops = 0
    }
}
