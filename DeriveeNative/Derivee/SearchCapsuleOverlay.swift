import SwiftUI

/// Floating frosted-glass quick search capsule overlay for Screen 1 (Wave PA.4 / design.md §12.2 / Guardrail G10).
/// Tapping opens Screen 4A place and station search.
public struct SearchCapsuleOverlay: View {
    public let action: () -> Void
    
    public init(action: @escaping () -> Void) {
        self.action = action
    }
    
    public var body: some View {
        Button(action: {
            let impact = UIImpactFeedbackGenerator(style: .light)
            impact.impactOccurred()
            action()
        }) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(Color(hex: "#FFB300"))
                
                Text("Where to?")
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)
                
                Spacer()
                
                HStack(spacing: 5) {
                    Image(systemName: "tram.fill")
                        .font(.system(size: 11, weight: .semibold))
                    Image(systemName: "bus.fill")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundColor(.secondary.opacity(0.45))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(height: 48)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(Color.white.opacity(0.20), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.14), radius: 8, x: 0, y: 4)
        }
        .buttonStyle(SearchCapsuleButtonStyle())
    }
}

public struct SearchCapsuleButtonStyle: ButtonStyle {
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.interactiveSpring(response: 0.2, dampingFraction: 0.65), value: configuration.isPressed)
            .opacity(configuration.isPressed ? 0.85 : 1.0)
    }
}

#Preview {
    ZStack {
        Color.gray.ignoresSafeArea()
        VStack {
            SearchCapsuleOverlay(action: {})
                .padding(.horizontal, 20)
                .padding(.top, 50)
            Spacer()
        }
    }
}
