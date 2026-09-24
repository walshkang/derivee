import Foundation
import CoreGraphics
import MapLibre

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
    
    /// Canonical reference primary stroke line width in points at neighborhood scale (z=14).
    /// For dynamic GPU zoom-interpolated rendering, use `cartographyLineWidthExpression()`.
    public var cartographyLineWidth: CGFloat {
        switch self {
        case .subway:
            return 2.5
        case .lightRail:
            return 2.5
        case .bus:
            return 0.0 // Bus handled via capillary lens dots at z >= 14.5
        case .ferry:
            return 2.5
        }
    }
    
    /// Canonical reference casing stroke line width in points at neighborhood scale (z=14).
    /// 4.5pt provides a clean 1.0pt casing border on each side of 2.5pt line.
    /// For dynamic GPU zoom-interpolated rendering, use `cartographyCasingWidthExpression()`.
    public var cartographyCasingWidth: CGFloat {
        switch self {
        case .subway:
            return 4.5
        case .lightRail:
            return 4.5
        case .bus, .ferry:
            return 0.0
        }
    }
    
    /// Generates continuous zoom-interpolated line width expression per Research Doc 22 §4.2.
    /// Regional (z=11): 1.2pt -> Neighborhood (z=14): 2.5pt -> Street (z=17): 4.5pt.
    public func cartographyLineWidthExpression() -> NSExpression {
        switch self {
        case .subway, .lightRail:
            return NSExpression(
                forMLNInterpolating: .zoomLevelVariable,
                curveType: .linear,
                parameters: nil,
                stops: NSExpression(forConstantValue: [
                    11.0: 1.2,
                    14.0: 2.5,
                    17.0: 4.5
                ])
            )
        case .ferry:
            return NSExpression(forConstantValue: 2.5)
        case .bus:
            return NSExpression(forConstantValue: 0.0)
        }
    }
    
    /// Generates continuous zoom-interpolated casing width expression per Research Doc 22 §4.2.
    /// Regional (z=11): 2.5pt -> Neighborhood (z=14): 4.5pt -> Street (z=17): 8.1pt.
    /// Margin: 0.65pt at z=11 -> 1.0pt at z=14 -> 1.8pt at z=17.
    public func cartographyCasingWidthExpression() -> NSExpression {
        switch self {
        case .subway, .lightRail:
            return NSExpression(
                forMLNInterpolating: .zoomLevelVariable,
                curveType: .linear,
                parameters: nil,
                stops: NSExpression(forConstantValue: [
                    11.0: 2.5,
                    14.0: 4.5,
                    17.0: 8.1
                ])
            )
        case .ferry, .bus:
            return NSExpression(forConstantValue: 0.0)
        }
    }
    
    /// Generates unified trench casing width expression per Research Doc 22 §4.2 and Wave V.3.
    /// Regional (z=11): casing_width_z11 -> Neighborhood (z=14): casing_width -> Street (z=17): casing_width_z17.
    public static func trenchCasingWidthExpression() -> NSExpression {
        return NSExpression(
            forMLNInterpolating: .zoomLevelVariable,
            curveType: .linear,
            parameters: nil,
            stops: NSExpression(forConstantValue: [
                11.0: NSExpression(forKeyPath: "casing_width_z11"),
                14.0: NSExpression(forKeyPath: "casing_width"),
                17.0: NSExpression(forKeyPath: "casing_width_z17")
            ])
        )
    }
    
    /// Generates route badge opacity expression per Research Doc 22 §5.5 and Wave V.4.
    /// Clamped to 0.0 for z < 13.5; smooth linear transition to full opacity 1.0 at z >= 14.5.
    public static func badgeOpacityExpression() -> NSExpression {
        return NSExpression(
            forMLNInterpolating: .zoomLevelVariable,
            curveType: .linear,
            parameters: nil,
            stops: NSExpression(forConstantValue: [
                13.5: 0.0,
                14.5: 1.0
            ])
        )
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
