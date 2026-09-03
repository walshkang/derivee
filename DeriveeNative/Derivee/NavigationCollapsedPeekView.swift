import SwiftUI

/// Glanceable collapsed peek banner rendered at the 15% bottom sheet detent (Wave N-D.5).
/// Displays next upcoming maneuver, route badge, egress/dock metadata, arrival countdown,
/// and a compact thumb action while preserving 85% screen real estate for the floating hero map.
public struct NavigationCollapsedPeekView: View {
    public let leg: JourneyLeg
    public let totalDurationFormatted: String
    public let arrivalTimeFormatted: String
    public var onExpandToHalf: (() -> Void)?
    public var onQuickAction: (() -> Void)?
    
    public init(
        leg: JourneyLeg,
        totalDurationFormatted: String,
        arrivalTimeFormatted: String,
        onExpandToHalf: (() -> Void)? = nil,
        onQuickAction: (() -> Void)? = nil
    ) {
        self.leg = leg
        self.totalDurationFormatted = totalDurationFormatted
        self.arrivalTimeFormatted = arrivalTimeFormatted
        self.onExpandToHalf = onExpandToHalf
        self.onQuickAction = onQuickAction
    }
    
    public var body: some View {
        Button {
            onExpandToHalf?()
        } label: {
            HStack(spacing: 12) {
                // Mode / Route Badge Node
                modeBadgeView
                
                // Maneuver Instructions & Secondary Metadata
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(instructionTitle)
                            .font(.system(size: 14.5, weight: .bold, design: .rounded))
                            .foregroundColor(Color(hex: "#0F172A"))
                            .lineLimit(1)
                        
                        Spacer()
                        
                        Text(arrivalTimeFormatted)
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundColor(Color(hex: "#B45309"))
                    }
                    
                    HStack(spacing: 6) {
                        if let anchor = leg.primaryLandmarkAnchor {
                            HStack(spacing: 4) {
                                Image(systemName: anchor.category.iconName)
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(Color(hex: "#059669"))
                                Text(anchor.landmarkName)
                                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                                    .foregroundColor(Color(hex: "#065F46"))
                            }
                            
                            Text("•")
                                .foregroundColor(.secondary)
                            
                            if anchor.isShaded, let shade = anchor.shadePercentage {
                                HStack(spacing: 3) {
                                    Image(systemName: "tree.fill")
                                        .font(.system(size: 9, weight: .bold))
                                    Text("\(Int(shade))% Shaded")
                                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                                }
                                .foregroundColor(Color(hex: "#047857"))
                            } else {
                                Text("\(leg.formattedDuration) • \(totalDurationFormatted) total")
                                    .font(.system(size: 11.5, weight: .medium, design: .rounded))
                                    .foregroundColor(.secondary)
                            }
                        } else if let cue = leg.landmarkCue {
                            Text(cue)
                                .font(.system(size: 11.5, weight: .medium, design: .rounded))
                                .foregroundColor(Color(hex: "#065F46"))
                                .lineLimit(1)
                        } else if let car = leg.recommendedCarPosition {
                            Text(car)
                                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                                .foregroundColor(Color(hex: "#92400E"))
                                .lineLimit(1)
                        } else if let exit = leg.exitCode {
                            Text(exit)
                                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                                .foregroundColor(Color(hex: "#1E40AF"))
                                .lineLimit(1)
                        } else if let meta = leg.bikeMetadata, meta.isEBike, let soc = meta.batterySocPercent {
                            HStack(spacing: 2) {
                                Image(systemName: "bolt.fill")
                                    .font(.system(size: 9, weight: .bold))
                                Text("\(soc)% battery")
                                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            }
                            .foregroundColor(Color(hex: "#0284C7"))
                        } else {
                            Text("\(leg.formattedDuration) • \(totalDurationFormatted) total")
                                .font(.system(size: 11.5, weight: .medium, design: .rounded))
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                    }
                }
                
                // Compact Right-Anchored Thumb Action / Expand Affordance
                if leg.mode == .bikeShare {
                    Button {
                        onQuickAction?()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "bicycle.circle.fill")
                                .font(.system(size: 11, weight: .bold))
                            Text("Unlock")
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(Color(hex: "#0284C7"))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                } else {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(Color.secondary.opacity(0.6))
                        .padding(8)
                        .background(Color.primary.opacity(0.05))
                        .clipShape(Circle())
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Instruction Title
    
    private var instructionTitle: String {
        switch leg.mode {
        case .walk:
            if let anchor = leg.primaryLandmarkAnchor {
                return anchor.prompt
            }
            return "Walk to \(leg.destinationName)"
        case .subway, .bus, .lightRail, .ferry:
            if let headsign = leg.headsign {
                return "Ride to \(headsign)"
            } else if let route = leg.routeId {
                return "Board \(route) at \(leg.originName)"
            } else {
                return "Board transit at \(leg.originName)"
            }
        case .bikeShare:
            return "Unlock bike at \(leg.originName)"
        case .personalBike:
            return "Ride to \(leg.destinationName)"
        }
    }
    
    // MARK: - Mode Badge
    
    @ViewBuilder
    private var modeBadgeView: some View {
        if let routeId = leg.routeId {
            TransitRouteBadge(routeId: routeId, lineInfo: leg.lineInfo, size: .regular)
        } else {
            ZStack {
                Circle()
                    .fill(badgeBackgroundColor)
                    .frame(width: 32, height: 32)
                
                Image(systemName: leg.mode.systemIcon)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(badgeForegroundColor)
            }
        }
    }
    
    private var badgeBackgroundColor: Color {
        switch leg.mode {
        case .walk: return Color.secondary.opacity(0.18)
        case .bikeShare, .personalBike: return Color(hex: "#0284C7").opacity(0.18)
        default: return Color(hex: "#FFB300").opacity(0.18)
        }
    }
    
    private var badgeForegroundColor: Color {
        switch leg.mode {
        case .walk: return Color(hex: "#0F172A")
        case .bikeShare, .personalBike: return Color(hex: "#0284C7")
        default: return Color(hex: "#D97706")
        }
    }
}
