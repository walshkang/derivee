import SwiftUI
import CoreLocation

/// Pinned directional vector chip rendered at the visible map perimeter when an inspected transit vehicle is off-screen (Pre-T.7).
/// Displays directional bearing, route badge, stops away, and ETA countdown.
/// Tapping the beacon smoothly flies the map camera to the vehicle.
public struct OffScreenVectorBeacon: View {
    public let beacon: OffScreenBeaconState
    public let onTap: () -> Void
    
    public init(beacon: OffScreenBeaconState, onTap: @escaping () -> Void) {
        self.beacon = beacon
        self.onTap = onTap
    }
    
    public var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                // Directional Pointer Arrow (rotated along screen track bearing)
                Image(systemName: "arrow.up")
                    .font(.system(size: 11, weight: .black))
                    .rotationEffect(Angle(radians: beacon.bearingRadians + .pi / 2))
                    .foregroundColor(Color(hex: "#FFB300"))
                
                // Route Badge
                TransitRouteBadge(routeId: beacon.routeId, size: .compact)
                
                // Imminence Metadata
                HStack(spacing: 3) {
                    if beacon.stopsAway > 0 {
                        Text("\(beacon.stopsAway) \(beacon.stopsAway == 1 ? "stop" : "stops")")
                            .font(.system(size: 11.5, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)
                    }
                    
                    if beacon.minutes >= 0 {
                        Text(beacon.minutes == 0 ? "• Boarding" : "• \(beacon.minutes)m")
                            .font(.system(size: 11.5, weight: .bold, design: .rounded))
                            .foregroundColor(Color(hex: "#FFB300"))
                    }
                }
                .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background {
                TransitSheetGlassBackground(cornerRadius: 16)
            }
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color(hex: "#FFB300").opacity(0.4),
                                Color.white.opacity(0.15)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.8
                    )
            )
            .shadow(color: Color.black.opacity(0.18), radius: 8, x: 0, y: 3)
        }
        .buttonStyle(.plain)
    }
}
