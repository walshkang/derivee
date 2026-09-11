import WidgetKit
import SwiftUI
import AppIntents

/// Provides synchronous boolean tracking state snapshots for the iOS 18 Control Center toggle.
@available(iOS 18.0, *)
public struct TrackingControlValueProvider: ControlValueProvider {
    public init() {}
    
    public var previewValue: Bool {
        true
    }
    
    public func currentValue() async throws -> Bool {
        let status = AmbientTrackingIPCService.shared.currentStatus()
        return status.isActive
    }
}

/// iOS 18 Control Center and Action Button Control Widget.
/// Enables 1-tap toggling of ambient exploration tracking from Control Center,
/// Lock Screen bottom shortcut controls, or the hardware Action Button.
@available(iOS 18.0, *)
public struct TrackingControlWidget: ControlWidget {
    public static let kind: String = "com.derivee.TrackingControlWidget"
    
    public init() {}
    
    public var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(
            kind: Self.kind,
            provider: TrackingControlValueProvider()
        ) { isTracking in
            ControlWidgetToggle(
                "Ambient Tracking",
                isOn: isTracking,
                action: SetAmbientTrackingIntent()
            ) { isOn in
                Label(
                    isOn ? "Tracking Active" : "Tracking Paused",
                    systemImage: isOn ? "location.fill" : "location.slash"
                )
            }
            .tint(Color.electricAmber)
        }
        .displayName("Ambient Tracking")
        .description("Toggle Derivee ambient exploration tracking.")
    }
}
