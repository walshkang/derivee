import Foundation
import AppIntents

/// App Intent to explicitly start ambient exploration tracking.
public struct StartAmbientTrackingIntent: AppIntent {
    public static var title: LocalizedStringResource = "Start Ambient Tracking"
    public static var description = IntentDescription("Start ambient exploration tracking in the background.")
    public static var openAppWhenRun: Bool = false
    
    public init() {}
    
    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        _ = AmbientTrackingIPCService.shared.sendCommand(enable: true)
        return .result(dialog: "Derivee exploration tracking started.")
    }
}
