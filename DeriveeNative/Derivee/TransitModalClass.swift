import Foundation
import CoreGraphics

/// Dérivée's 4-tier transit modal classification system.
/// Normalizes standard GTFS `route_type` (0–7, 11) and Extended GTFS (Hierarchical Vehicle Types / HVT 100–1400)
/// into 4 visual cartography layers and UI rendering paradigms.
public enum TransitModalClass: Int, Sendable, CaseIterable, Codable, Comparable, Hashable {
    case subway = 0    // Heavy Rail / Subway / Metro / Commuter Rail / PATH
    case lightRail = 1 // Light Rail (LRT) / Tram / Streetcar / Trolley
    case bus = 2       // BRT / Local Bus / Express Bus / Trolleybus
    case ferry = 3     // Maritime Ferry / Water Transport
    
    public static func < (lhs: TransitModalClass, rhs: TransitModalClass) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
    
    /// Normalizes standard GTFS `route_type` and Extended GTFS (HVT) codes into Dérivée's 4 modal classes.
    /// Perfectly mirrors the Go Observer engine (`observer/internal/gtfs/models.go:107`).
    public static func from(routeType: Int) -> TransitModalClass {
        switch routeType {
        case 0, 900, 901, 904: // Tram / Streetcar / Light Rail
            return .lightRail
        case 1, 2, 401, 402, 405: // Subway / Heavy Rail / Metro / Monorail
            return .subway
        case 3, 5, 11, 700, 702, 800: // Bus / Cable Car / Trolleybus
            return .bus
        case 4, 1000, 1200: // Maritime Ferry
            return .ferry
        default:
            if routeType >= 100 && routeType < 200 { // Railway / Commuter Rail
                return .subway
            } else if routeType >= 400 && routeType < 500 { // Metro / Underground
                return .subway
            } else if routeType >= 700 && routeType < 900 { // Bus / Coach / Trolleybus
                return .bus
            } else if routeType >= 900 && routeType < 1000 { // Tram / LRT
                return .lightRail
            } else if routeType >= 1000 && routeType < 1300 { // Water / Ferry
                return .ferry
            }
            return .subway
        }
    }
    
    /// User-facing display name for station and drawer subtitles.
    public var displayName: String {
        switch self {
        case .subway:
            return "Subway"
        case .lightRail:
            return "Light Rail"
        case .bus:
            return "Bus"
        case .ferry:
            return "Ferry"
        }
    }
    
    /// SF Symbol icon name representing the transit mode.
    public var symbolName: String {
        switch self {
        case .subway:
            return "tram.fill"
        case .lightRail:
            return "cablecar.fill"
        case .bus:
            return "bus.fill"
        case .ferry:
            return "ferry.fill"
        }
    }
    
    /// MapLibre primary stroke line width in points.
    public var cartographyLineWidth: CGFloat {
        switch self {
        case .subway:
            return 4.0
        case .lightRail:
            return 4.0
        case .bus:
            return 0.0 // Bus handled via capillary lens dots at z >= 14.5
        case .ferry:
            return 2.5
        }
    }
    
    /// MapLibre casing stroke line width in points.
    public var cartographyCasingWidth: CGFloat {
        switch self {
        case .subway:
            return 6.0
        case .lightRail:
            return 6.0
        case .bus, .ferry:
            return 0.0
        }
    }
    
    /// MapLibre dash pattern for the primary stroke line, or nil for solid lines.
    public var cartographyLineDashPattern: [Double]? {
        switch self {
        case .ferry:
            return [4.0, 3.0]
        case .subway, .lightRail, .bus:
            return nil
        }
    }
    
    /// MapLibre dash pattern for casing stroke, or nil for solid casings.
    public var cartographyCasingDashPattern: [Double]? {
        switch self {
        case .lightRail:
            return [3.0, 2.0] // Dashed casing visually conveys surface LRT rail
        case .subway, .bus, .ferry:
            return nil
        }
    }
    
    /// Default brand color hex when route color is not specified.
    public var defaultColorHex: String {
        switch self {
        case .subway:
            return "#FFB300"
        case .lightRail:
            return "#00843D"
        case .bus:
            return "#00A1DE"
        case .ferry:
            return "#00A3E0"
        }
    }
    
    /// Default text contrast color hex.
    public var defaultTextColorHex: String {
        switch self {
        case .subway, .lightRail, .bus, .ferry:
            return "#FFFFFF"
        }
    }
}
