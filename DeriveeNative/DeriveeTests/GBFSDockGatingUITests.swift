import XCTest
import SwiftUI
import CoreLocation
@testable import Derivee

@MainActor
final class GBFSDockGatingUITests: XCTestCase {
    
    // MARK: - 1. 3-Tier Dock Availability Gating Tests
    
    func testDockGatingRiskClassification() {
        // Low Risk (>3 docks)
        XCTAssertEqual(GBFSDockGatingRisk.risk(forAvailableDocks: 15), .low)
        XCTAssertEqual(GBFSDockGatingRisk.risk(forAvailableDocks: 4), .low)
        XCTAssertEqual(GBFSDockGatingRisk.low.title, "Docks Available")
        
        // Moderate Risk (1-2 docks)
        XCTAssertEqual(GBFSDockGatingRisk.risk(forAvailableDocks: 2), .moderate)
        XCTAssertEqual(GBFSDockGatingRisk.risk(forAvailableDocks: 1), .moderate)
        XCTAssertEqual(GBFSDockGatingRisk.moderate.title, "Limited Docks")
        
        // High Risk (0 docks / Station Full)
        XCTAssertEqual(GBFSDockGatingRisk.risk(forAvailableDocks: 0), .high)
        XCTAssertEqual(GBFSDockGatingRisk.high.title, "Dock Starvation")
    }
    
    func testDockAvailabilityBadgeViewProperties() {
        let lowBadge = DockAvailabilityBadgeView(availableDocks: 12)
        XCTAssertEqual(lowBadge.risk, .low)
        
        var fallbackTapped = false
        let moderateBadge = DockAvailabilityBadgeView(
            availableDocks: 2,
            fallbackStationName: "Broadway & E 14th St",
            isCompact: false,
            onTapFallback: { fallbackTapped = true }
        )
        XCTAssertEqual(moderateBadge.risk, .moderate)
        moderateBadge.onTapFallback?()
        XCTAssertTrue(fallbackTapped)
        
        let highBadge = DockAvailabilityBadgeView(availableDocks: 0, isCompact: true)
        XCTAssertEqual(highBadge.risk, .high)
    }
    
    // MARK: - 2. Pre-Armed Fallback Card & Auto-Reroute Banner Tests
    
    func testPreArmedFallbackCardExecution() {
        var switched = false
        let card = PreArmedFallbackCard(
            primaryStationName: "Union Square West",
            fallbackStationName: "Broadway & E 14th St",
            availableDocksAtFallback: 14,
            extraWalkDistanceMeters: 200,
            extraWalkDurationSec: 100,
            onSwitchToFallback: { switched = true }
        )
        
        XCTAssertEqual(card.primaryStationName, "Union Square West")
        XCTAssertEqual(card.fallbackStationName, "Broadway & E 14th St")
        XCTAssertEqual(card.availableDocksAtFallback, 14)
        card.onSwitchToFallback()
        XCTAssertTrue(switched)
    }
    
    func testDockOverflowAutoRerouteBannerExecution() {
        var accepted = false
        let banner = DockOverflowAutoRerouteBanner(
            failedStationName: "Astor Place",
            reroutedStationName: "Lafayette & 8th St",
            availableDocksAtReroute: 11,
            extraWalkMeters: 150,
            onAcceptReroute: { accepted = true }
        )
        
        XCTAssertEqual(banner.failedStationName, "Astor Place")
        XCTAssertEqual(banner.reroutedStationName, "Lafayette & 8th St")
        XCTAssertEqual(banner.availableDocksAtReroute, 11)
        banner.onAcceptReroute()
        XCTAssertTrue(accepted)
    }
    
    // MARK: - 3. E-Bike Battery SOC % & Usable Range Radius Tests
    
    func testEBikeBatterySOCOverlayRangeCalculation() {
        let overlay85 = EBikeBatterySOCOverlay(batterySocPercent: 85, legDistanceMeters: 3000)
        // 85% * 0.20 mi/% = 17.0 miles
        XCTAssertEqual(overlay85.estimatedRangeMiles, 17.0, accuracy: 0.01)
        XCTAssertEqual(overlay85.estimatedRangeMeters, 17.0 * 1609.34, accuracy: 1.0)
        XCTAssertFalse(overlay85.isRangeDeficit)
        XCTAssertEqual(overlay85.deficitMiles, 0.0)
        
        // Low battery with range deficit (10% * 0.20 = 2.0 miles, leg distance = 4.0 miles ~ 6437m)
        let overlayDeficit = EBikeBatterySOCOverlay(batterySocPercent: 10, legDistanceMeters: 6437)
        XCTAssertEqual(overlayDeficit.estimatedRangeMiles, 2.0, accuracy: 0.01)
        XCTAssertTrue(overlayDeficit.isRangeDeficit)
        XCTAssertGreaterThan(overlayDeficit.deficitMiles, 1.9)
    }
    
    func testEBikeBatterySOCPillInitialization() {
        let pill = EBikeBatterySOCPill(batterySocPercent: 92, estimatedRangeMiles: 18.4)
        XCTAssertEqual(pill.batterySocPercent, 92)
        XCTAssertEqual(pill.estimatedRangeMiles, 18.4)
    }
    
    // MARK: - 4. ActiveCyclingNavigationSession Telemetry & State Transitions
    
    func testActiveCyclingNavigationSessionStateTransitions() {
        let itinerary = makeCyclingItineraryFixture()
        let session = ActiveCyclingNavigationSession(itinerary: itinerary, initialLegIndex: 1)
        
        XCTAssertTrue(session.isNavigating)
        XCTAssertEqual(session.currentManeuver, .turnLeft)
        XCTAssertEqual(session.currentDistanceMeters, 180)
        XCTAssertEqual(session.destinationDockName, "Broadway & E 14th St")
        XCTAssertEqual(session.availableDocksAtDest, 12)
        XCTAssertEqual(session.dockRisk, .low)
        XCTAssertFalse(session.isAutoRerouteActive)
        
        // 1. Telemetry update
        session.updateUserLocation(CLLocationCoordinate2D(latitude: 40.73, longitude: -73.99))
        XCTAssertLessThanOrEqual(session.currentDistanceMeters, 180)
        
        // 2. Dock availability drops to 2 (Moderate Risk: Fallback pre-armed)
        session.updateDockState(docks: 2)
        XCTAssertEqual(session.dockRisk, .moderate)
        XCTAssertNotNil(session.fallbackStationName)
        XCTAssertFalse(session.isAutoRerouteActive)
        
        // 3. Dock availability drops to 0 (High Risk: Auto-Reroute active)
        session.updateDockState(docks: 0)
        XCTAssertEqual(session.dockRisk, .high)
        XCTAssertTrue(session.isAutoRerouteActive)
        
        // 4. Accept auto-reroute
        let fallbackName = session.fallbackStationName
        session.acceptAutoReroute()
        XCTAssertEqual(session.destinationDockName, fallbackName)
        XCTAssertEqual(session.dockRisk, .low)
        XCTAssertFalse(session.isAutoRerouteActive)
        
        // 5. Advance maneuvers
        session.advanceToNextManeuver()
        XCTAssertEqual(session.currentManeuver, .slightRight)
        
        session.endCycling()
        XCTAssertFalse(session.isNavigating)
    }
    
    // MARK: - Fixtures
    
    private func makeCyclingItineraryFixture() -> JourneyItinerary {
        let walkLeg = JourneyLeg(
            mode: .walk,
            originName: "Origin",
            destinationName: "Lafayette St & 8th St",
            departureTimeSec: 30000,
            arrivalTimeSec: 30060,
            distanceMeters: 60
        )
        
        let bikeMeta = BikeLegMetadata(
            originStationName: "Lafayette St & E 8th St",
            destinationStationName: "Broadway & E 14th St",
            availableBikesAtOrigin: 8,
            availableDocksAtDest: 12,
            isEBike: true,
            batterySocPercent: 90,
            estimatedRangeMiles: 18.0,
            dockGatingRisk: .low,
            cyclingInfrastructureType: .protectedBikeTrack,
            nextManeuver: .turnLeft,
            nextManeuverDistanceMeters: 180
        )
        
        let bikeLeg = JourneyLeg(
            mode: .bikeShare,
            originName: "Lafayette St & E 8th St",
            destinationName: "Broadway & E 14th St",
            departureTimeSec: 30060,
            arrivalTimeSec: 30300,
            distanceMeters: 800,
            bikeMetadata: bikeMeta
        )
        
        return JourneyItinerary(
            profile: .multiModalBikeRail,
            departureTimeSec: 30000,
            arrivalTimeSec: 30300,
            legs: [walkLeg, bikeLeg]
        )
    }
}
