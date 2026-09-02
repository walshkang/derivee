import SwiftUI

/// Horizontal multi-profile selector supporting diverse commuter mental models.
/// Includes spring animations, Electric Amber accents, and light tactile haptic feedback.
public struct MultiProfileSelectorBar: View {
    @Binding public var selectedProfile: RoutingProfile
    public var onProfileChanged: ((RoutingProfile) -> Void)?
    
    @Namespace private var profileNamespace
    
    public init(
        selectedProfile: Binding<RoutingProfile>,
        onProfileChanged: ((RoutingProfile) -> Void)? = nil
    ) {
        self._selectedProfile = selectedProfile
        self.onProfileChanged = onProfileChanged
    }
    
    public var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(RoutingProfile.allCases) { profile in
                    profilePill(for: profile)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }
    
    @ViewBuilder
    private func profilePill(for profile: RoutingProfile) -> some View {
        let isSelected = selectedProfile == profile
        
        Button {
            if selectedProfile != profile {
                let generator = UIImpactFeedbackGenerator(style: .light)
                generator.prepare()
                generator.impactOccurred()
                
                withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                    selectedProfile = profile
                }
                onProfileChanged?(profile)
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: profile.iconName)
                    .font(.system(size: 13, weight: isSelected ? .bold : .semibold))
                    .foregroundColor(isSelected ? Color(hex: "#1E293B") : Color.secondary)
                
                Text(profile.displayName)
                    .font(.system(size: 13.5, weight: isSelected ? .bold : .medium, design: .rounded))
                    .foregroundColor(isSelected ? Color(hex: "#0F172A") : Color.primary.opacity(0.8))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(minHeight: 44)
            .background(
                ZStack {
                    if isSelected {
                        Capsule()
                            .fill(Color(hex: "#FFB300"))
                            .matchedGeometryEffect(id: "ActiveProfileBackground", in: profileNamespace)
                            .shadow(color: Color(hex: "#FFB300").opacity(0.35), radius: 6, x: 0, y: 2)
                    } else {
                        Capsule()
                            .fill(Color.primary.opacity(0.04))
                    }
                }
            )
            .overlay(
                Capsule()
                    .stroke(isSelected ? Color(hex: "#F59E0B") : Color.primary.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(profile.displayName) profile. \(profile.subtitle)")
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : [.isButton])
    }
}
