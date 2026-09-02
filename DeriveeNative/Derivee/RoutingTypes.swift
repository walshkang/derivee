import Foundation
import CoreLocation

// MARK: - Routing Location

/// Represents a query endpoint—either a geographic coordinate or a discrete transit stop.
public enum RoutingLocation: Sendable, Equatable, Hashable {
    case coordinate(latitude: Double, longitude: Double, name: String? = nil)
    case stop(stopId: UInt32, name: String? = nil)
    
    public var displayName: String {
        switch self {
        case .coordinate(_, _, let name):
            return name ?? "Pinned Location"
        case .stop(let stopId, let name):
            return name ?? "Stop #\(stopId)"
        }
    }
    
    public var coordinate: (latitude: Double, longitude: Double)? {
        switch self {
        case .coordinate(let lat, let lon, _):
            return (lat, lon)
        case .stop:
            return nil
        }
    }
    
    public var stopId: UInt32? {
        switch self {
        case .stop(let id, _):
            return id
        case .coordinate:
            return nil
        }
    }
}

// MARK: - Routing Options

/// Configuration parameters governing RAPTOR and Range-RAPTOR pathfinding execution.
public struct RoutingOptions: Sendable, Equatable {
    public var maxTransfers: UInt16
    public var departureWindowSeconds: UInt32
    public var maxWalkDistanceMeters: UInt32
    public var walkingSpeedMps: Double
    public var flags: UInt16
    public var includeDirectWalk: Bool
    public var stochasticHorizonSeconds: UInt32
    public var samplingStepSeconds: UInt32
    public var maxCandidateStops: Int
    
    public init(
        maxTransfers: UInt16 = 4,
        departureWindowSeconds: UInt32 = 3600, // 60 min Range-RAPTOR sweep
        maxWalkDistanceMeters: UInt32 = 1000,
        walkingSpeedMps: Double = 1.3,
        flags: UInt16 = 0,
        includeDirectWalk: Bool = true,
        stochasticHorizonSeconds: UInt32 = 2700, // 45 min
        samplingStepSeconds: UInt32 = 60,
        maxCandidateStops: Int = 8
    ) {
        self.maxTransfers = maxTransfers
        self.departureWindowSeconds = departureWindowSeconds
        self.maxWalkDistanceMeters = maxWalkDistanceMeters
        self.walkingSpeedMps = walkingSpeedMps
        self.flags = flags
        self.includeDirectWalk = includeDirectWalk
        self.stochasticHorizonSeconds = stochasticHorizonSeconds
        self.samplingStepSeconds = samplingStepSeconds
        self.maxCandidateStops = maxCandidateStops
    }
    
    public static let `default` = RoutingOptions()
    
    public static let wheelchairAccessible = RoutingOptions(
        maxWalkDistanceMeters: 800,
        walkingSpeedMps: 1.1,
        flags: 1 << 0 // ROUTING_FLAG_WHEELCHAIR_ACCESSIBLE
    )
}

// MARK: - Stop Metadata Provider Protocol

/// Interface for enriching raw stop IDs with human-readable titles, egress exit codes, and landmark cues.
public protocol StopMetadataProvider: Sendable {
    func stopName(for stopId: UInt32) -> String?
    func stopCoordinate(for stopId: UInt32) -> (latitude: Double, longitude: Double)?
    func exitCode(for stopId: UInt32) -> String?
    func landmarkCue(for stopId: UInt32) -> String?
    func routeName(for routeId: UInt16) -> String?
}

// MARK: - Default Stop Metadata Provider

public struct DefaultStopMetadataProvider: StopMetadataProvider {
    public let stopNames: [UInt32: String]
    public let stopCoordinates: [UInt32: (latitude: Double, longitude: Double)]
    public let exitCodes: [UInt32: String]
    public let landmarkCues: [UInt32: String]
    public let routeNames: [UInt16: String]
    
    public init(
        stopNames: [UInt32: String] = [:],
        stopCoordinates: [UInt32: (latitude: Double, longitude: Double)] = [:],
        exitCodes: [UInt32: String] = [:],
        landmarkCues: [UInt32: String] = [:],
        routeNames: [UInt16: String] = [:]
    ) {
        self.stopNames = stopNames
        self.stopCoordinates = stopCoordinates
        self.exitCodes = exitCodes
        self.landmarkCues = landmarkCues
        self.routeNames = routeNames
    }
    
    public func stopName(for stopId: UInt32) -> String? {
        stopNames[stopId] ?? "Stop #\(stopId)"
    }
    
    public func stopCoordinate(for stopId: UInt32) -> (latitude: Double, longitude: Double)? {
        stopCoordinates[stopId]
    }
    
    public func exitCode(for stopId: UInt32) -> String? {
        exitCodes[stopId]
    }
    
    public func landmarkCue(for stopId: UInt32) -> String? {
        landmarkCues[stopId]
    }
    
    public func routeName(for routeId: UInt16) -> String? {
        routeNames[routeId] ?? "\(routeId)"
    }
}
