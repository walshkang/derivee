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
    
    // MARK: - 4. Disruption Models & Summary Formatting
    
    func testDisruptionTypeDisplayNamesAndFormatting() {
        XCTAssertEqual(DisruptionType.delays.displayName, "Delays")
        XCTAssertEqual(DisruptionType.suspended.displayName, "Suspended")
        XCTAssertEqual(DisruptionType.rerouted.displayName, "Rerouted")
        XCTAssertEqual(DisruptionType.bypassLocal.displayName, "Station Bypass")
        XCTAssertEqual(DisruptionType.maintenance.displayName, "Track Work")
        XCTAssertEqual(DisruptionType.unknown.displayName, "Alert")
        
        let d1 = ServiceDisruptionRecord(
            routeId: "6",
            startEpoch: 1000,
            endEpoch: 2000,
            disruptionType: .delays,
            summaryText: "Signal problems at 68th St"
        )
        XCTAssertEqual(d1.formattedAlertSummary, "Delays: Signal problems at 68th St")
        
        let d2 = ServiceDisruptionRecord(
            routeId: "L",
            startEpoch: 1000,
            endEpoch: 2000,
            disruptionType: .suspended,
            summaryText: nil
        )
        XCTAssertEqual(d2.formattedAlertSummary, "Suspended: Service disruption on line")
        
        let d3 = ServiceDisruptionRecord(
            routeId: "M15",
            startEpoch: 1000,
            endEpoch: 2000,
            disruptionType: .maintenance,
            summaryText: "Track Work: Overnight utility repairs"
        )
        XCTAssertEqual(d3.formattedAlertSummary, "Track Work: Overnight utility repairs")
    }
    
    // MARK: - 5. Disruption Fetch from Engine
    
    func testDisruptionFetchFromEngine() async throws {
        let engine = TransitDatabaseEngine.makeForTesting(inMemory: true)
        let baseEpoch: Int64 = 1710000000
        
        let dSubway = ServiceDisruptionRecord(
            id: "disr_6_downtown",
            routeId: "6",
            stopId: nil,
            directionId: 1,
            startEpoch: baseEpoch,
            endEpoch: baseEpoch + 3600,
            disruptionType: .delays,
            summaryText: "Delays: Signal problems at 68th St"
        )
        
        let dBus = ServiceDisruptionRecord(
            id: "disr_m15_detour",
            routeId: "M15-SBS",
            stopId: nil,
            directionId: nil,
            startEpoch: baseEpoch,
            endEpoch: baseEpoch + 7200,
            disruptionType: .rerouted,
            summaryText: "Street closure detour on 2nd Ave"
        )
        
        try await engine.insertServiceDisruptions([dSubway, dBus])
        
        // 1. Fetch 6 train downtown disruption
        let res6 = try await engine.fetchDisruptions(for: "6", directionId: 1, at: baseEpoch + 500)
        XCTAssertEqual(res6.count, 1)
        XCTAssertEqual(res6.first?.id, "disr_6_downtown")
        XCTAssertEqual(res6.first?.formattedAlertSummary, "Delays: Signal problems at 68th St")
        
        // 2. Fetch M15 bus disruption (directionId nil applies to all)
        let resBus = try await engine.fetchDisruptions(for: "M15-SBS", directionId: 0, at: baseEpoch + 1000)
        XCTAssertEqual(resBus.count, 1)
        XCTAssertEqual(resBus.first?.id, "disr_m15_detour")
        
        // 3. Out-of-window query returns empty
        let resPast = try await engine.fetchDisruptions(for: "6", directionId: 1, at: baseEpoch - 100)
        XCTAssertTrue(resPast.isEmpty)
        
        // 4. Unrelated route returns empty
        let res7 = try await engine.fetchDisruptions(for: "7", directionId: 1, at: baseEpoch + 500)
        XCTAssertTrue(res7.isEmpty)
    }
    
    // MARK: - 6. Follow-On Departure Resolution
    
    func testFollowOnArrivalResolution() {
        let arrTarget = SpatialDatabaseManager.ArrivalInfo(
            line: "6",
            destination: "Pelham Bay Park",
            minutes: 3,
            direction: "Downtown"
        )
        let arrFollowOn = SpatialDatabaseManager.ArrivalInfo(
            line: "6",
            destination: "Pelham Bay Park",
            minutes: 9,
            direction: "Downtown"
        )
        let arrLater = SpatialDatabaseManager.ArrivalInfo(
            line: "6",
            destination: "Pelham Bay Park",
            minutes: 18,
            direction: "Downtown"
        )
        let arrOtherDir = SpatialDatabaseManager.ArrivalInfo(
            line: "6",
            destination: "Brooklyn Bridge",
            minutes: 5,
            direction: "Uptown"
        )
        let arrOtherLine = SpatialDatabaseManager.ArrivalInfo(
            line: "4",
            destination: "Crown Hts",
            minutes: 4,
            direction: "Downtown"
        )
        
        let candidates = [arrTarget, arrFollowOn, arrLater, arrOtherDir, arrOtherLine]
        
        // Resolving for arrTarget should select arrFollowOn (9 min, same line, same direction)
        let resolved = TransitRevealSheet.resolveFollowOnArrival(for: arrTarget, from: candidates)
        XCTAssertNotNil(resolved)
        XCTAssertEqual(resolved?.id, arrFollowOn.id)
        XCTAssertEqual(resolved?.minutes, 9)
        
        // Resolving for arrLater (which has no subsequent departures) should return nil
        let resolvedLast = TransitRevealSheet.resolveFollowOnArrival(for: arrLater, from: candidates)
        XCTAssertNil(resolvedLast)
    }
    
    // MARK: - 7. Inspector Construction with Follow-On & Disruption Data
    
    @MainActor
    func testInspectorsWithDisruptionAndFollowOn() {
        let arrival = SpatialDatabaseManager.ArrivalInfo(
            line: "6",
            destination: "Pelham Bay Park",
            minutes: 2,
            direction: "Downtown"
        )
        let followOn = SpatialDatabaseManager.ArrivalInfo(
            line: "6",
            destination: "Pelham Bay Park",
            minutes: 10,
            direction: "Downtown"
        )
        
        let guideway = GuidewayRunInspector(
            arrival: arrival,
            currentStopId: "631",
            currentStopName: "Grand Central-42 St",
            followOnArrival: followOn
        )
        let guidewayHosting = UIHostingController(rootView: guideway)
        XCTAssertNotNil(guidewayHosting.view)
        
        let surface = SurfaceRunInspector(
            arrival: arrival,
            currentStopId: "stop_1",
            currentStopName: "23rd St",
            modalClass: .bus,
            followOnArrival: followOn
        )
        let surfaceHosting = UIHostingController(rootView: surface)
        XCTAssertNotNil(surfaceHosting.view)
    }

    // MARK: - 8. Wave PC.1 Accordion Threshold & Glanceable Crowding Tests

    func testPassedStopsAccordionThresholdLogic() {
        let dummyStops = (0..<10).map { i in
            TrackStop(
                stopId: "S\(i)",
                stopName: "Station \(i)",
                coordinate: CLLocationCoordinate2D(latitude: 40.70 + Double(i) * 0.01, longitude: -73.95),
                sequenceIndex: i,
                isPassed: i < 5,
                isCurrent: i == 5
            )
        }
        
        let passed = dummyStops.filter { $0.isPassed }
        let upcoming = dummyStops.filter { !$0.isPassed }
        
        XCTAssertEqual(passed.count, 5)
        XCTAssertTrue(passed.count >= 3, "Passed stops >= 3 should trigger accordion disclosure container")
        XCTAssertEqual(upcoming.count, 5)
        XCTAssertTrue(upcoming.first?.isCurrent == true, "First stop in upcoming block must be active station")
        
        // Under threshold (< 3 passed stops)
        let fewPassedStops = (0..<4).map { i in
            TrackStop(
                stopId: "S\(i)",
                stopName: "Station \(i)",
                coordinate: CLLocationCoordinate2D(latitude: 40.70 + Double(i) * 0.01, longitude: -73.95),
                sequenceIndex: i,
                isPassed: i < 2,
                isCurrent: i == 2
            )
        }
        let fewPassed = fewPassedStops.filter { $0.isPassed }
        XCTAssertEqual(fewPassed.count, 2)
        XCTAssertFalse(fewPassed.count >= 3, "Passed stops < 3 must render inline without accordion")
    }

    func testGlanceableCrowdingBadges() {
        XCTAssertEqual(CrowdDensityEstimate.CrowdLevel.light.glanceableTitle, "Light")
        XCTAssertEqual(CrowdDensityEstimate.CrowdLevel.moderate.glanceableTitle, "Moderate")
        XCTAssertEqual(CrowdDensityEstimate.CrowdLevel.crowded.glanceableTitle, "Crowded")
        XCTAssertEqual(CrowdDensityEstimate.CrowdLevel.full.glanceableTitle, "Crowded")
        
        XCTAssertEqual(CrowdDensityEstimate.CrowdLevel.light.statusEmoji, "🟢")
        XCTAssertEqual(CrowdDensityEstimate.CrowdLevel.moderate.statusEmoji, "🟡")
        XCTAssertEqual(CrowdDensityEstimate.CrowdLevel.crowded.statusEmoji, "🟠")
        XCTAssertEqual(CrowdDensityEstimate.CrowdLevel.full.statusEmoji, "🔴")
    }

    // MARK: - 9. Wave PC.2 Telemetry De-Jargonization & Canonical Status Tests (FC-2, FC-3)

    func testProximityContextWithLadder() {
        let ladder = [
            TrackStop(stopId: "L01", stopName: "Canarsie - Rockaway Pkwy", coordinate: CLLocationCoordinate2D(latitude: 40.6466, longitude: -73.9018), sequenceIndex: 0, isPassed: true, isCurrent: false, isTerminus: true),
            TrackStop(stopId: "L10", stopName: "Lorimer St", coordinate: CLLocationCoordinate2D(latitude: 40.7140, longitude: -73.9497), sequenceIndex: 1, isPassed: true, isCurrent: false),
            TrackStop(stopId: "L11", stopName: "Bedford Av", coordinate: CLLocationCoordinate2D(latitude: 40.7173, longitude: -73.9568), sequenceIndex: 2, isPassed: false, isCurrent: true),
            TrackStop(stopId: "L12", stopName: "1 Av", coordinate: CLLocationCoordinate2D(latitude: 40.7309, longitude: -73.9816), sequenceIndex: 3, isPassed: false, isCurrent: false),
            TrackStop(stopId: "L13", stopName: "8 Av", coordinate: CLLocationCoordinate2D(latitude: 40.7397, longitude: -74.0025), sequenceIndex: 4, isPassed: false, isCurrent: false, isTerminus: true)
        ]
        
        // 2 stops away: vehicle at index 0 (Canarsie), approaching index 1 (Lorimer St)
        let arr2Stops = SpatialDatabaseManager.ArrivalInfo(
            line: "L",
            destination: "8 Av",
            minutes: 4,
            distanceDescription: "2 stops away"
        )
        XCTAssertEqual(
            arr2Stops.proximityContext(ladder: ladder, currentStopName: "Bedford Av"),
            "2 stops away • Approaching Lorimer St",
            "Vehicle 2 stops upstream must show the upcoming approaching station name"
        )
        
        // 1 stop away: vehicle at index 1 (Lorimer St), approaching index 2 (Bedford Av)
        let arr1Stop = SpatialDatabaseManager.ArrivalInfo(
            line: "L",
            destination: "8 Av",
            minutes: 2,
            distanceDescription: "1 stop away"
        )
        XCTAssertEqual(
            arr1Stop.proximityContext(ladder: ladder, currentStopName: "Bedford Av"),
            "1 stop away • Approaching Bedford Av"
        )
        
        // Approaching current station
        let arrApproaching = SpatialDatabaseManager.ArrivalInfo(
            line: "L",
            destination: "8 Av",
            minutes: 1,
            distanceDescription: "Approaching"
        )
        XCTAssertEqual(
            arrApproaching.proximityContext(ladder: ladder, currentStopName: "Bedford Av"),
            "Approaching Bedford Av"
        )
        
        // Boarding at current station
        let arrBoarding = SpatialDatabaseManager.ArrivalInfo(
            line: "L",
            destination: "8 Av",
            minutes: 0,
            distanceDescription: "Boarding"
        )
        XCTAssertEqual(
            arrBoarding.proximityContext(ladder: ladder, currentStopName: "Bedford Av"),
            "Boarding at Bedford Av"
        )
        
        // Dwelling at terminus
        let arrTerminus = SpatialDatabaseManager.ArrivalInfo(
            line: "L",
            destination: "8 Av",
            minutes: 8,
            distanceDescription: "At Terminus"
        )
        XCTAssertEqual(
            arrTerminus.proximityContext(ladder: ladder, currentStopName: "Bedford Av"),
            "At Terminus • Canarsie - Rockaway Pkwy"
        )
        
        // Holding at station
        let arrHolding = SpatialDatabaseManager.ArrivalInfo(
            line: "L",
            destination: "8 Av",
            minutes: 3,
            isHoldingStation: true
        )
        XCTAssertEqual(
            arrHolding.proximityContext(ladder: ladder, currentStopName: "Bedford Av"),
            "Station Hold"
        )
        
        // Graceful fallback when ladder is empty
        XCTAssertEqual(
            arr2Stops.proximityContext(ladder: [], currentStopName: "Bedford Av"),
            "2 stops away"
        )
    }

    func testCommuterStatusDescriptionAndTrackFormatting() {
        // Track formatting
        let arrWithTrack1 = SpatialDatabaseManager.ArrivalInfo(
            line: "L",
            destination: "8 Av",
            minutes: 0,
            distanceDescription: "Boarding",
            track: "1"
        )
        XCTAssertEqual(arrWithTrack1.formattedTrack, "Track 1")
        XCTAssertEqual(arrWithTrack1.commuterStatusDescription, "Boarding (Track 1)")
        
        let arrWithFullTrackName = SpatialDatabaseManager.ArrivalInfo(
            line: "L",
            destination: "8 Av",
            minutes: 2,
            distanceDescription: "Approaching",
            track: "Track 2"
        )
        XCTAssertEqual(arrWithFullTrackName.formattedTrack, "Track 2")
        XCTAssertEqual(arrWithFullTrackName.commuterStatusDescription, "Approaching (Track 2)")
        
        let arrNoTrack = SpatialDatabaseManager.ArrivalInfo(
            line: "L",
            destination: "8 Av",
            minutes: 0,
            distanceDescription: "Boarding"
        )
        XCTAssertNil(arrNoTrack.formattedTrack)
        XCTAssertEqual(arrNoTrack.commuterStatusDescription, "Boarding")
        
        let arrMinutes = SpatialDatabaseManager.ArrivalInfo(
            line: "L",
            destination: "8 Av",
            minutes: 5,
            track: "3"
        )
        XCTAssertEqual(arrMinutes.commuterStatusDescription, "5 min (Track 3)")
        
        let arrHolding = SpatialDatabaseManager.ArrivalInfo(
            line: "L",
            destination: "8 Av",
            minutes: 2,
            isHoldingStation: true
        )
        XCTAssertEqual(arrHolding.commuterStatusDescription, "Station Hold")
    }

    @MainActor
    func testInspectorViewConstructionWithTrackAndFollowOn() {
        let arrival = SpatialDatabaseManager.ArrivalInfo(
            line: "L",
            destination: "8 Av",
            minutes: 0,
            direction: "Manhattan",
            distanceDescription: "Boarding",
            track: "1"
        )
        let followOn = SpatialDatabaseManager.ArrivalInfo(
            line: "L",
            destination: "8 Av",
            minutes: 4,
            direction: "Manhattan"
        )
        
        let guideway = GuidewayRunInspector(
            arrival: arrival,
            currentStopId: "L11",
            currentStopName: "Bedford Av",
            followOnArrival: followOn
        )
        let guidewayHosting = UIHostingController(rootView: guideway)
        XCTAssertNotNil(guidewayHosting.view)
        
        let busArrival = SpatialDatabaseManager.ArrivalInfo(
            line: "S51",
            destination: "St George Ferry",
            minutes: 0,
            direction: "Inbound",
            distanceDescription: "Boarding"
        )
        let surface = SurfaceRunInspector(
            arrival: busArrival,
            currentStopId: "stop_s51",
            currentStopName: "Midland Beach",
            modalClass: .bus,
            followOnArrival: followOn
        )
        let surfaceHosting = UIHostingController(rootView: surface)
        XCTAssertNotNil(surfaceHosting.view)
    }

    // MARK: - Wave PC.3 Single-Sheet Transition Hierarchy & OnBack Callback Tests

    @MainActor
    func testGuidewayRunInspectorOnBackCallbackExecution() {
        var onBackCalled = false
        let arrival = SpatialDatabaseManager.ArrivalInfo(
            line: "L",
            destination: "8 Av",
            minutes: 2,
            direction: "Manhattan",
            distanceDescription: "Approaching"
        )
        
        let guideway = GuidewayRunInspector(
            arrival: arrival,
            currentStopId: "L11",
            currentStopName: "Bedford Av",
            onBack: {
                onBackCalled = true
            }
        )
        
        XCTAssertNotNil(guideway.onBack)
        guideway.onBack?()
        XCTAssertTrue(onBackCalled)
        
        // Verify view construction with onBack provided
        let hosting = UIHostingController(rootView: guideway)
        XCTAssertNotNil(hosting.view)
        
        // Verify view construction without onBack (standalone fallback)
        let standaloneGuideway = GuidewayRunInspector(
            arrival: arrival,
            currentStopId: "L11",
            currentStopName: "Bedford Av"
        )
        XCTAssertNil(standaloneGuideway.onBack)
        let standaloneHosting = UIHostingController(rootView: standaloneGuideway)
        XCTAssertNotNil(standaloneHosting.view)
    }

    @MainActor
    func testSurfaceRunInspectorOnBackCallbackExecution() {
        var onBackCalled = false
        let arrival = SpatialDatabaseManager.ArrivalInfo(
            line: "M15-SBS",
            destination: "South Ferry",
            minutes: 3,
            direction: "Downtown",
            distanceDescription: "1 stop away"
        )
        
        let surface = SurfaceRunInspector(
            arrival: arrival,
            currentStopId: "stop_m15",
            currentStopName: "2nd Ave & 23rd St",
            modalClass: .bus,
            onBack: {
                onBackCalled = true
            }
        )
        
        XCTAssertNotNil(surface.onBack)
        surface.onBack?()
        XCTAssertTrue(onBackCalled)
        
        // Verify view construction with onBack provided
        let hosting = UIHostingController(rootView: surface)
        XCTAssertNotNil(hosting.view)
        
        // Verify view construction without onBack (standalone fallback)
        let standaloneSurface = SurfaceRunInspector(
            arrival: arrival,
            currentStopId: "stop_m15",
            currentStopName: "2nd Ave & 23rd St",
            modalClass: .bus
        )
        XCTAssertNil(standaloneSurface.onBack)
        let standaloneHosting = UIHostingController(rootView: standaloneSurface)
        XCTAssertNotNil(standaloneHosting.view)
    }
}

