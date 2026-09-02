import Foundation
import SwiftUI

// MARK: - Routing Profiles

/// Multi-profile navigation modes reflecting diverse commuter mental models and physical tolerances.
public enum RoutingProfile: String, CaseIterable, Identifiable, Sendable, Equatable, Hashable {
    case mostReliable = "most_reliable"
    case fastest = "fastest"
    case fewestTransfers = "fewest_transfers"
    case stepFree = "step_free"
    case multiModalBikeRail = "bike_rail"
    
    public var id: String { rawValue }
    
    public var displayName: String {
        switch self {
        case .mostReliable:
            return "Most Reliable"
        case .fastest:
            return "Fastest"
        case .fewestTransfers:
            return "Fewest Transfers"
        case .stepFree:
            return "Step-Free"
        case .multiModalBikeRail:
            return "Bike + Rail"
        }
    }
    
    public var shortTag: String {
        switch self {
        case .mostReliable:
            return "RELIABLE"
        case .fastest:
            return "FASTEST"
        case .fewestTransfers:
            return "DIRECT"
        case .stepFree:
            return "ACCESSIBLE"
        case .multiModalBikeRail:
            return "BIKE+RAIL"
        }
    }
    
    public var iconName: String {
        switch self {
        case .mostReliable:
            return "shield.fill"
        case .fastest:
            return "bolt.fill"
        case .fewestTransfers:
            return "arrow.triangle.swap"
        case .stepFree:
            return "figure.roll"
        case .multiModalBikeRail:
            return "bicycle"
        }
    }
    
    public var subtitle: String {
        switch self {
        case .mostReliable:
            return "Minimizes delay risk & variance (P90-P10)"
        case .fastest:
            return "Earliest scheduled arrival time"
        case .fewestTransfers:
            return "Direct routes with minimum connections"
        case .stepFree:
            return "Elevators, ramps & accessible platforms"
        case .multiModalBikeRail:
            return "Combines Citi Bike/GBFS with rapid transit"
        }
    }
}

// MARK: - 3-Tier GTFS-RT Confidence

/// 3-tier GTFS-Realtime confidence indicator eliminating ghost vehicle anxiety.
public enum GTFSRealtimeConfidenceTier: String, Sendable, Equatable, Hashable {
    /// Active AVL GPS ping received within 60s. High confidence, live vehicle telemetry.
    case verified = "verified"
    /// Stale GPS ping (>60s) or schedule-interpolated. Moderate confidence.
    case estimated = "estimated"
    /// No live vehicle telemetry available. Fallback to published timetable.
    case staticSchedule = "static_schedule"
    
    public var title: String {
        switch self {
        case .verified:
            return "VERIFIED"
        case .estimated:
            return "ESTIMATED"
        case .staticSchedule:
            return "SCHEDULED"
        }
    }
    
    public var accessibilityDescription: String {
        switch self {
        case .verified:
            return "Verified live GPS tracking with active vehicle telemetry"
        case .estimated:
            return "Estimated arrival time based on recent telemetry"
        case .staticSchedule:
            return "Scheduled timetable arrival time without live vehicle tracking"
        }
    }
}

// MARK: - Leg Modes

/// Transport mode for an individual leg in a multimodal journey.
public enum LegMode: String, Sendable, Equatable, Hashable {
    case walk
    case subway
    case bus
    case lightRail
    case ferry
    case bikeShare
    case personalBike
    
    public var systemIcon: String {
        switch self {
        case .walk:
            return "figure.walk"
        case .subway:
            return "tram.fill"
        case .bus:
            return "bus.fill"
        case .lightRail:
            return "train.side.front.car"
        case .ferry:
            return "ferry.fill"
        case .bikeShare:
            return "bicycle"
        case .personalBike:
            return "bicycle"
        }
    }
    
    public var isTransit: Bool {
        switch self {
        case .subway, .bus, .lightRail, .ferry:
            return true
        case .walk, .bikeShare, .personalBike:
            return false
        }
    }
}

// MARK: - Service Disruptions

public enum DisruptionSeverity: String, Sendable, Equatable, Hashable {
    case informational
    case minorDelay
    case majorSuspension
    
    public var iconName: String {
        switch self {
        case .informational:
            return "info.circle.fill"
        case .minorDelay:
            return "exclamationmark.triangle.fill"
        case .majorSuspension:
            return "xmark.octagon.fill"
        }
    }
    
    public var accentColorHex: String {
        switch self {
        case .informational:
            return "#3B82F6"
        case .minorDelay:
            return "#FFB300" // Electric Amber
        case .majorSuspension:
            return "#EF4444"
        }
    }
}

public struct JourneyDisruption: Identifiable, Sendable, Equatable, Hashable {
    public let id: String
    public let routeId: String?
    public let affectedStopIds: [String]
    public let severity: DisruptionSeverity
    public let headline: String
    public let detailText: String
    public let isActionable: Bool
    public let rerouteSuggested: Bool
    
    public init(
        id: String = UUID().uuidString,
        routeId: String? = nil,
        affectedStopIds: [String] = [],
        severity: DisruptionSeverity = .minorDelay,
        headline: String,
        detailText: String,
        isActionable: Bool = false,
        rerouteSuggested: Bool = false
    ) {
        self.id = id
        self.routeId = routeId
        self.affectedStopIds = affectedStopIds
        self.severity = severity
        self.headline = headline
        self.detailText = detailText
        self.isActionable = isActionable
        self.rerouteSuggested = rerouteSuggested
    }
}

// MARK: - Micro-Mobility Metadata

public enum GBFSDockGatingRisk: String, Sendable, Equatable, Hashable {
    case low       // >3 docks available
    case moderate  // 1-2 docks available
    case high      // 0 docks available
    
    public var title: String {
        switch self {
        case .low:
            return "Docks Available"
        case .moderate:
            return "Limited Docks"
        case .high:
            return "Dock Starvation"
        }
    }
    
    public var badgeColor: Color {
        switch self {
        case .low:
            return Color(hex: "#10B981") // Green
        case .moderate:
            return Color(hex: "#FFB300") // Electric Amber
        case .high:
            return Color(hex: "#EF4444") // Red
        }
    }
}

public struct BikeLegMetadata: Sendable, Equatable, Hashable {
    public let originStationName: String?
    public let destinationStationName: String?
    public let availableBikesAtOrigin: Int
    public let availableDocksAtDest: Int
    public let isEBike: Bool
    public let batterySocPercent: Int?
    public let estimatedRangeMiles: Double?
    public let dockGatingRisk: GBFSDockGatingRisk
    
    public init(
        originStationName: String? = nil,
        destinationStationName: String? = nil,
        availableBikesAtOrigin: Int = 5,
        availableDocksAtDest: Int = 8,
        isEBike: Bool = true,
        batterySocPercent: Int? = 85,
        estimatedRangeMiles: Double? = 16.5,
        dockGatingRisk: GBFSDockGatingRisk = .low
    ) {
        self.originStationName = originStationName
        self.destinationStationName = destinationStationName
        self.availableBikesAtOrigin = availableBikesAtOrigin
        self.availableDocksAtDest = availableDocksAtDest
        self.isEBike = isEBike
        self.batterySocPercent = batterySocPercent
        self.estimatedRangeMiles = estimatedRangeMiles
        self.dockGatingRisk = dockGatingRisk
    }
}

// MARK: - Journey Leg

public struct JourneyLeg: Identifiable, Sendable, Equatable, Hashable {
    public let id: UUID
    public let mode: LegMode
    public let originName: String
    public let destinationName: String
    public let departureTimeSec: UInt32
    public let arrivalTimeSec: UInt32
    public let durationSec: UInt32
    public let distanceMeters: UInt32
    public let routeId: String?
    public let headsign: String?
    public let stopCount: Int?
    public let lineInfo: TransitRouteData.LineInfo?
    public let confidenceTier: GTFSRealtimeConfidenceTier
    public let disruption: JourneyDisruption?
    public let bikeMetadata: BikeLegMetadata?
    public let isTransferWalk: Bool
    public let landmarkCue: String?
    public let exitCode: String?
    public let recommendedCarPosition: String?
    
    public init(
        id: UUID = UUID(),
        mode: LegMode,
        originName: String,
        destinationName: String,
        departureTimeSec: UInt32,
        arrivalTimeSec: UInt32,
        durationSec: UInt32? = nil,
        distanceMeters: UInt32 = 0,
        routeId: String? = nil,
        headsign: String? = nil,
        stopCount: Int? = nil,
        lineInfo: TransitRouteData.LineInfo? = nil,
        confidenceTier: GTFSRealtimeConfidenceTier = .verified,
        disruption: JourneyDisruption? = nil,
        bikeMetadata: BikeLegMetadata? = nil,
        isTransferWalk: Bool = false,
        landmarkCue: String? = nil,
        exitCode: String? = nil,
        recommendedCarPosition: String? = nil
    ) {
        self.id = id
        self.mode = mode
        self.originName = originName
        self.destinationName = destinationName
        self.departureTimeSec = departureTimeSec
        self.arrivalTimeSec = arrivalTimeSec
        self.durationSec = durationSec ?? (arrivalTimeSec >= departureTimeSec ? arrivalTimeSec - departureTimeSec : 0)
        self.distanceMeters = distanceMeters
        self.routeId = routeId
        self.headsign = headsign
        self.stopCount = stopCount
        self.lineInfo = lineInfo ?? (routeId.map { TransitRouteData.lineInfo(for: $0) })
        self.confidenceTier = confidenceTier
        self.disruption = disruption
        self.bikeMetadata = bikeMetadata
        self.isTransferWalk = isTransferWalk
        self.landmarkCue = landmarkCue
        self.exitCode = exitCode
        self.recommendedCarPosition = recommendedCarPosition
    }
    
    public var formattedDuration: String {
        let minutes = Int(ceil(Double(durationSec) / 60.0))
        if minutes < 1 { return "<1m" }
        return "\(minutes)m"
    }
    
    public var formattedDistance: String {
        let miles = Double(distanceMeters) / 1609.34
        if miles < 0.1 {
            let feet = Int(Double(distanceMeters) * 3.28084)
            return "\(feet) ft"
        }
        return String(format: "%.1f mi", miles)
    }
}

// MARK: - Journey Itinerary

public struct JourneyItinerary: Identifiable, Sendable, Equatable, Hashable {
    public let id: UUID
    public let profile: RoutingProfile
    public let departureTimeSec: UInt32
    public let arrivalTimeSec: UInt32
    public let p10ArrivalSec: UInt32
    public let p50ArrivalSec: UInt32
    public let p90ArrivalSec: UInt32
    public let totalDurationSec: UInt32
    public let totalCost: Double
    public let totalDistanceMeters: UInt32
    public let walkingDurationSec: UInt32
    public let walkingDistanceMeters: UInt32
    public let bikingDurationSec: UInt32
    public let bikingDistanceMeters: UInt32
    public let transitDurationSec: UInt32
    public let transferCount: Int
    public let caloriesBurned: Int
    public let elevationGainMeters: Int
    public let legs: [JourneyLeg]
    public let disruptions: [JourneyDisruption]
    public let confidenceTier: GTFSRealtimeConfidenceTier
    
    public init(
        id: UUID = UUID(),
        profile: RoutingProfile = .mostReliable,
        departureTimeSec: UInt32,
        arrivalTimeSec: UInt32,
        p10ArrivalSec: UInt32? = nil,
        p50ArrivalSec: UInt32? = nil,
        p90ArrivalSec: UInt32? = nil,
        totalCost: Double = 2.90,
        legs: [JourneyLeg] = [],
        disruptions: [JourneyDisruption] = [],
        confidenceTier: GTFSRealtimeConfidenceTier = .verified,
        caloriesBurned: Int? = nil,
        elevationGainMeters: Int = 0
    ) {
        self.id = id
        self.profile = profile
        self.departureTimeSec = departureTimeSec
        self.arrivalTimeSec = arrivalTimeSec
        self.p50ArrivalSec = p50ArrivalSec ?? arrivalTimeSec
        self.p10ArrivalSec = p10ArrivalSec ?? (self.p50ArrivalSec > 120 ? self.p50ArrivalSec - 120 : self.p50ArrivalSec)
        self.p90ArrivalSec = p90ArrivalSec ?? (self.p50ArrivalSec + 180)
        self.totalDurationSec = arrivalTimeSec >= departureTimeSec ? (arrivalTimeSec - departureTimeSec) : 0
        self.totalCost = totalCost
        self.legs = legs
        self.disruptions = disruptions
        self.confidenceTier = confidenceTier
        self.elevationGainMeters = elevationGainMeters
        
        var walkDist: UInt32 = 0
        var walkDur: UInt32 = 0
        var bikeDist: UInt32 = 0
        var bikeDur: UInt32 = 0
        var transitDur: UInt32 = 0
        var transfers = 0
        var transitLegCount = 0
        
        for leg in legs {
            switch leg.mode {
            case .walk:
                walkDist += leg.distanceMeters
                walkDur += leg.durationSec
            case .bikeShare, .personalBike:
                bikeDist += leg.distanceMeters
                bikeDur += leg.durationSec
            case .subway, .bus, .lightRail, .ferry:
                transitDur += leg.durationSec
                transitLegCount += 1
            }
        }
        
        if transitLegCount > 1 {
            transfers = transitLegCount - 1
        }
        
        self.walkingDistanceMeters = walkDist
        self.walkingDurationSec = walkDur
        self.bikingDistanceMeters = bikeDist
        self.bikingDurationSec = bikeDur
        self.transitDurationSec = transitDur
        self.totalDistanceMeters = walkDist + bikeDist
        self.transferCount = transfers
        
        if let cal = caloriesBurned {
            self.caloriesBurned = cal
        } else {
            // Rough estimation: 65 kcal per km walking, 35 kcal per km cycling
            let walkKm = Double(walkDist) / 1000.0
            let bikeKm = Double(bikeDist) / 1000.0
            self.caloriesBurned = Int(walkKm * 65.0 + bikeKm * 35.0)
        }
    }
    
    // MARK: - Formatting Helpers
    
    public var formattedDepartureTime: String {
        Self.formatSecondsToClock(departureTimeSec)
    }
    
    public var formattedArrivalTime: String {
        Self.formatSecondsToClock(arrivalTimeSec)
    }
    
    public var formattedDuration: String {
        let minutes = Int(ceil(Double(totalDurationSec) / 60.0))
        return "\(minutes) min"
    }
    
    public var formattedCost: String {
        if totalCost <= 0.0 {
            return "Free"
        }
        return String(format: "$%.2f", totalCost)
    }
    
    public var formattedWalkingDistance: String {
        let miles = Double(walkingDistanceMeters) / 1609.34
        if miles < 0.1 {
            let feet = Int(Double(walkingDistanceMeters) * 3.28084)
            return "\(feet) ft"
        }
        return String(format: "%.1f mi", miles)
    }
    
    public var formattedBikingDistance: String {
        let miles = Double(bikingDistanceMeters) / 1609.34
        return String(format: "%.1f mi", miles)
    }
    
    /// Formatted P10-P90 confidence interval string, e.g. "8:42 – 8:46 AM (±2m)"
    public var formattedConfidenceInterval: String {
        let p10Str = Self.formatSecondsToClock(p10ArrivalSec)
        let p90Str = Self.formatSecondsToClock(p90ArrivalSec)
        
        let uncertaintySec = p90ArrivalSec > p10ArrivalSec ? (p90ArrivalSec - p10ArrivalSec) : 0
        let deltaMin = max(1, Int(round(Double(uncertaintySec) / 120.0)))
        
        if p10Str == p90Str {
            return p10Str
        }
        return "\(p10Str) – \(p90Str) (±\(deltaMin)m)"
    }
    
    /// Uncertainty spread in minutes (P90 - P10)
    public var uncertaintyMinutes: Int {
        let diff = p90ArrivalSec >= p10ArrivalSec ? (p90ArrivalSec - p10ArrivalSec) : 0
        return Int(ceil(Double(diff) / 60.0))
    }
    
    public var transferSummary: String {
        if transferCount == 0 {
            return "Direct"
        } else if transferCount == 1 {
            return "1 transfer"
        } else {
            return "\(transferCount) transfers"
        }
    }
    
    public var voiceOverSummary: String {
        var summary = "\(profile.displayName) route. Depart at \(formattedDepartureTime), arriving between \(Self.formatSecondsToClock(p10ArrivalSec)) and \(Self.formatSecondsToClock(p90ArrivalSec)). "
        summary += "Total travel time \(formattedDuration). \(transferSummary). Fare \(formattedCost). "
        summary += "\(confidenceTier.accessibilityDescription). "
        if !disruptions.isEmpty {
            summary += "Warning: \(disruptions.count) active disruption alerts on this route."
        }
        return summary
    }
    
    // MARK: - Internal Clock Formatter
    
    public static func formatSecondsToClock(_ secondsSinceMidnight: UInt32) -> String {
        let normalized = secondsSinceMidnight % 86400
        let totalMinutes = normalized / 60
        let hour24 = Int(totalMinutes / 60)
        let minute = Int(totalMinutes % 60)
        
        let period = hour24 >= 12 ? "PM" : "AM"
        let hour12 = hour24 == 0 ? 12 : (hour24 > 12 ? hour24 - 12 : hour24)
        
        return String(format: "%d:%02d %@", hour12, minute, period)
    }
}
