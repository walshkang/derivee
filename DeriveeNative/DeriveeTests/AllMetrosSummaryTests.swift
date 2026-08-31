import XCTest
import SwiftUI
import CoreLocation
import SnapshotTesting
@testable import Derivee

final class AllMetrosSummaryTests: XCTestCase {
    
    func testCityOverviewCardFormattedDownloadSize() {
        let city = CityOverviewProgress(
            slug: "bos",
            displayName: "Boston",
            region: "Massachusetts, USA",
            clearedHexes: 0,
            totalHexes: 115000,
            isInstalled: false,
            centerCoordinate: CLLocationCoordinate2D(latitude: 42.3601, longitude: -71.0589),
            compressedSizeBytes: 9_400_000
        )
        
        XCTAssertEqual(city.compressedSizeBytes, 9_400_000)
        XCTAssertTrue(city.formattedDownloadSize.contains("MB") || city.formattedDownloadSize.contains("9"),
                      "Formatted download size should contain formatted MB: \(city.formattedDownloadSize)")
    }
    
    @MainActor
    func testCityOverviewCardDownloadStateTransitions() {
        let uninstalledCity = CityOverviewProgress(
            slug: "chi",
            displayName: "Chicago",
            region: "Illinois, USA",
            clearedHexes: 0,
            totalHexes: 220000,
            isInstalled: false,
            centerCoordinate: CLLocationCoordinate2D(latitude: 41.8781, longitude: -87.6298),
            compressedSizeBytes: 11_200_000
        )
        
        var downloadStarted = false
        let cardIdle = CityOverviewCard(
            city: uninstalledCity,
            downloadState: .idle,
            onViewStats: {},
            onViewOnMap: {},
            onStartDownload: {
                downloadStarted = true
            }
        )
        
        XCTAssertNotNil(cardIdle.onStartDownload)
        cardIdle.onStartDownload?()
        XCTAssertTrue(downloadStarted)
        
        let cardDownloading = CityOverviewCard(
            city: uninstalledCity,
            downloadState: .downloading(progress: 0.5, receivedBytes: 5_600_000, totalBytes: 11_200_000),
            onViewStats: {},
            onViewOnMap: {}
        )
        XCTAssertEqual(cardDownloading.downloadState, .downloading(progress: 0.5, receivedBytes: 5_600_000, totalBytes: 11_200_000))
        
        let cardCompleted = CityOverviewCard(
            city: uninstalledCity,
            downloadState: .completed,
            onViewStats: {},
            onViewOnMap: {}
        )
        XCTAssertEqual(cardCompleted.downloadState, .completed)
    }
    
    @MainActor
    func testAllMetrosSummaryViewSnapshot() {
        let summaryData = AllMetrosSummaryData(
            totalGlobalClearedHexes: 1420,
            totalGlobalHexes: 477118,
            totalDriftDistanceKm: 63.9,
            citiesExploredCount: 2,
            totalCitiesCount: 3,
            cityOverviews: [
                CityOverviewProgress(
                    slug: "nyc",
                    displayName: "New York City",
                    region: "New York, USA",
                    clearedHexes: 1280,
                    totalHexes: 362118,
                    isInstalled: true,
                    centerCoordinate: CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060),
                    compressedSizeBytes: 12_800_000
                ),
                CityOverviewProgress(
                    slug: "bos",
                    displayName: "Boston",
                    region: "Massachusetts, USA",
                    clearedHexes: 140,
                    totalHexes: 115000,
                    isInstalled: true,
                    centerCoordinate: CLLocationCoordinate2D(latitude: 42.3601, longitude: -71.0589),
                    compressedSizeBytes: 9_400_000
                ),
                CityOverviewProgress(
                    slug: "chi",
                    displayName: "Chicago",
                    region: "Illinois, USA",
                    clearedHexes: 0,
                    totalHexes: 220000,
                    isInstalled: false,
                    centerCoordinate: CLLocationCoordinate2D(latitude: 41.8781, longitude: -87.6298),
                    compressedSizeBytes: 11_200_000
                )
            ]
        )
        
        let testDefaults = UserDefaults(suiteName: "com.derivee.test.allmetrossnapshot")!
        testDefaults.removePersistentDomain(forName: "com.derivee.test.allmetrossnapshot")
        let detectionService = CityDetectionService(userDefaults: testDefaults)
        
        let view = NavigationStack {
            AllMetrosSummaryView(
                summaryData: summaryData,
                onSelectCity: { _ in },
                onViewOnMap: { _, _ in },
                cityDetectionService: detectionService
            )
            .navigationTitle("All Metros")
        }
        .frame(width: 393, height: 852)
        
        let vc = UIHostingController(rootView: view)
        vc.overrideUserInterfaceStyle = .light
        assertSnapshot(of: vc, as: .image(on: ViewImageConfig(size: CGSize(width: 393, height: 852)), precision: 0.98))
    }
}
