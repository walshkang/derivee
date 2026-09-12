import XCTest
import CoreLocation
import SwiftUI
@testable import Derivee

final class BusStopLadderTests: XCTestCase {

    override func setUp() async throws {
        try await super.setUp()
        // Ensure transit database is attached
        _ = try? await SpatialDatabaseManager.shared.isHydrationComplete()
    }

    // MARK: - 1. Real Bus Stop Ladder Query (S51 Staten Island)

    func testS51BusStopLadderRealStops() async throws {
        let ladder = try await SpatialDatabaseManager.shared.fetchRouteStopLadder(
            routeId: "S51",
            directionId: 1, // Southbound towards Midland Beach
            currentStopId: "200153", // Bay St & Victory Blvd
            currentArrivalMinutes: 5
        )

        XCTAssertFalse(ladder.isEmpty, "S51 bus stop ladder must return real stops from transit.stops")
        XCTAssertGreaterThan(ladder.count, 5, "S51 corridor should have substantial stops")

        // 1. Current stop resolution
        let currentStop = ladder.first(where: { $0.isCurrent })
        XCTAssertNotNil(currentStop, "Current stop must be identified in stop ladder")
        XCTAssertEqual(currentStop?.stopId, "200153")
        XCTAssertEqual(currentStop?.stopName, "Bay St & Victory Blvd")
        XCTAssertEqual(currentStop?.estimatedMinutes, 5)
        XCTAssertFalse(currentStop?.isPassed ?? true)

        // 2. Real street intersection names along Bay St / Midland Beach
        let stopNames = ladder.map(\.stopName)
        XCTAssertTrue(stopNames.contains("St George Ferry Terminal") || stopNames.contains("Bay St & Borough Pl"),
                      "Should contain St George Ferry or nearby Bay St terminal stops")
        XCTAssertTrue(stopNames.contains("Bay St & Victory Blvd"), "Should contain Bay St & Victory Blvd")

        // 3. ZERO mock stops from deleted generateFallbackStopLadder
        XCTAssertFalse(stopNames.contains("Midtown Crossing"), "Must not leak Midtown Crossing mock stop")
        XCTAssertFalse(stopNames.contains("Central Square"), "Must not leak Central Square mock stop")
        XCTAssertFalse(stopNames.contains("Civic Center"), "Must not leak Civic Center mock stop")
        XCTAssertFalse(stopNames.contains("Origin Terminal"), "Must not leak Origin Terminal mock stop")
        XCTAssertFalse(stopNames.contains("Final Destination"), "Must not leak Final Destination mock stop")

        // 4. Zero fake subway 4/5 transfer badges
        for stop in ladder {
            XCTAssertFalse(stop.transferRoutes.contains("4") && stop.transferRoutes.contains("5"),
                           "Bus stop \(stop.stopName) must not have hardcoded subway 4/5 transfer badges")
        }
    }

    // MARK: - 2. Coordinate Boundaries in Staten Island (No Manhattan Flyout)

    func testS51BusStopLadderCoordinatesInStatenIsland() async throws {
        let ladder = try await SpatialDatabaseManager.shared.fetchRouteStopLadder(
            routeId: "S51",
            directionId: 1,
            currentStopId: "200153",
            currentArrivalMinutes: 3
        )

        XCTAssertFalse(ladder.isEmpty)

        // All S51 coordinates must reside strictly within Staten Island bounds
        // Staten Island roughly: Lat 40.49 to 40.66, Lon -74.26 to -74.05
        for stop in ladder {
            let lat = stop.coordinate.latitude
            let lon = stop.coordinate.longitude

            XCTAssertGreaterThanOrEqual(lat, 40.54, "Stop \(stop.stopName) lat (\(lat)) below Staten Island")
            XCTAssertLessThanOrEqual(lat, 40.66, "Stop \(stop.stopName) lat (\(lat)) above Staten Island")
            XCTAssertGreaterThanOrEqual(lon, -74.20, "Stop \(stop.stopName) lon (\(lon)) west of Staten Island")
            XCTAssertLessThanOrEqual(lon, -74.04, "Stop \(stop.stopName) lon (\(lon)) east of Staten Island")

            // Explicitly assert none are at Times Square / Midtown Manhattan (40.7580, -73.9855)
            let distToTimesSq = abs(lat - 40.7580) + abs(lon - (-73.9855))
            XCTAssertGreaterThan(distToTimesSq, 0.10, "Stop \(stop.stopName) must not be in Midtown Manhattan")
        }
    }

    // MARK: - 3. Directional Progression Ordering

    func testS51DirectionalProgressionOrder() async throws {
        // Direction 1 (Southbound): starts at St George Ferry (north) and heads south towards Midland Beach
        let southbound = try await SpatialDatabaseManager.shared.fetchRouteStopLadder(
            routeId: "S51",
            directionId: 1,
            currentStopId: "200153"
        )
        guard let sbFirst = southbound.first, let sbLast = southbound.last else {
            XCTFail("Southbound ladder must not be empty")
            return
        }
        XCTAssertGreaterThan(sbFirst.coordinate.latitude, sbLast.coordinate.latitude,
                             "Southbound S51 must start further North (St George) than it ends (Midland Beach)")

        // Direction 0 (Northbound): starts at Midland Beach (south) and heads north towards St George Ferry
        let northbound = try await SpatialDatabaseManager.shared.fetchRouteStopLadder(
            routeId: "S51",
            directionId: 0,
            currentStopId: "200153"
        )
        guard let nbFirst = northbound.first, let nbLast = northbound.last else {
            XCTFail("Northbound ladder must not be empty")
            return
        }
        XCTAssertLessThan(nbFirst.coordinate.latitude, nbLast.coordinate.latitude,
                          "Northbound S51 must start further South (Midland Beach) than it ends (St George)")
    }

    // MARK: - 4. East-West Crosstown Progression Ordering

    func testEastWestCrosstownProgressionOrder() async throws {
        // M23 / M23-SBS runs East-West along 23rd Street in Manhattan
        let ladder = try await SpatialDatabaseManager.shared.fetchRouteStopLadder(
            routeId: "M23-SBS",
            directionId: 1, // Westbound
            currentStopId: "401000" // Fallback ID
        )

        if !ladder.isEmpty && ladder.count >= 2 {
            let lats = ladder.map(\.coordinate.latitude)
            let lons = ladder.map(\.coordinate.longitude)
            let latSpan = (lats.max() ?? 0) - (lats.min() ?? 0)
            let lonSpan = (lons.max() ?? 0) - (lons.min() ?? 0)

            XCTAssertGreaterThan(lonSpan, latSpan, "M23-SBS corridor must be predominantly East-West")

            // Direction 1 (Westbound): should progress West (longitude becoming more negative)
            let firstLon = ladder.first!.coordinate.longitude
            let lastLon = ladder.last!.coordinate.longitude
            XCTAssertGreaterThan(firstLon, lastLon, "Westbound crosstown bus must start further East than it ends")
        }
    }

    // MARK: - 5. Tapped Stop Fallback Anchoring (No Database Corridor Stops)

    func testTappedStopFallbackAnchor() async throws {
        // Query an unmapped route at known Staten Island stop 200153
        let fallbackLadder = try await SpatialDatabaseManager.shared.fetchRouteStopLadder(
            routeId: "UNMAPPED_SHUTTLE_999",
            directionId: 0,
            currentStopId: "200153",
            currentArrivalMinutes: 7
        )

        XCTAssertEqual(fallbackLadder.count, 1, "Fallback should return single anchor stop for tapped station")
        let stop = fallbackLadder[0]
        XCTAssertEqual(stop.stopId, "200153")
        XCTAssertEqual(stop.stopName, "Bay St & Victory Blvd")
        XCTAssertEqual(stop.estimatedMinutes, 7)
        XCTAssertTrue(stop.isCurrent)
        XCTAssertTrue(stop.isTerminus)

        // Coordinates must be the actual Staten Island coordinates, NOT Midtown Manhattan
        XCTAssertEqual(stop.coordinate.latitude, 40.6375, accuracy: 0.01)
        XCTAssertEqual(stop.coordinate.longitude, -74.0760, accuracy: 0.01)
    }

    func testTappedCoordinateExplicitFallback() async throws {
        // When stop ID is completely unknown to database, use explicit tappedCoordinate
        let explicitCoord = CLLocationCoordinate2D(latitude: 40.5800, longitude: -74.0900)
        let ladder = try await SpatialDatabaseManager.shared.fetchRouteStopLadder(
            routeId: "UNKNOWN_BUS",
            directionId: 0,
            currentStopId: "SYNTHETIC_STOP_001",
            currentArrivalMinutes: 4,
            tappedCoordinate: explicitCoord
        )

        XCTAssertEqual(ladder.count, 1)
        XCTAssertEqual(ladder[0].coordinate.latitude, explicitCoord.latitude, accuracy: 0.0001)
        XCTAssertEqual(ladder[0].coordinate.longitude, explicitCoord.longitude, accuracy: 0.0001)
    }

    // MARK: - 6. Camera Safety Invariant & Bounding Box

    func testSurfaceInspectorCommandCameraBoundsStatenIsland() async throws {
        let ladder = try await SpatialDatabaseManager.shared.fetchRouteStopLadder(
            routeId: "S51",
            directionId: 1,
            currentStopId: "200153"
        )
        guard let station = ladder.first(where: { $0.isCurrent })?.coordinate else {
            XCTFail("Station coordinate must be found")
            return
        }

        let cmd = RouteInspectionCommand(
            routeId: "S51",
            lineName: "S51 Local",
            agencyColorHex: "#00A1DE",
            modalClass: .bus,
            coordinates: ladder.map(\.coordinate),
            stationCoordinate: station
        )

        let bounds = cmd.computedBoundingBox()
        XCTAssertNotNil(bounds)
        guard let b = bounds else { return }

        // Bounding box must be strictly within Staten Island
        XCTAssertGreaterThanOrEqual(b.sw.latitude, 40.54, "SW latitude must be in Staten Island")
        XCTAssertLessThanOrEqual(b.ne.latitude, 40.66, "NE latitude must be in Staten Island")
        XCTAssertGreaterThanOrEqual(b.sw.longitude, -74.15, "SW longitude must be in Staten Island")
        XCTAssertLessThanOrEqual(b.ne.longitude, -74.04, "NE longitude must be in Staten Island")

        // Crucial: Times Square (40.7580, -73.9855) must NOT be enclosed
        let enclosesTimesSquare = b.sw.latitude <= 40.7580 && b.ne.latitude >= 40.7580 &&
                                  b.sw.longitude <= -73.9855 && b.ne.longitude >= -73.9855
        XCTAssertFalse(enclosesTimesSquare, "Camera Safety Invariant VIOLATION: S51 camera bounds must never enclose Times Square")
    }

    // MARK: - 7. Guideway Subway Regression Check

    func testSubwayLine1ProgressionRegression() async throws {
        let ladder = try await SpatialDatabaseManager.shared.fetchRouteStopLadder(
            routeId: "1",
            directionId: 0,
            currentStopId: "127", // Times Sq - 42 St
            currentArrivalMinutes: 4
        )

        XCTAssertFalse(ladder.isEmpty, "Subway Line 1 must resolve stops from scheduled_hourly_patterns")
        XCTAssertTrue(ladder.contains(where: { $0.isCurrent }))

        if let current = ladder.first(where: { $0.isCurrent }) {
            XCTAssertEqual(current.estimatedMinutes, 4)
            XCTAssertFalse(current.isPassed)
        }
    }
}
