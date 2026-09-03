import Foundation
import ActivityKit

/// ActivityKit attributes for real-time multimodal journey navigation (Wave N-D.8).
/// Powers lock screen banners, active dynamic island expansions, transfer countdowns,
/// subterranean egress cues, platform car positioning, and dynamic recovery alerts.
public struct MultimodalTripAttributes: ActivityAttributes {
    
    public struct ContentState: Codable, Hashable, Sendable {
        public var currentLegIndex: Int
        public var totalLegs: Int
        public var stepHeadline: String
        public var secondaryContext: String
        public var modeRawValue: String
        public var routeBadge: String?
        public var routeColorHex: String?
        public var departureCountdownSec: Int?
        public var targetDepartureTime: Date?
        public var destinationETA: Date
        public var tripProgressFraction: Double
        public var exitCode: String?
        public var carRecommendation: String?
        public var isMissedConnection: Bool
        public var recoveryNotice: String?
        
        public init(
            currentLegIndex: Int,
            totalLegs: Int,
            stepHeadline: String,
            secondaryContext: String,
            modeRawValue: String,
            routeBadge: String? = nil,
            routeColorHex: String? = nil,
            departureCountdownSec: Int? = nil,
            targetDepartureTime: Date? = nil,
            destinationETA: Date,
            tripProgressFraction: Double,
            exitCode: String? = nil,
            carRecommendation: String? = nil,
            isMissedConnection: Bool = false,
            recoveryNotice: String? = nil
        ) {
            self.currentLegIndex = currentLegIndex
            self.totalLegs = totalLegs
            self.stepHeadline = stepHeadline
            self.secondaryContext = secondaryContext
            self.modeRawValue = modeRawValue
            self.routeBadge = routeBadge
            self.routeColorHex = routeColorHex
            self.departureCountdownSec = departureCountdownSec
            self.targetDepartureTime = targetDepartureTime
            self.destinationETA = destinationETA
            self.tripProgressFraction = max(0.0, min(1.0, tripProgressFraction))
            self.exitCode = exitCode
            self.carRecommendation = carRecommendation
            self.isMissedConnection = isMissedConnection
            self.recoveryNotice = recoveryNotice
        }
    }
    
    public var originName: String
    public var destinationName: String
    public var tripStartTime: Date
    
    public init(
        originName: String,
        destinationName: String,
        tripStartTime: Date = Date()
    ) {
        self.originName = originName
        self.destinationName = destinationName
        self.tripStartTime = tripStartTime
    }
}
