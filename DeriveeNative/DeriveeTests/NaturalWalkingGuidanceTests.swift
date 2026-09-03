import XCTest
import CoreLocation
@testable import Derivee

final class NaturalWalkingGuidanceTests: XCTestCase {
    
    // MARK: - 1. City Block Computation Tests
    
    func testCityBlockComputationDualMode() {
        let engine = NaturalWalkingGuidanceEngine.shared
        
        // Regular Manhattan street blocks (~80m)
        XCTAssertEqual(engine.computeBlockCount(distanceMeters: 45.0, isGridTopology: true), 1)
        XCTAssertEqual(engine.computeBlockCount(distanceMeters: 80.0, isGridTopology: true), 1)
        XCTAssertEqual(engine.computeBlockCount(distanceMeters: 160.0, isGridTopology: true), 2)
        XCTAssertEqual(engine.computeBlockCount(distanceMeters: 240.0, isGridTopology: true), 3)
        XCTAssertEqual(engine.computeBlockCount(distanceMeters: 400.0, isGridTopology: true), 5)
        
        // Manhattan Avenue blocks (~240m)
        XCTAssertEqual(engine.computeBlockCount(distanceMeters: 240.0, isAvenueCorridor: true, isGridTopology: true), 1)
        XCTAssertEqual(engine.computeBlockCount(distanceMeters: 480.0, isAvenueCorridor: true, isGridTopology: true), 2)
        XCTAssertEqual(engine.computeBlockCount(distanceMeters: 720.0, isAvenueCorridor: true, isGridTopology: true), 3)
        
        // Irregular non-grid topology (Downtown Boston / park greenways)
        XCTAssertNil(
            engine.computeBlockCount(distanceMeters: 300.0, isGridTopology: false),
            "Non-grid topography must suppress block counts"
        )
        
        // Very short distance (< 40m) suppresses block counts
        XCTAssertNil(engine.computeBlockCount(distanceMeters: 25.0, isGridTopology: true))
    }
    
    // MARK: - 2. Decision Zone Resolution & Anti-Flap Hysteresis
    
    func testDecisionZoneThresholdsAndHysteresis() {
        let engine = NaturalWalkingGuidanceEngine.shared
        
        // Initial state resolution (no prior zone)
        XCTAssertEqual(engine.resolveDecisionZone(distanceMeters: 200.0), .foresight)
        XCTAssertEqual(engine.resolveDecisionZone(distanceMeters: 80.0), .approach)
        XCTAssertEqual(engine.resolveDecisionZone(distanceMeters: 20.0), .imminent)
        
        // Hysteresis latch from Approach -> Foresight (threshold: 120m + 8m = 128m)
        XCTAssertEqual(
            engine.resolveDecisionZone(distanceMeters: 125.0, previousZone: .approach),
            .approach,
            "125m must remain in Approach zone due to 8m hysteresis buffer"
        )
        XCTAssertEqual(
            engine.resolveDecisionZone(distanceMeters: 129.0, previousZone: .approach),
            .foresight,
            "129m (> 128m) must flip back to Foresight zone"
        )
        
        // Hysteresis latch from Imminent -> Approach (threshold: 30m + 8m = 38m)
        XCTAssertEqual(
            engine.resolveDecisionZone(distanceMeters: 35.0, previousZone: .imminent),
            .imminent,
            "35m must remain in Imminent zone due to 8m hysteresis buffer"
        )
        XCTAssertEqual(
            engine.resolveDecisionZone(distanceMeters: 40.0, previousZone: .imminent),
            .approach,
            "40m (> 38m) must flip back to Approach zone"
        )
    }
    
    // MARK: - 3. Headline Conciseness & Glanceability Invariant
    
    func testHeadlineCognitiveTieringGlanceability() {
        let engine = NaturalWalkingGuidanceEngine.shared
        let anchor = LandmarkWalkingAnchor(
            prompt: "Turn left at the Starbucks on 42nd St",
            landmarkName: "Starbucks",
            maneuver: .turnLeft,
            streetName: "5th Ave"
        )
        
        let distances = [350.0, 100.0, 20.0]
        for dist in distances {
            let cue = engine.synthesizeDynamicCue(
                anchor: anchor,
                distanceMeters: dist,
                hasTrafficSignal: true,
                isGridTopology: true
            )
            
            XCTAssertLessThanOrEqual(
                cue.primaryHeadline.count,
                28,
                "Headline '\(cue.primaryHeadline)' must be <= 28 characters for glanceability"
            )
            XCTAssertFalse(cue.secondaryContext.isEmpty, "Contextual subtitle must be present")
        }
    }
    
    // MARK: - 4. Traffic Signal vs. Corner Framing
    
    func testTrafficSignalVsCornerFraming() {
        let engine = NaturalWalkingGuidanceEngine.shared
        let anchor = LandmarkWalkingAnchor(
            prompt: "Turn left onto 5th Ave",
            landmarkName: "Starbucks",
            maneuver: .turnLeft,
            streetName: "5th Ave"
        )
        
        // 1. With verified traffic light
        let signalApproach = engine.synthesizeDynamicCue(
            anchor: anchor,
            distanceMeters: 80.0,
            hasTrafficSignal: true,
            isGridTopology: true
        )
        XCTAssertEqual(signalApproach.primaryHeadline, "At the next light, turn left")
        XCTAssertEqual(signalApproach.promptBadgeText, "At light")
        XCTAssertEqual(signalApproach.iconName, "light.beacon.max.fill")
        XCTAssertTrue(signalApproach.secondaryContext.contains("5th Ave"))
        
        let signalImminent = engine.synthesizeDynamicCue(
            anchor: anchor,
            distanceMeters: 20.0,
            hasTrafficSignal: true,
            isGridTopology: true
        )
        XCTAssertEqual(signalImminent.primaryHeadline, "Turn left at the light")
        XCTAssertEqual(signalImminent.promptBadgeText, "Turn here")
        
        // 2. Unsignaled corner
        let cornerApproach = engine.synthesizeDynamicCue(
            anchor: anchor,
            distanceMeters: 80.0,
            hasTrafficSignal: false,
            isGridTopology: true
        )
        XCTAssertEqual(cornerApproach.primaryHeadline, "In 1 block, turn left")
        XCTAssertEqual(cornerApproach.promptBadgeText, "1 block")
        
        let cornerImminent = engine.synthesizeDynamicCue(
            anchor: anchor,
            distanceMeters: 20.0,
            hasTrafficSignal: false,
            isGridTopology: true
        )
        XCTAssertEqual(cornerImminent.primaryHeadline, "Turn left here")
        XCTAssertEqual(cornerImminent.promptBadgeText, "Turn here")
    }
    
    // MARK: - 5. Singular vs. Plural Grammar Invariants
    
    func testSingularVsPluralGrammar() {
        let engine = NaturalWalkingGuidanceEngine.shared
        let anchor = LandmarkWalkingAnchor(
            prompt: "Turn right onto Broadway",
            landmarkName: "Duane Reade",
            maneuver: .turnRight,
            streetName: "Broadway"
        )
        
        // Exactly 1 block out (80m)
        let oneBlock = engine.synthesizeDynamicCue(
            anchor: anchor,
            distanceMeters: 80.0,
            hasTrafficSignal: false,
            isGridTopology: true
        )
        XCTAssertEqual(oneBlock.primaryHeadline, "In 1 block, turn right")
        XCTAssertEqual(oneBlock.promptBadgeText, "1 block")
        
        // 3 blocks out (240m)
        let threeBlocks = engine.synthesizeDynamicCue(
            anchor: anchor,
            distanceMeters: 240.0,
            hasTrafficSignal: false,
            isGridTopology: true
        )
        XCTAssertEqual(threeBlocks.primaryHeadline, "In 3 blocks, turn right")
        XCTAssertEqual(threeBlocks.promptBadgeText, "3 blocks")
    }
    
    // MARK: - 6. Intermediate Straight-Walk Confirmation Reminders
    
    func testIntermediateStraightReassurance() {
        let engine = NaturalWalkingGuidanceEngine.shared
        
        // Long segment (500m total, 300m remaining)
        let reassurance = engine.synthesizeStraightReassurance(
            distanceRemainingMeters: 300.0,
            totalSegmentMeters: 500.0,
            prominentLandmark: "Bryant Park",
            isGridTopology: true
        )
        XCTAssertNotNil(reassurance)
        XCTAssertEqual(reassurance?.primaryHeadline, "Continue straight for 4 blocks")
        XCTAssertEqual(reassurance?.secondaryContext, "past Bryant Park")
        XCTAssertTrue(reassurance?.isIntermediateReminder == true)
        XCTAssertEqual(reassurance?.iconName, "arrow.up")
        
        // Short segment (< 250m) should not generate intermediate reassurance
        let shortReassurance = engine.synthesizeStraightReassurance(
            distanceRemainingMeters: 140.0,
            totalSegmentMeters: 200.0,
            prominentLandmark: "Park",
            isGridTopology: true
        )
        XCTAssertNil(shortReassurance, "Segments < 250m must not produce intermediate reassurance cues")
    }
    
    // MARK: - 7. Subterranean Egress Handshake
    
    func testSubterraneanEgressHandshake() {
        let engine = NaturalWalkingGuidanceEngine.shared
        let departAnchor = LandmarkWalkingAnchor(
            prompt: "Start walking from Grand Central",
            landmarkName: "Grand Central Terminal",
            maneuver: .depart,
            streetName: "42nd St"
        )
        
        let egressCue = engine.synthesizeDynamicCue(
            anchor: departAnchor,
            distanceMeters: 15.0,
            hasTrafficSignal: true,
            isGridTopology: true,
            exitCode: "Exit 4B"
        )
        
        XCTAssertEqual(egressCue.primaryHeadline, "Exit to 42nd St")
        XCTAssertEqual(egressCue.secondaryContext, "Walk to sidewalk • Exit 4B")
        XCTAssertEqual(egressCue.promptBadgeText, "Exit")
        XCTAssertEqual(egressCue.iconName, "figure.walk")
    }
    
    // MARK: - 8. Simulated Traversal along Manhattan 42nd St Corridor
    
    func testSimulatedWalkingTraversalProgression() {
        let engine = NaturalWalkingGuidanceEngine.shared
        let turnAnchor = LandmarkWalkingAnchor(
            prompt: "Turn left at the Starbucks on 42nd St",
            landmarkName: "Starbucks",
            maneuver: .turnLeft,
            streetName: "5th Ave"
        )
        
        var currentZone: GuidanceDecisionZone? = nil
        
        // Walk simulation: from 400m down to 5m
        let trajectoryDistances = [400.0, 320.0, 240.0, 160.0, 120.0, 80.0, 40.0, 25.0, 15.0, 5.0]
        var recordedHeadlines: [String] = []
        var recordedZones: [GuidanceDecisionZone] = []
        
        for dist in trajectoryDistances {
            let cue = engine.synthesizeDynamicCue(
                anchor: turnAnchor,
                distanceMeters: dist,
                hasTrafficSignal: true,
                isGridTopology: true,
                previousZone: currentZone
            )
            currentZone = cue.decisionZone
            recordedHeadlines.append(cue.primaryHeadline)
            recordedZones.append(cue.decisionZone)
        }
        
        // Verify zone progression
        XCTAssertEqual(recordedZones[0], .foresight) // 400m
        XCTAssertEqual(recordedZones[4], .approach)  // 120m
        XCTAssertEqual(recordedZones[5], .approach)  // 80m
        XCTAssertEqual(recordedZones[7], .imminent)  // 25m
        
        // Verify headline progression
        XCTAssertTrue(recordedHeadlines[0].contains("blocks"))
        XCTAssertEqual(recordedHeadlines[5], "At the next light, turn left")
        XCTAssertEqual(recordedHeadlines[7], "Turn left at the light")
    }
}
