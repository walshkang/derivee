import Foundation
import AppIntents

/// App Intent to query the current ambient exploration tracking status.
/// Returns both a boolean value indicating if tracking is active and a formatted spoken/text summary.
public struct GetAmbientTrackingStatusIntent: AppIntent {
    public static var title: LocalizedStringResource = "Get Tracking Status"
    public static var description = IntentDescription("Check whether ambient exploration tracking is currently active.")
    public static var openAppWhenRun: Bool = false
    
    public init() {}
    
    @MainActor
    public func perform() async throws -> some IntentResult & ReturnsValue<Bool> & ProvidesDialog {
        let status = AmbientTrackingIPCService.shared.currentStatus()
        return .result(value: status.isActive, dialog: IntentDialog(stringLiteral: status.dialogSummary))
    }
}
