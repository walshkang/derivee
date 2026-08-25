import Foundation
import CoreLocation
import UIKit
import MapLibre

/// High-performance dynamic loader and parser for multi-modal transit GeoJSON networks (`transit-lines.geojson`).
/// Replaces static trunk line datasets to support on-demand City Packs across all metropolitan regions.
public enum TransitCartographyLoader: Sendable {
    
    /// Resolves the file URL for the transit lines GeoJSON dataset.
    /// Precedence order:
    /// 1. Installed City Pack directory: `~/Documents/CityPacks/{slug}/transit-lines.geojson`
    /// 2. App bundle resource: `transit-lines.geojson`
    /// 3. App bundle resource: `subway-lines.geojson` (NYC legacy baseline fallback)
    /// 4. Test bundle fallback via `Bundle(for: SpatialDatabaseManager.self)`
    public static func resolveTransitLinesGeoJSONURL(for citySlug: String? = nil) -> URL? {
        if let slug = citySlug, !slug.isEmpty {
            let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            if let packURL = documentsURL?.appendingPathComponent("CityPacks/\(slug)/transit-lines.geojson"),
               FileManager.default.fileExists(atPath: packURL.path) {
                return packURL
            }
        }
        
        if let bundleURL = Bundle.main.url(forResource: "transit-lines", withExtension: "geojson") {
            return bundleURL
        }
        
        if let bundleURL = Bundle.main.url(forResource: "subway-lines", withExtension: "geojson") {
            return bundleURL
        }
        
        // Secondary lookup for unit test bundles
        let testBundle = Bundle(for: SpatialDatabaseManager.self)
        if let testURL = testBundle.url(forResource: "transit-lines", withExtension: "geojson") {
            return testURL
        }
        if let testURL = testBundle.url(forResource: "subway-lines", withExtension: "geojson") {
            return testURL
        }
        
        return nil
    }
    
    /// Synchronously loads and parses the transit network shape for the specified city.
    /// Returns an empty `MLNShapeCollectionFeature` if the dataset is missing or corrupt.
    public static func loadTransitLinesShapeSync(for citySlug: String? = nil) -> MLNShapeCollectionFeature {
        guard let url = resolveTransitLinesGeoJSONURL(for: citySlug),
              let data = try? Data(contentsOf: url) else {
            return MLNShapeCollectionFeature(shapes: [])
        }
        return parseGeoJSONData(data)
    }
    
    /// Asynchronously loads and parses transit lines off the main thread at `.userInitiated` priority.
    public static func loadTransitLinesShape(for citySlug: String? = nil) async -> MLNShapeCollectionFeature {
        return await Task.detached(priority: .userInitiated) {
            guard let url = resolveTransitLinesGeoJSONURL(for: citySlug),
                  let data = try? Data(contentsOf: url) else {
                return MLNShapeCollectionFeature(shapes: [])
            }
            return parseGeoJSONData(data)
        }.value
    }
    
    /// Asynchronously loads and parses transit lines from an explicit file URL off the main thread.
    public static func loadTransitLinesShape(from url: URL) async -> MLNShapeCollectionFeature {
        return await Task.detached(priority: .userInitiated) {
            guard let data = try? Data(contentsOf: url) else {
                return MLNShapeCollectionFeature(shapes: [])
            }
            return parseGeoJSONData(data)
        }.value
    }
    
    /// Parses raw GeoJSON Data into an `MLNShapeCollectionFeature`, converting color attributes to `UIColor`
    /// for GPU shader evaluation via `NSExpression(forKeyPath: "color")`.
    public static func parseGeoJSONData(_ data: Data) -> MLNShapeCollectionFeature {
        guard let parsedShape = try? MLNShape(data: data, encoding: String.Encoding.utf8.rawValue) else {
            return MLNShapeCollectionFeature(shapes: [])
        }
        
        let features: [MLNShape]
        if let collection = parsedShape as? MLNShapeCollectionFeature {
            features = collection.shapes
        } else if let singleFeature = parsedShape as? MLNFeature, let shape = singleFeature as? MLNShape {
            features = [shape]
        } else {
            return MLNShapeCollectionFeature(shapes: [])
        }
        
        for shape in features {
            if let feature = shape as? MLNFeature {
                var attrs = feature.attributes
                let hex = (attrs["color_hex"] as? String) ?? (attrs["color"] as? String) ?? "#FFB300"
                attrs["color_hex"] = hex
                attrs["color"] = UIColor(hex: hex)
                
                if attrs["casing_color_hex"] == nil {
                    attrs["casing_color_hex"] = "#FFFFFF"
                }
                
                // Extract or infer modal_class for MapLibre layer predicates
                let modalClassRaw: Int
                if let raw = attrs["modal_class"] as? Int {
                    modalClassRaw = raw
                } else if let num = attrs["modal_class"] as? NSNumber {
                    modalClassRaw = num.intValue
                } else if let str = attrs["modal_class"] as? String, let parsed = Int(str) {
                    modalClassRaw = parsed
                } else if let routeType = attrs["route_type"] as? Int {
                    modalClassRaw = TransitModalClass.from(routeType: routeType).rawValue
                } else if let routeTypeNum = attrs["route_type"] as? NSNumber {
                    modalClassRaw = TransitModalClass.from(routeType: routeTypeNum.intValue).rawValue
                } else {
                    modalClassRaw = TransitModalClass.subway.rawValue
                }
                attrs["modal_class"] = modalClassRaw
                
                feature.attributes = attrs
            }
        }
        
        return MLNShapeCollectionFeature(shapes: features)
    }
}
