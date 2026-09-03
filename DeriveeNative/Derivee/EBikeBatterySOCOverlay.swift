import SwiftUI

/// E-bike state-of-charge (SOC %) overlay and usable range radius calculator (Wave N-D.7).
/// Eliminates "Micro-Mobility Hardware Blindness" by providing real-time battery visualization,
/// usable range radius computation (0.20 mi / %), and range deficit warning alerts per Doc 14.
public struct EBikeBatterySOCOverlay: View {
    public let batterySocPercent: Int
    public let legDistanceMeters: UInt32?
    public var isCompact: Bool
    
    public init(
        batterySocPercent: Int,
        legDistanceMeters: UInt32? = nil,
        isCompact: Bool = false
    ) {
        self.batterySocPercent = max(0, min(100, batterySocPercent))
        self.legDistanceMeters = legDistanceMeters
        self.isCompact = isCompact
    }
    
    public static let milesPerBatteryPercent: Double = 0.20 // 100% = 20.0 miles
    
    public var estimatedRangeMiles: Double {
        Double(batterySocPercent) * Self.milesPerBatteryPercent
    }
    
    public var estimatedRangeMeters: Double {
        estimatedRangeMiles * 1609.34
    }
    
    public var isRangeDeficit: Bool {
        guard let legDist = legDistanceMeters else { return false }
        return estimatedRangeMeters < Double(legDist)
    }
    
    public var deficitMiles: Double {
        guard let legDist = legDistanceMeters else { return 0.0 }
        let legMiles = Double(legDist) / 1609.34
        return max(0.0, legMiles - estimatedRangeMiles)
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: isCompact ? 4 : 8) {
            if isCompact {
                compactGaugeRow
            } else {
                fullGaugeCard
            }
            
            if isRangeDeficit {
                rangeDeficitAlert
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
    }
    
    // MARK: - Compact Gauge Row
    
    @ViewBuilder
    private var compactGaugeRow: some View {
        HStack(spacing: 6) {
            batteryIcon
            
            Text("\(batterySocPercent)%")
                .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                .foregroundColor(accentColor)
            
            Text("•")
                .font(.system(size: 9))
                .foregroundColor(.secondary)
            
            Text(String(format: "%.1f mi range", estimatedRangeMiles))
                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3.5)
        .background(accentColor.opacity(0.10))
        .clipShape(Capsule())
    }
    
    // MARK: - Full Gauge Card
    
    @ViewBuilder
    private var fullGaugeCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                HStack(spacing: 6) {
                    batteryIcon
                    
                    Text("E-BIKE BATTERY SOC")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(accentColor)
                }
                
                Spacer()
                
                Text("\(batterySocPercent)%")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundColor(accentColor)
            }
            
            // Segmented Progress Bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.secondary.opacity(0.15))
                        .frame(height: 8)
                    
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(accentColor)
                        .frame(width: geo.size.width * CGFloat(Double(batterySocPercent) / 100.0), height: 8)
                }
            }
            .frame(height: 8)
            
            HStack {
                Text(String(format: "%.1f miles usable range radius", estimatedRangeMiles))
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Text(capacityLabel)
                    .font(.system(size: 10.5, weight: .bold, design: .rounded))
                    .foregroundColor(accentColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(accentColor.opacity(0.12))
                    .clipShape(Capsule())
            }
        }
        .padding(12)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(accentColor.opacity(0.25), lineWidth: 1.0)
        )
    }
    
    // MARK: - Range Deficit Alert
    
    @ViewBuilder
    private var rangeDeficitAlert: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(Color(hex: "#EF4444"))
            
            Text(String(format: "Range Deficit: Leg exceeds battery by %.1f mi", deficitMiles))
                .font(.system(size: 11.5, weight: .bold, design: .rounded))
                .foregroundColor(Color(hex: "#991B1B"))
            
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(hex: "#FEE2E2"))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
    
    // MARK: - Subviews & Styling
    
    @ViewBuilder
    private var batteryIcon: some View {
        if batterySocPercent < 20 {
            Image(systemName: "battery.0percent")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(accentColor)
        } else if batterySocPercent < 50 {
            Image(systemName: "battery.25percent")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(accentColor)
        } else if batterySocPercent < 80 {
            Image(systemName: "battery.75percent")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(accentColor)
        } else {
            Image(systemName: "battery.100percent.bolt")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(accentColor)
        }
    }
    
    private var accentColor: Color {
        if batterySocPercent < 20 {
            return Color(hex: "#EF4444") // Crimson Alert (<20%)
        } else if batterySocPercent < 40 {
            return Color(hex: "#FFB300") // Electric Amber (20-39%)
        } else {
            return Color(hex: "#0284C7") // Sky Blue (>=40%)
        }
    }
    
    private var capacityLabel: String {
        if batterySocPercent < 20 {
            return "LOW BATTERY"
        } else if batterySocPercent < 40 {
            return "MODERATE"
        } else {
            return "PLENTIFUL"
        }
    }
    
    private var accessibilitySummary: String {
        let deficitText = isRangeDeficit ? " Warning: Battery is insufficient for this trip." : ""
        return "E-bike battery at \(batterySocPercent) percent. Estimated usable range is \(String(format: "%.1f", estimatedRangeMiles)) miles.\(deficitText)"
    }
}

// MARK: - Compact Header Pill for HUD

/// Ultra-glanceable pill for HUD and card headers.
public struct EBikeBatterySOCPill: View {
    public let batterySocPercent: Int
    public let estimatedRangeMiles: Double?
    
    public init(batterySocPercent: Int, estimatedRangeMiles: Double? = nil) {
        self.batterySocPercent = batterySocPercent
        self.estimatedRangeMiles = estimatedRangeMiles
    }
    
    public var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 9, weight: .bold))
            
            Text("\(batterySocPercent)%")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
            
            if let range = estimatedRangeMiles {
                Text("• \(String(format: "%.1f", range))mi")
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
            }
        }
        .foregroundColor(batterySocPercent < 20 ? Color(hex: "#EF4444") : Color(hex: "#0284C7"))
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(
            batterySocPercent < 20
                ? Color(hex: "#FEE2E2")
                : Color(hex: "#0284C7").opacity(0.12)
        )
        .clipShape(Capsule())
    }
}
