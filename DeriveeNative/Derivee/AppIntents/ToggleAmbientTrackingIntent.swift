import Foundation
import AppIntents

/// App Intent to toggle ambient exploration tracking on or off.
/// Conforms to `AppIntent` and conditionally to `AudioRecordingIntent` on iOS 18+
/// for direct mapping to the hardware Action Button on supported devices.
public struct ToggleAmbientTrackingIntent: AppIntent {
    public static var title: LocalizedStringResource = "Toggle Ambient Tracking"
    public static var description = IntentDescription("Toggle ambient exploration tracking on or off.")
    public static var openAppWhenRun: Bool = false
    
    public init() {}
    
    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let ipc = AmbientTrackingIPCService.shared
        let newStatus = ipc.sendCommand(enable: nil)
        
        let dialogText = newStatus
            ? "Derivee exploration tracking is now active."
            : "Derivee exploration tracking is now paused."
        
        return .result(dialog: IntentDialog(stringLiteral: dialogText))
    }
}

#if canImport(AppIntents)
@available(iOS 18.0, *)
extension ToggleAmbientTrackingIntent: AudioRecordingIntent {}
#endif
