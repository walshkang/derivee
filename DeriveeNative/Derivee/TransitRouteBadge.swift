import SwiftUI

/// Reusable SwiftUI component rendering mode-aware route capsules and circular discs.
/// Supports Subway, Light Rail (LRT), BRT/Bus, and Maritime Ferry with pixel-perfect
/// typography, contrast colors, and scale variations.
struct TransitRouteBadge: View {
    let routeId: String
    let lineInfo: TransitRouteData.LineInfo
    var size: BadgeSize = .regular
    var isSelected: Bool = false
    
    enum BadgeSize {
        case large    // Header hero badge (38pt height)
        case regular  // Header multi-route badge (28-34pt)
        case compact  // Arrival row badge (22pt height)
        case filter   // Timetable filter pill badge (14pt height)
        case tiny     // Heatmap / minute pill badge (10pt height)
    }
    
    init(
        routeId: String,
        lineInfo: TransitRouteData.LineInfo? = nil,
        size: BadgeSize = .regular,
        isSelected: Bool = false
    ) {
        self.routeId = routeId
        self.lineInfo = lineInfo ?? TransitRouteData.lineInfo(for: routeId)
        self.size = size
        self.isSelected = isSelected
    }
    
    var body: some View {
        switch lineInfo.modalClass {
        case .subway:
            renderSubwayBadge()
        case .lightRail:
            renderLightRailBadge()
        case .bus:
            renderBusBadge()
        case .ferry:
            renderFerryBadge()
        }
    }
    
    // MARK: - Subway & Heavy Rail
    
    @ViewBuilder
    private func renderSubwayBadge() -> some View {
        let isSingleChar = lineInfo.name.count <= 2 && !["SIR", "RED", "PATH"].contains(lineInfo.name.uppercased())
        
        switch size {
        case .large:
            if isSingleChar {
                Circle()
                    .fill(lineInfo.color)
                    .frame(width: 38, height: 38)
                    .overlay(
                        Text(lineInfo.name)
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundColor(Color(hex: lineInfo.textColorHex))
                    )
            } else {
                Text(lineInfo.name)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(Color(hex: lineInfo.textColorHex))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(lineInfo.color)
                    .clipShape(Capsule())
            }
            
        case .regular:
            if isSingleChar {
                Circle()
                    .fill(lineInfo.color)
                    .frame(width: 30, height: 30)
                    .overlay(
                        Text(lineInfo.name)
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundColor(Color(hex: lineInfo.textColorHex))
                    )
            } else {
                Text(lineInfo.name)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(Color(hex: lineInfo.textColorHex))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(lineInfo.color)
                    .clipShape(Capsule())
            }
            
        case .compact:
            if isSingleChar {
                Circle()
                    .fill(lineInfo.color)
                    .frame(width: 22, height: 22)
                    .overlay(
                        Text(lineInfo.name)
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundColor(Color(hex: lineInfo.textColorHex))
                    )
            } else {
                Text(lineInfo.name)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(Color(hex: lineInfo.textColorHex))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(lineInfo.color)
                    .clipShape(Capsule())
            }
            
        case .filter:
            Circle()
                .fill(lineInfo.color)
                .frame(width: 14, height: 14)
                .overlay(
                    Text(lineInfo.name.prefix(1))
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundColor(Color(hex: lineInfo.textColorHex))
                )
            
        case .tiny:
            Circle()
                .fill(lineInfo.color)
                .frame(width: 10, height: 10)
        }
    }
    
    // MARK: - Light Rail (LRT)
    
    @ViewBuilder
    private func renderLightRailBadge() -> some View {
        switch size {
        case .large:
            HStack(spacing: 5) {
                Image(systemName: "tram.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(Color(hex: lineInfo.textColorHex))
                Text(lineInfo.name)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(Color(hex: lineInfo.textColorHex))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(lineInfo.color)
            .clipShape(Capsule())
            
        case .regular:
            Text(lineInfo.name)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(Color(hex: lineInfo.textColorHex))
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(lineInfo.color)
                .clipShape(Capsule())
            
        case .compact:
            Text(lineInfo.name)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundColor(Color(hex: lineInfo.textColorHex))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(lineInfo.color)
                .clipShape(Capsule())
            
        case .filter:
            Circle()
                .fill(lineInfo.color)
                .frame(width: 14, height: 14)
                .overlay(
                    Text(lineInfo.name.prefix(1))
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundColor(Color(hex: lineInfo.textColorHex))
                )
            
        case .tiny:
            Circle()
                .fill(lineInfo.color)
                .frame(width: 10, height: 10)
        }
    }
    
    // MARK: - BRT & Bus
    
    @ViewBuilder
    private func renderBusBadge() -> some View {
        switch size {
        case .large:
            HStack(spacing: 6) {
                Image(systemName: "bus.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                Text(lineInfo.name)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color(hex: lineInfo.colorHex))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            
        case .regular:
            Text(lineInfo.name)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(Color(hex: lineInfo.colorHex).opacity(0.15))
                .foregroundColor(Color(hex: lineInfo.colorHex))
                .clipShape(Capsule())
            
        case .compact:
            Text(lineInfo.name)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color(hex: lineInfo.colorHex).opacity(0.15))
                .foregroundColor(Color(hex: lineInfo.colorHex))
                .clipShape(Capsule())
            
        case .filter:
            Text(lineInfo.name)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundColor(Color(hex: lineInfo.colorHex))
            
        case .tiny:
            Circle()
                .fill(Color(hex: lineInfo.colorHex))
                .frame(width: 8, height: 8)
        }
    }
    
    // MARK: - Maritime Ferry
    
    @ViewBuilder
    private func renderFerryBadge() -> some View {
        switch size {
        case .large:
            HStack(spacing: 6) {
                Image(systemName: "ferry.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                Text(lineInfo.name)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color(hex: lineInfo.colorHex))
            .clipShape(Capsule())
            
        case .regular:
            HStack(spacing: 4) {
                Image(systemName: "ferry.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white)
                Text(lineInfo.name)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(hex: lineInfo.colorHex))
            .clipShape(Capsule())
            
        case .compact:
            Text(lineInfo.name)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color(hex: lineInfo.colorHex))
                .clipShape(Capsule())
            
        case .filter:
            Circle()
                .fill(Color(hex: lineInfo.colorHex))
                .frame(width: 14, height: 14)
                .overlay(
                    Image(systemName: "ferry.fill")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.white)
                )
            
        case .tiny:
            Circle()
                .fill(Color(hex: lineInfo.colorHex))
                .frame(width: 8, height: 8)
        }
    }
}
