import WidgetKit
import SwiftUI

@main
struct DeriveeWidgetBundle: WidgetBundle {
    var body: some Widget {
        TrackingLiveActivity()
        MultimodalTripLiveActivity()
        ExplorationMetricsWidget()
        if #available(iOS 18.0, *) {
            TrackingControlWidget()
        }
    }
}
