import SwiftUI

/// Predictive route comparison card presenting arrival times with P10-P90 confidence intervals,
/// 3-tier GTFS-RT confidence badges, multimodal leg chaining, effort summaries, and inline disruption callouts.
public struct RouteComparisonCardView: View {
    public let itinerary: JourneyItinerary
    public var isSelected: Bool = false
    public var onSelect: (() -> Void)?
    
    public init(
        itinerary: JourneyItinerary,
        isSelected: Bool = false,
        onSelect: (() -> Void)? = nil
    ) {
        self.itinerary = itinerary
        self.isSelected = isSelected
        self.onSelect = onSelect
    }
    
    public var body: some View {
        Button {
            onSelect?()
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                // MARK: - Header: Times, Duration & Confidence
                headerRow
                
                // MARK: - Multimodal Leg Chain
                legChainView
                
                // MARK: - Effort, Fare & Transfer Strip
                metricsStripView
                
                // MARK: - Inline Disruption Callouts
                if !itinerary.disruptions.isEmpty {
                    disruptionsCalloutView
                }
            }
            .padding(16)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(
                        isSelected ? Color(hex: "#FFB300") : Color.primary.opacity(0.08),
                        lineWidth: isSelected ? 2.0 : 1.0
                    )
            )
            .shadow(color: Color.black.opacity(isSelected ? 0.08 : 0.03), radius: isSelected ? 8 : 4, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(itinerary.voiceOverSummary)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : [.isButton])
    }
    
    // MARK: - Header Row
    
    @ViewBuilder
    private var headerRow: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(itinerary.formattedArrivalTime)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundColor(Color(hex: "#0F172A"))
                    
                    Text("arrive")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(.secondary)
                }
                
                // P10 - P90 Confidence Interval Callout
                HStack(spacing: 4) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(Color(hex: "#B45309"))
                    
                    Text(itinerary.formattedConfidenceInterval)
                        .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                        .foregroundColor(Color(hex: "#92400E"))
                }
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 5) {
                // Total Duration Capsule
                HStack(spacing: 4) {
                    Text(itinerary.formattedDuration)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(Color(hex: "#0F172A"))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3.5)
                .background(Color.primary.opacity(0.05))
                .clipShape(Capsule())
                
                // 3-Tier GTFS-RT Confidence Badge
                ConfidenceBadgeView(tier: itinerary.confidenceTier, size: .compact)
            }
        }
    }
    
    // MARK: - Multimodal Leg Chain
    
    @ViewBuilder
    private var legChainView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Array(itinerary.legs.enumerated()), id: \.element.id) { index, leg in
                    legPill(for: leg)
                    
                    if index < itinerary.legs.count - 1 {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(Color.secondary.opacity(0.5))
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }
    
    @ViewBuilder
    private func legPill(for leg: JourneyLeg) -> some View {
        switch leg.mode {
        case .walk:
            HStack(spacing: 3.5) {
                Image(systemName: "figure.walk")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                Text(leg.formattedDuration)
                    .font(.system(size: 11.5, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(Color.primary.opacity(0.04))
            .clipShape(Capsule())
            
        case .subway, .bus, .lightRail, .ferry:
            if let routeId = leg.routeId {
                HStack(spacing: 4) {
                    TransitRouteBadge(
                        routeId: routeId,
                        lineInfo: leg.lineInfo,
                        size: .compact
                    )
                    
                    if let headsign = leg.headsign, !headsign.isEmpty {
                        Text(headsign)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundColor(Color(hex: "#334155"))
                            .lineLimit(1)
                    }
                    
                    Text(leg.formattedDuration)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(Color(hex: "#475569"))
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.primary.opacity(0.03))
                .clipShape(Capsule())
            }
            
        case .bikeShare, .personalBike:
            HStack(spacing: 4) {
                Image(systemName: "bicycle")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Color(hex: "#0284C7")) // Citi Bike Blue
                
                Text(leg.formattedDuration)
                    .font(.system(size: 11.5, weight: .bold, design: .rounded))
                    .foregroundColor(Color(hex: "#0369A1"))
                
                if let meta = leg.bikeMetadata, let soc = meta.batterySocPercent, meta.isEBike {
                    HStack(spacing: 1.5) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 8, weight: .bold))
                        Text("\(soc)%")
                            .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                    }
                    .foregroundColor(Color(hex: "#0284C7"))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1.5)
                    .background(Color(hex: "#0284C7").opacity(0.12))
                    .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(Color(hex: "#0284C7").opacity(0.08))
            .clipShape(Capsule())
        }
    }
    
    // MARK: - Metrics Strip (Transfers, Cost, Walking/Biking Effort)
    
    @ViewBuilder
    private var metricsStripView: some View {
        HStack(spacing: 12) {
            // Transfer Count
            HStack(spacing: 4) {
                Image(systemName: "arrow.triangle.swap")
                    .font(.system(size: 10.5, weight: .medium))
                Text(itinerary.transferSummary)
                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
            }
            .foregroundColor(itinerary.transferCount == 0 ? Color(hex: "#059669") : Color.secondary)
            
            Text("•")
                .font(.system(size: 10))
                .foregroundColor(Color.secondary.opacity(0.5))
            
            // Total Fare
            HStack(spacing: 3.5) {
                Image(systemName: "dollarsign.circle")
                    .font(.system(size: 10.5, weight: .medium))
                Text(itinerary.formattedCost)
                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
            }
            .foregroundColor(.secondary)
            
            Text("•")
                .font(.system(size: 10))
                .foregroundColor(Color.secondary.opacity(0.5))
            
            // Walking Effort
            HStack(spacing: 3.5) {
                Image(systemName: "figure.walk")
                    .font(.system(size: 10.5, weight: .medium))
                Text(itinerary.formattedWalkingDistance)
                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
            }
            .foregroundColor(.secondary)
            
            // Biking Distance if present
            if itinerary.bikingDistanceMeters > 0 {
                Text("•")
                    .font(.system(size: 10))
                    .foregroundColor(Color.secondary.opacity(0.5))
                
                HStack(spacing: 3.5) {
                    Image(systemName: "bicycle")
                        .font(.system(size: 10.5, weight: .medium))
                    Text(itinerary.formattedBikingDistance)
                        .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                }
                .foregroundColor(Color(hex: "#0284C7"))
            }
            
            Spacer()
        }
        .padding(.top, 2)
    }
    
    // MARK: - Inline Disruptions Callout
    
    @ViewBuilder
    private var disruptionsCalloutView: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(itinerary.disruptions) { disruption in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: disruption.severity.iconName)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(Color(hex: disruption.severity.accentColorHex))
                        .padding(.top, 1)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(disruption.headline)
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundColor(Color(hex: "#78350F"))
                        
                        Text(disruption.detailText)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Color(hex: "#92400E"))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    
                    Spacer()
                    
                    if disruption.rerouteSuggested {
                        Text("Reroute")
                            .font(.system(size: 9.5, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2.5)
                            .background(Color(hex: "#D97706"))
                            .clipShape(Capsule())
                    }
                }
                .padding(10)
                .background(Color(hex: "#FEF3C7"))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color(hex: "#F59E0B").opacity(0.35), lineWidth: 1)
                )
            }
        }
    }
}
