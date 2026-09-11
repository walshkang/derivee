import Foundation
import AppIntents

/// App Intent to explicitly stop ambient exploration tracking.
public struct StopAmbientTrackingIntent: AppIntent {
    public static var title: LocalizedStringResource = "Stop Ambient Tracking"
    public static var description = IntentDescription("Stop ambient exploration tracking and release background location session.")
    public static var openAppWhenRun: Bool = false
    
    public init() {}
    
    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        _ = AmbientTrackingIPCService.shared.sendCommand(enable: false)
        return .result(dialog: "Derivee exploration tracking paused.")
    }
}
