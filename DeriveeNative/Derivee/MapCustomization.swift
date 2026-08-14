import Foundation
import UIKit

/// Strongly typed `@AppStorage` keys for visual customization settings
public enum AppStorageKeys {
    public static let selectedBasemapTheme = "selectedBasemapTheme"
    public static let fogOpacity = "fogOpacity"
    public static let showBoundaryBorders = "showBoundaryBorders"
}

/// Constants and defaults for map visual customization (Wave J.5)
public enum MapCustomizationDefaults {
    public static let defaultTheme = BasemapTheme.night
    
    // Fog Opacity
    public static let defaultFogOpacity: Double = 0.85
    public static let minFogOpacity: Double = 0.60
    public static let maxFogOpacity: Double = 0.98
    
    // Boundary Borders
    public static let defaultShowBoundaryBorders: Bool = false
    public static let boundaryBorderColorHex: String = "#FFB300" // Dérivée Electric Amber
    public static let boundaryBorderWidth: CGFloat = 1.5
    public static let boundaryBorderOpacity: CGFloat = 0.75
    
    // MapLibre Layer Identifier
    public static let fogBorderLayerId = "fog-border-layer"
}
