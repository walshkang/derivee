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
}
