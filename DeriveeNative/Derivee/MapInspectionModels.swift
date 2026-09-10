import Foundation
import CoreLocation
import UIKit

/// Encapsulates closure-based map synchronization commands dispatched when a transit run inspector opens.
/// Formatted according to design.md §10.5.2 & §10.6.1 for Layer 4 Ephemeral Route Inspection.
public struct RouteInspectionCommand: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let routeId: String
    public let lineName: String
    public let agencyColorHex: String
    public let casingColorHex: String
    public let modalClass: TransitModalClass
    public let coordinates: [CLLocationCoordinate2D]
    public let stationCoordinate: CLLocationCoordinate2D
    public let shouldFrameCamera: Bool
    
    public init(
        id: UUID = UUID(),
        routeId: String,
        lineName: String,
        agencyColorHex: String,
        casingColorHex: String = "#FFFFFF",
        modalClass: TransitModalClass,
        coordinates: [CLLocationCoordinate2D],
        stationCoordinate: CLLocationCoordinate2D,
        shouldFrameCamera: Bool = true
    ) {
        self.id = id
        self.routeId = routeId
        self.lineName = lineName
        self.agencyColorHex = agencyColorHex
        self.casingColorHex = casingColorHex
        self.modalClass = modalClass
        self.coordinates = coordinates
        self.stationCoordinate = stationCoordinate
        self.shouldFrameCamera = shouldFrameCamera
    }
    
    /// Official primary line stroke color (4px).
    public var agencyColor: UIColor {
        UIColor(hex: agencyColorHex)
    }
    
    /// High-contrast dual-layer casing color (6px).
    public var casingColor: UIColor {
        UIColor(hex: casingColorHex)
    }
    
    /// Maritime Ferries render with a dashed line pattern (`[4.0, 3.0]`) per design.md §10.6.1.
    public var isDashed: Bool {
        modalClass == .ferry
    }
    
    /// Computes southwest and northeast bounds enclosing all route coordinates and the user's station.
    public func computedBoundingBox() -> (sw: CLLocationCoordinate2D, ne: CLLocationCoordinate2D)? {
        var allPoints = coordinates
        allPoints.append(stationCoordinate)
        
        guard let first = allPoints.first else { return nil }
        
        var minLat = first.latitude
        var maxLat = first.latitude
        var minLon = first.longitude
        var maxLon = first.longitude
        
        for pt in allPoints {
            minLat = min(minLat, pt.latitude)
            maxLat = max(maxLat, pt.latitude)
            minLon = min(minLon, pt.longitude)
            maxLon = max(maxLon, pt.longitude)
        }
        
        // Ensure a minimum span to prevent excessive zooming on single-point routes
        let minSpan = 0.008
        if (maxLat - minLat) < minSpan {
            let mid = (maxLat + minLat) / 2.0
            minLat = mid - minSpan / 2.0
            maxLat = mid + minSpan / 2.0
        }
        if (maxLon - minLon) < minSpan {
            let mid = (maxLon + minLon) / 2.0
            minLon = mid - minSpan / 2.0
            maxLon = mid + minSpan / 2.0
        }
        
        return (
            sw: CLLocationCoordinate2D(latitude: minLat, longitude: minLon),
            ne: CLLocationCoordinate2D(latitude: maxLat, longitude: maxLon)
        )
    }
    
    public static func == (lhs: RouteInspectionCommand, rhs: RouteInspectionCommand) -> Bool {
        guard lhs.id == rhs.id &&
              lhs.routeId == rhs.routeId &&
              lhs.lineName == rhs.lineName &&
              lhs.agencyColorHex == rhs.agencyColorHex &&
              lhs.casingColorHex == rhs.casingColorHex &&
              lhs.modalClass == rhs.modalClass &&
              lhs.shouldFrameCamera == rhs.shouldFrameCamera &&
              abs(lhs.stationCoordinate.latitude - rhs.stationCoordinate.latitude) < 0.00001 &&
              abs(lhs.stationCoordinate.longitude - rhs.stationCoordinate.longitude) < 0.00001 &&
              lhs.coordinates.count == rhs.coordinates.count else {
            return false
        }
        
        for i in 0..<lhs.coordinates.count {
            if abs(lhs.coordinates[i].latitude - rhs.coordinates[i].latitude) > 0.00001 ||
               abs(lhs.coordinates[i].longitude - rhs.coordinates[i].longitude) > 0.00001 {
                return false
            }
        }
        return true
    }
}

// MARK: - Wave R.3: Corridor Pulse Telemetry Models (Research Doc 19 §5)

/// Real-time vehicle telemetry model for Corridor Pulse dynamic map visualization (Research Doc 19 §5).
public struct CorridorVehicleTelemetry: Identifiable, Sendable, Equatable {
    public let id: String
    public let vehicleId: String
    public let tripId: String
    public let routeId: String
    public let coordinate: CLLocationCoordinate2D
    public let bearing: Double
    public let speedMps: Double
    public let delaySec: Int
    public let isTarget: Bool
    public let isBunched: Bool
    public let isServiceGap: Bool
    public let statusColorHex: String
    public let haloColorHex: String
    
    public init(
        vehicleId: String,
        tripId: String,
        routeId: String,
        coordinate: CLLocationCoordinate2D,
        bearing: Double = 0.0,
        speedMps: Double = 0.0,
        delaySec: Int = 0,
        isTarget: Bool = false,
        isBunched: Bool = false,
        isServiceGap: Bool = false,
        statusColorHex: String = "#388E3C",
        haloColorHex: String = "#C8E6C9"
    ) {
        self.id = vehicleId
        self.vehicleId = vehicleId
        self.tripId = tripId
        self.routeId = routeId
        self.coordinate = coordinate
        self.bearing = bearing
        self.speedMps = speedMps
        self.delaySec = delaySec
        self.isTarget = isTarget
        self.isBunched = isBunched
        self.isServiceGap = isServiceGap
        self.statusColorHex = statusColorHex
        self.haloColorHex = haloColorHex
    }
    
    public static func == (lhs: CorridorVehicleTelemetry, rhs: CorridorVehicleTelemetry) -> Bool {
        return lhs.vehicleId == rhs.vehicleId &&
               lhs.tripId == rhs.tripId &&
               lhs.routeId == rhs.routeId &&
               abs(lhs.coordinate.latitude - rhs.coordinate.latitude) < 0.00001 &&
               abs(lhs.coordinate.longitude - rhs.coordinate.longitude) < 0.00001 &&
               abs(lhs.bearing - rhs.bearing) < 0.1 &&
               lhs.isTarget == rhs.isTarget &&
               lhs.isBunched == rhs.isBunched &&
               lhs.isServiceGap == rhs.isServiceGap &&
               lhs.statusColorHex == rhs.statusColorHex &&
               lhs.haloColorHex == rhs.haloColorHex
    }
}

/// Platooning / bunching corridor segment telemetry for MapLibre dynamic lines (Research Doc 19 §5).
public struct CorridorBunchingSegmentTelemetry: Identifiable, Sendable, Equatable {
    public let id: String
    public let trailingVehicleId: String
    public let leadingVehicleId: String
    public let coordinates: [CLLocationCoordinate2D]
    public let lineColorHex: String
    public let casingColorHex: String
    public let severity: String
    public let segmentLengthM: Double
    public let compressionRatio: Double
    
    public init(
        id: String = UUID().uuidString,
        trailingVehicleId: String,
        leadingVehicleId: String,
        coordinates: [CLLocationCoordinate2D],
        lineColorHex: String = "#B71C1C",
        casingColorHex: String = "#FFEBEE",
        severity: String = "critical",
        segmentLengthM: Double = 0.0,
        compressionRatio: Double = 0.0
    ) {
        self.id = id
        self.trailingVehicleId = trailingVehicleId
        self.leadingVehicleId = leadingVehicleId
        self.coordinates = coordinates
        self.lineColorHex = lineColorHex
        self.casingColorHex = casingColorHex
        self.severity = severity
        self.segmentLengthM = segmentLengthM
        self.compressionRatio = compressionRatio
    }
    
    public static func == (lhs: CorridorBunchingSegmentTelemetry, rhs: CorridorBunchingSegmentTelemetry) -> Bool {
        guard lhs.id == rhs.id &&
              lhs.trailingVehicleId == rhs.trailingVehicleId &&
              lhs.leadingVehicleId == rhs.leadingVehicleId &&
              lhs.lineColorHex == rhs.lineColorHex &&
              lhs.casingColorHex == rhs.casingColorHex &&
              lhs.severity == rhs.severity &&
              lhs.coordinates.count == rhs.coordinates.count else {
            return false
        }
        for i in 0..<lhs.coordinates.count {
            if abs(lhs.coordinates[i].latitude - rhs.coordinates[i].latitude) > 0.00001 ||
               abs(lhs.coordinates[i].longitude - rhs.coordinates[i].longitude) > 0.00001 {
                return false
            }
        }
        return true
    }
}

