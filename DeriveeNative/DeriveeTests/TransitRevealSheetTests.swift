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
        
        let view = ReliabilityHeatmapCanvas(
            records: sampleRecords,
            initialDay: 3,
            initialHour: 8
        )
        .frame(width: 360, height: 250)
        
        let vc = UIHostingController(rootView: view)
        assertSnapshot(of: vc, as: .image(on: ViewImageConfig(size: CGSize(width: 360, height: 250))))
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
        assertSnapshot(of: vc, as: .image(on: ViewImageConfig(size: CGSize(width: 375, height: 600))))
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
        assertSnapshot(of: vc, as: .image(on: ViewImageConfig(size: CGSize(width: 375, height: 600))))
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
        assertSnapshot(of: vc, as: .image(on: ViewImageConfig(size: CGSize(width: 375, height: 620))))
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
        assertSnapshot(of: vc, as: .image(on: ViewImageConfig(size: CGSize(width: 375, height: 620))))
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
        assertSnapshot(of: vc, as: .image(on: ViewImageConfig(size: CGSize(width: 375, height: 620))))
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
        
        XCTAssertEqual(h10.departures.count, 2, "Unscheduled GTFS-RT arrival must be dynamically injected.")
        XCTAssertEqual(h10.departures[0].minute, 10)
        XCTAssertEqual(h10.departures[1].minute, 45)
        XCTAssertTrue(h10.departures[1].isUnscheduled)
        XCTAssertTrue(h10.departures[1].isLive)
    }
}
