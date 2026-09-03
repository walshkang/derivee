import WidgetKit
import SwiftUI
import ActivityKit

/// Native iOS 17+ WidgetKit Live Activity & Dynamic Island for Multimodal Navigation (Wave N-D.8).
/// Delivers passive, glanceable progress tracking on the Lock Screen, StandBy, and Dynamic Island:
/// - Transfer countdowns and live departure timers.
/// - Step transitions and subterranean exit guidance codes (e.g. "Exit 4B").
/// - Train car egress alignment recommendations (e.g. "Board near front car").
/// - Automated missed-connection alerts with 1-tap deep-linking.
struct MultimodalTripLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: MultimodalTripAttributes.self) { context in
            // MARK: - Lock Screen / Banner Presentation
            VStack(spacing: 10) {
                // Header: Origin -> Destination with ETA
                HStack(alignment: .center) {
                    HStack(spacing: 6) {
                        ApertureMicroGlyph(size: 16, strokeWidth: 1.2)
                        Text("\(context.attributes.originName) → \(context.attributes.destinationName)")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundColor(.white.opacity(0.85))
                            .lineLimit(1)
                    }
                    
                    Spacer()
                    
                    HStack(spacing: 4) {
                        Text("Arrives")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(0.6))
                        Text(context.state.destinationETA, style: .time)
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundColor(.electricAmber)
                    }
                }
                
                // Missed Connection Alert Banner (if disrupted)
                if context.state.isMissedConnection {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.white)
                        Text(context.state.recoveryNotice ?? "Missed Connection • Tap to Reroute")
                            .font(.system(size: 12.5, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        Spacer()
                        Text("1-Tap Reroute")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.white.opacity(0.2))
                            .clipShape(Capsule())
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color(red: 0.95, green: 0.45, blue: 0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                
                // Main Step Guidance Row
                HStack(spacing: 12) {
                    // Route bullet or mode badge
                    modeBadgeView(
                        modeRawValue: context.state.modeRawValue,
                        badge: context.state.routeBadge,
                        colorHex: context.state.routeColorHex
                    )
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.state.stepHeadline)
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        
                        Text(context.state.secondaryContext)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(0.7))
                            .lineLimit(1)
                    }
                    
                    Spacer()
                    
                    // Transfer countdown or departure timer
                    if let targetDate = context.state.targetDepartureTime {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("Departs in")
                                .font(.system(size: 10, weight: .medium, design: .rounded))
                                .foregroundColor(.white.opacity(0.6))
                            Text(timerInterval: Date()...targetDate, countsDown: true)
                                .font(.system(size: 15, weight: .bold, design: .monospaced))
                                .foregroundColor(.electricAmber)
                        }
                    }
                }
                
                // Auxiliary Badges (Exit Code + Platform Car Position)
                if context.state.exitCode != nil || context.state.carRecommendation != nil {
                    HStack(spacing: 8) {
                        if let car = context.state.carRecommendation {
                            HStack(spacing: 4) {
                                Image(systemName: "tram.fill")
                                    .font(.system(size: 10))
                                Text(car)
                                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                            }
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color.white.opacity(0.12))
                            .clipShape(Capsule())
                            .foregroundColor(.white.opacity(0.9))
                        }
                        
                        if let exit = context.state.exitCode {
                            HStack(spacing: 4) {
                                Image(systemName: "figure.walk.departure")
                                    .font(.system(size: 10))
                                Text(exit)
                                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                            }
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color.electricAmber.opacity(0.2))
                            .clipShape(Capsule())
                            .foregroundColor(.electricAmber)
                            .lineLimit(1)
                        }
                        
                        Spacer()
                    }
                }
                
                // Linear Trip Progress Gauge
                ProgressView(value: context.state.tripProgressFraction)
                    .progressViewStyle(LinearProgressViewStyle(tint: .electricAmber))
                    .background(Color.white.opacity(0.15))
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .activityBackgroundTint(Color(red: 0.06, green: 0.07, blue: 0.1).opacity(0.92))
            .activitySystemActionForegroundColor(Color.white)
            .widgetURL(URL(string: "derivee://navigation"))
            
        } dynamicIsland: { context in
            // MARK: - Dynamic Island Presentation
            DynamicIsland {
                // Expanded Leading
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 8) {
                        modeBadgeView(
                            modeRawValue: context.state.modeRawValue,
                            badge: context.state.routeBadge,
                            colorHex: context.state.routeColorHex,
                            size: 26
                        )
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(context.state.stepHeadline)
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                                .lineLimit(1)
                            
                            Text(context.state.secondaryContext)
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .foregroundColor(.white.opacity(0.7))
                                .lineLimit(1)
                        }
                    }
                }
                
                // Expanded Trailing
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        if let targetDate = context.state.targetDepartureTime {
                            Text(timerInterval: Date()...targetDate, countsDown: true)
                                .font(.system(size: 14, weight: .bold, design: .monospaced))
                                .foregroundColor(.electricAmber)
                            Text("to departure")
                                .font(.system(size: 9, weight: .medium, design: .rounded))
                                .foregroundColor(.white.opacity(0.6))
                        } else {
                            Text(context.state.destinationETA, style: .time)
                                .font(.system(size: 14, weight: .bold, design: .monospaced))
                                .foregroundColor(.electricAmber)
                            Text("arrival ETA")
                                .font(.system(size: 9, weight: .medium, design: .rounded))
                                .foregroundColor(.white.opacity(0.6))
                        }
                    }
                }
                
                // Expanded Bottom
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        if context.state.isMissedConnection {
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.white)
                                Text(context.state.recoveryNotice ?? "Missed Connection • Tap to Reroute")
                                    .font(.system(size: 11.5, weight: .bold, design: .rounded))
                                    .foregroundColor(.white)
                                Spacer()
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color(red: 0.95, green: 0.45, blue: 0.1))
                            .clipShape(Capsule())
                        }
                        
                        HStack(spacing: 6) {
                            if let car = context.state.carRecommendation {
                                Text(car)
                                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.white.opacity(0.15))
                                    .clipShape(Capsule())
                                    .foregroundColor(.white.opacity(0.9))
                            }
                            
                            if let exit = context.state.exitCode {
                                Text(exit)
                                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.electricAmber.opacity(0.2))
                                    .clipShape(Capsule())
                                    .foregroundColor(.electricAmber)
                                    .lineLimit(1)
                            }
                            
                            Spacer()
                            
                            ProgressView(value: context.state.tripProgressFraction)
                                .progressViewStyle(LinearProgressViewStyle(tint: .electricAmber))
                                .frame(width: 80)
                        }
                    }
                    .padding(.top, 4)
                }
                
            } compactLeading: {
                compactLeadingBadge(
                    modeRawValue: context.state.modeRawValue,
                    badge: context.state.routeBadge,
                    colorHex: context.state.routeColorHex
                )
            } compactTrailing: {
                if let targetDate = context.state.targetDepartureTime {
                    Text(timerInterval: Date()...targetDate, countsDown: true)
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundColor(context.state.isMissedConnection ? .orange : .electricAmber)
                } else {
                    Text(context.state.destinationETA, style: .time)
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundColor(context.state.isMissedConnection ? .orange : .electricAmber)
                }
            } minimal: {
                if context.state.isMissedConnection {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.orange)
                } else if let badge = context.state.routeBadge, !badge.isEmpty {
                    Text(badge)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(.electricAmber)
                } else {
                    ApertureMicroGlyph(size: 14, strokeWidth: 1.2)
                }
            }
            .keylineTint(context.state.isMissedConnection ? .orange : .electricAmber)
            .widgetURL(URL(string: "derivee://navigation"))
        }
    }
    
    // MARK: - Subview Helpers
    
    @ViewBuilder
    private func modeBadgeView(
        modeRawValue: String,
        badge: String?,
        colorHex: String?,
        size: CGFloat = 32
    ) -> some View {
        let bgColor = colorHex.flatMap { Color(hex: $0) } ?? defaultColorFor(modeRawValue: modeRawValue)
        
        ZStack {
            Circle()
                .fill(bgColor)
                .frame(width: size, height: size)
            
            if let b = badge, !b.isEmpty {
                Text(b)
                    .font(.system(size: size * 0.46, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            } else {
                Image(systemName: iconFor(modeRawValue: modeRawValue))
                    .font(.system(size: size * 0.46, weight: .bold))
                    .foregroundColor(.white)
            }
        }
    }
    
    @ViewBuilder
    private func compactLeadingBadge(
        modeRawValue: String,
        badge: String?,
        colorHex: String?
    ) -> some View {
        let bgColor = colorHex.flatMap { Color(hex: $0) } ?? defaultColorFor(modeRawValue: modeRawValue)
        
        HStack(spacing: 3) {
            Circle()
                .fill(bgColor)
                .frame(width: 8, height: 8)
            
            if let b = badge, !b.isEmpty {
                Text(b)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            } else {
                Image(systemName: iconFor(modeRawValue: modeRawValue))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white)
            }
        }
    }
    
    private func iconFor(modeRawValue: String) -> String {
        switch modeRawValue {
        case "walk":
            return "figure.walk"
        case "subway":
            return "tram.fill"
        case "bus":
            return "bus.fill"
        case "bikeShare", "personalBike":
            return "bicycle"
        case "lightRail":
            return "train.side.front.car"
        case "ferry":
            return "ferry.fill"
        default:
            return "location.fill"
        }
    }
    
    private func defaultColorFor(modeRawValue: String) -> Color {
        switch modeRawValue {
        case "walk":
            return Color(hex: "#64748B")
        case "subway":
            return Color(hex: "#00933C")
        case "bus":
            return Color(hex: "#0039A6")
        case "bikeShare", "personalBike":
            return Color(hex: "#007AFF")
        case "lightRail":
            return Color(hex: "#EE352E")
        case "ferry":
            return Color(hex: "#0085CA")
        default:
            return Color(hex: "#FFB300")
        }
    }
}

fileprivate extension Color {
    init(hex: String) {
        let cleanHex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: cleanHex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch cleanHex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

