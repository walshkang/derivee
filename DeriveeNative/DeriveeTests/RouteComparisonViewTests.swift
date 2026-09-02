import XCTest
import SwiftUI
import SnapshotTesting
@testable import Derivee

@MainActor
final class RouteComparisonViewTests: XCTestCase {

    // MARK: - Confidence Badge Tests
    
    func testConfidenceBadgeAllTiersSnapshot() {
        let view = VStack(spacing: 12) {
            ConfidenceBadgeView(tier: .verified, size: .regular)
            ConfidenceBadgeView(tier: .estimated, size: .regular)
            ConfidenceBadgeView(tier: .staticSchedule, size: .regular)
            
            HStack(spacing: 8) {
                ConfidenceBadgeView(tier: .verified, size: .compact)
                ConfidenceBadgeView(tier: .estimated, size: .compact)
                ConfidenceBadgeView(tier: .staticSchedule, size: .compact)
            }
        }
        .padding(20)
        .background(Color(hex: "#F9F9F6"))
        
        let vc = UIHostingController(rootView: view)
        assertSnapshot(of: vc, as: .image(on: ViewImageConfig(size: CGSize(width: 320, height: 180)), precision: 0.98))
    }

    // MARK: - Multi-Profile Selector Bar Tests

    func testMultiProfileSelectorBarSnapshot() {
        let view = VStack(spacing: 16) {
            MultiProfileSelectorBar(selectedProfile: .constant(.mostReliable))
            MultiProfileSelectorBar(selectedProfile: .constant(.fastest))
            MultiProfileSelectorBar(selectedProfile: .constant(.multiModalBikeRail))
        }
        .padding(.vertical, 16)
        .background(Color(hex: "#F9F9F6"))
        
        let vc = UIHostingController(rootView: view)
        assertSnapshot(of: vc, as: .image(on: ViewImageConfig(size: CGSize(width: 375, height: 240)), precision: 0.98))
    }

    // MARK: - Route Comparison Card Snapshots

    func testRouteComparisonCardSubwaySnapshot() {
        let legs = [
            JourneyLeg(
                mode: .walk,
                originName: "Astor Place",
                destinationName: "Astor Pl Station",
                departureTimeSec: 31320,
                arrivalTimeSec: 31440,
                distanceMeters: 140
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
                confidenceTier: .verified
            ),
            JourneyLeg(
                mode: .walk,
                originName: "Grand Central Platform",
                destinationName: "Grand Central Terminal",
                departureTimeSec: 32100,
                arrivalTimeSec: 32220,
                distanceMeters: 160
            )
        ]
        
        let itinerary = JourneyItinerary(
            profile: .mostReliable,
            departureTimeSec: 31320,
            arrivalTimeSec: 32220,
            p10ArrivalSec: 32160,
            p50ArrivalSec: 32220,
            p90ArrivalSec: 32340,
            totalCost: 2.90,
            legs: legs,
            confidenceTier: .verified
        )
        
        let view = RouteComparisonCardView(itinerary: itinerary, isSelected: true)
            .padding(16)
            .background(Color(hex: "#F9F9F6"))
        
        let vc = UIHostingController(rootView: view)
        assertSnapshot(of: vc, as: .image(on: ViewImageConfig(size: CGSize(width: 375, height: 180)), precision: 0.98))
    }

    func testRouteComparisonCardMultimodalBikeRailSnapshot() {
        let bikeMetadata = BikeLegMetadata(
            originStationName: "Lafayette St & E 8th St",
            destinationStationName: "Broadway & E 14th St",
            availableBikesAtOrigin: 7,
            availableDocksAtDest: 12,
            isEBike: true,
            batterySocPercent: 92,
            estimatedRangeMiles: 18.0,
            dockGatingRisk: .low
        )
        
        let legs = [
            JourneyLeg(
                mode: .walk,
                originName: "Origin",
                destinationName: "Citi Bike Station",
                departureTimeSec: 31320,
                arrivalTimeSec: 31380,
                distanceMeters: 60
            ),
            JourneyLeg(
                mode: .bikeShare,
                originName: "Lafayette St & E 8th St",
                destinationName: "Broadway & E 14th St",
                departureTimeSec: 31410,
                arrivalTimeSec: 31590,
                distanceMeters: 750,
                bikeMetadata: bikeMetadata
            ),
            JourneyLeg(
                mode: .subway,
                originName: "14 St - Union Sq",
                destinationName: "Grand Central - 42 St",
                departureTimeSec: 31740,
                arrivalTimeSec: 31980,
                routeId: "4",
                headsign: "Woodlawn",
                stopCount: 1,
                confidenceTier: .verified
            ),
            JourneyLeg(
                mode: .walk,
                originName: "Grand Central",
                destinationName: "Main Concourse",
                departureTimeSec: 31980,
                arrivalTimeSec: 32100,
                distanceMeters: 160
            )
        ]
        
        let itinerary = JourneyItinerary(
            profile: .multiModalBikeRail,
            departureTimeSec: 31320,
            arrivalTimeSec: 32100,
            p10ArrivalSec: 32040,
            p50ArrivalSec: 32100,
            p90ArrivalSec: 32220,
            totalCost: 4.95,
            legs: legs,
            confidenceTier: .verified
        )
        
        let view = RouteComparisonCardView(itinerary: itinerary, isSelected: false)
            .padding(16)
            .background(Color(hex: "#F9F9F6"))
        
        let vc = UIHostingController(rootView: view)
        assertSnapshot(of: vc, as: .image(on: ViewImageConfig(size: CGSize(width: 375, height: 180)), precision: 0.98))
    }

    func testRouteComparisonCardWithDisruptionSnapshot() {
        let disruption = JourneyDisruption(
            routeId: "6",
            affectedStopIds: ["10023"],
            severity: .minorDelay,
            headline: "Delays on 6 Line",
            detailText: "Expect +4m dwell time at 59th St due to signal work.",
            isActionable: true,
            rerouteSuggested: true
        )
        
        let legs = [
            JourneyLeg(
                mode: .walk,
                originName: "Astor Place",
                destinationName: "Astor Pl Station",
                departureTimeSec: 31320,
                arrivalTimeSec: 31440,
                distanceMeters: 140
            ),
            JourneyLeg(
                mode: .subway,
                originName: "Astor Pl",
                destinationName: "Grand Central - 42 St",
                departureTimeSec: 31500,
                arrivalTimeSec: 32340,
                routeId: "6",
                headsign: "Pelham Bay Park",
                stopCount: 5,
                confidenceTier: .estimated,
                disruption: disruption
            )
        ]
        
        let itinerary = JourneyItinerary(
            profile: .mostReliable,
            departureTimeSec: 31320,
            arrivalTimeSec: 32460,
            p10ArrivalSec: 32340,
            p50ArrivalSec: 32460,
            p90ArrivalSec: 32700,
            totalCost: 2.90,
            legs: legs,
            disruptions: [disruption],
            confidenceTier: .estimated
        )
        
        let view = RouteComparisonCardView(itinerary: itinerary, isSelected: false)
            .padding(16)
            .background(Color(hex: "#F9F9F6"))
        
        let vc = UIHostingController(rootView: view)
        assertSnapshot(of: vc, as: .image(on: ViewImageConfig(size: CGSize(width: 375, height: 260)), precision: 0.98))
    }

    func testRouteLegDetailViewSnapshot() {
        let vm = RouteComparisonViewModel()
        guard let itinerary = vm.selectedItinerary else {
            XCTFail("Default fixture must contain itineraries")
            return
        }
        
        let view = RouteLegDetailView(itinerary: itinerary)
            .frame(width: 375, height: 600)
        
        let vc = UIHostingController(rootView: view)
        assertSnapshot(of: vc, as: .image(on: ViewImageConfig(size: CGSize(width: 375, height: 600)), precision: 0.98))
    }

    func testRouteComparisonListViewSnapshot() {
        let vm = RouteComparisonViewModel()
        let view = RouteComparisonListView(viewModel: vm)
            .frame(width: 375, height: 750)
        
        let vc = UIHostingController(rootView: view)
        assertSnapshot(of: vc, as: .image(on: ViewImageConfig(size: CGSize(width: 375, height: 750)), precision: 0.98))
    }
}
