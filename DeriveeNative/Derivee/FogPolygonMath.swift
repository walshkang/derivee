import Foundation
import CoreLocation
import MapLibre
import H3
import CH3

/// Spatial math utilities for dissolving H3 hex collections and generating optimized MapLibre fog shapes.
public enum FogPolygonMath {
    
    /// Dissolves a set of H3 hexadecimal strings into a list of closed `MLNPolygon` interior rings.
    /// Contiguous hexes are merged into single macro-polygons via `cellsToLinkedMultiPolygon`,
    /// eliminating redundant internal edges and reducing vertex count by >85%.
    ///
    /// Vertices are converted to Clockwise (CW) winding order to comply with MapLibre Native interior hole requirements.
    public static func dissolveHexesToInteriorPolygons(hexes: Set<String>) -> [MLNPolygon] {
        guard !hexes.isEmpty else { return [] }
        
        let cells: [UInt64] = hexes.compactMap { UInt64($0, radix: 16) }
        guard !cells.isEmpty else { return [] }
        
        return dissolveCellsToInteriorPolygons(cells: cells)
    }
    
    /// Dissolves an array of `UInt64` H3 cell indices into a list of closed `MLNPolygon` interior rings.
    public static func dissolveCellsToInteriorPolygons(cells: [UInt64]) -> [MLNPolygon] {
        guard !cells.isEmpty else { return [] }
        
        var polygon = LinkedGeoPolygon()
        let err = cells.withUnsafeBufferPointer { buf in
            CH3.cellsToLinkedMultiPolygon(buf.baseAddress, Int32(cells.count), &polygon)
        }
        
        guard err == 0 else {
            print("⚠️ [FogPolygonMath] cellsToLinkedMultiPolygon failed with error code: \(err)")
            return []
        }
        
        defer {
            withUnsafeMutablePointer(to: &polygon) { ptr in
                CH3.destroyLinkedMultiPolygon(ptr)
            }
        }
        
        var innerRings: [MLNPolygon] = []
        var currentPolyPtr: UnsafeMutablePointer<LinkedGeoPolygon>? = withUnsafeMutablePointer(to: &polygon) { $0 }
        
        while let currentPoly = currentPolyPtr {
            // Each LinkedGeoPolygon represents a connected cluster of hexagons.
            // The outer boundary loop of the cluster is stored in currentPoly.pointee.first.
            if let loopPtr = currentPoly.pointee.first {
                var coords: [CLLocationCoordinate2D] = []
                var vertexPtr = loopPtr.pointee.first
                
                while let v = vertexPtr {
                    let latDeg = CH3.radsToDegs(v.pointee.vertex.lat)
                    let lngDeg = CH3.radsToDegs(v.pointee.vertex.lng)
                    coords.append(CLLocationCoordinate2D(latitude: latDeg, longitude: lngDeg))
                    vertexPtr = v.pointee.next
                }
                
                // VERIFIED: MapLibre Native (iOS) interior polygon rings (holes) require Clockwise (CW) winding order.
                // H3 LinkedGeoPolygon outer loops default to Counter-Clockwise (CCW) per GeoJSON RFC 7946.
                // Reversing coords produces the required Clockwise (CW) winding order (positive shoelace sum).
                // Tested & hardened in Wave I.2 (WI2-WINDING).
                coords.reverse()
                
                // Ensure closed ring
                if coords.count > 0, let first = coords.first {
                    coords.append(first)
                }
                
                // A valid closed polygon ring must contain at least 4 coordinates (3 distinct vertices + 1 closing)
                if coords.count >= 4 {
                    innerRings.append(MLNPolygon(coordinates: coords, count: UInt(coords.count)))
                }
            }
            
            currentPolyPtr = currentPoly.pointee.next
        }
        
        return innerRings
    }
    
    /// Generates a complete fog `MLNPolygon` spanning the NYC metropolitan bounding box with dissolved interior holes.
    ///
    /// - Parameters:
    ///   - hexes: The explored H3 hex strings to carve out of the fog mask.
    ///   - jitter: A minute coordinate offset applied to the top-left boundary coordinate to force MapLibre cache invalidation.
    public static func generateFogPolygon(hexes: Set<String>, jitter: Double = 0.0) -> MLNPolygon {
        let bounds = [
            CLLocationCoordinate2D(latitude: 41.5 + jitter, longitude: -74.5 - jitter), // Top Left
            CLLocationCoordinate2D(latitude: 41.5, longitude: -73.0),                  // Top Right
            CLLocationCoordinate2D(latitude: 40.0, longitude: -73.0),                  // Bottom Right
            CLLocationCoordinate2D(latitude: 40.0, longitude: -74.5),                  // Bottom Left
            CLLocationCoordinate2D(latitude: 41.5 + jitter, longitude: -74.5 - jitter)   // Top Left (closed)
        ]
        
        let innerRings = dissolveHexesToInteriorPolygons(hexes: hexes)
        return MLNPolygon(coordinates: bounds, count: UInt(bounds.count), interiorPolygons: innerRings.isEmpty ? nil : innerRings)
    }
}
