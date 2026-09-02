import XCTest
import SwiftUI
@testable import Derivee
@testable import DeriveeCore

final class RouteComparisonViewModelBridgeTests: XCTestCase {

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

    func testViewModelWithNilBridgeLoadsDefaultFixtures() async {
        let vm = await MainActor.run { RouteComparisonViewModel() }
        await MainActor.run {
            XCTAssertFalse(vm.allJourneys.isEmpty)
            XCTAssertEqual(vm.allJourneys.count, 5)
            XCTAssertFalse(vm.filteredJourneys.isEmpty)
            XCTAssertNil(vm.bridge)
        }
    }

    func testViewModelLiveSearchExecution() async {
        let metadata = DefaultStopMetadataProvider(
            stopNames: [0: "Astor Place", 1: "14 St - Union Sq", 2: "Grand Central - 42 St"],
            routeNames: [0: "6"]
        )
        let bridge = RoutingEngineBridge(metadataProvider: metadata)
        let blob = buildSyntheticTimetable()
        await bridge.loadTimetableBlob(blob)

        let vm = await MainActor.run { RouteComparisonViewModel(bridge: bridge) }

        let origin = RoutingLocation.coordinate(latitude: 40.7302, longitude: -73.9922, name: "Astor Pl Vicinity")
        let dest = RoutingLocation.coordinate(latitude: 40.7525, longitude: -73.9775, name: "Grand Central Vicinity")

        let calendar = Calendar.current
        var comps = DateComponents()
        comps.hour = 7
        comps.minute = 58
        comps.second = 0
        let depDate = calendar.date(from: comps) ?? Date()

        await vm.searchJourneys(origin: origin, destination: dest, departureTime: depDate)

        await MainActor.run {
            XCTAssertFalse(vm.isLoading)
            XCTAssertGreaterThan(vm.executionLatencyMs, 0.0)
            XCTAssertFalse(vm.allJourneys.isEmpty)
            XCTAssertEqual(vm.originName, "Astor Pl Vicinity")
            XCTAssertEqual(vm.destinationName, "Grand Central Vicinity")

            // Test profile switching updates filtered journeys
            vm.selectProfile(.fastest)
            XCTAssertEqual(vm.selectedProfile, .fastest)
            XCTAssertFalse(vm.filteredJourneys.isEmpty)
        }
    }
}
