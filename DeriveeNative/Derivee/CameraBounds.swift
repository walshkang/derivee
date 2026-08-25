import Foundation
import CoreLocation
import MapLibre

public struct CameraBounds {
    public static var activeConfig: CityConfig = .nycDefault
    
    public static var minLatitude: Double { activeConfig.bounds.minLatitude }
    public static var maxLatitude: Double { activeConfig.bounds.maxLatitude }
    public static var minLongitude: Double { activeConfig.bounds.minLongitude }
    public static var maxLongitude: Double { activeConfig.bounds.maxLongitude }
    
    /// Maximum allowable elastic margin beyond the hard boundary during active gestures (~5 km)
    public static let rubberBandMargin: Double = 0.05
    
    /// Sets the active metropolitan configuration for camera clamping and bounds enforcement.
    public static func setActiveConfig(_ config: CityConfig) {
        activeConfig = config
    }
    
    /// Resets the active configuration back to the default NYC metropolitan envelope.
    public static func resetToDefault() {
        activeConfig = .nycDefault
    }
    
    /// Checks if a coordinate is strictly within the active fog boundary envelope.
    public static func isWithinBounds(_ coordinate: CLLocationCoordinate2D) -> Bool {
        return coordinate.latitude >= minLatitude &&
               coordinate.latitude <= maxLatitude &&
               coordinate.longitude >= minLongitude &&
               coordinate.longitude <= maxLongitude
    }
    
    /// Checks if a coordinate is within the extended rubber-band boundary limit.
    public static func isWithinRubberBandLimit(_ coordinate: CLLocationCoordinate2D, margin: Double = rubberBandMargin) -> Bool {
        return coordinate.latitude >= (minLatitude - margin) &&
               coordinate.latitude <= (maxLatitude + margin) &&
               coordinate.longitude >= (minLongitude - margin) &&
               coordinate.longitude <= (maxLongitude + margin)
    }
    
    /// Clamps a coordinate to the hard boundary envelope.
    public static func clampedCoordinate(for coordinate: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        let clampedLat = min(max(coordinate.latitude, minLatitude), maxLatitude)
        let clampedLon = min(max(coordinate.longitude, minLongitude), maxLongitude)
        return CLLocationCoordinate2D(latitude: clampedLat, longitude: clampedLon)
    }
    
    /// Determines whether the camera transition should be allowed by MapLibre delegate.
    public static func shouldAllowCameraChange(
        from oldCamera: MLNMapCamera,
        to newCamera: MLNMapCamera,
        reason: MLNCameraChangeReason,
        isRollingBack: Bool = false
    ) -> Bool {
        // Enforce strict 2D top-down view: reject tilt gestures and any pitched camera states
        if reason.contains(.gestureTilt) || newCamera.pitch > 0.001 {
            return false
        }
        
        // If an automated rollback is underway, always allow it to complete.
        if isRollingBack {
            return true
        }
        
        let targetCoord = newCamera.centerCoordinate
        
        // If inside the hard bounding box, allow movement unconditionally.
        if isWithinBounds(targetCoord) {
            return true
        }
        
        // If outside hard bounds, check if it's a gesture-driven movement
        let isGesture = reason.contains(.gesturePan) ||
                        reason.contains(.gesturePinch) ||
                        reason.contains(.gestureRotate) ||
                        reason.contains(.gestureZoomIn) ||
                        reason.contains(.gestureZoomOut)
        
        if isGesture {
            // Allow temporary rubber-band stretch as long as it does not exceed the elastic margin
            return isWithinRubberBandLimit(targetCoord)
        }
        
        // For programmatic movements or momentum outside bounds, allow up to rubber band limit
        return isWithinRubberBandLimit(targetCoord)
    }
}
