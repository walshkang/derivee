import Foundation
import UIKit

/// Strongly typed `@AppStorage` keys for visual customization settings
public enum AppStorageKeys {
    public static let selectedBasemapTheme = "selectedBasemapTheme"
    public static let fogOpacity = "fogOpacity"
    public static let showBoundaryBorders = "showBoundaryBorders"
    public static let isTrackingEnabled = "isTrackingEnabled"
    public static let isLiveActivityEnabled = "isLiveActivityEnabled"
    
    // Transit & Wayfinding (Wave J.6)
    public static let showSubwayThoroughfares = "showSubwayThoroughfares"
    public static let subwayStationMarkerStyle = "subwayStationMarkerStyle"
    public static let showNearbyBusesLens = "showNearbyBusesLens"
}

/// Subway station bullet presentation styles
public enum SubwayStationMarkerStyle: String, CaseIterable, Identifiable, Sendable {
    case exploredOnly = "Explored Only"
    case allStations = "All Stations"
    case hidden = "Hidden"
    
    public var id: String { rawValue }
}

/// Constants and defaults for map visual customization (Wave J.5 & J.6)
public enum MapCustomizationDefaults {
    public static let defaultTheme = BasemapTheme.day
    
    // Fog Opacity
    public static let defaultFogOpacity: Double = 0.85
    public static let minFogOpacity: Double = 0.60
    public static let maxFogOpacity: Double = 0.98
    
    // Boundary Borders
    public static let defaultShowBoundaryBorders: Bool = false
    public static let boundaryBorderColorHex: String = "#FFB300" // Dérivée Electric Amber
    public static let boundaryBorderWidth: CGFloat = 1.5
    public static let boundaryBorderOpacity: CGFloat = 0.75
    
    // Transit Thoroughfares & Bus Stops
    public static let defaultShowSubwayThoroughfares: Bool = true
    public static let defaultSubwayStationMarkerStyle: SubwayStationMarkerStyle = .exploredOnly
    public static let defaultShowNearbyBusesLens: Bool = true
    
    // MapLibre Layer Identifiers
    public static let fogBorderLayerId = "fog-border-layer"
    public static let subwayLinesSourceId = "subway-thoroughfares-source"
    public static let subwayLinesCasingLayerId = "subway-lines-casing-layer"
    public static let subwayLinesLayerId = "subway-lines-layer"
    public static let subwayStationBulletsSourceId = "subway-station-bullets-source"
    public static let subwayStationBulletsLayerId = "subway-station-bullets-layer"
    public static let nearbyBusStopsSourceId = "nearby-bus-stops-source"
    public static let nearbyBusStopsLayerId = "nearby-bus-stops-layer"
}
