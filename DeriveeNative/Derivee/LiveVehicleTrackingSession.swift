import Foundation
import CoreLocation
import QuartzCore
import UIKit
import CxxStdlib
import DeriveeCore

// MARK: - CADisplayLink Weak Proxy

/// Prevents strong retain cycles between CADisplayLink and the tracking session.
@MainActor
private final class TrackingDisplayLinkProxy {
    weak var target: LiveVehicleTrackingSession?
    
    init(target: LiveVehicleTrackingSession) {
        self.target = target
    }
    
    @objc func onDisplayLinkTick(_ link: CADisplayLink) {
        target?.step(link)
    }
}

// MARK: - Live Vehicle Tracking Session

/// Bridges C++20 SubwayPositionInterpolator (Research Doc 17) into Swift.
/// Owned by GuidewayRunInspector to drive 30Hz consist position animation along
/// track geometry with zero SwiftUI body re-evaluations and 0% background idle battery drain.
@Observable
@MainActor
public final class LiveVehicleTrackingSession {
    
    // MARK: - Observable Discrete State (UI-Glanceable)
    
    public private(set) var isHolding: Bool = false
    public private(set) var isStale: Bool = false
    public private(set) var linearProgress: Double = 0.0
    public private(set) var isRunning: Bool = false
    public private(set) var currentCoordinate: CLLocationCoordinate2D? = nil
    public private(set) var currentBearing: Double = 0.0
    
    // MARK: - Direct High-Frequency Callback (Zero SwiftUI Body Churn)
    
    /// High-frequency frame callback dispatched directly to MapLibre Coordinator.
    public var onVehicleFrame: ((CLLocationCoordinate2D, Double) -> Void)? = nil
    
    // MARK: - Private Core State
    
    @ObservationIgnored private var interpolator: SubwayPositionInterpolator? = nil
    @ObservationIgnored private var currentTelemetry: IngestedTelemetry? = nil
    @ObservationIgnored private nonisolated(unsafe) var displayLink: CADisplayLink? = nil
    @ObservationIgnored private var displayLinkProxy: TrackingDisplayLinkProxy? = nil
    
    @ObservationIgnored private var originPlatformDist: Double = 0.0
    @ObservationIgnored private var targetPlatformDist: Double = 0.0
    
    // MARK: - Initialization & Deinitialization
    
    public init() {
        setupLifecycleObservers()
    }
    
    deinit {
        // NotificationCenter observer removal and CADisplayLink invalidation
        NotificationCenter.default.removeObserver(self)
        displayLink?.invalidate()
        displayLink = nil
    }
    
    // MARK: - Configuration
    
    /// Configures the kinematic interpolator with route polyline geometry and GTFS-RT telemetry.
    public func configure(
        polyline: [CLLocationCoordinate2D],
        arrival: SpatialDatabaseManager.ArrivalInfo,
        ladder: [TrackStop]
    ) {
        guard !polyline.isEmpty else {
            stop()
            return
        }
        
        let refLat = polyline.first?.latitude ?? 40.7128
        let refLon = polyline.first?.longitude ?? -74.0060
        
        // 1. Build C++ Conformal Geometry
        let geoCoords = polyline.map { GeoCoordinate($0.latitude, $0.longitude) }
        let interp = geoCoords.withUnsafeBufferPointer { buf in
            SubwayPositionInterpolator.from_geographic_coords(
                buf.baseAddress,
                buf.count,
                refLat,
                refLon
            )
        }
        self.interpolator = interp
        
        // 2. Resolve Station Projection Distances & Status
        updateTelemetry(arrival: arrival, ladder: ladder)
    }
    
    /// Updates the ingested telemetry from a new GTFS-RT feed update.
    public func updateTelemetry(
        arrival: SpatialDatabaseManager.ArrivalInfo,
        ladder: [TrackStop]
    ) {
        guard let interp = interpolator else { return }
        
        let currentIdx = ladder.firstIndex(where: { $0.isCurrent }) ?? 0
        let currentStop = ladder.indices.contains(currentIdx) ? ladder[currentIdx] : ladder.first
        
        let vehicleIdx = ladder.firstIndex(where: { $0.isVehicleHere })
        let isAtPlatform = (arrival.minutes <= 0 ||
                            arrival.distanceDescription == "Boarding" ||
                            arrival.distanceDescription == "At Platform")
        
        let status: GTFSVehicleStatus
        let originStop: TrackStop?
        let targetStop: TrackStop?
        
        if isAtPlatform {
            status = .STOPPED_AT
            originStop = ladder.first(where: { $0.isVehicleHere }) ?? currentStop
            targetStop = originStop
        } else if arrival.distanceDescription == "Approaching" || arrival.minutes <= 1 {
            status = .INCOMING_AT
            if let vIdx = vehicleIdx, vIdx + 1 < ladder.count {
                originStop = ladder[vIdx]
                targetStop = ladder[vIdx + 1]
            } else if currentIdx > 0 {
                originStop = ladder[currentIdx - 1]
                targetStop = ladder[currentIdx]
            } else {
                originStop = currentStop
                targetStop = currentStop
            }
        } else {
            status = .IN_TRANSIT_TO
            if let vIdx = vehicleIdx, vIdx + 1 < ladder.count {
                originStop = ladder[vIdx]
                targetStop = ladder[vIdx + 1]
            } else if currentIdx > 0 {
                originStop = ladder[currentIdx - 1]
                targetStop = ladder[currentIdx]
            } else {
                originStop = currentStop
                targetStop = currentStop
            }
        }
        
        let now = Date().timeIntervalSince1970
        let feedTime = now
        
        // Platform linear distances along polyline
        let origDist: Double
        let targDist: Double
        if let orig = originStop {
            origDist = interp.project_geographic_point(orig.coordinate.latitude, orig.coordinate.longitude)
        } else {
            origDist = 0.0
        }
        
        if let targ = targetStop {
            targDist = interp.project_geographic_point(targ.coordinate.latitude, targ.coordinate.longitude)
        } else {
            targDist = origDist
        }
        
        self.originPlatformDist = origDist
        self.targetPlatformDist = targDist
        
        // Timing derivation
        let arrivalNextSec = now + Double(max(0, arrival.minutes) * 60)
        let interDist = max(100.0, targDist - origDist)
        let nominalDuration = max(30.0, interDist / 15.0) // ~15 m/s typical subway speed
        let departureSec: Double
        
        if status == .STOPPED_AT {
            departureSec = arrival.isHoldingStation ? (now - 130.0) : now
        } else {
            departureSec = arrivalNextSec - nominalDuration
        }
        
        let seq = UInt32(targetStop?.sequenceIndex ?? 1)
        let tripIdStr = std.string(arrival.tripId ?? "")
        let routeIdStr = std.string(arrival.line)
        let stopIdStr = std.string(targetStop?.stopId ?? (currentStop?.stopId ?? ""))
        
        self.currentTelemetry = IngestedTelemetry(
            tripIdStr,
            routeIdStr,
            seq,
            stopIdStr,
            status,
            arrival.isAssigned,
            departureSec,
            arrivalNextSec,
            feedTime,
            origDist,
            targDist
        )
    }
    
    // MARK: - Simulation Frame Step (30Hz CADisplayLink)
    
    internal func step(_ link: CADisplayLink) {
        guard isRunning,
              let interp = interpolator,
              let telem = currentTelemetry else { return }
        
        let now = Date().timeIntervalSince1970
        let estimate = interp.update(telem, now)
        
        let coord = CLLocationCoordinate2D(latitude: estimate.latitude, longitude: estimate.longitude)
        let bearing = estimate.heading_degrees
        
        self.currentCoordinate = coord
        self.currentBearing = bearing
        self.linearProgress = estimate.linear_progress
        
        // 1. Direct high-frequency dispatch (MapLibre render pipeline, zero SwiftUI body re-evaluation)
        onVehicleFrame?(coord, bearing)
        
        // 2. Discrete state updates (only mutate observed values when changed)
        let newHolding = estimate.is_holding
        if isHolding != newHolding {
            self.isHolding = newHolding
        }
        
        let newStale = (estimate.visual_state == VisualState.TELEMETRY_STALE)
        if isStale != newStale {
            self.isStale = newStale
        }
    }
    
    // MARK: - Lifecycle Controls
    
    /// Starts the 30Hz display link loop.
    public func start() {
        guard displayLink == nil else {
            resume()
            return
        }
        
        let proxy = TrackingDisplayLinkProxy(target: self)
        self.displayLinkProxy = proxy
        
        let link = CADisplayLink(target: proxy, selector: #selector(TrackingDisplayLinkProxy.onDisplayLinkTick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 30, preferred: 30)
        link.add(to: .main, forMode: .common)
        
        self.displayLink = link
        self.isRunning = true
    }
    
    /// Pauses the display link loop (e.g. app in background).
    public func pause() {
        displayLink?.isPaused = true
        self.isRunning = false
    }
    
    /// Resumes the display link loop when returning to foreground.
    public func resume() {
        guard let link = displayLink else {
            start()
            return
        }
        link.isPaused = false
        self.isRunning = true
    }
    
    /// Permanently stops and invalidates the display link.
    public func stop() {
        displayLink?.invalidate()
        displayLink = nil
        displayLinkProxy = nil
        self.isRunning = false
    }
    
    // MARK: - App Lifecycle Observers
    
    private func setupLifecycleObservers() {
        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.pause()
            }
        }
        
        NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.resume()
            }
        }
    }
}
