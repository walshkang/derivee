import XCTest
import GRDB
@testable import Derivee

final class TransitReliabilityEngineTests: XCTestCase {
    var engine: TransitDatabaseEngine!
    
    override func setUp() async throws {
        try await super.setUp()
        engine = TransitDatabaseEngine.makeForTesting(inMemory: true)
    }
    
    override func tearDown() async throws {
        engine = nil
        try await super.tearDown()
    }
    
    // MARK: - 1. Service Disruptions Tests
    
    func testServiceDisruptionActiveFiltering() async throws {
        let baseEpoch: Int64 = 1700000000
        
        let d1 = ServiceDisruptionRecord(
            id: "disr_1",
            routeId: "L",
            stopId: "stop_bedford",
            directionId: 0,
            startEpoch: baseEpoch,
            endEpoch: baseEpoch + 3600,
            disruptionType: .delays,
            summaryText: "Track maintenance at Bedford Ave"
        )
        
        let d2 = ServiceDisruptionRecord(
            id: "disr_2",
            routeId: "7",
            stopId: nil,
            directionId: nil,
            startEpoch: baseEpoch + 7200,
            endEpoch: baseEpoch + 10800,
            disruptionType: .suspended,
            summaryText: "Line 7 suspended between Times Sq and Queensboro Plaza"
        )
        
        try await engine.insertServiceDisruptions([d1, d2])
        
        // Active at baseEpoch + 1800 -> only d1
        let active1 = try await engine.fetchActiveDisruptions(at: baseEpoch + 1800)
        XCTAssertEqual(active1.count, 1)
        XCTAssertEqual(active1.first?.id, "disr_1")
        XCTAssertEqual(active1.first?.disruptionType, .delays)
        
        // Active at baseEpoch + 5000 -> none
        let activeNone = try await engine.fetchActiveDisruptions(at: baseEpoch + 5000)
        XCTAssertTrue(activeNone.isEmpty)
        
        // Active at baseEpoch + 8000 -> only d2
        let active2 = try await engine.fetchActiveDisruptions(at: baseEpoch + 8000)
        XCTAssertEqual(active2.count, 1)
        XCTAssertEqual(active2.first?.id, "disr_2")
        XCTAssertEqual(active2.first?.disruptionType, .suspended)
    }
    
    func testDisruptionRouteAndStopQueries() async throws {
        let baseEpoch: Int64 = 1700000000
        
        let d1 = ServiceDisruptionRecord(
            id: "disr_l_bedford",
            routeId: "L",
            stopId: "stop_bedford",
            directionId: 0,
            startEpoch: baseEpoch,
            endEpoch: baseEpoch + 3600,
            disruptionType: .bypassLocal,
            summaryText: "Trains bypassing Bedford Ave"
        )
        
        let d2 = ServiceDisruptionRecord(
            id: "disr_l_lorimer",
            routeId: "L",
            stopId: "stop_lorimer",
            directionId: 1,
            startEpoch: baseEpoch,
            endEpoch: baseEpoch + 3600,
            disruptionType: .delays,
            summaryText: "Signal delays at Lorimer St"
        )
        
        try await engine.insertServiceDisruptions([d1, d2])
        
        let routeLDisruptions = try await engine.fetchDisruptions(for: "L", directionId: 0, at: baseEpoch + 1000)
        XCTAssertEqual(routeLDisruptions.count, 1)
        XCTAssertEqual(routeLDisruptions.first?.id, "disr_l_bedford")
        
        let stopLorimerDisruptions = try await engine.fetchDisruptions(for: "stop_lorimer", at: baseEpoch + 1000)
        XCTAssertEqual(stopLorimerDisruptions.count, 1)
        XCTAssertEqual(stopLorimerDisruptions.first?.id, "disr_l_lorimer")
    }
    
    func testDynamicDisruptionBitmask() async throws {
        let baseEpoch: Int64 = 1700000000
        
        let d1 = ServiceDisruptionRecord(
            id: "disr_stop_closed",
            routeId: "L",
            stopId: "stop_bedford",
            directionId: 0,
            startEpoch: baseEpoch,
            endEpoch: baseEpoch + 3600,
            disruptionType: .suspended,
            summaryText: "Bedford Ave closed"
        )
        
        let d2 = ServiceDisruptionRecord(
            id: "disr_line_closed",
            routeId: "F",
            stopId: nil,
            directionId: nil,
            startEpoch: baseEpoch,
            endEpoch: baseEpoch + 3600,
            disruptionType: .suspended,
            summaryText: "F line suspended"
        )
        
        try await engine.insertServiceDisruptions([d1, d2])
        
        let bitmask = try await engine.fetchDisruptionBitmask(at: baseEpoch + 1000)
        
        // Stop Bedford should be inactive, 1 Av should be active
        XCTAssertFalse(bitmask.isStopActive("stop_bedford"))
        XCTAssertTrue(bitmask.isStopActive("stop_1_av"))
        
        // Line F should be inactive, Line L active
        XCTAssertFalse(bitmask.isRouteActive("F"))
        XCTAssertTrue(bitmask.isRouteActive("L"))
        
        // Segment involving disrupted stop or route should be inactive
        XCTAssertFalse(bitmask.isRouteSegmentActive(routeId: "L", fromStop: "stop_1_av", toStop: "stop_bedford"))
        XCTAssertFalse(bitmask.isRouteSegmentActive(routeId: "F", fromStop: "stop_a", toStop: "stop_b"))
        XCTAssertTrue(bitmask.isRouteSegmentActive(routeId: "L", fromStop: "stop_1_av", toStop: "stop_3_av"))
    }
    
    // MARK: - 2. 15-Minute Origin Dispatch Slot Profiler Tests
    
    func testSlotIndexMath() {
        // Midnight (00:00:00) -> Slot 0
        XCTAssertEqual(TripSlotProfileRecord.slotIndex(secondsFromMidnight: 0), 0)
        
        // 00:14:59 -> Slot 0
        XCTAssertEqual(TripSlotProfileRecord.slotIndex(secondsFromMidnight: 14 * 60 + 59), 0)
        
        // 00:15:00 -> Slot 1
        XCTAssertEqual(TripSlotProfileRecord.slotIndex(secondsFromMidnight: 15 * 60), 1)
        
        // 08:30:00 -> (8 * 3600 + 30 * 60) / 900 = 30600 / 900 = 34
        XCTAssertEqual(TripSlotProfileRecord.slotIndex(secondsFromMidnight: 8 * 3600 + 30 * 60), 34)
        
        // 12:00:00 -> 43200 / 900 = 48
        XCTAssertEqual(TripSlotProfileRecord.slotIndex(secondsFromMidnight: 12 * 3600), 48)
        
        // 23:45:00 -> Slot 95
        XCTAssertEqual(TripSlotProfileRecord.slotIndex(secondsFromMidnight: 23 * 3600 + 45 * 60), 95)
        
        // 23:59:59 -> Slot 95
        XCTAssertEqual(TripSlotProfileRecord.slotIndex(secondsFromMidnight: 86399), 95)
        
        // Slot Range for Slot 34 -> 30600s to 31500s (8:30 to 8:45 AM)
        let range = TripSlotProfileRecord.slotRange(slotIndex: 34)
        XCTAssertEqual(range.startSec, 30600)
        XCTAssertEqual(range.endSec, 31500)
    }
    
    func testTripSlotProfileIngestionAndQuery() async throws {
        let profiles = [
            TripSlotProfileRecord(
                routeId: "6",
                directionId: 0,
                originSlotIndex: 34, // 8:30 - 8:45 AM
                stopId: "stop_pelham",
                dayType: 0, // Weekday
                medianDurationSec: 180,
                p90DurationSec: 240,
                regularityPct: 94.5,
                sampleCount: 120
            ),
            TripSlotProfileRecord(
                routeId: "6",
                directionId: 0,
                originSlotIndex: 34,
                stopId: "stop_125_st",
                dayType: 0,
                medianDurationSec: 720,
                p90DurationSec: 900,
                regularityPct: 91.0,
                sampleCount: 120
            ),
            TripSlotProfileRecord(
                routeId: "6",
                directionId: 0,
                originSlotIndex: 35, // 8:45 - 9:00 AM
                stopId: "stop_125_st",
                dayType: 0,
                medianDurationSec: 750,
                p90DurationSec: 930,
                regularityPct: 89.5,
                sampleCount: 115
            )
        ]
        
        try await engine.insertTripSlotProfiles(profiles)
        
        // Query specific slot point lookup
        let point = try await engine.fetchTripSlotProfile(
            routeId: "6",
            directionId: 0,
            stopId: "stop_125_st",
            slotIndex: 34,
            dayType: 0
        )
        XCTAssertNotNil(point)
        XCTAssertEqual(point?.medianDurationSec, 720)
        XCTAssertEqual(point?.p90DurationSec, 900)
        XCTAssertEqual(point?.regularityPct, 91.0)
        XCTAssertEqual(point?.sampleCount, 120)
        
        // Query all stops for route & slot 34
        let slotStops = try await engine.fetchTripSlotProfiles(
            routeId: "6",
            directionId: 0,
            slotIndex: 34,
            dayType: 0
        )
        XCTAssertEqual(slotStops.count, 2)
        XCTAssertEqual(slotStops[0].stopId, "stop_pelham")
        XCTAssertEqual(slotStops[1].stopId, "stop_125_st")
        
        // Query slot profile history for a stop
        let stopProfiles = try await engine.fetchSlotProfilesForStop(stopId: "stop_125_st", routeId: "6", dayType: 0)
        XCTAssertEqual(stopProfiles.count, 2)
        XCTAssertEqual(stopProfiles.map { $0.originSlotIndex }, [34, 35])
    }
    
    // MARK: - 3. Exact Mathematical Moment Aggregation Tests (SWT, AWT, EWT, OTP, Variance)
    
    func testMathematicalMomentDerivations() {
        // Construct a single hourly record:
        // Sched headways: uniform 300s (5 mins). N = 10.
        // sum_sched = 10 * 300 = 3000s
        // sum_sq_sched = 10 * (300^2) = 900,000
        // Expected SWT = sum_sq_sched / (2 * sum_sched) = 900000 / 6000 = 150.0s (2.5 mins)
        //
        // Actual headways with irregular bunching: [200, 400, 200, 400, 200, 400, 200, 400, 200, 400]
        // sum_actual = 3000s. sum_sq_actual = 5 * 40000 + 5 * 160000 = 200,000 + 800,000 = 1,000,000
        // Expected AWT = 1,000,000 / (2 * 3000) = 166.667s (~2.78 mins)
        // Expected EWT = max(0, AWT - SWT) = 166.667 - 150.0 = 16.667s
        //
        // Headway variance: (sum_sq_act / N) - (sum_act / N)^2 = (1000000 / 10) - (3000 / 10)^2 = 100000 - 90000 = 10,000
        // Headway stddev: sqrt(10000) = 100.0s
        //
        // OTP: 8 on-time, 1 early, 1 late. Total = 10. OTP = 80% (0.80)
        
        let record = HourlyReliabilityRecord(
            stopId: "stop_bedford",
            routeId: "L",
            directionId: 0,
            hourOfDay: 8,
            dayType: 0,
            sampleCount: 10,
            scheduledCount: 10,
            sumActualHeadway: 3000.0,
            sumSqActualHeadway: 1000000.0,
            sumSchedHeadway: 3000.0,
            sumSqSchedHeadway: 900000.0,
            onTimeCount: 8,
            earlyCount: 1,
            lateCount: 1,
            p10DeltaQ16: Int32(ReliabilityQuantizer.quantize(-30.0)),
            p50DeltaQ16: Int32(ReliabilityQuantizer.quantize(15.0)),
            p90DeltaQ16: Int32(ReliabilityQuantizer.quantize(120.0)),
            p10HeadwayQ16: Int32(ReliabilityQuantizer.quantize(200.0)),
            p50HeadwayQ16: Int32(ReliabilityQuantizer.quantize(300.0)),
            p90HeadwayQ16: Int32(ReliabilityQuantizer.quantize(400.0))
        )
        
        XCTAssertEqual(record.swt, 150.0, accuracy: 0.001)
        XCTAssertEqual(record.awt, 166.6666, accuracy: 0.001)
        XCTAssertEqual(record.ewt, 16.6666, accuracy: 0.001)
        XCTAssertEqual(record.otpRatio, 0.8, accuracy: 0.001)
        XCTAssertEqual(record.otpPct, 80.0, accuracy: 0.001)
        XCTAssertEqual(record.headwayVariance, 10000.0, accuracy: 0.001)
        XCTAssertEqual(record.headwayStdDev, 100.0, accuracy: 0.001)
        
        XCTAssertEqual(record.p10DeltaSec, -30.0, accuracy: 0.1)
        XCTAssertEqual(record.p50DeltaSec, 15.0, accuracy: 0.1)
        XCTAssertEqual(record.p90DeltaSec, 120.0, accuracy: 0.1)
    }
    
    // MARK: - 4. 168-Hour / Multi-Hour Rolling Window Aggregation Tests
    
    func testRollingWindowAlgebraicMomentAggregation() async throws {
        // Seed 3 hours of reliability records
        // Hour 7: 10 samples
        let r7 = HourlyReliabilityRecord(
            stopId: "stop_times_sq",
            routeId: "1",
            directionId: 0,
            hourOfDay: 7,
            dayType: 0,
            sampleCount: 10,
            scheduledCount: 10,
            sumActualHeadway: 3000.0,
            sumSqActualHeadway: 1000000.0,
            sumSchedHeadway: 3000.0,
            sumSqSchedHeadway: 900000.0,
            onTimeCount: 9,
            earlyCount: 0,
            lateCount: 1
        )
        
        // Hour 8: 12 samples
        let r8 = HourlyReliabilityRecord(
            stopId: "stop_times_sq",
            routeId: "1",
            directionId: 0,
            hourOfDay: 8,
            dayType: 0,
            sampleCount: 12,
            scheduledCount: 12,
            sumActualHeadway: 2880.0,
            sumSqActualHeadway: 750000.0,
            sumSchedHeadway: 2880.0,
            sumSqSchedHeadway: 691200.0,
            onTimeCount: 11,
            earlyCount: 0,
            lateCount: 1
        )
        
        // Hour 9: 10 samples
        let r9 = HourlyReliabilityRecord(
            stopId: "stop_times_sq",
            routeId: "1",
            directionId: 0,
            hourOfDay: 9,
            dayType: 0,
            sampleCount: 10,
            scheduledCount: 10,
            sumActualHeadway: 3000.0,
            sumSqActualHeadway: 950000.0,
            sumSchedHeadway: 3000.0,
            sumSqSchedHeadway: 900000.0,
            onTimeCount: 8,
            earlyCount: 1,
            lateCount: 1
        )
        
        try await engine.insertHourlyReliability([r7, r8, r9])
        
        // Multi-hour aggregation for Morning Rush (7 AM - 9 AM)
        let rushSummary = try await engine.aggregateReliability(
            stopId: "stop_times_sq",
            routeId: "1",
            directionId: 0,
            startHour: 7,
            endHour: 9,
            dayTypes: [0]
        )
        
        XCTAssertEqual(rushSummary.sampleCount, 32)
        XCTAssertEqual(rushSummary.scheduledCount, 32)
        XCTAssertEqual(rushSummary.sumActualHeadway, 3000.0 + 2880.0 + 3000.0, accuracy: 0.001)
        XCTAssertEqual(rushSummary.sumSqActualHeadway, 1000000.0 + 750000.0 + 950000.0, accuracy: 0.001)
        XCTAssertEqual(rushSummary.onTimeCount, 9 + 11 + 8)
        XCTAssertEqual(rushSummary.otpPct, (28.0 / 32.0) * 100.0, accuracy: 0.01)
        
        // SWT = (900000 + 691200 + 900000) / (2 * 8880) = 2491200 / 17760 = 140.27s
        XCTAssertEqual(rushSummary.swt, 2491200.0 / 17760.0, accuracy: 0.01)
        // AWT = (1000000 + 750000 + 950000) / (2 * 8880) = 2700000 / 17760 = 152.027s
        XCTAssertEqual(rushSummary.awt, 2700000.0 / 17760.0, accuracy: 0.01)
        // EWT = AWT - SWT = 152.027 - 140.270 = 11.756s
        XCTAssertEqual(rushSummary.ewt, (2700000.0 - 2491200.0) / 17760.0, accuracy: 0.01)
    }
    
    // MARK: - 5. 16-Bit Quantization & Dequantization Precision Tests
    
    func testQuantizationPrecision() {
        let testValues: [Double] = [
            -3200.0, -1800.5, -60.0, -0.1, 0.0, 0.1, 45.2, 120.0, 300.0, 1800.0, 3353.5
        ]
        
        for original in testValues {
            let q = ReliabilityQuantizer.quantize(original)
            let recovered = ReliabilityQuantizer.dequantize(Int32(q))
            XCTAssertEqual(recovered, original, accuracy: 0.1, "Quantization error for \(original) exceeded 0.1s tolerance")
        }
        
        // Test Clamping
        let belowMin = ReliabilityQuantizer.quantize(-5000.0)
        XCTAssertEqual(belowMin, 0)
        
        let aboveMax = ReliabilityQuantizer.quantize(5000.0)
        XCTAssertEqual(aboveMax, 65535)
    }
    
    // MARK: - 6. 120Hz Canvas Buffer Container Population & Offset Strides
    
    func testCanvasReliabilityBufferPopulation() async throws {
        let container = CanvasReliabilityBufferContainer()
        XCTAssertEqual(container.toArray().count, 4320)
        
        let r = HourlyReliabilityRecord(
            stopId: "stop_union_sq",
            routeId: "N",
            directionId: 1,
            hourOfDay: 14,
            dayType: 1, // Saturday
            sampleCount: 20,
            scheduledCount: 20,
            sumActualHeadway: 6000.0,
            sumSqActualHeadway: 1900000.0,
            sumSchedHeadway: 6000.0,
            sumSqSchedHeadway: 1800000.0,
            onTimeCount: 18,
            earlyCount: 1,
            lateCount: 1,
            p10DeltaQ16: Int32(ReliabilityQuantizer.quantize(-20.0)),
            p50DeltaQ16: Int32(ReliabilityQuantizer.quantize(10.0)),
            p90DeltaQ16: Int32(ReliabilityQuantizer.quantize(90.0)),
            p10HeadwayQ16: Int32(ReliabilityQuantizer.quantize(240.0)),
            p50HeadwayQ16: Int32(ReliabilityQuantizer.quantize(300.0)),
            p90HeadwayQ16: Int32(ReliabilityQuantizer.quantize(380.0))
        )
        
        try await engine.insertHourlyReliability([r])
        try await engine.populateReliabilityBuffer(stopId: "stop_union_sq", routeId: "N", container: container)
        
        let bufferArray = container.toArray()
        let expectedBaseOffset = CanvasReliabilityBufferContainer.calculateOffset(
            hour: 14,
            dayType: 1,
            direction: 1,
            metricIndex: 0
        )
        
        // Offset = 14 * 180 + 1 * 60 + 1 * 30 + 0 = 2520 + 60 + 30 = 2610
        XCTAssertEqual(expectedBaseOffset, 2610)
        
        // Metric 0: EWT
        XCTAssertEqual(bufferArray[expectedBaseOffset + 0], Float(r.ewt), accuracy: 0.001)
        // Metric 1: OTP ratio
        XCTAssertEqual(bufferArray[expectedBaseOffset + 1], Float(r.otpRatio), accuracy: 0.001)
        // Metric 2: AWT
        XCTAssertEqual(bufferArray[expectedBaseOffset + 2], Float(r.awt), accuracy: 0.001)
        // Metric 3: SWT
        XCTAssertEqual(bufferArray[expectedBaseOffset + 3], Float(r.swt), accuracy: 0.001)
        // Metric 4: Headway Variance
        XCTAssertEqual(bufferArray[expectedBaseOffset + 4], Float(r.headwayVariance), accuracy: 0.001)
        // Metric 5: P10 Delta (-20.0)
        XCTAssertEqual(bufferArray[expectedBaseOffset + 5], -20.0, accuracy: 0.1)
        // Metric 6: P50 Delta (10.0)
        XCTAssertEqual(bufferArray[expectedBaseOffset + 6], 10.0, accuracy: 0.1)
        // Metric 7: P90 Delta (90.0)
        XCTAssertEqual(bufferArray[expectedBaseOffset + 7], 90.0, accuracy: 0.1)
    }
}
