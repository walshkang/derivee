import XCTest
import CoreLocation
import SwiftUI
@testable import Derivee

final class InspectorMapSyncTests: XCTestCase {

    // MARK: - 1. RouteInspectionCommand Model Tests

    func testRouteInspectionCommandPropertiesSubway() {
        let station = CLLocationCoordinate2D(latitude: 40.7527, longitude: -73.9772)
        let coords = [
            CLLocationCoordinate2D(latitude: 40.7580, longitude: -73.9855),
            CLLocationCoordinate2D(latitude: 40.7527, longitude: -73.9772),
            CLLocationCoordinate2D(latitude: 40.7484, longitude: -73.9857)
        ]
        
        let cmd = RouteInspectionCommand(
            routeId: "6",
            lineName: "Lexington Avenue Local",
            agencyColorHex: "#00933C",
            casingColorHex: "#FFFFFF",
            modalClass: .subway,
            coordinates: coords,
            stationCoordinate: station,
            shouldFrameCamera: true
        )
        
        XCTAssertEqual(cmd.routeId, "6")
        XCTAssertEqual(cmd.lineName, "Lexington Avenue Local")
        XCTAssertEqual(cmd.agencyColorHex, "#00933C")
        XCTAssertEqual(cmd.casingColorHex, "#FFFFFF")
        XCTAssertEqual(cmd.modalClass, .subway)
        XCTAssertFalse(cmd.isDashed)
        XCTAssertTrue(cmd.shouldFrameCamera)
        XCTAssertEqual(cmd.coordinates.count, 3)
        XCTAssertEqual(cmd.stationCoordinate.latitude, station.latitude, accuracy: 0.0001)
        XCTAssertEqual(cmd.stationCoordinate.longitude, station.longitude, accuracy: 0.0001)
    }

    func testRouteInspectionCommandFerryDashed() {
        let pier = CLLocationCoordinate2D(latitude: 40.7018, longitude: -74.0090)
        let coords = [
            CLLocationCoordinate2D(latitude: 40.7018, longitude: -74.0090),
            CLLocationCoordinate2D(latitude: 40.7180, longitude: -73.9680)
        ]
        
        let cmd = RouteInspectionCommand(
            routeId: "ER",
            lineName: "East River Ferry",
            agencyColorHex: "#00A3E0",
            modalClass: .ferry,
            coordinates: coords,
            stationCoordinate: pier
        )
        
        XCTAssertEqual(cmd.modalClass, .ferry)
        XCTAssertTrue(cmd.isDashed, "Ferry routes must render with dashed pattern per design.md §10.6.1")
    }

    func testRouteInspectionCommandBoundingBoxEnclosure() {
        let station = CLLocationCoordinate2D(latitude: 40.7527, longitude: -73.9772)
        let coords = [
            CLLocationCoordinate2D(latitude: 40.7600, longitude: -73.9700),
            CLLocationCoordinate2D(latitude: 40.7400, longitude: -73.9900)
        ]
        
        let cmd = RouteInspectionCommand(
            routeId: "6",
            lineName: "Lexington Avenue Local",
            agencyColorHex: "#00933C",
            modalClass: .subway,
            coordinates: coords,
            stationCoordinate: station
        )
        
        let bounds = cmd.computedBoundingBox()
        XCTAssertNotNil(bounds)
        guard let b = bounds else { return }
        
        XCTAssertLessThanOrEqual(b.sw.latitude, 40.7400)
        XCTAssertGreaterThanOrEqual(b.ne.latitude, 40.7600)
        XCTAssertLessThanOrEqual(b.sw.longitude, -73.9900)
        XCTAssertGreaterThanOrEqual(b.ne.longitude, -73.9700)
    }

    // MARK: - 2. Polyline Resolution & Fallbacks

    func testPolylineResolutionWithFallbackStops() async {
        let stops = [
            CLLocationCoordinate2D(latitude: 40.7500, longitude: -73.9800),
            CLLocationCoordinate2D(latitude: 40.7600, longitude: -73.9700)
        ]
        
        let polyline = await TransitRouteData.resolveInspectionPolyline(
            routeId: "TEST_UNMAPPED_ROUTE",
            modalClass: .bus,
            fallbackStops: stops
        )
        
        XCTAssertEqual(polyline.count, 2)
        XCTAssertEqual(polyline.first?.latitude ?? 0, stops.first?.latitude ?? 0, accuracy: 0.0001)
    }

    func testPolylineResolutionSubwayShapes() async {
        let polyline = await TransitRouteData.resolveInspectionPolyline(
            routeId: "L",
            modalClass: .subway,
            fallbackStops: []
        )
        
        // "L" line has bundled subway-lines.geojson geometry
        XCTAssertFalse(polyline.isEmpty, "Subway L train should resolve geometry from bundled GeoJSON")
    }

    // MARK: - 3. Inspector Closures & View Construction

    @MainActor
    func testGuidewayInspectorClosureWiring() {
        let arrival = SpatialDatabaseManager.ArrivalInfo(
            line: "6",
            destination: "Pelham Bay Park",
            minutes: 3,
            direction: "Downtown"
        )
        
        var inspectCalled = false
        var clearCalled = false
        
        let inspector = GuidewayRunInspector(
            arrival: arrival,
            currentStopId: "631",
            currentStopName: "Grand Central-42 St",
            onFocusMap: { _ in },
            onInspectRoute: { cmd in
                inspectCalled = true
                XCTAssertEqual(cmd.routeId, "6")
            },
            onClearRouteInspection: {
                clearCalled = true
            }
        )
        
        XCTAssertNotNil(inspector.onInspectRoute)
        XCTAssertNotNil(inspector.onClearRouteInspection)
        
        let hosting = UIHostingController(rootView: inspector)
        XCTAssertNotNil(hosting.view)
        
        // Directly test closure execution
        inspector.onInspectRoute?(RouteInspectionCommand(
            routeId: "6",
            lineName: "6",
            agencyColorHex: "#00933C",
            modalClass: .subway,
            coordinates: [],
            stationCoordinate: CLLocationCoordinate2D(latitude: 40.75, longitude: -73.98)
        ))
        XCTAssertTrue(inspectCalled)
        
        inspector.onClearRouteInspection?()
        XCTAssertTrue(clearCalled)
    }

    @MainActor
    func testSurfaceInspectorClosureWiring() {
        let arrival = SpatialDatabaseManager.ArrivalInfo(
            line: "M15-SBS",
            destination: "South Ferry",
            minutes: 5,
            direction: "Downtown"
        )
        
        var inspectCalled = false
        var clearCalled = false
        
        let inspector = SurfaceRunInspector(
            arrival: arrival,
            currentStopId: "stop_m15_1",
            currentStopName: "2nd Ave & 23rd St",
            modalClass: .bus,
            onFocusMap: { _ in },
            onInspectRoute: { cmd in
                inspectCalled = true
                XCTAssertEqual(cmd.routeId, "M15-SBS")
            },
            onClearRouteInspection: {
                clearCalled = true
            }
        )
        
        XCTAssertNotNil(inspector.onInspectRoute)
        XCTAssertNotNil(inspector.onClearRouteInspection)
        
        let hosting = UIHostingController(rootView: inspector)
        XCTAssertNotNil(hosting.view)
        
        inspector.onInspectRoute?(RouteInspectionCommand(
            routeId: "M15-SBS",
            lineName: "M15 Select Bus Service",
            agencyColorHex: "#00A1DE",
            modalClass: .bus,
            coordinates: [],
            stationCoordinate: CLLocationCoordinate2D(latitude: 40.73, longitude: -73.98)
        ))
        XCTAssertTrue(inspectCalled)
        
        inspector.onClearRouteInspection?()
        XCTAssertTrue(clearCalled)
    }

    @MainActor
    func testTransitRevealSheetClosureWiring() {
        var inspectCommand: RouteInspectionCommand? = nil
        var clearCount = 0
        
        let sheet = TransitRevealSheet(
            stopId: "631",
            onFocusMap: { _ in },
            onInspectRoute: { cmd in
                inspectCommand = cmd
            },
            onClearRouteInspection: {
                clearCount += 1
            }
        )
        
        XCTAssertNotNil(sheet.onInspectRoute)
        XCTAssertNotNil(sheet.onClearRouteInspection)
        
        let dummyCommand = RouteInspectionCommand(
            routeId: "6",
            lineName: "6",
            agencyColorHex: "#00933C",
            modalClass: .subway,
            coordinates: [],
            stationCoordinate: CLLocationCoordinate2D(latitude: 40.75, longitude: -73.98)
        )
        sheet.onInspectRoute?(dummyCommand)
        XCTAssertEqual(inspectCommand?.routeId, "6")
        
        sheet.onClearRouteInspection?()
        XCTAssertEqual(clearCount, 1)
    }
}
