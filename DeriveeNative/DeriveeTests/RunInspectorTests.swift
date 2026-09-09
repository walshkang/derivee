import XCTest
import CoreLocation
import SwiftUI
@testable import Derivee

final class RunInspectorTests: XCTestCase {

    // MARK: - 1. SurfaceInspectableRoute Protocol Tokens

    func testSurfaceInspectableRouteTokensBus() {
        let busClass = TransitModalClass.bus
        XCTAssertEqual(busClass.stopLabelNoun, "Stop")
        XCTAssertFalse(busClass.tracksOverWater)
        XCTAssertTrue(busClass.displaysStopsAwayCountdown)
    }

    func testSurfaceInspectableRouteTokensFerry() {
        let ferryClass = TransitModalClass.ferry
        XCTAssertEqual(ferryClass.stopLabelNoun, "Pier / Slip")
        XCTAssertTrue(ferryClass.tracksOverWater)
        XCTAssertFalse(ferryClass.displaysStopsAwayCountdown)
    }

    func testSurfaceInspectableRouteTokensGuideway() {
        let subwayClass = TransitModalClass.subway
        XCTAssertEqual(subwayClass.stopLabelNoun, "Station")
        XCTAssertFalse(subwayClass.tracksOverWater)
        XCTAssertTrue(subwayClass.displaysStopsAwayCountdown)

        let lrtClass = TransitModalClass.lightRail
        XCTAssertEqual(lrtClass.stopLabelNoun, "Station")
        XCTAssertFalse(lrtClass.tracksOverWater)
        XCTAssertTrue(lrtClass.displaysStopsAwayCountdown)
    }

    func testLineInfoSurfaceInspectableRouteForwarding() {
        let busLine = TransitRouteData.LineInfo(
            routeId: "M15-SBS",
            name: "M15 Select Bus Service",
            colorHex: "#00A1DE",
            textColorHex: "#FFFFFF",
            modalClass: .bus,
            routeType: 3
        )
        XCTAssertEqual(busLine.stopLabelNoun, "Stop")
        XCTAssertFalse(busLine.tracksOverWater)
        XCTAssertTrue(busLine.displaysStopsAwayCountdown)

        let ferryLine = TransitRouteData.LineInfo(
            routeId: "ER",
            name: "East River Ferry",
            colorHex: "#00A3E0",
            textColorHex: "#FFFFFF",
            modalClass: .ferry,
            routeType: 4
        )
        XCTAssertEqual(ferryLine.stopLabelNoun, "Pier / Slip")
        XCTAssertTrue(ferryLine.tracksOverWater)
        XCTAssertFalse(ferryLine.displaysStopsAwayCountdown)
    }

    // MARK: - 2. Modal Class Branching Contract

    func testModalClassBranchingLogic() {
        let subwayArrival = SpatialDatabaseManager.ArrivalInfo(
            line: "6",
            destination: "Pelham Bay Park",
            minutes: 4,
            direction: "Downtown"
        )
        let subwayLineInfo = TransitRouteData.lineInfo(for: subwayArrival.line)
        XCTAssertTrue(subwayLineInfo.modalClass == .subway || subwayLineInfo.modalClass == .lightRail)

        let busArrival = SpatialDatabaseManager.ArrivalInfo(
            line: "M15",
            destination: "South Ferry",
            minutes: 7,
            direction: "Downtown"
        )
        let busLineInfo = TransitRouteData.lineInfo(for: busArrival.line)
        XCTAssertTrue(busLineInfo.modalClass == .bus || busLineInfo.modalClass == .ferry)
    }

    // MARK: - 3. Inspector Instantiation & View Construction

    @MainActor
    func testGuidewayRunInspectorViewConstruction() {
        let arrival = SpatialDatabaseManager.ArrivalInfo(
            line: "6",
            destination: "Pelham Bay Park",
            minutes: 3,
            direction: "Downtown",
            distanceDescription: "2 stops away",
            tripId: "MTA_NYCT_6_12345"
        )
        let followOn = SpatialDatabaseManager.ArrivalInfo(
            line: "6",
            destination: "Pelham Bay Park",
            minutes: 11,
            direction: "Downtown"
        )
        
        let inspector = GuidewayRunInspector(
            arrival: arrival,
            currentStopId: "631",
            currentStopName: "Grand Central-42 St",
            followOnArrival: followOn
        )
        
        let hosting = UIHostingController(rootView: inspector)
        XCTAssertNotNil(hosting.view)
    }

    @MainActor
    func testSurfaceRunInspectorViewConstructionBus() {
        let arrival = SpatialDatabaseManager.ArrivalInfo(
            line: "M15-SBS",
            destination: "South Ferry",
            minutes: 5,
            direction: "Downtown",
            distanceDescription: "3 stops away",
            tripId: "MTA_NYCT_5421"
        )
        
        let inspector = SurfaceRunInspector(
            arrival: arrival,
            currentStopId: "stop_m15_1",
            currentStopName: "2nd Ave & 23rd St",
            modalClass: .bus
        )
        
        let hosting = UIHostingController(rootView: inspector)
        XCTAssertNotNil(hosting.view)
    }

    @MainActor
    func testSurfaceRunInspectorViewConstructionFerry() {
        let arrival = SpatialDatabaseManager.ArrivalInfo(
            line: "ER",
            destination: "Wall St / Pier 11",
            minutes: 12,
            direction: "Southbound",
            distanceDescription: nil,
            tripId: "VESSEL_ASTORIA"
        )
        
        let inspector = SurfaceRunInspector(
            arrival: arrival,
            currentStopId: "ferry_pier_11",
            currentStopName: "Wall St / Pier 11",
            modalClass: .ferry
        )
        
        let hosting = UIHostingController(rootView: inspector)
        XCTAssertNotNil(hosting.view)
    }
}
