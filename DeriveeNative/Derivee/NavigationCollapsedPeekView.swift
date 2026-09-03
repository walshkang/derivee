import SwiftUI

/// Glanceable collapsed peek banner rendered at the 15% bottom sheet detent (Wave N-D.5).
/// Displays next upcoming maneuver, route badge, egress/dock metadata, arrival countdown,
/// and a compact thumb action while preserving 85% screen real estate for the floating hero map.
public struct NavigationCollapsedPeekView: View {
    public let leg: JourneyLeg
    public let totalDurationFormatted: String
    public let arrivalTimeFormatted: String
    public var naturalCue: NaturalGuidanceCue?
    public var recoveryPlan: DynamicRecoveryPlan?
    public var onExpandToHalf: (() -> Void)?
    public var onQuickAction: (() -> Void)?
    public var onAcceptRecoveryOption: ((DynamicRecoveryOption) -> Void)?
    
    public init(
        leg: JourneyLeg,
        totalDurationFormatted: String,
        arrivalTimeFormatted: String,
        naturalCue: NaturalGuidanceCue? = nil,
        recoveryPlan: DynamicRecoveryPlan? = nil,
        onExpandToHalf: (() -> Void)? = nil,
        onQuickAction: (() -> Void)? = nil,
        onAcceptRecoveryOption: ((DynamicRecoveryOption) -> Void)? = nil
    ) {
        self.leg = leg
        self.totalDurationFormatted = totalDurationFormatted
        self.arrivalTimeFormatted = arrivalTimeFormatted
        self.naturalCue = naturalCue
        self.recoveryPlan = recoveryPlan
        self.onExpandToHalf = onExpandToHalf
        self.onQuickAction = onQuickAction
        self.onAcceptRecoveryOption = onAcceptRecoveryOption
    }
    
    public var body: some View {
        if let plan = recoveryPlan {
            recoveryPeekView(plan)
        } else {
            standardPeekView
        }
    }
    
    // MARK: - Recovery Alert Peek View
    
    @ViewBuilder
    private func recoveryPeekView(_ plan: DynamicRecoveryPlan) -> some View {
        Button {
            onExpandToHalf?()
        } label: {
            HStack(spacing: 12) {
                // Amber Warning Icon
                ZStack {
                    Circle()
                        .fill(Color(hex: "#FFB300").opacity(0.2))
                        .frame(width: 36, height: 36)
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(Color(hex: "#B45309"))
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("Missed Connection")
                            .font(.system(size: 14.5, weight: .bold, design: .rounded))
                            .foregroundColor(Color(hex: "#0F172A"))
                        
                        Text(plan.primaryOption.formattedDelta)
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(Color(hex: "#B45309"))
                    }
                    
                    Text(plan.primaryOption.title)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(Color(hex: "#64748B"))
                        .lineLimit(1)
                }
                
                Spacer()
                
                // 1-Tap Reroute Button
                Button {
                    let generator = UIImpactFeedbackGenerator(style: .heavy)
                    generator.prepare()
                    generator.impactOccurred()
                    onAcceptRecoveryOption?(plan.primaryOption)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 12, weight: .bold))
                        Text("Reroute")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                    }
                    .foregroundColor(Color(hex: "#0F172A"))
                    .padding(.horizontal, 12)
                    .frame(minWidth: 80, minHeight: 44)
                    .background(Color(hex: "#FFB300"))
                    .clipShape(Capsule())
                    .shadow(color: Color(hex: "#FFB300").opacity(0.3), radius: 4, x: 0, y: 2)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Standard Peek View
    
    @ViewBuilder
    private var standardPeekView: some View {
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
                        
                        if let cue = naturalCue, let badge = cue.promptBadgeText {
                            HStack(spacing: 3) {
                                if cue.intersectionControl == .trafficSignal && cue.decisionZone == .approach {
                                    Image(systemName: "light.beacon.max.fill")
                                        .font(.system(size: 8, weight: .bold))
                                }
                                Text(badge)
                                    .font(.system(size: 10, weight: .bold, design: .rounded))
                            }
                            .foregroundColor(badgeTextColor(for: cue))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(badgeBgColor(for: cue))
                            .clipShape(Capsule())
                        }
                        
                        Spacer()
                        
                        Text(arrivalTimeFormatted)
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundColor(Color(hex: "#B45309"))
                    }
                    
                    HStack(spacing: 6) {
                        if let cue = naturalCue {
                            Text(cue.secondaryContext)
                                .font(.system(size: 11.5, weight: .medium, design: .rounded))
                                .foregroundColor(Color(hex: "#065F46"))
                                .lineLimit(1)
                        } else if let anchor = leg.primaryLandmarkAnchor {
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
                        } else if let meta = leg.bikeMetadata {
                            HStack(spacing: 6) {
                                DockAvailabilityBadgeView(
                                    availableDocks: meta.availableDocksAtDest,
                                    isCompact: true
                                )
                                if meta.isEBike, let soc = meta.batterySocPercent {
                                    EBikeBatterySOCPill(
                                        batterySocPercent: soc,
                                        estimatedRangeMiles: meta.estimatedRangeMiles
                                    )
                                }
                            }
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
                        let generator = UIImpactFeedbackGenerator(style: .heavy)
                        generator.prepare()
                        generator.impactOccurred()
                        onQuickAction?()
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "bicycle.circle.fill")
                                .font(.system(size: 13, weight: .bold))
                            Text("Unlock")
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .frame(minWidth: 76, minHeight: 44)
                        .background(Color(hex: "#0284C7"))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .frame(minWidth: 56, minHeight: 56) // 56×56pt touch target floor (Doc 14)
                    .contentShape(Rectangle())
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
        if let cue = naturalCue {
            return cue.primaryHeadline
        }
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
        if let cue = naturalCue {
            ZStack {
                Circle()
                    .fill(cue.intersectionControl == .trafficSignal && cue.decisionZone == .approach ? Color(hex: "#FFB300").opacity(0.2) : badgeBackgroundColor)
                    .frame(width: 32, height: 32)
                
                Image(systemName: cue.iconName)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(cue.intersectionControl == .trafficSignal && cue.decisionZone == .approach ? Color(hex: "#D97706") : badgeForegroundColor)
            }
        } else if let routeId = leg.routeId {
            TransitRouteBadge(routeId: routeId, lineInfo: leg.lineInfo, size: .regular)
        } else if (leg.mode == .bikeShare || leg.mode == .personalBike), let maneuver = leg.bikeMetadata?.nextManeuver {
            ZStack {
                Circle()
                    .fill(badgeBackgroundColor)
                    .frame(width: 32, height: 32)
                
                Image(systemName: maneuver.systemIcon)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(badgeForegroundColor)
            }
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
    
    // MARK: - Natural Cue Badge Colors
    
    private func badgeTextColor(for cue: NaturalGuidanceCue) -> Color {
        switch cue.decisionZone {
        case .imminent: return Color(hex: "#92400E")
        case .approach: return cue.intersectionControl == .trafficSignal ? Color(hex: "#92400E") : Color(hex: "#0F172A")
        case .foresight: return Color.secondary
        }
    }
    
    private func badgeBgColor(for cue: NaturalGuidanceCue) -> Color {
        switch cue.decisionZone {
        case .imminent: return Color(hex: "#FFB300").opacity(0.25)
        case .approach: return cue.intersectionControl == .trafficSignal ? Color(hex: "#FFB300").opacity(0.2) : Color.secondary.opacity(0.12)
        case .foresight: return Color.secondary.opacity(0.12)
        }
    }
}
