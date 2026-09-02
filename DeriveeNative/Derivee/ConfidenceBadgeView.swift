import SwiftUI

/// Reusable 3-tier GTFS-Realtime confidence indicator badge.
/// Resolves ghost vehicle anxiety with animated Electric Amber radar telemetry.
public struct ConfidenceBadgeView: View {
    public let tier: GTFSRealtimeConfidenceTier
    public var size: BadgeSize = .regular
    public var showLabel: Bool = true
    
    @State private var isPulsing: Bool = false
    
    public enum BadgeSize {
        case compact   // Inside route cards (18pt height)
        case regular   // Inside modal headers (24pt height)
        case expanded  // Inspector / Detail drilldown (28pt height)
        
        var dotSize: CGFloat {
            switch self {
            case .compact: return 5.5
            case .regular: return 7.0
            case .expanded: return 8.5
            }
        }
        
        var fontSize: CGFloat {
            switch self {
            case .compact: return 9.0
            case .regular: return 10.5
            case .expanded: return 12.0
            }
        }
        
        var horizontalPadding: CGFloat {
            switch self {
            case .compact: return 6.0
            case .regular: return 8.0
            case .expanded: return 10.0
            }
        }
        
        var verticalPadding: CGFloat {
            switch self {
            case .compact: return 3.0
            case .regular: return 4.0
            case .expanded: return 5.0
            }
        }
    }
    
    public init(
        tier: GTFSRealtimeConfidenceTier,
        size: BadgeSize = .regular,
        showLabel: Bool = true
    ) {
        self.tier = tier
        self.size = size
        self.showLabel = showLabel
    }
    
    public var body: some View {
        HStack(spacing: size == .compact ? 4 : 5) {
            dotIndicator
            
            if showLabel {
                Text(tierLabel)
                    .font(.system(size: size.fontSize, weight: .bold, design: .monospaced))
                    .foregroundColor(textColor)
            }
        }
        .padding(.horizontal, size.horizontalPadding)
        .padding(.vertical, size.verticalPadding)
        .background(badgeBackground)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(badgeBorder, lineWidth: 1)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tier.accessibilityDescription)
        .onAppear {
            if tier == .verified {
                withAnimation(
                    .easeInOut(duration: 1.4)
                    .repeatForever(autoreverses: true)
                ) {
                    isPulsing = true
                }
            }
        }
    }
    
    // MARK: - Dot Telemetry
    
    @ViewBuilder
    private var dotIndicator: some View {
        ZStack {
            switch tier {
            case .verified:
                // Expanding radar pulse wave
                Circle()
                    .fill(Color(hex: "#FFB300"))
                    .frame(width: size.dotSize, height: size.dotSize)
                    .scaleEffect(isPulsing ? 1.85 : 1.0)
                    .opacity(isPulsing ? 0.0 : 0.6)
                
                // Core breathing dot
                Circle()
                    .fill(Color(hex: "#FFB300"))
                    .frame(width: size.dotSize, height: size.dotSize)
                    .opacity(isPulsing ? 1.0 : 0.4)
                    .shadow(color: Color(hex: "#FFB300").opacity(0.8), radius: isPulsing ? 3 : 1)
                
            case .estimated:
                Circle()
                    .fill(Color(hex: "#E67E22").opacity(0.75))
                    .frame(width: size.dotSize - 1, height: size.dotSize - 1)
                
            case .staticSchedule:
                Circle()
                    .fill(Color.secondary.opacity(0.45))
                    .frame(width: size.dotSize - 1, height: size.dotSize - 1)
            }
        }
        .frame(width: size.dotSize + 4, height: size.dotSize + 4)
    }
    
    // MARK: - Text & Colors
    
    private var tierLabel: String {
        switch tier {
        case .verified:
            return size == .compact ? "LIVE" : "VERIFIED LIVE"
        case .estimated:
            return "~ESTIMATED"
        case .staticSchedule:
            return "SCHEDULED"
        }
    }
    
    private var textColor: Color {
        switch tier {
        case .verified:
            return Color(hex: "#B45309") // High-contrast amber-brown for light background
        case .estimated:
            return Color(hex: "#B45309").opacity(0.85)
        case .staticSchedule:
            return Color.secondary
        }
    }
    
    private var badgeBackground: some View {
        Group {
            switch tier {
            case .verified:
                Color(hex: "#FFB300").opacity(0.14)
            case .estimated:
                Color(hex: "#E67E22").opacity(0.08)
            case .staticSchedule:
                Color.primary.opacity(0.04)
            }
        }
    }
    
    private var badgeBorder: Color {
        switch tier {
        case .verified:
            return Color(hex: "#FFB300").opacity(0.35)
        case .estimated:
            return Color(hex: "#E67E22").opacity(0.2)
        case .staticSchedule:
            return Color.primary.opacity(0.08)
        }
    }
}
