import Foundation
import CoreLocation
import UIKit

/// 3-State Camera Mode for Proximity-Adaptive Viewport (Wave Pre-T.7 / WPT7).
/// Replaces unconditional midpoint framing with proximity-adaptive visual horizons.
public enum InspectionCameraMode: Sendable, Equatable {
    /// Track distance D <= 2.5 km (or <= 4 min): Upper viewport frames both station and oncoming consist
    /// with dynamic zoom clamp z in [13.8, 15.5] and asymmetric bottom padding H_sheet + 24pt.
    case dualFraming(trackDistanceMeters: Double)
    
    /// Track distance D > 2.5 km (or > 4 min): Camera defaults to street-level tracking of the consist
    /// at z = 15.2 centered in the upper viewport above the bottom sheet.
    case vehicleTracking(trackDistanceMeters: Double)
    
    /// Scheduled departure or missing telemetry / vehicle at platform: Anchored to station platform at z = 15.5.
    case stationAnchor
}

/// Encapsulates positional and navigational metadata for an off-screen transit consist (Pre-T.7).
/// Pinned to visible map perimeter along track bearing when vehicle is outside viewport.
public struct OffScreenBeaconState: Equatable, Sendable {
    public let routeId: String
    public let routeColorHex: String
    public let stopsAway: Int
    public let minutes: Int
    public let screenPosition: CGPoint
    public let bearingRadians: Double
    public let vehicleCoordinate: CLLocationCoordinate2D
    
    public init(
        routeId: String,
        routeColorHex: String,
        stopsAway: Int,
        minutes: Int,
        screenPosition: CGPoint,
        bearingRadians: Double,
        vehicleCoordinate: CLLocationCoordinate2D
    ) {
        self.routeId = routeId
        self.routeColorHex = routeColorHex
        self.stopsAway = stopsAway
        self.minutes = minutes
        self.screenPosition = screenPosition
        self.bearingRadians = bearingRadians
        self.vehicleCoordinate = vehicleCoordinate
    }
    
    public static func == (lhs: OffScreenBeaconState, rhs: OffScreenBeaconState) -> Bool {
        return lhs.routeId == rhs.routeId &&
               lhs.routeColorHex == rhs.routeColorHex &&
               lhs.stopsAway == rhs.stopsAway &&
               lhs.minutes == rhs.minutes &&
               lhs.screenPosition == rhs.screenPosition &&
               abs(lhs.bearingRadians - rhs.bearingRadians) < 0.001 &&
               abs(lhs.vehicleCoordinate.latitude - rhs.vehicleCoordinate.latitude) < 0.00001 &&
               abs(lhs.vehicleCoordinate.longitude - rhs.vehicleCoordinate.longitude) < 0.00001
    }
}

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
    public let vehicleCoordinate: CLLocationCoordinate2D?
    public let vehicleBearing: Double?
    public let vehicleStatus: String?
    public let stopsAway: Int?
    public let minutes: Int?
    
    public init(
        id: UUID = UUID(),
        routeId: String,
        lineName: String,
        agencyColorHex: String,
        casingColorHex: String? = nil,
        modalClass: TransitModalClass,
        coordinates: [CLLocationCoordinate2D],
        stationCoordinate: CLLocationCoordinate2D,
        shouldFrameCamera: Bool = true,
        vehicleCoordinate: CLLocationCoordinate2D? = nil,
        vehicleBearing: Double? = nil,
        vehicleStatus: String? = nil,
        stopsAway: Int? = nil,
        minutes: Int? = nil
    ) {
        self.id = id
        self.routeId = routeId
        self.lineName = lineName
        self.agencyColorHex = agencyColorHex
        self.casingColorHex = casingColorHex ?? TransitRouteData.adaptiveCasingColor(for: agencyColorHex, theme: .day)
        self.modalClass = modalClass
        self.coordinates = coordinates
        self.stationCoordinate = stationCoordinate
        self.shouldFrameCamera = shouldFrameCamera
        self.vehicleCoordinate = vehicleCoordinate
        self.vehicleBearing = vehicleBearing
        self.vehicleStatus = vehicleStatus
        self.stopsAway = stopsAway
        self.minutes = minutes
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
    
    /// Computes southwest and northeast bounds enclosing the route inspection geometry.
    /// When `tightVehicleBounding` is true and `vehicleCoordinate` is available, calculates a tight
    /// bounding box enclosing the commuter station, the live vehicle, and intermediate route curvature.
    /// Camera Safety Invariant (Wave PB.3): Filters out any errant coordinates (>45km / 0.4° lat from station).
    public func computedBoundingBox(tightVehicleBounding: Bool = false) -> (sw: CLLocationCoordinate2D, ne: CLLocationCoordinate2D)? {
        let validCoords = coordinates.filter { pt in
            abs(pt.latitude - stationCoordinate.latitude) < 0.4 &&
            abs(pt.longitude - stationCoordinate.longitude) < 0.5
        }
        
        var allPoints: [CLLocationCoordinate2D] = []
        
        if tightVehicleBounding, let vCoord = vehicleCoordinate,
           abs(vCoord.latitude - stationCoordinate.latitude) < 0.4 &&
           abs(vCoord.longitude - stationCoordinate.longitude) < 0.5 {
            allPoints = [stationCoordinate, vCoord]
            
            // Include intermediate route coordinates between station and vehicle to preserve track curvature
            let intermediate = Self.extractIntermediateCoordinates(
                between: stationCoordinate,
                and: vCoord,
                in: validCoords
            )
            allPoints.append(contentsOf: intermediate)
        } else {
            allPoints = validCoords
            allPoints.append(stationCoordinate)
            if let vCoord = vehicleCoordinate,
               abs(vCoord.latitude - stationCoordinate.latitude) < 0.4 &&
               abs(vCoord.longitude - stationCoordinate.longitude) < 0.5 {
                allPoints.append(vCoord)
            }
        }
        
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
        let minSpan = tightVehicleBounding ? 0.004 : 0.008
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
    
    /// Finds the slice of polyline coordinates along `coords` that fall between the projections
    /// of point A and point B.
    public static func extractIntermediateCoordinates(
        between coordA: CLLocationCoordinate2D,
        and coordB: CLLocationCoordinate2D,
        in coords: [CLLocationCoordinate2D]
    ) -> [CLLocationCoordinate2D] {
        guard coords.count >= 2 else { return [] }
        
        var idxA = 0
        var bestDistA = Double.infinity
        var idxB = 0
        var bestDistB = Double.infinity
        
        for (i, pt) in coords.enumerated() {
            let dA = pow(pt.latitude - coordA.latitude, 2) + pow(pt.longitude - coordA.longitude, 2)
            if dA < bestDistA {
                bestDistA = dA
                idxA = i
            }
            let dB = pow(pt.latitude - coordB.latitude, 2) + pow(pt.longitude - coordB.longitude, 2)
            if dB < bestDistB {
                bestDistB = dB
                idxB = i
            }
        }
        
        let start = min(idxA, idxB)
        let end = max(idxA, idxB)
        guard start < end else { return [] }
        
        return Array(coords[start...end])
    }
    
    /// Computes the track distance (in meters) along the intermediate polyline coordinates between two points.
    /// Falls back to straight-line great-circle distance if intermediate polyline points are insufficient.
    public static func calculateTrackDistance(
        between coordA: CLLocationCoordinate2D,
        and coordB: CLLocationCoordinate2D,
        in coords: [CLLocationCoordinate2D]
    ) -> Double {
        let intermediate = extractIntermediateCoordinates(between: coordA, and: coordB, in: coords)
        if intermediate.count >= 2 {
            var totalMeters: Double = 0.0
            for i in 0..<(intermediate.count - 1) {
                let loc1 = CLLocation(latitude: intermediate[i].latitude, longitude: intermediate[i].longitude)
                let loc2 = CLLocation(latitude: intermediate[i + 1].latitude, longitude: intermediate[i + 1].longitude)
                totalMeters += loc1.distance(from: loc2)
            }
            return totalMeters
        } else {
            let locA = CLLocation(latitude: coordA.latitude, longitude: coordA.longitude)
            let locB = CLLocation(latitude: coordB.latitude, longitude: coordB.longitude)
            return locA.distance(from: locB)
        }
    }
    
    /// Classifies the camera mode for an inspected corridor run based on track distance and imminence (Pre-T.7).
    public static func classifyCameraMode(
        station: CLLocationCoordinate2D,
        vehicle: CLLocationCoordinate2D?,
        coordinates: [CLLocationCoordinate2D],
        minutes: Int? = nil,
        status: String? = nil
    ) -> InspectionCameraMode {
        guard let vCoord = vehicle else {
            return .stationAnchor
        }
        
        let trimmedStatus = (status ?? "").lowercased()
        if trimmedStatus.contains("boarding") || minutes == 0 {
            return .stationAnchor
        }
        
        let distance = calculateTrackDistance(between: station, and: vCoord, in: coordinates)
        
        // D <= 2.5km (2500m) or imminence <= 4 min triggers dual framing of both station and vehicle
        if distance <= 2500.0 || (minutes != nil && minutes! <= 4) {
            return .dualFraming(trackDistanceMeters: distance)
        } else {
            return .vehicleTracking(trackDistanceMeters: distance)
        }
    }
    
    /// Resolves the active camera mode for this inspection command based on vehicle proximity.
    public var cameraMode: InspectionCameraMode {
        Self.classifyCameraMode(
            station: stationCoordinate,
            vehicle: vehicleCoordinate,
            coordinates: coordinates,
            minutes: minutes,
            status: vehicleStatus
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
              lhs.coordinates.count == rhs.coordinates.count &&
              lhs.vehicleStatus == rhs.vehicleStatus else {
            return false
        }
        
        if let lCoord = lhs.vehicleCoordinate, let rCoord = rhs.vehicleCoordinate {
            if abs(lCoord.latitude - rCoord.latitude) > 0.00001 ||
               abs(lCoord.longitude - rCoord.longitude) > 0.00001 {
                return false
            }
        } else if (lhs.vehicleCoordinate == nil) != (rhs.vehicleCoordinate == nil) {
            return false
        }
        
        if let lBearing = lhs.vehicleBearing, let rBearing = rhs.vehicleBearing {
            if abs(lBearing - rBearing) > 0.1 {
                return false
            }
        } else if (lhs.vehicleBearing == nil) != (rhs.vehicleBearing == nil) {
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

