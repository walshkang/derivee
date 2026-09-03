import SwiftUI
import CoreLocation

/// 3-tier real-time dock availability gating badge and pre-armed fallback card (Wave N-D.7).
/// Implements Doc 11 & Doc 14 standards:
/// - Low Risk (>3 empty docks): High-contrast emerald green badge (`#10B981`)
/// - Moderate Risk (1–2 empty docks): Electric Amber badge (`#FFB300`) with pre-armed fallback station
/// - High Risk (0 empty docks): Alert crimson badge (`#EF4444`) with automated overflow rerouting prompt.
public struct DockAvailabilityBadgeView: View {
    public let availableDocks: Int
    public let fallbackStationName: String?
    public var isCompact: Bool
    public var onTapFallback: (() -> Void)?
    
    public init(
        availableDocks: Int,
        fallbackStationName: String? = nil,
        isCompact: Bool = false,
        onTapFallback: (() -> Void)? = nil
    ) {
        self.availableDocks = availableDocks
        self.fallbackStationName = fallbackStationName
        self.isCompact = isCompact
        self.onTapFallback = onTapFallback
    }
    
    public var risk: GBFSDockGatingRisk {
        GBFSDockGatingRisk.risk(forAvailableDocks: availableDocks)
    }
    
    public var body: some View {
        HStack(spacing: 6) {
            badgePill
            
            if !isCompact, risk == .moderate, let fallback = fallbackStationName {
                Button {
                    let generator = UIImpactFeedbackGenerator(style: .light)
                    generator.prepare()
                    generator.impactOccurred()
                    onTapFallback?()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.branch")
                            .font(.system(size: 9, weight: .bold))
                        Text("Fallback: \(fallback)")
                            .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                            .lineLimit(1)
                    }
                    .foregroundColor(Color(hex: "#78350F"))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color(hex: "#FEF3C7"))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
    }
    
    @ViewBuilder
    private var badgePill: some View {
        HStack(spacing: isCompact ? 3 : 5) {
            Circle()
                .fill(indicatorDotColor)
                .frame(width: isCompact ? 6 : 7, height: isCompact ? 6 : 7)
            
            Text(badgeText)
                .font(.system(size: isCompact ? 10 : 11.5, weight: .bold, design: .rounded))
                .foregroundColor(textColor)
        }
        .padding(.horizontal, isCompact ? 6 : 8)
        .padding(.vertical, isCompact ? 2.5 : 4)
        .background(backgroundColor)
        .clipShape(Capsule())
    }
    
    private var badgeText: String {
        switch risk {
        case .low:
            return isCompact ? "\(availableDocks) docks" : "\(availableDocks) Docks Available"
        case .moderate:
            return isCompact ? "\(availableDocks) left" : "\(availableDocks) Docks Left"
        case .high:
            return isCompact ? "0 docks" : "Station Full (0 docks)"
        }
    }
    
    private var indicatorDotColor: Color {
        switch risk {
        case .low: return Color(hex: "#10B981") // Emerald
        case .moderate: return Color(hex: "#FFB300") // Electric Amber
        case .high: return Color(hex: "#EF4444") // Red
        }
    }
    
    private var textColor: Color {
        switch risk {
        case .low: return Color(hex: "#064E3B") // WCAG AAA on #D1FAE5 (8.57:1)
        case .moderate: return Color(hex: "#78350F") // WCAG AAA on #FEF3C7 (8.15:1)
        case .high: return Color(hex: "#7F1D1D") // WCAG AAA on #FEE2E2 (8.20:1)
        }
    }
    
    private var backgroundColor: Color {
        switch risk {
        case .low: return Color(hex: "#D1FAE5")
        case .moderate: return Color(hex: "#FEF3C7")
        case .high: return Color(hex: "#FEE2E2")
        }
    }
    
    private var accessibilityDescription: String {
        switch risk {
        case .low:
            return "\(availableDocks) docks available. Low dock exhaustion risk."
        case .moderate:
            return "\(availableDocks) docks remaining. Moderate risk. Secondary fallback dock pre-armed."
        case .high:
            return "0 docks remaining. Station full. Automatic reroute recommended."
        }
    }
}

// MARK: - Pre-Armed Fallback Station Card

/// Contextual card pre-arming a secondary fallback dock when the primary station drops to moderate risk (1–2 docks).
public struct PreArmedFallbackCard: View {
    public let primaryStationName: String
    public let fallbackStationName: String
    public let availableDocksAtFallback: Int
    public let extraWalkDistanceMeters: UInt32
    public let extraWalkDurationSec: UInt32
    public var onSwitchToFallback: () -> Void
    
    public init(
        primaryStationName: String,
        fallbackStationName: String,
        availableDocksAtFallback: Int = 8,
        extraWalkDistanceMeters: UInt32 = 180,
        extraWalkDurationSec: UInt32 = 90,
        onSwitchToFallback: @escaping () -> Void
    ) {
        self.primaryStationName = primaryStationName
        self.fallbackStationName = fallbackStationName
        self.availableDocksAtFallback = availableDocksAtFallback
        self.extraWalkDistanceMeters = extraWalkDistanceMeters
        self.extraWalkDurationSec = extraWalkDurationSec
        self.onSwitchToFallback = onSwitchToFallback
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "shield.righthalf.filled")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(Color(hex: "#D97706"))
                
                Text("PRE-ARMED FALLBACK DOCK")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(Color(hex: "#78350F"))
                
                Spacer()
                
                Text("\(availableDocksAtFallback) docks open")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(Color(hex: "#064E3B"))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color(hex: "#D1FAE5"))
                    .clipShape(Capsule())
            }
            
            VStack(alignment: .leading, spacing: 3) {
                Text(fallbackStationName)
                    .font(.system(size: 14.5, weight: .bold, design: .rounded))
                    .foregroundColor(Color(hex: "#0F172A"))
                
                HStack(spacing: 5) {
                    Image(systemName: "figure.walk")
                        .font(.system(size: 11, weight: .medium))
                    Text("+\(extraWalkFormatted) walk from \(primaryStationName)")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                }
                .foregroundColor(.secondary)
            }
            
            // 56pt Cycling Touch Target (Doc 14)
            Button {
                let generator = UIImpactFeedbackGenerator(style: .medium)
                generator.prepare()
                generator.impactOccurred()
                onSwitchToFallback()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 14, weight: .bold))
                    Text("Switch to Fallback Dock")
                        .font(.system(size: 14.5, weight: .bold, design: .rounded))
                }
                .foregroundColor(Color(hex: "#0F172A"))
                .frame(maxWidth: .infinity)
                .frame(height: 56) // 56pt floor
                .background(Color(hex: "#FFB300"))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(Color(hex: "#FEF3C7").opacity(0.45))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color(hex: "#FFB300").opacity(0.4), lineWidth: 1.5)
        )
    }
    
    private var extraWalkFormatted: String {
        let minutes = Int(ceil(Double(extraWalkDurationSec) / 60.0))
        let feet = Int(Double(extraWalkDistanceMeters) * 3.28084)
        return "\(minutes)m (\(feet) ft)"
    }
}

// MARK: - Auto-Reroute Alert Banner (0 Docks / Station Full)

/// High-impact auto-reroute card presented when the destination station suffers complete dock exhaustion (0 docks).
public struct DockOverflowAutoRerouteBanner: View {
    public let failedStationName: String
    public let reroutedStationName: String
    public let availableDocksAtReroute: Int
    public let extraWalkMeters: UInt32
    public var onAcceptReroute: () -> Void
    public var onDismiss: (() -> Void)?
    
    public init(
        failedStationName: String,
        reroutedStationName: String,
        availableDocksAtReroute: Int = 10,
        extraWalkMeters: UInt32 = 140,
        onAcceptReroute: @escaping () -> Void,
        onDismiss: (() -> Void)? = nil
    ) {
        self.failedStationName = failedStationName
        self.reroutedStationName = reroutedStationName
        self.availableDocksAtReroute = availableDocksAtReroute
        self.extraWalkMeters = extraWalkMeters
        self.onAcceptReroute = onAcceptReroute
        self.onDismiss = onDismiss
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.octagon.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(Color(hex: "#EF4444"))
                
                Text("STATION FULL • AUTO-REROUTE")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(Color(hex: "#7F1D1D"))
                
                Spacer()
                
                if let onDismiss = onDismiss {
                    Button(action: onDismiss) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundColor(.secondary.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                }
            }
            
            Text("\(failedStationName) has 0 empty docks. Auto-rerouted to nearest station within a 3-minute walk:")
                .font(.system(size: 12.5, weight: .medium, design: .rounded))
                .foregroundColor(Color(hex: "#334155"))
            
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: "bicycle.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(Color(hex: "#0284C7"))
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(reroutedStationName)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(Color(hex: "#0F172A"))
                    
                    Text("\(availableDocksAtReroute) docks • +\(Int(Double(extraWalkMeters) * 3.28084)) ft walk to destination")
                        .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                        .foregroundColor(Color(hex: "#064E3B"))
                }
                
                Spacer()
            }
            .padding(10)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            
            // 56pt Cycling Touch Target
            Button {
                let generator = UIImpactFeedbackGenerator(style: .heavy)
                generator.prepare()
                generator.impactOccurred()
                onAcceptReroute()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.triangle.swap")
                        .font(.system(size: 14.5, weight: .bold))
                    Text("Confirm Reroute to \(reroutedStationName)")
                        .font(.system(size: 14.5, weight: .bold, design: .rounded))
                        .lineLimit(1)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 56) // 56pt floor
                .background(Color(hex: "#0F172A"))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(Color(hex: "#FEE2E2").opacity(0.85))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color(hex: "#EF4444").opacity(0.4), lineWidth: 1.5)
        )
    }
}
