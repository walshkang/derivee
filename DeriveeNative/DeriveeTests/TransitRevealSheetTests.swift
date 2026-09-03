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
                
                CREATE TABLE scheduled_hourly_patterns (
                    stop_id TEXT NOT NULL,
                    route_id TEXT NOT NULL,
                    direction_id INTEGER NOT NULL,
                    hour_of_day INTEGER NOT NULL,
                    service_mask INTEGER NOT NULL,
                    baseline_days_of_week INTEGER NOT NULL,
                    minute_offsets TEXT NOT NULL,
                    headsign TEXT NOT NULL,
                    PRIMARY KEY (stop_id, route_id, direction_id, hour_of_day, service_mask)
                );
                CREATE INDEX idx_patterns_lookup ON scheduled_hourly_patterns(stop_id, route_id, direction_id);
                INSERT INTO scheduled_hourly_patterns VALUES ('stop_pattern_test', 'Red', 0, 8, 384, 127, '04,16,28,40,52', 'Alewife');
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
            
            // Seed single-direction terminal stop (Direction 1 only)
            try db.execute(sql: """
                INSERT INTO scheduled_stops
                VALUES ('stop_terminal_dir1', 'TRIP_DIR1_1', 'L', '2025-01-08 08:00:00', 'Brooklyn - Canarsie', 1);
            """)
            
            // Seed bidirectional stop (Direction 0 and 1)
            try db.execute(sql: """
                INSERT INTO scheduled_stops
                VALUES ('stop_bidirectional', 'TRIP_BI_0', 'L', '2025-01-08 08:00:00', 'Manhattan - 8th Ave', 0),
                       ('stop_bidirectional', 'TRIP_BI_1', 'L', '2025-01-08 08:05:00', 'Brooklyn - Canarsie', 1);
            """)
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
        for _ in 0..<2 {
            _ = try await dbManager.fetchHourlyReliability(for: "stop_bedford", routeId: "L")
        }
        let startTime = CFAbsoluteTimeGetCurrent()
        let records = try await dbManager.fetchHourlyReliability(for: "stop_bedford", routeId: "L")
        let durationMs = (CFAbsoluteTimeGetCurrent() - startTime) * 1000.0
        
        XCTAssertEqual(records.count, 168, "Hourly reliability matrix must contain 168 cells.")
        XCTAssertLessThan(durationMs, 12.0, "Hourly reliability query must complete in < 12ms (Actual: \(durationMs)ms).")
    }
    
    func testStopEventsQueryPerformanceUnder12ms() async throws {
        for _ in 0..<2 {
            _ = try await dbManager.fetchStopEvents(for: "stop_bedford", hourOfDay: 8, dayOfWeek: 3)
        }
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
        assertSnapshot(of: vc, as: .image(on: ViewImageConfig(size: CGSize(width: 320, height: 100)), precision: 0.98))
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
        
        let view = ReliabilityHeatmapCanvas(
            records: sampleRecords,
            initialDay: 3,
            initialHour: 8
        )
        .frame(width: 360, height: 250)
        
        let vc = UIHostingController(rootView: view)
        assertSnapshot(of: vc, as: .image(on: ViewImageConfig(size: CGSize(width: 360, height: 250)), precision: 0.98))
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
        assertSnapshot(of: vc, as: .image(on: ViewImageConfig(size: CGSize(width: 375, height: 600)), precision: 0.98))
    }
    
    func testTimetableQueryPerformanceUnder12ms() async throws {
        for _ in 0..<3 {
            _ = try await dbManager.fetchTimetable(for: "stop_bedford", routeId: "L", directionId: 0)
        }
        let startTime = CFAbsoluteTimeGetCurrent()
        let schedule = try await dbManager.fetchTimetable(for: "stop_bedford", routeId: "L", directionId: 0)
        let durationMs = (CFAbsoluteTimeGetCurrent() - startTime) * 1000.0
        
        XCTAssertEqual(schedule.count, 24, "Timetable query should return all 24 hours.")
        let totalPills = schedule.reduce(0) { $0 + $1.departures.count }
        XCTAssertGreaterThan(totalPills, 0, "Timetable should contain departures.")
        XCTAssertLessThan(durationMs, 15.0, "Timetable database query must complete in < 15ms (Actual: \(durationMs)ms).")
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

    func testStopDetailsMultiRouteParsing() async throws {
        let details = try await dbManager.fetchStopDetails(for: "stop_lorimer")
        XCTAssertEqual(details.name, "Lorimer St Station")
        XCTAssertEqual(details.routeId, "L")
        XCTAssertEqual(details.routeIds, ["L", "G"], "Multi-route stations must parse all comma-separated routes into routeIds array.")
    }
    
    func testMultiRouteFeedMessageParsing() throws {
        var feedMessage = TransitRealtime_FeedMessage()
        var header = TransitRealtime_FeedHeader()
        header.gtfsRealtimeVersion = "2.0"
        header.timestamp = 1736337600
        feedMessage.header = header
        
        // Trip 1: Route N
        var entity1 = TransitRealtime_FeedEntity()
        entity1.id = "TRIP_N_1"
        var tripUpdate1 = TransitRealtime_TripUpdate()
        var trip1 = TransitRealtime_TripDescriptor()
        trip1.tripID = "TRIP_N"
        trip1.routeID = "N"
        tripUpdate1.trip = trip1
        var stu1 = TransitRealtime_TripUpdate.StopTimeUpdate()
        stu1.stopID = "stop_times_sq"
        var arr1 = TransitRealtime_TripUpdate.StopTimeEvent()
        arr1.time = 1736337600 + 180 // 3 min
        stu1.arrival = arr1
        tripUpdate1.stopTimeUpdate = [stu1]
        entity1.tripUpdate = tripUpdate1
        
        // Trip 2: Route W (sibling)
        var entity2 = TransitRealtime_FeedEntity()
        entity2.id = "TRIP_W_1"
        var tripUpdate2 = TransitRealtime_TripUpdate()
        var trip2 = TransitRealtime_TripDescriptor()
        trip2.tripID = "TRIP_W"
        trip2.routeID = "W"
        tripUpdate2.trip = trip2
        var stu2 = TransitRealtime_TripUpdate.StopTimeUpdate()
        stu2.stopID = "stop_times_sq"
        var arr2 = TransitRealtime_TripUpdate.StopTimeEvent()
        arr2.time = 1736337600 + 360 // 6 min
        stu2.arrival = arr2
        tripUpdate2.stopTimeUpdate = [stu2]
        entity2.tripUpdate = tripUpdate2
        
        feedMessage.entity = [entity1, entity2]
        let data = try feedMessage.serializedData()
        
        let parsed = try TransitRealtimeService.shared.parseFeedMessage(
            data: data,
            stopId: "stop_times_sq",
            targetRouteIds: ["N", "Q", "R", "W"],
            referenceDate: Date(timeIntervalSince1970: 1736337600)
        )
        
        XCTAssertEqual(parsed.count, 2, "Protobuf parser must extract both sibling line arrivals.")
        XCTAssertEqual(parsed[0].line, "N")
        XCTAssertEqual(parsed[0].minutes, 3)
        XCTAssertEqual(parsed[1].line, "W")
        XCTAssertEqual(parsed[1].minutes, 6)
    }
    
    func testMultiRouteTimetableFallback() async throws {
        let timetable = try await dbManager.fetchTimetable(for: "stop_union_sq", routeIds: ["N", "Q", "R", "W"], directionId: 0)
        XCTAssertEqual(timetable.count, 24)
        let allPills = timetable.flatMap { $0.departures }
        let uniqueRoutes = Set(allPills.map { $0.routeId })
        XCTAssertTrue(uniqueRoutes.contains("N"))
        XCTAssertTrue(uniqueRoutes.contains("Q"))
        XCTAssertTrue(uniqueRoutes.contains("R"))
        XCTAssertTrue(uniqueRoutes.contains("W"))
    }

    func testTransitRevealSheetDirectionalSnapshot() throws {
        let fixedDate = Date(timeIntervalSince1970: 1736337600)
        let mockDetails = SpatialDatabaseManager.StopDetails(
            stopId: "stop_bedford",
            name: "Bedford Ave",
            routeId: "L",
            routeType: 1,
            arrivals: [
                SpatialDatabaseManager.ArrivalInfo(line: "L", destination: "8th Ave", minutes: 2, direction: "Manhattan-bound", distanceDescription: "Approaching", arrivalDate: fixedDate.addingTimeInterval(120)),
                SpatialDatabaseManager.ArrivalInfo(line: "L", destination: "Canarsie - Rockaway Pkwy", minutes: 4, direction: "Brooklyn-bound", distanceDescription: "1 stop away", arrivalDate: fixedDate.addingTimeInterval(240)),
                SpatialDatabaseManager.ArrivalInfo(line: "L", destination: "8th Ave", minutes: 8, direction: "Manhattan-bound", distanceDescription: "3 stops away", arrivalDate: fixedDate.addingTimeInterval(480)),
                SpatialDatabaseManager.ArrivalInfo(line: "L", destination: "Lorimer St (Short Turn)", minutes: 12, direction: "Brooklyn-bound", distanceDescription: "5 stops away", arrivalDate: fixedDate.addingTimeInterval(720))
            ]
        )
        
        let mockAlerts = [
            TransitAlert(id: "L_1", routeId: "L", headerText: "Planned Work: Late night single-tracking between 8th Ave and Bedford Ave.")
        ]
        
        let view = TransitRevealSheet(
            stopId: "stop_bedford",
            initialDetails: mockDetails,
            initialLiveArrivals: mockDetails.arrivals,
            initialAlerts: mockAlerts,
            referenceDate: fixedDate
        )
        .frame(width: 375, height: 600)
        
        let vc = UIHostingController(rootView: view)
        vc.overrideUserInterfaceStyle = .light
        assertSnapshot(of: vc, as: .image(on: ViewImageConfig(size: CGSize(width: 375, height: 600)), precision: 0.98))
    }
    
    func testTransitRevealSheetMultiRouteSnapshot() throws {
        let fixedDate = Date(timeIntervalSince1970: 1736337600)
        let multiDetails = SpatialDatabaseManager.StopDetails(
            stopId: "stop_canal",
            name: "Canal St",
            routeId: "N",
            routeIds: ["N", "Q", "R", "W"],
            routeType: 1,
            arrivals: [
                SpatialDatabaseManager.ArrivalInfo(line: "N", destination: "Astoria - Ditmars Blvd", minutes: 2, direction: "Uptown & Queens", distanceDescription: "Approaching", arrivalDate: fixedDate.addingTimeInterval(120)),
                SpatialDatabaseManager.ArrivalInfo(line: "R", destination: "Forest Hills - 71 Av", minutes: 4, direction: "Uptown & Queens", distanceDescription: "1 stop away", arrivalDate: fixedDate.addingTimeInterval(240)),
                SpatialDatabaseManager.ArrivalInfo(line: "W", destination: "Astoria - Ditmars Blvd", minutes: 7, direction: "Uptown & Queens", distanceDescription: "2 stops away", arrivalDate: fixedDate.addingTimeInterval(420)),
                SpatialDatabaseManager.ArrivalInfo(line: "Q", destination: "96 St - 2nd Ave", minutes: 9, direction: "Uptown & Queens", distanceDescription: "3 stops away", arrivalDate: fixedDate.addingTimeInterval(540)),
                SpatialDatabaseManager.ArrivalInfo(line: "N", destination: "Coney Island", minutes: 3, direction: "Downtown & Brooklyn", distanceDescription: "Approaching", arrivalDate: fixedDate.addingTimeInterval(180)),
                SpatialDatabaseManager.ArrivalInfo(line: "R", destination: "Bay Ridge - 95 St", minutes: 8, direction: "Downtown & Brooklyn", distanceDescription: "3 stops away", arrivalDate: fixedDate.addingTimeInterval(480))
            ]
        )
        
        let view = TransitRevealSheet(
            stopId: "stop_canal",
            initialDetails: multiDetails,
            initialLiveArrivals: multiDetails.arrivals,
            referenceDate: fixedDate
        )
        .frame(width: 375, height: 600)
        
        let vc = UIHostingController(rootView: view)
        vc.overrideUserInterfaceStyle = .light
        assertSnapshot(of: vc, as: .image(on: ViewImageConfig(size: CGSize(width: 375, height: 600)), precision: 0.98))
    }

    func testDepartureMatrixViewSnapshot() throws {
        let fixedDate = Date(timeIntervalSince1970: 1736337600) // 12:00 UTC (hour 12)
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
                SpatialDatabaseManager.ArrivalInfo(line: "L", destination: "8th Ave", minutes: 3, direction: "Manhattan-bound", arrivalDate: fixedDate.addingTimeInterval(180))
            ],
            referenceDate: fixedDate
        )
        .frame(width: 375, height: 620)
        
        let vc = UIHostingController(rootView: view)
        assertSnapshot(of: vc, as: .image(on: ViewImageConfig(size: CGSize(width: 375, height: 620)), precision: 0.98))
    }
    
    func testDepartureMatrixViewMultiRouteSnapshot() throws {
        let fixedDate = Date(timeIntervalSince1970: 1736337600)
        var sampleDepartures: [SpatialDatabaseManager.DeparturePillRecord] = []
        let routes = ["N", "Q", "R", "W"]
        for (i, r) in routes.enumerated() {
            sampleDepartures.append(
                SpatialDatabaseManager.DeparturePillRecord(
                    id: "DEP_\(r)_\(i)",
                    tripId: "TRIP_\(r)_\(i)",
                    routeId: r,
                    destination: "Astoria",
                    minute: 5 + i * 12,
                    isExpress: (r == "N" || r == "Q")
                )
            )
        }
        
        let sampleHours = (0..<24).map { h in
            SpatialDatabaseManager.HourScheduleRecord(hourOfDay: h, departures: sampleDepartures)
        }
        
        let view = DepartureMatrixView(
            records: sampleHours,
            routeId: "N",
            routeIds: ["N", "Q", "R", "W"],
            stopId: "stop_canal",
            liveArrivals: [
                SpatialDatabaseManager.ArrivalInfo(line: "N", destination: "Astoria", minutes: 2, direction: "Uptown & Queens", arrivalDate: fixedDate.addingTimeInterval(120))
            ],
            referenceDate: fixedDate
        )
        .frame(width: 375, height: 620)
        
        let vc = UIHostingController(rootView: view)
        assertSnapshot(of: vc, as: .image(on: ViewImageConfig(size: CGSize(width: 375, height: 620)), precision: 0.98))
    }
    
    func testExportTimetableVerificationScreenshots() throws {
        let calendar = Calendar.current
        var comps = DateComponents()
        comps.year = 2025; comps.month = 1; comps.day = 8
        comps.hour = 0; comps.minute = 39; comps.second = 0
        let date0039 = calendar.date(from: comps)!
        
        let sampleDepartures00 = [
            SpatialDatabaseManager.DeparturePillRecord(id: "D00_00", tripId: "T00_00", routeId: "6", destination: "Pelham Bay Park", minute: 0),
            SpatialDatabaseManager.DeparturePillRecord(id: "D00_04", tripId: "T00_04", routeId: "6", destination: "Pelham Bay Park", minute: 4),
            SpatialDatabaseManager.DeparturePillRecord(id: "D00_06", tripId: "T00_06", routeId: "6", destination: "Pelham Bay Park", minute: 6),
            SpatialDatabaseManager.DeparturePillRecord(id: "D00_08", tripId: "T00_08", routeId: "6", destination: "Pelham Bay Park", minute: 8),
            SpatialDatabaseManager.DeparturePillRecord(id: "D00_13", tripId: "T00_13", routeId: "6", destination: "Pelham Bay Park", minute: 13),
            SpatialDatabaseManager.DeparturePillRecord(id: "D00_15", tripId: "T00_15", routeId: "6", destination: "Pelham Bay Park", minute: 15),
            SpatialDatabaseManager.DeparturePillRecord(id: "D00_17", tripId: "T00_17", routeId: "6", destination: "Pelham Bay Park", minute: 17),
            SpatialDatabaseManager.DeparturePillRecord(id: "D00_22", tripId: "T00_22", routeId: "6", destination: "Pelham Bay Park", minute: 22),
            SpatialDatabaseManager.DeparturePillRecord(id: "D00_24", tripId: "T00_24", routeId: "6", destination: "Pelham Bay Park", minute: 24),
            SpatialDatabaseManager.DeparturePillRecord(id: "D00_26", tripId: "T00_26", routeId: "6", destination: "Pelham Bay Park", minute: 26),
            SpatialDatabaseManager.DeparturePillRecord(id: "D00_31", tripId: "T00_31", routeId: "6", destination: "Pelham Bay Park", minute: 31),
            SpatialDatabaseManager.DeparturePillRecord(id: "D00_33", tripId: "T00_33", routeId: "6", destination: "Pelham Bay Park", minute: 33),
            SpatialDatabaseManager.DeparturePillRecord(id: "D00_35", tripId: "T00_35", routeId: "6", destination: "Pelham Bay Park", minute: 35),
            SpatialDatabaseManager.DeparturePillRecord(id: "D00_40", tripId: "T00_40", routeId: "6", destination: "Pelham Bay Park", minute: 40),
            SpatialDatabaseManager.DeparturePillRecord(id: "D00_42", tripId: "T00_42", routeId: "6", destination: "Pelham Bay Park", minute: 42),
            SpatialDatabaseManager.DeparturePillRecord(id: "D00_44", tripId: "T00_44", routeId: "6", destination: "Pelham Bay Park", minute: 44),
            SpatialDatabaseManager.DeparturePillRecord(id: "D00_50", tripId: "T00_50", routeId: "6", destination: "Pelham Bay Park", minute: 50),
            SpatialDatabaseManager.DeparturePillRecord(id: "D00_56", tripId: "T00_56", routeId: "6", destination: "Pelham Bay Park", minute: 56)
        ]
        
        let sampleDepartures01 = [
            SpatialDatabaseManager.DeparturePillRecord(id: "D01_00", tripId: "T01_00", routeId: "6", destination: "Pelham Bay Park", minute: 0),
            SpatialDatabaseManager.DeparturePillRecord(id: "D01_08", tripId: "T01_08", routeId: "6", destination: "Pelham Bay Park", minute: 8),
            SpatialDatabaseManager.DeparturePillRecord(id: "D01_14", tripId: "T01_14", routeId: "6", destination: "Pelham Bay Park", minute: 14),
            SpatialDatabaseManager.DeparturePillRecord(id: "D01_20", tripId: "T01_20", routeId: "6", destination: "Pelham Bay Park", minute: 20),
            SpatialDatabaseManager.DeparturePillRecord(id: "D01_29", tripId: "T01_29", routeId: "6", destination: "Pelham Bay Park", minute: 29),
            SpatialDatabaseManager.DeparturePillRecord(id: "D01_35", tripId: "T01_35", routeId: "6", destination: "Pelham Bay Park", minute: 35),
            SpatialDatabaseManager.DeparturePillRecord(id: "D01_41", tripId: "T01_41", routeId: "6", destination: "Pelham Bay Park", minute: 41),
            SpatialDatabaseManager.DeparturePillRecord(id: "D01_50", tripId: "T01_50", routeId: "6", destination: "Pelham Bay Park", minute: 50)
        ]
        
        let sampleHours = (0..<24).map { h in
            if h == 0 {
                return SpatialDatabaseManager.HourScheduleRecord(hourOfDay: 0, departures: sampleDepartures00)
            } else if h == 1 {
                return SpatialDatabaseManager.HourScheduleRecord(hourOfDay: 1, departures: sampleDepartures01)
            } else {
                let deps = [4, 12, 20, 28, 36, 44, 52].map { m in
                    SpatialDatabaseManager.DeparturePillRecord(
                        id: "D\(h)_\(m)",
                        tripId: "T\(h)_\(m)",
                        routeId: "6",
                        destination: "Pelham Bay Park",
                        minute: m
                    )
                }
                return SpatialDatabaseManager.HourScheduleRecord(hourOfDay: h, departures: deps)
            }
        }
        
        let liveArrivals = [
            SpatialDatabaseManager.ArrivalInfo(line: "6", destination: "Pelham Bay Park", minutes: 1, direction: "Uptown & Bronx", arrivalDate: date0039.addingTimeInterval(60), tripId: "T00_40"),
            SpatialDatabaseManager.ArrivalInfo(line: "6", destination: "Pelham Bay Park", minutes: 3, direction: "Uptown & Bronx", arrivalDate: date0039.addingTimeInterval(180), tripId: "T00_42"),
            SpatialDatabaseManager.ArrivalInfo(line: "6", destination: "Pelham Bay Park", minutes: 5, direction: "Uptown & Bronx", arrivalDate: date0039.addingTimeInterval(300), tripId: "T00_44"),
            SpatialDatabaseManager.ArrivalInfo(line: "6", destination: "Pelham Bay Park", minutes: 11, direction: "Uptown & Bronx", arrivalDate: date0039.addingTimeInterval(660), tripId: "T00_50"),
            SpatialDatabaseManager.ArrivalInfo(line: "6", destination: "Pelham Bay Park", minutes: 17, direction: "Uptown & Bronx", arrivalDate: date0039.addingTimeInterval(1020), tripId: "T00_56"),
            SpatialDatabaseManager.ArrivalInfo(line: "6", destination: "Pelham Bay Park", minutes: 21, direction: "Uptown & Bronx", arrivalDate: date0039.addingTimeInterval(1260), tripId: "T01_00")
        ]
        
        let details = SpatialDatabaseManager.StopDetails(
            stopId: "stop_brooklyn_bridge",
            name: "Brooklyn Bridge-City Hall",
            routeId: "6",
            routeIds: ["6"],
            routeType: 1,
            arrivals: liveArrivals
        )
        
        // Full Timetable Tab (Showing 00:00 to 03:00)
        let matrixView = DepartureMatrixView(
            records: sampleHours,
            routeId: "6",
            stopId: "stop_brooklyn_bridge",
            liveArrivals: liveArrivals,
            referenceDate: date0039
        )
        .frame(width: 375, height: 600)
        
        let matrixVC = UIHostingController(rootView: matrixView)
        matrixVC.overrideUserInterfaceStyle = .light
        assertSnapshot(of: matrixVC, as: .image(on: ViewImageConfig(size: CGSize(width: 375, height: 600)), precision: 0.98))
        
        // Live Arrivals Tab
        let sheetView = TransitRevealSheet(
            stopId: "stop_brooklyn_bridge",
            initialDetails: details,
            initialLiveArrivals: liveArrivals,
            referenceDate: date0039
        )
        .frame(width: 375, height: 650)
        
        let sheetVC = UIHostingController(rootView: sheetView)
        sheetVC.overrideUserInterfaceStyle = .light
        assertSnapshot(of: sheetVC, as: .image(on: ViewImageConfig(size: CGSize(width: 375, height: 650)), precision: 0.98))
    }
    
    func testFetchAvailableDirectionsInDatabase() async throws {
        // stop_terminal_dir1 was seeded with only direction_id = 1
        let dirs1 = try await dbManager.fetchAvailableDirections(for: "stop_terminal_dir1", routeId: "L")
        XCTAssertEqual(dirs1, Set([1]), "Stop with only Direction 1 departures should return Set([1]).")
        
        // stop_bedford was seeded with only direction_id = 0
        let dirs0 = try await dbManager.fetchAvailableDirections(for: "stop_bedford", routeId: "L")
        XCTAssertEqual(dirs0, Set([0]), "Stop with only Direction 0 departures should return Set([0]).")
        
        // stop_bidirectional was seeded with both direction 0 and 1
        let dirsBi = try await dbManager.fetchAvailableDirections(for: "stop_bidirectional", routeId: "L")
        XCTAssertEqual(dirsBi, Set([0, 1]), "Bidirectional stop should return Set([0, 1]).")
    }
    
    func testFallbackAvailableDirectionsForTerminalStops() async throws {
        // 8th Ave L is Manhattan terminal -> Direction 1 only (Brooklyn-bound)
        let dirs8th = try await dbManager.fetchAvailableDirections(for: "stop_8th_ave", routeId: "L")
        XCTAssertEqual(dirs8th, Set([1]))
        
        // South Ferry 1 is Downtown terminal -> Direction 0 only (Uptown-bound)
        let dirsSouthFerry = try await dbManager.fetchAvailableDirections(for: "stop_south_ferry", routeId: "1")
        XCTAssertEqual(dirsSouthFerry, Set([0]))
        
        // General non-terminal unknown stop defaults to [0, 1]
        let dirsGeneral = try await dbManager.fetchAvailableDirections(for: "stop_general_station", routeId: "L")
        XCTAssertEqual(dirsGeneral, Set([0, 1]))
    }
    
    func testDepartureMatrixViewAutoSelectsValidDirection() {
        var selectedDir = 0
        let binding = Binding<Int>(
            get: { selectedDir },
            set: { selectedDir = $0 }
        )
        
        let sampleHours = (0..<24).map { h in
            SpatialDatabaseManager.HourScheduleRecord(hourOfDay: h, departures: [])
        }
        
        let _ = DepartureMatrixView(
            records: sampleHours,
            routeId: "L",
            stopId: "stop_8th_ave",
            availableDirections: Set([1]),
            selectedDirection: binding
        )
        
        // Wait for main thread async dispatch in init
        let exp = expectation(description: "Auto-select valid direction")
        DispatchQueue.main.async {
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1.0)
        
        XCTAssertEqual(selectedDir, 1, "DepartureMatrixView must auto-select valid direction 1 when direction 0 is unavailable.")
    }
    
    func testDepartureMatrixViewDisabledDirectionSnapshot() throws {
        let fixedDate = Date(timeIntervalSince1970: 1736337600)
        let sampleDepartures = [
            SpatialDatabaseManager.DeparturePillRecord(id: "1", tripId: "T1", routeId: "L", destination: "Canarsie - Rockaway Pkwy", minute: 6, isExpress: false, isFirstDeparture: true),
            SpatialDatabaseManager.DeparturePillRecord(id: "2", tripId: "T2", routeId: "L", destination: "Canarsie - Rockaway Pkwy", minute: 16, isExpress: false, liveDeltaMinutes: 4, isLive: true),
            SpatialDatabaseManager.DeparturePillRecord(id: "3", tripId: "T3", routeId: "L", destination: "Canarsie - Rockaway Pkwy", minute: 26, isExpress: false),
            SpatialDatabaseManager.DeparturePillRecord(id: "4", tripId: "T4", routeId: "L", destination: "Canarsie - Rockaway Pkwy", minute: 36, isExpress: false, delaySeconds: 180),
            SpatialDatabaseManager.DeparturePillRecord(id: "5", tripId: "T5", routeId: "L", destination: "Canarsie - Rockaway Pkwy", minute: 46, isExpress: false),
            SpatialDatabaseManager.DeparturePillRecord(id: "6", tripId: "T6", routeId: "L", destination: "Canarsie - Rockaway Pkwy", minute: 56, isExpress: false, isLastDeparture: true)
        ]
        
        let sampleHours = (0..<24).map { h in
            SpatialDatabaseManager.HourScheduleRecord(hourOfDay: h, departures: sampleDepartures)
        }
        
        // Direction 0 disabled (No Service at 8th Ave terminal), Direction 1 selected
        let view = DepartureMatrixView(
            records: sampleHours,
            routeId: "L",
            stopId: "stop_8th_ave",
            liveArrivals: [
                SpatialDatabaseManager.ArrivalInfo(line: "L", destination: "Canarsie", minutes: 4, direction: "Brooklyn-bound", arrivalDate: fixedDate.addingTimeInterval(240))
            ],
            availableDirections: Set([1]),
            selectedDirection: .constant(1),
            referenceDate: fixedDate
        )
        .frame(width: 375, height: 620)
        
        let vc = UIHostingController(rootView: view)
        assertSnapshot(of: vc, as: .image(on: ViewImageConfig(size: CGSize(width: 375, height: 620)), precision: 0.98))
    }
    
    // MARK: - Wave K.7 Unit Tests
    
    func testAbsoluteMinuteLiveReconciliationCrossHour() throws {
        let calendar = Calendar.current
        var comps = DateComponents()
        comps.year = 2025; comps.month = 1; comps.day = 8
        comps.hour = 11; comps.minute = 55; comps.second = 0
        let date1155 = calendar.date(from: comps)!
        
        let hour11Deps = [
            SpatialDatabaseManager.DeparturePillRecord(id: "D11_05", tripId: "T11_05", routeId: "L", destination: "8th Ave", minute: 5),
            SpatialDatabaseManager.DeparturePillRecord(id: "D11_50", tripId: "T11_50", routeId: "L", destination: "8th Ave", minute: 50)
        ]
        let hour12Deps = [
            SpatialDatabaseManager.DeparturePillRecord(id: "D12_05", tripId: "T12_05", routeId: "L", destination: "8th Ave", minute: 5)
        ]
        
        let sampleHours = (0..<24).map { h in
            if h == 11 { return SpatialDatabaseManager.HourScheduleRecord(hourOfDay: 11, departures: hour11Deps) }
            if h == 12 { return SpatialDatabaseManager.HourScheduleRecord(hourOfDay: 12, departures: hour12Deps) }
            return SpatialDatabaseManager.HourScheduleRecord(hourOfDay: h, departures: [])
        }
        
        // Live arrival in 10 minutes (at 12:05)
        let liveArr = SpatialDatabaseManager.ArrivalInfo(
            line: "L",
            destination: "8th Ave",
            minutes: 10,
            arrivalDate: date1155.addingTimeInterval(600)
        )
        
        let view = DepartureMatrixView(
            records: sampleHours,
            routeId: "L",
            stopId: "stop_bedford",
            liveArrivals: [liveArr],
            referenceDate: date1155
        )
        
        let reconciled = view.reconciledRecords(at: date1155)
        
        let h11 = reconciled.first(where: { $0.hourOfDay == 11 })!
        let h12 = reconciled.first(where: { $0.hourOfDay == 12 })!
        
        // D11_05 must be marked past and NOT matched to 12:05 arrival
        let pill11_05 = h11.departures.first(where: { $0.id == "D11_05" })!
        XCTAssertTrue(pill11_05.isPast, "11:05 departure must be marked past.")
        XCTAssertFalse(pill11_05.isLive, "11:05 departure must NOT be matched to the 12:05 live arrival.")
        
        // D12_05 must be matched to 12:05 arrival with isLive = true and liveDeltaMinutes = 10
        let pill12_05 = h12.departures.first(where: { $0.id == "D12_05" })!
        XCTAssertTrue(pill12_05.isLive, "12:05 departure in hour 12 must be matched to live arrival.")
        XCTAssertEqual(pill12_05.liveDeltaMinutes, 10)
        XCTAssertFalse(pill12_05.isPast, "12:05 departure is in the future.")
    }
    
    func testMidnightCrossingReconciliation() throws {
        let calendar = Calendar.current
        var comps = DateComponents()
        comps.year = 2025; comps.month = 1; comps.day = 8
        comps.hour = 23; comps.minute = 58; comps.second = 0
        let date2358 = calendar.date(from: comps)!
        
        let hour00Deps = [
            SpatialDatabaseManager.DeparturePillRecord(id: "D00_03", tripId: "T00_03", routeId: "L", destination: "8th Ave", minute: 3)
        ]
        let sampleHours = (0..<24).map { h in
            if h == 0 { return SpatialDatabaseManager.HourScheduleRecord(hourOfDay: 0, departures: hour00Deps) }
            return SpatialDatabaseManager.HourScheduleRecord(hourOfDay: h, departures: [])
        }
        
        // Live arrival in 5 minutes (at 00:03 next day)
        let liveArr = SpatialDatabaseManager.ArrivalInfo(
            line: "L",
            destination: "8th Ave",
            minutes: 5,
            arrivalDate: date2358.addingTimeInterval(300)
        )
        
        let view = DepartureMatrixView(
            records: sampleHours,
            routeId: "L",
            stopId: "stop_bedford",
            liveArrivals: [liveArr],
            referenceDate: date2358
        )
        
        let reconciled = view.reconciledRecords(at: date2358)
        let h0 = reconciled.first(where: { $0.hourOfDay == 0 })!
        let pill00_03 = h0.departures.first(where: { $0.id == "D00_03" })!
        
        XCTAssertTrue(pill00_03.isLive, "00:03 departure must match across midnight boundary.")
        XCTAssertEqual(pill00_03.liveDeltaMinutes, 5)
        XCTAssertFalse(pill00_03.isPast)
    }
    
    func testPastDepartureDimming() throws {
        let calendar = Calendar.current
        var comps = DateComponents()
        comps.year = 2025; comps.month = 1; comps.day = 8
        comps.hour = 14; comps.minute = 30; comps.second = 0
        let date1430 = calendar.date(from: comps)!
        
        let deps = [
            SpatialDatabaseManager.DeparturePillRecord(id: "D14_10", tripId: "T14_10", routeId: "L", destination: "8th Ave", minute: 10),
            SpatialDatabaseManager.DeparturePillRecord(id: "D14_45", tripId: "T14_45", routeId: "L", destination: "8th Ave", minute: 45)
        ]
        let sampleHours = (0..<24).map { h in
            if h == 14 { return SpatialDatabaseManager.HourScheduleRecord(hourOfDay: 14, departures: deps) }
            return SpatialDatabaseManager.HourScheduleRecord(hourOfDay: h, departures: [])
        }
        
        let view = DepartureMatrixView(
            records: sampleHours,
            routeId: "L",
            stopId: "stop_bedford",
            liveArrivals: [],
            referenceDate: date1430
        )
        
        let reconciled = view.reconciledRecords(at: date1430)
        let h14 = reconciled.first(where: { $0.hourOfDay == 14 })!
        
        let pPast = h14.departures.first(where: { $0.id == "D14_10" })!
        let pFuture = h14.departures.first(where: { $0.id == "D14_45" })!
        
        XCTAssertTrue(pPast.isPast, "14:10 scheduled departure must be marked isPast when current time is 14:30.")
        XCTAssertFalse(pFuture.isPast, "14:45 scheduled departure must NOT be marked isPast.")
    }
    
    func testDelayAwareLivenessNotDimmed() throws {
        let calendar = Calendar.current
        var comps = DateComponents()
        comps.year = 2025; comps.month = 1; comps.day = 8
        comps.hour = 11; comps.minute = 55; comps.second = 0
        let date1155 = calendar.date(from: comps)!
        
        let deps = [
            SpatialDatabaseManager.DeparturePillRecord(id: "D11_50", tripId: "T11_50", routeId: "L", destination: "8th Ave", minute: 50)
        ]
        let sampleHours = (0..<24).map { h in
            if h == 11 { return SpatialDatabaseManager.HourScheduleRecord(hourOfDay: 11, departures: deps) }
            return SpatialDatabaseManager.HourScheduleRecord(hourOfDay: h, departures: [])
        }
        
        let liveArr = SpatialDatabaseManager.ArrivalInfo(
            line: "L",
            destination: "8th Ave",
            minutes: 3,
            arrivalDate: date1155.addingTimeInterval(180)
        )
        
        let view = DepartureMatrixView(
            records: sampleHours,
            routeId: "L",
            stopId: "stop_bedford",
            liveArrivals: [liveArr],
            referenceDate: date1155
        )
        
        let reconciled = view.reconciledRecords(at: date1155)
        let h11 = reconciled.first(where: { $0.hourOfDay == 11 })!
        let pill = h11.departures.first(where: { $0.id == "D11_50" })!
        
        XCTAssertTrue(pill.isLive)
        XCTAssertFalse(pill.isPast, "Delayed train with future estimated arrival must remain active (isPast = false).")
        XCTAssertEqual(pill.liveDeltaMinutes, 3)
        XCTAssertEqual(pill.delaySeconds, 480, "Delay must be 8 minutes (480 seconds).")
    }
    
    func testExtremeDelayMatching() throws {
        let calendar = Calendar.current
        var comps = DateComponents()
        comps.year = 2025; comps.month = 1; comps.day = 8
        comps.hour = 11; comps.minute = 55; comps.second = 0
        let date1155 = calendar.date(from: comps)!
        
        let deps = [
            SpatialDatabaseManager.DeparturePillRecord(id: "D11_40", tripId: "T11_40", routeId: "L", destination: "8th Ave", minute: 40)
        ]
        let sampleHours = (0..<24).map { h in
            if h == 11 { return SpatialDatabaseManager.HourScheduleRecord(hourOfDay: 11, departures: deps) }
            return SpatialDatabaseManager.HourScheduleRecord(hourOfDay: h, departures: [])
        }
        
        let liveArr = SpatialDatabaseManager.ArrivalInfo(
            line: "L",
            destination: "8th Ave",
            minutes: 3,
            arrivalDate: date1155.addingTimeInterval(180)
        )
        
        let view = DepartureMatrixView(
            records: sampleHours,
            routeId: "L",
            stopId: "stop_bedford",
            liveArrivals: [liveArr],
            referenceDate: date1155
        )
        
        let reconciled = view.reconciledRecords(at: date1155)
        let h11 = reconciled.first(where: { $0.hourOfDay == 11 })!
        
        XCTAssertEqual(h11.departures.count, 1, "Must not create duplicate ad-hoc pill for delayed train.")
        let pill = h11.departures[0]
        XCTAssertEqual(pill.id, "D11_40")
        XCTAssertTrue(pill.isLive)
        XCTAssertFalse(pill.isPast)
        XCTAssertEqual(pill.delaySeconds, 18 * 60)
    }
    
    func testBoardingGracePeriodAndPruning() throws {
        var feedMessage = TransitRealtime_FeedMessage()
        var header = TransitRealtime_FeedHeader()
        header.gtfsRealtimeVersion = "2.0"
        header.timestamp = 1736337600
        feedMessage.header = header
        
        let nowEpoch: Int64 = 1736337600
        
        // Entity 1: Train at platform (diffSec = -10s, within 30s grace)
        var entity1 = TransitRealtime_FeedEntity()
        entity1.id = "T1"
        var tu1 = TransitRealtime_TripUpdate()
        var trip1 = TransitRealtime_TripDescriptor()
        trip1.tripID = "TRIP_BOARDING"
        trip1.routeID = "L"
        tu1.trip = trip1
        var stu1 = TransitRealtime_TripUpdate.StopTimeUpdate()
        stu1.stopID = "stop_bedford"
        var arr1 = TransitRealtime_TripUpdate.StopTimeEvent()
        arr1.time = nowEpoch - 10
        stu1.arrival = arr1
        tu1.stopTimeUpdate = [stu1]
        entity1.tripUpdate = tu1
        
        // Entity 2: Train departed 45s ago (diffSec = -45s, past 30s grace -> must be pruned)
        var entity2 = TransitRealtime_FeedEntity()
        entity2.id = "T2"
        var tu2 = TransitRealtime_TripUpdate()
        var trip2 = TransitRealtime_TripDescriptor()
        trip2.tripID = "TRIP_PRUNED"
        trip2.routeID = "L"
        tu2.trip = trip2
        var stu2 = TransitRealtime_TripUpdate.StopTimeUpdate()
        stu2.stopID = "stop_bedford"
        var arr2 = TransitRealtime_TripUpdate.StopTimeEvent()
        arr2.time = nowEpoch - 45
        stu2.arrival = arr2
        tu2.stopTimeUpdate = [stu2]
        entity2.tripUpdate = tu2
        
        feedMessage.entity = [entity1, entity2]
        let data = try feedMessage.serializedData()
        
        let parsed = try TransitRealtimeService.shared.parseFeedMessage(
            data: data,
            stopId: "stop_bedford",
            targetRouteId: "L",
            referenceDate: Date(timeIntervalSince1970: TimeInterval(nowEpoch))
        )
        
        XCTAssertEqual(parsed.count, 1, "Only the train within 30s boarding grace should be retained.")
        XCTAssertEqual(parsed[0].minutes, 0)
        XCTAssertEqual(parsed[0].distanceDescription, "Boarding")
    }
    
    func testDynamicLivePillInjection() throws {
        let calendar = Calendar.current
        var comps = DateComponents()
        comps.year = 2025; comps.month = 1; comps.day = 8
        comps.hour = 10; comps.minute = 0; comps.second = 0
        let date1000 = calendar.date(from: comps)!
        
        let hour10Deps = [
            SpatialDatabaseManager.DeparturePillRecord(id: "D10_10", tripId: "T10_10", routeId: "L", destination: "8th Ave", minute: 10)
        ]
        let sampleHours = (0..<24).map { h in
            if h == 10 { return SpatialDatabaseManager.HourScheduleRecord(hourOfDay: 10, departures: hour10Deps) }
            return SpatialDatabaseManager.HourScheduleRecord(hourOfDay: h, departures: [])
        }
        
        // Live arrivals: 10:10 (matches static) + 10:45 (unscheduled extra train arriving in 45m)
        let liveArr1 = SpatialDatabaseManager.ArrivalInfo(
            line: "L",
            destination: "8th Ave",
            minutes: 10,
            arrivalDate: date1000.addingTimeInterval(600)
        )
        let liveArr2 = SpatialDatabaseManager.ArrivalInfo(
            line: "L",
            destination: "8th Ave",
            minutes: 45,
            arrivalDate: date1000.addingTimeInterval(2700)
        )
        
        let view = DepartureMatrixView(
            records: sampleHours,
            routeId: "L",
            stopId: "stop_bedford",
            liveArrivals: [liveArr1, liveArr2],
            referenceDate: date1000
        )
        
        let reconciled = view.reconciledRecords(at: date1000)
        let h10 = reconciled.first(where: { $0.hourOfDay == 10 })!
        
        // Full Timetable preserves published baseline schedule (no synthetic ad-hoc injections into grid)
        XCTAssertEqual(h10.departures.count, 1, "Published baseline schedule must remain stable without phantom ad-hoc injections.")
        XCTAssertEqual(h10.departures[0].minute, 10)
        XCTAssertTrue(h10.departures[0].isLive, "Matched scheduled trip must be flagged as live.")
        XCTAssertTrue(h10.departures[0].isNextDeparture, "Immediate upcoming departure must be tagged with isNextDeparture.")
    }

    func testBusFallbackAvailableDirectionsKentAndWythe() async throws {
        // Kent Av / Metropolitan Av is Northbound only (Direction 0)
        let kentDirs = try await dbManager.fetchAvailableDirections(for: "308666", routeId: "B32")
        XCTAssertEqual(kentDirs, Set([0]), "Kent Av B32 stop 308666 must be Direction 0 (Northbound) only.")
        
        let kentNamedDirs = try await dbManager.fetchAvailableDirections(for: "stop_kent_metropolitan", routeId: "B32")
        XCTAssertEqual(kentNamedDirs, Set([0]), "Kent Av B32 stop must be Direction 0 (Northbound) only.")
        
        // Wythe Av / Metropolitan Av is Southbound only (Direction 1)
        let wytheDirs = try await dbManager.fetchAvailableDirections(for: "308683", routeId: "B32")
        XCTAssertEqual(wytheDirs, Set([1]), "Wythe Av B32 stop 308683 must be Direction 1 (Southbound) only.")
    }

    func testBusFallbackTimetableRealisticHeadways() async throws {
        let timetable = try await dbManager.fetchTimetable(for: "308666", routeId: "B32", directionId: 0)
        XCTAssertEqual(timetable.count, 24)
        
        // Rush hour (8 AM) should have realistic 2-3 departures per hour (~20-30m headways), not 12-16 subway departures
        let h8 = timetable.first(where: { $0.hourOfDay == 8 })!
        XCTAssertTrue(h8.departures.count >= 2 && h8.departures.count <= 4, "Local bus rush hour should have 2-4 departures/hr, got \(h8.departures.count).")
        
        // Late night (2 AM) should have 0 departures for daytime-only local bus
        let h2 = timetable.first(where: { $0.hourOfDay == 2 })!
        XCTAssertEqual(h2.departures.count, 0, "Daytime-only local bus should have 0 departures at 2 AM.")
        
        // Destination should be Long Island City - Queens Plaza
        if let firstDep = h8.departures.first {
            XCTAssertEqual(firstDep.destination, "Long Island City - Queens Plaza")
        }
    }

    func testBusFallbackHeadwaysRange() async throws {
        let busHeadways = try await dbManager.fetchHeadwayData(for: "BUS_B32")
        XCTAssertFalse(busHeadways.isEmpty)
        for hw in busHeadways {
            XCTAssertGreaterThanOrEqual(hw, 10.0, "Bus headways should be >= 10m, got \(hw).")
            XCTAssertLessThanOrEqual(hw, 35.0, "Bus headways should be <= 35m, got \(hw).")
        }
    }
    
    func testMultiModalStopDetailsClassification() {
        // 1. Boston Park Street (Co-located Subway Red + Light Rail Green branches)
        let parkSt = SpatialDatabaseManager.StopDetails(
            stopId: "place-pktrm",
            name: "Park Street",
            routeId: "Red",
            routeIds: ["Red", "Green-B", "Green-C", "Green-D", "Green-E"],
            routeType: 1,
            arrivals: []
        )
        XCTAssertEqual(parkSt.modalClass, .subway)
        XCTAssertEqual(parkSt.routeIds.count, 5)
        
        // 2. Charlestown Ferry F4
        let ferryStop = SpatialDatabaseManager.StopDetails(
            stopId: "place-crtwn",
            name: "Charlestown Navy Yard",
            routeId: "F4",
            routeIds: ["F4"],
            routeType: 4,
            arrivals: []
        )
        XCTAssertEqual(ferryStop.modalClass, .ferry)
        
        // 3. Silver Line SL1 BRT
        let brtStop = SpatialDatabaseManager.StopDetails(
            stopId: "place-wtc",
            name: "World Trade Center",
            routeId: "SL1",
            routeIds: ["SL1", "SL2", "SL3"],
            routeType: 3,
            arrivals: []
        )
        XCTAssertEqual(brtStop.modalClass, .bus)
    }
    
    func testTransitRouteBadgeModalRendering() {
        let subwayBadge = TransitRouteBadge(routeId: "L", size: .large)
        XCTAssertEqual(subwayBadge.lineInfo.modalClass, .subway)
        
        let lrtBadge = TransitRouteBadge(routeId: "Green-B", size: .regular)
        XCTAssertEqual(lrtBadge.lineInfo.modalClass, .lightRail)
        
        let busBadge = TransitRouteBadge(routeId: "M15", size: .compact)
        XCTAssertEqual(busBadge.lineInfo.modalClass, .bus)
        
        let ferryBadge = TransitRouteBadge(routeId: "F4", size: .large)
        XCTAssertEqual(ferryBadge.lineInfo.modalClass, .ferry)
    }
    
    func testMultiModalTransitRevealSheetView() {
        let fixedDate = Date(timeIntervalSince1970: 1736337600)
        let multiModalDetails = SpatialDatabaseManager.StopDetails(
            stopId: "place-pktrm",
            name: "Park Street",
            routeId: "Red",
            routeIds: ["Red", "Green-B", "Green-C"],
            routeType: 1,
            arrivals: [
                SpatialDatabaseManager.ArrivalInfo(line: "Red", destination: "Alewife", minutes: 2, direction: "Inbound", arrivalDate: fixedDate.addingTimeInterval(120)),
                SpatialDatabaseManager.ArrivalInfo(line: "Green-B", destination: "Boston College", minutes: 4, direction: "Outbound", arrivalDate: fixedDate.addingTimeInterval(240)),
                SpatialDatabaseManager.ArrivalInfo(line: "Green-C", destination: "Cleveland Circle", minutes: 7, direction: "Outbound", arrivalDate: fixedDate.addingTimeInterval(420))
            ]
        )
        
        let sheet = TransitRevealSheet(
            stopId: "place-pktrm",
            initialDetails: multiModalDetails,
            initialLiveArrivals: multiModalDetails.arrivals,
            referenceDate: fixedDate
        )
        XCTAssertNotNil(sheet)
    }
    
    // MARK: - Wave L-C.4 Timetable Reconciler & ScheduleRelationship Tests
    
    func testBitwiseDayEvaluationFutureAndPast() async throws {
        let fixedDate = Date(timeIntervalSince1970: 1736337600) // Anchor date
        
        // Query day offset 0 (Today: bit 7 active)
        let todayResult = try await dbManager.fetchTimetableResult(
            for: "stop_pattern_test",
            routeId: "Red",
            directionId: 0,
            dayOffset: 0,
            referenceDate: fixedDate
        )
        let h8Today = todayResult.records.first(where: { $0.hourOfDay == 8 })!
        XCTAssertEqual(h8Today.departures.count, 5, "Today (offset 0) should be active and return 5 departures.")
        XCTAssertEqual(h8Today.departures.map { $0.minute }, [4, 16, 28, 40, 52])
        
        // Query day offset 1 (Tomorrow: bit 8 active)
        let tomorrowResult = try await dbManager.fetchTimetableResult(
            for: "stop_pattern_test",
            routeId: "Red",
            directionId: 0,
            dayOffset: 1,
            referenceDate: fixedDate
        )
        let h8Tomorrow = tomorrowResult.records.first(where: { $0.hourOfDay == 8 })!
        XCTAssertEqual(h8Tomorrow.departures.count, 5, "Tomorrow (offset 1) should be active and return 5 departures.")
        XCTAssertFalse(tomorrowResult.isHistoricalFallback)
    }
    
    func testCircularDistanceMatchingModeTolerances() throws {
        let calendar = Calendar.current
        var comps = DateComponents()
        comps.year = 2025; comps.month = 1; comps.day = 8
        comps.hour = 12; comps.minute = 0; comps.second = 0
        let date1200 = calendar.date(from: comps)!
        
        let sampleHours = (0..<24).map { h in
            if h == 12 {
                return SpatialDatabaseManager.HourScheduleRecord(hourOfDay: 12, departures: [
                    SpatialDatabaseManager.DeparturePillRecord(id: "D12_00", tripId: "T1", routeId: "L", destination: "8th Ave", minute: 0)
                ])
            }
            return SpatialDatabaseManager.HourScheduleRecord(hourOfDay: h, departures: [])
        }
        
        // 1. Subway live arrival 9 minutes late (12:09) -> within 10m rail tolerance
        let subwayArr = SpatialDatabaseManager.ArrivalInfo(
            line: "L",
            destination: "8th Ave",
            minutes: 9,
            arrivalDate: date1200.addingTimeInterval(540)
        )
        let subwayView = DepartureMatrixView(
            records: sampleHours,
            routeId: "L",
            stopId: "stop_subway",
            liveArrivals: [subwayArr],
            referenceDate: date1200
        )
        let subwayReconciled = subwayView.reconciledRecords(at: date1200)
        let subPill = subwayReconciled.first(where: { $0.hourOfDay == 12 })!.departures.first!
        XCTAssertTrue(subPill.isLive, "Subway 9m diff must match within 10m tolerance.")
        
        // 2. Bus stop live arrival 14 minutes late (12:14) -> within 15m bus tolerance
        let busSampleHours = (0..<24).map { h in
            if h == 12 {
                return SpatialDatabaseManager.HourScheduleRecord(hourOfDay: 12, departures: [
                    SpatialDatabaseManager.DeparturePillRecord(id: "B12_00", tripId: "TB1", routeId: "B32", destination: "Williamsburg", minute: 0)
                ])
            }
            return SpatialDatabaseManager.HourScheduleRecord(hourOfDay: h, departures: [])
        }
        let busArr = SpatialDatabaseManager.ArrivalInfo(
            line: "B32",
            destination: "Williamsburg",
            minutes: 14,
            arrivalDate: date1200.addingTimeInterval(840)
        )
        let busView = DepartureMatrixView(
            records: busSampleHours,
            routeId: "B32",
            stopId: "BUS_308666",
            liveArrivals: [busArr],
            referenceDate: date1200
        )
        let busReconciled = busView.reconciledRecords(at: date1200)
        let busPill = busReconciled.first(where: { $0.hourOfDay == 12 })!.departures.first!
        XCTAssertTrue(busPill.isLive, "Bus 14m diff must match within 15m bus tolerance.")
    }
    
    func testGTFSRealtimeScheduleRelationshipParsing() throws {
        var feedMessage = TransitRealtime_FeedMessage()
        var header = TransitRealtime_FeedHeader()
        header.gtfsRealtimeVersion = "2.0"
        header.timestamp = 1736337600
        feedMessage.header = header
        
        // 1. SCHEDULED
        var ent1 = TransitRealtime_FeedEntity()
        ent1.id = "E1"
        var tu1 = TransitRealtime_TripUpdate()
        var t1 = TransitRealtime_TripDescriptor()
        t1.routeID = "L"; t1.tripID = "T_SCHED"; t1.scheduleRelationship = .scheduled
        tu1.trip = t1
        var stu1 = TransitRealtime_TripUpdate.StopTimeUpdate()
        stu1.stopID = "stop_bedford"
        var arr1 = TransitRealtime_TripUpdate.StopTimeEvent()
        arr1.time = 1736337600 + 120
        stu1.arrival = arr1
        tu1.stopTimeUpdate = [stu1]
        ent1.tripUpdate = tu1
        
        // 2. ADDED
        var ent2 = TransitRealtime_FeedEntity()
        ent2.id = "E2"
        var tu2 = TransitRealtime_TripUpdate()
        var t2 = TransitRealtime_TripDescriptor()
        t2.routeID = "L"; t2.tripID = "T_ADDED"; t2.scheduleRelationship = .added
        tu2.trip = t2
        var stu2 = TransitRealtime_TripUpdate.StopTimeUpdate()
        stu2.stopID = "stop_bedford"
        var arr2 = TransitRealtime_TripUpdate.StopTimeEvent()
        arr2.time = 1736337600 + 300
        stu2.arrival = arr2
        tu2.stopTimeUpdate = [stu2]
        ent2.tripUpdate = tu2
        
        // 3. UNSCHEDULED
        var ent3 = TransitRealtime_FeedEntity()
        ent3.id = "E3"
        var tu3 = TransitRealtime_TripUpdate()
        var t3 = TransitRealtime_TripDescriptor()
        t3.routeID = "L"; t3.tripID = "T_UNSCHED"; t3.scheduleRelationship = .unscheduled
        tu3.trip = t3
        var stu3 = TransitRealtime_TripUpdate.StopTimeUpdate()
        stu3.stopID = "stop_bedford"
        var arr3 = TransitRealtime_TripUpdate.StopTimeEvent()
        arr3.time = 1736337600 + 450
        stu3.arrival = arr3
        tu3.stopTimeUpdate = [stu3]
        ent3.tripUpdate = tu3
        
        // 4. CANCELED
        var ent4 = TransitRealtime_FeedEntity()
        ent4.id = "E4"
        var tu4 = TransitRealtime_TripUpdate()
        var t4 = TransitRealtime_TripDescriptor()
        t4.routeID = "L"; t4.tripID = "T_CANCEL"; t4.scheduleRelationship = .canceled
        tu4.trip = t4
        var stu4 = TransitRealtime_TripUpdate.StopTimeUpdate()
        stu4.stopID = "stop_bedford"
        tu4.stopTimeUpdate = [stu4]
        ent4.tripUpdate = tu4
        
        // 5. SKIPPED STOP
        var ent5 = TransitRealtime_FeedEntity()
        ent5.id = "E5"
        var tu5 = TransitRealtime_TripUpdate()
        var t5 = TransitRealtime_TripDescriptor()
        t5.routeID = "L"; t5.tripID = "T_SKIPPED"; t5.scheduleRelationship = .scheduled
        tu5.trip = t5
        var stu5 = TransitRealtime_TripUpdate.StopTimeUpdate()
        stu5.stopID = "stop_bedford"
        stu5.scheduleRelationship = .skipped
        tu5.stopTimeUpdate = [stu5]
        ent5.tripUpdate = tu5
        
        feedMessage.entity = [ent1, ent2, ent3, ent4, ent5]
        let data = try feedMessage.serializedData()
        
        let arrivals = try TransitRealtimeService.shared.parseFeedMessage(
            data: data,
            stopId: "stop_bedford",
            targetRouteId: "L",
            referenceDate: Date(timeIntervalSince1970: 1736337600)
        )
        
        XCTAssertEqual(arrivals.count, 5)
        let sched = arrivals.first(where: { $0.tripId == "T_SCHED" })!
        XCTAssertEqual(sched.scheduleRelationship, .scheduled)
        
        let added = arrivals.first(where: { $0.tripId == "T_ADDED" })!
        XCTAssertEqual(added.scheduleRelationship, .added)
        
        let unsched = arrivals.first(where: { $0.tripId == "T_UNSCHED" })!
        XCTAssertEqual(unsched.scheduleRelationship, .unscheduled)
        
        let canceled = arrivals.first(where: { $0.tripId == "T_CANCEL" })!
        XCTAssertEqual(canceled.scheduleRelationship, .canceled)
        
        let skipped = arrivals.first(where: { $0.tripId == "T_SKIPPED" })!
        XCTAssertEqual(skipped.scheduleRelationship, .canceled)
    }
    
    func testScheduleRelationshipInSituRendering() throws {
        let calendar = Calendar.current
        var comps = DateComponents()
        comps.year = 2025; comps.month = 1; comps.day = 8
        comps.hour = 12; comps.minute = 0; comps.second = 0
        let date1200 = calendar.date(from: comps)!
        
        let sampleHours = (0..<24).map { h in
            if h == 12 {
                return SpatialDatabaseManager.HourScheduleRecord(hourOfDay: 12, departures: [
                    SpatialDatabaseManager.DeparturePillRecord(id: "D12_10", tripId: "T_CANCELED_1", routeId: "L", destination: "8th Ave", minute: 10),
                    SpatialDatabaseManager.DeparturePillRecord(id: "D12_30", tripId: "T_NORMAL_1", routeId: "L", destination: "8th Ave", minute: 30)
                ])
            }
            return SpatialDatabaseManager.HourScheduleRecord(hourOfDay: h, departures: [])
        }
        
        let liveArrivals = [
            SpatialDatabaseManager.ArrivalInfo(
                line: "L",
                destination: "8th Ave",
                minutes: 10,
                arrivalDate: date1200.addingTimeInterval(600),
                tripId: "T_CANCELED_1",
                scheduleRelationship: .canceled
            ),
            SpatialDatabaseManager.ArrivalInfo(
                line: "L",
                destination: "8th Ave",
                minutes: 45,
                arrivalDate: date1200.addingTimeInterval(2700),
                tripId: "T_ADDED_1",
                scheduleRelationship: .added
            )
        ]
        
        let view = DepartureMatrixView(
            records: sampleHours,
            routeId: "L",
            stopId: "stop_bedford",
            liveArrivals: liveArrivals,
            referenceDate: date1200
        )
        
        let reconciled = view.reconciledRecords(at: date1200)
        let h12 = reconciled.first(where: { $0.hourOfDay == 12 })!
        
        // Canceled pill should stay in-situ in hour 12
        let canceledPill = h12.departures.first(where: { $0.id == "D12_10" })!
        XCTAssertEqual(canceledPill.scheduleRelationship, .canceled)
        XCTAssertFalse(canceledPill.isPast)
        
        // Added pill should be dynamically injected into hour 12
        let addedPill = h12.departures.first(where: { $0.scheduleRelationship == .added })!
        XCTAssertEqual(addedPill.scheduleRelationship, .added)
        XCTAssertTrue(addedPill.isLive)
    }
    
    func testPastDayObservedRealityReplayAndFallbackBanner() async throws {
        let fixedDate = Date(timeIntervalSince1970: 1736337600)
        
        // Query past day (-1) for stop_bedford which has stop_events seeded
        let observedResult = try await dbManager.fetchTimetableResult(
            for: "stop_bedford",
            routeId: "L",
            directionId: 0,
            dayOffset: -1,
            referenceDate: fixedDate.addingTimeInterval(86400) // Next day querying yesterday
        )
        XCTAssertTrue(observedResult.isObservedReplay, "When stop_events exist for past day, isObservedReplay must be true.")
        XCTAssertFalse(observedResult.isHistoricalFallback)
        
        // Query past day (-2) for unknown stop with 0 stop_events
        let fallbackResult = try await dbManager.fetchTimetableResult(
            for: "stop_no_events",
            routeId: "L",
            directionId: 0,
            dayOffset: -2,
            referenceDate: fixedDate
        )
        XCTAssertFalse(fallbackResult.isObservedReplay)
        XCTAssertTrue(fallbackResult.isHistoricalFallback, "When no stop_events exist for past day, isHistoricalFallback must be true.")
    }
    
    func testTransitMatrixInspectorAndTripLedgerViewInstantiation() throws {
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
        
        let inspectorView = TransitMatrixInspectorView(record: record)
        let inspectorVc = UIHostingController(rootView: inspectorView)
        XCTAssertNotNil(inspectorVc.view)
        
        let ledgerView = TripLedgerView(
            stopId: "stop_bedford",
            routeId: "L",
            hourOfDay: 8,
            dayOfWeek: 3
        )
        let ledgerVc = UIHostingController(rootView: ledgerView)
        XCTAssertNotNil(ledgerVc.view)
    }
    
    func testUnionSquareMultiRouteTimetableIncludes4Train() async throws {
        let fixedDate = Date(timeIntervalSince1970: 1736337600) // Wednesday
        
        // Seed 4, 5, 6 patterns for a station
        try await dbManager.dbWriter.write { db in
            try db.execute(sql: """
                INSERT INTO scheduled_hourly_patterns VALUES ('stop_union_sq_test', '6', 0, 8, 384, 127, '02,14,26,38,50', 'Pelham Bay Park');
                INSERT INTO scheduled_hourly_patterns VALUES ('stop_union_sq_test', '4', 0, 8, 384, 127, '06,18,30,42,54', 'Woodlawn');
                INSERT INTO scheduled_hourly_patterns VALUES ('stop_union_sq_test', '5', 0, 8, 384, 127, '10,22,34,46,58', 'Eastchester');
            """)
        }
        
        // When TransitRevealSheet queries timetable with primary routeId "6" and all routeIds ["6", "5", "4"]
        let result = try await dbManager.fetchTimetableResult(
            for: "stop_union_sq_test",
            routeId: "6",
            routeIds: ["6", "5", "4"],
            directionId: 0,
            dayOffset: 0,
            referenceDate: fixedDate
        )
        
        let h8 = result.records.first(where: { $0.hourOfDay == 8 })
        XCTAssertNotNil(h8)
        let departures = h8?.departures ?? []
        let routeIdsInResult = Set(departures.map { $0.routeId })
        
        XCTAssertTrue(routeIdsInResult.contains("4"), "4 train departures must appear in timetable result for Union Square.")
        XCTAssertTrue(routeIdsInResult.contains("5"), "5 train departures must appear in timetable result for Union Square.")
        XCTAssertTrue(routeIdsInResult.contains("6"), "6 train departures must appear in timetable result for Union Square.")
    }
    
    @MainActor
    func testUnionSquareSnapshot() throws {
        let fixedDate = Date(timeIntervalSince1970: 1736337600) // Wednesday
        
        let unionSqDetails = SpatialDatabaseManager.StopDetails(
            stopId: "635",
            name: "14 St - Union Sq",
            routeId: "6",
            routeIds: ["6", "5", "4", "6X"],
            routeType: 1,
            arrivals: [
                SpatialDatabaseManager.ArrivalInfo(line: "4", destination: "Woodlawn", minutes: 2, direction: "Uptown & Bronx", distanceDescription: "Approaching", arrivalDate: fixedDate.addingTimeInterval(120)),
                SpatialDatabaseManager.ArrivalInfo(line: "5", destination: "Eastchester - Dyre Av", minutes: 5, direction: "Uptown & Bronx", distanceDescription: "2 stops away", arrivalDate: fixedDate.addingTimeInterval(300)),
                SpatialDatabaseManager.ArrivalInfo(line: "6", destination: "Pelham Bay Park", minutes: 7, direction: "Uptown & Bronx", distanceDescription: "3 stops away", arrivalDate: fixedDate.addingTimeInterval(420)),
                SpatialDatabaseManager.ArrivalInfo(line: "4", destination: "Woodlawn", minutes: 11, direction: "Uptown & Bronx", distanceDescription: "5 stops away", arrivalDate: fixedDate.addingTimeInterval(660))
            ]
        )
        
        var sampleDepartures: [SpatialDatabaseManager.DeparturePillRecord] = []
        let routes = ["6", "5", "4", "6X"]
        for (i, r) in routes.enumerated() {
            sampleDepartures.append(
                SpatialDatabaseManager.DeparturePillRecord(
                    id: "DEP_\(r)_\(i)_1",
                    tripId: "TRIP_\(r)_\(i)_1",
                    routeId: r,
                    destination: r == "4" ? "Woodlawn" : (r == "5" ? "Eastchester" : "Pelham Bay Park"),
                    minute: 4 + i * 14,
                    isExpress: (r == "4" || r == "5" || r == "6X")
                )
            )
            sampleDepartures.append(
                SpatialDatabaseManager.DeparturePillRecord(
                    id: "DEP_\(r)_\(i)_2",
                    tripId: "TRIP_\(r)_\(i)_2",
                    routeId: r,
                    destination: r == "4" ? "Woodlawn" : (r == "5" ? "Eastchester" : "Pelham Bay Park"),
                    minute: 10 + i * 14,
                    isExpress: (r == "4" || r == "5" || r == "6X")
                )
            )
        }
        
        let sampleHours = (0..<24).map { h in
            SpatialDatabaseManager.HourScheduleRecord(hourOfDay: h, departures: sampleDepartures.sorted { $0.minute < $1.minute })
        }
        
        // 1. Timetable Matrix with 4, 5, 6, 6X route pills
        let matrixView = DepartureMatrixView(
            records: sampleHours,
            routeId: "6",
            routeIds: ["6", "5", "4", "6X"],
            stopId: "635",
            liveArrivals: unionSqDetails.arrivals,
            referenceDate: fixedDate
        )
        .frame(width: 375, height: 620)
        
        let matrixVc = UIHostingController(rootView: matrixView)
        matrixVc.overrideUserInterfaceStyle = .light
        assertSnapshot(of: matrixVc, as: .image(on: ViewImageConfig(size: CGSize(width: 375, height: 620)), precision: 0.98))
        
        // 2. Full TransitRevealSheet with 4 train live arrivals and multi-route header badges
        let sheetView = TransitRevealSheet(
            stopId: "635",
            initialDetails: unionSqDetails,
            initialLiveArrivals: unionSqDetails.arrivals,
            referenceDate: fixedDate
        )
        .frame(width: 375, height: 650)
        
        let sheetVc = UIHostingController(rootView: sheetView)
        sheetVc.overrideUserInterfaceStyle = .light
        assertSnapshot(of: sheetVc, as: .image(on: ViewImageConfig(size: CGSize(width: 375, height: 650)), precision: 0.98))
    }
    
    func testDepartureMatrixCanvasSnapshot() throws {
        let fixture = DepartureMatrixBuffer.syntheticFixture(lowVariance: false)
        let canvasView = DepartureMatrixCanvas(
            buffer: fixture,
            maxWaitThreshold: 15.0
        )
        .frame(width: 375, height: 280)
        
        let vc = UIHostingController(rootView: canvasView)
        vc.overrideUserInterfaceStyle = .light
        assertSnapshot(of: vc, as: .image(on: ViewImageConfig(size: CGSize(width: 375, height: 280)), precision: 0.98))
    }
    
    func testDepartureMatrixCanvasSelectedSlotSnapshot() throws {
        let fixture = DepartureMatrixBuffer.syntheticFixture(lowVariance: false)
        let canvasView = DepartureMatrixCanvas(
            buffer: fixture,
            maxWaitThreshold: 15.0,
            initialSelectedSlot: 8 * 60 + 30 // 08:30 morning peak
        )
        .frame(width: 375, height: 280)
        
        let vc = UIHostingController(rootView: canvasView)
        vc.overrideUserInterfaceStyle = .light
        assertSnapshot(of: vc, as: .image(on: ViewImageConfig(size: CGSize(width: 375, height: 280)), precision: 0.98))
    }
    
    // MARK: - Wave P.1 Wall-Clock Matrix Anchoring & Temporal Invalidation Tests
    
    func testDepartureMatrixDeterministicDimensions() {
        XCTAssertEqual(DepartureMatrixView.defaultRowHeight, 56.0, "Hour row height must be deterministically 56pt (Doc 18)")
        XCTAssertEqual(DepartureMatrixView.defaultHeaderHeight, 36.0, "Timetable header height must be deterministically 36pt (Doc 18)")
    }
    
    func testInitialScrollTargetResolutionHeadless() {
        let calendar = Calendar.current
        var comps = DateComponents()
        comps.year = 2026; comps.month = 9; comps.day = 3
        comps.hour = 14; comps.minute = 44; comps.second = 0
        let date1444 = calendar.date(from: comps)!
        
        let sampleHours = (0..<24).map { h in
            SpatialDatabaseManager.HourScheduleRecord(hourOfDay: h, departures: [])
        }
        
        // Today (dayOffset = 0)
        let viewToday = DepartureMatrixView(
            records: sampleHours,
            routeId: "L",
            stopId: "stop_bedford",
            selectedDayOffset: .constant(0),
            referenceDate: date1444
        )
        let targetToday = viewToday.resolveInitialScrollTarget(relativeTo: date1444)
        XCTAssertEqual(targetToday, 14, "Initial target for today must resolve to current wall-clock hour (14)")
        
        // Yesterday / Tomorrow (dayOffset != 0)
        let viewOtherDay = DepartureMatrixView(
            records: sampleHours,
            routeId: "L",
            stopId: "stop_bedford",
            selectedDayOffset: .constant(1),
            referenceDate: date1444
        )
        let targetOtherDay = viewOtherDay.resolveInitialScrollTarget(relativeTo: date1444)
        XCTAssertEqual(targetOtherDay, 0, "Initial target for non-today must resolve to 00:00 (start of service day)")
    }
    
    func testAllTransitionDatesExtraction() {
        let calendar = Calendar.current
        var comps = DateComponents()
        comps.year = 2026; comps.month = 9; comps.day = 3
        comps.hour = 10; comps.minute = 0; comps.second = 0
        let date1000 = calendar.date(from: comps)!
        
        let deps = [
            SpatialDatabaseManager.DeparturePillRecord(id: "D1", tripId: "T1", routeId: "L", destination: "8th Ave", minute: 14),
            SpatialDatabaseManager.DeparturePillRecord(id: "D2", tripId: "T2", routeId: "L", destination: "8th Ave", minute: 31)
        ]
        let sampleHours = (0..<24).map { h in
            if h == 10 { return SpatialDatabaseManager.HourScheduleRecord(hourOfDay: 10, departures: deps) }
            return SpatialDatabaseManager.HourScheduleRecord(hourOfDay: h, departures: [])
        }
        
        let liveArr = SpatialDatabaseManager.ArrivalInfo(
            line: "L",
            destination: "8th Ave",
            minutes: 5,
            arrivalDate: date1000.addingTimeInterval(300)
        )
        
        let view = DepartureMatrixView(
            records: sampleHours,
            routeId: "L",
            stopId: "stop_bedford",
            liveArrivals: [liveArr],
            referenceDate: date1000
        )
        
        let transitionDates = view.allTransitionDates
        XCTAssertTrue(transitionDates.count >= 26, "Must contain all 24 hour boundaries plus scheduled departures and live arrivals")
        
        // Verify sorted ordering
        for i in 0..<(transitionDates.count - 1) {
            XCTAssertLessThanOrEqual(transitionDates[i], transitionDates[i + 1], "Transition dates must be strictly sorted")
        }
        
        // Verify specific departure date is included
        let expectedDep1 = calendar.date(bySettingHour: 10, minute: 14, second: 0, of: calendar.startOfDay(for: date1000))!
        XCTAssertTrue(transitionDates.contains(expectedDep1), "Must include 10:14 scheduled departure timestamp")
    }
    
    // MARK: - Wave P.2 Declutter & Single Imminent Anchor Tests
    
    func testDepartureMatrixDeclutterSingleImminentAnchor() {
        let calendar = Calendar.current
        var comps = DateComponents()
        comps.year = 2026; comps.month = 9; comps.day = 3
        comps.hour = 12; comps.minute = 10; comps.second = 0
        let date1210 = calendar.date(from: comps)!
        
        let deps = [
            SpatialDatabaseManager.DeparturePillRecord(id: "D1", tripId: "T1", routeId: "L", destination: "8th Ave", minute: 5),
            SpatialDatabaseManager.DeparturePillRecord(id: "D2", tripId: "T2", routeId: "L", destination: "8th Ave", minute: 15),
            SpatialDatabaseManager.DeparturePillRecord(id: "D3", tripId: "T3", routeId: "L", destination: "8th Ave", minute: 25),
            SpatialDatabaseManager.DeparturePillRecord(id: "D4", tripId: "T4", routeId: "L", destination: "8th Ave", minute: 35)
        ]
        let sampleHours = (0..<24).map { h in
            if h == 12 { return SpatialDatabaseManager.HourScheduleRecord(hourOfDay: 12, departures: deps) }
            return SpatialDatabaseManager.HourScheduleRecord(hourOfDay: h, departures: [])
        }
        
        // Live arrivals for both D2 and D3
        let live1 = SpatialDatabaseManager.ArrivalInfo(
            line: "L",
            destination: "8th Ave",
            minutes: 5,
            arrivalDate: date1210.addingTimeInterval(300),
            tripId: "T2"
        )
        let live2 = SpatialDatabaseManager.ArrivalInfo(
            line: "L",
            destination: "8th Ave",
            minutes: 15,
            arrivalDate: date1210.addingTimeInterval(900),
            tripId: "T3"
        )
        
        let view = DepartureMatrixView(
            records: sampleHours,
            routeId: "L",
            stopId: "stop_bedford",
            liveArrivals: [live1, live2],
            referenceDate: date1210
        )
        
        let reconciled = view.reconciledRecords(at: date1210)
        let hour12 = reconciled.first(where: { $0.hourOfDay == 12 })!
        
        // D1 should be marked as past
        let d1 = hour12.departures.first(where: { $0.id == "D1" })!
        XCTAssertTrue(d1.isPast)
        XCTAssertFalse(d1.isNextDeparture)
        
        // D2 should be the SINGLE imminent anchor
        let d2 = hour12.departures.first(where: { $0.id == "D2" })!
        XCTAssertFalse(d2.isPast)
        XCTAssertTrue(d2.isNextDeparture, "D2 at 12:15 must be flagged as the single imminent anchor")
        XCTAssertTrue(d2.isImminentLive, "D2 must be flagged as imminent live anchor")
        
        // D3 is a future live departure but MUST NOT be marked as next or imminent live anchor in the 24-hr matrix
        let d3 = hour12.departures.first(where: { $0.id == "D3" })!
        XCTAssertFalse(d3.isPast)
        XCTAssertTrue(d3.isLive, "D3 retains its live association")
        XCTAssertFalse(d3.isNextDeparture, "D3 must NOT be flagged as next departure")
        XCTAssertFalse(d3.isImminentLive, "D3 must NOT be flagged as imminent anchor pill")
        
        // Count total next departures across all 24 hours — must be exactly 1
        let allNext = reconciled.flatMap { $0.departures }.filter { $0.isNextDeparture }
        XCTAssertEqual(allNext.count, 1, "There must be exactly one imminent next departure anchor across the 24-hour matrix")
    }
    
    func testDepartureMatrixDeduplication() {
        let calendar = Calendar.current
        var comps = DateComponents()
        comps.year = 2026; comps.month = 9; comps.day = 3
        comps.hour = 14; comps.minute = 0; comps.second = 0
        let date1400 = calendar.date(from: comps)!
        
        // Create duplicate departures at minute 15 for route L
        let deps = [
            SpatialDatabaseManager.DeparturePillRecord(id: "D_sched", tripId: "T_sched", routeId: "L", destination: "Canarsie", minute: 15),
            SpatialDatabaseManager.DeparturePillRecord(id: "D_live", tripId: "T_live", routeId: "L", destination: "Canarsie", minute: 15)
        ]
        let sampleHours = (0..<24).map { h in
            if h == 14 { return SpatialDatabaseManager.HourScheduleRecord(hourOfDay: 14, departures: deps) }
            return SpatialDatabaseManager.HourScheduleRecord(hourOfDay: h, departures: [])
        }
        
        let liveArr = SpatialDatabaseManager.ArrivalInfo(
            line: "L",
            destination: "Canarsie",
            minutes: 15,
            arrivalDate: date1400.addingTimeInterval(900),
            tripId: "T_live"
        )
        
        let view = DepartureMatrixView(
            records: sampleHours,
            routeId: "L",
            stopId: "stop_bedford",
            liveArrivals: [liveArr],
            referenceDate: date1400
        )
        
        let reconciled = view.reconciledRecords(at: date1400)
        let hour14 = reconciled.first(where: { $0.hourOfDay == 14 })!
        
        XCTAssertEqual(hour14.departures.count, 1, "Duplicate departures at (L, 15) must be deduplicated to 1 pill")
        let merged = hour14.departures.first!
        XCTAssertEqual(merged.minute, 15)
        XCTAssertTrue(merged.isLive, "Merged pill should inherit live status from the matching departure")
    }
}

