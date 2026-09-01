import XCTest
import SwiftUI
@testable import Derivee

final class DepartureMatrixCanvasTests: XCTestCase {

    func testBufferElementCountAndInitialization() {
        let emptyBuf = DepartureMatrixBuffer.empty()
        XCTAssertEqual(emptyBuf.values.count, 4320, "DepartureMatrixBuffer must contain exactly 4,320 Float32 elements (17.28 KB).")
        XCTAssertEqual(DepartureMatrixBuffer.hours, 24)
        XCTAssertEqual(DepartureMatrixBuffer.minutesPerHour, 60)
        XCTAssertEqual(DepartureMatrixBuffer.totalMinutes, 1440)
        XCTAssertEqual(DepartureMatrixBuffer.channels, 3)
    }

    func testStrideOffsetFormula() {
        // Offset(h, m, p) = (h * 60 + m) * 3 + p
        XCTAssertEqual(DepartureMatrixBuffer.offset(hour: 0, minute: 0, channel: 0), 0)
        XCTAssertEqual(DepartureMatrixBuffer.offset(hour: 0, minute: 0, channel: 1), 1)
        XCTAssertEqual(DepartureMatrixBuffer.offset(hour: 0, minute: 0, channel: 2), 2)
        XCTAssertEqual(DepartureMatrixBuffer.offset(hour: 0, minute: 1, channel: 0), 3)
        XCTAssertEqual(DepartureMatrixBuffer.offset(hour: 1, minute: 0, channel: 0), 180)
        XCTAssertEqual(DepartureMatrixBuffer.offset(hour: 23, minute: 59, channel: 2), 4319)
    }

    func testQuantilesAndVarianceDisutility() {
        var buf = DepartureMatrixBuffer.empty()
        buf[8, 15, DepartureMatrixBuffer.p10Channel] = 2.5
        buf[8, 15, DepartureMatrixBuffer.p50Channel] = 6.0
        buf[8, 15, DepartureMatrixBuffer.p90Channel] = 11.5
        
        let q = buf.quantiles(hour: 8, minute: 15)
        XCTAssertEqual(q.p10, 2.5, accuracy: 0.001)
        XCTAssertEqual(q.p50, 6.0, accuracy: 0.001)
        XCTAssertEqual(q.p90, 11.5, accuracy: 0.001)
        
        let disutility = buf.varianceDisutility(hour: 8, minute: 15)
        XCTAssertEqual(disutility, 9.0, accuracy: 0.001)
    }

    func testCircularDensitySmootherMidnightContinuity() {
        var rawImpulses = [Float](repeating: 0.0, count: 1440)
        // Set impulses right at midnight edge
        rawImpulses[1439] = 1.0 // 23:59
        rawImpulses[0] = 1.0    // 00:00
        rawImpulses[1] = 1.0    // 00:01
        
        let smoothed = CircularDensitySmoother.convolveCircular(
            sparseSignal: rawImpulses,
            kernelRadius: 10,
            kappa: 300.0
        )
        
        XCTAssertEqual(smoothed.count, 1440)
        
        // Density at slot 0 (00:00) and slot 1439 (23:59) should be symmetric and continuous
        let diff = abs(smoothed[0] - smoothed[1439])
        XCTAssertLessThan(diff, 0.05, "Circular convolution must preserve midnight continuity across 23:59 -> 00:00.")
        XCTAssertGreaterThan(smoothed[0], 0.01, "Impulse energy should smoothly wrap across midnight.")
    }

    func testBufferFromScheduleRecords() {
        let sampleSchedule: [SpatialDatabaseManager.HourScheduleRecord] = [
            SpatialDatabaseManager.HourScheduleRecord(
                hourOfDay: 8,
                departures: [
                    SpatialDatabaseManager.DeparturePillRecord(id: "p1", tripId: "t1", routeId: "L", destination: "8 Av", minute: 2, isLive: false),
                    SpatialDatabaseManager.DeparturePillRecord(id: "p2", tripId: "t2", routeId: "L", destination: "8 Av", minute: 8, isLive: false),
                    SpatialDatabaseManager.DeparturePillRecord(id: "p3", tripId: "t3", routeId: "L", destination: "8 Av", minute: 14, isLive: false),
                    SpatialDatabaseManager.DeparturePillRecord(id: "p4", tripId: "t4", routeId: "L", destination: "8 Av", minute: 20, isLive: false)
                ]
            )
        ]
        
        let buf = DepartureMatrixBuffer.fromScheduleRecords(sampleSchedule, defaultHeadway: 6.0)
        XCTAssertEqual(buf.values.count, 4320)
        
        let q = buf.quantiles(hour: 8, minute: 10)
        XCTAssertGreaterThan(q.p50, 0.0)
        XCTAssertLessThanOrEqual(q.p10, q.p50)
        XCTAssertGreaterThanOrEqual(q.p90, q.p50)
    }

    func testBufferFromHourlyReliability() {
        var records: [SpatialDatabaseManager.HourlyReliabilityRecord] = []
        for h in 0..<24 {
            records.append(
                SpatialDatabaseManager.HourlyReliabilityRecord(
                    routeId: "L",
                    stopId: "stop_bedford",
                    directionId: 0,
                    hourOfDay: h,
                    dayOfWeek: 1,
                    medianDelaySec: 45,
                    p90DelaySec: 180,
                    medianHeadwaySec: 360,
                    headwayStdDevSec: 60,
                    ewtSeconds: 40.0,
                    onTimePct: 88.0,
                    sampleCount: 50
                )
            )
        }
        
        let buf = DepartureMatrixBuffer.fromHourlyReliability(records)
        XCTAssertEqual(buf.values.count, 4320)
        
        for h in 0..<24 {
            let q = buf.quantiles(hour: h, minute: 30)
            XCTAssertLessThanOrEqual(q.p10, q.p50, "P10 must be <= P50 for all hours.")
            XCTAssertGreaterThanOrEqual(q.p90, q.p50, "P90 must be >= P50 for all hours.")
        }
    }

    func testSyntheticFixtureOrderInvariants() {
        let buf = DepartureMatrixBuffer.syntheticFixture(lowVariance: false)
        XCTAssertEqual(buf.values.count, 4320)
        
        for minOfDay in 0..<1440 {
            let q = buf.quantiles(minuteOfDay: minOfDay)
            XCTAssertFalse(q.p10.isNaN)
            XCTAssertFalse(q.p50.isNaN)
            XCTAssertFalse(q.p90.isNaN)
            XCTAssertLessThanOrEqual(q.p10, q.p50, "P10 <= P50 quantile invariant violated at min \(minOfDay)")
            XCTAssertGreaterThanOrEqual(q.p90, q.p50, "P90 >= P50 quantile invariant violated at min \(minOfDay)")
        }
    }

    func testColorMappingCalculation() {
        let lowVarColor = DepartureMatrixCanvas.colorForQuantiles(normWait: 0.2, normVar: 0.1)
        let highVarColor = DepartureMatrixCanvas.colorForQuantiles(normWait: 0.8, normVar: 0.9)
        
        XCTAssertNotNil(lowVarColor)
        XCTAssertNotNil(highVarColor)
    }
}
