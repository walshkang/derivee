import Foundation
import CoreLocation

// MARK: - Natural Guidance Domain Models

/// Cognitive decision zones defining pedestrian spatial orientation and action readiness.
public enum GuidanceDecisionZone: String, Sendable, Codable, Equatable {
    /// Distal overview (> 120m / > 1.5 blocks): Orients the user so they can walk heads-up.
    case foresight
    /// Medial approach (30m – 120m / ~1 block out): Prepares the user to scan the streetscape for the upcoming turn/light.
    case approach
    /// Proximal execution (<= 30m / at corner): Unambiguous execution directive right at the curb.
    case imminent
}

/// Real-world intersection control classification.
public enum IntersectionControl: String, Sendable, Codable, Equatable {
    case trafficSignal
    case stopSign
    case standardCorner
    
    public var iconName: String {
        switch self {
        case .trafficSignal: return "light.beacon.max.fill"
        case .stopSign: return "octagon.fill"
        case .standardCorner: return "arrow.triangle.turn.up.right.diamond.fill"
        }
    }
}

/// A synthesized natural guidance instruction cue formatted for glanceable pedestrian consumption.
public struct NaturalGuidanceCue: Identifiable, Sendable, Codable, Equatable {
    public let id: UUID
    /// Primary punchy headline (<= 28 chars, glanceable in < 0.5s): e.g. "At the next light, turn left"
    public let primaryHeadline: String
    /// Secondary contextual grounding: e.g. "onto 5th Ave • past Starbucks"
    public let secondaryContext: String
    /// Current decision zone
    public let decisionZone: GuidanceDecisionZone
    /// Number of blocks ahead (nil if irregular topology or non-grid corridor)
    public let blockCount: Int?
    /// Verified intersection control
    public let intersectionControl: IntersectionControl
    /// Directional maneuver
    public let maneuver: LandmarkManeuver
    /// Destination cross-street
    public let targetStreet: String?
    /// Salient visual landmark anchor name
    public let landmarkName: String?
    /// Flag indicating this is an intermediate confirmation reminder on a long straight segment
    public let isIntermediateReminder: Bool
    /// Remaining distance in meters
    public let distanceMeters: UInt32
    /// Compact badge label text for the 15% peek banner (e.g. "3 blocks", "At light", "Turn here")
    public let promptBadgeText: String?
    /// SF Symbol icon name
    public let iconName: String
    
    public init(
        id: UUID = UUID(),
        primaryHeadline: String,
        secondaryContext: String,
        decisionZone: GuidanceDecisionZone,
        blockCount: Int? = nil,
        intersectionControl: IntersectionControl = .standardCorner,
        maneuver: LandmarkManeuver,
        targetStreet: String? = nil,
        landmarkName: String? = nil,
        isIntermediateReminder: Bool = false,
        distanceMeters: UInt32,
        promptBadgeText: String? = nil,
        iconName: String? = nil
    ) {
        self.id = id
        self.primaryHeadline = primaryHeadline
        self.secondaryContext = secondaryContext
        self.decisionZone = decisionZone
        self.blockCount = blockCount
        self.intersectionControl = intersectionControl
        self.maneuver = maneuver
        self.targetStreet = targetStreet
        self.landmarkName = landmarkName
        self.isIntermediateReminder = isIntermediateReminder
        self.distanceMeters = distanceMeters
        self.promptBadgeText = promptBadgeText
        self.iconName = iconName ?? maneuver.systemIcon
    }
}

// MARK: - Natural Guidance Synthesis Engine

/// Synthesis engine generating human-centered route reminders, block counts, and traffic signal framing (Wave N-D.6.1).
/// Adheres strictly to Google Maps Natural Guidance patterns and Research Document 14 §2.
public final class NaturalWalkingGuidanceEngine: @unchecked Sendable {
    public static let shared = NaturalWalkingGuidanceEngine()
    
    // Spatial block thresholds (in meters)
    public static let standardStreetBlockMeters: Double = 80.0    // ~260 ft (North-South in Manhattan)
    public static let standardAvenueBlockMeters: Double = 240.0   // ~780 ft (East-West in Manhattan)
    
    // Google Maps decision zone thresholds (in meters)
    public static let foresightThresholdMeters: Double = 120.0    // > 120m -> Foresight
    public static let approachThresholdMeters: Double = 30.0      // 30m - 120m -> Approach
    public static let imminentThresholdMeters: Double = 30.0      // <= 30m -> Imminent
    public static let advanceThresholdMeters: Double = 10.0       // <= 10m -> Step completed
    public static let hysteresisBufferMeters: Double = 8.0        // Anti-flap buffer
    
    private init() {}
    
    // MARK: - City Block Computation
    
    /// Computes intuitive city block count. Suppresses block counts in irregular, non-grid environments.
    public func computeBlockCount(
        distanceMeters: Double,
        isAvenueCorridor: Bool = false,
        isGridTopology: Bool = true
    ) -> Int? {
        guard isGridTopology, distanceMeters >= 40.0 else { return nil }
        let blockLength = isAvenueCorridor ? Self.standardAvenueBlockMeters : Self.standardStreetBlockMeters
        let count = max(1, Int(round(distanceMeters / blockLength)))
        return count
    }
    
    // MARK: - Decision Zone Resolution
    
    /// Resolves the current decision zone with optional hysteresis against a prior zone.
    public func resolveDecisionZone(
        distanceMeters: Double,
        previousZone: GuidanceDecisionZone? = nil
    ) -> GuidanceDecisionZone {
        guard let prev = previousZone else {
            if distanceMeters > Self.foresightThresholdMeters {
                return .foresight
            } else if distanceMeters > Self.imminentThresholdMeters {
                return .approach
            } else {
                return .imminent
            }
        }
        
        switch prev {
        case .foresight:
            // Downward transition to approach at <= 120m
            if distanceMeters <= Self.foresightThresholdMeters {
                return distanceMeters <= Self.imminentThresholdMeters ? .imminent : .approach
            }
            return .foresight
            
        case .approach:
            // Upward transition back to foresight requires 120m + 8m = 128m
            if distanceMeters > (Self.foresightThresholdMeters + Self.hysteresisBufferMeters) {
                return .foresight
            }
            // Downward transition to imminent at <= 30m
            if distanceMeters <= Self.imminentThresholdMeters {
                return .imminent
            }
            return .approach
            
        case .imminent:
            // Upward transition back to approach requires 30m + 8m = 38m
            if distanceMeters > (Self.imminentThresholdMeters + Self.hysteresisBufferMeters) {
                return distanceMeters > (Self.foresightThresholdMeters + Self.hysteresisBufferMeters) ? .foresight : .approach
            }
            return .imminent
        }
    }
    
    // MARK: - Primary Dynamic Cue Synthesis
    
    /// Synthesizes a natural guidance cue dynamically adapted across the Foresight, Approach, and Imminent zones.
    public func synthesizeDynamicCue(
        anchor: LandmarkWalkingAnchor,
        distanceMeters: Double,
        hasTrafficSignal: Bool = false,
        isGridTopology: Bool = true,
        isAvenueCorridor: Bool = false,
        previousZone: GuidanceDecisionZone? = nil,
        exitCode: String? = nil
    ) -> NaturalGuidanceCue {
        let zone = resolveDecisionZone(distanceMeters: distanceMeters, previousZone: previousZone)
        let blockCount = computeBlockCount(
            distanceMeters: distanceMeters,
            isAvenueCorridor: isAvenueCorridor,
            isGridTopology: isGridTopology
        )
        
        let control: IntersectionControl = hasTrafficSignal ? .trafficSignal : .standardCorner
        let targetStreet = anchor.streetName
        let landmark = anchor.landmarkName
        
        // Check for Subterranean Egress Handshake (Exit 4B etc.)
        if let exit = exitCode, anchor.maneuver == .depart {
            return synthesizeEgressHandshakeCue(
                exitCode: exit,
                distanceMeters: UInt32(distanceMeters),
                targetStreet: targetStreet,
                landmark: landmark
            )
        }
        
        // Maneuver Verb Text (e.g. "turn left", "bear right", "walk straight")
        let verb = maneuverVerb(anchor.maneuver)
        
        switch zone {
        case .foresight:
            let headline: String
            let badgeText: String?
            
            if let blocks = blockCount {
                headline = blocks == 1 ? "In 1 block, \(verb)" : "In \(blocks) blocks, \(verb)"
                badgeText = blocks == 1 ? "1 block" : "\(blocks) blocks"
            } else {
                headline = "Ahead, \(verb)"
                badgeText = nil
            }
            
            let secondary: String
            if let street = targetStreet, !street.isEmpty {
                if !landmark.isEmpty && landmark != street {
                    secondary = "at \(landmark) onto \(street)"
                } else {
                    secondary = "onto \(street)"
                }
            } else if !landmark.isEmpty {
                secondary = "past \(landmark)"
            } else {
                secondary = "toward destination"
            }
            
            return NaturalGuidanceCue(
                primaryHeadline: headline,
                secondaryContext: secondary,
                decisionZone: .foresight,
                blockCount: blockCount,
                intersectionControl: control,
                maneuver: anchor.maneuver,
                targetStreet: targetStreet,
                landmarkName: landmark,
                isIntermediateReminder: false,
                distanceMeters: UInt32(distanceMeters),
                promptBadgeText: badgeText,
                iconName: anchor.maneuver.systemIcon
            )
            
        case .approach:
            let headline: String
            let badgeText: String?
            
            if hasTrafficSignal {
                headline = "At the next light, \(verb)"
                badgeText = "At light"
            } else if let blocks = blockCount, blocks == 1 {
                headline = "In 1 block, \(verb)"
                badgeText = "1 block"
            } else {
                headline = "At the next corner, \(verb)"
                badgeText = "Next corner"
            }
            
            var secondaryParts: [String] = []
            if let street = targetStreet, !street.isEmpty {
                secondaryParts.append("onto \(street)")
            }
            if !landmark.isEmpty && landmark != targetStreet {
                secondaryParts.append("past \(landmark)")
            }
            let secondary = secondaryParts.isEmpty ? "follow street" : secondaryParts.joined(separator: " • ")
            
            return NaturalGuidanceCue(
                primaryHeadline: headline,
                secondaryContext: secondary,
                decisionZone: .approach,
                blockCount: blockCount,
                intersectionControl: control,
                maneuver: anchor.maneuver,
                targetStreet: targetStreet,
                landmarkName: landmark,
                isIntermediateReminder: false,
                distanceMeters: UInt32(distanceMeters),
                promptBadgeText: badgeText,
                iconName: hasTrafficSignal ? "light.beacon.max.fill" : anchor.maneuver.systemIcon
            )
            
        case .imminent:
            let capVerb = sentenceCapitalized(verb)
            let headline: String
            if hasTrafficSignal {
                headline = "\(capVerb) at the light"
            } else {
                headline = "\(capVerb) here"
            }
            
            let secondary: String
            if let street = targetStreet, !street.isEmpty {
                secondary = "onto \(street)"
            } else if !landmark.isEmpty {
                secondary = "after \(landmark)"
            } else {
                secondary = "now"
            }
            
            return NaturalGuidanceCue(
                primaryHeadline: headline,
                secondaryContext: secondary,
                decisionZone: .imminent,
                blockCount: blockCount,
                intersectionControl: control,
                maneuver: anchor.maneuver,
                targetStreet: targetStreet,
                landmarkName: landmark,
                isIntermediateReminder: false,
                distanceMeters: UInt32(distanceMeters),
                promptBadgeText: "Turn here",
                iconName: anchor.maneuver.systemIcon
            )
        }
    }
    
    // MARK: - Intermediate Straight-Walk Confirmation Reminders
    
    /// Synthesizes a calming confirmation reminder for long straightaways (>= 250m / >= 3 blocks).
    public func synthesizeStraightReassurance(
        distanceRemainingMeters: Double,
        totalSegmentMeters: Double,
        prominentLandmark: String? = nil,
        isGridTopology: Bool = true
    ) -> NaturalGuidanceCue? {
        guard totalSegmentMeters >= 250.0, distanceRemainingMeters >= Self.foresightThresholdMeters else {
            return nil
        }
        
        let blocks = computeBlockCount(distanceMeters: distanceRemainingMeters, isGridTopology: isGridTopology)
        let headline: String
        let badgeText: String?
        
        if let b = blocks {
            headline = b == 1 ? "Continue straight for 1 block" : "Continue straight for \(b) blocks"
            badgeText = b == 1 ? "1 block" : "\(b) blocks"
        } else {
            headline = "Continue straight along path"
            badgeText = "Straight"
        }
        
        let secondary: String
        if let lm = prominentLandmark, !lm.isEmpty {
            secondary = "past \(lm)"
        } else {
            secondary = "stay on route"
        }
        
        return NaturalGuidanceCue(
            primaryHeadline: headline,
            secondaryContext: secondary,
            decisionZone: .foresight,
            blockCount: blocks,
            intersectionControl: .standardCorner,
            maneuver: .straightPast,
            targetStreet: nil,
            landmarkName: prominentLandmark,
            isIntermediateReminder: true,
            distanceMeters: UInt32(distanceRemainingMeters),
            promptBadgeText: badgeText,
            iconName: "arrow.up"
        )
    }
    
    // MARK: - Subterranean Egress Handshake
    
    private func synthesizeEgressHandshakeCue(
        exitCode: String,
        distanceMeters: UInt32,
        targetStreet: String?,
        landmark: String?
    ) -> NaturalGuidanceCue {
        let headline = "Exit to \(targetStreet ?? landmark ?? "street level")"
        let secondary = "Walk to sidewalk • \(exitCode)"
        
        return NaturalGuidanceCue(
            primaryHeadline: headline,
            secondaryContext: secondary,
            decisionZone: .imminent,
            blockCount: nil,
            intersectionControl: .standardCorner,
            maneuver: .depart,
            targetStreet: targetStreet,
            landmarkName: landmark,
            isIntermediateReminder: false,
            distanceMeters: distanceMeters,
            promptBadgeText: "Exit",
            iconName: "figure.walk"
        )
    }
    
    // MARK: - Helper Formatting
    
    private func maneuverVerb(_ maneuver: LandmarkManeuver) -> String {
        switch maneuver {
        case .turnLeft: return "turn left"
        case .turnRight: return "turn right"
        case .slightLeft: return "bear left"
        case .slightRight: return "bear right"
        case .straightPast: return "walk straight"
        case .depart: return "start walking"
        case .arrive: return "arrive at destination"
        }
    }
    
    private func sentenceCapitalized(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.uppercased() + text.dropFirst()
    }
}
