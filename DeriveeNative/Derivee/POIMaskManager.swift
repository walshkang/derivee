import Foundation
import CoreLocation
import MapLibre
import H3

enum POIMaskManager {
    /// Target commercial, entertainment, educational, healthcare, and park POI symbol layers in MapTiler Streets v2
    static let baseVectorPOILayerIds = [
        "Public",
        "Sport",
        "Education",
        "Tourism",
        "Culture",
        "Shopping",
        "Food",
        "Transport",
        "Park",
        "Healthcare"
    ]
    
    /// Base vector layer for transit stations that should be suppressed in favor of native runtime POIs
    static let baseStationLayerId = "Station"
    
    /// Proximity radius in meters for the active vicinity bubble
    static let activeVicinityRadius: CLLocationDistance = 200.0
    
    /// Maximum distance in meters for the ambient lure glow in unexplored fog
    static let lureMaxRadius: CLLocationDistance = 1000.0
    
    /// Configures base vector layers by suppressing commercial POIs, base stations, and heavy rail
    /// in favor of Dérivée's subway network runtime layer.
    static func configureBaseVectorLayers(in style: MLNStyle) {
        for layerId in baseVectorPOILayerIds {
            if let layer = style.layer(withIdentifier: layerId) {
                layer.isVisible = false
            }
        }
        
        // Suppress base vector station layer to avoid duplicate stations and label collision fighting
        if let stationLayer = style.layer(withIdentifier: baseStationLayerId) {
            stationLayer.isVisible = false
        }
        
        // Suppress heavy rail layers (Metro North, LIRR, Amtrak)
        for layerId in BasemapThemeManager.railLayerIds {
            if let layer = style.layer(withIdentifier: layerId) {
                layer.isVisible = false
            }
        }
    }
    
    /// Updates base vector POI layer visibility. Commercial/retail base POIs and heavy rail remain suppressed.
    static func updateVectorPOIMasks(in style: MLNStyle, userLocation: CLLocation?) {
        for layerId in baseVectorPOILayerIds {
            if let layer = style.layer(withIdentifier: layerId) {
                layer.isVisible = false
            }
        }
        if let stationLayer = style.layer(withIdentifier: baseStationLayerId) {
            stationLayer.isVisible = false
        }
        for layerId in BasemapThemeManager.railLayerIds {
            if let layer = style.layer(withIdentifier: layerId) {
                layer.isVisible = false
            }
        }
    }
    
    /// Resolves the Ghost POI 3-phase lifecycle state:
    /// - Phase 2 (Active Vicinity): Distance <= 200m
    /// - Phase 3 (Archive): Distance > 200m AND (in exploredHexes OR in discoveredPOIs)
    /// - Phase 1 (Lure Glow): Distance > 200m AND Distance <= 1000m AND NOT explored (when in .exploredOnly mode)
    /// - nil (Hidden): Otherwise or when in .hidden mode
    static func resolvePhase(
        poi: GhostPOI,
        userLocation: CLLocation?,
        exploredHexes: Set<String>,
        discoveredPOIs: Set<String>,
        markerStyle: SubwayStationMarkerStyle = .exploredOnly
    ) -> Int? {
        if markerStyle == .hidden {
            return nil
        }
        
        let isExplored = (!poi.h3Index.isEmpty && exploredHexes.contains(poi.h3Index)) || discoveredPOIs.contains(poi.id)
        
        guard let userLoc = userLocation else {
            // If user location is not yet known:
            // If explored, show as archive (phase 3)
            return isExplored ? 3 : nil
        }
        
        let distance = userLoc.distance(from: CLLocation(latitude: poi.coordinate.latitude, longitude: poi.coordinate.longitude))
        
        if distance <= activeVicinityRadius {
            return 2
        } else if isExplored {
            return 3
        } else if markerStyle == .exploredOnly && distance <= lureMaxRadius {
            return 1
        } else {
            return nil
        }
    }
    
    /// Computes H3 Res-11 hex index string for a coordinate
    static func computeH3Index(latitude: Double, longitude: Double) -> String {
        do {
            let cell = try H3.latLngToCell(latitude: latitude, longitude: longitude, resolution: 11)
            return String(cell, radix: 16)
        } catch {
            return ""
        }
    }
}
