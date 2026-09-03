import Foundation
import CoreLocation

/// Represents the status of a passenger connecting to an upcoming transit leg (Wave N-D.8).
public enum MissedConnectionStatus: Sendable, Equatable, Hashable {
    /// Passenger is on schedule to reach the platform before vehicle departure.
    case onTrack
    
    /// Telemetry indicates the passenger cannot reach the platform in time at current walking speed.
    /// Deficit is the required time minus available time in seconds.
    case imminentMiss(deficitSeconds: Double)
    
    /// The scheduled or real-time departure has passed while the passenger is still outside/en route.
    case confirmedMiss(minutesLate: Int)
    
    public var isMissed: Bool {
        switch self {
        case .onTrack:
            return false
        case .imminentMiss, .confirmedMiss:
            return true
        }
    }
}

/// Diagnostic and reactive event emitted when a connection deficit or miss is identified.
public struct MissedConnectionEvent: Identifiable, Sendable, Equatable, Hashable {
    public let id: UUID
    public let legIndex: Int
    public let missedLeg: JourneyLeg
    public let stationName: String
    public let scheduledDepartureSec: UInt32
    public let estimatedUserArrivalSec: UInt32
    public let deficitSeconds: Double
    public let detectedAt: Date
    public let status: MissedConnectionStatus
    
    public init(
        id: UUID = UUID(),
        legIndex: Int,
        missedLeg: JourneyLeg,
        stationName: String,
        scheduledDepartureSec: UInt32,
        estimatedUserArrivalSec: UInt32,
        deficitSeconds: Double,
        detectedAt: Date = Date(),
        status: MissedConnectionStatus
    ) {
        self.id = id
        self.legIndex = legIndex
        self.missedLeg = missedLeg
        self.stationName = stationName
        self.scheduledDepartureSec = scheduledDepartureSec
        self.estimatedUserArrivalSec = estimatedUserArrivalSec
        self.deficitSeconds = deficitSeconds
        self.detectedAt = detectedAt
        self.status = status
    }
}

/// Categorization of recovery modalities.
public enum RecoveryOptionType: String, Sendable, Equatable, Hashable {
    case nextTransitDeparture
    case bikeShareFallback
    case alternateSurfaceRoute
    case directWalk
    
    public var iconSystemName: String {
        switch self {
        case .nextTransitDeparture:
            return "clock.arrow.circlepath"
        case .bikeShareFallback:
            return "bicycle"
        case .alternateSurfaceRoute:
            return "bus.fill"
        case .directWalk:
            return "figure.walk"
        }
    }
}

/// An actionable 1-tap recovery candidate.
public struct DynamicRecoveryOption: Identifiable, Sendable, Equatable, Hashable {
    public let id: UUID
    public let type: RecoveryOptionType
    public let title: String
    public let subtitle: String
    public let deltaMinutes: Int
    public let deltaTransfers: Int
    public let mode: LegMode
    public let routeBadge: String?
    public let routeColorHex: String?
    public let estimatedArrivalSec: UInt32
    public let isPrimaryRecommended: Bool
    public let recoveryItinerary: JourneyItinerary
    public let dockRisk: GBFSDockGatingRisk?
    public let batterySocPercent: Int?
    
    public init(
        id: UUID = UUID(),
        type: RecoveryOptionType,
        title: String,
        subtitle: String,
        deltaMinutes: Int,
        deltaTransfers: Int = 0,
        mode: LegMode,
        routeBadge: String? = nil,
        routeColorHex: String? = nil,
        estimatedArrivalSec: UInt32,
        isPrimaryRecommended: Bool = false,
        recoveryItinerary: JourneyItinerary,
        dockRisk: GBFSDockGatingRisk? = nil,
        batterySocPercent: Int? = nil
    ) {
        self.id = id
        self.type = type
        self.title = title
        self.subtitle = subtitle
        self.deltaMinutes = deltaMinutes
        self.deltaTransfers = deltaTransfers
        self.mode = mode
        self.routeBadge = routeBadge
        self.routeColorHex = routeColorHex
        self.estimatedArrivalSec = estimatedArrivalSec
        self.isPrimaryRecommended = isPrimaryRecommended
        self.recoveryItinerary = recoveryItinerary
        self.dockRisk = dockRisk
        self.batterySocPercent = batterySocPercent
    }
    
    public var formattedDelta: String {
        if deltaMinutes == 0 {
            return "Same ETA"
        } else if deltaMinutes > 0 {
            return "+\(deltaMinutes)m"
        } else {
            return "\(deltaMinutes)m faster"
        }
    }
    
    public var formattedArrival: String {
        JourneyItinerary.formatSecondsToClock(estimatedArrivalSec)
    }
}

/// Bundled recovery plan surfaced to the UI with 1-tap options.
public struct DynamicRecoveryPlan: Identifiable, Sendable, Equatable, Hashable {
    public let id: UUID
    public let event: MissedConnectionEvent
    public let options: [DynamicRecoveryOption]
    public let primaryOption: DynamicRecoveryOption
    public let createdAt: Date
    
    public init(
        id: UUID = UUID(),
        event: MissedConnectionEvent,
        options: [DynamicRecoveryOption],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.event = event
        self.options = options
        self.primaryOption = options.first(where: { $0.isPrimaryRecommended }) ?? options.first!
        self.createdAt = createdAt
    }
}
