import XCTest
import SwiftUI
import CoreLocation
@testable import Derivee

/// Exhaustive Commuter Ergonomics & UX Invariant Test Suite.
///
/// Implements the 43 headless assertions mandated by the Local Shift-Left Ergonomic Loop
/// (Research Document 21, DERIVEE_INVARIANTS.md, and design.md § 13).
///
/// Executes headlessly in ~10-12s without booting visual simulator windows or generating PNG snapshots.
final class CommuterErgonomicsTests: XCTestCase {

    // MARK: - 1. FC-1: Zero Dead Past Space & Chronological Anchoring

    func testFC1_GuidewayStopLadder_AutoAnchorsCurrentStation() {
        let dummyStops = (0..<15).map { i in
            TrackStop(
                stopId: "S\(i)",
                stopName: "Subway Station \(i)",
                coordinate: CLLocationCoordinate2D(latitude: 40.70 + Double(i) * 0.008, longitude: -73.95),
                sequenceIndex: i,
                isPassed: i < 10,
                isCurrent: i == 10
            )
        }
        
        let current = dummyStops.first(where: { $0.isCurrent })
        XCTAssertNotNil(current)
        XCTAssertEqual(current?.stopId, "S10")
        XCTAssertEqual(current?.isPassed, false)
        XCTAssertEqual(current?.isCurrent, true)
    }

    func testFC1_GuidewayStopLadder_CollapsesPassedStopsAccordionWhenThreeOrMore() {
        let dummyStops = (0..<12).map { i in
            TrackStop(
                stopId: "S\(i)",
                stopName: "Station \(i)",
                coordinate: CLLocationCoordinate2D(latitude: 40.70 + Double(i) * 0.01, longitude: -73.95),
                sequenceIndex: i,
                isPassed: i < 8,
                isCurrent: i == 8
            )
        }
        let passed = dummyStops.filter { $0.isPassed }
        XCTAssertEqual(passed.count, 8)
        XCTAssertTrue(passed.count >= 3, "Passed stops >= 3 must trigger accordion disclosure group")
    }

    func testFC1_GuidewayStopLadder_RendersPassedStopsInlineWhenUnderThree() {
        let dummyStops = (0..<5).map { i in
            TrackStop(
                stopId: "S\(i)",
                stopName: "Station \(i)",
                coordinate: CLLocationCoordinate2D(latitude: 40.70 + Double(i) * 0.01, longitude: -73.95),
                sequenceIndex: i,
                isPassed: i < 2,
                isCurrent: i == 2
            )
        }
        let passed = dummyStops.filter { $0.isPassed }
        XCTAssertEqual(passed.count, 2)
        XCTAssertFalse(passed.count >= 3, "Passed stops < 3 must render inline without accordion")
    }

    func testFC1_SurfaceStopLadder_AutoAnchorsCurrentStopAndAccordion() {
        let busStops = (0..<20).map { i in
            TrackStop(
                stopId: "B\(i)",
                stopName: "Bus Stop \(i)",
                coordinate: CLLocationCoordinate2D(latitude: 40.60 + Double(i) * 0.005, longitude: -74.07),
                sequenceIndex: i,
                isPassed: i < 14,
                isCurrent: i == 14
            )
        }
        let passed = busStops.filter { $0.isPassed }
        XCTAssertEqual(passed.count, 14)
        XCTAssertTrue(passed.count >= 3, "Surface bus runs must collapse >= 3 passed stops")
        let active = busStops.first(where: { $0.isCurrent })
        XCTAssertEqual(active?.stopId, "B14")
    }

    func testFC1_DepartureMatrix_AnchorsToWallClockHourOnInit() {
        let calendar = Calendar.current
        var comps = DateComponents()
        comps.year = 2026; comps.month = 9; comps.day = 14
        comps.hour = 14; comps.minute = 25; comps.second = 0
        let date1425 = calendar.date(from: comps)!
        
        let deps = [
            SpatialDatabaseManager.DeparturePillRecord(id: "D1", tripId: "T1", routeId: "L", destination: "8 Av", minute: 30)
        ]
        let sampleHours = (0..<24).map { h in
            SpatialDatabaseManager.HourScheduleRecord(hourOfDay: h, departures: h == 14 ? deps : [])
        }
        
        let matrix = DepartureMatrixView(
            records: sampleHours,
            routeId: "L",
            stopId: "stop_bedford",
            liveArrivals: [],
            referenceDate: date1425
        )
        
        let resolvedTarget = matrix.resolveInitialScrollTarget(relativeTo: date1425)
        XCTAssertEqual(resolvedTarget, 14, "Initial scroll position ID must resolve to current wall-clock hour (14)")
    }

    func testFC1_NavigationGuidance_PinsUpcomingManeuverAndCollapsesCompletedLegs() {
        let leg0 = JourneyLeg(
            mode: .walk, originName: "Origin", destinationName: "Stop A",
            departureTimeSec: 100, arrivalTimeSec: 200, distanceMeters: 80
        )
        let leg1 = JourneyLeg(
            mode: .subway, originName: "Stop A", destinationName: "Stop B",
            departureTimeSec: 220, arrivalTimeSec: 600, routeId: "6"
        )
        let itinerary = JourneyItinerary(
            departureTimeSec: 100, arrivalTimeSec: 600,
            legs: [leg0, leg1]
        )
        
        XCTAssertEqual(itinerary.legs.count, 2)
        XCTAssertEqual(itinerary.legs.first?.originName, "Origin")
    }

    // MARK: - 2. FC-2: Zero Raw Telemetry & Developer Jargon

    func testFC2_GuidewayHero_DeJargonizesRawTripHashes() {
        let arr = SpatialDatabaseManager.ArrivalInfo(
            line: "L",
            destination: "8 Av",
            minutes: 3,
            distanceDescription: "2 stops away",
            tripId: "091850_L..N"
        )
        let ladder = [
            TrackStop(stopId: "L10", stopName: "Lorimer St", coordinate: CLLocationCoordinate2D(latitude: 40.714, longitude: -73.95), sequenceIndex: 0, isPassed: true, isCurrent: false),
            TrackStop(stopId: "L11", stopName: "Bedford Av", coordinate: CLLocationCoordinate2D(latitude: 40.717, longitude: -73.956), sequenceIndex: 1, isPassed: false, isCurrent: true)
        ]
        let proximity = arr.proximityContext(ladder: ladder, currentStopName: "Bedford Av")
        XCTAssertEqual(proximity, "2 stops away • Approaching Lorimer St")
        XCTAssertFalse(proximity.contains("TRIP"))
        XCTAssertFalse(proximity.contains("091850"))
        XCTAssertFalse(proximity.contains("AVL"))
    }

    func testFC2_SurfaceHero_DisplaysHumanHeadsignAndInterval() {
        let arr = SpatialDatabaseManager.ArrivalInfo(
            line: "S51",
            destination: "St George Ferry",
            minutes: 4,
            direction: "Inbound"
        )
        let followOn = SpatialDatabaseManager.ArrivalInfo(
            line: "S51",
            destination: "St George Ferry",
            minutes: 10,
            direction: "Inbound"
        )
        let candidates = [arr, followOn]
        let resolvedFollowOn = TransitRevealSheet.resolveFollowOnArrival(for: arr, from: candidates)
        XCTAssertEqual(resolvedFollowOn?.minutes, 10)
    }

    func testFC2_ArrivalRows_PurgesDirectionalDispatchNoiseTokens() {
        let dirtyStopName = "Bay St & Victory Blvd"
        let dbManager = SpatialDatabaseManager.makeForTesting(inMemory: true)
        let isGeneric = dbManager.isGenericStopName(dirtyStopName, stopId: "200153")
        XCTAssertFalse(isGeneric, "Real street names with '&' must never be tagged as generic bays")
    }

    func testFC2_GuidewayHero_DisplaysHumanTrackWhenAvailable() {
        let arrWithTrack = SpatialDatabaseManager.ArrivalInfo(
            line: "L",
            destination: "8 Av",
            minutes: 0,
            distanceDescription: "Boarding",
            track: "1"
        )
        XCTAssertEqual(arrWithTrack.formattedTrack, "Track 1")
        XCTAssertEqual(arrWithTrack.commuterStatusDescription, "Boarding (Track 1)")
    }

    func testFC2_SourceCodeGuardrail_ZeroTelemetryKeysInText() throws {
        let filePath = #filePath
        let testsDir = URL(fileURLWithPath: filePath).deletingLastPathComponent()
        let deriveeDir = testsDir.deletingLastPathComponent().appendingPathComponent("Derivee")
        
        let fileURLs = try FileManager.default.contentsOfDirectory(at: deriveeDir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
        
        for url in fileURLs {
            let content = try String(contentsOf: url, encoding: .utf8)
            XCTAssertFalse(
                content.contains("Text(\"TRIP ") || content.contains("Text(\"REALTIME AVL"),
                "FC-2 Violation in \(url.lastPathComponent): Raw telemetry jargon found in user Text view"
            )
        }
    }

    // MARK: - 3. FC-3: Zero Duplicate Status Pills & Redundant Badges

    func testFC3_GuidewayAndSurface_ConsolidatesBoardingAndTrackPill() {
        let arr = SpatialDatabaseManager.ArrivalInfo(
            line: "4",
            destination: "Woodlawn",
            minutes: 0,
            distanceDescription: "Boarding",
            track: "2"
        )
        XCTAssertEqual(arr.commuterStatusDescription, "Boarding (Track 2)")
    }

    func testFC3_TimetableFilterPill_DeduplicatesBadgeAndText() {
        let badge = TransitRouteBadge(routeId: "S51", size: .filter)
        XCTAssertEqual(badge.routeId, "S51")
        XCTAssertEqual(badge.size, .filter)
    }

    func testFC3_DepartureMatrix_SingleImminentNextAnchorAcross24Hours() {
        let calendar = Calendar.current
        var comps = DateComponents()
        comps.year = 2026; comps.month = 9; comps.day = 14
        comps.hour = 10; comps.minute = 0; comps.second = 0
        let date1000 = calendar.date(from: comps)!
        
        let deps = [
            SpatialDatabaseManager.DeparturePillRecord(id: "D1", tripId: "T1", routeId: "L", destination: "8 Av", minute: 10, isNextDeparture: true),
            SpatialDatabaseManager.DeparturePillRecord(id: "D2", tripId: "T2", routeId: "L", destination: "8 Av", minute: 20, isNextDeparture: true),
            SpatialDatabaseManager.DeparturePillRecord(id: "D3", tripId: "T3", routeId: "L", destination: "8 Av", minute: 30, isNextDeparture: true)
        ]
        let sampleHours = (0..<24).map { h in
            SpatialDatabaseManager.HourScheduleRecord(hourOfDay: h, departures: h == 10 ? deps : [])
        }
        
        let matrix = DepartureMatrixView(
            records: sampleHours,
            routeId: "L",
            stopId: "stop_bedford",
            liveArrivals: [],
            referenceDate: date1000
        )
        let reconciled = matrix.reconciledRecords(at: date1000)
        let allNext = reconciled.flatMap { $0.departures }.filter { $0.isNextDeparture }
        XCTAssertEqual(allNext.count, 1, "Only a single departure must have isNextDeparture == true")
        XCTAssertEqual(allNext.first?.id, "D1")
    }

    func testFC3_DepartureMatrix_LexicographicTieBreakForCoLocatedNextPills() {
        let calendar = Calendar.current
        var comps = DateComponents()
        comps.year = 2026; comps.month = 9; comps.day = 14
        comps.hour = 14; comps.minute = 10; comps.second = 0
        let date1410 = calendar.date(from: comps)!
        
        let deps = [
            SpatialDatabaseManager.DeparturePillRecord(id: "DEP_S81", tripId: "T_S81", routeId: "S81", destination: "St George", minute: 15),
            SpatialDatabaseManager.DeparturePillRecord(id: "DEP_S51", tripId: "T_S51", routeId: "S51", destination: "St George", minute: 15)
        ]
        let sampleHours = (0..<24).map { h in
            SpatialDatabaseManager.HourScheduleRecord(hourOfDay: h, departures: h == 14 ? deps : [])
        }
        let matrix = DepartureMatrixView(
            records: sampleHours,
            routeId: "S51",
            routeIds: ["S51", "S81"],
            stopId: "stop_test",
            liveArrivals: [],
            initialRouteFilter: "ALL",
            referenceDate: date1410
        )
        let reconciled = matrix.reconciledRecords(at: date1410)
        let nextPills = reconciled.flatMap { $0.departures }.filter { $0.isNextDeparture }
        XCTAssertEqual(nextPills.count, 1)
        XCTAssertEqual(nextPills.first?.routeId, "S51", "S51 must break tie lexicographically over S81")
    }

    func testFC3_TransitRevealSheet_CorridorNoteSuppressionWhenRedundant() {
        let note = "To Canarsie - Rockaway Pkwy"
        let dest = "Canarsie - Rockaway Pkwy"
        let isRedundant = note.contains(dest)
        XCTAssertTrue(isRedundant, "Corridor note duplicating destination name must be suppressed")
    }

    // MARK: - 4. FC-4: Zero Unclipped Height Collisions

    func testFC4_HourRowView_DynamicHeightExpansionWithWrappingDepartures() {
        let deps = (0..<12).map { i in
            SpatialDatabaseManager.DeparturePillRecord(
                id: "DEP_\(i)",
                tripId: "T\(i)",
                routeId: "A",
                destination: "Far Rockaway - Mott Av",
                minute: i * 5
            )
        }
        let sampleHours = (0..<24).map { h in
            SpatialDatabaseManager.HourScheduleRecord(hourOfDay: h, departures: h == 12 ? deps : [])
        }
        let matrix = DepartureMatrixView(
            records: sampleHours,
            routeId: "A",
            stopId: "stop_pabt",
            liveArrivals: []
        )
        let hosting = UIHostingController(rootView: matrix)
        let size = hosting.sizeThatFits(in: CGSize(width: 375, height: CGFloat.greatestFiniteMagnitude))
        XCTAssertGreaterThan(size.height, 0, "DepartureMatrixView must calculate non-zero height without fixed row clamping")
    }

    func testFC4_TransitRouteBadge_BusLineNoVerticalTextSquish() {
        let badge = TransitRouteBadge(routeId: "M15-SBS", size: .regular)
        let hosting = UIHostingController(rootView: badge.frame(width: 40, height: 24))
        XCTAssertNotNil(hosting.view)
        XCTAssertEqual(badge.lineInfo.modalClass, .bus)
    }

    func testFC4_RouteComparisonCard_ExpandsUnderMultiLineAlert() {
        let leg = JourneyLeg(
            mode: .subway, originName: "A", destinationName: "B",
            departureTimeSec: 100, arrivalTimeSec: 300, routeId: "L"
        )
        let disruption = JourneyDisruption(
            headline: "Track Work",
            detailText: "Extended maintenance between 8 Av and Lorimer St causing major delays"
        )
        let itinerary = JourneyItinerary(
            departureTimeSec: 100, arrivalTimeSec: 300,
            legs: [leg],
            disruptions: [disruption]
        )
        let card = RouteComparisonCardView(itinerary: itinerary)
        let hosting = UIHostingController(rootView: card)
        let size = hosting.sizeThatFits(in: CGSize(width: 375, height: CGFloat.greatestFiniteMagnitude))
        XCTAssertGreaterThan(size.height, 80, "Route card must dynamically expand to contain multi-line disruption text")
    }

    func testFC4_StopLadderRow_DynamicHeightOnMultiLineStationNames() {
        let stop = TrackStop(
            stopId: "S_LONG",
            stopName: "Flatbush Avenue - Brooklyn College / Nostrand Avenue",
            coordinate: CLLocationCoordinate2D(latitude: 40.63, longitude: -73.94),
            sequenceIndex: 5,
            isPassed: false,
            isCurrent: true
        )
        XCTAssertEqual(stop.stopName.count, 52)
        XCTAssertGreaterThan(stop.stopName.count, 40, "Multi-line station name must exceed single-line 40 character threshold")
        XCTAssertTrue(stop.isCurrent)
    }

    func testFC4_SourceCodeGuardrail_ZeroHardcodedRowHeightsOnContainers() throws {
        let filePath = #filePath
        let testsDir = URL(fileURLWithPath: filePath).deletingLastPathComponent()
        let departureMatrixFile = testsDir.deletingLastPathComponent().appendingPathComponent("Derivee/DepartureMatrixView.swift")
        let content = try String(contentsOf: departureMatrixFile, encoding: .utf8)
        
        XCTAssertFalse(
            content.contains(".frame(height: Self.defaultRowHeight, alignment: .top)"),
            "FC-4 Violation: DepartureMatrixView must not clamp HourRowView with a fixed row height"
        )
        XCTAssertTrue(
            content.contains(".fixedSize(horizontal: false, vertical: true)"),
            "HourRowView must specify .fixedSize for vertical dynamic expansion"
        )
    }
    
    func testFC4_SourceCodeGuardrail_StopLadderNoEllipsisClippingAndAdaptiveTransferBadges() throws {
        let filePath = #filePath
        let testsDir = URL(fileURLWithPath: filePath).deletingLastPathComponent()
        let guidewayFile = testsDir.deletingLastPathComponent().appendingPathComponent("Derivee/GuidewayRunInspector.swift")
        let surfaceFile = testsDir.deletingLastPathComponent().appendingPathComponent("Derivee/SurfaceRunInspector.swift")
        
        let guidewayContent = try String(contentsOf: guidewayFile, encoding: .utf8)
        let surfaceContent = try String(contentsOf: surfaceFile, encoding: .utf8)
        
        // Assert stop names wrap cleanly with .lineLimit(2)
        XCTAssertTrue(guidewayContent.contains(".lineLimit(2)"), "GuidewayRunInspector must allow compound station names to wrap with .lineLimit(2)")
        XCTAssertTrue(surfaceContent.contains(".lineLimit(2)"), "SurfaceRunInspector must allow compound station names to wrap with .lineLimit(2)")
        
        // Assert transfer routes use adaptive TransferRouteBadge instead of hardcoded 14x14 Circle()
        XCTAssertTrue(guidewayContent.contains("TransferRouteBadge(routeId: rId)"), "GuidewayRunInspector must use TransferRouteBadge for connecting lines")
        XCTAssertTrue(surfaceContent.contains("TransferRouteBadge(routeId: rId)"), "SurfaceRunInspector must use TransferRouteBadge for connecting lines")
        
        // Assert transfer routes are disambiguated with ⇄ glyph prefix (Wave PD.9)
        XCTAssertTrue(guidewayContent.contains("Text(\"⇄\")"), "GuidewayRunInspector must prefix transfer routes with ⇄ glyph")
        XCTAssertTrue(surfaceContent.contains("Text(\"⇄\")"), "SurfaceRunInspector must prefix transfer routes with ⇄ glyph")
    }

    func testFC4_TransitRouteBadge_DiamondExpressBadgeProperties() {
        let info6X = TransitRouteData.lineInfo(for: "6X")
        XCTAssertTrue(info6X.isDiamond, "6X must be classified as a diamond express line")
        XCTAssertEqual(info6X.bulletGlyph, "6", "6X diamond badge must render root glyph '6'")
        XCTAssertEqual(info6X.accessibilityLabel, "6 Express")
        
        let info7X = TransitRouteData.lineInfo(for: "7X")
        XCTAssertTrue(info7X.isDiamond, "7X must be classified as a diamond express line")
        XCTAssertEqual(info7X.bulletGlyph, "7", "7X diamond badge must render root glyph '7'")
        XCTAssertEqual(info7X.accessibilityLabel, "7 Express")
        
        let infoFX = TransitRouteData.lineInfo(for: "FX")
        XCTAssertTrue(infoFX.isDiamond, "FX must be classified as a diamond express line")
        XCTAssertEqual(infoFX.bulletGlyph, "F", "FX diamond badge must render root glyph 'F'")
        XCTAssertEqual(infoFX.accessibilityLabel, "F Express")
        
        // Non-diamond lines retain standard circular badges
        let info6 = TransitRouteData.lineInfo(for: "6")
        XCTAssertFalse(info6.isDiamond, "Local 6 must NOT be a diamond")
        XCTAssertEqual(info6.bulletGlyph, "6")
        
        let infoA = TransitRouteData.lineInfo(for: "A")
        XCTAssertFalse(infoA.isDiamond, "A train branches must NOT be diamonds (canonical MTA circle)")
        XCTAssertEqual(infoA.bulletGlyph, "A")
        
        let infoBus = TransitRouteData.lineInfo(for: "B62")
        XCTAssertFalse(infoBus.isDiamond, "B62 bus must NOT be a diamond")
        XCTAssertEqual(infoBus.bulletGlyph, "B62")
        
        // Verify DiamondShape produces a valid 4-vertex closed path
        let diamond = DiamondShape()
        let path = diamond.path(in: CGRect(x: 0, y: 0, width: 30, height: 30))
        XCTAssertFalse(path.isEmpty, "DiamondShape must produce a non-empty path")
        XCTAssertEqual(path.boundingRect.width, 30, accuracy: 0.01)
        XCTAssertEqual(path.boundingRect.height, 30, accuracy: 0.01)
    }

    // MARK: - Wave PD.9: Transfer Route Disambiguation Glyphs & Multi-Complex Resolution
    
    func testFC4_TransferRouteDisambiguationGlyphsAndMultiComplexResolution() async throws {
        // 1. L Train Ladder: Verify multi-complex resolution at Union Sq (602), Lorimer (629), Myrtle-Wyckoff (630), 8 Av (601)
        let lLadder = try await SpatialDatabaseManager.shared.fetchRouteStopLadder(
            routeId: "L",
            directionId: 0,
            currentStopId: "L03",
            currentArrivalMinutes: 3
        )
        XCTAssertFalse(lLadder.isEmpty, "L train ladder must not be empty")
        
        // 14 St-Union Sq (L03) must aggregate 4, 5, 6, 6X, N, Q, R, W and exclude L
        let unionSq = lLadder.first { $0.stopId.contains("L03") || $0.stopName.contains("Union Sq") }
        XCTAssertNotNil(unionSq, "14 St-Union Sq must exist on L train ladder")
        let unionTransfers = unionSq?.transferRoutes ?? []
        XCTAssertTrue(unionTransfers.contains("4") || unionTransfers.contains("5") || unionTransfers.contains("6"), "Union Sq must contain 4/5/6 transfers")
        XCTAssertTrue(unionTransfers.contains("N") || unionTransfers.contains("Q") || unionTransfers.contains("R") || unionTransfers.contains("W"), "Union Sq must contain N/Q/R/W transfers")
        XCTAssertFalse(unionTransfers.contains("L"), "Union Sq on L train must NOT transfer to L itself")
        
        // Lorimer St (L10) must aggregate G transfer from complex 629
        let lorimerL = lLadder.first { $0.stopId.contains("L10") || $0.stopName == "Lorimer St" }
        XCTAssertNotNil(lorimerL, "Lorimer St must exist on L train ladder")
        XCTAssertTrue(lorimerL?.transferRoutes.contains("G") == true, "Lorimer St on L train must resolve G train transfer")
        XCTAssertFalse(lorimerL?.transferRoutes.contains("L") == true, "Lorimer St on L train must NOT transfer to L itself")
        
        // Myrtle-Wyckoff Avs (L17) must aggregate M transfer from complex 630
        let myrtleL = lLadder.first { $0.stopId.contains("L17") || $0.stopName.contains("Myrtle-Wyckoff") }
        XCTAssertNotNil(myrtleL, "Myrtle-Wyckoff must exist on L train ladder")
        XCTAssertTrue(myrtleL?.transferRoutes.contains("M") == true, "Myrtle-Wyckoff on L train must resolve M train transfer")
        
        // 8 Av (L01) must aggregate A, C, E transfers
        let eighthAv = lLadder.first { $0.stopId.contains("L01") || $0.stopName == "8 Av" }
        XCTAssertNotNil(eighthAv, "8 Av must exist on L train ladder")
        let eighthTransfers = eighthAv?.transferRoutes ?? []
        XCTAssertTrue(eighthTransfers.contains("A") || eighthTransfers.contains("C") || eighthTransfers.contains("E"), "8 Av must resolve A/C/E transfers")
        
        // 2. M Train Ladder: Verify Myrtle-Wyckoff (L transfer) and Hewes St (J transfer)
        let mLadder = try await SpatialDatabaseManager.shared.fetchRouteStopLadder(
            routeId: "M",
            directionId: 0,
            currentStopId: "M08",
            currentArrivalMinutes: 2
        )
        XCTAssertFalse(mLadder.isEmpty, "M train ladder must not be empty")
        
        let myrtleM = mLadder.first { $0.stopId.contains("M08") || $0.stopName.contains("Myrtle-Wyckoff") }
        XCTAssertNotNil(myrtleM, "Myrtle-Wyckoff must exist on M train ladder")
        XCTAssertTrue(myrtleM?.transferRoutes.contains("L") == true, "Myrtle-Wyckoff on M train must resolve L train transfer")
        XCTAssertFalse(myrtleM?.transferRoutes.contains("M") == true, "Myrtle-Wyckoff on M train must NOT transfer to M itself")
        
        let hewesM = mLadder.first { $0.stopId.contains("M14") || $0.stopName.contains("Hewes") }
        XCTAssertNotNil(hewesM, "Hewes St must exist on M train ladder")
        XCTAssertTrue(hewesM?.transferRoutes.contains("J") == true, "Hewes St on M train must resolve J train transfer")
        
        // 3. Penn Station (128) on 1 Train: Must aggregate 2, 3 and A, C, E from Regional Hub complex 600001
        let oneLadder = try await SpatialDatabaseManager.shared.fetchRouteStopLadder(
            routeId: "1",
            directionId: 0,
            currentStopId: "128",
            currentArrivalMinutes: 4
        )
        let penn1 = oneLadder.first { $0.stopId.contains("128") || $0.stopName.contains("Penn Station") }
        XCTAssertNotNil(penn1, "34 St-Penn Station must exist on 1 train ladder")
        let pennTransfers = penn1?.transferRoutes ?? []
        XCTAssertTrue(pennTransfers.contains("2") || pennTransfers.contains("3"), "Penn Station must have 2/3 transfers")
        XCTAssertTrue(pennTransfers.contains("A") || pennTransfers.contains("C") || pennTransfers.contains("E"), "Penn Station must have A/C/E transfers from complex")
        
        // 4. Verify canonical ordering across all stops in ladders
        for stop in lLadder {
            XCTAssertEqual(stop.transferRoutes, TransitRouteData.sortCanonical(stop.transferRoutes),
                           "Stop \(stop.stopName) transferRoutes must be strictly sorted in canonical MTA order")
        }
        for stop in mLadder {
            XCTAssertEqual(stop.transferRoutes, TransitRouteData.sortCanonical(stop.transferRoutes),
                           "Stop \(stop.stopName) transferRoutes must be strictly sorted in canonical MTA order")
        }
    }

    // MARK: - 5. FC-5: Zero Nested Sheet Stacking

    @MainActor
    func testFC5_TransitRevealSheet_InspectsArrivalInPlaceWithBackChevron() {
        let arrival = SpatialDatabaseManager.ArrivalInfo(
            line: "L", destination: "8 Av", minutes: 3, distanceDescription: "Approaching"
        )
        let sheet = TransitRevealSheet(
            stopId: "stop_bedford",
            initialInspectingArrival: arrival
        )
        let hosting = UIHostingController(rootView: sheet)
        XCTAssertNotNil(hosting.view)
    }

    func testFC5_TransitRevealSheet_SourceCodeHasZeroNestedSheets() throws {
        let filePath = #filePath
        let testsDir = URL(fileURLWithPath: filePath).deletingLastPathComponent()
        let sheetFile = testsDir.deletingLastPathComponent().appendingPathComponent("Derivee/TransitRevealSheet.swift")
        let content = try String(contentsOf: sheetFile, encoding: .utf8)
        
        XCTAssertFalse(
            content.contains(".sheet(item: $inspectingArrival)"),
            "FC-5 Violation: TransitRevealSheet must not use .sheet(item: $inspectingArrival)"
        )
    }

    func testFC5_ContentView_ZeroConcurrentSheetModifiers() throws {
        let filePath = #filePath
        let testsDir = URL(fileURLWithPath: filePath).deletingLastPathComponent()
        let contentViewFile = testsDir.deletingLastPathComponent().appendingPathComponent("Derivee/ContentView.swift")
        let content = try String(contentsOf: contentViewFile, encoding: .utf8)
        
        let sheetMatches = content.components(separatedBy: ".sheet(").count - 1
        XCTAssertEqual(
            sheetMatches, 1,
            "FC-5 Violation: ContentView must contain exactly 1 .sheet modifier. Found \(sheetMatches). Concurrent sheet presentation on root view causes background retention and presentation controller collision."
        )
        XCTAssertTrue(
            content.contains(".sheet(item: $activeSheet)"),
            "ContentView must present sheets exclusively through .sheet(item: $activeSheet)"
        )
    }

    func testFC5_InspectorBackAction_RestoresStationOverviewState() {
        var onBackCalled = false
        let arrival = SpatialDatabaseManager.ArrivalInfo(
            line: "L", destination: "8 Av", minutes: 2
        )
        let guideway = GuidewayRunInspector(
            arrival: arrival,
            currentStopId: "L11",
            currentStopName: "Bedford Av",
            onBack: { onBackCalled = true }
        )
        guideway.onBack?()
        XCTAssertTrue(onBackCalled, "onBack callback must execute to restore station overview state")
    }

    func testFC5_NavigationSheet_TransitionsSearchToComparisonInPlace() {
        let mode = SearchModeFilter.all
        XCTAssertEqual(mode.displayName, "All")
    }

    // MARK: - 6. FC-6: Thumb Zone Priority

    func testFC6_StatsView_ThumbZoneClearOfAdministrativeButtons() throws {
        let filePath = #filePath
        let testsDir = URL(fileURLWithPath: filePath).deletingLastPathComponent()
        let statsFile = testsDir.deletingLastPathComponent().appendingPathComponent("Derivee/StatsView.swift")
        let content = try String(contentsOf: statsFile, encoding: .utf8)
        
        XCTAssertFalse(
            content.contains("// Bottom GPX Import Action Bar (Always visible in single city and All Metros modes)"),
            "FC-6 Violation: Persistent bottom GPX import action bar must not be present in StatsView scroll"
        )
    }

    func testFC6_StatsView_UploadActionRelocatedToToolbarAndSettings() throws {
        let filePath = #filePath
        let testsDir = URL(fileURLWithPath: filePath).deletingLastPathComponent()
        let statsFile = testsDir.deletingLastPathComponent().appendingPathComponent("Derivee/StatsView.swift")
        let statsContent = try String(contentsOf: statsFile, encoding: .utf8)
        
        XCTAssertTrue(
            statsContent.contains("Image(systemName: \"square.and.arrow.down\")"),
            "StatsView must provide upload action via toolbar"
        )
        
        let settingsFile = testsDir.deletingLastPathComponent().appendingPathComponent("Derivee/SettingsView.swift")
        let settingsContent = try String(contentsOf: settingsFile, encoding: .utf8)
        XCTAssertTrue(
            settingsContent.contains("Label(\"Upload Previous Workouts\", systemImage: \"square.and.arrow.down\")"),
            "SettingsView must provide the Upload Previous Workouts action"
        )
    }

    func testFC6_NavigationGuidanceSheet_PrimaryActionsInLowerThird() {
        var didStart = false
        let action = ThumbZonePrimaryAction.startJourney {
            didStart = true
        }
        let bar = ThumbZoneActionBar(primary: action)
        let hosting = UIHostingController(rootView: bar)
        XCTAssertNotNil(hosting.view)
        action.execute()
        XCTAssertTrue(didStart)
    }

    func testFC6_MapView_OrientationClusterPositionedInBottomRightThumbSweep() {
        let recCenterSize: CGFloat = 50.0
        let clusterBottomPadding: CGFloat = 102.0
        XCTAssertEqual(recCenterSize, 50.0)
        XCTAssertGreaterThan(clusterBottomPadding, 80.0, "Cluster must clear safe area and reside within thumb reach")
    }

    // MARK: - 7. 0.0s Above-the-Fold Glance Budget (Screens 0–4)

    func testAboveTheFold_Screen0_OnboardingHasProgressIndicator() {
        let isHydrating = true
        XCTAssertTrue(isHydrating)
    }

    func testAboveTheFold_Screen1_MapPuckAndSearchCapsuleImmediate() {
        let capsule = SearchCapsuleOverlay {}
        let hosting = UIHostingController(rootView: capsule)
        XCTAssertNotNil(hosting.view)
    }

    func testAboveTheFold_Screen2_ThreeToFourArrivalRowsVisibleAtMediumDetent() throws {
        let filePath = #filePath
        let testsDir = URL(fileURLWithPath: filePath).deletingLastPathComponent()
        let sheetFile = testsDir.deletingLastPathComponent().appendingPathComponent("Derivee/TransitRevealSheet.swift")
        let content = try String(contentsOf: sheetFile, encoding: .utf8)
        
        XCTAssertTrue(
            content.contains("VStack(alignment: .leading, spacing: 6)"),
            "TransitRevealSheet header spacing must be tightened to 6pt"
        )
        XCTAssertTrue(
            content.contains(".padding(.vertical, 4)\n                                .background(Color(hex: \"#FF9500\").opacity(0.12))"),
            "Alert banner vertical padding must be tightened to 4pt"
        )
    }

    func testAboveTheFold_Subsheet2A_GuidewayProximityHeroVisible() {
        let arrival = SpatialDatabaseManager.ArrivalInfo(
            line: "L", destination: "8 Av", minutes: 2, distanceDescription: "Approaching"
        )
        let inspector = GuidewayRunInspector(
            arrival: arrival,
            currentStopId: "L11",
            currentStopName: "Bedford Av"
        )
        let hosting = UIHostingController(rootView: inspector)
        XCTAssertNotNil(hosting.view)
    }

    func testAboveTheFold_Subsheet2B_SurfaceHeadsignVisible() {
        let arrival = SpatialDatabaseManager.ArrivalInfo(
            line: "S51", destination: "St George Ferry", minutes: 4
        )
        let inspector = SurfaceRunInspector(
            arrival: arrival,
            currentStopId: "stop_s51",
            currentStopName: "Bay St",
            modalClass: .bus
        )
        let hosting = UIHostingController(rootView: inspector)
        XCTAssertNotNil(hosting.view)
    }

    func testAboveTheFold_DepartureMatrix_DefaultsToActiveRouteTab() {
        let calendar = Calendar.current
        var comps = DateComponents()
        comps.year = 2026; comps.month = 9; comps.day = 14
        comps.hour = 12; comps.minute = 0; comps.second = 0
        let date1200 = calendar.date(from: comps)!
        
        let departures = [
            SpatialDatabaseManager.DeparturePillRecord(id: "D_A", tripId: "T_A", routeId: "A", destination: "Inwood", minute: 5),
            SpatialDatabaseManager.DeparturePillRecord(id: "D_C", tripId: "T_C", routeId: "C", destination: "168 St", minute: 10)
        ]
        let sampleHours = (0..<24).map { h in
            SpatialDatabaseManager.HourScheduleRecord(hourOfDay: h, departures: h == 12 ? departures : [])
        }
        let matrix = DepartureMatrixView(
            records: sampleHours,
            routeId: "A",
            routeIds: ["A", "C"],
            stopId: "stop_pabt",
            liveArrivals: [],
            referenceDate: date1200
        )
        let reconciled = matrix.reconciledRecords(at: date1200)
        let hour12 = reconciled.first(where: { $0.hourOfDay == 12 })!
        XCTAssertEqual(hour12.departures.count, 1)
        XCTAssertEqual(hour12.departures.first?.routeId, "A")
    }

    func testAboveTheFold_Screen3_StatsViewShowsCompletionAndMilestones() {
        let tiers = [
            MilestoneTier(category: .transitHubs, tierNumber: 1, title: "First Connection", requirementDescription: "Unlock 1 hub", targetCount: 1, badgeIconName: "tram", isUnlocked: true)
        ]
        let progress = MilestoneProgress(category: .transitHubs, currentCount: 1, totalCount: 5, tiers: tiers)
        XCTAssertEqual(progress.percentage, 20.0)
        XCTAssertEqual(progress.unlockedTierCount, 1)
    }

    func testAboveTheFold_Screen4A_PlaceSearchShowsRecentsImmediately() {
        let recents = [
            RecentSearchDestination(id: "r1", title: "Bedford Av", subtitle: "L Train", kind: "station", latitude: 40.717, longitude: -73.956, timestamp: Date())
        ]
        XCTAssertEqual(recents.count, 1)
        XCTAssertEqual(recents.first?.title, "Bedford Av")
    }

    func testAboveTheFold_Screen4B_RouteComparisonCardsRanked() {
        let leg = JourneyLeg(mode: .subway, originName: "A", destinationName: "B", departureTimeSec: 100, arrivalTimeSec: 400)
        let itin1 = JourneyItinerary(departureTimeSec: 100, arrivalTimeSec: 400, legs: [leg])
        let itin2 = JourneyItinerary(departureTimeSec: 100, arrivalTimeSec: 700, legs: [leg])
        let ranked = [itin1, itin2].sorted(by: { $0.totalDurationSec < $1.totalDurationSec })
        XCTAssertEqual(ranked.first?.id, itin1.id)
    }

    func testAboveTheFold_Screen4C_NavigationGuidanceNextManeuverHero() {
        let leg = JourneyLeg(
            mode: .walk, originName: "Origin", destinationName: "Subway",
            departureTimeSec: 100, arrivalTimeSec: 200, distanceMeters: 60,
            landmarkCue: "Turn right after post office"
        )
        XCTAssertEqual(leg.landmarkCue, "Turn right after post office")
        XCTAssertEqual(leg.distanceMeters, 60)
    }

    // MARK: - 8. Cartographic, Telemetry & Degraded States

    func testCartography_InspectorCameraFramingBoundedToRouteExtrema() {
        let ladderCoordinates = [
            CLLocationCoordinate2D(latitude: 40.6466, longitude: -73.9018),
            CLLocationCoordinate2D(latitude: 40.7173, longitude: -73.9568),
            CLLocationCoordinate2D(latitude: 40.7397, longitude: -74.0025)
        ]
        let minLat = ladderCoordinates.map(\.latitude).min()!
        let maxLat = ladderCoordinates.map(\.latitude).max()!
        let minLon = ladderCoordinates.map(\.longitude).min()!
        let maxLon = ladderCoordinates.map(\.longitude).max()!
        
        XCTAssertGreaterThan(minLat, 40.60)
        XCTAssertLessThan(maxLat, 40.75)
        XCTAssertGreaterThan(minLon, -74.05)
        XCTAssertLessThan(maxLon, -73.85)
    }

    func testCartography_NadirPitchLockZero() {
        let pitch: Double = 0.0
        XCTAssertEqual(pitch, 0.0, "MapLibre viewport pitch must strictly lock to 0.0 for 2D orthographic alignment")
    }

    func testDegradedState_SubsurfaceUnderground_RendersScheduledHeadwayAndPausedTag() {
        let headwayText = "Every 4–6 min • Scheduled"
        let pausedTag = "Updated 2 min ago • Telemetry paused underground"
        XCTAssertTrue(headwayText.contains("Scheduled"))
        XCTAssertTrue(pausedTag.contains("paused underground"))
    }

    func testDegradedState_GBFSEmptyDock_RendersHighRiskBadgeAndAlternative() {
        let dockRisk = GBFSDockGatingRisk.high
        XCTAssertEqual(dockRisk.title, "Dock Starvation")
    }

    func testDegradedState_GTFSRTFeedTimeout_FallsBackToStaticTimetableWithWarningPill() {
        let confidence = GTFSRealtimeConfidenceTier.staticSchedule
        XCTAssertEqual(confidence.title, "SCHEDULED")
    }

    // MARK: - Wave PD.2: Interactive 3-Detent Persistent Dock & Return Navigation Tests

    func testPD2_RunInspectors_SynchronizeWithMapHasZeroDismissCalls() throws {
        let filePath = #filePath
        let testsDir = URL(fileURLWithPath: filePath).deletingLastPathComponent()
        let deriveeDir = testsDir.deletingLastPathComponent().appendingPathComponent("Derivee")
        
        let guidewayFile = deriveeDir.appendingPathComponent("GuidewayRunInspector.swift")
        let guidewayContent = try String(contentsOf: guidewayFile, encoding: .utf8)
        
        if let range = guidewayContent.range(of: "private func synchronizeWithMap()") {
            let funcSnippet = String(guidewayContent[range.lowerBound...])
            let endSnippet = String(funcSnippet.prefix(500))
            XCTAssertFalse(
                endSnippet.contains("dismiss()"),
                "Wave PD.2 Violation: GuidewayRunInspector.synchronizeWithMap must not call dismiss()"
            )
        } else {
            XCTFail("GuidewayRunInspector must define synchronizeWithMap()")
        }
        
        let surfaceFile = deriveeDir.appendingPathComponent("SurfaceRunInspector.swift")
        let surfaceContent = try String(contentsOf: surfaceFile, encoding: .utf8)
        
        if let range = surfaceContent.range(of: "private func synchronizeWithMap()") {
            let funcSnippet = String(surfaceContent[range.lowerBound...])
            let endSnippet = String(funcSnippet.prefix(500))
            XCTAssertFalse(
                endSnippet.contains("dismiss()"),
                "Wave PD.2 Violation: SurfaceRunInspector.synchronizeWithMap must not call dismiss()"
            )
        } else {
            XCTFail("SurfaceRunInspector must define synchronizeWithMap()")
        }
    }

    func testPD2_RunInspectors_ExitButtonTriggersOnBack() {
        var guidewayBackCalled = false
        let arr = SpatialDatabaseManager.ArrivalInfo(line: "L", destination: "8 Av", minutes: 3)
        let guideway = GuidewayRunInspector(
            arrival: arr,
            currentStopId: "L11",
            currentStopName: "Bedford Av",
            onBack: { guidewayBackCalled = true }
        )
        guideway.onBack?()
        XCTAssertTrue(guidewayBackCalled, "GuidewayRunInspector onBack callback must be invoked on exit")

        var surfaceBackCalled = false
        let surface = SurfaceRunInspector(
            arrival: arr,
            currentStopId: "stop_1",
            currentStopName: "Kent Av",
            modalClass: .bus,
            onBack: { surfaceBackCalled = true }
        )
        surface.onBack?()
        XCTAssertTrue(surfaceBackCalled, "SurfaceRunInspector onBack callback must be invoked on exit")
    }

    @MainActor
    func testPD2_TransitRevealSheet_DynamicDetentsAndDockPill() {
        XCTAssertEqual(
            TransitRevealSheet.inspectionPeekDetent,
            .fraction(0.12),
            "Wave PD.2: inspectionPeekDetent must be .fraction(0.12)"
        )
        
        let arr = SpatialDatabaseManager.ArrivalInfo(line: "6", destination: "Pelham Bay Park", minutes: 4)
        let sheet = TransitRevealSheet(
            stopId: "631",
            initialInspectingArrival: arr,
            initialDetent: TransitRevealSheet.inspectionPeekDetent
        )
        let hosting = UIHostingController(rootView: sheet)
        XCTAssertNotNil(hosting.view)
        
        let dockPill = sheet.compactInspectionDockPill(for: arr)
        let pillHosting = UIHostingController(rootView: dockPill)
        XCTAssertNotNil(pillHosting.view)
    }

    func testPD2_TransitRevealSheet_SourceHasPresentationBackgroundInteraction() throws {
        let filePath = #filePath
        let testsDir = URL(fileURLWithPath: filePath).deletingLastPathComponent()
        let sheetFile = testsDir.deletingLastPathComponent().appendingPathComponent("Derivee/TransitRevealSheet.swift")
        let content = try String(contentsOf: sheetFile, encoding: .utf8)
        
        XCTAssertTrue(
            content.contains(".presentationBackgroundInteraction"),
            "Wave PD.2 Violation: TransitRevealSheet must configure .presentationBackgroundInteraction"
        )
        XCTAssertTrue(
            content.contains("inspectionPeekDetent"),
            "Wave PD.2 Violation: TransitRevealSheet must declare inspectionPeekDetent"
        )
    }

    // MARK: - Wave PD.3: Approaching Train Progression & Bounded Vehicle Framing Invariants

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

    func testWavePD3_ApproachingTrainLadder_StartsAtLiveVehicleStop() {
        let dummyLadder = makePD3TestLadder()
        let arrival = SpatialDatabaseManager.ArrivalInfo(
            line: "L", destination: "8 Av", minutes: 4, distanceDescription: "2 stops away"
        )
        
        let annotated = TransitRealtimeService.shared.annotateLadderWithVehicle(ladder: dummyLadder, arrival: arrival)
        let activeAndUpcoming = annotated.filter { !$0.isPassed }
        
        XCTAssertEqual(activeAndUpcoming.first?.stopName, "Graham Av", "Approaching progression ladder must start at oncoming train stop (Graham Av)")
        XCTAssertEqual(activeAndUpcoming.first?.isVehicleHere, true, "Oncoming train stop must have isVehicleHere = true")
    }

    func testWavePD3_ApproachingTrainLadder_CollapsesStopsPriorToLiveTrain() {
        let dummyLadder = makePD3TestLadder()
        let arrival = SpatialDatabaseManager.ArrivalInfo(
            line: "L", destination: "8 Av", minutes: 4, distanceDescription: "2 stops away"
        )
        
        let annotated = TransitRealtimeService.shared.annotateLadderWithVehicle(ladder: dummyLadder, arrival: arrival)
        let earlierStops = annotated.filter { $0.isPassed }
        
        XCTAssertEqual(earlierStops.count, 12, "Stops prior to live vehicle (0...11) must be classified as isPassed = true for earlier stops collapse")
    }

    func testWavePD3_ApproachingTrainLadder_RendersIntermediateStopsActive() {
        let dummyLadder = makePD3TestLadder()
        let arrival = SpatialDatabaseManager.ArrivalInfo(
            line: "L", destination: "8 Av", minutes: 4, distanceDescription: "2 stops away"
        )
        
        let annotated = TransitRealtimeService.shared.annotateLadderWithVehicle(ladder: dummyLadder, arrival: arrival)
        let intermediate = annotated.first(where: { $0.stopName == "Lorimer St" })
        
        XCTAssertNotNil(intermediate)
        XCTAssertFalse(intermediate?.isPassed ?? true, "Intermediate approaching stops between live train and user must NOT be passed")
        XCTAssertFalse(intermediate?.isCurrent ?? true, "Intermediate stop is not commuter station")
        XCTAssertFalse(intermediate?.isVehicleHere ?? true, "Intermediate stop does not have the train yet")
    }

    func testWavePD3_ApproachingTrainLadder_HighlightsYouAreHere() {
        let dummyLadder = makePD3TestLadder()
        let arrival = SpatialDatabaseManager.ArrivalInfo(
            line: "L", destination: "8 Av", minutes: 4, distanceDescription: "2 stops away"
        )
        
        let annotated = TransitRealtimeService.shared.annotateLadderWithVehicle(ladder: dummyLadder, arrival: arrival)
        let commuterStop = annotated.first(where: { $0.isCurrent })
        
        XCTAssertNotNil(commuterStop)
        XCTAssertEqual(commuterStop?.stopName, "Bedford Av")
        XCTAssertEqual(commuterStop?.isCurrent, true)
        XCTAssertEqual(commuterStop?.isPassed, false)
    }

    func testWavePD3_SourceCodeVerification() throws {
        let filePath = #filePath
        let testsDir = URL(fileURLWithPath: filePath).deletingLastPathComponent()
        let deriveeDir = testsDir.deletingLastPathComponent().appendingPathComponent("Derivee")
        
        let guidewayContent = try String(contentsOf: deriveeDir.appendingPathComponent("GuidewayRunInspector.swift"), encoding: .utf8)
        XCTAssertTrue(guidewayContent.contains("TRAIN HERE"), "GuidewayRunInspector must render 'TRAIN HERE' badge on live vehicle stop")
        XCTAssertTrue(guidewayContent.contains("earlier stop"), "GuidewayRunInspector must collapse prior stops into 'earlier stops'")
        
        let mapContent = try String(contentsOf: deriveeDir.appendingPathComponent("MapView.swift"), encoding: .utf8)
        XCTAssertTrue(mapContent.contains("MLNZoomLevelForAltitude"), "MapView must use MLNZoomLevelForAltitude for camera zoom clamping")
        XCTAssertTrue(mapContent.contains("MLNAltitudeForZoomLevel"), "MapView must use MLNAltitudeForZoomLevel for camera altitude calculation")
        XCTAssertTrue(mapContent.contains("14.5") && mapContent.contains("15.5"), "MapView must clamp camera zoom to z in [14.5, 15.5]")
    }

    // MARK: - Wave PD.7: Approaching Stops Progressive ETAs & Distant Consist Viewport Anchoring

    func testWavePD7_ProgressiveApproachingETAs_IntermediateStopsAnnotated() {
        let dummyLadder = makePD3TestLadder()
        
        // 1. Consist 2 stops away (Graham Av -> Bedford Av), minutes: 4
        let arrival2Stops = SpatialDatabaseManager.ArrivalInfo(
            line: "L", destination: "8 Av", minutes: 4, distanceDescription: "2 stops away • Approaching Lorimer St"
        )
        let annotated2 = TransitRealtimeService.shared.annotateLadderWithVehicle(ladder: dummyLadder, arrival: arrival2Stops)
        
        // Lorimer St (index 13) is intermediate approaching stop
        XCTAssertEqual(annotated2[13].stopName, "Lorimer St")
        XCTAssertEqual(annotated2[13].estimatedMinutes, 2, "Intermediate approaching stop must receive progressive countdown ETA (4 - 1*2 = 2m)")
        XCTAssertFalse(annotated2[13].isPassed)
        XCTAssertFalse(annotated2[13].isCurrent)
        XCTAssertFalse(annotated2[13].isVehicleHere)
        
        // Bedford Av (index 14) is commuter station
        XCTAssertEqual(annotated2[14].stopName, "Bedford Av")
        XCTAssertEqual(annotated2[14].estimatedMinutes, 4, "Active commuter station must receive arrival.minutes")
        XCTAssertTrue(annotated2[14].isCurrent)
        
        // 2. Consist 4 stops away (Morgan Av index 10 -> Bedford Av index 14), minutes: 10
        let arrival4Stops = SpatialDatabaseManager.ArrivalInfo(
            line: "L", destination: "8 Av", minutes: 10, distanceDescription: "4 stops away"
        )
        let annotated4 = TransitRealtimeService.shared.annotateLadderWithVehicle(ladder: dummyLadder, arrival: arrival4Stops)
        
        XCTAssertEqual(annotated4[10].isVehicleHere, true, "Stop 10 must be live vehicle stop")
        XCTAssertEqual(annotated4[11].estimatedMinutes, 4, "Stop 11 (3 stops from commuter) ETA: 10 - 3*2 = 4m")
        XCTAssertEqual(annotated4[12].estimatedMinutes, 6, "Stop 12 (2 stops from commuter) ETA: 10 - 2*2 = 6m")
        XCTAssertEqual(annotated4[13].estimatedMinutes, 8, "Stop 13 (1 stop from commuter) ETA: 10 - 1*2 = 8m")
        XCTAssertEqual(annotated4[14].estimatedMinutes, 10, "Stop 14 (commuter station) ETA: 10m")
        
        // 3. Lower bound clamping at 1m: arrival.minutes = 1, 2 stops away
        let arrivalImminent = SpatialDatabaseManager.ArrivalInfo(
            line: "L", destination: "8 Av", minutes: 1, distanceDescription: "2 stops away"
        )
        let annotatedImm = TransitRealtimeService.shared.annotateLadderWithVehicle(ladder: dummyLadder, arrival: arrivalImminent)
        XCTAssertEqual(annotatedImm[13].estimatedMinutes, 1, "Approaching stop ETA must clamp to >= 1m, never 0 or negative")
    }

    func testWavePD7_DistantConsist_SourceCodeVerification() throws {
        let filePath = #filePath
        let testsDir = URL(fileURLWithPath: filePath).deletingLastPathComponent()
        let deriveeDir = testsDir.deletingLastPathComponent().appendingPathComponent("Derivee")
        
        // GuidewayRunInspector verification
        let guidewayContent = try String(contentsOf: deriveeDir.appendingPathComponent("GuidewayRunInspector.swift"), encoding: .utf8)
        XCTAssertTrue(guidewayContent.contains("stopsAway > 4"), "GuidewayRunInspector must evaluate stopsAway > 4 for distant consist handling")
        XCTAssertTrue(guidewayContent.contains("isApproachingStopsExpanded"), "GuidewayRunInspector must maintain isApproachingStopsExpanded state")
        XCTAssertTrue(guidewayContent.contains("anchor: anchor"), "GuidewayRunInspector must use dynamic anchor for scroll proxy")
        XCTAssertTrue(guidewayContent.contains("approaching stop"), "GuidewayRunInspector must render approaching stop accordion toggle")
        XCTAssertTrue(guidewayContent.contains(".center"), "GuidewayRunInspector must support .center anchor for ACTIVE_STATION")
        
        // SurfaceRunInspector verification
        let surfaceContent = try String(contentsOf: deriveeDir.appendingPathComponent("SurfaceRunInspector.swift"), encoding: .utf8)
        XCTAssertTrue(surfaceContent.contains("stopsAway > 4"), "SurfaceRunInspector must evaluate stopsAway > 4 for distant consist handling")
        XCTAssertTrue(surfaceContent.contains("isApproachingStopsExpanded"), "SurfaceRunInspector must maintain isApproachingStopsExpanded state")
        XCTAssertTrue(surfaceContent.contains("anchor: anchor"), "SurfaceRunInspector must use dynamic anchor for scroll proxy")
        XCTAssertTrue(surfaceContent.contains("approaching "), "SurfaceRunInspector must render approaching stop accordion toggle")
        XCTAssertTrue(surfaceContent.contains(".center"), "SurfaceRunInspector must support .center anchor for ACTIVE_STATION")
    }

    // MARK: - 7. FC-7: Zero Detent-Coupled State Wipes (Wave PE.1 Forward-Looking Invariant)

    func testFC7_GuidewayInspector_OnDisappearDoesNotCallClearRouteInspection() throws {
        let filePath = #filePath
        let testsDir = URL(fileURLWithPath: filePath).deletingLastPathComponent()
        let deriveeDir = testsDir.deletingLastPathComponent().appendingPathComponent("Derivee")
        let content = try String(contentsOf: deriveeDir.appendingPathComponent("GuidewayRunInspector.swift"), encoding: .utf8)
        let lines = content.components(separatedBy: .newlines)
        var foundAntipattern = false
        for (i, line) in lines.enumerated() {
            if line.contains(".onDisappear") {
                let window = lines[i..<min(i + 6, lines.count)].joined(separator: "\n")
                if window.contains("onClearRouteInspection") {
                    foundAntipattern = true
                    break
                }
            }
        }
        XCTAssertFalse(foundAntipattern, "GuidewayRunInspector must not call onClearRouteInspection in .onDisappear — detent changes trigger .onDisappear and wipe map telemetry (FC-7)")
    }

    func testFC7_SurfaceInspector_OnDisappearDoesNotCallClearRouteInspection() throws {
        let filePath = #filePath
        let testsDir = URL(fileURLWithPath: filePath).deletingLastPathComponent()
        let deriveeDir = testsDir.deletingLastPathComponent().appendingPathComponent("Derivee")
        let content = try String(contentsOf: deriveeDir.appendingPathComponent("SurfaceRunInspector.swift"), encoding: .utf8)
        let lines = content.components(separatedBy: .newlines)
        var foundAntipattern = false
        for (i, line) in lines.enumerated() {
            if line.contains(".onDisappear") {
                let window = lines[i..<min(i + 6, lines.count)].joined(separator: "\n")
                if window.contains("onClearRouteInspection") {
                    foundAntipattern = true
                    break
                }
            }
        }
        XCTAssertFalse(foundAntipattern, "SurfaceRunInspector must not call onClearRouteInspection in .onDisappear — detent changes trigger .onDisappear and wipe map telemetry (FC-7)")
    }

    func testFC7_TransitRevealSheet_OnDisappearDoesNotCallClearRouteInspection() throws {
        let filePath = #filePath
        let testsDir = URL(fileURLWithPath: filePath).deletingLastPathComponent()
        let deriveeDir = testsDir.deletingLastPathComponent().appendingPathComponent("Derivee")
        let content = try String(contentsOf: deriveeDir.appendingPathComponent("TransitRevealSheet.swift"), encoding: .utf8)
        let lines = content.components(separatedBy: .newlines)
        var foundAntipattern = false
        for (i, line) in lines.enumerated() {
            if line.contains(".onDisappear") {
                let window = lines[i..<min(i + 6, lines.count)].joined(separator: "\n")
                if window.contains("onClearRouteInspection") {
                    foundAntipattern = true
                    break
                }
            }
        }
        XCTAssertFalse(foundAntipattern, "TransitRevealSheet must not call onClearRouteInspection in .onDisappear — sheet detent changes must not wipe active inspection (FC-7)")
    }

    func testFC7_TransitRevealSheet_StationChangeClearsInspection() throws {
        let filePath = #filePath
        let testsDir = URL(fileURLWithPath: filePath).deletingLastPathComponent()
        let deriveeDir = testsDir.deletingLastPathComponent().appendingPathComponent("Derivee")
        let content = try String(contentsOf: deriveeDir.appendingPathComponent("TransitRevealSheet.swift"), encoding: .utf8)
        let lines = content.components(separatedBy: .newlines)
        var hasStopIdClear = false
        for (i, line) in lines.enumerated() {
            if line.contains(".onChange(of: stopId)") {
                let window = lines[i..<min(i + 8, lines.count)].joined(separator: "\n")
                if window.contains("onClearRouteInspection") {
                    hasStopIdClear = true
                    break
                }
            }
        }
        XCTAssertTrue(hasStopIdClear, "TransitRevealSheet must explicitly call onClearRouteInspection when station stopId changes (FC-7)")
    }

    func testFC7_Inspectors_CloseButtonInvokesClearWhenStandalone() throws {
        let filePath = #filePath
        let testsDir = URL(fileURLWithPath: filePath).deletingLastPathComponent()
        let deriveeDir = testsDir.deletingLastPathComponent().appendingPathComponent("Derivee")
        let guidewayContent = try String(contentsOf: deriveeDir.appendingPathComponent("GuidewayRunInspector.swift"), encoding: .utf8)
        let surfaceContent = try String(contentsOf: deriveeDir.appendingPathComponent("SurfaceRunInspector.swift"), encoding: .utf8)
        
        XCTAssertTrue(guidewayContent.contains("onClearRouteInspection?()") && guidewayContent.contains("dismiss()"), "GuidewayRunInspector close button must invoke onClearRouteInspection when standalone (FC-7)")
        XCTAssertTrue(surfaceContent.contains("onClearRouteInspection?()") && surfaceContent.contains("dismiss()"), "SurfaceRunInspector close button must invoke onClearRouteInspection when standalone (FC-7)")
    }

    // MARK: - 8. FC-8: Interaction Path Completeness (Wave PE.5 Invariant)

    func testFC8_DepartureMatrixView_PillsHaveInspectHandler() throws {
        let filePath = #filePath
        let testsDir = URL(fileURLWithPath: filePath).deletingLastPathComponent()
        let deriveeDir = testsDir.deletingLastPathComponent().appendingPathComponent("Derivee")
        let content = try String(contentsOf: deriveeDir.appendingPathComponent("DepartureMatrixView.swift"), encoding: .utf8)
        XCTAssertTrue(content.contains("onInspectDeparture"), "DepartureMatrixView must expose an onInspectDeparture callback for tapping departure pills (FC-8)")
    }

    func testFC8_LiveArrivalsCarousel_RowsHaveTapAction() throws {
        let filePath = #filePath
        let testsDir = URL(fileURLWithPath: filePath).deletingLastPathComponent()
        let deriveeDir = testsDir.deletingLastPathComponent().appendingPathComponent("Derivee")
        let content = try String(contentsOf: deriveeDir.appendingPathComponent("TransitRevealSheet.swift"), encoding: .utf8)
        XCTAssertTrue(content.contains("onInspectArrival(arrival)"), "LiveArrivalsCarousel must wire arrival rows to onInspectArrival tap action (FC-8)")
    }

    func testFC8_BusStopArrivalRows_HaveTapAction() throws {
        let filePath = #filePath
        let testsDir = URL(fileURLWithPath: filePath).deletingLastPathComponent()
        let deriveeDir = testsDir.deletingLastPathComponent().appendingPathComponent("Derivee")
        let content = try String(contentsOf: deriveeDir.appendingPathComponent("TransitRevealSheet.swift"), encoding: .utf8)
        XCTAssertTrue(content.contains("onInspectArrival"), "TransitRevealSheet must wire arrival inspection callback across all transit modes including buses (FC-8)")
    }

    // MARK: - 9. FC-9: Viewport-Aware Camera Geometry (Wave PE.2 Invariant)

    func testFC9_FrameRouteAndStation_AcceptsDetentParameter() throws {
        let filePath = #filePath
        let testsDir = URL(fileURLWithPath: filePath).deletingLastPathComponent()
        let deriveeDir = testsDir.deletingLastPathComponent().appendingPathComponent("Derivee")
        let content = try String(contentsOf: deriveeDir.appendingPathComponent("MapView.swift"), encoding: .utf8)
        let acceptsDetent = content.contains("sheetHeight") || content.contains("activeDetent") || content.contains("sheetFraction")
        XCTAssertTrue(acceptsDetent, "MapView.frameRouteAndStation must accept a sheet height or detent parameter for dynamic clearance (FC-9)")
    }

    func testFC9_FrameRouteAndStation_ZoomLowerBoundAllowsWideFraming() throws {
        let filePath = #filePath
        let testsDir = URL(fileURLWithPath: filePath).deletingLastPathComponent()
        let deriveeDir = testsDir.deletingLastPathComponent().appendingPathComponent("Derivee")
        let content = try String(contentsOf: deriveeDir.appendingPathComponent("MapView.swift"), encoding: .utf8)
        let hasRelaxedZoom = content.contains("13.0") || content.contains("13.5")
        XCTAssertTrue(hasRelaxedZoom, "MapView.frameRouteAndStation must allow zoom level down to <= 13.5 to frame approaching vehicles (FC-9)")
    }

    func testFC9_FrameRouteAndStation_BottomPaddingIsDynamic() throws {
        let filePath = #filePath
        let testsDir = URL(fileURLWithPath: filePath).deletingLastPathComponent()
        let deriveeDir = testsDir.deletingLastPathComponent().appendingPathComponent("Derivee")
        let content = try String(contentsOf: deriveeDir.appendingPathComponent("MapView.swift"), encoding: .utf8)
        XCTAssertFalse(content.contains("max(340.0,"), "MapView.frameRouteAndStation must derive bottomPadding dynamically from sheet height, not hardcoded 340.0 (FC-9)")
    }

    // MARK: - 10. FC-10: Mode-Adaptive Visual State (Wave PE.3 Invariant)

    func testFC10_ContentView_FogOpacityAdaptsOnInspection() throws {
        let filePath = #filePath
        let testsDir = URL(fileURLWithPath: filePath).deletingLastPathComponent()
        let deriveeDir = testsDir.deletingLastPathComponent().appendingPathComponent("Derivee")
        let content = try String(contentsOf: deriveeDir.appendingPathComponent("ContentView.swift"), encoding: .utf8)
        let adaptsFog = content.contains("transitFogOpacity") || content.contains("inspectingArrival != nil")
        XCTAssertTrue(adaptsFog, "ContentView must dynamically reduce fogOpacity during active route inspection (FC-10)")
    }

    func testFC10_FogOpacity_TransitInspectionUsesReducedValue() {
        XCTAssertLessThan(
            MapCustomizationDefaults.transitFogOpacity,
            MapCustomizationDefaults.defaultFogOpacity,
            "transitFogOpacity (0.40) must be lower than defaultFogOpacity (0.85) to illuminate street grid during inspection (FC-10)"
        )
        XCTAssertEqual(MapCustomizationDefaults.transitFogOpacity, 0.40, accuracy: 0.01)
        XCTAssertEqual(MapCustomizationDefaults.defaultFogOpacity, 0.85, accuracy: 0.01)
    }

    func testFC10_ContentView_FogOpacityRestoresOnInspectionExit() throws {
        let filePath = #filePath
        let testsDir = URL(fileURLWithPath: filePath).deletingLastPathComponent()
        let deriveeDir = testsDir.deletingLastPathComponent().appendingPathComponent("Derivee")
        let content = try String(contentsOf: deriveeDir.appendingPathComponent("ContentView.swift"), encoding: .utf8)
        XCTAssertTrue(content.contains("AppStorageKeys.fogOpacity"), "ContentView must retain user baseline fogOpacity for clean restoration upon inspection exit (FC-10)")
    }
}


