import XCTest
import SwiftUI
import CoreLocation
@testable import Derivee

@MainActor
final class SingleSheetArchitectureTests: XCTestCase {

    // MARK: - 1. ActiveSheet State Machine & Identification

    func testActiveSheetIdentificationAndEquality() {
        let cityEntry = CityManifestEntry(
            slug: "nyc",
            displayName: "New York City",
            region: "New York, USA",
            compressedSizeBytes: 50,
            uncompressedSizeBytes: 100,
            isBundled: true,
            version: "1.0"
        )
        
        let citySheet = ActiveSheet.cityPrompt(cityEntry)
        let transitSheet = ActiveSheet.transit(stopId: "stop_columbus")
        let searchSheet = ActiveSheet.search
        let statsSheet = ActiveSheet.stats
        let driftSheet = ActiveSheet.driftControls
        
        XCTAssertEqual(citySheet.id, "cityPrompt_nyc")
        XCTAssertEqual(transitSheet.id, "transit_stop_columbus")
        XCTAssertEqual(searchSheet.id, "search")
        XCTAssertEqual(statsSheet.id, "stats")
        XCTAssertEqual(driftSheet.id, "driftControls")
        
        // Equality tests
        XCTAssertEqual(searchSheet, ActiveSheet.search)
        XCTAssertEqual(statsSheet, ActiveSheet.stats)
        XCTAssertEqual(driftSheet, ActiveSheet.driftControls)
        XCTAssertEqual(transitSheet, ActiveSheet.transit(stopId: "stop_columbus"))
        XCTAssertNotEqual(transitSheet, ActiveSheet.transit(stopId: "stop_bedford"))
        XCTAssertNotEqual(transitSheet, searchSheet)
        XCTAssertNotEqual(statsSheet, driftSheet)
    }

    // MARK: - 2. External Detent Binding Synchronization (Wave PE.9)

    func testTransitRevealSheetExternalDetentBindingSync() {
        var externalDetent: PresentationDetent = .medium
        let binding = Binding<PresentationDetent>(
            get: { externalDetent },
            set: { externalDetent = $0 }
        )
        
        let sheet = TransitRevealSheet(
            stopId: "stop_columbus",
            selectedDetent: binding
        )
        
        // Initial value matches external binding
        XCTAssertEqual(sheet.selectedDetent, .medium)
        
        // Mutating via sheet updates external binding synchronously
        sheet.selectedDetent = TransitRevealSheet.inspectionPeekDetent
        XCTAssertEqual(externalDetent, TransitRevealSheet.inspectionPeekDetent)
        XCTAssertEqual(sheet.selectedDetent, TransitRevealSheet.inspectionPeekDetent)
        
        // Mutating external binding reflects in sheet synchronously
        externalDetent = .large
        XCTAssertEqual(sheet.selectedDetent, .large)
    }

    func testTransitRevealSheetInternalDetentFallbackWhenNoBindingProvided() {
        let mediumSheet = TransitRevealSheet(
            stopId: "stop_columbus",
            initialDetent: .medium
        )
        XCTAssertEqual(mediumSheet.selectedDetent, .medium)
        
        let peekSheet = TransitRevealSheet(
            stopId: "stop_columbus",
            initialDetent: TransitRevealSheet.inspectionPeekDetent
        )
        XCTAssertEqual(peekSheet.selectedDetent, TransitRevealSheet.inspectionPeekDetent)
    }

    // MARK: - 3. Static Code Audit: Single .sheet Modifier Architecture (FC-5)

    func testContentViewSingleSheetArchitectureAudit() throws {
        let filePath = #filePath
        let testsDir = URL(fileURLWithPath: filePath).deletingLastPathComponent()
        let contentViewFile = testsDir.deletingLastPathComponent().appendingPathComponent("Derivee/ContentView.swift")
        let content = try String(contentsOf: contentViewFile, encoding: .utf8)
        
        // Count occurrences of ".sheet(" in ContentView.swift
        let sheetMatches = content.components(separatedBy: ".sheet(").count - 1
        XCTAssertEqual(
            sheetMatches, 1,
            "FC-5 Violation: ContentView must contain exactly 1 .sheet modifier. Found \(sheetMatches). Concurrent sheet presentation on root view causes background retention and presentation controller collision."
        )
        
        // Ensure it binds to the unified ActiveSheet state machine
        XCTAssertTrue(
            content.contains(".sheet(item: $activeSheet)"),
            "ContentView must present sheets exclusively through .sheet(item: $activeSheet)"
        )
        
        // Ensure deprecated fragmented sheet bindings are completely eliminated
        XCTAssertFalse(content.contains(".sheet(isPresented: $showStatsView)"))
        XCTAssertFalse(content.contains(".sheet(isPresented: $showDriftControls)"))
        XCTAssertFalse(content.contains(".sheet(isPresented: $showSearchSheet)"))
        XCTAssertFalse(content.contains(".sheet(isPresented: $showTransitSheet"))
    }

    // MARK: - 4. Mutual Exclusivity Transition Logic

    func testMutualExclusivityStateTransitions() {
        var activeSheet: ActiveSheet? = .transit(stopId: "stop_columbus")
        XCTAssertEqual(activeSheet, .transit(stopId: "stop_columbus"))
        
        // Commuter opens drift controls: cleanly replaces transit sheet
        activeSheet = .driftControls
        XCTAssertEqual(activeSheet, .driftControls)
        XCTAssertNotEqual(activeSheet, .transit(stopId: "stop_columbus"))
        
        // Commuter opens stats: cleanly replaces drift controls
        activeSheet = .stats
        XCTAssertEqual(activeSheet, .stats)
        XCTAssertNotEqual(activeSheet, .driftControls)
        
        // Dismissal returns to nil
        activeSheet = nil
        XCTAssertNil(activeSheet)
    }

    // MARK: - 5. Floating Lens Hit-Testing & Collision Safety (Pre-T.1 / FC-5)

    func testFC5_FloatingLensesHitTestingAndOpacityGatedByActiveSheet() throws {
        let filePath = #filePath
        let testsDir = URL(fileURLWithPath: filePath).deletingLastPathComponent()
        let contentViewFile = testsDir.deletingLastPathComponent().appendingPathComponent("Derivee/ContentView.swift")
        let content = try String(contentsOf: contentViewFile, encoding: .utf8)
        
        // Both NearbyBusesCapsule and RecenterFAB must disable hit-testing when a sheet is presented
        XCTAssertTrue(
            content.contains(".allowsHitTesting(activeSheet == nil)"),
            "FC-5 Violation: ContentView must apply .allowsHitTesting(activeSheet == nil) to prevent invisible tap-interception traps over bottom sheets"
        )
        
        // Both NearbyBusesCapsule and RecenterFAB must attenuate opacity when a sheet is presented
        XCTAssertTrue(
            content.contains(".opacity(activeSheet == nil ? 1.0 : 0.0)"),
            "FC-5 Violation: ContentView must apply .opacity(activeSheet == nil ? 1.0 : 0.0) to hide floating lenses while sheets are active"
        )
        
        // Must auto-collapse isNearbyBusesExpanded on activeSheet presentation and selectedTransitStop binding
        XCTAssertTrue(
            content.contains("isNearbyBusesExpanded = false"),
            "FC-5 Violation: ContentView must auto-collapse isNearbyBusesExpanded when sheets or transit stops are selected"
        )
    }

    // MARK: - 6. Pre-T.5 Persistent Inspection Dock Hardening & Non-Trapping Dismissal Tests (WPT5)

    @MainActor
    func testPreT5_InspectionPeekDetent_SnapBackClamping() {
        var externalDetent: PresentationDetent = .medium
        let externalBinding = Binding<PresentationDetent>(
            get: { externalDetent },
            set: { externalDetent = $0 }
        )
        let arr = SpatialDatabaseManager.ArrivalInfo(line: "L", destination: "Canarsie", minutes: 4)
        let sheet = TransitRevealSheet(
            stopId: "stop_bedford",
            initialInspectingArrival: arr,
            initialDetent: .medium,
            selectedDetent: externalBinding
        )
        
        // Simulating user dragging sheet down into peek detent
        sheet.selectedDetent = TransitRevealSheet.inspectionPeekDetent
        XCTAssertEqual(externalDetent, TransitRevealSheet.inspectionPeekDetent)
        XCTAssertEqual(sheet.selectedDetent, TransitRevealSheet.inspectionPeekDetent)
    }

    func testPreT5_CompactDockPill_DefensivePrefixStripping() {
        // Line-prefixed destination with uppercase line
        XCTAssertEqual(
            TransitRevealSheet.cleanInspectionDestination(destination: "L to Canarsie - Rockaway Pkwy", line: "L"),
            "Canarsie - Rockaway Pkwy"
        )
        
        // Line-prefixed destination with lowercase line
        XCTAssertEqual(
            TransitRevealSheet.cleanInspectionDestination(destination: "l to 8 Av", line: "L"),
            "8 Av"
        )
        
        // Bus line prefix
        XCTAssertEqual(
            TransitRevealSheet.cleanInspectionDestination(destination: "B32 to Williamsburg Bridge Plaza", line: "B32"),
            "Williamsburg Bridge Plaza"
        )
        
        // Generic "To " prefix
        XCTAssertEqual(
            TransitRevealSheet.cleanInspectionDestination(destination: "To Long Island City", line: "B32"),
            "Long Island City"
        )
        XCTAssertEqual(
            TransitRevealSheet.cleanInspectionDestination(destination: "to Jamaica Center", line: "E"),
            "Jamaica Center"
        )
        
        // Non-prefixed destination passes through unmodified
        XCTAssertEqual(
            TransitRevealSheet.cleanInspectionDestination(destination: "Pelham Bay Park", line: "6"),
            "Pelham Bay Park"
        )
        XCTAssertEqual(
            TransitRevealSheet.cleanInspectionDestination(destination: "World Trade Center", line: "E"),
            "World Trade Center"
        )
    }

    func testPreT5_SourceCodeAudit_NoInteractiveDismissDisabled_AndPeekChromeHidden() throws {
        let filePath = #filePath
        let testsDir = URL(fileURLWithPath: filePath).deletingLastPathComponent()
        let sheetFile = testsDir.deletingLastPathComponent().appendingPathComponent("Derivee/TransitRevealSheet.swift")
        let content = try String(contentsOf: sheetFile, encoding: .utf8)
        
        // 1. Must NOT contain .interactiveDismissDisabled to prevent trapping the commuter (FC-7)
        XCTAssertFalse(
            content.contains(".interactiveDismissDisabled"),
            "FC-7 Violation: TransitRevealSheet must not use .interactiveDismissDisabled which locks commuters in the sheet"
        )
        
        // 2. Must hide inspectorView from accessibility during peek detent
        XCTAssertTrue(
            content.contains(".accessibilityHidden(selectedDetent == Self.inspectionPeekDetent)"),
            "Pre-T.5 Violation: TransitRevealSheet must isolate accessibility in peek detent"
        )
        
        // 3. Must apply auto-scaling (.minimumScaleFactor(0.85)) to dock pill destination text
        XCTAssertTrue(
            content.contains(".minimumScaleFactor(0.85)"),
            "Pre-T.5 Violation: compactInspectionDockPill must apply .minimumScaleFactor(0.85) to prevent ellipsis truncation"
        )
    }
}
