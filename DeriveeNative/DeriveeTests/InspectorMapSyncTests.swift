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

    // MARK: - Wave PD.3: Approaching Train Progression & Bounded Vehicle Framing

    private func makePD3TestLadder() -> [TrackStop] {
        var ladder: [TrackStop] = []
        for i in 0..<15 {
            let name: String
            if i == 12 {
                name = "Graham Av"
            } else if i == 13 {
                name = "Lorimer St"
            } else if i == 14 {
                name = "Bedford Av"
            } else {
                name = "Stop \(i)"
            }
            ladder.append(TrackStop(
                stopId: "L\(i)",
                stopName: name,
                coordinate: CLLocationCoordinate2D(latitude: 40.70 + Double(i) * 0.005, longitude: -73.95),
                sequenceIndex: i,
                isPassed: i < 14,
                isCurrent: i == 14
            ))
        }
        return ladder
    }

    func testPD3_VehicleStopIndexResolution() {
        let dummyLadder = makePD3TestLadder()
        
        // 1. "2 stops away" -> index 14 - 2 = 12
        let arr2Stops = SpatialDatabaseManager.ArrivalInfo(
            line: "L", destination: "8 Av", minutes: 4, distanceDescription: "2 stops away"
        )
        let idx2Stops = TransitRealtimeService.shared.resolveVehicleStopIndex(arrival: arr2Stops, ladder: dummyLadder)
        XCTAssertEqual(idx2Stops, 12, "2 stops away should resolve to 2 stops upstream of commuter station")
        
        // 2. "Approaching" -> index 14 - 1 = 13
        let arrApproaching = SpatialDatabaseManager.ArrivalInfo(
            line: "L", destination: "8 Av", minutes: 2, distanceDescription: "Approaching"
        )
        let idxApproaching = TransitRealtimeService.shared.resolveVehicleStopIndex(arrival: arrApproaching, ladder: dummyLadder)
        XCTAssertEqual(idxApproaching, 13, "'Approaching' should resolve to 1 stop upstream")
        
        // 3. "Boarding" -> index 14
        let arrBoarding = SpatialDatabaseManager.ArrivalInfo(
            line: "L", destination: "8 Av", minutes: 0, distanceDescription: "Boarding"
        )
        let idxBoarding = TransitRealtimeService.shared.resolveVehicleStopIndex(arrival: arrBoarding, ladder: dummyLadder)
        XCTAssertEqual(idxBoarding, 14, "'Boarding' should resolve to commuter station index")
        
        // 4. "At Terminus" -> index 0
        let arrTerminus = SpatialDatabaseManager.ArrivalInfo(
            line: "L", destination: "8 Av", minutes: 12, distanceDescription: "At Terminus"
        )
        let idxTerminus = TransitRealtimeService.shared.resolveVehicleStopIndex(arrival: arrTerminus, ladder: dummyLadder)
        XCTAssertEqual(idxTerminus, 0, "'At Terminus' should resolve to sequence index 0")
        
        // 5. GPS coordinate matching
        let arrGPS = SpatialDatabaseManager.ArrivalInfo(
            line: "L", destination: "8 Av", minutes: 6,
            vehicleCoordinate: CLLocationCoordinate2D(latitude: 40.70 + 7.0 * 0.005, longitude: -73.95)
        )
        let idxGPS = TransitRealtimeService.shared.resolveVehicleStopIndex(arrival: arrGPS, ladder: dummyLadder)
        XCTAssertEqual(idxGPS, 7, "Direct GPS coordinate should snap to closest upstream sequence index")
    }

    func testPD3_AnnotateLadderWithApproachingTrain() {
        let dummyLadder = makePD3TestLadder()
        
        let arrival = SpatialDatabaseManager.ArrivalInfo(
            line: "L", destination: "8 Av", minutes: 4, distanceDescription: "2 stops away • Approaching Lorimer St"
        )
        
        let annotated = TransitRealtimeService.shared.annotateLadderWithVehicle(ladder: dummyLadder, arrival: arrival)
        XCTAssertEqual(annotated.count, 15)
        
        // Prior stops 0...11 should be isPassed = true
        for i in 0...11 {
            XCTAssertTrue(annotated[i].isPassed, "Stop \(i) prior to live vehicle must be marked isPassed")
            XCTAssertFalse(annotated[i].isVehicleHere, "Stop \(i) must not have vehicle marker")
            XCTAssertFalse(annotated[i].isCurrent, "Stop \(i) is not commuter station")
        }
        
        // Stop 12 (Graham Av) is live train stop
        XCTAssertTrue(annotated[12].isVehicleHere, "Graham Av must be marked with isVehicleHere = true")
        XCTAssertFalse(annotated[12].isPassed, "Live vehicle stop must not be marked isPassed")
        XCTAssertFalse(annotated[12].isCurrent, "Graham Av is not commuter station")
        
        // Stop 13 (Lorimer St) is intermediate approaching stop
        XCTAssertFalse(annotated[13].isPassed, "Intermediate approaching stop must be active, not passed")
        XCTAssertFalse(annotated[13].isVehicleHere, "Lorimer St does not have the train yet")
        XCTAssertFalse(annotated[13].isCurrent, "Lorimer St is not commuter station")
        
        // Stop 14 (Bedford Av) is commuter station
        XCTAssertTrue(annotated[14].isCurrent, "Bedford Av must be marked with isCurrent = true")
        XCTAssertFalse(annotated[14].isPassed, "Commuter station must not be passed")
        XCTAssertFalse(annotated[14].isVehicleHere, "Commuter station does not have train yet")
    }

    func testPD3_RouteInspectionCommandTightVehicleBoundingBox() {
        let station = CLLocationCoordinate2D(latitude: 40.7173, longitude: -73.9566) // Bedford Av
        let vehicle = CLLocationCoordinate2D(latitude: 40.7145, longitude: -73.9440) // Graham Av
        
        let fullRouteCoords = [
            CLLocationCoordinate2D(latitude: 40.6466, longitude: -73.9018), // Canarsie (Far away South)
            CLLocationCoordinate2D(latitude: 40.7145, longitude: -73.9440), // Graham Av
            CLLocationCoordinate2D(latitude: 40.7150, longitude: -73.9500), // Intermediate Lorimer
            CLLocationCoordinate2D(latitude: 40.7173, longitude: -73.9566), // Bedford Av
            CLLocationCoordinate2D(latitude: 40.7397, longitude: -74.0025)  // 8 Av (Far away North/West)
        ]
        
        let cmd = RouteInspectionCommand(
            routeId: "L",
            lineName: "14th Street-Canarsie Local",
            agencyColorHex: "#A7A9AC",
            modalClass: .subway,
            coordinates: fullRouteCoords,
            stationCoordinate: station,
            vehicleCoordinate: vehicle
        )
        
        let bounds = cmd.computedBoundingBox(tightVehicleBounding: true)
        XCTAssertNotNil(bounds)
        guard let b = bounds else { return }
        
        // Must tightly enclose Graham Av and Bedford Av
        XCTAssertLessThanOrEqual(b.sw.latitude, min(station.latitude, vehicle.latitude))
        XCTAssertGreaterThanOrEqual(b.ne.latitude, max(station.latitude, vehicle.latitude))
        
        // Must strictly exclude distant Canarsie (40.6466)
        XCTAssertGreaterThan(b.sw.latitude, 40.6800, "Tight bounding box must not expand to Canarsie terminal")
        
        // Must strictly exclude distant 8th Ave (40.7397)
        XCTAssertLessThan(b.ne.latitude, 40.7350, "Tight bounding box must not expand to Manhattan 8 Av terminal")
    }

    // MARK: - 8. Wave PE.1 Persistent Route & Vehicle Telemetry Tests

    @MainActor
    func testPersistentRouteInspectionAcrossDetentPeek() {
        var clearCount = 0
        let arr = SpatialDatabaseManager.ArrivalInfo(line: "L", destination: "Canarsie", minutes: 3)
        
        let sheet = TransitRevealSheet(
            stopId: "stop_bedford",
            initialInspectingArrival: arr,
            initialDetent: .medium,
            onClearRouteInspection: {
                clearCount += 1
            }
        )
        
        let hosting = UIHostingController(rootView: sheet)
        XCTAssertNotNil(hosting.view)
        
        // At .medium, inspection must be active and clearCount must be 0
        XCTAssertEqual(clearCount, 0, "Initial presentation must not call onClearRouteInspection")
        
        // Simulating peek detent transition: render compactInspectionDockPill
        let dockPill = sheet.compactInspectionDockPill(for: arr)
        let pillHosting = UIHostingController(rootView: dockPill)
        XCTAssertNotNil(pillHosting.view)
        
        // Entering peek detent must NOT invoke onClearRouteInspection (FC-7)
        XCTAssertEqual(clearCount, 0, "Lowering drawer to inspectionPeekDetent must NOT wipe map telemetry")
    }

    // MARK: - 9. Wave PE.2 Detent-Aware Dynamic Camera Viewport Framing Tests

    @MainActor
    func testPE2_TransitRevealSheet_NotifiesDetentChanges() {
        var recordedDetent: PresentationDetent? = nil
        let arr = SpatialDatabaseManager.ArrivalInfo(line: "L", destination: "Canarsie", minutes: 4)
        
        let sheet = TransitRevealSheet(
            stopId: "stop_bedford",
            initialInspectingArrival: arr,
            initialDetent: TransitRevealSheet.inspectionPeekDetent,
            onDetentChange: { detent in
                recordedDetent = detent
            }
        )
        
        let hosting = UIHostingController(rootView: sheet)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        window.rootViewController = hosting
        window.makeKeyAndVisible()
        hosting.beginAppearanceTransition(true, animated: false)
        hosting.endAppearanceTransition()
        hosting.view.layoutIfNeeded()
        
        // On appear, initialDetent (.fraction(0.12)) must be notified to parent
        XCTAssertEqual(
            recordedDetent,
            TransitRevealSheet.inspectionPeekDetent,
            "TransitRevealSheet must report its active detent via onDetentChange"
        )
    }

    func testPE2_WideApproachBoundingBox_PreservesIntermediateCurvature() {
        // Commuter station: Bedford Av L
        let station = CLLocationCoordinate2D(latitude: 40.7173, longitude: -73.9566)
        // Oncoming train: Bushwick Av-Aberdeen St (distant consist ~5km away)
        let distantVehicle = CLLocationCoordinate2D(latitude: 40.6780, longitude: -73.9050)
        
        let intermediateCurvature = [
            CLLocationCoordinate2D(latitude: 40.7173, longitude: -73.9566), // Bedford Av
            CLLocationCoordinate2D(latitude: 40.7145, longitude: -73.9440), // Graham Av
            CLLocationCoordinate2D(latitude: 40.7115, longitude: -73.9350), // Grand St
            CLLocationCoordinate2D(latitude: 40.7070, longitude: -73.9210), // Montrose Av
            CLLocationCoordinate2D(latitude: 40.7000, longitude: -73.9100), // Jefferson St
            CLLocationCoordinate2D(latitude: 40.6780, longitude: -73.9050)  // Bushwick Av-Aberdeen St
        ]
        
        let cmd = RouteInspectionCommand(
            routeId: "L",
            lineName: "14th Street-Canarsie Local",
            agencyColorHex: "#A7A9AC",
            modalClass: .subway,
            coordinates: intermediateCurvature,
            stationCoordinate: station,
            vehicleCoordinate: distantVehicle
        )
        
        let bounds = cmd.computedBoundingBox(tightVehicleBounding: true)
        XCTAssertNotNil(bounds, "Distant consist bounding box must be computable")
        guard let b = bounds else { return }
        
        // Bounding box must enclose the entire span
        XCTAssertLessThanOrEqual(b.sw.latitude, distantVehicle.latitude)
        XCTAssertGreaterThanOrEqual(b.ne.latitude, station.latitude)
        XCTAssertLessThanOrEqual(b.sw.longitude, min(station.longitude, distantVehicle.longitude))
        XCTAssertGreaterThanOrEqual(b.ne.longitude, max(station.longitude, distantVehicle.longitude))
        
        // Longitudinal and latitudinal spans must be within long approach scale (allowing z in [13.0, 15.5])
        let latSpan = b.ne.latitude - b.sw.latitude
        let lonSpan = b.ne.longitude - b.sw.longitude
        XCTAssertGreaterThan(latSpan, 0.03, "Distant approach span must exceed tight station radius")
        XCTAssertLessThan(latSpan, 0.20, "Distant approach span must remain within city corridor limits")
        XCTAssertGreaterThan(lonSpan, 0.03, "Distant approach span must span corridor longitude")
    }

    // MARK: - 10. Wave Pre-T.5 Persistent Inspection Dock Synchronization Tests (WPT5)

    func testPreT5_SourceCodeAudit_MapViewUnconditionalAssignment() throws {
        let filePath = #filePath
        let testsDir = URL(fileURLWithPath: filePath).deletingLastPathComponent()
        let mapViewFile = testsDir.deletingLastPathComponent().appendingPathComponent("Derivee/MapView.swift")
        let content = try String(contentsOf: mapViewFile, encoding: .utf8)
        
        // 1. Must unconditionally assign lastAppliedInspectionCommand = cmd when command is present
        XCTAssertTrue(
            content.contains("lastAppliedInspectionCommand = cmd"),
            "Pre-T.5 Violation: MapView.Coordinator must unconditionally assign lastAppliedInspectionCommand = cmd"
        )
        
        // 2. Must record lastAppliedInspectionDetent = activeDetent upon new command ID
        XCTAssertTrue(
            content.contains("lastAppliedInspectionDetent = activeDetent"),
            "Pre-T.5 Violation: MapView.Coordinator must record lastAppliedInspectionDetent = activeDetent"
        )
        
        // 3. Must re-frame camera on detent transition using activeCmd
        XCTAssertTrue(
            content.contains("else if lastAppliedInspectionDetent != activeDetent, let activeCmd = lastAppliedInspectionCommand") ||
            content.contains("if lastAppliedInspectionDetent != activeDetent, let activeCmd = lastAppliedInspectionCommand"),
            "Pre-T.5 Violation: MapView.Coordinator must re-frame camera with activeCmd on detent change"
        )
    }

    func testPreT5_RouteInspectionCommand_RetainsTelemetryForDetentReFrame() {
        let station = CLLocationCoordinate2D(latitude: 40.7173, longitude: -73.9566)
        let initialVehicle = CLLocationCoordinate2D(latitude: 40.7145, longitude: -73.9440)
        let updatedVehicle = CLLocationCoordinate2D(latitude: 40.7130, longitude: -73.9390)
        
        let initialCmd = RouteInspectionCommand(
            routeId: "L",
            lineName: "14th Street-Canarsie Local",
            agencyColorHex: "#A7A9AC",
            modalClass: .subway,
            coordinates: [station, initialVehicle],
            stationCoordinate: station,
            vehicleCoordinate: initialVehicle
        )
        
        // Simulating live vehicle telemetry update (same route/station, updated vehicle location)
        let updatedCmd = RouteInspectionCommand(
            id: initialCmd.id,
            routeId: initialCmd.routeId,
            lineName: initialCmd.lineName,
            agencyColorHex: initialCmd.agencyColorHex,
            modalClass: initialCmd.modalClass,
            coordinates: initialCmd.coordinates,
            stationCoordinate: initialCmd.stationCoordinate,
            vehicleCoordinate: updatedVehicle
        )
        
        XCTAssertEqual(initialCmd.id, updatedCmd.id, "Trip ID must remain invariant across live telemetry updates")
        XCTAssertEqual(updatedCmd.vehicleCoordinate?.latitude, updatedVehicle.latitude)
        XCTAssertEqual(updatedCmd.vehicleCoordinate?.longitude, updatedVehicle.longitude)
        
        // Bounding box computed from updated command must enclose the updated vehicle coordinate
        let bounds = updatedCmd.computedBoundingBox(tightVehicleBounding: true)
        XCTAssertNotNil(bounds)
        if let b = bounds {
            XCTAssertLessThanOrEqual(b.sw.latitude, updatedVehicle.latitude)
            XCTAssertGreaterThanOrEqual(b.ne.latitude, station.latitude)
        }
    }

    // MARK: - 11. Wave Pre-T.7 Adaptive Viewport, Horizon Switcher & Vector Beacon Tests (WPT7)

    func testPreT7_AdaptiveCameraMode_ClassificationByTrackDistance() {
        let station = CLLocationCoordinate2D(latitude: 40.7527, longitude: -73.9772) // Grand Central
        let closeVehicle = CLLocationCoordinate2D(latitude: 40.7460, longitude: -73.9820) // ~900m away (33rd St)
        let distantVehicle = CLLocationCoordinate2D(latitude: 40.8525, longitude: -73.8281) // ~15km away (Pelham Bay Park)
        
        let trackCoords = [
            closeVehicle,
            CLLocationCoordinate2D(latitude: 40.7500, longitude: -73.9790),
            station,
            CLLocationCoordinate2D(latitude: 40.7800, longitude: -73.9500),
            distantVehicle
        ]
        
        // 1. Close vehicle (<= 2.5km) -> .dualFraming
        let closeMode = RouteInspectionCommand.classifyCameraMode(
            station: station,
            vehicle: closeVehicle,
            coordinates: trackCoords,
            minutes: 6
        )
        if case .dualFraming(let dist) = closeMode {
            XCTAssertLessThanOrEqual(dist, 2500.0, "Close vehicle must be classified as dualFraming with distance <= 2.5km")
        } else {
            XCTFail("Close vehicle should yield .dualFraming, got \(closeMode)")
        }
        
        // 2. Imminence <= 4 min triggers dual framing even if slightly beyond 2.5km
        let imminentMode = RouteInspectionCommand.classifyCameraMode(
            station: station,
            vehicle: CLLocationCoordinate2D(latitude: 40.7300, longitude: -73.9900),
            coordinates: trackCoords,
            minutes: 3
        )
        if case .dualFraming = imminentMode {
            // Expected
        } else {
            XCTFail("Imminent vehicle (minutes <= 4) must yield .dualFraming, got \(imminentMode)")
        }
        
        // 3. Distant vehicle (> 2.5km and minutes > 4) -> .vehicleTracking
        let distantMode = RouteInspectionCommand.classifyCameraMode(
            station: station,
            vehicle: distantVehicle,
            coordinates: trackCoords,
            minutes: 18
        )
        if case .vehicleTracking(let dist) = distantMode {
            XCTAssertGreaterThan(dist, 2500.0, "Distant vehicle must be classified as vehicleTracking with distance > 2.5km")
        } else {
            XCTFail("Distant vehicle should yield .vehicleTracking, got \(distantMode)")
        }
        
        // 4. Missing vehicle coordinate -> .stationAnchor
        let missingVehicleMode = RouteInspectionCommand.classifyCameraMode(
            station: station,
            vehicle: nil,
            coordinates: trackCoords
        )
        XCTAssertEqual(missingVehicleMode, .stationAnchor, "Missing telemetry must anchor to station")
        
        // 5. Boarding / minutes == 0 -> .stationAnchor
        let boardingMode = RouteInspectionCommand.classifyCameraMode(
            station: station,
            vehicle: closeVehicle,
            coordinates: trackCoords,
            minutes: 0,
            status: "Boarding"
        )
        XCTAssertEqual(boardingMode, .stationAnchor, "Boarding consist at platform must anchor to station")
    }

    func testPreT7_PolylineTrackDistanceCalculation() {
        let ptA = CLLocationCoordinate2D(latitude: 40.7500, longitude: -73.9800)
        let ptB = CLLocationCoordinate2D(latitude: 40.7550, longitude: -73.9750)
        let ptC = CLLocationCoordinate2D(latitude: 40.7600, longitude: -73.9700)
        
        let polyline = [ptA, ptB, ptC]
        let distance = RouteInspectionCommand.calculateTrackDistance(between: ptA, and: ptC, in: polyline)
        
        let locA = CLLocation(latitude: ptA.latitude, longitude: ptA.longitude)
        let locB = CLLocation(latitude: ptB.latitude, longitude: ptB.longitude)
        let locC = CLLocation(latitude: ptC.latitude, longitude: ptC.longitude)
        let expectedDist = locA.distance(from: locB) + locB.distance(from: locC)
        
        XCTAssertEqual(distance, expectedDist, accuracy: 1.0, "Track distance must accurately sum polyline segment lengths")
    }

    @MainActor
    func testPreT7_FocusCapsuleViewConstruction() {
        let station = CLLocationCoordinate2D(latitude: 40.7527, longitude: -73.9772)
        let vehicle = CLLocationCoordinate2D(latitude: 40.7460, longitude: -73.9820)
        
        var focusedCoord: CLLocationCoordinate2D? = nil
        let capsule = TransitFocusSwitcherCapsule(
            stationName: "Grand Central-42 St",
            stationCoordinate: station,
            vehicleStopName: "33rd St",
            vehicleCoordinate: vehicle,
            etaMinutes: 3,
            onFocus: { coord in
                focusedCoord = coord
            }
        )
        
        let hosting = UIHostingController(rootView: capsule)
        XCTAssertNotNil(hosting.view)
        
        // Invoke focus callback directly
        capsule.onFocus?(station)
        guard let focused = focusedCoord else {
            XCTFail("focusedCoord should not be nil")
            return
        }
        XCTAssertEqual(focused.latitude, station.latitude, accuracy: 0.0001)
    }

    func testPreT7_OffScreenBeaconState() {
        let beacon = OffScreenBeaconState(
            routeId: "6",
            routeColorHex: "#00933C",
            stopsAway: 3,
            minutes: 4,
            screenPosition: CGPoint(x: 200, y: 120),
            bearingRadians: 1.57,
            vehicleCoordinate: CLLocationCoordinate2D(latitude: 40.78, longitude: -73.95)
        )
        
        XCTAssertEqual(beacon.routeId, "6")
        XCTAssertEqual(beacon.stopsAway, 3)
        XCTAssertEqual(beacon.minutes, 4)
        XCTAssertEqual(beacon.bearingRadians, 1.57, accuracy: 0.01)
        XCTAssertEqual(beacon.screenPosition.x, 200)
    }

    func testPreT7_NonCollapsingLadderTaps_SourceCodeAudit() throws {
        let filePath = #filePath
        let testsDir = URL(fileURLWithPath: filePath).deletingLastPathComponent()
        let sheetFile = testsDir.deletingLastPathComponent().appendingPathComponent("Derivee/TransitRevealSheet.swift")
        let content = try String(contentsOf: sheetFile, encoding: .utf8)
        
        // TransitRevealSheet inspectorView onFocusMap closures must not mutate selectedDetent to inspectionPeekDetent
        // Check that inspectorView for GuidewayRunInspector and SurfaceRunInspector does not contain peek detent assignment
        let hasForcedCollapse = content.contains("onFocusMap: { coord in\n                    onFocusMap?(coord)\n                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {\n                        selectedDetent = Self.inspectionPeekDetent")
        XCTAssertFalse(
            hasForcedCollapse,
            "Pre-T.7 Violation: onFocusMap in inspectorView must NOT collapse selectedDetent to inspectionPeekDetent"
        )
    }

    func testPreT7_SourceCodeAudit_MapView3StateEngine() throws {
        let filePath = #filePath
        let testsDir = URL(fileURLWithPath: filePath).deletingLastPathComponent()
        let mapViewFile = testsDir.deletingLastPathComponent().appendingPathComponent("Derivee/MapView.swift")
        let content = try String(contentsOf: mapViewFile, encoding: .utf8)
        
        // 1. Must implement centerCoordinateInUpperViewport with asymmetric bottom padding (+ 24.0)
        XCTAssertTrue(
            content.contains("centerCoordinateInUpperViewport"),
            "Pre-T.7 Violation: MapView.Coordinator must implement centerCoordinateInUpperViewport"
        )
        XCTAssertTrue(
            content.contains("+ 24.0"),
            "Pre-T.7 Violation: Viewport framing must include asymmetric bottom padding H_sheet + 24pt"
        )
        
        // 2. Must classify camera mode in frameRouteAndStation
        XCTAssertTrue(
            content.contains("classifyCameraMode"),
            "Pre-T.7 Violation: frameRouteAndStation must classify camera mode"
        )
        
        // 3. Must implement off-screen beacon tracking
        XCTAssertTrue(
            content.contains("updateOffScreenBeacon"),
            "Pre-T.7 Violation: MapView.Coordinator must implement updateOffScreenBeacon"
        )
        
        // 4. Must track user gestures to suppress auto-transition
        XCTAssertTrue(
            content.contains("hasUserPannedDuringInspection"),
            "Pre-T.7 Violation: MapView.Coordinator must track hasUserPannedDuringInspection"
        )
    }
}



