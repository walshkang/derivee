import Foundation
import CoreFoundation
#if canImport(WidgetKit)
import WidgetKit
#endif

/// High-performance cross-process IPC service coordinating tracking commands and state synchronization
/// between App Intents, Control Center widgets, and the host application via Darwin notifications and App Group defaults.
public final class AmbientTrackingIPCService: @unchecked Sendable {
    public static var shared = AmbientTrackingIPCService()
    
    /// Darwin notification name posted by out-of-process intents to command the tracking engine.
    public static let commandNotification = "com.derivee.tracking.command"
    
    /// Darwin notification name posted by the tracking engine when active tracking status changes.
    public static let statusNotification = "com.derivee.tracking.statusChanged"
    
    private final class ObserverBox: @unchecked Sendable {
        let queue: DispatchQueue
        let block: () -> Void
        init(queue: DispatchQueue, _ block: @escaping () -> Void) {
            self.queue = queue
            self.block = block
        }
    }
    
    private let userDefaults: UserDefaults
    private var commandObserverPtr: UnsafeMutableRawPointer? = nil
    private var statusObserverPtr: UnsafeMutableRawPointer? = nil
    private let lock = NSLock()
    
    public init(userDefaults: UserDefaults = AppGroupConfig.sharedUserDefaults) {
        self.userDefaults = userDefaults
    }
    
    deinit {
        stopListening()
    }
    
    // MARK: - Darwin Notification Observation
    
    /// Registers a listener for commands sent from out-of-process App Intents or Widgets.
    /// - Parameters:
    ///   - queue: The dispatch queue on which the handler closure will be executed (default is `.main`).
    ///   - handler: Closure invoked with the requested target state: `true` (start), `false` (stop), or `nil` (toggle).
    public func registerCommandHandler(
        queue: DispatchQueue = .main,
        handler: @escaping @Sendable (Bool?) -> Void
    ) {
        lock.lock()
        defer { lock.unlock() }
        
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        let notifName = CFNotificationName(Self.commandNotification as CFString)
        
        if let existing = commandObserverPtr {
            CFNotificationCenterRemoveObserver(center, existing, notifName, nil)
            Unmanaged<ObserverBox>.fromOpaque(existing).release()
            commandObserverPtr = nil
        }
        
        let box = ObserverBox(queue: queue) { [weak self] in
            guard let self = self else { return }
            let requestedState = self.fetchRequestedState()
            handler(requestedState)
        }
        
        let ptr = Unmanaged.passRetained(box).toOpaque()
        commandObserverPtr = ptr
        
        CFNotificationCenterAddObserver(
            center,
            ptr,
            { (_, observer, _, _, _) in
                guard let observer = observer else { return }
                let box = Unmanaged<ObserverBox>.fromOpaque(observer).takeUnretainedValue()
                box.queue.async {
                    box.block()
                }
            },
            notifName.rawValue,
            nil,
            .deliverImmediately
        )
    }
    
    /// Registers a listener for state change updates published by the main application's tracking engine.
    /// - Parameters:
    ///   - queue: The dispatch queue on which the handler closure will be executed (default is `.main`).
    ///   - handler: Closure invoked with the newly updated `AmbientTrackingStatus`.
    public func registerStatusHandler(
        queue: DispatchQueue = .main,
        handler: @escaping @Sendable (AmbientTrackingStatus) -> Void
    ) {
        lock.lock()
        defer { lock.unlock() }
        
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        let notifName = CFNotificationName(Self.statusNotification as CFString)
        
        if let existing = statusObserverPtr {
            CFNotificationCenterRemoveObserver(center, existing, notifName, nil)
            Unmanaged<ObserverBox>.fromOpaque(existing).release()
            statusObserverPtr = nil
        }
        
        let box = ObserverBox(queue: queue) { [weak self] in
            guard let self = self else { return }
            let current = self.currentStatus()
            handler(current)
        }
        
        let ptr = Unmanaged.passRetained(box).toOpaque()
        statusObserverPtr = ptr
        
        CFNotificationCenterAddObserver(
            center,
            ptr,
            { (_, observer, _, _, _) in
                guard let observer = observer else { return }
                let box = Unmanaged<ObserverBox>.fromOpaque(observer).takeUnretainedValue()
                box.queue.async {
                    box.block()
                }
            },
            notifName.rawValue,
            nil,
            .deliverImmediately
        )
    }
    
    /// Unregisters all active Darwin notification listeners.
    public func stopListening() {
        lock.lock()
        defer { lock.unlock() }
        
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        
        if let ptr = commandObserverPtr {
            CFNotificationCenterRemoveObserver(center, ptr, CFNotificationName(Self.commandNotification as CFString), nil)
            Unmanaged<ObserverBox>.fromOpaque(ptr).release()
            commandObserverPtr = nil
        }
        
        if let ptr = statusObserverPtr {
            CFNotificationCenterRemoveObserver(center, ptr, CFNotificationName(Self.statusNotification as CFString), nil)
            Unmanaged<ObserverBox>.fromOpaque(ptr).release()
            statusObserverPtr = nil
        }
    }
    
    // MARK: - Command Dispatch (Out-of-Process -> In-Process)
    
    /// Sends an out-of-process command to start, stop, or toggle ambient exploration tracking.
    /// Writes the desired preference to shared `UserDefaults` and dispatches the Darwin notification.
    /// - Parameter enable: `true` to start, `false` to stop, or `nil` to toggle current state.
    /// - Returns: The new target boolean state.
    @discardableResult
    public func sendCommand(enable: Bool? = nil) -> Bool {
        let targetState: Bool
        if let explicit = enable {
            targetState = explicit
        } else {
            // Toggle current preference
            let current = userDefaults.bool(forKey: AppGroupKeys.isTrackingEnabled)
            targetState = !current
        }
        
        userDefaults.set(targetState, forKey: AppGroupKeys.isTrackingEnabled)
        userDefaults.set(Date().timeIntervalSince1970, forKey: AppGroupKeys.lastStateChangeTimestamp)
        
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        let name = CFNotificationName(Self.commandNotification as CFString)
        CFNotificationCenterPostNotification(center, name, nil, nil, true)
        
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        if #available(iOS 18.0, *) {
            ControlCenter.shared.reloadAllControls()
        }
        #endif
        
        return targetState
    }
    
    // MARK: - Engine State Publishing (In-Process -> Out-of-Process)
    
    /// Called by `AmbientTrackingEngine` when its runtime execution state, hex count, or neighborhood updates.
    /// Persists the updated snapshot into shared App Group `UserDefaults` and notifies external observers.
    public func publishEngineState(
        isActive: Bool,
        sessionHexCount: Int = 0,
        sessionDistanceMeters: Double = 0.0,
        activeNeighborhood: String? = nil
    ) {
        userDefaults.set(isActive, forKey: AppGroupKeys.isTrackingActive)
        userDefaults.set(isActive, forKey: AppGroupKeys.isTrackingEnabled)
        userDefaults.set(sessionHexCount, forKey: AppGroupKeys.sessionHexCount)
        userDefaults.set(sessionDistanceMeters, forKey: AppGroupKeys.sessionDistanceMeters)
        if let nbhd = activeNeighborhood {
            userDefaults.set(nbhd, forKey: AppGroupKeys.activeNeighborhood)
        } else {
            userDefaults.removeObject(forKey: AppGroupKeys.activeNeighborhood)
        }
        userDefaults.set(Date().timeIntervalSince1970, forKey: AppGroupKeys.lastStateChangeTimestamp)
        
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        let name = CFNotificationName(Self.statusNotification as CFString)
        CFNotificationCenterPostNotification(center, name, nil, nil, true)
        
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        if #available(iOS 18.0, *) {
            ControlCenter.shared.reloadAllControls()
        }
        #endif
    }
    
    // MARK: - Status Queries
    
    /// Retrieves a synchronous snapshot of the current ambient tracking state from shared storage.
    public func currentStatus() -> AmbientTrackingStatus {
        let isEnabled: Bool
        if userDefaults.object(forKey: AppGroupKeys.isTrackingEnabled) == nil {
            isEnabled = true
        } else {
            isEnabled = userDefaults.bool(forKey: AppGroupKeys.isTrackingEnabled)
        }
        
        let isActive = userDefaults.bool(forKey: AppGroupKeys.isTrackingActive)
        let hexCount = userDefaults.integer(forKey: AppGroupKeys.sessionHexCount)
        let distance = userDefaults.double(forKey: AppGroupKeys.sessionDistanceMeters)
        let neighborhood = userDefaults.string(forKey: AppGroupKeys.activeNeighborhood)
        let timestamp = userDefaults.double(forKey: AppGroupKeys.lastStateChangeTimestamp)
        let lastUpdated = timestamp > 0 ? Date(timeIntervalSince1970: timestamp) : Date()
        
        return AmbientTrackingStatus(
            isEnabled: isEnabled,
            isActive: isActive,
            sessionHexCount: hexCount,
            sessionDistanceMeters: distance,
            activeNeighborhood: neighborhood,
            lastUpdated: lastUpdated
        )
    }
    
    private func fetchRequestedState() -> Bool? {
        if userDefaults.object(forKey: AppGroupKeys.isTrackingEnabled) == nil {
            return nil
        }
        return userDefaults.bool(forKey: AppGroupKeys.isTrackingEnabled)
    }
}
