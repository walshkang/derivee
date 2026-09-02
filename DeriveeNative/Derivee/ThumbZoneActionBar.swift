import SwiftUI

/// Primary button archetype for the lower-third thumb zone.
public enum ThumbZonePrimaryAction {
    case startJourney(title: String = "Start Journey", action: () -> Void)
    case reroute(title: String = "Reroute", action: () -> Void)
    case unlockBike(title: String = "Unlock Bike", batterySoc: Int? = nil, dockInfo: String? = nil, action: () -> Void)
    case custom(title: String, icon: String, backgroundColor: Color, foregroundColor: Color, action: () -> Void)
    
    public var title: String {
        switch self {
        case .startJourney(let title, _): return title
        case .reroute(let title, _): return title
        case .unlockBike(let title, _, _, _): return title
        case .custom(let title, _, _, _, _): return title
        }
    }
    
    public var iconSystemName: String {
        switch self {
        case .startJourney: return "location.fill"
        case .reroute: return "arrow.triangle.2.circlepath"
        case .unlockBike: return "bicycle.circle.fill"
        case .custom(_, let icon, _, _, _): return icon
        }
    }
    
    public var backgroundColor: Color {
        switch self {
        case .startJourney: return Color(hex: "#FFB300")
        case .reroute: return Color(hex: "#0F172A")
        case .unlockBike: return Color(hex: "#0284C7")
        case .custom(_, _, let bg, _, _): return bg
        }
    }
    
    public var foregroundColor: Color {
        switch self {
        case .startJourney: return Color(hex: "#0F172A")
        case .reroute: return .white
        case .unlockBike: return .white
        case .custom(_, _, _, let fg, _): return fg
        }
    }
    
    public var height: CGFloat {
        switch self {
        case .unlockBike: return 56 // Cycling ergonomics touch target (Doc 14)
        default: return 52
        }
    }
    
    public func execute() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.prepare()
        generator.impactOccurred()
        
        switch self {
        case .startJourney(_, let action): action()
        case .reroute(_, let action): action()
        case .unlockBike(_, _, _, let action): action()
        case .custom(_, _, _, _, let action): action()
        }
    }
}

/// Secondary quick action button archetype for the lower-third thumb zone.
public struct ThumbZoneSecondaryAction {
    public let title: String
    public let iconSystemName: String
    public let action: () -> Void
    
    public init(title: String, iconSystemName: String, action: @escaping () -> Void) {
        self.title = title
        self.iconSystemName = iconSystemName
        self.action = action
    }
    
    public static func steps(action: @escaping () -> Void) -> ThumbZoneSecondaryAction {
        ThumbZoneSecondaryAction(title: "Steps", iconSystemName: "list.bullet", action: action)
    }
    
    public static func alternatives(action: @escaping () -> Void) -> ThumbZoneSecondaryAction {
        ThumbZoneSecondaryAction(title: "Alternatives", iconSystemName: "arrow.triangle.branch", action: action)
    }
    
    public static func endJourney(action: @escaping () -> Void) -> ThumbZoneSecondaryAction {
        ThumbZoneSecondaryAction(title: "End", iconSystemName: "xmark", action: action)
    }
    
    public func execute() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.prepare()
        generator.impactOccurred()
        action()
    }
}

/// Standardized one-handed lower-third thumb-zone action bar (Wave N-D.5).
/// Anchors primary actions (`Start Journey`, `Reroute`, `Unlock Bike`) with $\ge 52\text{pt}$
/// touch targets and haptic feedback within natural thumb reach.
public struct ThumbZoneActionBar: View {
    public let primaryAction: ThumbZonePrimaryAction
    public var secondaryAction: ThumbZoneSecondaryAction?
    
    public init(
        primary: ThumbZonePrimaryAction,
        secondary: ThumbZoneSecondaryAction? = nil
    ) {
        self.primaryAction = primary
        self.secondaryAction = secondary
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            Divider()
            
            HStack(spacing: 12) {
                if let secondary = secondaryAction {
                    Button {
                        secondary.execute()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: secondary.iconSystemName)
                                .font(.system(size: 13, weight: .semibold))
                            Text(secondary.title)
                                .font(.system(size: 14.5, weight: .semibold, design: .rounded))
                        }
                        .foregroundColor(Color(hex: "#0F172A"))
                        .frame(maxWidth: .infinity)
                        .frame(height: primaryAction.height)
                        .background(Color.primary.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .frame(width: 105)
                }
                
                Button {
                    primaryAction.execute()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: primaryAction.iconSystemName)
                            .font(.system(size: 14.5, weight: .bold))
                        
                        VStack(alignment: .leading, spacing: 1) {
                            Text(primaryAction.title)
                                .font(.system(size: 15.5, weight: .bold, design: .rounded))
                            
                            if case .unlockBike(_, let batterySoc, let dockInfo, _) = primaryAction {
                                HStack(spacing: 6) {
                                    if let soc = batterySoc {
                                        HStack(spacing: 2) {
                                            Image(systemName: "bolt.fill")
                                                .font(.system(size: 9, weight: .bold))
                                            Text("\(soc)% battery")
                                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                        }
                                    }
                                    if let dock = dockInfo {
                                        Text("• \(dock)")
                                            .font(.system(size: 11, weight: .medium, design: .rounded))
                                    }
                                }
                                .foregroundColor(.white.opacity(0.9))
                            }
                        }
                    }
                    .foregroundColor(primaryAction.foregroundColor)
                    .frame(maxWidth: .infinity)
                    .frame(height: primaryAction.height)
                    .background(primaryAction.backgroundColor)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .shadow(
                        color: primaryAction.backgroundColor.opacity(0.35),
                        radius: 8,
                        x: 0,
                        y: 3
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 16)
        }
        .background(Color.white.opacity(0.95))
    }
}
