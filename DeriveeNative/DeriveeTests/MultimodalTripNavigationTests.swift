import XCTest
import CoreLocation
@testable import Derivee

@MainActor
final class MultimodalTripNavigationTests: XCTestCase {
    
    private func makeMultimodalFixture() -> JourneyItinerary {
        let walkLeg = JourneyLeg(
            id: UUID(),
            mode: .walk,
            originName: "Astor Place",
            destinationName: "Astor Place Subway",
            departureTimeSec: 28800,
            arrivalTimeSec: 29000,
            durationSec: 200,
            distanceMeters: 150,
            confidenceTier: .verified
        )
        
        let subwayLeg = JourneyLeg(
            id: UUID(),
            mode: .subway,
            originName: "Astor Place",
            destinationName: "Grand Central - 42nd St",
            departureTimeSec: 29100,
            arrivalTimeSec: 29700,
            durationSec: 600,
            distanceMeters: 3000,
            routeId: "6",
            confidenceTier: .verified,
            exitCode: "Exit 4B - NW Corner 42nd & Lexington",
            recommendedCarPosition: "Board near front car"
        )
        
        let bikeMeta = BikeLegMetadata(
            originStationName: "E 42nd St & Lexington Ave",
            destinationStationName: "5th Ave & E 46th St",
            availableBikesAtOrigin: 10,
            availableDocksAtDest: 14,
            isEBike: true,
            batterySocPercent: 88,
            estimatedRangeMiles: 17.5,
            dockGatingRisk: .low,
            cyclingInfrastructureType: .protectedBikeTrack,
            nextManeuver: .turnLeft,
            nextManeuverDistanceMeters: 180
        )
        
        let bikeLeg = JourneyLeg(
            id: UUID(),
            mode: .bikeShare,
            originName: "E 42nd St & Lexington Ave",
            destinationName: "5th Ave & E 46th St",
            departureTimeSec: 29800,
            arrivalTimeSec: 30300,
            durationSec: 500,
            distanceMeters: 1200,
            confidenceTier: .verified,
            bikeMetadata: bikeMeta
        )
        
        return JourneyItinerary(
            id: UUID(),
            profile: .multiModalBikeRail,
            departureTimeSec: 28800,
            arrivalTimeSec: 30300,
            p10ArrivalSec: 30200,
            p50ArrivalSec: 30300,
            p90ArrivalSec: 30450,
            totalCost: 5.50,
            legs: [walkLeg, subwayLeg, bikeLeg],
            confidenceTier: .verified
        )
    }
    
    // MARK: - Unit Tests
    
    func testMultimodalTripAttributesCodableRoundTrip() throws {
        let state = MultimodalTripAttributes.ContentState(
            currentLegIndex: 1,
            totalLegs: 3,
            stepHeadline: "Board 6 Train",
            secondaryContext: "at Astor Place",
            modeRawValue: "subway",
            routeBadge: "6",
            routeColorHex: "#00933C",
            departureCountdownSec: 180,
            targetDepartureTime: Date().addingTimeInterval(180),
            destinationETA: Date().addingTimeInterval(1200),
            tripProgressFraction: 0.33,
            exitCode: "Exit 4B",
            carRecommendation: "Board near front car",
            isMissedConnection: false,
            recoveryNotice: nil
        )
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(state)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(MultimodalTripAttributes.ContentState.self, from: data)
        
        XCTAssertEqual(decoded.currentLegIndex, 1)
        XCTAssertEqual(decoded.totalLegs, 3)
        XCTAssertEqual(decoded.stepHeadline, "Board 6 Train")
        XCTAssertEqual(decoded.routeBadge, "6")
        XCTAssertEqual(decoded.exitCode, "Exit 4B")
        XCTAssertEqual(decoded.carRecommendation, "Board near front car")
        XCTAssertFalse(decoded.isMissedConnection)
    }
    
    func testNavigationManagerLifecycleAndContentState() {
        let manager = MultimodalTripNavigationManager()
        let fixture = makeMultimodalFixture()
        
        manager.startTripNavigation(itinerary: fixture, initialLegIndex: 0, enableLiveActivity: false)
        XCTAssertTrue(manager.isNavigating)
        XCTAssertEqual(manager.currentLegIndex, 0)
        XCTAssertNotNil(manager.walkingSession)
        
        // Check initial ContentState
        let state0 = manager.buildContentState()
        XCTAssertEqual(state0.currentLegIndex, 0)
        XCTAssertEqual(state0.totalLegs, 3)
        XCTAssertEqual(state0.modeRawValue, "walk")
        
        // Advance to subway leg
        manager.advanceToNextLeg()
        XCTAssertEqual(manager.currentLegIndex, 1)
        XCTAssertNil(manager.walkingSession)
        
        let state1 = manager.buildContentState()
        XCTAssertEqual(state1.currentLegIndex, 1)
        XCTAssertEqual(state1.modeRawValue, "subway")
        XCTAssertEqual(state1.routeBadge, "6")
        XCTAssertEqual(state1.exitCode, "Exit 4B - NW Corner 42nd & Lexington")
        XCTAssertEqual(state1.carRecommendation, "Board near front car")
        
        // Advance to bike leg
        manager.advanceToNextLeg()
        XCTAssertEqual(manager.currentLegIndex, 2)
        XCTAssertNotNil(manager.cyclingSession)
        
        let state2 = manager.buildContentState()
        XCTAssertEqual(state2.currentLegIndex, 2)
        XCTAssertEqual(state2.modeRawValue, "bikeShare")
        
        manager.endNavigation()
        XCTAssertFalse(manager.isNavigating)
        XCTAssertNil(manager.walkingSession)
        XCTAssertNil(manager.cyclingSession)
    }
    
    func test1TapRecoveryHotSwapWorkflow() {
        let manager = MultimodalTripNavigationManager()
        let fixture = makeMultimodalFixture()
        
        manager.startTripNavigation(itinerary: fixture, initialLegIndex: 0, enableLiveActivity: false)
        
        // Simulate a detected connection miss
        let event = MissedConnectionEvent(
            legIndex: 1,
            missedLeg: fixture.legs[1],
            stationName: "Astor Place",
            scheduledDepartureSec: 29100,
            estimatedUserArrivalSec: 29300,
            deficitSeconds: 200,
            status: .imminentMiss(deficitSeconds: 200)
        )
        
        let plan = DynamicRecoveryEngine().generateRecoveryPlan(for: event, activeItinerary: fixture)
        manager.activeRecoveryPlan = plan
        XCTAssertNotNil(manager.activeRecoveryPlan)
        
        // 1-Tap acceptance of the primary alternative
        let primaryAlt = plan.primaryOption
        manager.acceptRecoveryOption(primaryAlt)
        
        XCTAssertNil(manager.activeRecoveryPlan, "Plan must clear on acceptance")
        XCTAssertEqual(manager.itinerary?.id, primaryAlt.recoveryItinerary.id, "Active itinerary must hot-swap to the recovery itinerary")
        XCTAssertEqual(manager.itinerary?.legs[1].departureTimeSec, fixture.legs[1].departureTimeSec + 240)
    }
}
