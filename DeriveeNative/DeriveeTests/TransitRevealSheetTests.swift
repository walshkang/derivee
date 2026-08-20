import XCTest
import GRDB
import SwiftUI
import SnapshotTesting
@testable import Derivee

final class TransitRevealSheetTests: XCTestCase {

    private var tempDirectoryURL: URL!
    private var mockTransitURL: URL!
    private var dbManager: SpatialDatabaseManager!

    override func setUpWithError() throws {
        try super.setUpWithError()
        
        // ARCHITECT GUARDRAIL 4: Create temp directory and seed mock transit database
        tempDirectoryURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectoryURL, withIntermediateDirectories: true)
        
        mockTransitURL = tempDirectoryURL.appendingPathComponent("transit_delta.sqlite")
        
        let mockDB = try DatabaseQueue(path: mockTransitURL.path)
        try mockDB.write { db in
            try db.execute(sql: """
                CREATE TABLE stops (
                    stop_id TEXT PRIMARY KEY,
                    stop_name TEXT NOT NULL,
                    stop_lat REAL NOT NULL,
                    stop_lon REAL NOT NULL,
                    route_type INTEGER NOT NULL DEFAULT 1,
                    location_type INTEGER NOT NULL DEFAULT 0,
                    routes TEXT NOT NULL DEFAULT ''
                );
                INSERT INTO stops VALUES ('stop_bedford', 'Bedford Ave Station', 40.7180, -73.9575, 1, 1, 'L');
                INSERT INTO stops VALUES ('stop_lorimer', 'Lorimer St Station', 40.7140, -73.9500, 1, 1, 'L,G');
                
                CREATE TABLE headway_history (
                    stop_id TEXT NOT NULL,
                    day_offset INTEGER NOT NULL,
                    headway_min REAL NOT NULL,
                    PRIMARY KEY (stop_id, day_offset)
                );
                INSERT INTO headway_history VALUES ('stop_bedford', 0, 4.2);
                INSERT INTO headway_history VALUES ('stop_bedford', 1, 4.5);
                INSERT INTO headway_history VALUES ('stop_bedford', 2, 4.0);
                INSERT INTO headway_history VALUES ('stop_bedford', 3, 5.8);
                INSERT INTO headway_history VALUES ('stop_bedford', 4, 4.3);
                INSERT INTO headway_history VALUES ('stop_bedford', 5, 4.6);
                INSERT INTO headway_history VALUES ('stop_bedford', 6, 4.1);
                
                CREATE TABLE stop_reliability_hourly (
                    route_id TEXT NOT NULL,
                    stop_id TEXT NOT NULL,
                    direction_id INTEGER NOT NULL DEFAULT 0,
                    hour_of_day INTEGER NOT NULL,
                    day_of_week INTEGER NOT NULL,
                    median_delay_sec INTEGER NOT NULL,
                    p90_delay_sec INTEGER NOT NULL,
                    median_headway_sec INTEGER NOT NULL DEFAULT 0,
                    headway_stddev_sec INTEGER NOT NULL DEFAULT 0,
                    ewt_seconds REAL NOT NULL,
                    on_time_pct REAL NOT NULL,
                    sample_count INTEGER NOT NULL,
                    PRIMARY KEY (route_id, stop_id, hour_of_day, day_of_week)
                );
                CREATE INDEX idx_stop_rel ON stop_reliability_hourly (stop_id, route_id);
                
                CREATE TABLE stop_events (
                    event_id TEXT PRIMARY KEY,
                    trip_id TEXT NOT NULL,
                    route_id TEXT NOT NULL,
                    stop_id TEXT NOT NULL,
                    scheduled_time INTEGER,
                    actual_time INTEGER NOT NULL,
                    delay_seconds INTEGER NOT NULL,
                    observed_at INTEGER NOT NULL,
                    direction_id INTEGER NOT NULL DEFAULT 0
                );
                
                CREATE TABLE scheduled_stops (
                    stop_id TEXT NOT NULL,
                    trip_id TEXT NOT NULL,
                    route_id TEXT NOT NULL,
                    departure_time TEXT NOT NULL,
                    headsign TEXT NOT NULL,
                    direction_id INTEGER NOT NULL DEFAULT 0,
                    PRIMARY KEY (stop_id, trip_id, departure_time)
                );
            """)
            
            // Seed all 168 cells (7 days x 24 hours) for stop_bedford
            for dow in 0..<7 {
                for hour in 0..<24 {
                    let otp = 70.0 + Double((dow * 7 + hour * 3) % 29)
                    try db.execute(sql: """
                        INSERT INTO stop_reliability_hourly 
                        VALUES ('L', 'stop_bedford', 0, ?, ?, 75, 240, 300, 60, 65.0, ?, 45);
                    """, arguments: [hour, dow, otp])
                }
            }
            
            // Seed sample stop events
            for i in 0..<10 {
                try db.execute(sql: """
                    INSERT INTO stop_events 
                    VALUES ('EVT_\(i)', 'TRIP_L_\(i)', 'L', 'stop_bedford', 1736337600 + \(i * 300), 1736337600 + \(i * 300 + 45), 45, 1736337600 + \(i * 300 + 50), 0);
                """)
            }
            
            // Seed sample scheduled stops
            for h in 0..<24 {
                for m in [5, 15, 25, 35, 45, 55] {
                    let timeStr = String(format: "2025-01-08 %02d:%02d:00", h, m)
                    try db.execute(sql: """
                        INSERT INTO scheduled_stops
                        VALUES ('stop_bedford', 'TRIP_SCHED_\(h)_\(m)', 'L', ?, 'Manhattan - 8th Ave', 0);
                    """, arguments: [timeStr])
                }
            }
        }
        
        // Initialize SpatialDatabaseManager with attached transit DB
        dbManager = SpatialDatabaseManager.makeForTesting(inMemory: true, customTransitURL: mockTransitURL)
    }

    override func tearDownWithError() throws {
        dbManager = nil
        if let tempURL = tempDirectoryURL {
            try? FileManager.default.removeItem(at: tempURL)
        }
        try super.tearDownWithError()
    }

    func testHeadwayDataQueryPerformanceUnder12ms() async throws {
        _ = try await dbManager.fetchHeadwayData(for: "stop_bedford")
        let startTime = CFAbsoluteTimeGetCurrent()
        let headways = try await dbManager.fetchHeadwayData(for: "stop_bedford")
        let durationMs = (CFAbsoluteTimeGetCurrent() - startTime) * 1000.0
        
        XCTAssertEqual(headways.count, 7, "Headway query should return 7 historical data points.")
        XCTAssertLessThan(durationMs, 12.0, "Historical headway database query must complete in < 12ms (Actual: \(durationMs)ms).")
    }

    func testStopDetailsQueryPerformanceUnder12ms() async throws {
        _ = try await dbManager.fetchStopDetails(for: "stop_bedford")
        let startTime = CFAbsoluteTimeGetCurrent()
        let details = try await dbManager.fetchStopDetails(for: "stop_bedford")
        let durationMs = (CFAbsoluteTimeGetCurrent() - startTime) * 1000.0
        
        XCTAssertEqual(details.name, "Bedford Ave Station")
        XCTAssertLessThan(durationMs, 12.0, "Stop details database query must complete in < 12ms (Actual: \(durationMs)ms).")
    }
    
    func testHourlyReliabilityQueryPerformanceUnder12ms() async throws {
        _ = try await dbManager.fetchHourlyReliability(for: "stop_bedford", routeId: "L")
        let startTime = CFAbsoluteTimeGetCurrent()
        let records = try await dbManager.fetchHourlyReliability(for: "stop_bedford", routeId: "L")
        let durationMs = (CFAbsoluteTimeGetCurrent() - startTime) * 1000.0
        
        XCTAssertEqual(records.count, 168, "Hourly reliability matrix must contain 168 cells.")
        XCTAssertLessThan(durationMs, 12.0, "Hourly reliability query must complete in < 12ms (Actual: \(durationMs)ms).")
    }
    
    func testStopEventsQueryPerformanceUnder12ms() async throws {
        _ = try await dbManager.fetchStopEvents(for: "stop_bedford", hourOfDay: 8, dayOfWeek: 3)
        let startTime = CFAbsoluteTimeGetCurrent()
        let events = try await dbManager.fetchStopEvents(for: "stop_bedford", hourOfDay: 8, dayOfWeek: 3)
        let durationMs = (CFAbsoluteTimeGetCurrent() - startTime) * 1000.0
        
        XCTAssertFalse(events.isEmpty, "Stop events query should return records.")
        XCTAssertLessThan(durationMs, 12.0, "Stop events query must complete in < 12ms (Actual: \(durationMs)ms).")
    }

    func testTransitSparklineViewSnapshot() throws {
        // Pinned referenceDate (Wednesday Jan 8, 2025 12:00:00 UTC) to ensure deterministic snapshots across CI runs
        let fixedDate = Date(timeIntervalSince1970: 1736337600)
        let view = TransitSparklineView(
            headways: [4.2, 4.5, 4.0, 5.8, 4.3, 4.6, 4.1],
            title: "7-Day Headway Reliability (min)",
            referenceDate: fixedDate
        )
        .frame(width: 320, height: 100)

        let vc = UIHostingController(rootView: view)
        assertSnapshot(of: vc, as: .image(on: ViewImageConfig(size: CGSize(width: 320, height: 100))))
    }
    
    func testReliabilityHeatmapCanvasSnapshot() throws {
        var sampleRecords: [SpatialDatabaseManager.HourlyReliabilityRecord] = []
        for dow in 0..<7 {
            for hour in 0..<24 {
                let otp: Double = 60.0 + Double((dow * 7 + hour * 3) % 38)
                let rec = SpatialDatabaseManager.HourlyReliabilityRecord(
                    routeId: "L",
                    stopId: "stop_bedford",
                    directionId: 0,
                    hourOfDay: hour,
                    dayOfWeek: dow,
                    medianDelaySec: 75,
                    p90DelaySec: 240,
                    medianHeadwaySec: 300,
                    headwayStdDevSec: 60,
                    ewtSeconds: 65.0,
                    onTimePct: otp,
                    sampleCount: 45
                )
                sampleRecords.append(rec)
            }
        }
        
        let view = ReliabilityHeatmapCanvas(records: sampleRecords)
            .frame(width: 360, height: 200)
        
        let vc = UIHostingController(rootView: view)
        assertSnapshot(of: vc, as: .image(on: ViewImageConfig(size: CGSize(width: 360, height: 200))))
    }
    
    func testTransitMatrixInspectorViewSnapshot() throws {
        let record = SpatialDatabaseManager.HourlyReliabilityRecord(
            routeId: "L",
            stopId: "stop_bedford",
            directionId: 0,
            hourOfDay: 8,
            dayOfWeek: 3,
            medianDelaySec: 84,
            p90DelaySec: 288,
            medianHeadwaySec: 270,
            headwayStdDevSec: 68,
            ewtSeconds: 72.0,
            onTimePct: 84.2,
            sampleCount: 48
        )
        
        let view = TransitMatrixInspectorView(record: record)
            .frame(width: 375, height: 600)
        
        let vc = UIHostingController(rootView: view)
        assertSnapshot(of: vc, as: .image(on: ViewImageConfig(size: CGSize(width: 375, height: 600))))
    }
    
    func testTimetableQueryPerformanceUnder12ms() async throws {
        _ = try await dbManager.fetchTimetable(for: "stop_bedford", routeId: "L", directionId: 0)
        let startTime = CFAbsoluteTimeGetCurrent()
        let schedule = try await dbManager.fetchTimetable(for: "stop_bedford", routeId: "L", directionId: 0)
        let durationMs = (CFAbsoluteTimeGetCurrent() - startTime) * 1000.0
        
        XCTAssertEqual(schedule.count, 24, "Timetable query should return all 24 hours.")
        let totalPills = schedule.reduce(0) { $0 + $1.departures.count }
        XCTAssertGreaterThan(totalPills, 0, "Timetable should contain departures.")
        XCTAssertLessThan(durationMs, 12.0, "Timetable database query must complete in < 12ms (Actual: \(durationMs)ms).")
    }
    
    func testTimetableFallbackQueryPerformanceUnder20ms() async throws {
        _ = try await dbManager.fetchTimetable(for: "stop_unknown", routeId: "7", directionId: 0)
        let startTime = CFAbsoluteTimeGetCurrent()
        let schedule = try await dbManager.fetchTimetable(for: "stop_unknown", routeId: "7", directionId: 0)
        let durationMs = (CFAbsoluteTimeGetCurrent() - startTime) * 1000.0
        
        XCTAssertEqual(schedule.count, 24, "Fallback timetable should generate all 24 hours.")
        let totalPills = schedule.reduce(0) { $0 + $1.departures.count }
        XCTAssertGreaterThan(totalPills, 100, "Fallback timetable should generate full day of departures.")
        XCTAssertLessThan(durationMs, 20.0, "Fallback timetable generation must complete in < 20ms (Actual: \(durationMs)ms).")
    }
    
    func testDirectionalArrivalGrouping() async throws {
        let details = try await dbManager.fetchStopDetails(for: "stop_bedford")
        XCTAssertFalse(details.arrivals.isEmpty, "Arrivals should be generated for stop_bedford.")
        
        let sheet = TransitRevealSheet(stopId: "stop_bedford", initialDetails: details)
        let groups = sheet.groupedArrivals
        
        // Assert that arrivals are partitioned by direction
        XCTAssertFalse(groups.isEmpty, "Grouped arrivals should not be empty.")
        let directionNames = groups.map { $0.directionName }
        XCTAssertTrue(directionNames.contains(where: { $0.contains("Manhattan") || $0.contains("Northbound") || $0.contains("Uptown") }))
        XCTAssertTrue(directionNames.contains(where: { $0.contains("Brooklyn") || $0.contains("Southbound") || $0.contains("Downtown") }))
        
        // Assert chronological ordering within each direction group
        for group in groups {
            for i in 0..<(group.arrivals.count - 1) {
                XCTAssertLessThanOrEqual(group.arrivals[i].minutes, group.arrivals[i + 1].minutes, "Arrivals within each direction group must be sorted by minutes ascending.")
            }
        }
    }

    func testTransitRevealSheetDirectionalSnapshot() throws {
        let mockDetails = SpatialDatabaseManager.StopDetails(
            stopId: "stop_bedford",
            name: "Bedford Ave",
            routeId: "L",
            routeType: 1,
            arrivals: [
                SpatialDatabaseManager.ArrivalInfo(line: "L", destination: "8th Ave", minutes: 2, direction: "Manhattan-bound", distanceDescription: "Approaching"),
                SpatialDatabaseManager.ArrivalInfo(line: "L", destination: "Canarsie - Rockaway Pkwy", minutes: 4, direction: "Brooklyn-bound", distanceDescription: "1 stop away"),
                SpatialDatabaseManager.ArrivalInfo(line: "L", destination: "8th Ave", minutes: 8, direction: "Manhattan-bound", distanceDescription: "3 stops away"),
                SpatialDatabaseManager.ArrivalInfo(line: "L", destination: "Lorimer St (Short Turn)", minutes: 12, direction: "Brooklyn-bound", distanceDescription: "5 stops away")
            ]
        )
        
        let mockAlerts = [
            TransitAlert(id: "L_1", routeId: "L", headerText: "Planned Work: Late night single-tracking between 8th Ave and Bedford Ave.")
        ]
        
        let view = TransitRevealSheet(
            stopId: "stop_bedford",
            initialDetails: mockDetails,
            initialLiveArrivals: mockDetails.arrivals,
            initialAlerts: mockAlerts
        )
        .frame(width: 375, height: 600)
        
        let vc = UIHostingController(rootView: view)
        assertSnapshot(of: vc, as: .image(on: ViewImageConfig(size: CGSize(width: 375, height: 600))))
    }

    func testDepartureMatrixViewSnapshot() throws {
        let sampleDepartures = [
            SpatialDatabaseManager.DeparturePillRecord(id: "1", tripId: "T1", routeId: "L", destination: "8th Ave", minute: 4, isExpress: false, isFirstDeparture: true),
            SpatialDatabaseManager.DeparturePillRecord(id: "2", tripId: "T2", routeId: "L", destination: "8th Ave", minute: 12, isExpress: false, liveDeltaMinutes: 3, isLive: true),
            SpatialDatabaseManager.DeparturePillRecord(id: "3", tripId: "T3", routeId: "L", destination: "8th Ave", minute: 19, isExpress: true),
            SpatialDatabaseManager.DeparturePillRecord(id: "4", tripId: "T4", routeId: "L", destination: "8th Ave", minute: 26, isExpress: false, delaySeconds: 240),
            SpatialDatabaseManager.DeparturePillRecord(id: "5", tripId: "T5", routeId: "L", destination: "8th Ave", minute: 34, isExpress: false),
            SpatialDatabaseManager.DeparturePillRecord(id: "6", tripId: "T6", routeId: "L", destination: "8th Ave", minute: 42, isExpress: true),
            SpatialDatabaseManager.DeparturePillRecord(id: "7", tripId: "T7", routeId: "L", destination: "8th Ave", minute: 51, isExpress: false, isLastDeparture: true)
        ]
        
        let sampleHours = (0..<24).map { h in
            SpatialDatabaseManager.HourScheduleRecord(hourOfDay: h, departures: sampleDepartures)
        }
        
        let view = DepartureMatrixView(
            records: sampleHours,
            routeId: "L",
            stopId: "stop_bedford",
            liveArrivals: [
                SpatialDatabaseManager.ArrivalInfo(line: "L", destination: "8th Ave", minutes: 3, direction: "Manhattan-bound")
            ]
        )
        .frame(width: 375, height: 620)
        
        let vc = UIHostingController(rootView: view)
        assertSnapshot(of: vc, as: .image(on: ViewImageConfig(size: CGSize(width: 375, height: 620))))
    }
}
