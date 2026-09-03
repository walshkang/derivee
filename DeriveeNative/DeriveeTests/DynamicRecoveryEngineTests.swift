import XCTest
import CoreLocation
@testable import Derivee

final class DynamicRecoveryEngineTests: XCTestCase {
    
    private let engine = DynamicRecoveryEngine()
    
    private func makeTestItinerary() -> JourneyItinerary {
        let walkLeg = JourneyLeg(
            id: UUID(),
            mode: .walk,
            originName: "Washington Square",
            destinationName: "Astor Place Station",
            departureTimeSec: 28800,
            arrivalTimeSec: 29300,
            durationSec: 500,
            distanceMeters: 400,
            confidenceTier: .verified
        )
        
        let subwayLeg = JourneyLeg(
            id: UUID(),
            mode: .subway,
            originName: "Astor Place",
            destinationName: "Grand Central - 42nd St",
            departureTimeSec: 29400,
            arrivalTimeSec: 29800,
            durationSec: 400,
            distanceMeters: 2200,
            routeId: "6",
            confidenceTier: .verified
        )
        
        let finalWalk = JourneyLeg(
            id: UUID(),
            mode: .walk,
            originName: "Grand Central - 42nd St",
            destinationName: "Bryant Park",
            departureTimeSec: 29800,
            arrivalTimeSec: 30000,
            durationSec: 200,
            distanceMeters: 300,
            confidenceTier: .verified
        )
        
        return JourneyItinerary(
            id: UUID(),
            profile: .mostReliable,
            departureTimeSec: 28800,
            arrivalTimeSec: 30000,
            p10ArrivalSec: 29940,
            p50ArrivalSec: 30000,
            p90ArrivalSec: 30120,
            totalCost: 2.90,
            legs: [walkLeg, subwayLeg, finalWalk],
            confidenceTier: .verified
        )
    }
    
    // MARK: - Tests
    
    func testRecoveryPlanGenerationForSubwayMiss() {
        let itin = makeTestItinerary()
        let event = MissedConnectionEvent(
            legIndex: 1,
            missedLeg: itin.legs[1],
            stationName: "Astor Place",
            scheduledDepartureSec: 29400,
            estimatedUserArrivalSec: 29550,
            deficitSeconds: 150,
            status: .imminentMiss(deficitSeconds: 150)
        )
        
        let plan = engine.generateRecoveryPlan(
            for: event,
            activeItinerary: itin,
            availableBikesAtNearbyDock: 12,
            isEBikeAvailable: true,
            batterySoc: 90
        )
        
        XCTAssertEqual(plan.event.stationName, "Astor Place")
        XCTAssertGreaterThanOrEqual(plan.options.count, 2, "Should generate at least next departure and bike share options")
        
        // Primary option: Next 6 Train
        let primary = plan.primaryOption
        XCTAssertTrue(primary.isPrimaryRecommended)
        XCTAssertEqual(primary.mode, .subway)
        XCTAssertEqual(primary.routeBadge, "6")
        XCTAssertEqual(primary.deltaMinutes, 4, "Subway headway should default to 4 minutes")
        XCTAssertEqual(primary.formattedDelta, "+4m")
        
        // Secondary option: Citi Bike Fallback
        let bikeOpt = plan.options.first(where: { $0.type == .bikeShareFallback })
        XCTAssertNotNil(bikeOpt)
        XCTAssertEqual(bikeOpt?.mode, .bikeShare)
        XCTAssertEqual(bikeOpt?.batterySocPercent, 90)
        XCTAssertEqual(bikeOpt?.dockRisk, .low)
    }
    
    func testSplicedItineraryPreservesChronologicalContinuity() {
        let itin = makeTestItinerary()
        let event = MissedConnectionEvent(
            legIndex: 1,
            missedLeg: itin.legs[1],
            stationName: "Astor Place",
            scheduledDepartureSec: 29400,
            estimatedUserArrivalSec: 29550,
            deficitSeconds: 150,
            status: .imminentMiss(deficitSeconds: 150)
        )
        
        let plan = engine.generateRecoveryPlan(for: event, activeItinerary: itin)
        let splicedItin = plan.primaryOption.recoveryItinerary
        
        XCTAssertEqual(splicedItin.legs.count, itin.legs.count)
        
        // Leg 0 unchanged
        XCTAssertEqual(splicedItin.legs[0].departureTimeSec, itin.legs[0].departureTimeSec)
        XCTAssertEqual(splicedItin.legs[0].arrivalTimeSec, itin.legs[0].arrivalTimeSec)
        
        // Leg 1 shifted by +240s
        XCTAssertEqual(splicedItin.legs[1].departureTimeSec, itin.legs[1].departureTimeSec + 240)
        XCTAssertEqual(splicedItin.legs[1].arrivalTimeSec, itin.legs[1].arrivalTimeSec + 240)
        
        // Leg 2 shifted by +240s
        XCTAssertEqual(splicedItin.legs[2].departureTimeSec, itin.legs[2].departureTimeSec + 240)
        XCTAssertEqual(splicedItin.legs[2].arrivalTimeSec, itin.legs[2].arrivalTimeSec + 240)
        
        // Total arrival time matches
        XCTAssertEqual(splicedItin.arrivalTimeSec, itin.arrivalTimeSec + 240)
    }
}
