import SwiftUI
import CoreLocation

/// Interactive dual-horizon focus switcher capsule docked in the transit run inspector (Pre-T.7).
/// Allows commuters to 1-tap glide between the oncoming consist and their departure platform
/// without changing the bottom sheet presentation detent.
/// Styled using the engineered 3-tier optical glass stack (Research Doc 18).
public struct TransitFocusSwitcherCapsule: View {
    public enum FocusHorizon: Sendable, Equatable {
        case train
        case station
    }
    
    public let stationName: String
    public let stationCoordinate: CLLocationCoordinate2D
    public let vehicleStopName: String?
    public let vehicleCoordinate: CLLocationCoordinate2D?
    public let etaMinutes: Int?
    public let onFocus: ((CLLocationCoordinate2D) -> Void)?
    
    @State private var activeHorizon: FocusHorizon = .train
    
    public init(
        stationName: String,
        stationCoordinate: CLLocationCoordinate2D,
        vehicleStopName: String? = nil,
        vehicleCoordinate: CLLocationCoordinate2D? = nil,
        etaMinutes: Int? = nil,
        initialHorizon: FocusHorizon = .train,
        onFocus: ((CLLocationCoordinate2D) -> Void)? = nil
    ) {
        self.stationName = stationName
        self.stationCoordinate = stationCoordinate
        self.vehicleStopName = vehicleStopName
        self.vehicleCoordinate = vehicleCoordinate
        self.etaMinutes = etaMinutes
        self._activeHorizon = State(initialValue: initialHorizon)
        self.onFocus = onFocus
    }
    
    public var body: some View {
        HStack(spacing: 4) {
            // Train Focus Segment
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    activeHorizon = .train
                }
                if let vCoord = vehicleCoordinate {
                    onFocus?(vCoord)
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "tram.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(activeHorizon == .train ? Color(hex: "#FFB300") : .secondary)
                    
                    Text("Train: \(vehicleStopName ?? "En Route")")
                        .font(.system(size: 12, weight: activeHorizon == .train ? .bold : .medium, design: .rounded))
                        .foregroundColor(activeHorizon == .train ? .primary : .secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    
                    if let minutes = etaMinutes, minutes >= 0 {
                        Text(minutes == 0 ? "(Boarding)" : "(\(minutes)m)")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundColor(Color(hex: "#FFB300"))
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(activeHorizon == .train ? Color(hex: "#FFB300").opacity(0.16) : Color.clear)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            
            // Subtle Divider
            Rectangle()
                .fill(Color.secondary.opacity(0.25))
                .frame(width: 1, height: 14)
            
            // Station Focus Segment
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    activeHorizon = .station
                }
                onFocus?(stationCoordinate)
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "mappin.circle.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(activeHorizon == .station ? Color(hex: "#FFB300") : .secondary)
                    
                    Text("Station: \(stationName)")
                        .font(.system(size: 12, weight: activeHorizon == .station ? .bold : .medium, design: .rounded))
                        .foregroundColor(activeHorizon == .station ? .primary : .secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(activeHorizon == .station ? Color(hex: "#FFB300").opacity(0.16) : Color.clear)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(3)
        .background {
            TransitSheetGlassBackground(cornerRadius: 18)
        }
        .clipShape(Capsule())
        .shadow(color: Color.black.opacity(0.08), radius: 6, x: 0, y: 2)
    }
}
