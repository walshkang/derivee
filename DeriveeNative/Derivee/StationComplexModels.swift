import Foundation
import CoreLocation
import GRDB

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

// MARK: - Clustered Real-Time Departures Domain Models (Doc 16 §2 & §3)

/// Clustered real-time departure record materialized in `realtime_departures` table (WITHOUT ROWID).
/// Eliminates runtime joins and `USE TEMP B-TREE FOR ORDER BY`, serving complex departures in 40–70µs.
public struct ComplexDeparture: FetchableRecord, PersistableRecord, Identifiable, Sendable, Equatable, Hashable {
    public var id: String { "\(complexId)_\(departureTime)_\(feedId)_\(childStopId)_\(tripId)" }
    public let complexId: Int64
    public let departureTime: Int64
    public let feedId: String
    public let parentStationId: String
    public let childStopId: String
    public let tripId: String
    public let routeId: String
    public let routeShortName: String
    public let directionId: Int
    public let dynamicTerminalStopId: String
    public let dynamicTerminalName: String
    public let isExpress: Bool
    public let track: String
    public let updatedAt: Int64
    
    public init(
        complexId: Int64,
        departureTime: Int64,
        feedId: String,
        parentStationId: String,
        childStopId: String,
        tripId: String,
        routeId: String,
        routeShortName: String,
        directionId: Int,
        dynamicTerminalStopId: String = "",
        dynamicTerminalName: String = "",
        isExpress: Bool = false,
        track: String = "",
        updatedAt: Int64 = 0
    ) {
        self.complexId = complexId
        self.departureTime = departureTime
        self.feedId = feedId
        self.parentStationId = parentStationId
        self.childStopId = childStopId
        self.tripId = tripId
        self.routeId = routeId
        self.routeShortName = routeShortName
        self.directionId = directionId
        self.dynamicTerminalStopId = dynamicTerminalStopId
        self.dynamicTerminalName = dynamicTerminalName
        self.isExpress = isExpress
        self.track = track
        self.updatedAt = updatedAt
    }
    
    /// Zero-overhead positional index mapping directly from SQLite row buffer (Doc 16 §3).
    public init(row: Row) {
        self.complexId              = row[0]
        self.departureTime          = row[1]
        self.feedId                 = row[2]
        self.parentStationId        = row[3]
        self.childStopId            = row[4]
        self.tripId                 = row[5]
        self.routeId                = row[6]
        self.routeShortName         = row[7]
        self.directionId            = row[8]
        self.dynamicTerminalStopId  = row[9]
        self.dynamicTerminalName    = row[10]
        self.isExpress              = (row[11] as Int) != 0
        self.track                  = row[12]
        self.updatedAt              = row.count > 13 ? (row[13] as Int64? ?? 0) : 0
    }
    
    public func encode(to container: inout PersistenceContainer) {
        container["complex_id"] = complexId
        container["departure_time"] = departureTime
        container["feed_id"] = feedId
        container["parent_station_id"] = parentStationId
        container["child_stop_id"] = childStopId
        container["trip_id"] = tripId
        container["route_id"] = routeId
        container["route_short_name"] = routeShortName
        container["direction_id"] = directionId
        container["dynamic_terminal_stop_id"] = dynamicTerminalStopId
        container["dynamic_terminal_name"] = dynamicTerminalName
        container["is_express"] = isExpress ? 1 : 0
        container["scheduled_track"] = track.isEmpty ? nil : track
        container["actual_track"] = track.isEmpty ? nil : track
        container["updated_at"] = updatedAt
    }
}


/// Unified serving route resolution for a station complex across all constituent lines (Doc 16 §3).
public struct ComplexServingRoute: FetchableRecord, Sendable, Equatable, Hashable, Identifiable {
    public var id: String { "\(feedId)_\(routeId)" }
    public let feedId: String
    public let routeId: String
    public let routeShortName: String
    
    public init(feedId: String, routeId: String, routeShortName: String) {
        self.feedId = feedId
        self.routeId = routeId
        self.routeShortName = routeShortName
    }
    
    public init(row: Row) {
        self.feedId         = row[0]
        self.routeId        = row[1]
        self.routeShortName = row[2]
    }
}

