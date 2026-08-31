import XCTest
import SwiftUI
@testable import Derivee

final class SettingsDeepLinkTests: XCTestCase {
    
    func testSettingsSectionEnumCasesAndIdentifiers() {
        let expectedCases: [SettingsSection] = [
            .mapAesthetics,
            .transitWayfinding,
            .tracking,
            .notifications,
            .citiesStorage,
            .dataManagement,
            .about
        ]
        
        XCTAssertEqual(SettingsSection.allCases.count, expectedCases.count)
        
        for section in expectedCases {
            XCTAssertFalse(section.rawValue.isEmpty)
            XCTAssertEqual(section.id, section.rawValue)
        }
        
        // Assert specific anchor IDs for deep-linking
        XCTAssertEqual(SettingsSection.citiesStorage.rawValue, "citiesStorage")
        XCTAssertEqual(SettingsSection.mapAesthetics.rawValue, "mapAesthetics")
        XCTAssertEqual(SettingsSection.transitWayfinding.rawValue, "transitWayfinding")
        XCTAssertEqual(SettingsSection.tracking.rawValue, "tracking")
        XCTAssertEqual(SettingsSection.notifications.rawValue, "notifications")
        XCTAssertEqual(SettingsSection.dataManagement.rawValue, "dataManagement")
        XCTAssertEqual(SettingsSection.about.rawValue, "about")
    }
    
    func testSettingsSectionUniqueness() {
        let allIds = SettingsSection.allCases.map { $0.id }
        let uniqueIds = Set(allIds)
        XCTAssertEqual(allIds.count, uniqueIds.count, "All SettingsSection identifiers must be unique for ScrollViewReader anchoring")
    }
}
