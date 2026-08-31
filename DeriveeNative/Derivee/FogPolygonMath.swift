import Foundation
import CoreLocation
import MapLibre
import H3
import CH3

/// Encapsulates the composite geometric representation of the dynamic fog mask.
public struct FogGeometry: Sendable {
    /// The primary 50km bounding box polygon with explored territory cut out as interior holes.
    public let worldMaskPolygon: MLNPolygonFeature
    
    /// Standalone additive fog polygons representing unvisited center islands.
    public let islandPolygons: [MLNPolygonFeature]
    
    /// Combined composite shape suitable for `MLNShapeSource.shape`.
    /// Emits `MLNShapeCollection` when islands exist, or `MLNPolygon` when no islands are present.
    public var compositeShape: MLNShape {
        if islandPolygons.isEmpty {
            return worldMaskPolygon
        } else {
            return MLNShapeCollection(shapes: [worldMaskPolygon] + islandPolygons)
        }
    }
    
    /// Combined composite shape wrapped in a newly initialized `MLNShapeCollectionFeature`.
    /// Guaranteeing distinct object identity to invalidate MapLibre C++ GPU tessellation cache.
    public var compositeShapeFeature: MLNShapeCollectionFeature {
        let allShapes: [MLNShape & MLNFeature] = [worldMaskPolygon] + islandPolygons
        return MLNShapeCollectionFeature(shapes: allShapes)
    }
}

/// Spatial math utilities for dissolving H3 hex collections and generating optimized MapLibre fog shapes.
public enum FogPolygonMath {
    
    // MARK: - Global World Fog Mask Bounds (Wave M.5.1)
    
    /// Web Mercator upper projection latitude limit (EPSG:3857).
    public static let worldMaxLatitude: Double = 85.0511
    /// Web Mercator lower projection latitude limit (EPSG:3857).
    public static let worldMinLatitude: Double = -85.0511
    /// Web Mercator western longitude boundary with 0.001 deg buffer to avoid antimeridian wrapping singularities.
    public static let worldMinLongitude: Double = -179.999
    /// Web Mercator eastern longitude boundary with 0.001 deg buffer to avoid antimeridian wrapping singularities.
    public static let worldMaxLongitude: Double = 179.999
    
    /// Generates the Global World Fog Mask outer polygon coordinates with optional sub-pixel jitter.
    /// Preserves strict Clockwise (CW) winding order required by MapLibre Native:
    /// Top-Left -> Top-Right -> Bottom-Right -> Bottom-Left -> Top-Left (closed).
    public static func makeWorldBounds(jitter: Double = 0.0) -> [CLLocationCoordinate2D] {
        [
            CLLocationCoordinate2D(latitude: worldMaxLatitude + jitter, longitude: worldMinLongitude - jitter), // Top Left
            CLLocationCoordinate2D(latitude: worldMaxLatitude, longitude: worldMaxLongitude),                  // Top Right
            CLLocationCoordinate2D(latitude: worldMinLatitude, longitude: worldMaxLongitude),                  // Bottom Right
            CLLocationCoordinate2D(latitude: worldMinLatitude, longitude: worldMinLongitude),                  // Bottom Left
            CLLocationCoordinate2D(latitude: worldMaxLatitude + jitter, longitude: worldMinLongitude - jitter)   // Top Left (closed)
        ]
    }
    
    /// Generates the standard global world fog mask bounding box coordinates with optional sub-pixel jitter.
    public static func makeDefaultBounds(jitter: Double = 0.0) -> [CLLocationCoordinate2D] {
        makeWorldBounds(jitter: jitter)
    }
    
    /// Generates bounding box coordinates for a specific CityBounds with optional sub-pixel jitter.
    /// Preserves strict Clockwise (CW) winding order required by MapLibre Native.
    public static func makeBounds(for bounds: CityBounds, jitter: Double = 0.0) -> [CLLocationCoordinate2D] {
        [
            CLLocationCoordinate2D(latitude: bounds.maxLatitude + jitter, longitude: bounds.minLongitude - jitter), // Top Left
            CLLocationCoordinate2D(latitude: bounds.maxLatitude, longitude: bounds.maxLongitude),                  // Top Right
            CLLocationCoordinate2D(latitude: bounds.minLatitude, longitude: bounds.maxLongitude),                  // Bottom Right
            CLLocationCoordinate2D(latitude: bounds.minLatitude, longitude: bounds.minLongitude),                  // Bottom Left
            CLLocationCoordinate2D(latitude: bounds.maxLatitude + jitter, longitude: bounds.minLongitude - jitter)   // Top Left (closed)
        ]
    }
    
    /// Generates bounding box coordinates for a specific CityConfig with optional sub-pixel jitter.
    public static func makeBounds(for config: CityConfig, jitter: Double = 0.0) -> [CLLocationCoordinate2D] {
        makeBounds(for: config.bounds, jitter: jitter)
    }
    
    /// Calculates the signed area of a 2D coordinate loop using the Shoelace formula.
    /// A positive value indicates Clockwise (CW) winding order in geographic Lat/Lng space.
    public static func shoelaceSignedArea(_ coords: [CLLocationCoordinate2D]) -> Double {
        guard coords.count >= 3 else { return 0.0 }
        var sum: Double = 0.0
        for i in 0..<(coords.count - 1) {
            let p1 = coords[i]
            let p2 = coords[i + 1]
            sum += (p2.longitude - p1.longitude) * (p2.latitude + p1.latitude)
        }
        return sum
    }
    
    /// Enforces the specified winding order (Clockwise or Counter-Clockwise) on a coordinate array.
    public static func enforceWindingOrder(_ coords: [CLLocationCoordinate2D], targetClockwise: Bool) -> [CLLocationCoordinate2D] {
        guard coords.count >= 3 else { return coords }
        let area = shoelaceSignedArea(coords)
        let isClockwise = area > 0
        if isClockwise != targetClockwise {
            return coords.reversed()
        }
        return coords
    }
    
    /// Dissolves a set of H3 hexadecimal strings into a `FogGeometry` containing the world mask with cutouts and unvisited fog islands.
    public static func dissolveHexesToFogGeometry(hexes: Set<String>, bounds: [CLLocationCoordinate2D]? = nil) -> FogGeometry {
        let targetBounds = bounds ?? makeWorldBounds()
        guard !hexes.isEmpty else {
            let emptyWorld = MLNPolygonFeature(coordinates: targetBounds, count: UInt(targetBounds.count))
            return FogGeometry(worldMaskPolygon: emptyWorld, islandPolygons: [])
        }
        
        let cells: [UInt64] = hexes.compactMap { UInt64($0, radix: 16) }
        guard !cells.isEmpty else {
            let emptyWorld = MLNPolygonFeature(coordinates: targetBounds, count: UInt(targetBounds.count))
            return FogGeometry(worldMaskPolygon: emptyWorld, islandPolygons: [])
        }
        
        return dissolveCellsToFogGeometry(cells: cells, bounds: targetBounds)
    }
    
    /// Dissolves an array of `UInt64` H3 cell indices into a `FogGeometry` containing the world mask with cutouts and unvisited fog islands.
    public static func dissolveCellsToFogGeometry(cells: [UInt64], bounds: [CLLocationCoordinate2D]? = nil) -> FogGeometry {
        let targetBounds = bounds ?? makeWorldBounds()
        guard !cells.isEmpty else {
            let emptyWorld = MLNPolygonFeature(coordinates: targetBounds, count: UInt(targetBounds.count))
            return FogGeometry(worldMaskPolygon: emptyWorld, islandPolygons: [])
        }
        
        var polygon = LinkedGeoPolygon()
        let err = cells.withUnsafeBufferPointer { buf in
            CH3.cellsToLinkedMultiPolygon(buf.baseAddress, Int32(cells.count), &polygon)
        }
        
        guard err == 0 else {
            print("⚠️ [FogPolygonMath] cellsToLinkedMultiPolygon failed with error code: \(err)")
            let emptyWorld = MLNPolygonFeature(coordinates: targetBounds, count: UInt(targetBounds.count))
            return FogGeometry(worldMaskPolygon: emptyWorld, islandPolygons: [])
        }
        
        defer {
            withUnsafeMutablePointer(to: &polygon) { ptr in
                CH3.destroyLinkedMultiPolygon(ptr)
            }
        }
        
        var holePolygons: [MLNPolygon] = []
        var islandPolygons: [MLNPolygonFeature] = []
        var currentPolyPtr: UnsafeMutablePointer<LinkedGeoPolygon>? = withUnsafeMutablePointer(to: &polygon) { $0 }
        
        while let currentPoly = currentPolyPtr {
            var currentLoopPtr = currentPoly.pointee.first
            var isOuterLoop = true
            
            while let loopPtr = currentLoopPtr {
                var coords: [CLLocationCoordinate2D] = []
                var vertexPtr = loopPtr.pointee.first
                
                while let v = vertexPtr {
                    let latDeg = CH3.radsToDegs(v.pointee.vertex.lat)
                    let lngDeg = CH3.radsToDegs(v.pointee.vertex.lng)
                    coords.append(CLLocationCoordinate2D(latitude: latDeg, longitude: lngDeg))
                    vertexPtr = v.pointee.next
                }
                
                if !coords.isEmpty {
                    // Close ring if necessary
                    if coords.first?.latitude != coords.last?.latitude || coords.first?.longitude != coords.last?.longitude {
                        if let first = coords.first {
                            coords.append(first)
                        }
                    }
                    
                    if coords.count >= 4 {
                        if isOuterLoop {
                            // Explored Corridor Exterior Boundary (Hole in World Box)
                            // MUST be Clockwise (CW) for MapLibre interior hole convention (positive shoelace sum)
                            let cwCoords = enforceWindingOrder(coords, targetClockwise: true)
                            holePolygons.append(MLNPolygon(coordinates: cwCoords, count: UInt(cwCoords.count)))
                            isOuterLoop = false
                        } else {
                            // Unvisited Island Interior Boundary (Positive Fog Island)
                            // Standalone positive polygon exterior shell MUST be Clockwise (CW) for MapLibre
                            let cwCoords = enforceWindingOrder(coords, targetClockwise: true)
                            islandPolygons.append(MLNPolygonFeature(coordinates: cwCoords, count: UInt(cwCoords.count)))
                        }
                    }
                }
                
                currentLoopPtr = loopPtr.pointee.next
            }
            
            currentPolyPtr = currentPoly.pointee.next
        }
        
        let worldMask = (MLNPolygonFeature.self as MLNPolygon.Type).init(
            coordinates: targetBounds,
            count: UInt(targetBounds.count),
            interiorPolygons: holePolygons.isEmpty ? nil : holePolygons
        ) as! MLNPolygonFeature
        
        return FogGeometry(worldMaskPolygon: worldMask, islandPolygons: islandPolygons)
    }
    
    /// Dissolves a set of H3 hexadecimal strings into a list of closed `MLNPolygon` interior cutout rings.
    public static func dissolveHexesToInteriorPolygons(hexes: Set<String>) -> [MLNPolygon] {
        let dummyBounds = makeWorldBounds()
        let geom = dissolveHexesToFogGeometry(hexes: hexes, bounds: dummyBounds)
        return geom.worldMaskPolygon.interiorPolygons ?? []
    }
    
    /// Dissolves an array of `UInt64` H3 cell indices into a list of closed `MLNPolygon` interior cutout rings.
    public static func dissolveCellsToInteriorPolygons(cells: [UInt64]) -> [MLNPolygon] {
        let dummyBounds = makeWorldBounds()
        let geom = dissolveCellsToFogGeometry(cells: cells, bounds: dummyBounds)
        return geom.worldMaskPolygon.interiorPolygons ?? []
    }
    
    /// Generates a complete fog `MLNPolygon` spanning the global world bounds with dissolved interior holes.
    public static func generateFogPolygon(hexes: Set<String>, jitter: Double = 0.0) -> MLNPolygon {
        let bounds = makeWorldBounds(jitter: jitter)
        let geom = dissolveHexesToFogGeometry(hexes: hexes, bounds: bounds)
        return geom.worldMaskPolygon
    }
    
    /// Generates a complete fog `MLNPolygon` spanning the specified city's bounding box with dissolved interior holes.
    public static func generateFogPolygon(hexes: Set<String>, config: CityConfig, jitter: Double = 0.0) -> MLNPolygon {
        let bounds = makeBounds(for: config.bounds, jitter: jitter)
        let geom = dissolveHexesToFogGeometry(hexes: hexes, bounds: bounds)
        return geom.worldMaskPolygon
    }
    
    /// Generates a complete composite fog `MLNShape` (including interior unvisited islands) spanning the global world bounds.
    public static func generateFogShape(hexes: Set<String>, jitter: Double = 0.0) -> MLNShape {
        let bounds = makeWorldBounds(jitter: jitter)
        let geom = dissolveHexesToFogGeometry(hexes: hexes, bounds: bounds)
        return geom.compositeShape
    }
    
    /// Generates a complete composite fog `MLNShape` (including interior unvisited islands) spanning the specified city's bounding box.
    public static func generateFogShape(hexes: Set<String>, config: CityConfig, jitter: Double = 0.0) -> MLNShape {
        let bounds = makeBounds(for: config.bounds, jitter: jitter)
        let geom = dissolveHexesToFogGeometry(hexes: hexes, bounds: bounds)
        return geom.compositeShape
    }
    
    /// Generates an initial baseline global world fog shape feature with zero explored holes.
    /// Allocates fresh coordinate arrays and a new `MLNShapeCollectionFeature` to reset GPU mesh cache.
    public static func makeInitialFogShapeFeature(jitter: Double = 0.0) -> MLNShapeCollectionFeature {
        let bounds = makeWorldBounds(jitter: jitter)
        let worldMask = MLNPolygonFeature(coordinates: bounds, count: UInt(bounds.count))
        return MLNShapeCollectionFeature(shapes: [worldMask])
    }
    
    /// Generates an initial baseline fog shape feature for a specific city config with zero explored holes.
    /// Allocates fresh coordinate arrays and a new `MLNShapeCollectionFeature` to reset GPU mesh cache.
    public static func makeInitialFogShapeFeature(for config: CityConfig, jitter: Double = 0.0) -> MLNShapeCollectionFeature {
        makeInitialFogShapeFeature(jitter: jitter)
    }
    
    /// Generates a complete composite fog `MLNShapeCollectionFeature` spanning the global world bounds.
    /// Ensures newly allocated `MLNShapeCollectionFeature` with fresh coordinate arrays for MapLibre cache invalidation.
    public static func generateFogShapeFeature(hexes: Set<String>, jitter: Double = 0.0) -> MLNShapeCollectionFeature {
        let bounds = makeWorldBounds(jitter: jitter)
        let geom = dissolveHexesToFogGeometry(hexes: hexes, bounds: bounds)
        return geom.compositeShapeFeature
    }
    
    /// Generates a complete composite fog `MLNShapeCollectionFeature` spanning the specified city's bounding box.
    /// Ensures newly allocated `MLNShapeCollectionFeature` with fresh coordinate arrays for MapLibre cache invalidation.
    public static func generateFogShapeFeature(hexes: Set<String>, config: CityConfig, jitter: Double = 0.0) -> MLNShapeCollectionFeature {
        generateFogShapeFeature(hexes: hexes, jitter: jitter)
    }
}
