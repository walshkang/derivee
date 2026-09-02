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
}
