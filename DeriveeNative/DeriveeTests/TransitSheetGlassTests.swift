import XCTest
import SwiftUI
import SnapshotTesting
@testable import Derivee

@MainActor
final class TransitSheetGlassTests: XCTestCase {

    // MARK: - 1. Unit Tests: TransitSheetGlassBackground Architecture

    func testTransitSheetGlassBackgroundInitialization() {
        let defaultBg = TransitSheetGlassBackground()
        XCTAssertEqual(defaultBg.cornerRadius, 28)
        
        let customBg = TransitSheetGlassBackground(cornerRadius: 32)
        XCTAssertEqual(customBg.cornerRadius, 32)
        
        // Ensure body evaluates without crashing
        _ = defaultBg.body
        _ = customBg.body
    }

    func testStandardNavigationSheetModifierWithGlassStack() {
        let binding = Binding<PresentationDetent>(
            get: { NavigationSheetDetent.half.presentationDetent },
            set: { _ in }
        )
        let modifier = StandardNavigationSheetModifier(
            selectedDetent: binding,
            interactiveUpThrough: NavigationSheetDetent.half.presentationDetent,
            cornerRadius: 28
        )
        XCTAssertEqual(modifier.cornerRadius, 28)
        XCTAssertEqual(modifier.interactiveUpThrough, NavigationSheetDetent.half.presentationDetent)
        
        let staticModifier = StandardNavigationSheetStaticModifier(
            interactiveUpThrough: NavigationSheetDetent.half.presentationDetent,
            cornerRadius: 24
        )
        XCTAssertEqual(staticModifier.cornerRadius, 24)
        XCTAssertEqual(staticModifier.interactiveUpThrough, NavigationSheetDetent.half.presentationDetent)
    }

    func testTransitGlassPresentationViewExtensions() {
        let testView = Text("Transit Timetable")
            .transitSheetGlassBackground(cornerRadius: 28)
        XCTAssertNotNil(testView)
        
        let presentedView = Text("Departures")
            .transitGlassPresentation(
                availableDetents: [.fraction(0.5), .large],
                cornerRadius: 28
            )
        XCTAssertNotNil(presentedView)
    }

    // MARK: - 2. Snapshot Tests: High-Contrast 3-Tier Glass Stack over Vector Cartography

    func testTransitSheetGlassOverHighContrastBasemapSnapshot() {
        // Construct simulated high-contrast vector cartography background
        // (dark asphalt roads, glowing transit routes, and water body)
        let simulatedBasemap = ZStack {
            Color(hex: "#0F172A") // Dark asphalt / night cartography
            
            // Saturated transit lines (MTA Line 6 & L)
            Path { path in
                path.move(to: CGPoint(x: 20, y: 10))
                path.addLine(to: CGPoint(x: 350, y: 190))
            }
            .stroke(Color(hex: "#007AFF"), lineWidth: 6) // Blue heavy rail line
            
            Path { path in
                path.move(to: CGPoint(x: 10, y: 150))
                path.addLine(to: CGPoint(x: 360, y: 30))
            }
            .stroke(Color(hex: "#FFB300"), lineWidth: 8) // Electric Amber route
            
            Circle()
                .fill(Color(hex: "#0284C7")) // Water body
                .frame(width: 140, height: 140)
                .offset(x: 100, y: -20)
        }
        
        // Modal transit bottom sheet content using 3-tier glass stack
        let sheetContent = VStack(alignment: .leading, spacing: 14) {
            // Drag indicator handle
            Capsule()
                .fill(Color.secondary.opacity(0.4))
                .frame(width: 36, height: 5)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 8)
            
            // Stop header
            HStack(spacing: 12) {
                Circle()
                    .fill(Color(hex: "#FFB300"))
                    .frame(width: 32, height: 32)
                    .overlay(
                        Text("L")
                            .font(.system(size: 17, weight: .black, design: .rounded))
                            .foregroundColor(.black)
                    )
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Bedford Av Station")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                    Text("Manhattan-bound • 8th Ave")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Live Radar Pulse Pill
                HStack(spacing: 5) {
                    Circle()
                        .fill(Color(hex: "#FFB300"))
                        .frame(width: 8, height: 8)
                    Text("LIVE 2m")
                        .font(.system(size: 11, weight: .heavy, design: .monospaced))
                        .foregroundColor(Color(hex: "#FFB300"))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color(hex: "#FFB300").opacity(0.16))
                .clipShape(Capsule())
            }
            .padding(.horizontal, 20)
            
            // Timetable Departure Pills
            HStack(spacing: 8) {
                Text("NEXT DEPARTURES")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal, 20)
            
            HStack(spacing: 8) {
                ForEach(["02", "07", "14", "21", "29"], id: \.self) { min in
                    Text(min)
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundColor(min == "02" ? .black : .primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            min == "02"
                                ? Color(hex: "#FFB300")
                                : Color.primary.opacity(0.08)
                        )
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity)
        .background(TransitSheetGlassBackground(cornerRadius: 24))
        .padding(.horizontal, 12)
        
        // Composite container: Sheet placed over high-contrast basemap
        let compositeView = ZStack(alignment: .bottom) {
            simulatedBasemap
            sheetContent
                .padding(.bottom, 12)
        }
        .frame(width: 375, height: 260)
        
        let vc = UIHostingController(rootView: compositeView)
        assertSnapshot(
            of: vc,
            as: .image(on: ViewImageConfig(size: CGSize(width: 375, height: 260)), precision: 0.98)
        )
    }
}
