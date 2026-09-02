import XCTest
import SwiftUI
@testable import Derivee

final class ConfidenceBandCanvasTests: XCTestCase {

    // MARK: - Buffer Geometry & Offsets
    
    func testConfidenceBandSliceInitializationAndOffsets() {
        let emptySlice = ConfidenceBandSlice.empty(slotCount: 30, startMinute: 480, stepMinutes: 2)
        XCTAssertEqual(emptySlice.slotCount, 30)
        XCTAssertEqual(emptySlice.startMinute, 480)
        XCTAssertEqual(emptySlice.stepMinutes, 2)
        XCTAssertEqual(emptySlice.values.count, 90) // 30 * 3
        
        // Offset computation: slot * 3 + channel
        XCTAssertEqual(emptySlice.offset(slot: 0, channel: 0), 0)
        XCTAssertEqual(emptySlice.offset(slot: 0, channel: 1), 1)
        XCTAssertEqual(emptySlice.offset(slot: 0, channel: 2), 2)
        XCTAssertEqual(emptySlice.offset(slot: 1, channel: 0), 3)
        XCTAssertEqual(emptySlice.offset(slot: 29, channel: 2), 89)
    }

    // MARK: - Quantile Monotonicity Invariants
    
    func testQuantileMonotonicityInvariants() {
        let fixtures: [ConfidenceBandSlice] = [
            ConfidenceBandSlice.reliableSubwayFixture(slotCount: 60, startMinute: 480),
            ConfidenceBandSlice.volatileBusFixture(slotCount: 60, startMinute: 480),
            ConfidenceBandSlice.moderateRushHourFixture(slotCount: 120, startMinute: 420)
        ]
        
        for fixture in fixtures {
            for slot in 0..<fixture.slotCount {
                let q = fixture.quantiles(slot: slot)
                XCTAssertFalse(q.p10.isNaN)
                XCTAssertFalse(q.p50.isNaN)
                XCTAssertFalse(q.p90.isNaN)
                XCTAssertLessThanOrEqual(q.p10, q.p50, "P10 must be <= P50 at slot \(slot)")
                XCTAssertGreaterThanOrEqual(q.p90, q.p50, "P90 must be >= P50 at slot \(slot)")
                XCTAssertGreaterThanOrEqual(fixture.varianceDisutility(slot: slot), 0.0)
            }
        }
    }

    // MARK: - Variance Disutility & Risk Tiers
    
    func testVarianceDisutilityAndRiskTiers() {
        XCTAssertEqual(ConfidenceRiskTier.tier(forVariance: 1.2), .low)
        XCTAssertEqual(ConfidenceRiskTier.tier(forVariance: 2.49), .low)
        XCTAssertEqual(ConfidenceRiskTier.tier(forVariance: 2.5), .moderate)
        XCTAssertEqual(ConfidenceRiskTier.tier(forVariance: 5.5), .moderate)
        XCTAssertEqual(ConfidenceRiskTier.tier(forVariance: 6.0), .moderate)
        XCTAssertEqual(ConfidenceRiskTier.tier(forVariance: 6.1), .high)
        XCTAssertEqual(ConfidenceRiskTier.tier(forVariance: 12.0), .high)
        
        let lowColor = ConfidenceBandCanvas.colorForVariance(1.5)
        let medColor = ConfidenceBandCanvas.colorForVariance(4.0)
        let highColor = ConfidenceBandCanvas.colorForVariance(8.0)
        
        XCTAssertNotNil(lowColor)
        XCTAssertNotNil(medColor)
        XCTAssertNotNil(highColor)
    }

    // MARK: - DepartureMatrixBuffer Slicing
    
    func testExtractionFromDepartureMatrixBuffer() {
        let matrixBuf = DepartureMatrixBuffer.syntheticFixture(lowVariance: true)
        
        // Extract a 2-hour window (120 minutes) starting at 8:00 AM (480)
        let slice = matrixBuf.extractConfidenceSlice(startMinute: 480, durationMinutes: 120, stepMinutes: 2)
        XCTAssertEqual(slice.slotCount, 60)
        XCTAssertEqual(slice.startMinute, 480)
        XCTAssertEqual(slice.stepMinutes, 2)
        XCTAssertEqual(slice.values.count, 180)
        
        for slot in 0..<slice.slotCount {
            let q = slice.quantiles(slot: slot)
            XCTAssertLessThanOrEqual(q.p10, q.p50)
            XCTAssertGreaterThanOrEqual(q.p90, q.p50)
        }
        
        // Extract full day
        let fullDaySlice = matrixBuf.asConfidenceSlice()
        XCTAssertEqual(fullDaySlice.slotCount, 1440)
        XCTAssertEqual(fullDaySlice.values.count, 4320)
    }

    // MARK: - From Discrete Points
    
    func testConstructionFromDiscretePoints() {
        let points = [
            ConfidenceDataPoint(minuteOfDay: 480, p10: 2.0, p50: 4.0, p90: 6.0),
            ConfidenceDataPoint(minuteOfDay: 485, p10: 2.5, p50: 4.5, p90: 7.0),
            ConfidenceDataPoint(minuteOfDay: 490, p10: 3.0, p50: 5.0, p90: 8.5)
        ]
        
        let slice = ConfidenceBandSlice.fromPoints(points, stepMinutes: 5)
        XCTAssertEqual(slice.slotCount, 3)
        XCTAssertEqual(slice.startMinute, 480)
        XCTAssertEqual(slice.stepMinutes, 5)
        
        let q0 = slice.quantiles(slot: 0)
        XCTAssertEqual(q0.p10, 2.0, accuracy: 0.001)
        XCTAssertEqual(q0.p50, 4.0, accuracy: 0.001)
        XCTAssertEqual(q0.p90, 6.0, accuracy: 0.001)
        
        let q2 = slice.quantiles(slot: 2)
        XCTAssertEqual(q2.p10, 3.0, accuracy: 0.001)
        XCTAssertEqual(q2.p50, 5.0, accuracy: 0.001)
        XCTAssertEqual(q2.p90, 8.5, accuracy: 0.001)
    }

    // MARK: - JourneyItinerary Confidence Slice
    
    func testJourneyItineraryConfidenceSlice() {
        let itinerary = JourneyItinerary(
            profile: .mostReliable,
            departureTimeSec: 28800, // 8:00 AM
            arrivalTimeSec: 30600,   // 8:30 AM (30 min)
            p10ArrivalSec: 30480,    // 8:28 AM
            p50ArrivalSec: 30600,    // 8:30 AM
            p90ArrivalSec: 30840     // 8:34 AM
        )
        
        let slice = itinerary.confidenceSlice
        XCTAssertGreaterThanOrEqual(slice.slotCount, 10)
        XCTAssertEqual(slice.startMinute, 480)
        
        for slot in 0..<slice.slotCount {
            let q = slice.quantiles(slot: slot)
            XCTAssertLessThanOrEqual(q.p10, q.p50, "P10 <= P50 in journey slice at slot \(slot)")
            XCTAssertGreaterThanOrEqual(q.p90, q.p50, "P90 >= P50 in journey slice at slot \(slot)")
        }
    }
}
