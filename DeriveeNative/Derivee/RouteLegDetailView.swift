import SwiftUI

/// Granular step-by-step itinerary drilldown view.
/// Integrates landmark walking cues, platform train car positioning badges,
/// subterranean exit mapping, and GBFS dock availability gating.
public struct RouteLegDetailView: View {
    public let itinerary: JourneyItinerary
    public var onClose: (() -> Void)?
    
    public init(
        itinerary: JourneyItinerary,
        onClose: (() -> Void)? = nil
    ) {
        self.itinerary = itinerary
        self.onClose = onClose
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            headerBar
            
            Divider()
            
            // Step-by-Step Leg List
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(itinerary.legs.enumerated()), id: \.element.id) { index, leg in
                        legTimelineRow(leg: leg, isLast: index == itinerary.legs.count - 1)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
        }
        .background(Color(hex: "#F9F9F6"))
    }
    
    // MARK: - Header Bar
    
    @ViewBuilder
    private var headerBar: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(itinerary.profile.displayName)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundColor(Color(hex: "#0F172A"))
                    
                    Text("•")
                        .foregroundColor(.secondary)
                    
                    Text(itinerary.formattedDuration)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundColor(.secondary)
                }
                
                Text("Arrives \(itinerary.formattedArrivalTime) (\(itinerary.formattedConfidenceInterval))")
                    .font(.system(size: 12.5, weight: .medium, design: .monospaced))
                    .foregroundColor(Color(hex: "#B45309"))
            }
            
            Spacer()
            
            ConfidenceBadgeView(tier: itinerary.confidenceTier, size: .regular)
            
            if let onClose = onClose {
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(Color.secondary.opacity(0.6))
                }
                .buttonStyle(.plain)
                .padding(.leading, 8)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(Color.white)
    }
    
    // MARK: - Timeline Leg Row
    
    @ViewBuilder
    private func legTimelineRow(leg: JourneyLeg, isLast: Bool) -> some View {
        HStack(alignment: .top, spacing: 14) {
            // Timeline Line & Icon Node
            VStack(spacing: 0) {
                timelineNode(for: leg)
                
                if !isLast {
                    Rectangle()
                        .fill(timelineLineColor(for: leg))
                        .frame(width: 2)
                        .frame(minHeight: 40)
                }
            }
            .frame(width: 24)
            
            // Content
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(leg.originName)
                        .font(.system(size: 14.5, weight: .bold, design: .rounded))
                        .foregroundColor(Color(hex: "#0F172A"))
                    
                    Spacer()
                    
                    Text(JourneyItinerary.formatSecondsToClock(leg.departureTimeSec))
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                
                legSpecificDetails(for: leg)
                
                if isLast {
                    HStack {
                        Text(leg.destinationName)
                            .font(.system(size: 14.5, weight: .bold, design: .rounded))
                            .foregroundColor(Color(hex: "#0F172A"))
                        
                        Spacer()
                        
                        Text(JourneyItinerary.formatSecondsToClock(leg.arrivalTimeSec))
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 8)
                }
            }
            .padding(.bottom, isLast ? 8 : 20)
        }
    }
    
    // MARK: - Leg Node & Details
    
    @ViewBuilder
    private func timelineNode(for leg: JourneyLeg) -> some View {
        ZStack {
            Circle()
                .fill(timelineNodeBackground(for: leg))
                .frame(width: 22, height: 22)
            
            Image(systemName: leg.mode.systemIcon)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(timelineNodeForeground(for: leg))
        }
    }
    
    @ViewBuilder
    private func legSpecificDetails(for leg: JourneyLeg) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            switch leg.mode {
            case .walk:
                HStack(spacing: 6) {
                    Text("Walk \(leg.formattedDistance) (\(leg.formattedDuration))")
                        .font(.system(size: 12.5, weight: .medium, design: .rounded))
                        .foregroundColor(.secondary)
                }
                
                if let cue = leg.landmarkCue {
                    HStack(spacing: 5) {
                        Image(systemName: "mappin.circle.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(Color(hex: "#059669"))
                        Text(cue)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Color(hex: "#065F46"))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(hex: "#D1FAE5"))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                
            case .subway, .bus, .lightRail, .ferry:
                if let routeId = leg.routeId {
                    HStack(spacing: 6) {
                        TransitRouteBadge(routeId: routeId, lineInfo: leg.lineInfo, size: .regular)
                        
                        if let headsign = leg.headsign {
                            Text(headsign)
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundColor(Color(hex: "#1E293B"))
                        }
                    }
                }
                
                if let stops = leg.stopCount {
                    Text("Ride \(stops) stops (\(leg.formattedDuration))")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(.secondary)
                }
                
                // Platform Car Recommendation & Subterranean Exit
                if let car = leg.recommendedCarPosition {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.left.and.right.square.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(Color(hex: "#D97706"))
                        Text(car)
                            .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                            .foregroundColor(Color(hex: "#92400E"))
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3.5)
                    .background(Color(hex: "#FEF3C7"))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                
                if let exit = leg.exitCode {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.right.square.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(Color(hex: "#2563EB"))
                        Text(exit)
                            .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                            .foregroundColor(Color(hex: "#1E40AF"))
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3.5)
                    .background(Color(hex: "#DBEAFE"))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                
            case .bikeShare, .personalBike:
                HStack(spacing: 6) {
                    Text("Ride \(leg.formattedDistance) (\(leg.formattedDuration))")
                        .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                        .foregroundColor(Color(hex: "#0369A1"))
                }
                
                if let meta = leg.bikeMetadata {
                    HStack(spacing: 8) {
                        if meta.isEBike, let soc = meta.batterySocPercent {
                            HStack(spacing: 3) {
                                Image(systemName: "bolt.fill")
                                    .font(.system(size: 10, weight: .bold))
                                Text("\(soc)% battery (\(String(format: "%.1f", meta.estimatedRangeMiles ?? 0)) mi)")
                                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            }
                            .foregroundColor(Color(hex: "#0284C7"))
                        }
                        
                        Text(meta.dockGatingRisk.title)
                            .font(.system(size: 10.5, weight: .bold, design: .rounded))
                            .foregroundColor(meta.dockGatingRisk.badgeColor)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(meta.dockGatingRisk.badgeColor.opacity(0.12))
                            .clipShape(Capsule())
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
    
    private func timelineNodeBackground(for leg: JourneyLeg) -> Color {
        if let line = leg.lineInfo {
            return line.color
        }
        switch leg.mode {
        case .walk: return Color.secondary.opacity(0.2)
        case .bikeShare, .personalBike: return Color(hex: "#0284C7")
        default: return Color(hex: "#FFB300")
        }
    }
    
    private func timelineNodeForeground(for leg: JourneyLeg) -> Color {
        if let line = leg.lineInfo {
            return Color(hex: line.textColorHex)
        }
        switch leg.mode {
        case .walk: return Color.primary.opacity(0.7)
        default: return Color.white
        }
    }
    
    private func timelineLineColor(for leg: JourneyLeg) -> Color {
        if let line = leg.lineInfo {
            return line.color.opacity(0.5)
        }
        switch leg.mode {
        case .bikeShare, .personalBike: return Color(hex: "#0284C7").opacity(0.4)
        default: return Color.secondary.opacity(0.2)
        }
    }
}
