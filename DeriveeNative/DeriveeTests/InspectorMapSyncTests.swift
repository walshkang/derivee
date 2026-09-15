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

    // MARK: - 4. Wave PC.1 Live Map Vehicle Tracking & Location Resolution Tests

    func testRouteInspectionCommandVehiclePuckAttributes() {
        let station = CLLocationCoordinate2D(latitude: 40.7527, longitude: -73.9772)
        let vehicle = CLLocationCoordinate2D(latitude: 40.7600, longitude: -73.9700)
        let coords = [
            CLLocationCoordinate2D(latitude: 40.7500, longitude: -73.9800),
            station
        ]
        
        let cmd = RouteInspectionCommand(
            routeId: "L",
            lineName: "14th St - Canarsie Local",
            agencyColorHex: "#A7A9AC",
            modalClass: .subway,
            coordinates: coords,
            stationCoordinate: station,
            vehicleCoordinate: vehicle,
            vehicleBearing: 45.0,
            vehicleStatus: "Approaching"
        )
        
        XCTAssertNotNil(cmd.vehicleCoordinate)
        XCTAssertEqual(cmd.vehicleCoordinate?.latitude, vehicle.latitude)
        XCTAssertEqual(cmd.vehicleCoordinate?.longitude, vehicle.longitude)
        XCTAssertEqual(cmd.vehicleBearing, 45.0)
        XCTAssertEqual(cmd.vehicleStatus, "Approaching")
        
        // Bounding box must enclose both station and vehicle
        let bounds = cmd.computedBoundingBox()
        XCTAssertNotNil(bounds)
        guard let b = bounds else { return }
        XCTAssertLessThanOrEqual(b.sw.latitude, station.latitude)
        XCTAssertGreaterThanOrEqual(b.ne.latitude, vehicle.latitude)
        XCTAssertLessThanOrEqual(b.sw.longitude, coords[0].longitude)
        XCTAssertGreaterThanOrEqual(b.ne.longitude, vehicle.longitude)
    }

    func testVehicleLocationResolutionBusGPS() {
        let gpsCoord = CLLocationCoordinate2D(latitude: 40.7300, longitude: -73.9800)
        let busArrival = SpatialDatabaseManager.ArrivalInfo(
            line: "M15",
            destination: "South Ferry",
            minutes: 3,
            direction: "Downtown",
            distanceDescription: "1 stop away",
            vehicleCoordinate: gpsCoord,
            vehicleBearing: 180.0
        )
        
        let dummyLadder = [
            TrackStop(stopId: "1", stopName: "Stop 1", coordinate: CLLocationCoordinate2D(latitude: 40.74, longitude: -73.98), sequenceIndex: 0, isPassed: true),
            TrackStop(stopId: "2", stopName: "Stop 2", coordinate: CLLocationCoordinate2D(latitude: 40.73, longitude: -73.98), sequenceIndex: 1, isCurrent: true)
        ]
        
        let resolved = TransitRealtimeService.shared.resolveVehicleLocation(arrival: busArrival, ladder: dummyLadder)
        XCTAssertNotNil(resolved)
        XCTAssertEqual(resolved?.coordinate.latitude, gpsCoord.latitude)
        XCTAssertEqual(resolved?.coordinate.longitude, gpsCoord.longitude)
        XCTAssertEqual(resolved?.bearing, 180.0)
    }

    func testVehicleLocationResolutionSubwayPlatform() {
        let subwayArrival = SpatialDatabaseManager.ArrivalInfo(
            line: "L",
            destination: "8 Av",
            minutes: 0,
            distanceDescription: "Boarding"
        )
        
        let stationCoord = CLLocationCoordinate2D(latitude: 40.7173, longitude: -73.9566)
        let nextCoord = CLLocationCoordinate2D(latitude: 40.7180, longitude: -73.9500)
        let dummyLadder = [
            TrackStop(stopId: "L10", stopName: "Bedford Av", coordinate: stationCoord, sequenceIndex: 0, isCurrent: true),
            TrackStop(stopId: "L11", stopName: "Lorimer St", coordinate: nextCoord, sequenceIndex: 1)
        ]
        
        let resolved = TransitRealtimeService.shared.resolveVehicleLocation(arrival: subwayArrival, ladder: dummyLadder)
        XCTAssertNotNil(resolved)
        XCTAssertEqual(resolved?.coordinate.latitude, stationCoord.latitude)
        XCTAssertEqual(resolved?.coordinate.longitude, stationCoord.longitude)
        XCTAssertNotNil(resolved?.bearing)
    }

    func testVehicleLocationResolutionSubwayInterpolation() {
        let subwayArrival = SpatialDatabaseManager.ArrivalInfo(
            line: "L",
            destination: "8 Av",
            minutes: 2,
            distanceDescription: "Approaching",
            progressLambda: 0.80
        )
        
        let upstreamCoord = CLLocationCoordinate2D(latitude: 40.7100, longitude: -73.9500)
        let currentCoord = CLLocationCoordinate2D(latitude: 40.7200, longitude: -73.9600)
        let dummyLadder = [
            TrackStop(stopId: "L09", stopName: "1 Av", coordinate: upstreamCoord, sequenceIndex: 0, isPassed: true),
            TrackStop(stopId: "L10", stopName: "Bedford Av", coordinate: currentCoord, sequenceIndex: 1, isCurrent: true)
        ]
        
        let resolved = TransitRealtimeService.shared.resolveVehicleLocation(arrival: subwayArrival, ladder: dummyLadder)
        XCTAssertNotNil(resolved)
        
        // Progress 0.80 means vehicle is 80% of the way from upstream (40.71) toward current (40.72)
        let expectedLat = 40.7100 + (40.7200 - 40.7100) * 0.80
        let expectedLon = -73.9500 + (-73.9600 - (-73.9500)) * 0.80
        XCTAssertEqual(resolved!.coordinate.latitude, expectedLat, accuracy: 0.0001)
        XCTAssertEqual(resolved!.coordinate.longitude, expectedLon, accuracy: 0.0001)
        XCTAssertNotNil(resolved?.bearing)
    }

    func testVehicleLocationResolutionTerminusHold() {
        let heldArrival = SpatialDatabaseManager.ArrivalInfo(
            line: "L",
            destination: "8 Av",
            minutes: 5,
            distanceDescription: "At Terminus",
            isHoldingStation: true
        )
        
        let originCoord = CLLocationCoordinate2D(latitude: 40.6350, longitude: -73.9010)
        let nextCoord = CLLocationCoordinate2D(latitude: 40.6400, longitude: -73.9020)
        let dummyLadder = [
            TrackStop(stopId: "L29", stopName: "Canarsie-Rockaway Pkwy", coordinate: originCoord, sequenceIndex: 0, isPassed: true),
            TrackStop(stopId: "L28", stopName: "East 105 St", coordinate: nextCoord, sequenceIndex: 1, isPassed: true),
            TrackStop(stopId: "L10", stopName: "Bedford Av", coordinate: CLLocationCoordinate2D(latitude: 40.7173, longitude: -73.9566), sequenceIndex: 2, isCurrent: true)
        ]
        
        let resolved = TransitRealtimeService.shared.resolveVehicleLocation(arrival: heldArrival, ladder: dummyLadder)
        XCTAssertNotNil(resolved)
        XCTAssertEqual(resolved?.coordinate.latitude, originCoord.latitude)
        XCTAssertEqual(resolved?.coordinate.longitude, originCoord.longitude)
    }

    // MARK: - Wave PD.2: Focus on Map & Return Navigation

    @MainActor
    func testPD2_FocusMapClosureExecution() {
        var focusedCoord: CLLocationCoordinate2D? = nil
        let targetCoord = CLLocationCoordinate2D(latitude: 40.7173, longitude: -73.9566)
        
        let arrival = SpatialDatabaseManager.ArrivalInfo(
            line: "L",
            destination: "8 Av",
            minutes: 2
        )
        
        let guideway = GuidewayRunInspector(
            arrival: arrival,
            currentStopId: "L10",
            currentStopName: "Bedford Av",
            currentStopCoordinate: targetCoord,
            onFocusMap: { coord in
                focusedCoord = coord
            }
        )
        
        guideway.onFocusMap?(targetCoord)
        XCTAssertNotNil(focusedCoord)
        XCTAssertEqual(focusedCoord?.latitude, targetCoord.latitude)
        XCTAssertEqual(focusedCoord?.longitude, targetCoord.longitude)
    }
}
