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
                        if Task.isCancelled { break }
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
    
    // Filter for cold-start convergence, staleness, and contextual drift gating
    private var coldStartFilter = ColdStartLocationFilter()
    private var lastSavedHex: String?
    private var currentNeighborhood: String?
    
    // Termination Observer
    private var terminationObserver: NSObjectProtocol?
    
    // Live Activity State
    private var currentActivity: Activity<TrackingAttributes>?
    private var sessionHexCount: Int = 0
    private var sessionDistanceMeters: Double = 0.0
    
    @AppStorage(AppStorageKeys.isTrackingEnabled) var isTrackingEnabled = true
    @AppStorage(AppStorageKeys.isLiveActivityEnabled) var isLiveActivityEnabled = true
    @Published var isTracking = false
    @Published var lastKnownLocation: CLLocation? = nil
    
    private let locationProvider: any LocationProvider
    private let databaseManager: SpatialDatabaseManager
    
    init(locationProvider: any LocationProvider = LiveLocationProvider(), databaseManager: SpatialDatabaseManager = .shared) {
        self.locationProvider = locationProvider
        self.databaseManager = databaseManager
        
        locationManager.distanceFilter = 10.0
        // Note: pausesLocationUpdatesAutomatically doesn't apply to liveUpdates in iOS 17
        // but we can still set it just in case of fallback
        locationManager.pausesLocationUpdatesAutomatically = true
        
        setupTerminationObserver()
        cleanUpOrphanedLiveActivities()
    }
    
    private func setupTerminationObserver() {
        if let observer = terminationObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        terminationObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            logPipeline("🛑 [AmbientTrackingEngine] willTerminateNotification received — cleaning up background session and Live Activities")
            self?.handleAppTermination()
        }
    }
    
    func handleAppTermination() {
        logPipeline("🛑 [AmbientTrackingEngine] handleAppTermination executing synchronous full location tear down")
        
        // 1. Cancel location updates task
        updatesTask?.cancel()
        updatesTask = nil
        
        // 2. Invalidate background activity session
        backgroundSession?.invalidate()
        backgroundSession = nil
        
        // 3. Completely shut down CoreLocation background assertions & updates
        locationManager.stopUpdatingLocation()
        locationManager.allowsBackgroundLocationUpdates = false
        
        // 4. Synchronously drain Live Activity termination before process SIGKILL
        let activities = Activity<TrackingAttributes>.activities
        if !activities.isEmpty {
            let semaphore = DispatchSemaphore(value: 0)
            Task.detached(priority: .userInteractive) {
                for activity in activities {
                    await activity.end(ActivityContent(state: activity.content.state, staleDate: nil), dismissalPolicy: .immediate)
                }
                semaphore.signal()
            }
            // Wait up to 250ms for IPC delivery to SpringBoard/chronod
            _ = semaphore.wait(timeout: .now() + 0.25)
        }
        
        // 5. Clean up in-memory runtime tracking state (keep persistent isTrackingEnabled preference)
        coldStartFilter.reset()
        lastSavedHex = nil
        currentNeighborhood = nil
        isTracking = false
        
        logPipeline("🛑 [AmbientTrackingEngine] handleAppTermination complete — all location sessions killed")
    }
    
    deinit {
        if let observer = terminationObserver {
            NotificationCenter.default.removeObserver(observer)
        }
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
    
    func startLiveActivity() {
        guard isLiveActivityEnabled, currentActivity == nil else { return }
        do {
            let attributes = TrackingAttributes(sessionStartTime: Date())
            let state = TrackingAttributes.ContentState(
                hexesCleared: sessionHexCount,
                activeNeighborhood: currentNeighborhood,
                distanceMeters: sessionDistanceMeters
            )
            currentActivity = try Activity.request(
                attributes: attributes,
                content: ActivityContent(state: state, staleDate: Date().addingTimeInterval(45)),
                pushType: nil
            )
            logPipeline("✨ [AmbientTrackingEngine] Live Activity started successfully")
        } catch {
            print("Failed to start Live Activity: \(error)")
        }
    }
    
    func stopLiveActivity() async {
        guard let activity = currentActivity else { return }
        let state = TrackingAttributes.ContentState(
            hexesCleared: sessionHexCount,
            activeNeighborhood: currentNeighborhood,
            distanceMeters: sessionDistanceMeters
        )
        await activity.end(ActivityContent(state: state, staleDate: nil), dismissalPolicy: .immediate)
        currentActivity = nil
        logPipeline("⏹️ [AmbientTrackingEngine] Live Activity ended")
    }
    
    func updateLiveActivityPreference(enabled: Bool) {
        isLiveActivityEnabled = enabled
        if enabled {
            if isTracking && currentActivity == nil {
                startLiveActivity()
            }
        } else {
            if currentActivity != nil {
                Task {
                    await stopLiveActivity()
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
        coldStartFilter.reset()
        lastSavedHex = nil
        locationManager.allowsBackgroundLocationUpdates = true
        
        // Instantiate the watchdog shield
        backgroundSession = CLBackgroundActivitySession()
        
        sessionHexCount = 0
        sessionDistanceMeters = 0.0
        
        if isLiveActivityEnabled {
            startLiveActivity()
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
        
        await stopLiveActivity()
        cleanUpOrphanedLiveActivities()
        
        locationManager.stopUpdatingLocation()
        locationManager.allowsBackgroundLocationUpdates = false
        
        coldStartFilter.reset()
        lastSavedHex = nil
        currentNeighborhood = nil
        
        isTrackingEnabled = false
        isTracking = false
    }
    
    private func processLocation(_ location: CLLocation) {
        // Keep lastKnownLocation fresh for immediate UI queries even during warmup or mild accuracy convergence
        if location.horizontalAccuracy >= 0 && location.horizontalAccuracy <= 100.0 {
            self.lastKnownLocation = location
        }
        
        let filterResult = coldStartFilter.process(location: location)
        
        switch filterResult {
        case .discardedStale(let age):
            logPipeline("⚠️ [Filter - Stale] Dropping cached/historical fix (age: \(String(format: "%.1f", age))s)")
            return
        case .discardedUncertain(let accuracy):
            logPipeline("⚠️ [Filter - Uncertain] Dropping inaccurate fix (hAcc: \(String(format: "%.1f", accuracy))m > 25m)")
            return
        case .warmingUp(let current, let target):
            logPipeline("⏳ [Filter - Warmup] Buffering fix \(current)/\(target) before first hex unlock")
            return
        case .discardedExcessiveSpeed(let speed):
            logPipeline("⚠️ [Filter - Excessive Speed] Drift gate triggered: Dropping multipath jump (\(String(format: "%.1f", speed)) m/s)")
            return
        case .accepted(let validLocation, _, let stepDistance):
            sessionDistanceMeters += stepDistance
            self.lastKnownLocation = validLocation
            
            // Convert to H3 string to avoid blocking the actor
            do {
                let index = try H3.latLngToCell(latitude: validLocation.coordinate.latitude,
                                                longitude: validLocation.coordinate.longitude,
                                                resolution: 11)
                let indexString = String(index, radix: 16)
                
                logPipeline("📍 [S2 - processLocation] hex=\(indexString), timestamp=\(validLocation.timestamp), lastSavedHex=\(lastSavedHex ?? "nil"), hAcc=\(validLocation.horizontalAccuracy)")
                
                // If still within the same hex, refresh rolling stale date & distance metrics
                if indexString == lastSavedHex {
                    if let activity = currentActivity {
                        let state = TrackingAttributes.ContentState(
                            hexesCleared: sessionHexCount,
                            activeNeighborhood: currentNeighborhood,
                            distanceMeters: sessionDistanceMeters
                        )
                        Task {
                            await activity.update(ActivityContent(state: state, staleDate: Date().addingTimeInterval(45)))
                        }
                    }
                    return
                }
                
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
                            if let nbhd = nbhd {
                                self.currentNeighborhood = nbhd
                            }
                            if isNew {
                                let generator = UIImpactFeedbackGenerator(style: .light)
                                generator.prepare()
                                generator.impactOccurred()
                                self.sessionHexCount += 1
                            }
                            if let activity = self.currentActivity {
                                let state = TrackingAttributes.ContentState(
                                    hexesCleared: self.sessionHexCount,
                                    activeNeighborhood: self.currentNeighborhood,
                                    distanceMeters: self.sessionDistanceMeters
                                )
                                Task {
                                    await activity.update(ActivityContent(state: state, staleDate: Date().addingTimeInterval(45)))
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
}

