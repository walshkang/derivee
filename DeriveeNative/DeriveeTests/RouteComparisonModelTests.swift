import XCTest
import SwiftUI
@testable import Derivee

final class RouteComparisonModelTests: XCTestCase {

    // MARK: - Clock & Formatting Tests
    
    func testClockFormattingAndSecondsConversion() {
        // Midnight (00:00:00)
        XCTAssertEqual(JourneyItinerary.formatSecondsToClock(0), "12:00 AM")
        
        // 8:42 AM (31,320 seconds)
        XCTAssertEqual(JourneyItinerary.formatSecondsToClock(31320), "8:42 AM")
        
        // 12:00 PM (43,200 seconds)
        XCTAssertEqual(JourneyItinerary.formatSecondsToClock(43200), "12:00 PM")
        
        // 1:15 PM (47,700 seconds)
        XCTAssertEqual(JourneyItinerary.formatSecondsToClock(47700), "1:15 PM")
        
        // 11:59 PM (86,340 seconds)
        XCTAssertEqual(JourneyItinerary.formatSecondsToClock(86340), "11:59 PM")
        
        // Past midnight schedule (25:30:00 = 91,800 seconds -> 1:30 AM)
        XCTAssertEqual(JourneyItinerary.formatSecondsToClock(91800), "1:30 AM")
    }

    func testConfidenceIntervalFormatting() {
        let baseDep: UInt32 = 31320 // 8:42 AM
        let arrP10: UInt32 = 31800  // 8:50 AM
        let arrP50: UInt32 = 31920  // 8:52 AM
        let arrP90: UInt32 = 32040  // 8:54 AM (±2m uncertainty)
        
        let itinerary = JourneyItinerary(
            profile: .mostReliable,
            departureTimeSec: baseDep,
            arrivalTimeSec: arrP50,
            p10ArrivalSec: arrP10,
            p50ArrivalSec: arrP50,
            p90ArrivalSec: arrP90,
            totalCost: 2.90,
            confidenceTier: .verified
        )
        
        XCTAssertEqual(itinerary.formattedDepartureTime, "8:42 AM")
        XCTAssertEqual(itinerary.formattedArrivalTime, "8:52 AM")
        XCTAssertEqual(itinerary.formattedConfidenceInterval, "8:50 AM – 8:54 AM (±2m)")
        XCTAssertEqual(itinerary.uncertaintyMinutes, 4)
        XCTAssertEqual(itinerary.formattedCost, "$2.90")
        XCTAssertEqual(itinerary.formattedDuration, "10 min")
    }

    func testIdenticalP10P90ConfidenceInterval() {
        let exactArrival: UInt32 = 36000 // 10:00 AM
        let itinerary = JourneyItinerary(
            departureTimeSec: 34200,
            arrivalTimeSec: exactArrival,
            p10ArrivalSec: exactArrival,
            p50ArrivalSec: exactArrival,
            p90ArrivalSec: exactArrival
        )
        
        XCTAssertEqual(itinerary.formattedConfidenceInterval, "10:00 AM")
        XCTAssertEqual(itinerary.uncertaintyMinutes, 0)
    }

    // MARK: - Profile Filtering & Sorting Tests

    func testProfileSortingAndFiltering() async {
        let vm = await MainActor.run { RouteComparisonViewModel() }
        
        // 1. Most Reliable profile: should prioritize lowest arrival uncertainty (P90 - P10)
        await MainActor.run {
            vm.selectProfile(.mostReliable)
            XCTAssertEqual(vm.selectedProfile, .mostReliable)
            XCTAssertFalse(vm.filteredJourneys.isEmpty)
            
            // First item should have minimal uncertainty minutes
            if vm.filteredJourneys.count >= 2 {
                let first = vm.filteredJourneys[0]
                let second = vm.filteredJourneys[1]
                XCTAssertLessThanOrEqual(first.uncertaintyMinutes, second.uncertaintyMinutes)
            }
        }
        
        // 2. Fastest profile: should sort strictly by earliest arrival timestamp
        await MainActor.run {
            vm.selectProfile(.fastest)
            XCTAssertEqual(vm.selectedProfile, .fastest)
            
            for i in 0..<(vm.filteredJourneys.count - 1) {
                let current = vm.filteredJourneys[i]
                let next = vm.filteredJourneys[i + 1]
                XCTAssertLessThanOrEqual(current.arrivalTimeSec, next.arrivalTimeSec, "Fastest profile must order by arrival time")
            }
        }
        
        // 3. Fewest Transfers profile: should sort by transfer count ascending
        await MainActor.run {
            vm.selectProfile(.fewestTransfers)
            XCTAssertEqual(vm.selectedProfile, .fewestTransfers)
            
            for i in 0..<(vm.filteredJourneys.count - 1) {
                let current = vm.filteredJourneys[i]
                let next = vm.filteredJourneys[i + 1]
                XCTAssertLessThanOrEqual(current.transferCount, next.transferCount, "Fewest Transfers must order by transfer count")
            }
        }
        
        // 4. Step-Free profile: should include accessible routes
        await MainActor.run {
            vm.selectProfile(.stepFree)
            XCTAssertEqual(vm.selectedProfile, .stepFree)
            XCTAssertFalse(vm.filteredJourneys.isEmpty)
        }
        
        // 5. Bike + Rail profile: should prioritize itineraries with biking distance
        await MainActor.run {
            vm.selectProfile(.multiModalBikeRail)
            XCTAssertEqual(vm.selectedProfile, .multiModalBikeRail)
            
            let first = vm.filteredJourneys.first
            XCTAssertNotNil(first)
            XCTAssertGreaterThan(first?.bikingDistanceMeters ?? 0, 0, "Bike + Rail top result should include cycling legs")
        }
    }

    // MARK: - Cost, Distance & Effort Calculations

    func testCostAndEffortAggregation() {
        let legs = [
            JourneyLeg(
                mode: .walk,
                originName: "A",
                destinationName: "B",
                departureTimeSec: 1000,
                arrivalTimeSec: 1300,
                distanceMeters: 400
            ),
            JourneyLeg(
                mode: .bikeShare,
                originName: "B",
                destinationName: "C",
                departureTimeSec: 1300,
                arrivalTimeSec: 1700,
                distanceMeters: 1200,
                bikeMetadata: BikeLegMetadata(isEBike: true, batterySocPercent: 88)
            ),
            JourneyLeg(
                mode: .subway,
                originName: "C",
                destinationName: "D",
                departureTimeSec: 1800,
                arrivalTimeSec: 2400,
                routeId: "L"
            )
        ]
        
        let itinerary = JourneyItinerary(
            departureTimeSec: 1000,
            arrivalTimeSec: 2400,
            totalCost: 4.95,
            legs: legs
        )
        
        XCTAssertEqual(itinerary.walkingDistanceMeters, 400)
        XCTAssertEqual(itinerary.walkingDurationSec, 300)
        XCTAssertEqual(itinerary.bikingDistanceMeters, 1200)
        XCTAssertEqual(itinerary.bikingDurationSec, 400)
        XCTAssertEqual(itinerary.transitDurationSec, 600)
        XCTAssertEqual(itinerary.totalDistanceMeters, 1600)
        XCTAssertEqual(itinerary.transferCount, 0, "Single transit leg has 0 transfers")
        XCTAssertGreaterThan(itinerary.caloriesBurned, 0)
        XCTAssertEqual(itinerary.formattedCost, "$4.95")
    }

    // MARK: - Disruptions & Callouts

    func testDisruptionPropertiesAndMapping() {
        let disruption = JourneyDisruption(
            routeId: "6",
            affectedStopIds: ["101", "102"],
            severity: .minorDelay,
            headline: "Track Work at 59th St",
            detailText: "Expect +4 min delay on uptown local trains.",
            isActionable: true,
            rerouteSuggested: true
        )
        
        XCTAssertEqual(disruption.severity.accentColorHex, "#FFB300")
        XCTAssertEqual(disruption.severity.iconName, "exclamationmark.triangle.fill")
        XCTAssertTrue(disruption.isActionable)
        XCTAssertTrue(disruption.rerouteSuggested)
    }

    // MARK: - VoiceOver Accessibility Statements

    func testVoiceOverSummaryGeneration() {
        let itinerary = JourneyItinerary(
            profile: .mostReliable,
            departureTimeSec: 28800, // 8:00 AM
            arrivalTimeSec: 29700,   // 8:15 AM
            p10ArrivalSec: 29640,    // 8:14 AM
            p90ArrivalSec: 29760,    // 8:16 AM
            totalCost: 2.90,
            confidenceTier: .verified
        )
        
        let voText = itinerary.voiceOverSummary
        XCTAssertTrue(voText.contains("Most Reliable route"))
        XCTAssertTrue(voText.contains("Depart at 8:00 AM"))
        XCTAssertTrue(voText.contains("8:14 AM and 8:16 AM"))
        XCTAssertTrue(voText.contains("Verified live GPS tracking"))
    }
}
