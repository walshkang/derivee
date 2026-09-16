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
        if lineInfo.isDiamond {
            switch size {
            case .large:
                DiamondShape()
                    .fill(lineInfo.color)
                    .frame(width: 38, height: 38)
                    .overlay(
                        Text(lineInfo.bulletGlyph)
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundColor(Color(hex: lineInfo.textColorHex))
                    )
                    .accessibilityLabel(lineInfo.accessibilityLabel)
            case .regular:
                DiamondShape()
                    .fill(lineInfo.color)
                    .frame(width: 30, height: 30)
                    .overlay(
                        Text(lineInfo.bulletGlyph)
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundColor(Color(hex: lineInfo.textColorHex))
                    )
                    .accessibilityLabel(lineInfo.accessibilityLabel)
            case .compact:
                DiamondShape()
                    .fill(lineInfo.color)
                    .frame(width: 22, height: 22)
                    .overlay(
                        Text(lineInfo.bulletGlyph)
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundColor(Color(hex: lineInfo.textColorHex))
                    )
                    .accessibilityLabel(lineInfo.accessibilityLabel)
            case .filter:
                DiamondShape()
                    .fill(lineInfo.color)
                    .frame(width: 14, height: 14)
                    .overlay(
                        Text(lineInfo.bulletGlyph)
                            .font(.system(size: 8.5, weight: .bold, design: .rounded))
                            .foregroundColor(Color(hex: lineInfo.textColorHex))
                    )
                    .accessibilityLabel(lineInfo.accessibilityLabel)
            case .tiny:
                DiamondShape()
                    .fill(lineInfo.color)
                    .frame(width: 10, height: 10)
                    .accessibilityLabel(lineInfo.accessibilityLabel)
            }
        } else {
            let isSingleChar = lineInfo.name.count <= 2 && !["SIR", "SI", "RED", "PATH"].contains(lineInfo.name.uppercased())
            
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
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
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
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
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
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
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
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
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

// MARK: - Diamond Shape (MTA Express Peak Badges)

/// Vector-crisp diamond shape matching canonical MTA express subway bullet geometry (<6>, <7>, <FX>).
public struct DiamondShape: Shape {
    public init() {}
    
    public func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
        path.closeSubpath()
        return path
    }
}

// MARK: - Adaptive Transfer Route Badge

/// Adaptive transfer badge for stop progression ladders (Guideway & Surface Run Inspectors).
/// Renders crisp DiamondShape for express subways (<6>, <7>, <FX>), Circle for single-character subways (A, 4, L),
/// and adaptive Capsule for multi-character bus routes (B62, B32) and rail routes (SIR, PATH).
public struct TransferRouteBadge: View {
    public let routeId: String
    
    public init(routeId: String) {
        self.routeId = routeId
    }
    
    public var body: some View {
        let tInfo = TransitRouteData.lineInfo(for: routeId)
        if tInfo.isDiamond {
            DiamondShape()
                .fill(tInfo.color)
                .frame(width: 14, height: 14)
                .overlay(
                    Text(tInfo.bulletGlyph)
                        .font(.system(size: 8.5, weight: .bold, design: .rounded))
                        .foregroundColor(Color(hex: tInfo.textColorHex))
                )
                .accessibilityLabel(tInfo.accessibilityLabel)
        } else if tInfo.modalClass == .subway && tInfo.name.count <= 2 && !["SIR", "SI", "RED", "PATH"].contains(tInfo.name.uppercased()) {
            Circle()
                .fill(tInfo.color)
                .frame(width: 14, height: 14)
                .overlay(
                    Text(tInfo.name)
                        .font(.system(size: 8.5, weight: .bold, design: .rounded))
                        .foregroundColor(Color(hex: tInfo.textColorHex))
                )
                .accessibilityLabel(tInfo.name)
        } else {
            Text(tInfo.name)
                .font(.system(size: 8.5, weight: .bold, design: .rounded))
                .foregroundColor(Color(hex: tInfo.textColorHex))
                .lineLimit(1)
                .padding(.horizontal, 3.5)
                .frame(height: 14)
                .frame(minWidth: 14)
                .background(tInfo.color)
                .clipShape(Capsule())
                .accessibilityLabel(tInfo.name)
        }
    }
}
