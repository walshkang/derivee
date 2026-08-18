import SwiftUI
import CoreLocation

/// Floating frosted-glass Quick Lens Capsule for on-demand nearby bus discovery (Wave J.6)
struct NearbyBusesCapsule: View {
    let busStops: [SpatialDatabaseManager.NearbyBusStop]
    let isLoading: Bool
    let hasLocation: Bool
    let onSelectStop: (SpatialDatabaseManager.NearbyBusStop) -> Void
    let onRefresh: () -> Void
    
    @State private var isExpanded: Bool = false
    @Environment(\.colorScheme) private var colorScheme
    
    init(
        busStops: [SpatialDatabaseManager.NearbyBusStop],
        isLoading: Bool = false,
        hasLocation: Bool = true,
        onSelectStop: @escaping (SpatialDatabaseManager.NearbyBusStop) -> Void,
        onRefresh: @escaping () -> Void
    ) {
        self.busStops = busStops
        self.isLoading = isLoading
        self.hasLocation = hasLocation
        self.onSelectStop = onSelectStop
        self.onRefresh = onRefresh
    }
    
    public var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            if isExpanded {
                // Expanded Quick Card of nearby bus stops
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Image(systemName: "bus.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(Color(hex: "#00A1DE"))
                        
                        Text("BUSES NEARBY (400M)")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        Button {
                            onRefresh()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.secondary)
                                .rotationEffect(.degrees(isLoading ? 360 : 0))
                                .animation(isLoading ? Animation.linear(duration: 1).repeatForever(autoreverses: false) : .default, value: isLoading)
                        }
                    }
                    
                    if busStops.isEmpty {
                        let statusText: String = {
                            if !hasLocation {
                                return "Acquiring GPS position..."
                            } else if isLoading {
                                return "Scanning stops nearby..."
                            } else {
                                return "No MTA bus stops found within 400m"
                            }
                        }()
                        Text(statusText)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.vertical, 4)
                    } else {
                        ForEach(busStops.prefix(3)) { stop in
                            Button {
                                onSelectStop(stop)
                            } label: {
                                HStack(spacing: 8) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(stop.name)
                                            .font(.subheadline)
                                            .fontWeight(.semibold)
                                            .foregroundColor(.primary)
                                            .lineLimit(1)
                                        
                                        HStack(spacing: 4) {
                                            ForEach(stop.routes.prefix(2), id: \.self) { route in
                                                Text(route)
                                                    .font(.system(size: 10, weight: .bold, design: .rounded))
                                                    .padding(.horizontal, 5)
                                                    .padding(.vertical, 1)
                                                    .background(Color(hex: "#00A1DE").opacity(0.15))
                                                    .foregroundColor(Color(hex: "#00A1DE"))
                                                    .clipShape(Capsule())
                                            }
                                            
                                            Text("• \(Int(round(stop.distanceMeters)))m")
                                                .font(.system(size: 11, design: .monospaced))
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    
                                    Spacer()
                                    
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundColor(.secondary)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                }
                .padding(14)
                .frame(maxWidth: 300)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.2), radius: 10, x: 0, y: 4)
                .transition(.asymmetric(insertion: .scale(scale: 0.9).combined(with: .opacity), removal: .opacity))
            }
            
            // Primary Pill Button
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                    isExpanded.toggle()
                    if isExpanded && busStops.isEmpty {
                        onRefresh()
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "bus.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(Color(hex: "#00A1DE"))
                    
                    Text("Nearby Buses")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                    
                    if !busStops.isEmpty {
                        Text("\(busStops.count)")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color(hex: "#00A1DE"))
                            .clipShape(Capsule())
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.25), radius: 8, x: 0, y: 3)
            }
        }
    }
}
