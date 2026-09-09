import SwiftUI

/// Compact per-route reliability badge for Screen 2 arrival rows (Wave PA.3 / WPA3-RELIABILITY-BADGES).
/// Visual encoding:
/// - `● High` (green `#10B981`, OTP >= 90%)
/// - `◐ Moderate` (amber `#F59E0B`, 70% <= OTP < 90%)
/// - `○ Variable` (red `#EF4444`, OTP < 70%)
///
/// Designed to aid the "which departure should I take?" decision at the station level
/// with WCAG AAA contrast and high-density 1-row layout ergonomics.
public struct RouteReliabilityBadge: View {
    public let tier: LineReliabilityTier
    
    public init(tier: LineReliabilityTier) {
        self.tier = tier
    }
    
    public var body: some View {
        HStack(spacing: 3) {
            Text(tier.glyph)
                .font(.system(size: 8.5, weight: .bold))
                .foregroundColor(tier.tintColor)
            
            Text(tier.label)
                .font(.system(size: 9.5, weight: .bold, design: .rounded))
                .foregroundColor(tier.textColor)
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 1.5)
        .background(tier.backgroundColor)
        .clipShape(Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(tier.accessibilityText)
    }
}
