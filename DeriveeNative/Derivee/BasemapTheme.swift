import UIKit
import MapLibre

/// Available basemap visual themes
public enum BasemapTheme: String, CaseIterable, Identifiable, Codable {
    case day = "day"
    case night = "night"
    case oled = "oled"
    case transit = "transit"
    
    public var id: String { rawValue }
    
    public var displayName: String {
        switch self {
        case .day: return "Standard Day"
        case .night: return "Standard Night"
        case .oled: return "OLED Ultra Dark"
        case .transit: return "Transit Network"
        }
    }
}

/// Strongly typed color palette tokens for a basemap theme
public struct BasemapPalette: Equatable {
    public let backgroundColor: UIColor
    public let waterColor: UIColor
    public let parkColor: UIColor
    public let landuseColor: UIColor
    public let buildingColor: UIColor
    public let building3DColor: UIColor
    public let building3DOpacity: Double
    public let roadColor: UIColor
    public let roadCasingColor: UIColor
    public let railColor: UIColor
    public let railLineWidth: CGFloat
    public let railOpacity: CGFloat
    public let labelTextColor: UIColor
    public let labelHaloColor: UIColor
    public let fogColor: UIColor
    
    public static let day = BasemapPalette(
        backgroundColor: UIColor(hex: "#F9F9F6"),
        waterColor: UIColor(hex: "#C8D7DE"),
        parkColor: UIColor(hex: "#E3ECD9"),
        landuseColor: UIColor(hex: "#EDEDE9"),
        buildingColor: UIColor(hex: "#DCDCD6"),
        building3DColor: UIColor(hex: "#DCDCD6"),
        building3DOpacity: 0.6,
        roadColor: UIColor(hex: "#FFFFFF"),
        roadCasingColor: UIColor(hex: "#D6D6D0"),
        railColor: UIColor(hex: "#7A7D84"),
        railLineWidth: 1.5,
        railOpacity: 0.8,
        labelTextColor: UIColor(hex: "#1C1C1E"),
        labelHaloColor: UIColor(hex: "#FFFFFF"),
        fogColor: UIColor(hex: "#1C1C1E")
    )
    
    public static let night = BasemapPalette(
        backgroundColor: UIColor(hex: "#12121A"),
        waterColor: UIColor(hex: "#0A0A12"),
        parkColor: UIColor(hex: "#151B18"),
        landuseColor: UIColor(hex: "#14141E"),
        buildingColor: UIColor(hex: "#181822"),
        building3DColor: UIColor(hex: "#242436"),
        building3DOpacity: 0.75,
        roadColor: UIColor(hex: "#222433"),
        roadCasingColor: UIColor(hex: "#161722"),
        railColor: UIColor(hex: "#4E5366"),
        railLineWidth: 1.5,
        railOpacity: 0.8,
        labelTextColor: UIColor(hex: "#FFFFFF"),
        labelHaloColor: UIColor(hex: "#12121A"),
        fogColor: UIColor(hex: "#000000")
    )
    
    public static let oled = BasemapPalette(
        backgroundColor: UIColor(hex: "#000000"),
        waterColor: UIColor(hex: "#050508"),
        parkColor: UIColor(hex: "#080D0A"),
        landuseColor: UIColor(hex: "#06060A"),
        buildingColor: UIColor(hex: "#0A0A10"),
        building3DColor: UIColor(hex: "#161622"),
        building3DOpacity: 0.8,
        roadColor: UIColor(hex: "#1C1C24"),
        roadCasingColor: UIColor(hex: "#0D0D12"),
        railColor: UIColor(hex: "#3A3A4A"),
        railLineWidth: 1.5,
        railOpacity: 0.8,
        labelTextColor: UIColor(hex: "#D1D1D6"),
        labelHaloColor: UIColor(hex: "#000000"),
        fogColor: UIColor(hex: "#000000")
    )
    
    public static let transit = BasemapPalette(
        backgroundColor: UIColor(hex: "#0D0F14"),
        waterColor: UIColor(hex: "#06080C"),
        parkColor: UIColor(hex: "#0E1410"),
        landuseColor: UIColor(hex: "#101318"),
        buildingColor: UIColor(hex: "#13161D"),
        building3DColor: UIColor(hex: "#1A1F2B"),
        building3DOpacity: 0.7,
        roadColor: UIColor(hex: "#181B22"),
        roadCasingColor: UIColor(hex: "#0F1116"),
        railColor: UIColor(hex: "#FFB300"),
        railLineWidth: 3.0,
        railOpacity: 0.95,
        labelTextColor: UIColor(hex: "#E2E8F0"),
        labelHaloColor: UIColor(hex: "#0D0F14"),
        fogColor: UIColor(hex: "#0A0C10")
    )
    
    public static func forTheme(_ theme: BasemapTheme) -> BasemapPalette {
        switch theme {
        case .day: return .day
        case .night: return .night
        case .oled: return .oled
        case .transit: return .transit
        }
    }
}

/// GPU-accelerated Theme Manager for dynamically interpolating basemap layers
public enum BasemapThemeManager {
    
    // Layer Group IDs matching composite_style.json
    static let waterFillLayerIds = ["Water", "Water intermittent"]
    static let waterLineLayerIds = ["River", "River tunnel", "Ferry line"]
    static let natureLayerIds = ["Park", "Meadow", "Scrub", "Crop", "Forest", "Sand", "Wood", "Grass", "Glacier"]
    static let landuseLayerIds = ["Residential", "Industrial", "Cemetery", "Hospital", "Stadium", "School", "Airport zone"]
    static let buildingLayerIds = ["Building"]
    static let building3DLayerId = "Building 3D"
    static let roadOutlineLayerIds = [
        "Minor road outline", "Major road outline", "Highway outline",
        "Tunnel outline", "Bridge outline", "Footway tunnel outline",
        "Path outline", "Aqueduct outline"
    ]
    static let roadLayerIds = [
        "Minor road", "Major road", "Highway", "Road under construction",
        "Tunnel", "Bridge", "Pier", "Pier road", "Pedestrian", "Path",
        "Path minor", "Footway tunnel", "Aqueduct", "Aeroway", "Heliport"
    ]
    public static let railLayerIds = [
        "Major rail", "Minor rail", "Railway tunnel",
        "Major rail hatching", "Minor rail hatching", "Railway tunnel hatching",
        "Cablecar", "Cablecar dash"
    ]
    static let labelLayerIds = [
        "Road labels", "City labels", "Town labels", "State labels",
        "Capital city labels", "Country labels", "Continent labels",
        "Place labels", "River labels", "Ocean labels", "Lake labels",
        "Housenumber", "Highway junction", "Highway shield", "Highway shield (US)",
        "Highway shield interstate top (US)", "Highway shield interstate (US)"
    ]
    static let fogLayerId = "cloud-layer"
    
    /// Applies a BasemapTheme to an active MLNStyle via GPU property transitions
    public static func applyTheme(_ theme: BasemapTheme, in style: MLNStyle, animated: Bool = true) {
        let palette = BasemapPalette.forTheme(theme)
        let duration: TimeInterval = animated ? 0.6 : 0.0
        let transition = MLNTransition(duration: duration, delay: 0)
        
        // 1. Background Layer
        if let bgLayer = style.layer(withIdentifier: "Background") as? MLNBackgroundStyleLayer {
            bgLayer.backgroundColorTransition = transition
            bgLayer.backgroundColor = NSExpression(forConstantValue: palette.backgroundColor)
        }
        
        // 2. Water Layers
        for layerId in waterFillLayerIds {
            if let fillLayer = style.layer(withIdentifier: layerId) as? MLNFillStyleLayer {
                fillLayer.fillColorTransition = transition
                fillLayer.fillColor = NSExpression(forConstantValue: palette.waterColor)
            }
        }
        for layerId in waterLineLayerIds {
            if let lineLayer = style.layer(withIdentifier: layerId) as? MLNLineStyleLayer {
                lineLayer.lineColorTransition = transition
                lineLayer.lineColor = NSExpression(forConstantValue: palette.waterColor)
            }
        }
        
        // 3. Nature / Parks
        for layerId in natureLayerIds {
            if let fillLayer = style.layer(withIdentifier: layerId) as? MLNFillStyleLayer {
                fillLayer.fillColorTransition = transition
                fillLayer.fillColor = NSExpression(forConstantValue: palette.parkColor)
            }
        }
        
        // 4. Landuse
        for layerId in landuseLayerIds {
            if let fillLayer = style.layer(withIdentifier: layerId) as? MLNFillStyleLayer {
                fillLayer.fillColorTransition = transition
                fillLayer.fillColor = NSExpression(forConstantValue: palette.landuseColor)
            }
        }
        
        // 5. Buildings (2D Footprints & 3D Extrusions)
        for layerId in buildingLayerIds {
            if let fillLayer = style.layer(withIdentifier: layerId) as? MLNFillStyleLayer {
                fillLayer.fillColorTransition = transition
                fillLayer.fillColor = NSExpression(forConstantValue: palette.buildingColor)
            }
        }
        if let extrusionLayer = style.layer(withIdentifier: building3DLayerId) as? MLNFillExtrusionStyleLayer {
            extrusionLayer.fillExtrusionColorTransition = transition
            extrusionLayer.fillExtrusionColor = NSExpression(forConstantValue: palette.building3DColor)
            extrusionLayer.fillExtrusionOpacityTransition = transition
            extrusionLayer.fillExtrusionOpacity = NSExpression(forConstantValue: palette.building3DOpacity)
        }
        
        // 6. Road Outlines
        for layerId in roadOutlineLayerIds {
            if let lineLayer = style.layer(withIdentifier: layerId) as? MLNLineStyleLayer {
                lineLayer.lineColorTransition = transition
                lineLayer.lineColor = NSExpression(forConstantValue: palette.roadCasingColor)
            }
        }
        
        // 7. Roads
        for layerId in roadLayerIds {
            if let lineLayer = style.layer(withIdentifier: layerId) as? MLNLineStyleLayer {
                lineLayer.lineColorTransition = transition
                lineLayer.lineColor = NSExpression(forConstantValue: palette.roadColor)
            }
        }
        
        // 8. Rail & Transit (Turn off heavy rail / commuter rail in favor of subway network)
        for layerId in railLayerIds {
            if let lineLayer = style.layer(withIdentifier: layerId) as? MLNLineStyleLayer {
                lineLayer.isVisible = false
                lineLayer.lineColorTransition = transition
                lineLayer.lineColor = NSExpression(forConstantValue: palette.railColor)
                lineLayer.lineWidthTransition = transition
                lineLayer.lineWidth = NSExpression(forConstantValue: palette.railLineWidth)
                lineLayer.lineOpacityTransition = transition
                lineLayer.lineOpacity = NSExpression(forConstantValue: palette.railOpacity)
            }
        }
        
        // 9. Labels & Typography
        for layerId in labelLayerIds {
            if let symbolLayer = style.layer(withIdentifier: layerId) as? MLNSymbolStyleLayer {
                symbolLayer.textColorTransition = transition
                symbolLayer.textColor = NSExpression(forConstantValue: palette.labelTextColor)
                symbolLayer.textHaloColorTransition = transition
                symbolLayer.textHaloColor = NSExpression(forConstantValue: palette.labelHaloColor)
            }
        }
        
        // 10. Fog Layer
        if let fogLayer = style.layer(withIdentifier: fogLayerId) as? MLNFillStyleLayer {
            fogLayer.fillColorTransition = transition
            fogLayer.fillColor = NSExpression(forConstantValue: palette.fogColor)
        }
    }
}
