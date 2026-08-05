import WidgetKit
import SwiftUI
import ActivityKit

struct TrackingLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TrackingAttributes.self) { context in
            // Lock screen/banner UI goes here
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Tracking Walk")
                        .font(.headline)
                        .foregroundColor(.white)
                    Text(timerInterval: context.attributes.sessionStartTime...Date.distantFuture, countsDown: false)
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(context.state.hexesCleared) hexes")
                        .font(.headline)
                        .foregroundColor(.white)
                        .contentTransition(.numericText(value: Double(context.state.hexesCleared)))
                    
                    if let neighborhood = context.state.activeNeighborhood, !neighborhood.isEmpty {
                        Text(neighborhood)
                            .font(.caption)
                            .foregroundColor(.gray)
                            .lineLimit(1)
                    }
                }
            }
            .padding()
            .activityBackgroundTint(Color.black.opacity(0.6))
            .activitySystemActionForegroundColor(Color.white)
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded UI
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Walk")
                            .font(.headline)
                        Text(timerInterval: context.attributes.sessionStartTime...Date.distantFuture, countsDown: false)
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("\(context.state.hexesCleared) hexes")
                            .font(.headline)
                            .contentTransition(.numericText(value: Double(context.state.hexesCleared)))
                        
                        if let neighborhood = context.state.activeNeighborhood, !neighborhood.isEmpty {
                            Text(neighborhood)
                                .font(.caption)
                                .foregroundColor(.gray)
                                .lineLimit(1)
                        }
                    }
                }
            } compactLeading: {
                Image(systemName: "location.fill")
                    .foregroundColor(.white)
            } compactTrailing: {
                Text("\(context.state.hexesCleared)")
                    .contentTransition(.numericText(value: Double(context.state.hexesCleared)))
            } minimal: {
                Image(systemName: "location.fill")
                    .foregroundColor(.white)
            }
            .keylineTint(Color.white)
        }
    }
}
