import Foundation
import CoreGraphics
import CoreLocation
import MapLibre

public enum TransitHitTest {
    /// Standard Apple HIG minimum touch target size (44pt x 44pt)
    public static let targetSize: CGFloat = 44.0
    public static let targetRadius: CGFloat = targetSize / 2.0 // 22.0

    /// Computes the 44x44pt bounding box centered at the given screen tap point.
    public static func hitBox(for point: CGPoint) -> CGRect {
        CGRect(
            x: point.x - targetRadius,
            y: point.y - targetRadius,
            width: targetSize,
            height: targetSize
        )
    }

    /// Selects the closest feature to `point` from `features` based on screen-space Euclidean distance.
    /// Features without a valid non-empty "id" attribute are filtered out.
    public static func closestFeature(
        to point: CGPoint,
        among features: [MLNFeature],
        in mapView: MLNMapView
    ) -> MLNFeature? {
        closestFeature(
            to: point,
            among: features,
            coordinateConverter: { coordinate in
                mapView.convert(coordinate, toPointTo: mapView)
            }
        )
    }

    /// Pure coordinate-converter overload for fast deterministic unit testing without a live MLNMapView instance.
    public static func closestFeature(
        to point: CGPoint,
        among features: [MLNFeature],
        coordinateConverter: (CLLocationCoordinate2D) -> CGPoint
    ) -> MLNFeature? {
        var closest: MLNFeature?
        var minDistanceSquared: CGFloat = .infinity

        for feature in features {
            guard let id = feature.attributes["id"] as? String, !id.isEmpty else {
                continue
            }
            
            let screenPoint = coordinateConverter(feature.coordinate)
            let dx = screenPoint.x - point.x
            let dy = screenPoint.y - point.y
            let distSq = dx * dx + dy * dy

            if distSq < minDistanceSquared {
                minDistanceSquared = distSq
                closest = feature
            }
        }

        return closest
    }
}
