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
    
    // MARK: - Mode & Invariants
    
    public let modalClass: TransitModalClass
    
    // MARK: - Private Core State (Guideway & Shared)
    
    @ObservationIgnored private var interpolator: SubwayPositionInterpolator? = nil
    @ObservationIgnored private var currentTelemetry: IngestedTelemetry? = nil
    @ObservationIgnored private nonisolated(unsafe) var displayLink: CADisplayLink? = nil
    @ObservationIgnored private var displayLinkProxy: TrackingDisplayLinkProxy? = nil
    
    @ObservationIgnored private var originPlatformDist: Double = 0.0
    @ObservationIgnored private var targetPlatformDist: Double = 0.0
    
    @ObservationIgnored private var reconciliationError: Double = 0.0
    @ObservationIgnored private var reconciliationStartTime: Double = 0.0
    @ObservationIgnored private var isReconciling: Bool = false
    @ObservationIgnored public private(set) var lastRenderedDistance: Double = 0.0
    
    // MARK: - Surface Dead-Reckoning & Snapping State (Pre-T.8c)
    
    @ObservationIgnored private var lastFixCoordinate: CLLocationCoordinate2D? = nil
    @ObservationIgnored private var lastFixDistance: Double = 0.0
    @ObservationIgnored private var lastFixTime: Double = 0.0
    @ObservationIgnored private var estimatedSpeed: Double = 0.0
    @ObservationIgnored private var isOnCorridor: Bool = true
    @ObservationIgnored private var rawBusBearing: Double = 0.0
    
    public var activeReconciliationError: Double { reconciliationError }
    public var isCurrentlyReconciling: Bool { isReconciling }
    public var isVehicleOnCorridor: Bool { isOnCorridor }
    public var activeEstimatedSpeed: Double { estimatedSpeed }
    public var activeLastFixDistance: Double { lastFixDistance }
    
    // MARK: - Initialization & Deinitialization
    
    public init(modalClass: TransitModalClass = .subway) {
        self.modalClass = modalClass
        setupLifecycleObservers()
    }
    
    deinit {
        // NotificationCenter observer removal and CADisplayLink invalidation
        NotificationCenter.default.removeObserver(self)
        displayLink?.invalidate()
        displayLink = nil
    }
    
    // MARK: - Configuration & Telemetry Helpers
    
    /// Constructs IngestedTelemetry and platform projections from arrival data and stop ladder.
    private func buildTelemetry(
        arrival: SpatialDatabaseManager.ArrivalInfo,
        ladder: [TrackStop],
        now: Double
    ) -> (telemetry: IngestedTelemetry, origDist: Double, targDist: Double)? {
        guard let interp = interpolator else { return nil }
        
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
        
        // Timing derivation
        let interDist = max(100.0, targDist - origDist)
        let nominalDuration = max(30.0, interDist / 15.0) // ~15 m/s typical subway speed
        let departureSec: Double
        let arrivalNextSec: Double
        
        if status == .STOPPED_AT {
            departureSec = arrival.isHoldingStation ? (now - 130.0) : now
            arrivalNextSec = departureSec + 30.0
        } else {
            let lambda: Double
            if arrival.progressLambda > 0.0 {
                lambda = min(0.99, max(0.01, arrival.progressLambda))
            } else if status == .INCOMING_AT {
                lambda = 0.85
            } else {
                lambda = 0.45
            }
            departureSec = now - (nominalDuration * lambda)
            arrivalNextSec = departureSec + nominalDuration
        }
        
        let seq = UInt32(targetStop?.sequenceIndex ?? 1)
        let tripIdStr = std.string(arrival.tripId ?? "")
        let routeIdStr = std.string(arrival.line)
        let stopIdStr = std.string(targetStop?.stopId ?? (currentStop?.stopId ?? ""))
        
        let telem = IngestedTelemetry(
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
        return (telem, origDist, targDist)
    }
    
    // MARK: - Configuration
    
    /// Configures the kinematic interpolator with route polyline geometry and GTFS-RT telemetry.
    public func configure(
        polyline: [CLLocationCoordinate2D],
        arrival: SpatialDatabaseManager.ArrivalInfo,
        ladder: [TrackStop],
        now: Double = Date().timeIntervalSince1970
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
        updateTelemetry(arrival: arrival, ladder: ladder, now: now)
    }
    
    /// Updates the ingested telemetry from a new GTFS-RT feed update.
    public func updateTelemetry(
        arrival: SpatialDatabaseManager.ArrivalInfo,
        ladder: [TrackStop],
        now: Double = Date().timeIntervalSince1970
    ) {
        if modalClass == .bus {
            updateBusTelemetry(arrival: arrival, ladder: ladder, now: now)
            return
        }
        guard let built = buildTelemetry(arrival: arrival, ladder: ladder, now: now) else { return }
        self.originPlatformDist = built.origDist
        self.targetPlatformDist = built.targDist
        self.currentTelemetry = built.telemetry
        self.lastRenderedDistance = built.origDist
        self.reconciliationError = 0.0
        self.isReconciling = false
    }
    
    private func updateBusTelemetry(
        arrival: SpatialDatabaseManager.ArrivalInfo,
        ladder: [TrackStop],
        now: Double
    ) {
        guard let interp = interpolator else { return }
        
        if let rawCoord = arrival.vehicleCoordinate {
            let snapRes = interp.snap_geographic_point(rawCoord.latitude, rawCoord.longitude, 50.0)
            if snapRes.is_on_corridor {
                self.isOnCorridor = true
                let snapped = CLLocationCoordinate2D(
                    latitude: snapRes.snapped_coordinate.latitude,
                    longitude: snapRes.snapped_coordinate.longitude
                )
                self.lastFixCoordinate = snapped
                let dist = snapRes.cumulative_distance
                self.lastFixDistance = dist
                self.lastFixTime = now
                self.lastRenderedDistance = dist
                self.currentCoordinate = snapped
                self.currentBearing = snapRes.heading_degrees
                self.rawBusBearing = arrival.vehicleBearing ?? snapRes.heading_degrees
                let isDwelling = (arrival.minutes <= 0 ||
                                  arrival.distanceDescription == "Boarding" ||
                                  arrival.distanceDescription == "At Platform" ||
                                  arrival.distanceDescription == "At Stop")
                self.estimatedSpeed = isDwelling ? 0.0 : 8.0
                self.reconciliationError = 0.0
                self.isReconciling = false
            } else {
                self.isOnCorridor = false
                self.lastFixCoordinate = rawCoord
                self.lastFixDistance = snapRes.cumulative_distance
                self.lastFixTime = now
                self.currentCoordinate = rawCoord
                let bearing = arrival.vehicleBearing ?? 0.0
                self.currentBearing = bearing
                self.rawBusBearing = bearing
                self.estimatedSpeed = 0.0
                self.reconciliationError = 0.0
                self.isReconciling = false
            }
        } else {
            guard let built = buildTelemetry(arrival: arrival, ladder: ladder, now: now) else { return }
            self.isOnCorridor = true
            self.originPlatformDist = built.origDist
            self.targetPlatformDist = built.targDist
            self.currentTelemetry = built.telemetry
            self.lastRenderedDistance = built.origDist
            self.lastFixDistance = built.origDist
            self.lastFixTime = now
            self.estimatedSpeed = 8.0
            self.reconciliationError = 0.0
            self.isReconciling = false
        }
    }
    
    /// Reconciles new GTFS-RT feed updates with a critically damped 1.0s exponential decay curve
    /// to eliminate teleportation jumps and backward snaps.
    public func reconcile(
        arrival: SpatialDatabaseManager.ArrivalInfo,
        ladder: [TrackStop],
        now: Double = Date().timeIntervalSince1970
    ) {
        if modalClass == .bus {
            reconcileBus(arrival: arrival, ladder: ladder, now: now)
            return
        }
        reconcileGuideway(arrival: arrival, ladder: ladder, now: now)
    }
    
    private func reconcileGuideway(
        arrival: SpatialDatabaseManager.ArrivalInfo,
        ladder: [TrackStop],
        now: Double
    ) {
        guard let interp = interpolator,
              let currentTelem = currentTelemetry else {
            updateTelemetry(arrival: arrival, ladder: ladder, now: now)
            return
        }
        
        // 1. Determine current predicted distance at this exact instant
        let currentEst = interp.update(currentTelem, now)
        let currentInterDist = max(0.0, targetPlatformDist - originPlatformDist)
        let currentRawDist = originPlatformDist + (currentEst.linear_progress * currentInterDist)
        
        let predictedDist: Double
        if isReconciling {
            let dt = max(0.0, now - reconciliationStartTime)
            let omega: Double = 5.0
            let currentOffset = reconciliationError * (1.0 + omega * dt) * exp(-omega * dt)
            let candidate = currentRawDist - currentOffset
            predictedDist = max(lastRenderedDistance, candidate)
        } else {
            predictedDist = max(lastRenderedDistance, currentRawDist)
        }
        
        // 2. Build new telemetry from feed packet
        guard let built = buildTelemetry(arrival: arrival, ladder: ladder, now: now) else { return }
        
        // 3. Evaluate newly reported distance under new telemetry at now
        let newEst = interp.update(built.telemetry, now)
        let newInterDist = max(0.0, built.targDist - built.origDist)
        let reportedDist = built.origDist + (newEst.linear_progress * newInterDist)
        
        // 4. Compute prediction error e_0 = d_reported - d_predicted
        let e0 = reportedDist - predictedDist
        
        self.currentTelemetry = built.telemetry
        self.originPlatformDist = built.origDist
        self.targetPlatformDist = built.targDist
        
        if abs(e0) > 0.05 { // Discrepancies > 5cm trigger damped reconciliation
            self.reconciliationError = e0
            self.reconciliationStartTime = now
            self.isReconciling = true
        } else {
            self.reconciliationError = 0.0
            self.isReconciling = false
        }
        self.lastRenderedDistance = predictedDist
    }
    
    private func reconcileBus(
        arrival: SpatialDatabaseManager.ArrivalInfo,
        ladder: [TrackStop],
        now: Double
    ) {
        guard let interp = interpolator else {
            updateTelemetry(arrival: arrival, ladder: ladder, now: now)
            return
        }
        
        guard let rawCoord = arrival.vehicleCoordinate else {
            reconcileGuideway(arrival: arrival, ladder: ladder, now: now)
            return
        }
        
        let snapRes = interp.snap_geographic_point(rawCoord.latitude, rawCoord.longitude, 50.0)
        
        if snapRes.is_on_corridor {
            self.isOnCorridor = true
            let newReportedDist = snapRes.cumulative_distance
            
            // 1. Calculate current predicted distance at now
            let dtDeadReckon = min(30.0, max(0.0, now - lastFixTime))
            let unadjustedDist = lastFixDistance + (estimatedSpeed * dtDeadReckon)
            
            let predictedDist: Double
            if isReconciling {
                let dt = max(0.0, now - reconciliationStartTime)
                let omega: Double = 5.0
                let currentOffset = reconciliationError * (1.0 + omega * dt) * exp(-omega * dt)
                let candidate = unadjustedDist - currentOffset
                predictedDist = max(lastRenderedDistance, candidate)
            } else {
                predictedDist = max(lastRenderedDistance, unadjustedDist)
            }
            
            // 2. Estimate new speed v_est clamped to [0, 22 m/s]
            let dtFix = now - lastFixTime
            let ddFix = newReportedDist - lastFixDistance
            let isDwelling = (arrival.minutes <= 0 ||
                              arrival.distanceDescription == "Boarding" ||
                              arrival.distanceDescription == "At Platform" ||
                              arrival.distanceDescription == "At Stop")
            
            if isDwelling {
                self.estimatedSpeed = 0.0
            } else if dtFix > 0.0 && dtFix <= 60.0 {
                let rawSpeed = ddFix / dtFix
                self.estimatedSpeed = min(22.0, max(0.0, rawSpeed))
            } else {
                self.estimatedSpeed = 8.0
            }
            
            // 3. Compute prediction error e_0 = d_reported - d_predicted
            let e0 = newReportedDist - predictedDist
            self.lastFixDistance = newReportedDist
            self.lastFixTime = now
            self.lastFixCoordinate = CLLocationCoordinate2D(
                latitude: snapRes.snapped_coordinate.latitude,
                longitude: snapRes.snapped_coordinate.longitude
            )
            self.rawBusBearing = arrival.vehicleBearing ?? snapRes.heading_degrees
            
            if abs(e0) > 0.05 {
                self.reconciliationError = e0
                self.reconciliationStartTime = now
                self.isReconciling = true
            } else {
                self.reconciliationError = 0.0
                self.isReconciling = false
            }
            self.lastRenderedDistance = predictedDist
        } else {
            // Off-corridor (>50m): Retain raw GPS fix without snapping, disable dead-reckoning
            self.isOnCorridor = false
            self.lastFixCoordinate = rawCoord
            self.lastFixDistance = snapRes.cumulative_distance
            self.lastFixTime = now
            self.currentCoordinate = rawCoord
            let bearing = arrival.vehicleBearing ?? 0.0
            self.currentBearing = bearing
            self.rawBusBearing = bearing
            self.estimatedSpeed = 0.0
            self.reconciliationError = 0.0
            self.isReconciling = false
        }
    }
    
    // MARK: - Simulation Frame Step (30Hz CADisplayLink & Headless Simulation)
    
    internal func step(_ link: CADisplayLink) {
        guard isRunning else { return }
        stepSimulation(at: Date().timeIntervalSince1970)
    }
    
    internal func stepSimulation(at now: Double) {
        if modalClass == .bus {
            stepBusSimulation(at: now)
        } else {
            stepGuidewaySimulation(at: now)
        }
    }
    
    private func stepBusSimulation(at now: Double) {
        if !isOnCorridor {
            if let coord = lastFixCoordinate {
                self.currentCoordinate = coord
                self.currentBearing = rawBusBearing
                onVehicleFrame?(coord, rawBusBearing)
            }
            return
        }
        
        guard let interp = interpolator else { return }
        let dtDeadReckon = min(30.0, max(0.0, now - lastFixTime))
        let rawDist = lastFixDistance + (estimatedSpeed * dtDeadReckon)
        
        let displayDist: Double
        if isReconciling {
            let dt = max(0.0, now - reconciliationStartTime)
            if dt >= 1.5 {
                self.isReconciling = false
                self.reconciliationError = 0.0
                displayDist = max(lastRenderedDistance, rawDist)
            } else {
                let omega: Double = 5.0
                let offset = reconciliationError * (1.0 + omega * dt) * exp(-omega * dt)
                let candidateDist = rawDist - offset
                displayDist = max(lastRenderedDistance, candidateDist)
            }
        } else {
            displayDist = max(lastRenderedDistance, rawDist)
        }
        
        self.lastRenderedDistance = displayDist
        
        var headingRad: Double = 0.0
        let pt = interp.interpolate_point_at_distance(displayDist, &headingRad)
        let geo = interp.to_geographic(pt)
        var headingDeg = headingRad * (180.0 / .pi)
        if headingDeg < 0.0 { headingDeg += 360.0 }
        if headingDeg >= 360.0 { headingDeg -= 360.0 }
        
        let coord = CLLocationCoordinate2D(latitude: geo.latitude, longitude: geo.longitude)
        self.currentCoordinate = coord
        self.currentBearing = headingDeg
        
        let totalDist = interp.total_shape_distance()
        self.linearProgress = (totalDist > 0.0) ? min(1.0, max(0.0, displayDist / totalDist)) : 0.0
        
        onVehicleFrame?(coord, headingDeg)
    }
    
    private func stepGuidewaySimulation(at now: Double) {
        guard let interp = interpolator,
              let telem = currentTelemetry else { return }
        
        let estimate = interp.update(telem, now)
        let interDist = max(0.0, targetPlatformDist - originPlatformDist)
        let rawDist = originPlatformDist + (estimate.linear_progress * interDist)
        
        let displayDist: Double
        if isReconciling {
            let dt = max(0.0, now - reconciliationStartTime)
            if dt >= 1.5 {
                self.isReconciling = false
                self.reconciliationError = 0.0
                displayDist = max(lastRenderedDistance, rawDist)
            } else {
                let omega: Double = 5.0
                let offset = reconciliationError * (1.0 + omega * dt) * exp(-omega * dt)
                let candidateDist = rawDist - offset
                displayDist = max(lastRenderedDistance, candidateDist)
            }
        } else {
            displayDist = max(lastRenderedDistance, rawDist)
        }
        
        self.lastRenderedDistance = displayDist
        
        let coord: CLLocationCoordinate2D
        let bearing: Double
        
        if abs(displayDist - rawDist) < 1e-4 {
            coord = CLLocationCoordinate2D(latitude: estimate.latitude, longitude: estimate.longitude)
            bearing = estimate.heading_degrees
        } else {
            var headingRad: Double = 0.0
            let pt = interp.interpolate_point_at_distance(displayDist, &headingRad)
            let geo = interp.to_geographic(pt)
            var headingDeg = headingRad * (180.0 / .pi)
            if headingDeg < 0.0 { headingDeg += 360.0 }
            if headingDeg >= 360.0 { headingDeg -= 360.0 }
            coord = CLLocationCoordinate2D(latitude: geo.latitude, longitude: geo.longitude)
            bearing = headingDeg
        }
        
        self.currentCoordinate = coord
        self.currentBearing = bearing
        self.linearProgress = (interDist > 0.0) ? min(1.0, max(0.0, (displayDist - originPlatformDist) / interDist)) : estimate.linear_progress
        
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
