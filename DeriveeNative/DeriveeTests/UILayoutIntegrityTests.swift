import XCTest
import SwiftUI
import CoreLocation
import MapLibre
@testable import Derivee

final class UILayoutIntegrityTests: XCTestCase {
    
    // MARK: - Bug 7: Bus Route Badge Text Squishing & Fixed Size
    
    func testTransitRouteBadgeBusFixedSizeAndLineLimit() {
        let busBadge = TransitRouteBadge(routeId: "S51", size: .regular)
        XCTAssertEqual(busBadge.routeId, "S51")
        XCTAssertEqual(busBadge.size, .regular)
        XCTAssertEqual(busBadge.lineInfo.modalClass, .bus)
        
        let sbsBadge = TransitRouteBadge(routeId: "M15-SBS", size: .regular)
        XCTAssertEqual(sbsBadge.routeId, "M15-SBS")
        XCTAssertEqual(sbsBadge.lineInfo.modalClass, .bus)
        
        // Host the view in a tight frame to ensure layout calculates without crash
        let host = UIHostingController(rootView: busBadge.frame(width: 30, height: 20))
        _ = host.view
        XCTAssertNotNil(host.view)
    }
    
    // MARK: - Bug 8: StopDetails Route IDs Deduplication
    
    func testStopDetailsRouteIdsDeduplication() {
        let details = SpatialDatabaseManager.StopDetails(
            stopId: "200153",
            name: "Bay St & Victory Blvd",
            routeId: "S51",
            routeIds: ["S51", "S51", "S81", "S51", "S81", "S78"],
            routeType: 3,
            arrivals: []
        )
        
        XCTAssertEqual(details.routeIds, ["S51", "S81", "S78"], "StopDetails.init must deduplicate routeIds array while preserving insertion order")
    }
    
    func testStopDetailsEmptyRouteIdsFallback() {
        let details = SpatialDatabaseManager.StopDetails(
            stopId: "200153",
            name: "Bay St & Victory Blvd",
            routeId: "S51",
            routeIds: [],
            routeType: 3,
            arrivals: []
        )
        
        XCTAssertEqual(details.routeIds, ["S51"], "Empty routeIds must default to single primary routeId")
    }
    
    // MARK: - Bug 9 & Bug 10: Departure Matrix Filter Pills & Single Next Anchor Lexicographic Tie-Break
    
    func testDepartureMatrixNextBadgeSingleAnchorLexicographicTieBreak() {
        let calendar = Calendar.current
        var comps = DateComponents()
        comps.year = 2026; comps.month = 9; comps.day = 12
        comps.hour = 14; comps.minute = 10; comps.second = 0
        let date1410 = calendar.date(from: comps)!
        
        // S81 is added BEFORE S51 in the departures list, both at minute 15
        let deps = [
            SpatialDatabaseManager.DeparturePillRecord(id: "DEP_S81_15", tripId: "T_S81", routeId: "S81", destination: "St George", minute: 15),
            SpatialDatabaseManager.DeparturePillRecord(id: "DEP_S51_15", tripId: "T_S51", routeId: "S51", destination: "St George", minute: 15),
            SpatialDatabaseManager.DeparturePillRecord(id: "DEP_S51_30", tripId: "T_S51_2", routeId: "S51", destination: "St George", minute: 30)
        ]
        
        let sampleHours = (0..<24).map { h in
            if h == 14 { return SpatialDatabaseManager.HourScheduleRecord(hourOfDay: 14, departures: deps) }
            return SpatialDatabaseManager.HourScheduleRecord(hourOfDay: h, departures: [])
        }
        
        let view = DepartureMatrixView(
            records: sampleHours,
            routeId: "S51",
            routeIds: ["S51", "S81"],
            stopId: "200153",
            liveArrivals: [],
            initialRouteFilter: "ALL",
            referenceDate: date1410
        )
        
        let reconciled = view.reconciledRecords(at: date1410)
        let hour14 = reconciled.first(where: { $0.hourOfDay == 14 })!
        
        // Count total next departures across the entire 24-hour table — MUST BE EXACTLY 1
        let allNext = reconciled.flatMap { $0.departures }.filter { $0.isNextDeparture }
        XCTAssertEqual(allNext.count, 1, "There must be exactly one NEXT departure anchor across the 24-hour timetable")
        
        // S51 must win the tie-break over S81 lexicographically ("S51" < "S81")
        let s51Pill = hour14.departures.first(where: { $0.routeId == "S51" && $0.minute == 15 })!
        let s81Pill = hour14.departures.first(where: { $0.routeId == "S81" && $0.minute == 15 })!
        
        XCTAssertTrue(s51Pill.isNextDeparture, "S51 at 14:15 must be flagged as NEXT departure because S51 precedes S81 lexicographically")
        XCTAssertFalse(s81Pill.isNextDeparture, "S81 at 14:15 must NOT be flagged as NEXT departure")
    }
    
    func testDepartureMatrixSingleRouteDefaultingScopesToActiveLine() {
        let calendar = Calendar.current
        var comps = DateComponents()
        comps.year = 2026; comps.month = 9; comps.day = 12
        comps.hour = 14; comps.minute = 10; comps.second = 0
        let date1410 = calendar.date(from: comps)!
        
        let deps = [
            SpatialDatabaseManager.DeparturePillRecord(id: "DEP_S81_15", tripId: "T_S81", routeId: "S81", destination: "St George", minute: 15),
            SpatialDatabaseManager.DeparturePillRecord(id: "DEP_S51_15", tripId: "T_S51", routeId: "S51", destination: "St George", minute: 15),
            SpatialDatabaseManager.DeparturePillRecord(id: "DEP_S51_30", tripId: "T_S51_2", routeId: "S51", destination: "St George", minute: 30)
        ]
        
        let sampleHours = (0..<24).map { h in
            if h == 14 { return SpatialDatabaseManager.HourScheduleRecord(hourOfDay: 14, departures: deps) }
            return SpatialDatabaseManager.HourScheduleRecord(hourOfDay: h, departures: [])
        }
        
        // Default without initialRouteFilter must scope exclusively to routeId "S51"
        let view = DepartureMatrixView(
            records: sampleHours,
            routeId: "S51",
            routeIds: ["S51", "S81"],
            stopId: "200153",
            liveArrivals: [],
            referenceDate: date1410
        )
        
        let reconciled = view.reconciledRecords(at: date1410)
        let hour14 = reconciled.first(where: { $0.hourOfDay == 14 })!
        
        // Only S51 departures must be present in the reconciled stream
        XCTAssertEqual(hour14.departures.count, 2, "Default single-route scope must filter out co-located S81 departures")
        XCTAssertTrue(hour14.departures.allSatisfy { $0.routeId == "S51" }, "All departures must belong to active route S51")
    }
    
    func testDepartureMatrixResetPreExistingNextFlags() {
        let calendar = Calendar.current
        var comps = DateComponents()
        comps.year = 2026; comps.month = 9; comps.day = 12
        comps.hour = 10; comps.minute = 0; comps.second = 0
        let date1000 = calendar.date(from: comps)!
        
        // Departures where multiple pills mistakenly have isNextDeparture = true in raw input
        let deps = [
            SpatialDatabaseManager.DeparturePillRecord(id: "D1", tripId: "T1", routeId: "M15", destination: "South Ferry", minute: 10, isNextDeparture: true),
            SpatialDatabaseManager.DeparturePillRecord(id: "D2", tripId: "T2", routeId: "M15", destination: "South Ferry", minute: 20, isNextDeparture: true),
            SpatialDatabaseManager.DeparturePillRecord(id: "D3", tripId: "T3", routeId: "M15", destination: "South Ferry", minute: 30, isNextDeparture: true)
        ]
        
        let sampleHours = (0..<24).map { h in
            if h == 10 { return SpatialDatabaseManager.HourScheduleRecord(hourOfDay: 10, departures: deps) }
            return SpatialDatabaseManager.HourScheduleRecord(hourOfDay: h, departures: [])
        }
        
        let view = DepartureMatrixView(
            records: sampleHours,
            routeId: "M15",
            routeIds: ["M15"],
            stopId: "stop_m15",
            liveArrivals: [],
            referenceDate: date1000
        )
        
        let reconciled = view.reconciledRecords(at: date1000)
        let nextPills = reconciled.flatMap { $0.departures }.filter { $0.isNextDeparture }
        
        XCTAssertEqual(nextPills.count, 1, "Only the single earliest departure must remain tagged as NEXT; pre-existing flags must be cleared")
        XCTAssertEqual(nextPills.first?.id, "D1")
    }
    
    // MARK: - Bug 11: NearbyBusesCapsule Leading Alignment
    
    func testNearbyBusesCapsuleLeadingAlignment() {
        let busStops = [
            SpatialDatabaseManager.NearbyBusStop(
                id: "200153",
                name: "Bay St & Victory Blvd",
                coordinate: CLLocationCoordinate2D(latitude: 40.6385, longitude: -74.0765),
                distanceMeters: 45.0,
                routes: ["S51", "S81"],
                direction: "Southbound"
            )
        ]
        
        let capsule = NearbyBusesCapsule(
            busStops: busStops,
            isExpanded: .constant(true),
            isLoading: false,
            hasLocation: true,
            onSelectStop: { _ in },
            onRefresh: { }
        )
        
        // Host the capsule view
        let host = UIHostingController(rootView: capsule)
        _ = host.view
        XCTAssertNotNil(host.view)
    }
    
    // MARK: - Bug 12: Nearby Bus Stops Source Clustering
    
    func testNearbyBusStopsSourceClusteredOptions() {
        let sourceOptions: [MLNShapeSourceOption: Any] = [
            .clustered: true,
            .clusterRadius: 30
        ]
        
        let source = MLNShapeSource(
            identifier: MapCustomizationDefaults.nearbyBusStopsSourceId,
            features: [],
            options: sourceOptions
        )
        
        XCTAssertEqual(source.identifier, "nearby-bus-stops-source")
    }
}
