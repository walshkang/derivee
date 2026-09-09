import Foundation
import CoreLocation

// MARK: - Station Complex Domain Models (Doc 15 & 16)

/// Top-level physical station complex (e.g. Penn Station, Grand Central, Union Square).
/// Unifies historically fragmented stations across transit modes and operating divisions.
public struct StationComplex: Identifiable, Sendable, Equatable, Hashable {
    public let id: Int64                  // complex_id
    public let name: String               // complex_name
    public let borough: String?           // borough (e.g. "Manhattan", "Brooklyn")
    public let coordinate: CLLocationCoordinate2D
    public let isHub: Bool                // Regional mega-hub indicator
    
    public init(
        id: Int64,
        name: String,
        borough: String? = nil,
        coordinate: CLLocationCoordinate2D,
        isHub: Bool = false
    ) {
        self.id = id
        self.name = name
        self.borough = borough
        self.coordinate = coordinate
        self.isHub = isHub
    }
    
    public static func == (lhs: StationComplex, rhs: StationComplex) -> Bool {
        lhs.id == rhs.id &&
        lhs.name == rhs.name &&
        lhs.borough == rhs.borough &&
        lhs.isHub == rhs.isHub &&
        abs(lhs.coordinate.latitude - rhs.coordinate.latitude) < 0.000001 &&
        abs(lhs.coordinate.longitude - rhs.coordinate.longitude) < 0.000001
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

/// Clustered multi-tier topological stop resolution mapping.
/// Resolves complex_id -> feed_id -> parent_station_id -> child_stop_id.
public struct ResolvedStop: Sendable, Equatable, Hashable {
    public let complexId: Int64
    public let feedId: String
    public let parentStationId: String
    public let childStopId: String
    public let platformCode: String?
    public let directionId: Int?
    public let wheelchairBoarding: Int
    
    public init(
        complexId: Int64,
        feedId: String,
        parentStationId: String,
        childStopId: String,
        platformCode: String? = nil,
        directionId: Int? = nil,
        wheelchairBoarding: Int = 0
    ) {
        self.complexId = complexId
        self.feedId = feedId
        self.parentStationId = parentStationId
        self.childStopId = childStopId
        self.platformCode = platformCode
        self.directionId = directionId
        self.wheelchairBoarding = wheelchairBoarding
    }
}

// MARK: - Regional Mega-Hub Anchors (Doc 16 §1 & §5)

public enum RegionalHubAnchor {
    /// Penn Station / Moynihan Train Hall Complex (600001)
    public static let pennStation: Int64 = 600001
    
    /// Grand Central Terminal Complex (600002)
    public static let grandCentral: Int64 = 600002
    
    /// Atlantic Avenue - Barclays Center Complex (600003)
    public static let atlanticAve: Int64 = 600003
    
    /// All regional hub anchor IDs
    public static let allHubIDs: Set<Int64> = [pennStation, grandCentral, atlanticAve]
    
    /// Checks if a given complex ID is a regional hub anchor
    public static func isRegionalHub(_ complexId: Int64) -> Bool {
        allHubIDs.contains(complexId)
    }
}
