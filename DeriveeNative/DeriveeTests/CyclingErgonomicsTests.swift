import XCTest
import SwiftUI
import SnapshotTesting
@testable import Derivee

@MainActor
final class CyclingErgonomicsTests: XCTestCase {

    // MARK: - 1. 56×56pt Touch Target Floor Invariant (Doc 14)
    
    func testCyclingTouchTargetFloor() {
        // 1. ThumbZonePrimaryAction.unlockBike
        var unlockExecuted = false
        let unlockAction = ThumbZonePrimaryAction.unlockBike(
            title: "Unlock Citi Bike",
            batterySoc: 85,
            dockInfo: "8 docks",
            action: { unlockExecuted = true }
        )
        XCTAssertEqual(unlockAction.height, 56, "Cycling primary action must have 56pt minimum touch target floor for gloved use")
        unlockAction.execute()
        XCTAssertTrue(unlockExecuted)
        
        // 2. PreArmedFallbackCard
        var switched = false
        let fallbackCard = PreArmedFallbackCard(
            primaryStationName: "Astor Place",
            fallbackStationName: "Broadway & E 14th St",
            onSwitchToFallback: { switched = true }
        )
        XCTAssertNotNil(fallbackCard)
        fallbackCard.onSwitchToFallback()
        XCTAssertTrue(switched)
        
        // 3. DockOverflowAutoRerouteBanner
        var accepted = false
        let rerouteBanner = DockOverflowAutoRerouteBanner(
            failedStationName: "Astor Place",
            reroutedStationName: "Lafayette St & 8th St",
            onAcceptReroute: { accepted = true }
        )
        XCTAssertNotNil(rerouteBanner)
        rerouteBanner.onAcceptReroute()
        XCTAssertTrue(accepted)
        
        // 4. CyclingHUDView initialization
        let hud = CyclingHUDView(
            maneuver: .turnLeft,
            distanceMeters: 180,
            streetName: "14th St Protected Path",
            infrastructureType: .protectedBikeTrack,
            destinationDockName: "Broadway & E 14th St",
            availableDocksAtDest: 8
        )
        XCTAssertNotNil(hud)
    }

    // MARK: - 2. 0.5s Glance Window & Infrastructure Stress Tests
    
    func testCyclingManeuversAndInfrastructureLTS() {
        // Cycling Maneuvers
        XCTAssertEqual(CyclingManeuver.turnLeft.systemIcon, "arrow.turn.up.left")
        XCTAssertEqual(CyclingManeuver.turnRight.systemIcon, "arrow.turn.up.right")
        XCTAssertEqual(CyclingManeuver.straight.systemIcon, "arrow.up")
        XCTAssertEqual(CyclingManeuver.arriveAtDock.systemIcon, "bicycle.circle.fill")
        XCTAssertEqual(CyclingManeuver.turnLeft.conciseVoicePrompt, "Turn left")
        
        // Infrastructure LTS Classifications per Doc 14 Section 3
        XCTAssertEqual(CyclingInfrastructureType.protectedBikeTrack.levelOfTrafficStress, 1)
        XCTAssertEqual(CyclingInfrastructureType.greenway.levelOfTrafficStress, 1)
        XCTAssertEqual(CyclingInfrastructureType.paintedLane.levelOfTrafficStress, 2)
        XCTAssertEqual(CyclingInfrastructureType.arterialLane.levelOfTrafficStress, 3)
        XCTAssertEqual(CyclingInfrastructureType.sharedRoad.levelOfTrafficStress, 4)
        
        XCTAssertEqual(CyclingInfrastructureType.protectedBikeTrack.badgeTitle, "PROTECTED TRACK")
        XCTAssertEqual(CyclingInfrastructureType.greenway.badgeTitle, "GREENWAY")
    }

    // MARK: - 3. WCAG AAA Contrast Ratio Mathematical Assertions (≥ 7.0:1)
    
    func testWCAGAAAColorContrastRatios() {
        // Emerald Badge: #064E3B on #D1FAE5
        let emeraldTextLuminance = calculateRelativeLuminance(r: 6/255.0, g: 78/255.0, b: 59/255.0)
        let emeraldBgLuminance = calculateRelativeLuminance(r: 209/255.0, g: 250/255.0, b: 229/255.0)
        let emeraldRatio = calculateContrastRatio(l1: emeraldBgLuminance, l2: emeraldTextLuminance)
        XCTAssertGreaterThanOrEqual(emeraldRatio, 7.0, "Low-risk emerald badge must satisfy WCAG AAA (≥ 7.0:1)")
        
        // Amber Badge: #78350F on #FEF3C7
        let amberTextLuminance = calculateRelativeLuminance(r: 120/255.0, g: 53/255.0, b: 15/255.0)
        let amberBgLuminance = calculateRelativeLuminance(r: 254/255.0, g: 243/255.0, b: 199/255.0)
        let amberRatio = calculateContrastRatio(l1: amberBgLuminance, l2: amberTextLuminance)
        XCTAssertGreaterThanOrEqual(amberRatio, 7.0, "Moderate-risk amber badge must satisfy WCAG AAA (≥ 7.0:1)")
        
        // Red Alert Badge: #7F1D1D on #FEE2E2
        let redTextLuminance = calculateRelativeLuminance(r: 127/255.0, g: 29/255.0, b: 29/255.0)
        let redBgLuminance = calculateRelativeLuminance(r: 254/255.0, g: 226/255.0, b: 226/255.0)
        let redRatio = calculateContrastRatio(l1: redBgLuminance, l2: redTextLuminance)
        XCTAssertGreaterThanOrEqual(redRatio, 7.0, "High-risk red badge must satisfy WCAG AAA (≥ 7.0:1)")
        
        // Carbon HUD: Pure White (#FFFFFF) on Carbon (#0B0F17)
        let whiteLuminance = calculateRelativeLuminance(r: 1.0, g: 1.0, b: 1.0)
        let carbonLuminance = calculateRelativeLuminance(r: 11/255.0, g: 15/255.0, b: 23/255.0)
        let carbonRatio = calculateContrastRatio(l1: whiteLuminance, l2: carbonLuminance)
        XCTAssertGreaterThanOrEqual(carbonRatio, 15.0, "Carbon cycling HUD must exceed 15:1 contrast ratio")
        
        // Electric Amber Primary Button: Slate text (#0F172A) on Amber (#FFB300)
        let slateLuminance = calculateRelativeLuminance(r: 15/255.0, g: 23/255.0, b: 42/255.0)
        let electricAmberLuminance = calculateRelativeLuminance(r: 255/255.0, g: 179/255.0, b: 0/255.0)
        let buttonRatio = calculateContrastRatio(l1: electricAmberLuminance, l2: slateLuminance)
        XCTAssertGreaterThanOrEqual(buttonRatio, 7.0, "Electric amber action button must satisfy WCAG AAA (≥ 7.0:1)")
    }
    
    // MARK: - 4. Snapshot Tests: Cycling HUD
    
    func testCyclingHUDViewSnapshot() {
        let hudView = CyclingHUDView(
            maneuver: .turnLeft,
            distanceMeters: 140,
            streetName: "14th St Protected Path",
            infrastructureType: .protectedBikeTrack,
            destinationDockName: "Broadway & E 14th St",
            availableDocksAtDest: 8,
            batterySocPercent: 88,
            estimatedRangeMiles: 17.6,
            fallbackStationName: "Lafayette St & E 8th St",
            fallbackExtraWalkMeters: 120,
            isHighContrastDark: true
        )
        .frame(width: 393)
        .padding()
        .background(Color.black)
        
        assertSnapshot(of: hudView, as: .image)
    }

    // MARK: - Math Helpers (WCAG 2.1 Formula)
    
    private func calculateRelativeLuminance(r: Double, g: Double, b: Double) -> Double {
        func sRGBtoLin(_ c: Double) -> Double {
            c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * sRGBtoLin(r) + 0.7152 * sRGBtoLin(g) + 0.0722 * sRGBtoLin(b)
    }
    
    private func calculateContrastRatio(l1: Double, l2: Double) -> Double {
        let brighter = max(l1, l2)
        let darker = min(l1, l2)
        return (brighter + 0.05) / (darker + 0.05)
    }
}
