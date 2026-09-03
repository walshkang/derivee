import XCTest
import SwiftUI
import SnapshotTesting
@testable import Derivee

@MainActor
final class DynamicRecoverySnapshotTests: XCTestCase {
    
    private func makeFixturePlan() -> DynamicRecoveryPlan {
        let walkLeg = JourneyLeg(
            id: UUID(),
            mode: .walk,
            originName: "Astor Place",
            destinationName: "Subway Platform",
            departureTimeSec: 28800,
            arrivalTimeSec: 29000,
            durationSec: 200,
            distanceMeters: 200,
            confidenceTier: .verified
        )
        
        let subwayLeg = JourneyLeg(
            id: UUID(),
            mode: .subway,
            originName: "Astor Place",
            destinationName: "14th St - Union Sq",
            departureTimeSec: 29100,
            arrivalTimeSec: 29400,
            durationSec: 300,
            distanceMeters: 1000,
            routeId: "6",
            confidenceTier: .verified
        )
        
        let itin = JourneyItinerary(
            id: UUID(),
            profile: .mostReliable,
            departureTimeSec: 28800,
            arrivalTimeSec: 29400,
            p10ArrivalSec: 29350,
            p50ArrivalSec: 29400,
            p90ArrivalSec: 29500,
            totalCost: 2.90,
            legs: [walkLeg, subwayLeg],
            confidenceTier: .verified
        )
        
        let event = MissedConnectionEvent(
            legIndex: 1,
            missedLeg: subwayLeg,
            stationName: "Astor Place",
            scheduledDepartureSec: 29100,
            estimatedUserArrivalSec: 29250,
            deficitSeconds: 150,
            status: .imminentMiss(deficitSeconds: 150)
        )
        
        return DynamicRecoveryEngine().generateRecoveryPlan(for: event, activeItinerary: itin)
    }
    
    // MARK: - Snapshot Tests
    
    func testDynamicRecoveryCardViewSnapshot() {
        let plan = makeFixturePlan()
        let card = DynamicRecoveryCardView(
            plan: plan,
            onAcceptOption: nil,
            onDismiss: nil
        )
        .frame(width: 361)
        .padding(16)
        .background(Color(hex: "#F9F9F6"))
        
        assertSnapshot(
            of: card,
            as: .image(precision: 0.98, layout: .fixed(width: 393, height: 260))
        )
    }
    
    func testNavigationCollapsedPeekRecoveryAlertSnapshot() {
        let plan = makeFixturePlan()
        let view = NavigationCollapsedPeekView(
            leg: plan.event.missedLeg,
            totalDurationFormatted: "10m",
            arrivalTimeFormatted: "8:44 AM",
            recoveryPlan: plan
        )
        .frame(width: 393, height: 80)
        .background(Color.white)
        
        assertSnapshot(
            of: view,
            as: .image(precision: 0.98, layout: .fixed(width: 393, height: 80))
        )
    }
}
