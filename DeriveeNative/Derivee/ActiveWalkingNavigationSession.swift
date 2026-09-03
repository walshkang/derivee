import SwiftUI
import CoreLocation
import Observation

/// Modern iOS 17+ Observable active walking navigation state machine (Wave N-D.6.1).
/// Tracks real-time pedestrian progress against journey walking legs, evaluates dynamic decision zones,
/// executes two-stage tactile cueing, manages the subterranean egress handshake, and exposes the ephemeral
/// traffic signal coordinate for the hero map canvas.
@Observable
public final class ActiveWalkingNavigationSession: @unchecked Sendable {
    
    // MARK: - Published Reactive State
    
    public var itinerary: JourneyItinerary
    public var currentLegIndex: Int
    public var currentAnchorIndex: Int
    public var currentDistanceMeters: Double
    public var currentCue: NaturalGuidanceCue
    public var activeSignalCoordinate: CLLocationCoordinate2D?
    public var isNavigating: Bool
    public var userLocation: CLLocationCoordinate2D?
    public var isStabilizedAfterEgress: Bool
    
    // Internal state tracking
    private var previousZone: GuidanceDecisionZone?
    private let engine = NaturalWalkingGuidanceEngine.shared
    
    // MARK: - Initializer
    
    public init(itinerary: JourneyItinerary, initialLegIndex: Int = 0) {
        self.itinerary = itinerary
        self.currentLegIndex = initialLegIndex
        self.currentAnchorIndex = 0
        self.currentDistanceMeters = 0.0
        self.isNavigating = true
        self.isStabilizedAfterEgress = false
        self.userLocation = nil
        self.activeSignalCoordinate = nil
        
        // Initial fallback cue
        let initialLeg = itinerary.legs.indices.contains(initialLegIndex) ? itinerary.legs[initialLegIndex] : itinerary.legs.first
        let initialAnchor = initialLeg?.landmarkAnchors.first
        
        if let anchor = initialAnchor {
            self.currentCue = NaturalWalkingGuidanceEngine.shared.synthesizeDynamicCue(
                anchor: anchor,
                distanceMeters: Double(anchor.distanceMeters),
                hasTrafficSignal: false,
                isGridTopology: true,
                exitCode: initialLeg?.exitCode
            )
        } else {
            self.currentCue = NaturalGuidanceCue(
                primaryHeadline: "Start walking",
                secondaryContext: initialLeg?.originName ?? "to destination",
                decisionZone: .foresight,
                maneuver: .depart,
                distanceMeters: 0
            )
        }
        
        recalculateCue()
    }
    
    // MARK: - Active Walk Leg Inspection
    
    public var activeLeg: JourneyLeg? {
        guard itinerary.legs.indices.contains(currentLegIndex) else { return nil }
        return itinerary.legs[currentLegIndex]
    }
    
    public var activeAnchor: LandmarkWalkingAnchor? {
        guard let leg = activeLeg, leg.landmarkAnchors.indices.contains(currentAnchorIndex) else {
            return nil
        }
        return leg.landmarkAnchors[currentAnchorIndex]
    }
    
    // MARK: - User Telemetry Ingestion
    
    /// Updates user position, evaluates zone transitions, and executes two-stage tactile cueing.
    public func updateUserLocation(_ location: CLLocationCoordinate2D, horizontalAccuracy: Double = 5.0) {
        self.userLocation = location
        
        guard let leg = activeLeg, leg.mode == .walk else { return }
        guard let anchor = activeAnchor else { return }
        
        // Determine target waypoint coordinate
        let targetCoord = coordinateForAnchor(anchor, in: leg)
        let dist = SalientCommercialAnchorCatalog.distanceMeters(from: location, to: targetCoord)
        self.currentDistanceMeters = dist
        
        // Handle subterranean egress stabilization check (within 20m of exit portal)
        if let _ = leg.exitCode, currentAnchorIndex == 0 {
            if dist > 20.0 && horizontalAccuracy <= 15.0 {
                self.isStabilizedAfterEgress = true
            }
        }
        
        // Check for step advance threshold (<= 10m)
        if dist <= NaturalWalkingGuidanceEngine.advanceThresholdMeters && currentAnchorIndex < leg.landmarkAnchors.count - 1 {
            advanceToNextStep()
            return
        }
        
        recalculateCue()
    }
    
    /// Advance to the next decision anchor along the current walking leg.
    public func advanceToNextStep() {
        guard let leg = activeLeg else { return }
        
        if currentAnchorIndex < leg.landmarkAnchors.count - 1 {
            currentAnchorIndex += 1
            previousZone = nil
            
            // Haptic completion tick
            #if os(iOS)
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.prepare()
            generator.impactOccurred()
            #endif
            
            recalculateCue()
        } else if currentLegIndex < itinerary.legs.count - 1 {
            currentLegIndex += 1
            currentAnchorIndex = 0
            previousZone = nil
            recalculateCue()
        } else {
            // Reached destination
            isNavigating = false
        }
    }
    
    public func endNavigation() {
        isNavigating = false
    }
    
    // MARK: - Internal Recalculation
    
    private func recalculateCue() {
        guard let leg = activeLeg else { return }
        
        if leg.mode != .walk {
            currentCue = NaturalGuidanceCue(
                primaryHeadline: "Board \(leg.routeId ?? "transit")",
                secondaryContext: "at \(leg.originName)",
                decisionZone: .imminent,
                maneuver: .depart,
                distanceMeters: 0
            )
            activeSignalCoordinate = nil
            return
        }
        
        guard let anchor = activeAnchor else { return }
        
        // Ground-truth traffic signal verification
        let hasSignal = verifyTrafficSignal(for: anchor, in: leg)
        let anchorCoord = coordinateForAnchor(anchor, in: leg)
        
        // Evaluate subterranean exit handshake
        let activeExitCode = (!isStabilizedAfterEgress && currentAnchorIndex == 0) ? leg.exitCode : nil
        
        // Synthesize dynamic cue
        let cue = engine.synthesizeDynamicCue(
            anchor: anchor,
            distanceMeters: currentDistanceMeters,
            hasTrafficSignal: hasSignal,
            isGridTopology: true,
            previousZone: previousZone,
            exitCode: activeExitCode
        )
        
        // Two-Stage Tactile Cueing: Trigger medium haptic when transitioning into Imminent zone
        if cue.decisionZone == .imminent && previousZone != .imminent && previousZone != nil {
            #if os(iOS)
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.prepare()
            generator.impactOccurred()
            #endif
        }
        
        self.previousZone = cue.decisionZone
        self.currentCue = cue
        
        // Ephemeral Signal Pin on Hero Map Canvas: visible only in Approach zone for verified signals
        if cue.decisionZone == .approach && hasSignal {
            self.activeSignalCoordinate = anchorCoord
        } else {
            self.activeSignalCoordinate = nil
        }
    }
    
    // MARK: - Helpers
    
    private func verifyTrafficSignal(for anchor: LandmarkWalkingAnchor, in leg: JourneyLeg) -> Bool {
        // 1. Check SalientCommercialAnchor catalog
        if let brand = SalientCommercialAnchorCatalog.anchors.first(where: { $0.name == anchor.landmarkName || $0.name == anchor.businessName }) {
            return brand.hasTrafficSignal
        }
        
        // 2. Manhattan Avenue Crossing Rule: Any numbered street crossing an Avenue/Broadway has traffic signals
        if let street = anchor.streetName {
            let avenues = ["Avenue", "Ave", "Broadway", "Bowery"]
            if avenues.contains(where: { street.localizedCaseInsensitiveContains($0) }) {
                return true
            }
        }
        
        return false
    }
    
    private func coordinateForAnchor(_ anchor: LandmarkWalkingAnchor, in leg: JourneyLeg) -> CLLocationCoordinate2D {
        if let brand = SalientCommercialAnchorCatalog.anchors.first(where: { $0.name == anchor.landmarkName || $0.name == anchor.businessName }) {
            return brand.coordinate
        }
        
        // Fallback to Midtown default coordinates if unmapped
        return CLLocationCoordinate2D(latitude: 40.7538, longitude: -73.9806)
    }
}
