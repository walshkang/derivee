import XCTest
import SwiftUI
import SnapshotTesting
@testable import Derivee

@MainActor
final class NavigationDetentTests: XCTestCase {

    // MARK: - 1. Unit Tests: NavigationSheetDetent & Conversions

    func testNavigationSheetDetentFractionsAndConversions() {
        XCTAssertEqual(NavigationSheetDetent.peek.fraction, 0.15)
        XCTAssertEqual(NavigationSheetDetent.half.fraction, 0.50)
        XCTAssertEqual(NavigationSheetDetent.expanded.fraction, 0.90)
        
        let detents = NavigationSheetDetent.standardSet
        XCTAssertEqual(detents.count, 3)
        XCTAssertTrue(detents.contains(PresentationDetent.fraction(0.15)))
        XCTAssertTrue(detents.contains(PresentationDetent.fraction(0.50)))
        XCTAssertTrue(detents.contains(PresentationDetent.fraction(0.90)))
        
        XCTAssertEqual(NavigationSheetDetent.from(detent: .fraction(0.15)), .peek)
        XCTAssertEqual(NavigationSheetDetent.from(detent: .fraction(0.50)), .half)
        XCTAssertEqual(NavigationSheetDetent.from(detent: .fraction(0.90)), .expanded)
        XCTAssertNil(NavigationSheetDetent.from(detent: .medium))
        XCTAssertNil(NavigationSheetDetent.from(detent: .large))
    }

    // MARK: - 2. Unit Tests: ThumbZoneActionBar Archetypes & Execution

    func testThumbZoneActionBarActions() {
        var startExecuted = false
        let startAction = ThumbZonePrimaryAction.startJourney {
            startExecuted = true
        }
        XCTAssertEqual(startAction.title, "Start Journey")
        XCTAssertEqual(startAction.iconSystemName, "location.fill")
        XCTAssertEqual(startAction.height, 52)
        startAction.execute()
        XCTAssertTrue(startExecuted)
        
        var rerouteExecuted = false
        let rerouteAction = ThumbZonePrimaryAction.reroute {
            rerouteExecuted = true
        }
        XCTAssertEqual(rerouteAction.title, "Reroute")
        XCTAssertEqual(rerouteAction.iconSystemName, "arrow.triangle.2.circlepath")
        XCTAssertEqual(rerouteAction.height, 52)
        rerouteAction.execute()
        XCTAssertTrue(rerouteExecuted)
        
        var unlockExecuted = false
        let unlockAction = ThumbZonePrimaryAction.unlockBike(
            title: "Unlock Citi Bike",
            batterySoc: 88,
            dockInfo: "14 bikes",
            action: { unlockExecuted = true }
        )
        XCTAssertEqual(unlockAction.title, "Unlock Citi Bike")
        XCTAssertEqual(unlockAction.iconSystemName, "bicycle.circle.fill")
        XCTAssertEqual(unlockAction.height, 56) // 56pt touch target for cycling ergonomics (Doc 14)
        unlockAction.execute()
        XCTAssertTrue(unlockExecuted)
        
        var secondaryExecuted = false
        let secAction = ThumbZoneSecondaryAction.steps {
            secondaryExecuted = true
        }
        XCTAssertEqual(secAction.title, "Steps")
        XCTAssertEqual(secAction.iconSystemName, "list.bullet")
        secAction.execute()
        XCTAssertTrue(secondaryExecuted)
    }

    // MARK: - 3. Unit Tests: Multimodal Leg Progression

    func testMultimodalLegProgression() {
        let itinerary = makeMultimodalItineraryFixture()
        XCTAssertEqual(itinerary.legs.count, 3)
        
        // Leg 0: Walking
        XCTAssertEqual(itinerary.legs[0].mode, .walk)
        XCTAssertEqual(itinerary.legs[0].originName, "Astor Place")
        
        // Leg 1: Subway
        XCTAssertEqual(itinerary.legs[1].mode, .subway)
        XCTAssertEqual(itinerary.legs[1].routeId, "6")
        XCTAssertEqual(itinerary.legs[1].recommendedCarPosition, "Board near front car")
        XCTAssertEqual(itinerary.legs[1].exitCode, "Exit 4B - NW Corner 42nd & Lexington")
        
        // Leg 2: Bike Share with battery SOC
        XCTAssertEqual(itinerary.legs[2].mode, .bikeShare)
        XCTAssertNotNil(itinerary.legs[2].bikeMetadata)
        XCTAssertEqual(itinerary.legs[2].bikeMetadata?.batterySocPercent, 84)
        XCTAssertEqual(itinerary.legs[2].bikeMetadata?.dockGatingRisk, .low)
    }

    // MARK: - 4. Snapshot Tests: ThumbZoneActionBar Archetypes

    func testThumbZoneActionBarStartJourneySnapshot() {
        let view = ThumbZoneActionBar(
            primary: .startJourney(action: {}),
            secondary: .steps(action: {})
        )
        .frame(width: 375)
        .background(Color(hex: "#F9F9F6"))
        
        let vc = UIHostingController(rootView: view)
        assertSnapshot(of: vc, as: .image(on: ViewImageConfig(size: CGSize(width: 375, height: 90)), precision: 0.98))
    }

    func testThumbZoneActionBarRerouteSnapshot() {
        let view = ThumbZoneActionBar(
            primary: .reroute(action: {}),
            secondary: .alternatives(action: {})
        )
        .frame(width: 375)
        .background(Color(hex: "#F9F9F6"))
        
        let vc = UIHostingController(rootView: view)
        assertSnapshot(of: vc, as: .image(on: ViewImageConfig(size: CGSize(width: 375, height: 90)), precision: 0.98))
    }

    func testThumbZoneActionBarUnlockBikeSnapshot() {
        let view = ThumbZoneActionBar(
            primary: .unlockBike(
                batterySoc: 84,
                dockInfo: "14 bikes available",
                action: {}
            ),
            secondary: .endJourney(action: {})
        )
        .frame(width: 375)
        .background(Color(hex: "#F9F9F6"))
        
        let vc = UIHostingController(rootView: view)
        assertSnapshot(of: vc, as: .image(on: ViewImageConfig(size: CGSize(width: 375, height: 96)), precision: 0.98))
    }

    // MARK: - 5. Snapshot Tests: NavigationCollapsedPeekView

    func testNavigationCollapsedPeekViewSubwaySnapshot() {
        let itinerary = makeMultimodalItineraryFixture()
        let subwayLeg = itinerary.legs[1]
        
        let view = NavigationCollapsedPeekView(
            leg: subwayLeg,
            totalDurationFormatted: itinerary.formattedDuration,
            arrivalTimeFormatted: itinerary.formattedArrivalTime
        )
        .frame(width: 375)
        .background(Color.white)
        
        let vc = UIHostingController(rootView: view)
        assertSnapshot(of: vc, as: .image(on: ViewImageConfig(size: CGSize(width: 375, height: 85)), precision: 0.98))
    }

    func testNavigationCollapsedPeekViewBikeSnapshot() {
        let itinerary = makeMultimodalItineraryFixture()
        let bikeLeg = itinerary.legs[2]
        
        let view = NavigationCollapsedPeekView(
            leg: bikeLeg,
            totalDurationFormatted: itinerary.formattedDuration,
            arrivalTimeFormatted: itinerary.formattedArrivalTime
        )
        .frame(width: 375)
        .background(Color.white)
        
        let vc = UIHostingController(rootView: view)
        assertSnapshot(of: vc, as: .image(on: ViewImageConfig(size: CGSize(width: 375, height: 85)), precision: 0.98))
    }

    func testNavigationCollapsedPeekViewNaturalWalkingForesightSnapshot() {
        let itinerary = makeMultimodalItineraryFixture()
        let walkLeg = itinerary.legs[0]
        
        let cue = NaturalGuidanceCue(
            primaryHeadline: "In 3 blocks, turn left",
            secondaryContext: "onto 5th Ave • past Starbucks",
            decisionZone: .foresight,
            blockCount: 3,
            intersectionControl: .trafficSignal,
            maneuver: .turnLeft,
            targetStreet: "5th Ave",
            landmarkName: "Starbucks",
            isIntermediateReminder: false,
            distanceMeters: 240,
            promptBadgeText: "3 blocks",
            iconName: "arrow.turn.up.left"
        )
        
        let view = NavigationCollapsedPeekView(
            leg: walkLeg,
            totalDurationFormatted: itinerary.formattedDuration,
            arrivalTimeFormatted: itinerary.formattedArrivalTime,
            naturalCue: cue
        )
        .frame(width: 375)
        .background(Color.white)
        
        let vc = UIHostingController(rootView: view)
        assertSnapshot(of: vc, as: .image(on: ViewImageConfig(size: CGSize(width: 375, height: 85)), precision: 0.98))
    }

    func testNavigationCollapsedPeekViewNaturalWalkingApproachSignalSnapshot() {
        let itinerary = makeMultimodalItineraryFixture()
        let walkLeg = itinerary.legs[0]
        
        let cue = NaturalGuidanceCue(
            primaryHeadline: "At the next light, turn left",
            secondaryContext: "onto Broadway • past CVS",
            decisionZone: .approach,
            blockCount: 1,
            intersectionControl: .trafficSignal,
            maneuver: .turnLeft,
            targetStreet: "Broadway",
            landmarkName: "CVS",
            isIntermediateReminder: false,
            distanceMeters: 80,
            promptBadgeText: "At light",
            iconName: "light.beacon.max.fill"
        )
        
        let view = NavigationCollapsedPeekView(
            leg: walkLeg,
            totalDurationFormatted: itinerary.formattedDuration,
            arrivalTimeFormatted: itinerary.formattedArrivalTime,
            naturalCue: cue
        )
        .frame(width: 375)
        .background(Color.white)
        
        let vc = UIHostingController(rootView: view)
        assertSnapshot(of: vc, as: .image(on: ViewImageConfig(size: CGSize(width: 375, height: 85)), precision: 0.98))
    }

    func testNavigationCollapsedPeekViewNaturalWalkingImminentSnapshot() {
        let itinerary = makeMultimodalItineraryFixture()
        let walkLeg = itinerary.legs[0]
        
        let cue = NaturalGuidanceCue(
            primaryHeadline: "Turn left at the light",
            secondaryContext: "onto Broadway",
            decisionZone: .imminent,
            blockCount: nil,
            intersectionControl: .trafficSignal,
            maneuver: .turnLeft,
            targetStreet: "Broadway",
            landmarkName: "CVS",
            isIntermediateReminder: false,
            distanceMeters: 18,
            promptBadgeText: "Turn here",
            iconName: "arrow.turn.up.left"
        )
        
        let view = NavigationCollapsedPeekView(
            leg: walkLeg,
            totalDurationFormatted: itinerary.formattedDuration,
            arrivalTimeFormatted: itinerary.formattedArrivalTime,
            naturalCue: cue
        )
        .frame(width: 375)
        .background(Color.white)
        
        let vc = UIHostingController(rootView: view)
        assertSnapshot(of: vc, as: .image(on: ViewImageConfig(size: CGSize(width: 375, height: 85)), precision: 0.98))
    }

    // MARK: - 6. Snapshot Tests: NavigationGuidanceSheet Half & Peek Detents

    func testNavigationGuidanceSheetHalfDetentSnapshot() {
        let itinerary = makeMultimodalItineraryFixture()
        
        let view = NavigationGuidanceSheet(
            itinerary: itinerary,
            selectedDetent: .constant(NavigationSheetDetent.half.presentationDetent),
            initialLegIndex: 1
        )
        .frame(width: 375, height: 440)
        
        let vc = UIHostingController(rootView: view)
        assertSnapshot(of: vc, as: .image(on: ViewImageConfig(size: CGSize(width: 375, height: 440)), precision: 0.98))
    }

    // MARK: - Test Fixture Helper

    private func makeMultimodalItineraryFixture() -> JourneyItinerary {
        let legs = [
            JourneyLeg(
                mode: .walk,
                originName: "Astor Place",
                destinationName: "Astor Pl Station",
                departureTimeSec: 31320,
                arrivalTimeSec: 31440,
                distanceMeters: 140,
                landmarkCue: "Turn left after red brick pharmacy"
            ),
            JourneyLeg(
                mode: .subway,
                originName: "Astor Pl",
                destinationName: "Grand Central - 42 St",
                departureTimeSec: 31500,
                arrivalTimeSec: 32100,
                routeId: "6",
                headsign: "Uptown & The Bronx",
                stopCount: 5,
                confidenceTier: .verified,
                exitCode: "Exit 4B - NW Corner 42nd & Lexington",
                recommendedCarPosition: "Board near front car"
            ),
            JourneyLeg(
                mode: .bikeShare,
                originName: "E 42 St & Park Ave",
                destinationName: "3rd Ave & E 44 St",
                departureTimeSec: 32160,
                arrivalTimeSec: 32460,
                distanceMeters: 450,
                bikeMetadata: BikeLegMetadata(
                    originStationName: "E 42 St & Park Ave",
                    destinationStationName: "3rd Ave & E 44 St",
                    isEBike: true,
                    batterySocPercent: 84,
                    estimatedRangeMiles: 18.5,
                    dockGatingRisk: .low
                )
            )
        ]
        
        return JourneyItinerary(
            profile: .mostReliable,
            departureTimeSec: 31320,
            arrivalTimeSec: 32460,
            p10ArrivalSec: 32400,
            p90ArrivalSec: 32580,
            legs: legs,
            confidenceTier: .verified
        )
    }
}
