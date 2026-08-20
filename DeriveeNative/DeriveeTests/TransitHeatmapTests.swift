import XCTest
import SwiftUI
@testable import Derivee

final class TransitHeatmapTests: XCTestCase {

    func testCividisColormapBinning() {
        // Critical: < 50%
        XCTAssertEqual(CividisColormap.color(for: 0.0, sampleCount: 10), CividisColormap.critical)
        XCTAssertEqual(CividisColormap.color(for: 49.9, sampleCount: 10), CividisColormap.critical)
        XCTAssertEqual(CividisColormap.qualityLabel(for: 45.0, sampleCount: 10), "Critical")
        
        // Poor: 50% ..< 65%
        XCTAssertEqual(CividisColormap.color(for: 50.0, sampleCount: 10), CividisColormap.poor)
        XCTAssertEqual(CividisColormap.color(for: 64.9, sampleCount: 10), CividisColormap.poor)
        XCTAssertEqual(CividisColormap.qualityLabel(for: 58.0, sampleCount: 10), "Poor")
        
        // Below Average: 65% ..< 75%
        XCTAssertEqual(CividisColormap.color(for: 65.0, sampleCount: 10), CividisColormap.belowAverage)
        XCTAssertEqual(CividisColormap.color(for: 74.9, sampleCount: 10), CividisColormap.belowAverage)
        XCTAssertEqual(CividisColormap.qualityLabel(for: 70.0, sampleCount: 10), "Below Average")
        
        // Acceptable: 75% ..< 85%
        XCTAssertEqual(CividisColormap.color(for: 75.0, sampleCount: 10), CividisColormap.acceptable)
        XCTAssertEqual(CividisColormap.color(for: 84.9, sampleCount: 10), CividisColormap.acceptable)
        XCTAssertEqual(CividisColormap.qualityLabel(for: 80.0, sampleCount: 10), "Acceptable")
        
        // Good: 85% ..< 95%
        XCTAssertEqual(CividisColormap.color(for: 85.0, sampleCount: 10), CividisColormap.good)
        XCTAssertEqual(CividisColormap.color(for: 94.9, sampleCount: 10), CividisColormap.good)
        XCTAssertEqual(CividisColormap.qualityLabel(for: 90.0, sampleCount: 10), "Good")
        
        // Excellent: 95% ... 100%
        XCTAssertEqual(CividisColormap.color(for: 95.0, sampleCount: 10), CividisColormap.excellent)
        XCTAssertEqual(CividisColormap.color(for: 100.0, sampleCount: 10), CividisColormap.excellent)
        XCTAssertEqual(CividisColormap.qualityLabel(for: 98.5, sampleCount: 10), "Excellent")
        
        // Unobserved: nil or sampleCount == 0
        XCTAssertEqual(CividisColormap.color(for: nil, sampleCount: 0), CividisColormap.unobserved)
        XCTAssertEqual(CividisColormap.color(for: 95.0, sampleCount: 0), CividisColormap.unobserved)
        XCTAssertEqual(CividisColormap.qualityLabel(for: nil, sampleCount: 0), "No Data")
    }

    func testDayOrderingOrderMondayFirst() {
        // Monday (1), Tuesday (2), Wednesday (3), Thursday (4), Friday (5), Saturday (6), Sunday (0)
        XCTAssertEqual(ReliabilityHeatmapCanvas.dayOrder, [1, 2, 3, 4, 5, 6, 0])
        XCTAssertEqual(ReliabilityHeatmapCanvas.dayLabels, ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"])
    }

    func testHourlyReliabilityRecordIdentifiable() {
        let record = SpatialDatabaseManager.HourlyReliabilityRecord(
            routeId: "L",
            stopId: "stop_bedford",
            directionId: 0,
            hourOfDay: 8,
            dayOfWeek: 1,
            medianDelaySec: 45,
            p90DelaySec: 180,
            medianHeadwaySec: 300,
            headwayStdDevSec: 60,
            ewtSeconds: 60.0,
            onTimePct: 92.5,
            sampleCount: 50
        )
        
        XCTAssertEqual(record.id, "L_stop_bedford_0_1_8")
        XCTAssertEqual(record.hourOfDay, 8)
        XCTAssertEqual(record.dayOfWeek, 1)
        XCTAssertEqual(record.onTimePct, 92.5)
    }

    func testStopEventRecordProperties() {
        let now = Date()
        let event = SpatialDatabaseManager.StopEventRecord(
            eventId: "EVT_100",
            tripId: "TRIP_L_1",
            routeId: "L",
            stopId: "stop_bedford",
            scheduledTime: now,
            actualTime: now.addingTimeInterval(45),
            delaySeconds: 45,
            observedAt: now.addingTimeInterval(50),
            directionId: 0
        )
        
        XCTAssertEqual(event.id, "EVT_100")
        XCTAssertEqual(event.delaySeconds, 45)
        XCTAssertEqual(event.directionId, 0)
    }
}
