import SwiftUI

/// 1-Tap Dynamic Recovery Card surfaced upon automated missed-connection detection (Wave N-D.8).
/// Presents the disruption event, recalculated primary alternative (e.g. next departure or micro-mobility fallback),
/// and secondary routes with lower-third thumb-zone action targets.
public struct DynamicRecoveryCardView: View {
    public let plan: DynamicRecoveryPlan
    public var onAcceptOption: ((DynamicRecoveryOption) -> Void)?
    public var onDismiss: (() -> Void)?
    
    @State private var isShowingSecondaryOptions: Bool = false
    
    public init(
        plan: DynamicRecoveryPlan,
        onAcceptOption: ((DynamicRecoveryOption) -> Void)? = nil,
        onDismiss: (() -> Void)? = nil
    ) {
        self.plan = plan
        self.onAcceptOption = onAcceptOption
        self.onDismiss = onDismiss
    }
    
    public var body: some View {
        VStack(spacing: 12) {
            // Header Bar: Disruption Warning & Dismiss
            HStack(alignment: .top, spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Color(hex: "#FFB300").opacity(0.18))
                        .frame(width: 32, height: 32)
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(Color(hex: "#B45309"))
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Missed Connection: \(plan.event.stationName)")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(Color(hex: "#0F172A"))
                    
                    Text("Vehicle departed • Instant alternatives ready")
                        .font(.system(size: 12.5, weight: .medium, design: .rounded))
                        .foregroundColor(Color(hex: "#64748B"))
                }
                
                Spacer()
                
                Button {
                    onDismiss?()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(Color.secondary.opacity(0.4))
                }
                .buttonStyle(.plain)
            }
            
            // Primary Recommended Option Tile
            primaryOptionCard(plan.primaryOption)
            
            // Secondary Alternatives Section
            if plan.options.count > 1 {
                secondaryOptionsSection
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color(hex: "#FFB300").opacity(0.5), lineWidth: 1.5)
                )
                .shadow(color: Color.black.opacity(0.06), radius: 10, x: 0, y: 4)
        )
    }
    
    // MARK: - Primary Option Card
    
    @ViewBuilder
    private func primaryOptionCard(_ option: DynamicRecoveryOption) -> some View {
        VStack(spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                // Route Bullet / Mode Icon
                ZStack {
                    Circle()
                        .fill(Color(hex: option.routeColorHex ?? "#FFB300"))
                        .frame(width: 36, height: 36)
                    
                    if let badge = option.routeBadge, !badge.isEmpty {
                        Text(badge)
                            .font(.system(size: 16, weight: .heavy, design: .rounded))
                            .foregroundColor(.white)
                    } else {
                        Image(systemName: option.type.iconSystemName)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(option.title)
                            .font(.system(size: 14.5, weight: .bold, design: .rounded))
                            .foregroundColor(Color(hex: "#0F172A"))
                        
                        Text("Recommended")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color(hex: "#FFB300").opacity(0.2))
                            .clipShape(Capsule())
                            .foregroundColor(Color(hex: "#B45309"))
                    }
                    
                    Text(option.subtitle)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                // Arrival Delta Pill
                VStack(alignment: .trailing, spacing: 2) {
                    Text(option.formattedDelta)
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundColor(option.deltaMinutes <= 0 ? Color(hex: "#059669") : Color(hex: "#B45309"))
                    
                    Text(option.formattedArrival)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }
            
            // 1-Tap Lower-Third Primary Action Button (52pt thumb zone target)
            Button {
                onAcceptOption?(option)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 15, weight: .bold))
                    Text("Accept Alternative (\(option.formattedDelta))")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                }
                .foregroundColor(Color(hex: "#0F172A"))
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(Color(hex: "#FFB300"))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(color: Color(hex: "#FFB300").opacity(0.3), radius: 6, x: 0, y: 3)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(Color(hex: "#F9F9F6"))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
    
    // MARK: - Secondary Options Section
    
    @ViewBuilder
    private var secondaryOptionsSection: some View {
        let secondaryList = plan.options.filter { !$0.isPrimaryRecommended }
        
        VStack(spacing: 8) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    isShowingSecondaryOptions.toggle()
                }
            } label: {
                HStack {
                    Text(isShowingSecondaryOptions ? "Hide Other Alternatives" : "Show \(secondaryList.count) Other Alternatives")
                        .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                        .foregroundColor(.secondary)
                    
                    Image(systemName: isShowingSecondaryOptions ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
            
            if isShowingSecondaryOptions {
                VStack(spacing: 8) {
                    ForEach(secondaryList) { secOption in
                        HStack(spacing: 10) {
                            Image(systemName: secOption.type.iconSystemName)
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(Color(hex: "#0F172A"))
                                .frame(width: 24)
                            
                            VStack(alignment: .leading, spacing: 1) {
                                Text(secOption.title)
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                                    .foregroundColor(Color(hex: "#0F172A"))
                                
                                Text(secOption.subtitle)
                                    .font(.system(size: 11.5, weight: .medium, design: .rounded))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                            
                            Spacer()
                            
                            Button {
                                onAcceptOption?(secOption)
                            } label: {
                                Text("Switch")
                                    .font(.system(size: 12, weight: .bold, design: .rounded))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Color(hex: "#0F172A"))
                                    .foregroundColor(.white)
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(10)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(Color.secondary.opacity(0.15), lineWidth: 1)
                        )
                    }
                }
            }
        }
    }
}
