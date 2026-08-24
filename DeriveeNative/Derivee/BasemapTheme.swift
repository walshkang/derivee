import UIKit
import MapLibre

/// Available basemap visual themes
public enum BasemapTheme: String, CaseIterable, Identifiable, Codable {
    case day = "day"
    case transit = "transit"
    
    public var id: String { rawValue }
    
    public var displayName: String {
        switch self {
        case .day: return "Standard Day"
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
    
    public static let transit = BasemapPalette(
        backgroundColor: UIColor(hex: "#FFFFFF"),
        waterColor: UIColor(hex: "#DDE7ED"),
        parkColor: UIColor(hex: "#EDF3E8"),
        landuseColor: UIColor(hex: "#F5F6F8"),
        buildingColor: UIColor(hex: "#F1F3F5"),
        building3DColor: UIColor(hex: "#E5E8EB"),
        building3DOpacity: 0.5,
        roadColor: UIColor(hex: "#F0F2F5"),
        roadCasingColor: UIColor(hex: "#E4E7EB"),
        railColor: UIColor(hex: "#FFB300"),
        railLineWidth: 3.0,
        railOpacity: 0.95,
        labelTextColor: UIColor(hex: "#1C1C1E"),
        labelHaloColor: UIColor(hex: "#FFFFFF"),
        fogColor: UIColor(hex: "#1C1C1E")
    )
    
    public static func forTheme(_ theme: BasemapTheme) -> BasemapPalette {
        switch theme {
        case .day: return .day
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
