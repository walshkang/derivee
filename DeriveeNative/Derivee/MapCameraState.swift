import Foundation
import CoreLocation
import CoreGraphics
import MapLibre

/// High-precision, immutable camera state representation computed on the CPU using 64-bit floats.
/// Conforms to `Sendable` and `Equatable` for safe handoff between MapLibre gesture threads,
/// background tracking actors, and Metal render loops.
public struct MapCameraState: Sendable, Equatable {
    
    /// Geodetic center coordinate (WGS84) of the camera viewport.
    public let centerCoordinate: CLLocationCoordinate2D
    
    /// Continuous zoom scale factor (typically 0.0 to 22.0).
    public let zoomLevel: Double
    
    /// Clockwise camera rotation in degrees from True North [0, 360).
    public let bearing: Double
    
    /// Camera tilt angle in degrees from the ground plane [0, 60] (0.0 for 2D top-down).
    public let pitch: Double
    
    /// Vertical viewing angle of the perspective frustum in degrees (default 36.87°).
    public let fieldOfView: Double
    
    /// Viewport dimensions in logical screen points.
    public let viewportSize: CGSize
    
    /// Primary designated initializer.
    public init(
        centerCoordinate: CLLocationCoordinate2D,
        zoomLevel: Double,
        bearing: Double,
        pitch: Double = 0.0,
        fieldOfView: Double = 36.87,
        viewportSize: CGSize
    ) {
        self.centerCoordinate = centerCoordinate
        self.zoomLevel = zoomLevel
        self.bearing = bearing
        self.pitch = pitch
        self.fieldOfView = fieldOfView
        self.viewportSize = viewportSize
    }
    
    /// Convenience initializer extracting camera state directly from an active `MLNMapView`.
    @MainActor
    public init(mapView: MLNMapView) {
        self.init(
            centerCoordinate: mapView.centerCoordinate,
            zoomLevel: mapView.zoomLevel,
            bearing: mapView.direction,
            pitch: Double(mapView.camera.pitch),
            fieldOfView: 36.87,
            viewportSize: mapView.bounds.size
        )
    }
    
    /// Convenience initializer extracting camera state from a MapLibre custom style layer drawing context.
    public init(context: MLNStyleLayerDrawingContext) {
        self.init(
            centerCoordinate: context.centerCoordinate,
            zoomLevel: context.zoomLevel,
            bearing: context.direction,
            pitch: Double(context.pitch),
            fieldOfView: Double(context.fieldOfView),
            viewportSize: context.size
        )
    }
    
    // MARK: - Equatable
    
    public static func == (lhs: MapCameraState, rhs: MapCameraState) -> Bool {
        abs(lhs.centerCoordinate.latitude - rhs.centerCoordinate.latitude) < 1e-9 &&
        abs(lhs.centerCoordinate.longitude - rhs.centerCoordinate.longitude) < 1e-9 &&
        abs(lhs.zoomLevel - rhs.zoomLevel) < 1e-7 &&
        abs(lhs.bearing - rhs.bearing) < 1e-6 &&
        abs(lhs.pitch - rhs.pitch) < 1e-6 &&
        abs(lhs.fieldOfView - rhs.fieldOfView) < 1e-6 &&
        abs(lhs.viewportSize.width - rhs.viewportSize.width) < 1e-4 &&
        abs(lhs.viewportSize.height - rhs.viewportSize.height) < 1e-4
    }
}
