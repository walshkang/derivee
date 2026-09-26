import Foundation
import CoreLocation

/// Direct non-observational relay connecting 30Hz vehicle kinematic ticks
/// to MapView.Coordinator with ZERO SwiftUI view body re-evaluations.
@MainActor
public final class VehicleFrameRelay {
    public var handler: ((CLLocationCoordinate2D, Double) -> Void)? = nil
    
    public init() {}
    
    public func emit(coordinate: CLLocationCoordinate2D, bearing: Double) {
        handler?(coordinate, bearing)
    }
}
