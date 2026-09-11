import Foundation
import AppIntents

/// Registers predefined App Shortcuts for Siri and the Shortcuts app.
public struct DeriveeShortcuts: AppShortcutsProvider {
    public static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ToggleAmbientTrackingIntent(),
            phrases: [
                "Toggle \(.applicationName) tracking",
                "Toggle exploration tracking in \(.applicationName)",
                "Toggle tracking with \(.applicationName)"
            ],
            shortTitle: "Toggle Tracking",
            systemImageName: "location.fill"
        )
        AppShortcut(
            intent: StartAmbientTrackingIntent(),
            phrases: [
                "Start \(.applicationName) tracking",
                "Start exploring with \(.applicationName)",
                "Resume \(.applicationName) tracking"
            ],
            shortTitle: "Start Tracking",
            systemImageName: "play.circle.fill"
        )
        AppShortcut(
            intent: StopAmbientTrackingIntent(),
            phrases: [
                "Stop \(.applicationName) tracking",
                "Pause \(.applicationName) tracking",
                "Pause exploring in \(.applicationName)"
            ],
            shortTitle: "Stop Tracking",
            systemImageName: "pause.circle.fill"
        )
        AppShortcut(
            intent: GetAmbientTrackingStatusIntent(),
            phrases: [
                "Check \(.applicationName) tracking status",
                "Is \(.applicationName) tracking?",
                "How is my \(.applicationName) tracking?"
            ],
            shortTitle: "Tracking Status",
            systemImageName: "info.circle.fill"
        )
    }
}
