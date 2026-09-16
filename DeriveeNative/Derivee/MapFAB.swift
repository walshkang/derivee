import SwiftUI

struct RecenterFAB: View {
    let isCentered: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: {
            let impact = UIImpactFeedbackGenerator(style: .light)
            impact.impactOccurred()
            action()
        }) {
            Image(systemName: isCentered ? "location.fill" : "location")
                .font(.system(size: 20, weight: .medium))
                .foregroundColor(.primary)
                .frame(width: 50, height: 50)
                .background(.ultraThinMaterial)
                .clipShape(Circle())
                .shadow(color: Color.black.opacity(0.15), radius: 8, x: 0, y: 4)
        }
        .buttonStyle(FABButtonStyle())
    }
}

struct ProfileFAB: View {
    let action: () -> Void
    
    var body: some View {
        Button(action: {
            let impact = UIImpactFeedbackGenerator(style: .light)
            impact.impactOccurred()
            action()
        }) {
            ApertureMicroGlyph(size: 22, strokeWidth: 1.6)
                .frame(width: 50, height: 50)
                .background(.ultraThinMaterial)
                .clipShape(Circle())
                .shadow(color: Color.black.opacity(0.15), radius: 8, x: 0, y: 4)
        }
        .buttonStyle(FABButtonStyle())
    }
}

struct AmbientDriftFAB: View {
    let isTracking: Bool
    let action: () -> Void
    
    @State private var isPulsing = false
    
    var body: some View {
        Button(action: {
            let impact = UIImpactFeedbackGenerator(style: .light)
            impact.impactOccurred()
            action()
        }) {
            ZStack {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.system(size: 19, weight: .medium))
                    .foregroundColor(.primary)
                
                // Live Status Beacon Dot
                VStack {
                    HStack {
                        Spacer()
                        Circle()
                            .fill(isTracking ? Color(hex: "#FFB300") : Color.secondary.opacity(0.40))
                            .frame(width: 8, height: 8)
                            .overlay(
                                Circle()
                                    .stroke(isTracking ? Color(hex: "#FFB300").opacity(0.5) : Color.clear, lineWidth: 1.5)
                                    .scaleEffect(isPulsing && isTracking ? 1.7 : 1.0)
                                    .opacity(isPulsing && isTracking ? 0.0 : 0.8)
                            )
                            .shadow(color: isTracking ? Color(hex: "#FFB300").opacity(0.6) : Color.clear, radius: 3)
                    }
                    Spacer()
                }
                .padding(9)
            }
            .frame(width: 50, height: 50)
            .background(.ultraThinMaterial)
            .clipShape(Circle())
            .overlay(
                Circle()
                    .strokeBorder(Color.white.opacity(0.20), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.15), radius: 8, x: 0, y: 4)
        }
        .buttonStyle(FABButtonStyle())
        .accessibilityLabel("Ambient Drift: \(isTracking ? "Active" : "Paused"). Tap for Quick Controls")
        .onAppear {
            if isTracking {
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: false)) {
                    isPulsing = true
                }
            }
        }
        .onChange(of: isTracking) { _, newValue in
            if newValue {
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: false)) {
                    isPulsing = true
                }
            } else {
                isPulsing = false
            }
        }
    }
}

struct DriftStatusPill: View {
    let isTracking: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: {
            let impact = UIImpactFeedbackGenerator(style: .light)
            impact.impactOccurred()
            action()
        }) {
            HStack(spacing: 6) {
                Circle()
                    .fill(isTracking ? Color(hex: "#FFB300") : Color.secondary.opacity(0.40))
                    .frame(width: 7, height: 7)
                    .shadow(color: isTracking ? Color(hex: "#FFB300").opacity(0.6) : Color.clear, radius: 2)
                
                Text(isTracking ? "Drift Active" : "Drift Paused")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(.primary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(Color.white.opacity(0.20), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.12), radius: 6, x: 0, y: 3)
        }
        .buttonStyle(FABButtonStyle())
        .accessibilityLabel("Ambient Drift Status: \(isTracking ? "Active" : "Paused")")
    }
}

struct FABButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
            .animation(.interactiveSpring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
    }
}

#Preview {
    ZStack {
        Color.gray.ignoresSafeArea()
        
        VStack {
            ProfileFAB(action: {})
            Spacer()
            RecenterFAB(isCentered: false, action: {})
            RecenterFAB(isCentered: true, action: {})
        }
        .padding()
    }
}
