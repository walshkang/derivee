import Foundation
import CoreLocation

/// Automated missed-connection detection engine comparing live GPS telemetry against platform departure timestamps (Wave N-D.8).
/// Accounts for dynamic walking speeds, subterranean vertical circulation buffers, and slack tolerances.
public struct MissedConnectionDetector: Sendable {
    
    /// Default pedestrian walking speed on urban sidewalks (1.2 m/s ≈ 4.3 km/h).
    public static let defaultWalkingSpeedMps: Double = 1.2
    
    /// Bounded range for observed walking speed to avoid GPS multipath jumps or stationary dwells.
    public static let minPlausibleSpeedMps: Double = 0.7
    public static let maxPlausibleSpeedMps: Double = 1.8
    
    /// Vertical circulation buffer for station descent, turnstiles, and stairs (45 seconds).
    public static let verticalStationBufferSec: Double = 45.0
    
    /// Slack tolerance to prevent premature false alarms during minor sprint pacing (30 seconds).
    public static let slackToleranceSec: Double = 30.0
    
    /// Platform arrival radius (35 meters). Within this distance, user is considered at the platform.
    public static let platformArrivalRadiusMeters: Double = 35.0
    
    public init() {}
    
    /// Evaluates connection status for the upcoming transit leg relative to the passenger's current position and clock.
    ///
    /// - Parameters:
    ///   - itinerary: Active journey itinerary.
    ///   - currentLegIndex: Currently executing leg index.
    ///   - userLocation: Live GPS coordinate of the passenger.
    ///   - userSpeedMps: Observed GPS speed, if valid.
    ///   - currentClockSec: Midnight-offset current time in seconds.
    ///   - targetStationCoordinate: Geographic coordinate of the boarding platform / station entrance.
    /// - Returns: A `MissedConnectionEvent` if a deficit or miss is identified, or `nil` if on track.
    public func evaluateConnection(
        itinerary: JourneyItinerary,
        currentLegIndex: Int,
        userLocation: CLLocationCoordinate2D,
        userSpeedMps: Double? = nil,
        currentClockSec: UInt32,
        targetStationCoordinate: CLLocationCoordinate2D
    ) -> MissedConnectionEvent? {
        // Find the next upcoming transit leg (subway, bus, lightRail, ferry)
        guard let transitLegIndex = findUpcomingTransitLegIndex(in: itinerary, from: currentLegIndex) else {
            return nil
        }
        
        let transitLeg = itinerary.legs[transitLegIndex]
        let departureSec = transitLeg.departureTimeSec
        
        // Compute direct Euclidean distance to station
        let distanceMeters = distanceBetween(userLocation, targetStationCoordinate)
        
        // If user is already within platform arrival radius, they made the platform
        if distanceMeters <= Self.platformArrivalRadiusMeters {
            return nil
        }
        
        // Resolve effective walking speed
        let speed = resolveWalkingSpeed(userSpeedMps)
        
        // Compute required walking time + vertical station circulation buffer
        let walkTimeNeededSec = (distanceMeters / speed) + Self.verticalStationBufferSec
        
        // Estimated user arrival at platform
        let estimatedUserArrivalSec = currentClockSec + UInt32(ceil(walkTimeNeededSec))
        
        // Evaluate condition: Did departure time already elapse?
        if currentClockSec > departureSec {
            let secondsLate = currentClockSec - departureSec
            let minutesLate = max(1, Int(ceil(Double(secondsLate) / 60.0)))
            let status = MissedConnectionStatus.confirmedMiss(minutesLate: minutesLate)
            
            return MissedConnectionEvent(
                legIndex: transitLegIndex,
                missedLeg: transitLeg,
                stationName: transitLeg.originName,
                scheduledDepartureSec: departureSec,
                estimatedUserArrivalSec: estimatedUserArrivalSec,
                deficitSeconds: Double(secondsLate) + walkTimeNeededSec,
                status: status
            )
        }
        
        // Available time until departure
        let availableTimeSec = Double(departureSec - currentClockSec)
        
        // Deficit calculation: needed time minus available time minus slack tolerance
        let deficit = walkTimeNeededSec - availableTimeSec
        
        if deficit > Self.slackToleranceSec {
            let status = MissedConnectionStatus.imminentMiss(deficitSeconds: deficit)
            return MissedConnectionEvent(
                legIndex: transitLegIndex,
                missedLeg: transitLeg,
                stationName: transitLeg.originName,
                scheduledDepartureSec: departureSec,
                estimatedUserArrivalSec: estimatedUserArrivalSec,
                deficitSeconds: deficit,
                status: status
            )
        }
        
        return nil
    }
    
    // MARK: - Internal Helpers
    
    private func findUpcomingTransitLegIndex(in itinerary: JourneyItinerary, from currentIndex: Int) -> Int? {
        guard currentIndex >= 0 && currentIndex < itinerary.legs.count else { return nil }
        
        for index in currentIndex..<itinerary.legs.count {
            let leg = itinerary.legs[index]
            if leg.mode.isTransit {
                return index
            }
        }
        return nil
    }
    
    private func resolveWalkingSpeed(_ speed: Double?) -> Double {
        guard let s = speed, s >= Self.minPlausibleSpeedMps && s <= Self.maxPlausibleSpeedMps else {
            return Self.defaultWalkingSpeedMps
        }
        return s
    }
    
    private func distanceBetween(_ c1: CLLocationCoordinate2D, _ c2: CLLocationCoordinate2D) -> Double {
        let loc1 = CLLocation(latitude: c1.latitude, longitude: c1.longitude)
        let loc2 = CLLocation(latitude: c2.latitude, longitude: c2.longitude)
        return loc1.distance(from: loc2)
    }
}
