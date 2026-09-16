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

    // MARK: - 8. Wave PD.5: Surface Bus Corridor Progression & Map Sawtooth Elimination

    func testB32NorthboundCorridorProgressionKentAv() async throws {
        let ladder = try await SpatialDatabaseManager.shared.fetchRouteStopLadder(
            routeId: "B32",
            directionId: 0, // Northbound to Long Island City - Queens Plaza
            currentStopId: "308667", // Kent Av & N 6 St
            currentArrivalMinutes: 4
        )

        XCTAssertFalse(ladder.isEmpty, "B32 Northbound ladder must return real stops")
        XCTAssertGreaterThan(ladder.count, 10, "B32 corridor should have substantial stops")

        // 1. Current stop resolution at Kent Av & N 6 St
        let currentStop = ladder.first(where: { $0.isCurrent })
        XCTAssertNotNil(currentStop, "Current stop must be identified in stop ladder")
        XCTAssertEqual(currentStop?.stopId, "308667")
        XCTAssertEqual(currentStop?.stopName, "Kent Av & N 6 St")
        XCTAssertEqual(currentStop?.estimatedMinutes, 4)

        // 2. Must contain Northbound corridor stops along Kent Av
        let stopNames = ladder.map(\.stopName)
        XCTAssertTrue(stopNames.contains("Kent Av & S 6 St") || stopNames.contains("Kent Av & S 1 St"),
                      "Must contain Kent Av South Williamsburg stops")
        XCTAssertTrue(stopNames.contains("Kent Av & Metropolitan Av"), "Must contain Kent Av & Metropolitan Av")
        XCTAssertTrue(stopNames.contains("Kent Av & N 6 St"), "Must contain Kent Av & N 6 St")
        XCTAssertTrue(stopNames.contains("Kent Av & N 9 St"), "Must contain Kent Av & N 9 St")

        // 3. ZERO Wythe Av stops in Northbound ladder (Wythe Av is Southbound only)
        for stop in ladder {
            XCTAssertFalse(stop.stopName.lowercased().contains("wythe av"),
                           "Northbound B32 ladder must NOT contain Southbound Wythe Av stop: \(stop.stopName)")
        }

        // 4. ZERO 21 St stops in Northbound ladder (21 St is Southbound only)
        for stop in ladder {
            XCTAssertFalse(stop.stopName.lowercased().contains("21 st"),
                           "Northbound B32 ladder must NOT contain Southbound 21 St stop: \(stop.stopName)")
        }

        // 5. In Queens, must use 11 St, NOT 21 St
        XCTAssertTrue(stopNames.contains("11 St & 47 Av") || stopNames.contains("11 St & Jackson Av"),
                      "Northbound B32 must contain 11 St stops in Long Island City")

        // 6. Strict South-to-North monotonic progression
        for i in 0..<(ladder.count - 1) {
            let latA = ladder[i].coordinate.latitude
            let latB = ladder[i + 1].coordinate.latitude
            XCTAssertLessThanOrEqual(latA, latB + 0.001,
                                     "Northbound progression must move South to North: stop \(ladder[i].stopName) (\(latA)) -> \(ladder[i+1].stopName) (\(latB))")
        }
    }

    func testB32SouthboundCorridorProgressionWytheAv() async throws {
        let ladder = try await SpatialDatabaseManager.shared.fetchRouteStopLadder(
            routeId: "B32",
            directionId: 1, // Southbound to Williamsburg Bridge Plaza
            currentStopId: "308682", // Wythe Av & N 6 St
            currentArrivalMinutes: 6
        )

        XCTAssertFalse(ladder.isEmpty, "B32 Southbound ladder must return real stops")
        XCTAssertGreaterThan(ladder.count, 10, "B32 corridor should have substantial stops")

        // 1. Current stop resolution at Wythe Av & N 6 St
        let currentStop = ladder.first(where: { $0.isCurrent })
        XCTAssertNotNil(currentStop, "Current stop must be identified in stop ladder")
        XCTAssertEqual(currentStop?.stopId, "308682")
        XCTAssertEqual(currentStop?.stopName, "Wythe Av & N 6 St")
        XCTAssertEqual(currentStop?.estimatedMinutes, 6)

        // 2. Must contain Southbound corridor stops along Wythe Av
        let stopNames = ladder.map(\.stopName)
        XCTAssertTrue(stopNames.contains("Wythe Av & N 12 St") || stopNames.contains("Wythe Av & N 9 St"),
                      "Must contain Wythe Av North Williamsburg stops")
        XCTAssertTrue(stopNames.contains("Wythe Av & N 6 St"), "Must contain Wythe Av & N 6 St")
        XCTAssertTrue(stopNames.contains("Wythe Av & Metropolitan Av"), "Must contain Wythe Av & Metropolitan Av")
        XCTAssertTrue(stopNames.contains("Wythe Av & Grand St") || stopNames.contains("Wythe Av & S 3 St"),
                      "Must contain Wythe Av South Williamsburg stops")

        // 3. ZERO Kent Av stops in Southbound ladder (Kent Av is Northbound only)
        for stop in ladder {
            XCTAssertFalse(stop.stopName.lowercased().contains("kent av"),
                           "Southbound B32 ladder must NOT contain Northbound Kent Av stop: \(stop.stopName)")
        }

        // 4. ZERO 11 St stops in Southbound ladder (11 St is Northbound only)
        for stop in ladder {
            XCTAssertFalse(stop.stopName.lowercased().contains("11 st &") || stop.stopName.lowercased().hasPrefix("11 st"),
                           "Southbound B32 ladder must NOT contain Northbound 11 St stop: \(stop.stopName)")
        }

        // 5. In Queens, must use 21 St / Jackson Av
        XCTAssertTrue(stopNames.contains("21 St & 44 Dr") || stopNames.contains("21 St & 45 Rd") || stopNames.contains("Jackson Av & 47 Av"),
                      "Southbound B32 must contain 21 St / Jackson Av stops in Long Island City")

        // 6. Strict North-to-South monotonic progression
        for i in 0..<(ladder.count - 1) {
            let latA = ladder[i].coordinate.latitude
            let latB = ladder[i + 1].coordinate.latitude
            XCTAssertGreaterThanOrEqual(latA + 0.001, latB,
                                        "Southbound progression must move North to South: stop \(ladder[i].stopName) (\(latA)) -> \(ladder[i+1].stopName) (\(latB))")
        }
    }

    func testB32MapPolylineSawtoothElimination() async throws {
        let nbLadder = try await SpatialDatabaseManager.shared.fetchRouteStopLadder(
            routeId: "B32",
            directionId: 0,
            currentStopId: "308667"
        )
        let sbLadder = try await SpatialDatabaseManager.shared.fetchRouteStopLadder(
            routeId: "B32",
            directionId: 1,
            currentStopId: "308682"
        )

        // Helper to check for lateral back-and-forth zig-zags between Kent Av and Wythe Av
        // Kent Av lon is ~ -73.966 to -73.962; Wythe Av lon is ~ -73.965 to -73.957.
        // A sawtooth between Kent and Wythe across blocks creates alternating east-west jumps of >150 meters.
        for (name, ladder) in [("Northbound", nbLadder), ("Southbound", sbLadder)] {
            // Filter to Williamsburg segment (latitudes 40.711 to 40.724)
            let wburgStops = ladder.filter { $0.coordinate.latitude >= 40.711 && $0.coordinate.latitude <= 40.724 }
            XCTAssertGreaterThanOrEqual(wburgStops.count, 4, "\(name) should have at least 4 stops in Williamsburg")

            // Verify that all Williamsburg stops stay consistently on either Kent or Wythe
            let isKent = wburgStops.allSatisfy { $0.stopName.contains("Kent") }
            let isWythe = wburgStops.allSatisfy { $0.stopName.contains("Wythe") }
            XCTAssertTrue(isKent || isWythe,
                          "Sawtooth Elimination: \(name) stops in Williamsburg must strictly stay on a single thoroughfare (all Kent or all Wythe)")

            // Check that consecutive stops do not have wild lateral jumps (distance between adjacent stops < 800m)
            for i in 0..<(wburgStops.count - 1) {
                let locA = CLLocation(latitude: wburgStops[i].coordinate.latitude, longitude: wburgStops[i].coordinate.longitude)
                let locB = CLLocation(latitude: wburgStops[i+1].coordinate.latitude, longitude: wburgStops[i+1].coordinate.longitude)
                let dist = locA.distance(from: locB)
                XCTAssertLessThan(dist, 600, "\(name) consecutive stop jump \(dist)m between \(wburgStops[i].stopName) and \(wburgStops[i+1].stopName) exceeds threshold")
            }
        }
    }

    func testCrossStreetUniquenessPreservation() async throws {
        let nbLadder = try await SpatialDatabaseManager.shared.fetchRouteStopLadder(
            routeId: "B32",
            directionId: 0,
            currentStopId: "308667"
        )
        let sbLadder = try await SpatialDatabaseManager.shared.fetchRouteStopLadder(
            routeId: "B32",
            directionId: 1,
            currentStopId: "308682"
        )

        for (name, ladder) in [("Northbound", nbLadder), ("Southbound", sbLadder)] {
            var seenCross = Set<String>()
            for stop in ladder {
                let (_, cross) = SpatialDatabaseManager.shared.parseStopThoroughfareAndCrossStreet(stop.stopName)
                let key = SpatialDatabaseManager.shared.normalizeCrossStreetKey(cross)
                if !key.isEmpty {
                    XCTAssertFalse(seenCross.contains(key),
                                   "\(name) ladder has duplicate cross street '\(cross)' (key: '\(key)') at stop \(stop.stopName)")
                    seenCross.insert(key)
                }
            }
        }
    }

    func testCorridorProgressionEngineHelperParsing() {
        let (thoroughfare1, cross1) = SpatialDatabaseManager.shared.parseStopThoroughfareAndCrossStreet("Kent Av & N 6 St")
        XCTAssertEqual(thoroughfare1, "Kent Av")
        XCTAssertEqual(cross1, "N 6 St")

        let (thoroughfare2, cross2) = SpatialDatabaseManager.shared.parseStopThoroughfareAndCrossStreet("N 14 St & Kent Av")
        XCTAssertEqual(thoroughfare2, "Kent Av")
        XCTAssertEqual(cross2, "N 14 St")

        let key1 = SpatialDatabaseManager.shared.normalizeCrossStreetKey("N 6th St")
        let key2 = SpatialDatabaseManager.shared.normalizeCrossStreetKey("N 6 St")
        XCTAssertEqual(key1, key2)

        let key3 = SpatialDatabaseManager.shared.normalizeCrossStreetKey("Metropolitan Ave")
        let key4 = SpatialDatabaseManager.shared.normalizeCrossStreetKey("Metropolitan Av")
        XCTAssertEqual(key3, key4)
    }
}

