import Foundation
import ActivityKit

public struct TrackingAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var hexesCleared: Int
        public var activeNeighborhood: String?
        
        public init(hexesCleared: Int, activeNeighborhood: String?) {
            self.hexesCleared = hexesCleared
            self.activeNeighborhood = activeNeighborhood
        }
    }
    
    public var sessionStartTime: Date
    
    public init(sessionStartTime: Date) {
        self.sessionStartTime = sessionStartTime
    }
}
