import XCTest
import SwiftUI
import CoreLocation
@testable import Derivee

@MainActor
final class PlaceSearchTests: XCTestCase {
    
    // MARK: - 1. Filter Properties & Matching
    
    func testSearchModeFilterProperties() {
        XCTAssertEqual(SearchModeFilter.allCases.count, 5)
        XCTAssertEqual(SearchModeFilter.all.iconName, "sparkles")
        XCTAssertEqual(SearchModeFilter.subway.iconName, "tram.fill")
        XCTAssertEqual(SearchModeFilter.buses.iconName, "bus.fill")
        XCTAssertEqual(SearchModeFilter.rail.iconName, "train.side.front.car")
        XCTAssertEqual(SearchModeFilter.saved.iconName, "bookmark.fill")
        
        // Modal class matching
        XCTAssertTrue(SearchModeFilter.all.matches(modalClass: .subway))
        XCTAssertTrue(SearchModeFilter.all.matches(modalClass: .bus))
        XCTAssertTrue(SearchModeFilter.all.matches(modalClass: nil))
        
        XCTAssertTrue(SearchModeFilter.subway.matches(modalClass: .subway))
        XCTAssertFalse(SearchModeFilter.subway.matches(modalClass: .bus))
        
        XCTAssertTrue(SearchModeFilter.buses.matches(modalClass: .bus))
        XCTAssertFalse(SearchModeFilter.buses.matches(modalClass: .subway))
        
        XCTAssertTrue(SearchModeFilter.rail.matches(modalClass: .lightRail))
        XCTAssertTrue(SearchModeFilter.rail.matches(modalClass: .subway))
        XCTAssertFalse(SearchModeFilter.rail.matches(modalClass: .bus))
    }
    
    // MARK: - 2. RecentSearchDestination Serialization & Mapping
    
    func testRecentSearchDestinationSerialization() throws {
        let dest = RecentSearchDestination(
            id: "landmark_gct",
            title: "Grand Central Terminal",
            subtitle: "Manhattan • Architectural",
            kind: "landmark",
            stopId: nil,
            routeId: nil,
            latitude: 40.7527,
            longitude: -73.9772,
            modalClassRaw: nil,
            routes: nil,
            badgeColorHex: "#FFB300"
        )
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(dest)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(RecentSearchDestination.self, from: data)
        
        XCTAssertEqual(decoded.id, "landmark_gct")
        XCTAssertEqual(decoded.title, "Grand Central Terminal")
        XCTAssertEqual(decoded.latitude, 40.7527)
        XCTAssertEqual(decoded.longitude, -73.9772)
        XCTAssertEqual(decoded.badgeColorHex, "#FFB300")
        
        // Routing location mapping
        let routingLoc = try XCTUnwrap(decoded.routingLocation)
        XCTAssertEqual(routingLoc.displayName, "Grand Central Terminal")
        XCTAssertEqual(routingLoc.coordinate?.latitude, 40.7527)
        XCTAssertEqual(routingLoc.coordinate?.longitude, -73.9772)
    }
    
    // MARK: - 3. SearchResultItem RoutingLocation Resolution
    
    func testSearchResultItemRoutingLocationResolution() throws {
        // Station with coordinate
        let stationItem = SearchResultItem(
            id: "127",
            title: "Times Sq-42 St",
            subtitle: "Subway • 1, 2, 3, 7, N, Q, R, W, S",
            category: .station(stopId: "127", modalClass: .subway),
            coordinate: CLLocationCoordinate2D(latitude: 40.7552, longitude: -73.9874),
            modalClass: .subway,
            routes: ["1", "2", "3"]
        )
        let stationLoc = try XCTUnwrap(stationItem.routingLocation)
        XCTAssertEqual(stationLoc.displayName, "Times Sq-42 St")
        XCTAssertEqual(stationLoc.coordinate?.latitude, 40.7552)
        
        // Landmark
        let landmarkItem = SearchResultItem(
            id: "landmark_empire_state",
            title: "Empire State Building",
            subtitle: "Manhattan • Architectural",
            category: .landmark(landmarkId: "landmark_empire_state"),
            coordinate: CLLocationCoordinate2D(latitude: 40.7484, longitude: -73.9857)
        )
        let landmarkLoc = try XCTUnwrap(landmarkItem.routingLocation)
        XCTAssertEqual(landmarkLoc.displayName, "Empire State Building")
        XCTAssertEqual(landmarkLoc.coordinate?.latitude, 40.7484)
    }
    
    // MARK: - 4. SpatialDatabaseManager Search Queries
    
    func testSpatialDatabaseManagerStopSearch() async throws {
        let dbManager = SpatialDatabaseManager.shared
        _ = try await dbManager.isHydrationComplete()
        
        let results = try await dbManager.searchTransitStops(query: "Times Sq", filter: .all, limit: 10)
        XCTAssertFalse(results.isEmpty, "Search for 'Times Sq' should return station results")
        
        let first = try XCTUnwrap(results.first)
        XCTAssertTrue(first.title.contains("Times Sq"), "First result should contain 'Times Sq'")
        XCTAssertEqual(first.modalClass, .subway)
        XCTAssertNotNil(first.coordinate)
    }
    
    func testSpatialDatabaseManagerRouteSearch() async throws {
        let dbManager = SpatialDatabaseManager.shared
        _ = try await dbManager.isHydrationComplete()
        
        let results = try await dbManager.searchTransitRoutes(query: "6", filter: .all, limit: 5)
        XCTAssertFalse(results.isEmpty, "Search for '6' should return transit routes")
        
        let line6 = results.first(where: { $0.title == "6" })
        XCTAssertNotNil(line6, "Route search should find Lexington Avenue Line 6")
        XCTAssertEqual(line6?.modalClass, .subway)
    }
    
    // MARK: - 5. SearchViewModel Recents & Bookmarks
    
    func testSearchViewModelRecentsAndBookmarks() {
        let suiteName = "test_search_vm_\(UUID().uuidString)"
        let testDefaults = UserDefaults(suiteName: suiteName)!
        defer { testDefaults.removePersistentDomain(forName: suiteName) }
        
        let vm = SearchViewModel(spatialDbManager: .shared, userDefaults: testDefaults)
        XCTAssertTrue(vm.recentDestinations.isEmpty)
        XCTAssertTrue(vm.savedDestinationIds.isEmpty)
        
        let item = SearchResultItem(
            id: "test_stop_1",
            title: "Astor Pl",
            subtitle: "Subway • 6",
            category: .station(stopId: "test_stop_1", modalClass: .subway),
            coordinate: CLLocationCoordinate2D(latitude: 40.7305, longitude: -73.9920)
        )
        
        // Add recent
        vm.addRecentDestination(item)
        XCTAssertEqual(vm.recentDestinations.count, 1)
        XCTAssertEqual(vm.recentDestinations.first?.title, "Astor Pl")
        
        // Toggle saved
        vm.toggleSaved(item)
        XCTAssertTrue(vm.isItemSaved("test_stop_1"))
        
        vm.toggleSaved(item)
        XCTAssertFalse(vm.isItemSaved("test_stop_1"))
        
        // Clear recents
        vm.clearRecentDestinations()
        XCTAssertTrue(vm.recentDestinations.isEmpty)
    }
    
    // MARK: - 6. SearchViewModel Search Execution
    
    func testSearchViewModelSearchExecution() async {
        let suiteName = "test_search_vm_exec_\(UUID().uuidString)"
        let testDefaults = UserDefaults(suiteName: suiteName)!
        defer { testDefaults.removePersistentDomain(forName: suiteName) }
        
        let vm = SearchViewModel(
            spatialDbManager: .shared,
            userDefaults: testDefaults,
            initialLocation: CLLocationCoordinate2D(latitude: 40.7580, longitude: -73.9855)
        )
        
        await vm.performSearch(query: "Grand Central")
        
        XCTAssertFalse(vm.searchResults.isEmpty, "Searching 'Grand Central' should return stations and landmarks")
        XCTAssertFalse(vm.isSearching)
        XCTAssertGreaterThan(vm.executionLatencyMs, 0.0)
        
        // Should contain both landmark and station
        let hasLandmark = vm.searchResults.contains { item in
            if case .landmark = item.category { return true }
            return false
        }
        XCTAssertTrue(hasLandmark, "Results should contain Grand Central Terminal landmark")
    }
    
    // MARK: - 7. SearchViewModel Mode Filter Switching
    
    func testSearchViewModelFilterSwitching() async {
        let suiteName = "test_search_vm_filter_\(UUID().uuidString)"
        let testDefaults = UserDefaults(suiteName: suiteName)!
        defer { testDefaults.removePersistentDomain(forName: suiteName) }
        
        let vm = SearchViewModel(
            spatialDbManager: .shared,
            userDefaults: testDefaults
        )
        
        // Search all
        vm.selectedFilter = .all
        await vm.performSearch(query: "Broadway")
        let allCount = vm.searchResults.count
        
        // Filter to subway only
        vm.selectedFilter = .subway
        await vm.performSearch(query: "Broadway")
        for item in vm.searchResults {
            XCTAssertEqual(item.modalClass, .subway, "Subway filter should only return subway items")
        }
        
        XCTAssertLessThanOrEqual(vm.searchResults.count, allCount)
    }
    
    // MARK: - 8. UI Construction Tests
    
    func testSearchCapsuleOverlayViewConstruction() {
        var tapped = false
        let view = SearchCapsuleOverlay {
            tapped = true
        }
        
        let hosting = UIHostingController(rootView: view)
        XCTAssertNotNil(hosting.view)
    }
    
    func testPlaceSearchViewConstruction() {
        let vm = SearchViewModel(spatialDbManager: .shared)
        var stationSelected: String? = nil
        var destSelected: RoutingLocation? = nil
        var closed = false
        
        let view = PlaceSearchView(
            viewModel: vm,
            onSelectStation: { stopId, _ in
                stationSelected = stopId
            },
            onSelectDestination: { loc in
                destSelected = loc
            },
            onClose: {
                closed = true
            }
        )
        
        let hosting = UIHostingController(rootView: view)
        XCTAssertNotNil(hosting.view)
        XCTAssertNil(stationSelected)
        XCTAssertNil(destSelected)
        XCTAssertFalse(closed)
    }
}
