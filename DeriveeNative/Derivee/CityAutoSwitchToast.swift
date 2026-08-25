import SwiftUI

/// Top capsule toast displayed when Dérivée automatically switches to an installed city pack.
public struct CityAutoSwitchToast: View {
    public let cityName: String
    public var message: String? = nil
    public var onDismiss: () -> Void
    
    public init(cityName: String, message: String? = nil, onDismiss: @escaping () -> Void) {
        self.cityName = cityName
        self.message = message
        self.onDismiss = onDismiss
    }
    
    public var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color(hex: "#FFB300").opacity(0.2))
                    .frame(width: 32, height: 32)
                
                Image(systemName: "location.north.circle.fill")
                    .foregroundColor(Color(hex: "#FFB300"))
                    .font(.system(size: 18, weight: .bold))
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Active City Switched")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.5)
                
                Text(message ?? "Welcome to \(cityName) • Switched active city")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
            }
            
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .strokeBorder(Color.white.opacity(0.3), lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.12), radius: 12, x: 0, y: 6)
        .padding(.horizontal, 20)
        .gesture(
            DragGesture(minimumDistance: 15)
                .onEnded { value in
                    if value.translation.height < -15 {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            onDismiss()
                        }
                    }
                }
        )
        .onTapGesture {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                onDismiss()
            }
        }
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        VStack {
            CityAutoSwitchToast(cityName: "Boston") {
                print("Dismissed")
            }
            Spacer()
        }
        .padding(.top, 50)
    }
}
