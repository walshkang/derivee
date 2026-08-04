import Foundation
import CoreLocation
import H3

public protocol LocationProvider: Sendable {
    var updates: AsyncStream<CLLocation> { get }
}

public struct LiveLocationProvider: LocationProvider {
    public init() {}
    public var updates: AsyncStream<CLLocation> {
        AsyncStream { continuation in
            let task = Task {
                do {
                    let updates = CLLocationUpdate.liveUpdates()
                    for try await update in updates {
                        if let loc = update.location {
                            continuation.yield(loc)
                        }
                    }
                } catch {
                    print("Live updates failed: \(error)")
                    continuation.finish()
                }
            }
            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }
}

@MainActor
final class AmbientTrackingEngine: ObservableObject {
    private let locationManager = CLLocationManager()
    
    // Watchdog Shield to keep app alive in background
    private var backgroundSession: CLBackgroundActivitySession?
    
    // Persistent task for live updates
    private var updatesTask: Task<Void, Never>?
    
    // State for tracking previous location to calculate speed if speed is invalid
    private var lastLocation: CLLocation?
    
    @Published var isTracking = false
    
    private let locationProvider: any LocationProvider
    private let databaseManager: SpatialDatabaseManager
    
    init(locationProvider: any LocationProvider = LiveLocationProvider(), databaseManager: SpatialDatabaseManager = .shared) {
        self.locationProvider = locationProvider
        self.databaseManager = databaseManager
        
        locationManager.distanceFilter = 10.0
        locationManager.allowsBackgroundLocationUpdates = true
        // Note: pausesLocationUpdatesAutomatically doesn't apply to liveUpdates in iOS 17
        // but we can still set it just in case of fallback
        locationManager.pausesLocationUpdatesAutomatically = true
    }
    
    func requestPermissions() {
        locationManager.requestAlwaysAuthorization()
    }
    
    func startTracking() {
        guard !isTracking else { return }
        
        // Instantiate the watchdog shield
        backgroundSession = CLBackgroundActivitySession()
        isTracking = true
        
        updatesTask = Task {
            for await location in locationProvider.updates {
                processLocation(location)
            }
        }
    }
    
    func stopTracking() {
        isTracking = false
        updatesTask?.cancel()
        updatesTask = nil
        
        // Invalidate the watchdog shield
        backgroundSession?.invalidate()
        backgroundSession = nil
    }
    
    private func processLocation(_ location: CLLocation) {
        // Implied Speed Filter
        let speed: CLLocationSpeed
        
        if location.speed >= 0 {
            speed = location.speed
        } else if let lastLoc = lastLocation {
            let distance = location.distance(from: lastLoc)
            let timeDelta = location.timestamp.timeIntervalSince(lastLoc.timestamp)
            speed = timeDelta > 0 ? distance / timeDelta : 0
        } else {
            speed = 0
        }
        
        lastLocation = location
        
        // Discard if speed is > 12 m/s (approx 27 mph)
        if speed > 12.0 {
            print("Drift gate triggered: Dropping point due to speed (\(speed) m/s)")
            return
        }
        
        // Convert to H3 string asynchronously to avoid blocking the actor
        Task.detached { [self] in
            do {
                let index = try H3.latLngToCell(latitude: location.coordinate.latitude,
                                                longitude: location.coordinate.longitude,
                                                resolution: 11)
                let indexString = String(index, radix: 16)
                
                // Hand off to the database
                try await self.databaseManager.insertDiscoveredHex(h3Index: indexString)
                print("Saved hex: \(indexString)")
            } catch {
                print("Failed to convert or save hex: \(error)")
            }
        }
    }
}
