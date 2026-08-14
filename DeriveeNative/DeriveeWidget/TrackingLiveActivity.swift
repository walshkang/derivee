import WidgetKit
import SwiftUI
import ActivityKit

struct TrackingLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TrackingAttributes.self) { context in
            // Lock screen / Banner Card
            HStack(spacing: 14) {
                ApertureMicroGlyph(size: 32, strokeWidth: 1.8)
                    .frame(width: 36, height: 36)
                
                VStack(alignment: .leading, spacing: 3) {
                    Text("Ambient Drift")
                        .font(.system(.headline, design: .default))
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                    
                    HStack(spacing: 6) {
                        Text(timerInterval: context.attributes.sessionStartTime...Date.distantFuture, countsDown: false)
                            .font(.system(.subheadline, design: .monospaced))
                            .foregroundColor(.white.opacity(0.7))
                        
                        Text("•")
                            .foregroundColor(.white.opacity(0.4))
                        
                        Text(formatDistance(context.state.distanceMeters))
                            .font(.system(.subheadline, design: .monospaced))
                            .foregroundColor(.electricAmber)
                    }
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 3) {
                    Text("\(context.state.hexesCleared) hexes")
                        .font(.system(.headline, design: .monospaced))
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .contentTransition(.numericText(value: Double(context.state.hexesCleared)))
                    
                    if let neighborhood = context.state.activeNeighborhood, !neighborhood.isEmpty {
                        Text(neighborhood)
                            .font(.system(.caption, design: .default))
                            .foregroundColor(.white.opacity(0.6))
                            .lineLimit(1)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .activityBackgroundTint(Color.black.opacity(0.75))
            .activitySystemActionForegroundColor(Color.white)
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded Leading
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 8) {
                        ApertureMicroGlyph(size: 20, strokeWidth: 1.4)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Drift")
                                .font(.system(.subheadline, design: .default))
                                .fontWeight(.bold)
                            Text(timerInterval: context.attributes.sessionStartTime...Date.distantFuture, countsDown: false)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                // Expanded Trailing
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(context.state.hexesCleared) hexes")
                            .font(.system(.subheadline, design: .monospaced))
                            .fontWeight(.bold)
                            .contentTransition(.numericText(value: Double(context.state.hexesCleared)))
                        
                        Text(formatDistance(context.state.distanceMeters))
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundColor(.electricAmber)
                    }
                }
                
                // Expanded Bottom
                DynamicIslandExpandedRegion(.bottom) {
                    if let neighborhood = context.state.activeNeighborhood, !neighborhood.isEmpty {
                        HStack {
                            Text(neighborhood)
                                .font(.system(.caption, design: .default))
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                        .padding(.top, 2)
                    }
                }
            } compactLeading: {
                ApertureMicroGlyph(size: 16, strokeWidth: 1.2)
            } compactTrailing: {
                Text("\(context.state.hexesCleared)")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundColor(.electricAmber)
                    .contentTransition(.numericText(value: Double(context.state.hexesCleared)))
            } minimal: {
                ApertureMicroGlyph(size: 16, strokeWidth: 1.2)
            }
            .keylineTint(.electricAmber)
            .widgetURL(URL(string: "derivee://progress"))
        }
    }
    
    private func formatDistance(_ meters: Double) -> String {
        if meters >= 1000 {
            return String(format: "%.1f km", meters / 1000.0)
        } else {
            return "\(Int(meters)) m"
        }
    }
}
