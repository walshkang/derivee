import SwiftUI
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
    
    @AppStorage("isTrackingEnabled") var isTrackingEnabled = false
    @Published var isTracking = false
    
    private let locationProvider: any LocationProvider
    private let databaseManager: SpatialDatabaseManager
    
    init(locationProvider: any LocationProvider = LiveLocationProvider(), databaseManager: SpatialDatabaseManager = .shared) {
        self.locationProvider = locationProvider
        self.databaseManager = databaseManager
        
        locationManager.distanceFilter = 10.0
        // Note: pausesLocationUpdatesAutomatically doesn't apply to liveUpdates in iOS 17
        // but we can still set it just in case of fallback
        locationManager.pausesLocationUpdatesAutomatically = true
        
        cleanUpOrphanedLiveActivities()
    }
    
    func cleanUpOrphanedLiveActivities() {
        let activities = Activity<TrackingAttributes>.activities
        guard !activities.isEmpty else { return }
        
        let activeId = currentActivity?.id
        Task {
            for activity in activities {
                if activity.id != activeId {
                    await activity.end(dismissalPolicy: .immediate)
                }
            }
        }
    }
    
    func requestPermissions() {
        locationManager.requestAlwaysAuthorization()
    }
    
    func resumeTrackingIfNeeded() {
        logPipeline("📍 [S1 - resumeTrackingIfNeeded] ENTER isTrackingEnabled=\(isTrackingEnabled), isTracking=\(isTracking)")
        guard isTrackingEnabled, !isTracking else { return }
        startTracking()
    }
    
    func startTracking() {
        guard !isTracking else { return }
        logPipeline("▶️ [AmbientTrackingEngine] startTracking called")
        
        cleanUpOrphanedLiveActivities()
        
        isTrackingEnabled = true
        isTracking = true
        locationManager.allowsBackgroundLocationUpdates = true
        
        // Instantiate the watchdog shield
        backgroundSession = CLBackgroundActivitySession()
        
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
    
    func stopTracking() async {
        logPipeline("⏹️ [AmbientTrackingEngine] stopTracking called")
        updatesTask?.cancel()
        _ = await updatesTask?.result
        updatesTask = nil
        
        // Invalidate the watchdog shield
        backgroundSession?.invalidate()
        backgroundSession = nil
        
        if let activity = currentActivity {
            let state = TrackingAttributes.ContentState(hexesCleared: sessionHexCount, activeNeighborhood: nil)
            await activity.end(ActivityContent(state: state, staleDate: nil), dismissalPolicy: .immediate)
            currentActivity = nil
        }
        
        cleanUpOrphanedLiveActivities()
        
        locationManager.allowsBackgroundLocationUpdates = false
        
        lastLocation = nil
        lastSavedHex = nil
        
        isTrackingEnabled = false
        isTracking = false
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
            logPipeline("⚠️ Drift gate triggered: Dropping point due to speed (\(speed) m/s)")
            return
        }
        
        // Convert to H3 string to avoid blocking the actor
        do {
            let index = try H3.latLngToCell(latitude: location.coordinate.latitude,
                                            longitude: location.coordinate.longitude,
                                            resolution: 11)
            let indexString = String(index, radix: 16)
            
            logPipeline("📍 [S2 - processLocation] hex=\(indexString), timestamp=\(location.timestamp), lastSavedHex=\(lastSavedHex ?? "nil"), speed=\(speed)")
            
            // Only hit the database if the hex has changed
            guard indexString != lastSavedHex else { return }
            lastSavedHex = indexString
            
            Task.detached { [weak self] in
                guard let self = self else { return }
                do {
                    print("⚡️ [AmbientTrackingEngine] processLocation inserting hex \(indexString) using dbWriter pool: \(ObjectIdentifier(self.databaseManager.dbWriter as AnyObject))")
                    // Hand off to the database
                    let isNew = try await self.databaseManager.insertDiscoveredHex(h3Index: indexString)
                    logPipeline("📍 [S3 - insertDiscoveredHex] hex=\(indexString), isNew=\(isNew)")
                    let nbhd = try? await self.databaseManager.fetchNeighborhoodName(for: indexString)
                    
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
                    logPipeline("❌ Failed to process hex: \(error)")
                }
            }
        } catch {
            print("Failed to convert hex: \(error)")
        }
    }
}
