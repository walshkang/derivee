import Foundation
import ActivityKit

public struct TrackingAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var hexesCleared: Int
        public var activeNeighborhood: String?
        public var distanceMeters: Double
        
        public init(hexesCleared: Int, activeNeighborhood: String?, distanceMeters: Double = 0.0) {
            self.hexesCleared = hexesCleared
            self.activeNeighborhood = activeNeighborhood
            self.distanceMeters = distanceMeters
        }
    }
    
    public var sessionStartTime: Date
    
    public init(sessionStartTime: Date) {
        self.sessionStartTime = sessionStartTime
    }
}
