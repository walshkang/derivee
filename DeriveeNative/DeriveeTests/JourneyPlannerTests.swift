import XCTest
import GRDB
import CoreLocation
@testable import Derivee
@testable import DeriveeCore

final class JourneyPlannerTests: XCTestCase {

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
        let routes = [Route(0, 0, 1, 3)]
        let trips = [Trip(0, 3, 1)]
        let stopTimes = [
            StopTime(28800, 28800, 0),
            StopTime(29100, 29100, 1),
            StopTime(29700, 29700, 2)
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

    // MARK: - Tests

    @MainActor
    func testPlannerInitialState() {
        let planner = JourneyPlanner()
        XCTAssertFalse(planner.isReady)
        XCTAssertFalse(planner.isLoading)
        XCTAssertEqual(planner.activeCitySlug, "")
        XCTAssertTrue(planner.currentJourneys.isEmpty)
        XCTAssertNil(planner.selectedJourney)
        XCTAssertEqual(planner.selectedProfile, .mostReliable)
        XCTAssertEqual(planner.executionLatencyMs, 0.0)
        XCTAssertNil(planner.lastError)
    }

    @MainActor
    func testPlannerJourneyExecutionAndStateReactivity() async {
        let metadata = DefaultStopMetadataProvider(
            stopNames: [0: "Astor Place", 1: "14 St - Union Sq", 2: "Grand Central - 42 St"],
            exitCodes: [2: "Exit 4B"],
            landmarkCues: [0: "Subway stairs near Alamo Cube"],
            routeNames: [0: "6"]
        )
        let bridge = RoutingEngineBridge(metadataProvider: metadata)
        let blob = buildSyntheticTimetable()
        await bridge.loadTimetableBlob(blob)

        let planner = JourneyPlanner(bridge: bridge, metadataProvider: metadata)

        let origin = RoutingLocation.coordinate(latitude: 40.7305, longitude: -73.9920, name: "Origin Cafe")
        let dest = RoutingLocation.coordinate(latitude: 40.7530, longitude: -73.9770, name: "Grand Central HQ")

        let calendar = Calendar.current
        var comps = DateComponents()
        comps.hour = 7
        comps.minute = 58
        comps.second = 0
        let depDate = calendar.date(from: comps) ?? Date()

        var options = RoutingOptions.default
        options.includeDirectWalk = false

        let results = await planner.planJourneys(
            origin: origin,
            destination: dest,
            departureTime: depDate,
            profile: .mostReliable,
            options: options
        )

        XCTAssertFalse(results.isEmpty)
        XCTAssertEqual(planner.currentJourneys.count, results.count)
        XCTAssertNotNil(planner.selectedJourney)
        XCTAssertFalse(planner.isLoading)
        XCTAssertGreaterThan(planner.executionLatencyMs, 0.0)

        let topJourney = results[0]
        XCTAssertGreaterThanOrEqual(topJourney.legs.count, 2)
        XCTAssertEqual(topJourney.legs.first?.mode, .walk)
        XCTAssertEqual(topJourney.legs.first?.landmarkCue, "Subway stairs near Alamo Cube")

        let subwayLeg = topJourney.legs.first(where: { $0.mode == .subway })
        XCTAssertNotNil(subwayLeg)
        XCTAssertEqual(subwayLeg?.routeId, "6")
    }

    @MainActor
    func testPlannerProfileSelection() async {
        let metadata = DefaultStopMetadataProvider(
            stopNames: [0: "Astor Place", 1: "14 St - Union Sq", 2: "Grand Central - 42 St"],
            routeNames: [0: "6"]
        )
        let bridge = RoutingEngineBridge(metadataProvider: metadata)
        let blob = buildSyntheticTimetable()
        await bridge.loadTimetableBlob(blob)

        let planner = JourneyPlanner(bridge: bridge, metadataProvider: metadata)
        planner.selectProfile(.fastest)
        XCTAssertEqual(planner.selectedProfile, .fastest)

        planner.selectProfile(.fewestTransfers)
        XCTAssertEqual(planner.selectedProfile, .fewestTransfers)

        planner.selectProfile(.stepFree)
        XCTAssertEqual(planner.selectedProfile, .stepFree)

        planner.selectProfile(.multiModalBikeRail)
        XCTAssertEqual(planner.selectedProfile, .multiModalBikeRail)
    }

    @MainActor
    func testPlannerRealtimeDelayForwarding() async {
        let bridge = RoutingEngineBridge()
        let blob = buildSyntheticTimetable()
        await bridge.loadTimetableBlob(blob)

        let planner = JourneyPlanner(bridge: bridge)

        await planner.updateRealtimeDelay(tripId: 0, delaySeconds: 240)
        let recordedDelay = await bridge.getRealtimeDelay(tripId: 0)
        XCTAssertEqual(recordedDelay, 240)

        await planner.clearRealtimeDelays()
        let clearedDelay = await bridge.getRealtimeDelay(tripId: 0)
        XCTAssertEqual(clearedDelay, 0)
    }

    @MainActor
    func testPlannerDisruptionSyncFromTransitEngine() async throws {
        let testTransitEngine = TransitDatabaseEngine.makeForTesting(inMemory: true)
        let bridge = RoutingEngineBridge()
        let blob = buildSyntheticTimetable()
        await bridge.loadTimetableBlob(blob)

        let planner = JourneyPlanner(bridge: bridge, transitEngine: testTransitEngine)

        // Insert a service disruption on Stop 1
        let disruption = ServiceDisruptionRecord(
            id: "disp_1",
            routeId: "6",
            stopId: "1",
            directionId: 0,
            startEpoch: 1000,
            endEpoch: 9000,
            disruptionType: .maintenance,
            summaryText: "Station closed for maintenance"
        )
        try await testTransitEngine.insertServiceDisruptions([disruption])

        // Verify stop is initially active
        let beforeActive = await bridge.isStopActive(stopId: 1)
        XCTAssertTrue(beforeActive)

        // Sync disruptions at epoch 5000 (within [1000, 9000])
        await planner.syncActiveDisruptions(epoch: 5000)

        // Stop 1 should now be marked as disrupted
        let afterActive = await bridge.isStopActive(stopId: 1)
        XCTAssertFalse(afterActive)
    }

    @MainActor
    func testPlannerPrepareForCitySwap() async {
        let bridge = RoutingEngineBridge()
        let blob = buildSyntheticTimetable()
        await bridge.loadTimetableBlob(blob)

        let planner = JourneyPlanner(bridge: bridge)
        await planner.updateRealtimeDelay(tripId: 0, delaySeconds: 120)

        await planner.prepareForCitySwap()

        XCTAssertFalse(planner.isReady)
        XCTAssertTrue(planner.currentJourneys.isEmpty)
        XCTAssertNil(planner.selectedJourney)

        let delayAfter = await bridge.getRealtimeDelay(tripId: 0)
        XCTAssertEqual(delayAfter, 0)
    }

    func testSpatialDatabaseStopMetadataProviderWarming() async throws {
        var config = Configuration()
        config.qos = .userInitiated
        let queue = try DatabaseQueue(configuration: config)

        try await queue.write { db in
            try db.execute(sql: """
                CREATE TABLE stops (
                    stop_id TEXT PRIMARY KEY NOT NULL,
                    stop_name TEXT NOT NULL,
                    stop_lat REAL NOT NULL,
                    stop_lon REAL NOT NULL,
                    parent_station TEXT
                );
                CREATE TABLE routes (
                    route_id TEXT PRIMARY KEY NOT NULL,
                    route_short_name TEXT,
                    route_long_name TEXT
                );

                INSERT INTO stops (stop_id, stop_name, stop_lat, stop_lon) VALUES
                    ('101', 'Astor Place', 40.7300, -73.9925),
                    ('102', '14 St - Union Sq', 40.7359, -73.9911),
                    ('103', 'Grand Central', 40.7527, -73.9772);

                INSERT INTO routes (route_id, route_short_name, route_long_name) VALUES
                    ('6', '6', 'Lexington Avenue Local'),
                    ('L', 'L', '14th Street-Canarsie Local');
            """)
        }

        let provider = SpatialDatabaseStopMetadataProvider()
        try await provider.warm(using: queue, isAttachedMode: false)

        XCTAssertEqual(provider.totalStopsCount, 3)
        XCTAssertEqual(provider.totalRoutesCount, 2)

        // Sorted by stop_id ASC: 0 -> '101', 1 -> '102', 2 -> '103'
        XCTAssertEqual(provider.stopName(for: 0), "Astor Place")
        XCTAssertEqual(provider.stopName(for: 1), "14 St - Union Sq")
        XCTAssertEqual(provider.stopName(for: 2), "Grand Central")

        let coord0 = provider.stopCoordinate(for: 0)
        XCTAssertNotNil(coord0)
        XCTAssertEqual(coord0?.latitude ?? 0.0, 40.7300, accuracy: 0.0001)

        let exit0 = provider.exitCode(for: 0)
        XCTAssertNotNil(exit0)

        let cue1 = provider.landmarkCue(for: 1)
        XCTAssertNotNil(cue1)
        XCTAssertTrue(cue1?.contains("plaza") == true || cue1?.contains("square") == true)

        // Routes sorted by route_id ASC: 0 -> '6', 1 -> 'L'
        XCTAssertEqual(provider.routeName(for: 0), "6")
        XCTAssertEqual(provider.routeName(for: 1), "L")

        // Stop index lookup by string ID
        XCTAssertEqual(provider.indexOfStop(stopIdString: "101"), 0)
        XCTAssertEqual(provider.indexOfStop(stopIdString: "102"), 1)
        XCTAssertEqual(provider.indexOfStop(stopIdString: "103"), 2)
    }

    @MainActor
    func testRouteComparisonViewModelWithJourneyPlanner() async {
        let metadata = DefaultStopMetadataProvider(
            stopNames: [0: "Astor Place", 1: "14 St - Union Sq", 2: "Grand Central - 42 St"],
            routeNames: [0: "6"]
        )
        let bridge = RoutingEngineBridge(metadataProvider: metadata)
        let blob = buildSyntheticTimetable()
        await bridge.loadTimetableBlob(blob)

        let planner = JourneyPlanner(bridge: bridge, metadataProvider: metadata)
        let vm = RouteComparisonViewModel(planner: planner)

        XCTAssertNotNil(vm.planner)
        XCTAssertNotNil(vm.bridge)

        let origin = RoutingLocation.coordinate(latitude: 40.7302, longitude: -73.9922, name: "Astor Pl Vicinity")
        let dest = RoutingLocation.coordinate(latitude: 40.7525, longitude: -73.9775, name: "Grand Central Vicinity")

        let calendar = Calendar.current
        var comps = DateComponents()
        comps.hour = 7
        comps.minute = 58
        comps.second = 0
        let depDate = calendar.date(from: comps) ?? Date()

        await vm.searchJourneys(origin: origin, destination: dest, departureTime: depDate)

        XCTAssertFalse(vm.allJourneys.isEmpty)
        XCTAssertFalse(vm.filteredJourneys.isEmpty)
        XCTAssertEqual(vm.originName, "Astor Pl Vicinity")
        XCTAssertEqual(vm.destinationName, "Grand Central Vicinity")
    }
}
