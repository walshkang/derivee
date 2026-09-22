import XCTest
import CoreLocation
import SwiftUI
@testable import Derivee

final class TrainInspectorTests: XCTestCase {

    // MARK: - 1. Subterranean Egress Engine & Platform Car Positioning Tests

    func testSubterraneanEgressCuratedHubs() {
        // Times Sq-42 St (127)
        let tsExit = SubterraneanEgressEngine.resolvePrimaryExit(for: "127")
        XCTAssertEqual(tsExit.exitCode, "Exit 4B")
        XCTAssertTrue(tsExit.streetCorner.contains("42nd St & Broadway"))
        XCTAssertTrue(tsExit.isWheelchairAccessible)
        XCTAssertFalse(tsExit.isStairsOnly)
        
        let tsCar = SubterraneanEgressEngine.resolveCarRecommendation(for: "127")
        XCTAssertEqual(tsCar.position, .front)
        XCTAssertEqual(tsCar.specificCars, "Cars 1–3")
        XCTAssertTrue(tsCar.walkSavingsSeconds >= 60)
        
        // Grand Central-42 St (631)
        let gcExit = SubterraneanEgressEngine.resolvePrimaryExit(for: "631")
        XCTAssertEqual(gcExit.exitCode, "Exit 4B")
        XCTAssertTrue(gcExit.streetCorner.contains("Lexington Ave"))
        
        let gcCar = SubterraneanEgressEngine.resolveCarRecommendation(for: "631")
        XCTAssertEqual(gcCar.position, .front)
        
        // 14 St-Union Sq (635)
        let usCar = SubterraneanEgressEngine.resolveCarRecommendation(for: "635")
        XCTAssertEqual(usCar.position, .middle)
        XCTAssertEqual(usCar.specificCars, "Cars 4–6")
        
        // Boston South Station (place-sstat)
        let ssExit = SubterraneanEgressEngine.resolvePrimaryExit(for: "place-sstat")
        XCTAssertEqual(ssExit.exitCode, "Exit A")
        XCTAssertTrue(ssExit.isWheelchairAccessible)
    }
    
    func testSubterraneanEgressProceduralFallback() {
        let fallbackExit = SubterraneanEgressEngine.resolvePrimaryExit(for: "unknown_stop_999", stationName: "Oak St")
        XCTAssertFalse(fallbackExit.exitCode.isEmpty)
        XCTAssertTrue(fallbackExit.exitCode.hasPrefix("Exit "))
        XCTAssertTrue(fallbackExit.streetCorner.contains("Oak St"))
        
        let fallbackCar = SubterraneanEgressEngine.resolveCarRecommendation(for: "unknown_stop_999")
        XCTAssertTrue(PlatformCarPosition.allCases.contains(fallbackCar.position))
        XCTAssertTrue(fallbackCar.walkSavingsSeconds > 0)
    }

    func testSubterraneanAllExitsResolution() {
        let allExits = SubterraneanEgressEngine.resolveAllExits(for: "127")
        XCTAssertEqual(allExits.count, 3)
        XCTAssertEqual(allExits[0].exitCode, "Exit 4B")
        XCTAssertEqual(allExits[1].exitCode, "Exit 4A")
        XCTAssertEqual(allExits[2].exitCode, "Exit 1")
    }

    // MARK: - 2. Station Bullet Renderer Tests

    func testStationBulletRouteNormalization() {
        let raw = "1, 3, 2, 2, 1, 3"
        let parsed = StationBulletRenderer.parseAndNormalizeRoutes(raw)
        XCTAssertEqual(parsed, ["1", "2", "3"])
        
        let nqrw = "W,Q,N,R,R,N,Q,W"
        let parsedNqrw = StationBulletRenderer.parseAndNormalizeRoutes(nqrw)
        XCTAssertEqual(parsedNqrw, ["N", "Q", "R", "W"])
        
        let empty = StationBulletRenderer.parseAndNormalizeRoutes("")
        XCTAssertTrue(empty.isEmpty)
    }

    func testStationBulletCacheIdentifier() {
        let id123 = StationBulletRenderer.bulletIconIdentifier(for: ["1", "2", "3"])
        XCTAssertEqual(id123, "bullet_1_2_3")
        
        let idSingle = StationBulletRenderer.bulletIconIdentifier(for: ["6"])
        XCTAssertEqual(idSingle, "bullet_6")
        
        let idAce = StationBulletRenderer.bulletIconIdentifier(for: ["A", "C", "E"])
        XCTAssertEqual(idAce, "bullet_A_C_E")
    }

    @MainActor
    func testCompositeBulletImageGeneration() {
        let singleImage = StationBulletRenderer.renderCompositeBulletImage(routes: ["6"], discDiameter: 16.0, gap: 2.0)
        XCTAssertNotNil(singleImage)
        XCTAssertGreaterThan(singleImage.size.width, 0)
        XCTAssertGreaterThan(singleImage.size.height, 0)
        
        let multiImage = StationBulletRenderer.renderCompositeBulletImage(routes: ["4", "5", "6"], discDiameter: 16.0, gap: 2.0)
        XCTAssertNotNil(multiImage)
        // 3 discs (16pt each) + 2 gaps (2pt each) + 4pt padding = 48 + 4 + 4 = 56pt
        XCTAssertEqual(multiImage.size.width, 56.0, accuracy: 0.1)
        XCTAssertEqual(multiImage.size.height, 20.0, accuracy: 0.1)
        XCTAssertGreaterThan(multiImage.size.width, singleImage.size.width)
    }

    // MARK: - 3. Track Thermometer Models & Stop Ladder Tests

    func testTrackStopSequencing() {
        let stop1 = TrackStop(
            stopId: "125N",
            stopName: "125 St",
            coordinate: CLLocationCoordinate2D(latitude: 40.8155, longitude: -73.9583),
            sequenceIndex: 0,
            isPassed: true,
            isCurrent: false,
            isTerminus: true,
            estimatedMinutes: nil,
            transferRoutes: ["A", "B", "C", "D"]
        )
        
        let stop2 = TrackStop(
            stopId: "127N",
            stopName: "Times Sq-42 St",
            coordinate: CLLocationCoordinate2D(latitude: 40.7552, longitude: -73.9874),
            sequenceIndex: 1,
            isPassed: false,
            isCurrent: true,
            isTerminus: false,
            estimatedMinutes: 3,
            transferRoutes: ["N", "Q", "R", "W", "7"]
        )
        
        XCTAssertTrue(stop1.isPassed)
        XCTAssertFalse(stop1.isCurrent)
        XCTAssertTrue(stop1.isTerminus)
        XCTAssertNil(stop1.estimatedMinutes)
        
        XCTAssertFalse(stop2.isPassed)
        XCTAssertTrue(stop2.isCurrent)
        XCTAssertFalse(stop2.isTerminus)
        XCTAssertEqual(stop2.estimatedMinutes, 3)
        XCTAssertEqual(stop2.transferRoutes.count, 5)
    }

    // MARK: - 4. GTFS-RT Occupancy & Crowd Fallback Tests

    func testLiveOccupancyResolution() {
        let light = CrowdDensityEstimate.resolve(gtfsOccupancy: .manySeatsAvailable, occupancyPercentage: 20)
        XCTAssertEqual(light.level, .light)
        XCTAssertTrue(light.isLiveSensors)
        XCTAssertEqual(light.badgeTitle, "LIVE AVL OCCUPANCY")
        XCTAssertEqual(light.carriageLoads.count, 8)
        XCTAssertTrue(light.carriageLoads.allSatisfy { $0 > 0.0 && $0 <= 1.0 })
        
        let crowded = CrowdDensityEstimate.resolve(gtfsOccupancy: .standingRoomOnly, occupancyPercentage: 80)
        XCTAssertEqual(crowded.level, .crowded)
        XCTAssertTrue(crowded.isLiveSensors)
        
        let full = CrowdDensityEstimate.resolve(gtfsOccupancy: .full, occupancyPercentage: 98)
        XCTAssertEqual(full.level, .full)
        XCTAssertTrue(full.isLiveSensors)
    }

    func testDiurnalCrowdFallbackRushHour() {
        // Construct a weekday 8:30 AM date
        var calendar = Calendar.current
        calendar.timeZone = TimeZone(identifier: "America/New_York") ?? TimeZone.current
        var components = DateComponents()
        components.year = 2026
        components.month = 9
        components.day = 1 // Tuesday
        components.hour = 8
        components.minute = 30
        let morningRushDate = calendar.date(from: components) ?? Date()
        
        let fallbackRush = CrowdDensityEstimate.resolve(gtfsOccupancy: nil, date: morningRushDate)
        XCTAssertFalse(fallbackRush.isLiveSensors)
        XCTAssertEqual(fallbackRush.badgeTitle, "HISTORICAL CROWD ESTIMATE")
        XCTAssertEqual(fallbackRush.level, .crowded)
        
        // Late night 3:00 AM date
        components.hour = 3
        components.minute = 0
        let lateNightDate = calendar.date(from: components) ?? Date()
        let fallbackNight = CrowdDensityEstimate.resolve(gtfsOccupancy: nil, date: lateNightDate)
        XCTAssertEqual(fallbackNight.level, .light)
    }

    // MARK: - 5. SpatialDatabaseManager Stop Ladder Query Tests

    func testFetchRouteStopLadder() async throws {
        let ladder = try await SpatialDatabaseManager.shared.fetchRouteStopLadder(
            routeId: "1",
            directionId: 0,
            currentStopId: "127",
            currentArrivalMinutes: 4
        )
        
        XCTAssertFalse(ladder.isEmpty)
        XCTAssertTrue(ladder.contains(where: { $0.isCurrent }))
        
        if let current = ladder.first(where: { $0.isCurrent }) {
            XCTAssertEqual(current.estimatedMinutes, 4)
            XCTAssertFalse(current.isPassed)
        }
        
        // Downstream stops must have progressive ETAs
        let downstream = ladder.filter { !$0.isPassed && !$0.isCurrent }
        for stop in downstream {
            if let eta = stop.estimatedMinutes {
                XCTAssertGreaterThanOrEqual(eta, 4)
            }
        }
    }

    // MARK: - 6. Wave PE.11: Stop Ladder Continuity, Preceding Stops Accordion & Polyline Sync Tests

    func testPE11_MLadder_CompleteTripSequence_IncludesPrecedingStops() async throws {
        // Query M train Northbound (direction 0, to Forest Hills-71 Av) at Myrtle-Wyckoff (M08)
        let ladder = try await SpatialDatabaseManager.shared.fetchRouteStopLadder(
            routeId: "M",
            directionId: 0,
            currentStopId: "M08",
            currentArrivalMinutes: 3
        )
        
        XCTAssertFalse(ladder.isEmpty, "M train ladder must not be empty")
        
        // 1. Current stop must be Myrtle-Wyckoff (M08)
        let current = ladder.first(where: { $0.isCurrent })
        XCTAssertNotNil(current, "Current stop must exist on ladder")
        XCTAssertTrue(current?.stopId.contains("M08") == true || current?.stopName.contains("Myrtle-Wyckoff") == true)
        XCTAssertEqual(current?.estimatedMinutes, 3)
        XCTAssertEqual(current?.isPassed, false)
        
        // 2. Preceding stops must include origin M01 (Middle Village) and intermediate stops M04, M05, M06
        let passed = ladder.filter { $0.isPassed }
        XCTAssertTrue(passed.count >= 3, "M train at Myrtle-Wyckoff must have at least 3 preceding stops (M01, M04, M05, M06)")
        
        let origin = passed.first
        XCTAssertTrue(origin?.stopId.contains("M01") == true || origin?.stopName.contains("Middle Village") == true,
                      "First preceding stop must be origin M01 Middle Village")
        
        // 3. Downstream stops must include terminus G08 (Forest Hills-71 Av)
        let upcoming = ladder.filter { !$0.isPassed && !$0.isCurrent }
        let terminus = upcoming.last
        XCTAssertTrue(terminus?.stopId.contains("G08") == true || terminus?.stopName.contains("Forest Hills") == true,
                      "Last stop must be destination G08 Forest Hills-71 Av")
    }

    func testPE11_LLadder_PrecedingStopsAccordionThreshold() async throws {
        // Query L train Manhattan-bound (direction 0, to 8 Av) at 14 St-Union Sq (L03)
        let ladder = try await SpatialDatabaseManager.shared.fetchRouteStopLadder(
            routeId: "L",
            directionId: 0,
            currentStopId: "L03",
            currentArrivalMinutes: 2
        )
        
        XCTAssertFalse(ladder.isEmpty, "L train ladder must not be empty")
        let passed = ladder.filter { $0.isPassed }
        
        // At Union Sq, commuter has traveled past Canarsie, East New York, Bushwick, and Williamsburg (>15 stops)
        XCTAssertTrue(passed.count >= 3, "Passed stops >= 3 must trigger accordion collapse")
        
        // Origin must be Canarsie-Rockaway Pkwy (L29)
        let origin = passed.first
        XCTAssertTrue(origin?.stopId.contains("L29") == true || origin?.stopName.contains("Canarsie") == true,
                      "Origin stop must be Canarsie-Rockaway Pkwy")
        
        // Downstream stops must be 6th Ave (L02) and 8th Ave (L01)
        let upcoming = ladder.filter { !$0.isPassed && !$0.isCurrent }
        XCTAssertFalse(upcoming.isEmpty)
        let last = upcoming.last
        XCTAssertTrue(last?.stopId.contains("L01") == true || last?.stopName.contains("8 Av") == true,
                      "Terminus must be 8 Av")
    }

    // MARK: - 5. Pre-T.6 Continuous Ladder Stem & Express Variant Normalization Tests

    func testTrunkRouteIdNormalization() {
        // Express variants normalize to base trunk
        XCTAssertEqual(TransitRouteData.trunkRouteId(for: "6X"), "6")
        XCTAssertEqual(TransitRouteData.trunkRouteId(for: "6x"), "6")
        XCTAssertEqual(TransitRouteData.trunkRouteId(for: "7X"), "7")
        XCTAssertEqual(TransitRouteData.trunkRouteId(for: "7x"), "7")
        XCTAssertEqual(TransitRouteData.trunkRouteId(for: "FX"), "F")
        XCTAssertEqual(TransitRouteData.trunkRouteId(for: "fx"), "F")
        
        // Base trunks return clean uppercase
        XCTAssertEqual(TransitRouteData.trunkRouteId(for: "6"), "6")
        XCTAssertEqual(TransitRouteData.trunkRouteId(for: "7"), "7")
        XCTAssertEqual(TransitRouteData.trunkRouteId(for: "F"), "F")
        XCTAssertEqual(TransitRouteData.trunkRouteId(for: "L"), "L")
        XCTAssertEqual(TransitRouteData.trunkRouteId(for: "M15-SBS"), "M15-SBS")
    }

    func testGuidewayRunInspector_StripsExpressVariantTransfers() {
        // When inspecting 6X express train:
        // A stop with raw transfers ["6", "6X", "4", "5"] must strip both self-referential "6X" and trunk-equivalent "6"
        let arrival6X = SpatialDatabaseManager.ArrivalInfo(
            line: "6X",
            destination: "Pelham Bay Park",
            minutes: 4,
            direction: "Uptown & Bronx",
            distanceDescription: "2 stops away",
            corridorVector: .northbound
        )
        let inspector6X = GuidewayRunInspector(
            arrival: arrival6X,
            currentStopId: "635N",
            currentStopName: "14 St - Union Sq"
        )
        let testStop = TrackStop(
            id: "test_union_sq",
            stopId: "635",
            stopName: "14 St - Union Sq",
            coordinate: CLLocationCoordinate2D(latitude: 40.7359, longitude: -73.9906),
            sequenceIndex: 0,
            isPassed: false,
            isCurrent: true,
            isTerminus: false,
            estimatedMinutes: 4,
            transferRoutes: ["4", "5", "6", "6X", "L", "N", "Q", "R", "W"]
        )
        let filteredTransfers = inspector6X.displayedTransferRoutes(for: testStop)
        XCTAssertFalse(filteredTransfers.contains("6X"), "6X inspector must not display self-referential 6X transfer badge")
        XCTAssertFalse(filteredTransfers.contains("6"), "6X inspector must not display express variant trunk 6 transfer badge")
        XCTAssertTrue(filteredTransfers.contains("4"))
        XCTAssertTrue(filteredTransfers.contains("5"))
        XCTAssertTrue(filteredTransfers.contains("L"))
        
        // When inspecting 7X express train:
        let arrival7X = SpatialDatabaseManager.ArrivalInfo(
            line: "7X",
            destination: "Flushing - Main St",
            minutes: 3,
            direction: "Queens-bound",
            distanceDescription: "1 stop away",
            corridorVector: .eastbound
        )
        let inspector7X = GuidewayRunInspector(
            arrival: arrival7X,
            currentStopId: "701",
            currentStopName: "Flushing"
        )
        let stop7 = TrackStop(
            id: "test_7",
            stopId: "702",
            stopName: "Queensboro Plaza",
            coordinate: CLLocationCoordinate2D(latitude: 40.7505, longitude: -73.9402),
            sequenceIndex: 1,
            isPassed: false,
            isCurrent: false,
            isTerminus: false,
            estimatedMinutes: 5,
            transferRoutes: ["7", "7X", "N", "W"]
        )
        let filtered7 = inspector7X.displayedTransferRoutes(for: stop7)
        XCTAssertFalse(filtered7.contains("7X"), "7X inspector must not display self-referential 7X")
        XCTAssertFalse(filtered7.contains("7"), "7X inspector must not display trunk 7 transfer badge")
        XCTAssertTrue(filtered7.contains("N"))
        XCTAssertTrue(filtered7.contains("W"))
        
        // When inspecting FX express train:
        let arrivalFX = SpatialDatabaseManager.ArrivalInfo(
            line: "FX",
            destination: "Coney Island",
            minutes: 6,
            direction: "Brooklyn-bound",
            distanceDescription: "3 stops away",
            corridorVector: .southbound
        )
        let inspectorFX = GuidewayRunInspector(
            arrival: arrivalFX,
            currentStopId: "F20",
            currentStopName: "Church Av"
        )
        let stopFX = TrackStop(
            id: "test_fx",
            stopId: "F20",
            stopName: "Church Av",
            coordinate: CLLocationCoordinate2D(latitude: 40.6508, longitude: -73.9796),
            sequenceIndex: 2,
            isPassed: false,
            isCurrent: false,
            isTerminus: false,
            estimatedMinutes: 8,
            transferRoutes: ["F", "FX", "G"]
        )
        let filteredFX = inspectorFX.displayedTransferRoutes(for: stopFX)
        XCTAssertFalse(filteredFX.contains("FX"), "FX inspector must not display self-referential FX")
        XCTAssertFalse(filteredFX.contains("F"), "FX inspector must not display trunk F transfer badge")
        XCTAssertTrue(filteredFX.contains("G"))
    }

    func testGuidewayRunInspector_ContinuousStemGeometry() throws {
        // Assert that GuidewayRunInspector source file incorporates the continuous 4pt background stem on the 24x24 node
        let filePath = #filePath
        let testsDir = URL(fileURLWithPath: filePath).deletingLastPathComponent()
        let guidewayFile = testsDir.deletingLastPathComponent().appendingPathComponent("Derivee/GuidewayRunInspector.swift")
        let content = try String(contentsOf: guidewayFile, encoding: .utf8)
        
        XCTAssertTrue(content.contains(".frame(width: 4, height: 12)"), "GuidewayRunInspector must render 4pt-wide, 12pt-tall upper and lower stem segments in node background")
        XCTAssertTrue(content.contains("displayedTransferRoutes(for: stop)"), "GuidewayRunInspector must invoke displayedTransferRoutes to normalize transfer badges")
    }
}
