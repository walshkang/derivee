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
