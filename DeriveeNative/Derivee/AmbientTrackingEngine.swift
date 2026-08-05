import Foundation
import CoreLocation
import H3
import ActivityKit

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
    private var lastSavedHex: String?
    
    // Live Activity State
    private var currentActivity: Activity<TrackingAttributes>?
    private var sessionHexCount: Int = 0
    
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
        
        sessionHexCount = 0
        do {
            let attributes = TrackingAttributes(sessionStartTime: Date())
            let state = TrackingAttributes.ContentState(hexesCleared: 0, activeNeighborhood: nil)
            currentActivity = try Activity.request(attributes: attributes, content: ActivityContent(state: state, staleDate: nil), pushType: nil)
        } catch {
            print("Failed to start Live Activity: \(error)")
        }
        
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
        
        if let activity = currentActivity {
            Task {
                let state = TrackingAttributes.ContentState(hexesCleared: sessionHexCount, activeNeighborhood: nil)
                await activity.end(ActivityContent(state: state, staleDate: nil), dismissalPolicy: .default)
            }
            currentActivity = nil
        }
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
        
        // Convert to H3 string to avoid blocking the actor
        do {
            let index = try H3.latLngToCell(latitude: location.coordinate.latitude,
                                            longitude: location.coordinate.longitude,
                                            resolution: 11)
            let indexString = String(index, radix: 16)
            
            // Only hit the database if the hex has changed
            guard indexString != lastSavedHex else { return }
            lastSavedHex = indexString
            
            Task.detached { [self] in
                do {
                    // Hand off to the database
                    let isNew = try await self.databaseManager.insertDiscoveredHex(h3Index: indexString)
                    let nbhd = self.databaseManager.fetchNeighborhoodName(for: indexString)
                    
                    await MainActor.run {
                        if isNew {
                            self.sessionHexCount += 1
                        }
                        if let activity = self.currentActivity {
                            let state = TrackingAttributes.ContentState(hexesCleared: self.sessionHexCount, activeNeighborhood: nbhd)
                            Task {
                                await activity.update(ActivityContent(state: state, staleDate: nil))
                            }
                        }
                    }
                    print("Processed hex: \(indexString) (New: \(isNew))")
                } catch {
                    print("Failed to process hex: \(error)")
                }
            }
        } catch {
            print("Failed to convert hex: \(error)")
        }
    }
}
