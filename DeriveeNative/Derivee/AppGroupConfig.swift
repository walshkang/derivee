import Foundation

/// Centralized configuration and storage keys for cross-process App Group communication.
public enum AppGroupConfig {
    /// App Group identifier shared between Derivee application and extensions (DeriveeWidget, App Intents).
    public static let appGroupId = "group.com.derivee.Derivee"
    
    /// Shared `UserDefaults` instance backed by the App Group container.
    /// Falls back gracefully to `.standard` in isolated/mock test runner environments.
    public static var sharedUserDefaults: UserDefaults {
        UserDefaults(suiteName: appGroupId) ?? .standard
    }
}

/// Strongly typed keys stored inside the shared App Group `UserDefaults` container.
public enum AppGroupKeys {
    /// Persistent user preference indicating whether ambient tracking is enabled (matches AppStorageKeys.isTrackingEnabled).
    public static let isTrackingEnabled = "isTrackingEnabled"
    
    /// Live runtime status reflecting whether `AmbientTrackingEngine` is currently executing.
    public static let isTrackingActive = "isTrackingActive"
    
    /// Total number of newly discovered hexes cleared during the current active tracking session.
    public static let sessionHexCount = "sessionHexCount"
    
    /// Cumulative distance in meters traveled during the current active tracking session.
    public static let sessionDistanceMeters = "sessionDistanceMeters"
    
    /// Most recently identified neighborhood name for the user's current location.
    public static let activeNeighborhood = "activeNeighborhood"
    
    /// UNIX epoch timestamp (seconds) of the most recent tracking state update.
    public static let lastStateChangeTimestamp = "lastStateChangeTimestamp"
}

/// Snapshot of ambient exploration tracking status suitable for cross-process queries and Siri dialogs.
public struct AmbientTrackingStatus: Sendable, Equatable {
    public let isEnabled: Bool
    public let isActive: Bool
    public let sessionHexCount: Int
    public let sessionDistanceMeters: Double
    public let activeNeighborhood: String?
    public let lastUpdated: Date
    
    public init(
        isEnabled: Bool,
        isActive: Bool,
        sessionHexCount: Int,
        sessionDistanceMeters: Double,
        activeNeighborhood: String?,
        lastUpdated: Date
    ) {
        self.isEnabled = isEnabled
        self.isActive = isActive
        self.sessionHexCount = sessionHexCount
        self.sessionDistanceMeters = sessionDistanceMeters
        self.activeNeighborhood = activeNeighborhood
        self.lastUpdated = lastUpdated
    }
    
    /// Natural-language summary for Siri dialogs and App Intent results.
    public var dialogSummary: String {
        if isActive {
            if let nbhd = activeNeighborhood, !nbhd.isEmpty {
                if sessionHexCount > 0 {
                    return "Derivee is actively tracking. \(sessionHexCount) hex\(sessionHexCount == 1 ? "" : "es") uncovered in \(nbhd)."
                } else {
                    return "Derivee is actively tracking in \(nbhd)."
                }
            } else if sessionHexCount > 0 {
                return "Derivee is actively tracking. \(sessionHexCount) hex\(sessionHexCount == 1 ? "" : "es") uncovered."
            } else {
                return "Derivee exploration tracking is actively running."
            }
        } else {
            return "Derivee exploration tracking is currently paused."
        }
    }
}
