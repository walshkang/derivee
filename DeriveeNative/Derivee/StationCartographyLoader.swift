import Foundation
import CoreLocation
import UIKit
import MapLibre

/// High-performance dynamic loader and parser for subterranean and multi-level station geometries (`station_shapes.geojson`).
/// Implements Research Doc 15 (§2) and Research Doc 20 (§4).
/// Provides zero-copy / optimized `MLNShapeSource` configuration for seamless cross-scale transitions.
public enum StationCartographyLoader: Sendable {
    
    /// Resolves the file URL for the station shapes GeoJSON dataset.
    /// Precedence order:
    /// 1. Installed City Pack directory: `~/Documents/CityPacks/{slug}/station_shapes.geojson`
    /// 2. App bundle resource: `station_shapes.geojson`
    /// 3. Test bundle fallback via `Bundle(for: SpatialDatabaseManager.self)`
    public static func resolveStationShapesGeoJSONURL(for citySlug: String? = nil) -> URL? {
        if let slug = citySlug, !slug.isEmpty {
            let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            if let packURL = documentsURL?.appendingPathComponent("CityPacks/\(slug)/station_shapes.geojson"),
               FileManager.default.fileExists(atPath: packURL.path) {
                return packURL
            }
        }
        
        if let bundleURL = Bundle.main.url(forResource: "station_shapes", withExtension: "geojson") {
            return bundleURL
        }
        
        // Secondary lookup for unit test bundles
        let testBundle = Bundle(for: SpatialDatabaseManager.self)
        if let testURL = testBundle.url(forResource: "station_shapes", withExtension: "geojson") {
            return testURL
        }
        
        return nil
    }
    
    /// Synchronously loads and parses the station shapes for the specified city.
    /// Returns an empty `MLNShapeCollectionFeature` if the dataset is missing or corrupt.
    public static func loadStationShapesSync(for citySlug: String? = nil) -> MLNShapeCollectionFeature {
        guard let url = resolveStationShapesGeoJSONURL(for: citySlug),
              let data = try? Data(contentsOf: url) else {
            return MLNShapeCollectionFeature(shapes: [])
        }
        return parseGeoJSONData(data)
    }
    
    /// Asynchronously loads and parses station shapes off the main thread at `.userInitiated` priority.
    public static func loadStationShapes(for citySlug: String? = nil) async -> MLNShapeCollectionFeature {
        return await Task.detached(priority: .userInitiated) {
            guard let url = resolveStationShapesGeoJSONURL(for: citySlug),
                  let data = try? Data(contentsOf: url) else {
                return MLNShapeCollectionFeature(shapes: [])
            }
            return parseGeoJSONData(data)
        }.value
    }
    
    /// Asynchronously loads and parses station shapes from an explicit file URL off the main thread.
    public static func loadStationShapes(from url: URL) async -> MLNShapeCollectionFeature {
        return await Task.detached(priority: .userInitiated) {
            guard let data = try? Data(contentsOf: url) else {
                return MLNShapeCollectionFeature(shapes: [])
            }
            return parseGeoJSONData(data)
        }.value
    }
    
    /// Creates an optimized `MLNShapeSource` for station geometry (Doc 20 §4).
    /// Enforces:
    /// - `maximumZoomLevel: 16`: activates hardware-accelerated overzooming without tile thrashing.
    /// - `clipsCoordinates: false`: suppresses CPU boundary polygon clipping.
    /// - `clustered: false`: suppresses point-clustering spatial evaluation.
    /// - `synchronousUpdate: false`: forces deserialization onto background threads.
    public static func makeOptimizedStationSource(
        identifier: String,
        shape: MLNShape? = nil,
        geoJSONData: Data? = nil
    ) -> MLNShapeSource {
        let sourceOptions: [MLNShapeSourceOption: Any] = [
            .maximumZoomLevel: 16,
            .clipsCoordinates: false,
            .clustered: false,
            .synchronousUpdate: false
        ]
        
        if let data = geoJSONData,
           let parsedShape = try? MLNShape(data: data, encoding: String.Encoding.utf8.rawValue) {
            return MLNShapeSource(identifier: identifier, shape: parsedShape, options: sourceOptions)
        }
        
        return MLNShapeSource(identifier: identifier, shape: shape, options: sourceOptions)
    }
    
    /// Parses raw GeoJSON Data into an `MLNShapeCollectionFeature`.
    public static func parseGeoJSONData(_ data: Data) -> MLNShapeCollectionFeature {
        guard let parsedShape = try? MLNShape(data: data, encoding: String.Encoding.utf8.rawValue) else {
            return MLNShapeCollectionFeature(shapes: [])
        }
        
        if let collection = parsedShape as? MLNShapeCollectionFeature {
            return collection
        } else if let singleFeature = parsedShape as? MLNFeature, let shape = singleFeature as? MLNShape {
            return MLNShapeCollectionFeature(shapes: [shape])
        } else {
            return MLNShapeCollectionFeature(shapes: [])
        }
    }
}
