import SwiftUI
import CoreLocation
import Observation
import ActivityKit

/// Modern iOS 17+ Observable coordinator managing active multimodal journey execution (Wave N-D.8).
/// Coordinates walking, cycling, and transit legs; automates missed-connection detection;
/// powers the native iOS Live Activity and Dynamic Island lifecycle; and handles 1-tap dynamic recovery.
@Observable
public final class MultimodalTripNavigationManager: @unchecked Sendable {
    
    // MARK: - Singleton & Observable State
    
    @MainActor public static let shared = MultimodalTripNavigationManager()
    
    public var itinerary: JourneyItinerary?
    public var currentLegIndex: Int
    public var isNavigating: Bool
    public var userLocation: CLLocationCoordinate2D?
    public var activeRecoveryPlan: DynamicRecoveryPlan?
    
    // Sub-sessions for specialized active guidance
    public var walkingSession: ActiveWalkingNavigationSession?
    public var cyclingSession: ActiveCyclingNavigationSession?
    
    // Internal dependencies
    private let detector: MissedConnectionDetector
    private let recoveryEngine: DynamicRecoveryEngine
    private var currentActivity: Activity<MultimodalTripAttributes>?
    
    // MARK: - Initializer
    
    public init(
        detector: MissedConnectionDetector = MissedConnectionDetector(),
        recoveryEngine: DynamicRecoveryEngine = DynamicRecoveryEngine()
    ) {
        self.itinerary = nil
        self.currentLegIndex = 0
        self.isNavigating = false
        self.userLocation = nil
        self.activeRecoveryPlan = nil
        self.walkingSession = nil
        self.cyclingSession = nil
        self.detector = detector
        self.recoveryEngine = recoveryEngine
    }
    
    // MARK: - Active Leg Inspection
    
    public var activeLeg: JourneyLeg? {
        guard let itin = itinerary, itin.legs.indices.contains(currentLegIndex) else {
            return nil
        }
        return itin.legs[currentLegIndex]
    }
    
    public var totalLegs: Int {
        itinerary?.legs.count ?? 0
    }
    
    // MARK: - Navigation Lifecycle
    
    /// Starts active multimodal navigation for an itinerary.
    public func startTripNavigation(
        itinerary: JourneyItinerary,
        initialLegIndex: Int = 0,
        enableLiveActivity: Bool = true
    ) {
        self.itinerary = itinerary
        self.currentLegIndex = initialLegIndex
        self.isNavigating = true
        self.activeRecoveryPlan = nil
        
        setupSubSession(forLegIndex: initialLegIndex, in: itinerary)
        
        if enableLiveActivity {
            startLiveActivity()
        }
    }
    
    /// Advance to next leg in itinerary.
    public func advanceToNextLeg() {
        guard let itin = itinerary else { return }
        
        if currentLegIndex < itin.legs.count - 1 {
            currentLegIndex += 1
            setupSubSession(forLegIndex: currentLegIndex, in: itin)
            updateLiveActivity()
            
            #if os(iOS)
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.prepare()
            generator.impactOccurred()
            #endif
        } else {
            endNavigation()
        }
    }
    
    /// Ends active navigation and terminates Live Activity.
    public func endNavigation() {
        self.isNavigating = false
        self.walkingSession?.endNavigation()
        self.cyclingSession?.endCycling()
        self.walkingSession = nil
        self.cyclingSession = nil
        self.activeRecoveryPlan = nil
        
        stopLiveActivity()
    }
    
    // MARK: - Telemetry Ingestion & Missed Connection Detection
    
    /// Updates live passenger position and evaluates missed-connection invariants.
    public func updateUserLocation(
        _ location: CLLocation,
        currentClockSec: UInt32? = nil,
        stationCoordinate: CLLocationCoordinate2D? = nil
    ) {
        guard isNavigating, let itin = itinerary else { return }
        self.userLocation = location.coordinate
        
        // 1. Forward telemetry to active walking or cycling sub-session
        if let walkSession = walkingSession {
            walkSession.updateUserLocation(location.coordinate, horizontalAccuracy: location.horizontalAccuracy)
        }
        if let bikeSession = cyclingSession {
            bikeSession.updateUserLocation(location.coordinate, horizontalAccuracy: location.horizontalAccuracy)
        }
        
        // 2. Resolve clock seconds (either provided or computed from current date)
        let clockSec = currentClockSec ?? resolveCurrentClockSeconds()
        
        // 3. Resolve target transit station coordinate
        let targetCoord: CLLocationCoordinate2D
        if let overrideCoord = stationCoordinate {
            targetCoord = overrideCoord
        } else if let leg = activeLeg, leg.mode.isTransit {
            // Default Midtown fallback coordinate if unmapped
            targetCoord = CLLocationCoordinate2D(latitude: 40.7527, longitude: -73.9772)
        } else if itin.legs.dropFirst(currentLegIndex).contains(where: { $0.mode.isTransit }) {
            targetCoord = CLLocationCoordinate2D(latitude: 40.7527, longitude: -73.9772)
        } else {
            targetCoord = location.coordinate
        }
        
        // 4. Evaluate missed connection criteria if not already in recovery mode
        if activeRecoveryPlan == nil {
            if let event = detector.evaluateConnection(
                itinerary: itin,
                currentLegIndex: currentLegIndex,
                userLocation: location.coordinate,
                userSpeedMps: location.speed >= 0 ? location.speed : nil,
                currentClockSec: clockSec,
                targetStationCoordinate: targetCoord
            ) {
                // Generate recovery plan with 1-tap options
                let plan = recoveryEngine.generateRecoveryPlan(for: event, activeItinerary: itin)
                self.activeRecoveryPlan = plan
                
                // Alert in Live Activity
                updateLiveActivity(recoveryNotice: "Missed \(event.missedLeg.routeId ?? "train") • Tap for Alternative", isMissed: true)
                
                #if os(iOS)
                let generator = UINotificationFeedbackGenerator()
                generator.prepare()
                generator.notificationOccurred(.warning)
                #endif
                return
            }
        }
        
        // 5. Normal tick update to Live Activity
        updateLiveActivity()
    }
    
    // MARK: - 1-Tap Recovery Acceptance
    
    /// Instantly hot-swaps active itinerary with chosen recovery candidate.
    public func acceptRecoveryOption(_ option: DynamicRecoveryOption) {
        logPipeline("🔀 [MultimodalTripNavigationManager] Accepting recovery option: \(option.title)")
        
        self.itinerary = option.recoveryItinerary
        self.activeRecoveryPlan = nil
        
        // Re-setup appropriate sub-session
        setupSubSession(forLegIndex: currentLegIndex, in: option.recoveryItinerary)
        
        // Update Live Activity with refreshed route and cleared alert
        updateLiveActivity(recoveryNotice: nil, isMissed: false)
        
        #if os(iOS)
        let generator = UIImpactFeedbackGenerator(style: .heavy)
        generator.prepare()
        generator.impactOccurred()
        #endif
    }
    
    /// Dismisses active recovery alert and keeps current path.
    public func dismissRecoveryPlan() {
        self.activeRecoveryPlan = nil
        updateLiveActivity(recoveryNotice: nil, isMissed: false)
    }
    
    // MARK: - ActivityKit Integration
    
    private func startLiveActivity() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        guard let itin = itinerary else { return }
        
        let origin = itin.legs.first?.originName ?? "Origin"
        let destination = itin.legs.last?.destinationName ?? "Destination"
        let attributes = MultimodalTripAttributes(
            originName: origin,
            destinationName: destination,
            tripStartTime: Date()
        )
        
        let state = buildContentState(recoveryNotice: nil, isMissed: false)
        
        do {
            currentActivity = try Activity.request(
                attributes: attributes,
                content: ActivityContent(state: state, staleDate: Date().addingTimeInterval(60)),
                pushType: nil
            )
            logPipeline("✨ [MultimodalTripNavigationManager] Live Activity started successfully")
        } catch {
            logPipeline("⚠️ [MultimodalTripNavigationManager] Failed to start Live Activity: \(error)")
        }
    }
    
    private func updateLiveActivity(recoveryNotice: String? = nil, isMissed: Bool = false) {
        guard let activity = currentActivity else { return }
        let state = buildContentState(recoveryNotice: recoveryNotice, isMissed: isMissed)
        
        Task {
            await activity.update(
                ActivityContent(state: state, staleDate: Date().addingTimeInterval(45))
            )
        }
    }
    
    private func stopLiveActivity() {
        guard let activity = currentActivity else { return }
        let state = buildContentState(recoveryNotice: nil, isMissed: false)
        
        Task {
            await activity.end(
                ActivityContent(state: state, staleDate: nil),
                dismissalPolicy: .immediate
            )
        }
        self.currentActivity = nil
    }
    
    public func buildContentState(recoveryNotice: String? = nil, isMissed: Bool = false) -> MultimodalTripAttributes.ContentState {
        guard let itin = itinerary, !itin.legs.isEmpty else {
            return MultimodalTripAttributes.ContentState(
                currentLegIndex: 0,
                totalLegs: 1,
                stepHeadline: "Navigating",
                secondaryContext: "to destination",
                modeRawValue: "walk",
                destinationETA: Date(),
                tripProgressFraction: 0.0
            )
        }
        
        let safeIndex = max(0, min(currentLegIndex, itin.legs.count - 1))
        let leg = itin.legs[safeIndex]
        
        // Synthesize step headline and context
        let headline: String
        let secondary: String
        var countdownSec: Int? = nil
        var targetDepTime: Date? = nil
        
        switch leg.mode {
        case .walk:
            if let cue = walkingSession?.currentCue {
                headline = cue.primaryHeadline
                secondary = cue.secondaryContext
            } else {
                headline = "Walk to \(leg.destinationName)"
                secondary = "\(leg.formattedDistance) • \(leg.formattedDuration)"
            }
        case .subway, .bus, .lightRail, .ferry:
            let routeStr = leg.routeId ?? leg.mode.rawValue.capitalized
            headline = "Board \(routeStr) \(leg.mode == .bus ? "Bus" : "Train")"
            secondary = "at \(leg.originName)"
            
            let nowSec = resolveCurrentClockSeconds()
            if leg.departureTimeSec > nowSec {
                countdownSec = Int(leg.departureTimeSec - nowSec)
                targetDepTime = Date().addingTimeInterval(Double(countdownSec!))
            }
        case .bikeShare, .personalBike:
            if let bike = cyclingSession {
                headline = "\(bike.currentManeuver.conciseVoicePrompt) on \(bike.currentStreetName)"
                secondary = "to \(bike.destinationDockName)"
            } else {
                headline = "Ride to \(leg.destinationName)"
                secondary = "\(leg.formattedDistance)"
            }
        }
        
        let progressFraction = itin.legs.count > 0 ? Double(safeIndex) / Double(itin.legs.count) : 0.0
        let arrivalDate = Date().addingTimeInterval(Double(itin.totalDurationSec))
        
        return MultimodalTripAttributes.ContentState(
            currentLegIndex: safeIndex,
            totalLegs: itin.legs.count,
            stepHeadline: headline,
            secondaryContext: secondary,
            modeRawValue: leg.mode.rawValue,
            routeBadge: leg.routeId,
            routeColorHex: leg.lineInfo?.colorHex,
            departureCountdownSec: countdownSec,
            targetDepartureTime: targetDepTime,
            destinationETA: arrivalDate,
            tripProgressFraction: progressFraction,
            exitCode: leg.exitCode,
            carRecommendation: leg.recommendedCarPosition,
            isMissedConnection: isMissed,
            recoveryNotice: recoveryNotice
        )
    }
    
    // MARK: - Internal Session Setup
    
    private func setupSubSession(forLegIndex index: Int, in itinerary: JourneyItinerary) {
        guard itinerary.legs.indices.contains(index) else { return }
        let leg = itinerary.legs[index]
        
        if leg.mode == .walk {
            self.walkingSession = ActiveWalkingNavigationSession(itinerary: itinerary, initialLegIndex: index)
            self.cyclingSession = nil
        } else if leg.mode == .bikeShare || leg.mode == .personalBike {
            self.cyclingSession = ActiveCyclingNavigationSession(itinerary: itinerary, initialLegIndex: index)
            self.walkingSession = nil
        } else {
            self.walkingSession = nil
            self.cyclingSession = nil
        }
    }
    
    private func resolveCurrentClockSeconds() -> UInt32 {
        let calendar = Calendar.current
        let comps = calendar.dateComponents([.hour, .minute, .second], from: Date())
        let h = comps.hour ?? 0
        let m = comps.minute ?? 0
        let s = comps.second ?? 0
        return UInt32(h * 3600 + m * 60 + s)
    }
}
