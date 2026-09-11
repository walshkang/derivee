import Foundation
import AppIntents

/// App Intent conforming to `SetValueIntent` for explicit boolean state toggling.
/// Designed specifically for integration with iOS 18 `ControlWidgetToggle` (Wave S.2)
/// and Shortcuts actions requiring explicit parameter binding.
public struct SetAmbientTrackingIntent: AppIntent, SetValueIntent {
    public static var title: LocalizedStringResource = "Set Ambient Tracking"
    public static var description = IntentDescription("Set ambient exploration tracking to an explicit active or paused state.")
    public static var openAppWhenRun: Bool = false
    
    @Parameter(title: "Tracking Enabled")
    public var value: Bool
    
    public init() {
        self.value = true
    }
    
    public init(value: Bool) {
        self.value = value
    }
    
    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        _ = AmbientTrackingIPCService.shared.sendCommand(enable: value)
        
        let dialogText = value
            ? "Derivee exploration tracking enabled."
            : "Derivee exploration tracking paused."
        
        return .result(dialog: IntentDialog(stringLiteral: dialogText))
    }
}
