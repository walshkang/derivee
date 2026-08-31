import XCTest
import CoreLocation
import SwiftUI
import SnapshotTesting
@testable import Derivee

final class CitySelectorPillTests: XCTestCase {
    
    func testStatsBrowsingModeAccessors() {
        let cityMode = StatsBrowsingMode.city(slug: "bos")
        XCTAssertEqual(cityMode.slug, "bos")
        XCTAssertFalse(cityMode.isAllMetros)
        
        let allMetrosMode = StatsBrowsingMode.allMetros
        XCTAssertNil(allMetrosMode.slug)
        XCTAssertTrue(allMetrosMode.isAllMetros)
    }
    
    func testProximityContainment() {
        let manifest = CityManifest.defaultManifest
        let nyc = try! XCTUnwrap(manifest.findCity(bySlug: "nyc"))
        let bos = try! XCTUnwrap(manifest.findCity(bySlug: "bos"))
        
        let manhattanCoord = CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060)
        let bostonCoord = CLLocationCoordinate2D(latitude: 42.3601, longitude: -71.0589)
        let remoteCoord = CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194) // San Francisco
        
        XCTAssertTrue(nyc.bounds?.contains(coordinate: manhattanCoord) ?? false)
        XCTAssertFalse(nyc.bounds?.contains(coordinate: bostonCoord) ?? true)
        
        XCTAssertTrue(bos.bounds?.contains(coordinate: bostonCoord) ?? false)
        XCTAssertFalse(bos.bounds?.contains(coordinate: manhattanCoord) ?? true)
        
        XCTAssertFalse(nyc.bounds?.contains(coordinate: remoteCoord) ?? true)
        XCTAssertFalse(bos.bounds?.contains(coordinate: remoteCoord) ?? true)
    }
    
    func testAllMetrosSummaryDataCalculations() {
        let summary = AllMetrosSummaryData(
            totalGlobalClearedHexes: 1000,
            totalGlobalHexes: 10000,
            totalDriftDistanceKm: 45.0,
            citiesExploredCount: 2,
            totalCitiesCount: 3,
            cityOverviews: [
                CityOverviewProgress(
                    slug: "nyc",
                    displayName: "New York City",
                    region: "New York, USA",
                    clearedHexes: 800,
                    totalHexes: 6000,
                    isInstalled: true,
                    centerCoordinate: CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060)
                ),
                CityOverviewProgress(
                    slug: "bos",
                    displayName: "Boston",
                    region: "Massachusetts, USA",
                    clearedHexes: 200,
                    totalHexes: 4000,
                    isInstalled: true,
                    centerCoordinate: CLLocationCoordinate2D(latitude: 42.3601, longitude: -71.0589)
                )
            ]
        )
        
        XCTAssertEqual(summary.globalPercentage, 10.0, accuracy: 1e-4)
        XCTAssertEqual(summary.formattedGlobalPercentage, "10.0%")
        XCTAssertEqual(summary.formattedDriftDistance, "45 km")
        XCTAssertEqual(summary.cityOverviews[0].percentage, (800.0 / 6000.0) * 100.0, accuracy: 1e-4)
        XCTAssertEqual(summary.cityOverviews[1].percentage, 5.0, accuracy: 1e-4)
    }
    
    func testCitySelectorPillManageCitiesAction() {
        var manageCitiesInvoked = false
        let manifest = CityManifest.defaultManifest.cities
        
        let pill = CitySelectorPill(
            browsingMode: .city(slug: "nyc"),
            installedPacks: manifest,
            onSelectMode: { _ in },
            onManageCities: {
                manageCitiesInvoked = true
            }
        )
        
        XCTAssertNotNil(pill.onManageCities)
        pill.onManageCities?()
        XCTAssertTrue(manageCitiesInvoked, "onManageCities callback should be executed when triggered")
    }
    
    func testCitySelectorPillUninstalledPacksAction() {
        var uninstalledCitySelected: CityManifestEntry? = nil
        let manifest = CityManifest.defaultManifest.cities
        let installed = [manifest[0]] // NYC
        let uninstalled = [manifest[1], manifest[2]] // Boston, Chicago
        
        let pill = CitySelectorPill(
            browsingMode: .city(slug: "nyc"),
            installedPacks: installed,
            uninstalledPacks: uninstalled,
            onSelectMode: { _ in },
            onSelectUninstalledCity: { entry in
                uninstalledCitySelected = entry
            }
        )
        
        XCTAssertEqual(pill.uninstalledPacks.count, 2)
        XCTAssertNotNil(pill.onSelectUninstalledCity)
        pill.onSelectUninstalledCity?(uninstalled[0])
        XCTAssertEqual(uninstalledCitySelected?.slug, "bos")
    }
    
    @MainActor
    func testCitySelectorPillSnapshots() {
        let manifest = CityManifest.defaultManifest.cities
        let manhattanCoord = CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060)
        let installed = [manifest[0]]
        let uninstalled = [manifest[1], manifest[2]]
        
        let activePill = CitySelectorPill(
            browsingMode: .city(slug: "nyc"),
            installedPacks: installed,
            uninstalledPacks: uninstalled,
            userLocation: manhattanCoord,
            onSelectMode: { _ in }
        )
        .frame(width: 250, height: 60)
        
        let vc = UIHostingController(rootView: activePill)
        vc.overrideUserInterfaceStyle = .light
        assertSnapshot(of: vc, as: .image(on: ViewImageConfig(size: CGSize(width: 250, height: 60)), precision: 0.98))
    }
}
