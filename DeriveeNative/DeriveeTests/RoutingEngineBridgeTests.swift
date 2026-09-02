import XCTest
import CxxStdlib
@testable import Derivee
@testable import DeriveeCore

final class RoutingEngineBridgeTests: XCTestCase {

    private func buildSyntheticTimetable() -> Data {
        func align64(_ offset: Int) -> Int {
            let rem = offset % 64
            return rem == 0 ? offset : offset + (64 - rem)
        }

        let stops = [
            Stop(40.7300, -73.9925, 0, 0, 1, 0), // Stop 0 (Astor Place)
            Stop(40.7359, -73.9911, 1, 0, 1, 0), // Stop 1 (Union Sq)
            Stop(40.7527, -73.9772, 2, 0, 1, 0)  // Stop 2 (Grand Central)
        ]
        let routes = [Route(0, 0, 1, 3)] // Route 0 with 3 stops
        let trips = [Trip(0, 3, 1)]      // Trip 0
        let stopTimes = [
            StopTime(28800, 28800, 0), // 08:00:00 at Stop 0
            StopTime(29100, 29100, 1), // 08:05:00 at Stop 1
            StopTime(29700, 29700, 2)  // 08:15:00 at Stop 2
        ]
        let stopRoutes: [UInt32] = [0, 0, 0]
        let routeStops: [UInt32] = [0, 1, 2]

        let headerSize = 232
        let lenS0 = stops.count * MemoryLayout<Stop>.size
        let lenS1 = routes.count * MemoryLayout<Route>.size
        let lenS2 = trips.count * MemoryLayout<Trip>.size
        let lenS3 = stopTimes.count * MemoryLayout<StopTime>.size
        let lenS4 = 0
        let lenS5 = stopRoutes.count * MemoryLayout<UInt32>.size
        let lenS6 = routeStops.count * MemoryLayout<UInt32>.size

        let offS0 = align64(headerSize)
        let offS1 = align64(offS0 + lenS0)
        let offS2 = align64(offS1 + lenS1)
        let offS3 = align64(offS2 + lenS2)
        let offS4 = align64(offS3 + lenS3)
        let offS5 = align64(offS4 + lenS4)
        let offS6 = align64(offS5 + lenS5)
        let totalSize = align64(offS6 + lenS6)

        var data = Data(count: totalSize)
        data.withUnsafeMutableBytes { rawBuf in
            let ptr = rawBuf.baseAddress!
            ptr.storeBytes(of: UInt32(0x31565244), toByteOffset: 0, as: UInt32.self)
            ptr.storeBytes(of: UInt32(1), toByteOffset: 4, as: UInt32.self)
            ptr.storeBytes(of: UInt32(0x01020304), toByteOffset: 8, as: UInt32.self)
            ptr.storeBytes(of: UInt32(232), toByteOffset: 12, as: UInt32.self)
            ptr.storeBytes(of: UInt64(totalSize), toByteOffset: 16, as: UInt64.self)
            ptr.storeBytes(of: UInt64(0), toByteOffset: 24, as: UInt64.self)
            ptr.storeBytes(of: UInt32(7), toByteOffset: 32, as: UInt32.self)
            ptr.storeBytes(of: UInt32(0), toByteOffset: 36, as: UInt32.self)

            func writeTOC(index: Int, offset: Int, size: Int, count: Int) {
                let tocBase = 40 + index * 24
                ptr.storeBytes(of: UInt64(offset), toByteOffset: tocBase, as: UInt64.self)
                ptr.storeBytes(of: UInt64(size), toByteOffset: tocBase + 8, as: UInt64.self)
                ptr.storeBytes(of: UInt64(count), toByteOffset: tocBase + 16, as: UInt64.self)
            }

            writeTOC(index: 0, offset: offS0, size: lenS0, count: stops.count)
            writeTOC(index: 1, offset: offS1, size: lenS1, count: routes.count)
            writeTOC(index: 2, offset: offS2, size: lenS2, count: trips.count)
            writeTOC(index: 3, offset: offS3, size: lenS3, count: stopTimes.count)
            writeTOC(index: 4, offset: offS4, size: lenS4, count: 0)
            writeTOC(index: 5, offset: offS5, size: lenS5, count: stopRoutes.count)
            writeTOC(index: 6, offset: offS6, size: lenS6, count: routeStops.count)

            for (i, s) in stops.enumerated() {
                ptr.storeBytes(of: s, toByteOffset: offS0 + i * MemoryLayout<Stop>.size, as: Stop.self)
            }
            for (i, r) in routes.enumerated() {
                ptr.storeBytes(of: r, toByteOffset: offS1 + i * MemoryLayout<Route>.size, as: Route.self)
            }
            for (i, t) in trips.enumerated() {
                ptr.storeBytes(of: t, toByteOffset: offS2 + i * MemoryLayout<Trip>.size, as: Trip.self)
            }
            for (i, st) in stopTimes.enumerated() {
                ptr.storeBytes(of: st, toByteOffset: offS3 + i * MemoryLayout<StopTime>.size, as: StopTime.self)
            }
            for (i, sr) in stopRoutes.enumerated() {
                ptr.storeBytes(of: sr, toByteOffset: offS5 + i * MemoryLayout<UInt32>.size, as: UInt32.self)
            }
            for (i, rs) in routeStops.enumerated() {
                ptr.storeBytes(of: rs, toByteOffset: offS6 + i * MemoryLayout<UInt32>.size, as: UInt32.self)
            }
        }
        return data
    }

    func testBridgeInitializationAndBlobLoading() async {
        let bridge = RoutingEngineBridge()
        let isLoadedInitial = await bridge.isLoaded
        XCTAssertFalse(isLoadedInitial)

        let blob = buildSyntheticTimetable()
        let loaded = await bridge.loadTimetableBlob(blob)
        XCTAssertTrue(loaded)

        let isLoadedAfter = await bridge.isLoaded
        XCTAssertTrue(isLoadedAfter)

        let stopsCount = await bridge.stopsCount
        let routesCount = await bridge.routesCount
        let tripsCount = await bridge.tripsCount
        XCTAssertEqual(stopsCount, 3)
        XCTAssertEqual(routesCount, 1)
        XCTAssertEqual(tripsCount, 1)
    }

    func testStopToStopQuery() async {
        let metadata = DefaultStopMetadataProvider(
            stopNames: [0: "Astor Place", 1: "14 St - Union Sq", 2: "Grand Central - 42 St"],
            routeNames: [0: "6"]
        )
        let bridge = RoutingEngineBridge(metadataProvider: metadata)
        let blob = buildSyntheticTimetable()
        await bridge.loadTimetableBlob(blob)

        let itineraries = await bridge.computeStopToStopJourney(
            originStopId: 0,
            destinationStopId: 2,
            departureTimestampSec: 28800
        )

        XCTAssertEqual(itineraries.count, 1)
        let journey = itineraries[0]
        XCTAssertEqual(journey.departureTimeSec, 28800)
        XCTAssertEqual(journey.arrivalTimeSec, 29700)
        XCTAssertEqual(journey.legs.count, 1)
        XCTAssertEqual(journey.legs[0].routeId, "6")
        XCTAssertEqual(journey.legs[0].originName, "Astor Place")
        XCTAssertEqual(journey.legs[0].destinationName, "Grand Central - 42 St")
    }

    func testCoordinateToCoordinateQueryWithWalkTransfers() async {
        let metadata = DefaultStopMetadataProvider(
            stopNames: [0: "Astor Place", 1: "14 St - Union Sq", 2: "Grand Central - 42 St"],
            exitCodes: [2: "Exit 4B"],
            landmarkCues: [0: "Subway stairs next to Alamo Cube"],
            routeNames: [0: "6"]
        )
        let bridge = RoutingEngineBridge(metadataProvider: metadata)
        let blob = buildSyntheticTimetable()
        await bridge.loadTimetableBlob(blob)

        // Query starting 100m from Astor Place (40.7305, -73.9920) to 100m from Grand Central (40.7530, -73.9770)
        let origin = RoutingLocation.coordinate(latitude: 40.7305, longitude: -73.9920, name: "Origin Coffee Shop")
        let dest = RoutingLocation.coordinate(latitude: 40.7530, longitude: -73.9770, name: "Destination Office")

        var options = RoutingOptions.default
        options.includeDirectWalk = false // Force transit evaluation

        let calendar = Calendar.current
        var comps = DateComponents()
        comps.hour = 7
        comps.minute = 58 // 7:58 AM (28,680s) -> 2m walk to Stop 0 arrives at 8:00 AM (28,800s)
        comps.second = 0
        let depDate = calendar.date(from: comps) ?? Date()

        let itineraries = await bridge.computeJourneys(
            origin: origin,
            destination: dest,
            departureTime: depDate,
            profile: .mostReliable,
            options: options
        )

        XCTAssertFalse(itineraries.isEmpty)
        let topJourney = itineraries[0]
        XCTAssertGreaterThanOrEqual(topJourney.legs.count, 2)

        // First leg should be walk
        XCTAssertEqual(topJourney.legs.first?.mode, .walk)
        XCTAssertEqual(topJourney.legs.first?.originName, "Origin Coffee Shop")
        XCTAssertEqual(topJourney.legs.first?.landmarkCue, "Subway stairs next to Alamo Cube")

        // Transit leg should be route 6
        let transitLeg = topJourney.legs.first(where: { $0.mode == .subway })
        XCTAssertNotNil(transitLeg)
        XCTAssertEqual(transitLeg?.routeId, "6")

        // Final leg should be walk with exit code
        let lastLeg = topJourney.legs.last
        XCTAssertEqual(lastLeg?.mode, .walk)
        XCTAssertEqual(lastLeg?.exitCode, "Exit 4B")
    }

    func testDirectWalkItineraryDiscovery() async {
        let bridge = RoutingEngineBridge()
        let blob = buildSyntheticTimetable()
        await bridge.loadTimetableBlob(blob)

        // Origin and Destination within 300m
        let origin = RoutingLocation.coordinate(latitude: 40.7300, longitude: -73.9925, name: "Start Spot")
        let dest = RoutingLocation.coordinate(latitude: 40.7320, longitude: -73.9925, name: "Nearby Destination")

        let itineraries = await bridge.computeJourneys(
            origin: origin,
            destination: dest,
            profile: .fastest
        )

        XCTAssertFalse(itineraries.isEmpty)
        let walkOnly = itineraries.first(where: { $0.legs.count == 1 && $0.legs[0].mode == .walk })
        XCTAssertNotNil(walkOnly)
        XCTAssertEqual(walkOnly?.totalCost, 0.0)
    }

    func testRealtimeDelayAndDisruptionIntegration() async {
        let bridge = RoutingEngineBridge()
        let blob = buildSyntheticTimetable()
        await bridge.loadTimetableBlob(blob)

        // Register +120s delay on Trip 0
        await bridge.updateRealtimeDelay(tripId: 0, delaySeconds: 120)
        let delay = await bridge.getRealtimeDelay(tripId: 0)
        XCTAssertEqual(delay, 120)

        // Set Stop 1 disrupted
        await bridge.setStopDisrupted(stopId: 1, disrupted: true)
        let isActive = await bridge.isStopActive(stopId: 1)
        XCTAssertFalse(isActive)

        // Clear disruptions
        await bridge.clearDisruptions()
        let isNowActive = await bridge.isStopActive(stopId: 1)
        XCTAssertTrue(isNowActive)
    }
}
