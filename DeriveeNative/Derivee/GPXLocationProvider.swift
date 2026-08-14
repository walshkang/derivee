import Foundation
import CoreLocation

public enum GPXPacingMode: Sendable {
    case immediate
    case simulated(interval: TimeInterval)
}

public struct GPXLocationProvider: LocationProvider {
    private let coordinates: [GPXCoordinate]
    private let pacing: GPXPacingMode
    
    public init(coordinates: [GPXCoordinate], pacing: GPXPacingMode = .immediate) {
        self.coordinates = coordinates
        self.pacing = pacing
    }
    
    public init(url: URL, pacing: GPXPacingMode = .immediate) throws {
        let parser = GPXParser()
        self.coordinates = try parser.parse(url: url)
        self.pacing = pacing
    }
    
    public var updates: AsyncStream<CLLocation> {
        AsyncStream { continuation in
            let task = Task {
                for coord in coordinates {
                    if Task.isCancelled { break }
                    
                    let timestamp = coord.timestamp ?? Date()
                    let location = CLLocation(
                        coordinate: CLLocationCoordinate2D(latitude: coord.latitude, longitude: coord.longitude),
                        altitude: 0,
                        horizontalAccuracy: 5.0,
                        verticalAccuracy: 5.0,
                        timestamp: timestamp
                    )
                    
                    continuation.yield(location)
                    
                    switch pacing {
                    case .immediate:
                        break
                    case .simulated(let interval):
                        if interval > 0 {
                            try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                        }
                    }
                }
                continuation.finish()
            }
            
            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }
}
