import XCTest
import SwiftUI
import GRDB
@testable import Derivee

final class LineReliabilityBadgeTests: XCTestCase {
    
    // MARK: - 1. Tier Threshold & Boundary Tests
    
    func testReliabilityTierThresholds() {
        // High: OTP >= 90%
        XCTAssertEqual(LineReliabilityTier(score: 100.0), .high)
        XCTAssertEqual(LineReliabilityTier(score: 95.5), .high)
        XCTAssertEqual(LineReliabilityTier(score: 90.0), .high)
        
        // Moderate: 70% <= OTP < 90%
        XCTAssertEqual(LineReliabilityTier(score: 89.99), .moderate)
        XCTAssertEqual(LineReliabilityTier(score: 85.0), .moderate)
        XCTAssertEqual(LineReliabilityTier(score: 70.0), .moderate)
        
        // Variable: OTP < 70%
        XCTAssertEqual(LineReliabilityTier(score: 69.99), .variable)
        XCTAssertEqual(LineReliabilityTier(score: 55.0), .variable)
        XCTAssertEqual(LineReliabilityTier(score: 0.0), .variable)
        XCTAssertEqual(LineReliabilityTier(score: -5.0), .variable)
    }
    
    // MARK: - 2. Glyphs, Labels, Display Strings & Accessibility
    
    func testReliabilityTierGlyphsLabelsAndText() {
        // High
        let high = LineReliabilityTier.high
        XCTAssertEqual(high.glyph, "●")
        XCTAssertEqual(high.label, "High")
        XCTAssertEqual(high.displayText, "● High")
        XCTAssertEqual(high.iconName, "circle.fill")
        XCTAssertEqual(high.accessibilityText, "High reliability")
        
        // Moderate
        let moderate = LineReliabilityTier.moderate
        XCTAssertEqual(moderate.glyph, "◐")
        XCTAssertEqual(moderate.label, "Moderate")
        XCTAssertEqual(moderate.displayText, "◐ Moderate")
        XCTAssertEqual(moderate.iconName, "circle.lefthalf.filled")
        XCTAssertEqual(moderate.accessibilityText, "Moderate reliability")
        
        // Variable
        let variable = LineReliabilityTier.variable
        XCTAssertEqual(variable.glyph, "○")
        XCTAssertEqual(variable.label, "Variable")
        XCTAssertEqual(variable.displayText, "○ Variable")
        XCTAssertEqual(variable.iconName, "circle")
        XCTAssertEqual(variable.accessibilityText, "Variable reliability")
    }
    
    // MARK: - 3. Arrival Direction Resolution
    
    func testArrivalInfoResolvedDirectionId() {
        // Direction 1: Downtown / South / Brooklyn / Outbound / West
        let dtArrival = SpatialDatabaseManager.ArrivalInfo(
            line: "6",
            destination: "Brooklyn Bridge",
            minutes: 3,
            direction: "Downtown & Brooklyn"
        )
        XCTAssertEqual(dtArrival.resolvedDirectionId, 1)
        
        let southArrival = SpatialDatabaseManager.ArrivalInfo(
            line: "M15",
            destination: "South Ferry",
            minutes: 5,
            direction: "Southbound"
        )
        XCTAssertEqual(southArrival.resolvedDirectionId, 1)
        
        let outboundArrival = SpatialDatabaseManager.ArrivalInfo(
            line: "SIR",
            destination: "Tottenville",
            minutes: 12,
            direction: "Outbound (Tottenville)"
        )
        XCTAssertEqual(outboundArrival.resolvedDirectionId, 1)
        
        let westArrival = SpatialDatabaseManager.ArrivalInfo(
            line: "M14D-SBS",
            destination: "Chelsea Piers",
            minutes: 8,
            direction: "Westbound"
        )
        XCTAssertEqual(westArrival.resolvedDirectionId, 1)
        
        // Direction 0: Uptown / North / Manhattan / Queens / Bronx / Inbound / East
        let uptownArrival = SpatialDatabaseManager.ArrivalInfo(
            line: "6",
            destination: "Pelham Bay Park",
            minutes: 4,
            direction: "Uptown & The Bronx"
        )
        XCTAssertEqual(uptownArrival.resolvedDirectionId, 0)
        
        let manhattanArrival = SpatialDatabaseManager.ArrivalInfo(
            line: "L",
            destination: "8th Ave",
            minutes: 2,
            direction: "Manhattan-bound"
        )
        XCTAssertEqual(manhattanArrival.resolvedDirectionId, 0)
        
        let queensArrival = SpatialDatabaseManager.ArrivalInfo(
            line: "7",
            destination: "Flushing",
            minutes: 6,
            direction: "Queens-bound"
        )
        XCTAssertEqual(queensArrival.resolvedDirectionId, 0)
        
        let inboundArrival = SpatialDatabaseManager.ArrivalInfo(
            line: "SIR",
            destination: "St George",
            minutes: 10,
            direction: "Inbound (St. George)"
        )
        XCTAssertEqual(inboundArrival.resolvedDirectionId, 0)
        
        let nilDirectionArrival = SpatialDatabaseManager.ArrivalInfo(
            line: "L",
            destination: "Canarsie",
            minutes: 5,
            direction: nil
        )
        XCTAssertEqual(nilDirectionArrival.resolvedDirectionId, 0)
    }
    
    // MARK: - 4. Database Slot Profile & Reliability Tier Lookup
    
    func testReliabilityTierDatabaseResolutionWithSlotProfile() async throws {
        let engine = TransitDatabaseEngine.makeForTesting(inMemory: true)
        
        let slotDate = Date(timeIntervalSince1970: 1700000000) // Deterministic epoch
        let slotIdx = TripSlotProfileRecord.slotIndex(for: slotDate)
        let dayType = TripSlotProfileRecord.dayType(for: slotDate)
        
        let profiles = [
            TripSlotProfileRecord(
                routeId: "6",
                directionId: 0,
                originSlotIndex: slotIdx,
                stopId: "stop_pelham",
                dayType: dayType,
                medianDurationSec: 600,
                p90DurationSec: 720,
                regularityPct: 94.2, // High
                sampleCount: 50
            ),
            TripSlotProfileRecord(
                routeId: "4",
                directionId: 1,
                originSlotIndex: slotIdx,
                stopId: "stop_brooklyn_bridge",
                dayType: dayType,
                medianDurationSec: 800,
                p90DurationSec: 1050,
                regularityPct: 78.5, // Moderate
                sampleCount: 45
            ),
            TripSlotProfileRecord(
                routeId: "5",
                directionId: 1,
                originSlotIndex: slotIdx,
                stopId: "stop_flatbush",
                dayType: dayType,
                medianDurationSec: 900,
                p90DurationSec: 1300,
                regularityPct: 62.0, // Variable
                sampleCount: 30
            )
        ]
        
        try await engine.insertTripSlotProfiles(profiles)
        
        // 1. Point lookups
        let profile6 = try await engine.fetchTripSlotProfile(
            routeId: "6",
            directionId: 0,
            stopId: "stop_pelham",
            slotIndex: slotIdx,
            dayType: dayType
        )
        XCTAssertNotNil(profile6)
        XCTAssertEqual(LineReliabilityTier(score: profile6!.regularityPct), .high)
        
        let profile4 = try await engine.fetchTripSlotProfile(
            routeId: "4",
            directionId: 1,
            stopId: "stop_brooklyn_bridge",
            slotIndex: slotIdx,
            dayType: dayType
        )
        XCTAssertNotNil(profile4)
        XCTAssertEqual(LineReliabilityTier(score: profile4!.regularityPct), .moderate)
        
        let profile5 = try await engine.fetchTripSlotProfile(
            routeId: "5",
            directionId: 1,
            stopId: "stop_flatbush",
            slotIndex: slotIdx,
            dayType: dayType
        )
        XCTAssertNotNil(profile5)
        XCTAssertEqual(LineReliabilityTier(score: profile5!.regularityPct), .variable)
        
        // 2. Stop batch query
        let stopProfiles = try await engine.fetchSlotProfilesForStop(stopId: "stop_pelham")
        XCTAssertEqual(stopProfiles.count, 1)
        XCTAssertEqual(stopProfiles.first?.routeId, "6")
    }
    
    // MARK: - 5. SwiftUI Badge Construction & View Hierarchy
    
    func testRouteReliabilityBadgeViewConstruction() {
        let highBadge = RouteReliabilityBadge(tier: .high)
        XCTAssertNotNil(highBadge.body)
        
        let moderateBadge = RouteReliabilityBadge(tier: .moderate)
        XCTAssertNotNil(moderateBadge.body)
        
        let variableBadge = RouteReliabilityBadge(tier: .variable)
        XCTAssertNotNil(variableBadge.body)
    }
    
    // MARK: - 6. TransitRevealSheet Injected Tier Resolution
    
    func testTransitRevealSheetReliabilityTierResolution() {
        let testArrival = SpatialDatabaseManager.ArrivalInfo(
            line: "6",
            destination: "Pelham Bay Park",
            minutes: 4,
            direction: "Uptown & The Bronx",
            arrivalDate: Date()
        )
        
        let slot = TripSlotProfileRecord.slotIndex(for: testArrival.arrivalDate)
        let day = TripSlotProfileRecord.dayType(for: testArrival.arrivalDate)
        let key = "6_0_\(slot)_\(day)"
        
        let sheet = TransitRevealSheet(
            stopId: "stop_pelham",
            initialLiveArrivals: [testArrival],
            initialReliabilityTiers: [key: .high]
        )
        
        let resolvedTier = sheet.reliabilityTier(for: testArrival)
        XCTAssertEqual(resolvedTier, .high)
    }
    
    // MARK: - 7. LiveArrivalsCarousel With Injected Reliability Resolver
    
    func testLiveArrivalsCarouselWithReliabilityBadges() {
        let arr1 = SpatialDatabaseManager.ArrivalInfo(
            line: "6",
            destination: "Pelham Bay Park",
            minutes: 3,
            direction: "Uptown & The Bronx",
            distanceDescription: "2 stops away"
        )
        let arr2 = SpatialDatabaseManager.ArrivalInfo(
            line: "4",
            destination: "Woodlawn EXP",
            minutes: 7,
            direction: "Uptown & The Bronx",
            distanceDescription: "5 stops away"
        )
        
        let group = TransitRevealSheet.DirectionalArrivalGroup(
            directionName: "Uptown & The Bronx",
            corridorSubtitle: "Lexington Ave Line",
            iconName: "arrow.up.circle.fill",
            arrivals: [arr1, arr2]
        )
        
        let carousel = LiveArrivalsCarousel(
            groupedArrivals: [group],
            isLiveActive: true,
            isLivePulsing: false,
            isRefreshing: false,
            pollProgress: 0.5,
            reliabilityResolver: { arr in
                if arr.line == "6" { return .high }
                if arr.line == "4" { return .moderate }
                return nil
            },
            onRefresh: {},
            onInspectArrival: { _ in }
        )
        
        XCTAssertNotNil(carousel.body)
    }
}
