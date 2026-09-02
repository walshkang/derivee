import Foundation
import CoreLocation
import SwiftUI

// MARK: - Track Stop Model

/// Represents a single station node along the route progression ladder in the Track Thermometer.
public struct TrackStop: Identifiable, Sendable, Equatable, Hashable {
    public let id: String
    public let stopId: String
    public let stopName: String
    public let coordinate: CLLocationCoordinate2D
    public let sequenceIndex: Int
    public let isPassed: Bool
    public let isCurrent: Bool
    public let isTerminus: Bool
    public let estimatedMinutes: Int?
    public let transferRoutes: [String]
    
    public init(
        id: String? = nil,
        stopId: String,
        stopName: String,
        coordinate: CLLocationCoordinate2D,
        sequenceIndex: Int,
        isPassed: Bool = false,
        isCurrent: Bool = false,
        isTerminus: Bool = false,
        estimatedMinutes: Int? = nil,
        transferRoutes: [String] = []
    ) {
        self.id = id ?? "\(stopId)_\(sequenceIndex)"
        self.stopId = stopId
        self.stopName = stopName
        self.coordinate = coordinate
        self.sequenceIndex = sequenceIndex
        self.isPassed = isPassed
        self.isCurrent = isCurrent
        self.isTerminus = isTerminus
        self.estimatedMinutes = estimatedMinutes
        self.transferRoutes = transferRoutes
    }
    
    public static func == (lhs: TrackStop, rhs: TrackStop) -> Bool {
        lhs.id == rhs.id &&
        lhs.stopId == rhs.stopId &&
        lhs.sequenceIndex == rhs.sequenceIndex &&
        lhs.isPassed == rhs.isPassed &&
        lhs.isCurrent == rhs.isCurrent &&
        lhs.isTerminus == rhs.isTerminus &&
        lhs.estimatedMinutes == rhs.estimatedMinutes &&
        lhs.transferRoutes == rhs.transferRoutes
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(stopId)
        hasher.combine(sequenceIndex)
        hasher.combine(isPassed)
        hasher.combine(isCurrent)
        hasher.combine(isTerminus)
        hasher.combine(estimatedMinutes)
    }
}

// MARK: - Train Vehicle Telemetry Model

/// Live vehicle position and telemetry for an active train run.
public struct TrainVehicleTelemetry: Sendable, Equatable {
    public let vehicleId: String
    public let currentStatus: VehicleStatus
    public let currentStopId: String?
    public let currentStopSequence: Int?
    public let coordinate: CLLocationCoordinate2D?
    public let bearing: Float?
    public let occupancyStatus: VehicleOccupancyStatus?
    public let occupancyPercentage: Int?
    
    public enum VehicleStatus: String, Sendable {
        case incomingAt = "Approaching"
        case stoppedAt = "Dwelling at Platform"
        case inTransitTo = "In Transit"
        case unknown = "Active"
    }
    
    public init(
        vehicleId: String,
        currentStatus: VehicleStatus = .inTransitTo,
        currentStopId: String? = nil,
        currentStopSequence: Int? = nil,
        coordinate: CLLocationCoordinate2D? = nil,
        bearing: Float? = nil,
        occupancyStatus: VehicleOccupancyStatus? = nil,
        occupancyPercentage: Int? = nil
    ) {
        self.vehicleId = vehicleId
        self.currentStatus = currentStatus
        self.currentStopId = currentStopId
        self.currentStopSequence = currentStopSequence
        self.coordinate = coordinate
        self.bearing = bearing
        self.occupancyStatus = occupancyStatus
        self.occupancyPercentage = occupancyPercentage
    }
    
    public static func == (lhs: TrainVehicleTelemetry, rhs: TrainVehicleTelemetry) -> Bool {
        lhs.vehicleId == rhs.vehicleId &&
        lhs.currentStatus == rhs.currentStatus &&
        lhs.currentStopId == rhs.currentStopId &&
        lhs.currentStopSequence == rhs.currentStopSequence &&
        lhs.bearing == rhs.bearing &&
        lhs.occupancyStatus == rhs.occupancyStatus &&
        lhs.occupancyPercentage == rhs.occupancyPercentage &&
        lhs.coordinate?.latitude == rhs.coordinate?.latitude &&
        lhs.coordinate?.longitude == rhs.coordinate?.longitude
    }
}

// MARK: - Crowd Density & Occupancy Estimate

/// Harmonized passenger occupancy representation bridging live GTFS-RT sensors and diurnal crowd fallbacks.
public struct CrowdDensityEstimate: Sendable, Equatable {
    public let level: CrowdLevel
    public let isLiveSensors: Bool
    public let badgeTitle: String
    public let detailDescription: String
    public let carriageLoads: [Double] // 0.0 .. 1.0 load per train car
    
    public enum CrowdLevel: String, Sendable, CaseIterable {
        case light = "LIGHT"
        case moderate = "MODERATE"
        case crowded = "CROWDED"
        case full = "FULL"
        
        public var title: String {
            switch self {
            case .light: return "Many Seats Available"
            case .moderate: return "Seats Filling Fast"
            case .crowded: return "Standing Room Only"
            case .full: return "Crowded / High Capacity"
            }
        }
        
        public var statusColor: Color {
            switch self {
            case .light: return Color(hex: "#10B981")    // Emerald
            case .moderate: return Color(hex: "#F59E0B") // Amber
            case .crowded: return Color(hex: "#EA580C")  // Deep Amber / Orange
            case .full: return Color(hex: "#EF4444")     // Red / Rose
            }
        }
    }
    
    public init(
        level: CrowdLevel,
        isLiveSensors: Bool,
        badgeTitle: String? = nil,
        detailDescription: String? = nil,
        carriageLoads: [Double]? = nil
    ) {
        self.level = level
        self.isLiveSensors = isLiveSensors
        self.badgeTitle = badgeTitle ?? (isLiveSensors ? "LIVE AVL OCCUPANCY" : "HISTORICAL CROWD ESTIMATE")
        
        if let detail = detailDescription {
            self.detailDescription = detail
        } else {
            self.detailDescription = isLiveSensors
                ? "Reported in real-time from vehicle weight sensors."
                : "Estimated from historical 15-minute slot passenger volume."
        }
        
        if let loads = carriageLoads {
            self.carriageLoads = loads
        } else {
            // Default 8-car train distribution
            switch level {
            case .light:
                self.carriageLoads = [0.20, 0.25, 0.30, 0.35, 0.35, 0.30, 0.25, 0.20]
            case .moderate:
                self.carriageLoads = [0.45, 0.55, 0.65, 0.70, 0.70, 0.65, 0.55, 0.45]
            case .crowded:
                self.carriageLoads = [0.70, 0.85, 0.90, 0.95, 0.95, 0.90, 0.85, 0.70]
            case .full:
                self.carriageLoads = [0.90, 0.95, 1.00, 1.00, 1.00, 1.00, 0.95, 0.90]
            }
        }
    }
    
    /// Resolves occupancy from GTFS-RT status or evaluates diurnal rush-hour heuristic.
    public static func resolve(
        gtfsOccupancy: VehicleOccupancyStatus?,
        occupancyPercentage: Int? = nil,
        date: Date = Date()
    ) -> CrowdDensityEstimate {
        if let live = gtfsOccupancy, live != .noDataAvailable {
            let level: CrowdLevel
            switch live {
            case .empty, .manySeatsAvailable:
                level = .light
            case .fewSeatsAvailable:
                level = .moderate
            case .standingRoomOnly:
                level = .crowded
            case .crushedStandingRoomOnly, .full, .notAcceptingPassengers, .notBoardable:
                level = .full
            case .noDataAvailable:
                level = .moderate
            }
            
            // If percentage is provided, synthesize carriage variations around the mean
            let mean = Double(occupancyPercentage ?? (level == .light ? 25 : (level == .moderate ? 60 : (level == .crowded ? 85 : 95)))) / 100.0
            let loads: [Double] = [
                max(0.1, mean * 0.80),
                max(0.1, mean * 0.95),
                min(1.0, mean * 1.05),
                min(1.0, mean * 1.10),
                min(1.0, mean * 1.10),
                min(1.0, mean * 1.05),
                max(0.1, mean * 0.95),
                max(0.1, mean * 0.80)
            ]
            
            return CrowdDensityEstimate(level: level, isLiveSensors: true, carriageLoads: loads)
        }
        
        // Diurnal Statistical Fallback based on hour of day & day of week
        let cal = Calendar.current
        let hour = cal.component(.hour, from: date)
        let minute = cal.component(.minute, from: date)
        let timeMinutes = hour * 60 + minute
        let isWeekend = cal.isDateInWeekend(date)
        
        let level: CrowdLevel
        if !isWeekend {
            // Weekday Peak Windows: 07:30–09:30 (450..570) & 16:30–18:45 (990..1125)
            if (timeMinutes >= 450 && timeMinutes <= 570) || (timeMinutes >= 990 && timeMinutes <= 1125) {
                level = .crowded
            } else if (timeMinutes >= 420 && timeMinutes <= 630) || (timeMinutes >= 930 && timeMinutes <= 1170) {
                level = .moderate
            } else if timeMinutes >= 60 && timeMinutes <= 360 { // Late night
                level = .light
            } else {
                level = .moderate
            }
        } else {
            // Weekend: midday busy 11:30–18:00
            if timeMinutes >= 690 && timeMinutes <= 1080 {
                level = .moderate
            } else {
                level = .light
            }
        }
        
        return CrowdDensityEstimate(level: level, isLiveSensors: false)
    }
}
