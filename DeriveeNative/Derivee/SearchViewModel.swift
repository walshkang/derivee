import Foundation
import CoreLocation
import Observation

/// Observation-powered View Model managing Screen 4A place and station search (Wave PA.4 / design.md §12.2).
/// Features debounced offline prefix search, mode filtering, recent destinations persistence, and landmark conflation.
@Observable
@MainActor
public final class SearchViewModel {
    
    // MARK: - Published State
    
    public var searchQuery: String = "" {
        didSet {
            triggerDebouncedSearch()
        }
    }
    
    public var selectedFilter: SearchModeFilter = .all {
        didSet {
            triggerImmediateSearch()
        }
    }
    
    public var userLocation: CLLocationCoordinate2D? = nil {
        didSet {
            if !searchResults.isEmpty {
                sortResultsByProximity()
            }
        }
    }
    
    public private(set) var searchResults: [SearchResultItem] = []
    public private(set) var recentDestinations: [RecentSearchDestination] = []
    public private(set) var savedDestinationIds: Set<String> = []
    public private(set) var isSearching: Bool = false
    public private(set) var executionLatencyMs: Double = 0.0
    public private(set) var errorMessage: String? = nil
    
    // MARK: - Internal Dependencies
    
    private let spatialDbManager: SpatialDatabaseManager
    private let userDefaults: UserDefaults
    private var activeSearchTask: Task<Void, Never>?
    
    // MARK: - Initialization
    
    public init(
        spatialDbManager: SpatialDatabaseManager = .shared,
        userDefaults: UserDefaults = .standard,
        initialLocation: CLLocationCoordinate2D? = nil
    ) {
        self.spatialDbManager = spatialDbManager
        self.userDefaults = userDefaults
        self.userLocation = initialLocation
        
        loadSavedState()
    }
    
    // MARK: - State Persistence
    
    public func loadSavedState() {
        // Load recent destinations
        if let data = userDefaults.data(forKey: AppStorageKeys.recentSearchDestinations),
           let recents = try? JSONDecoder().decode([RecentSearchDestination].self, from: data) {
            self.recentDestinations = recents
        } else {
            self.recentDestinations = []
        }
        
        // Load saved destination IDs
        if let savedArray = userDefaults.stringArray(forKey: AppStorageKeys.savedSearchDestinations) {
            self.savedDestinationIds = Set(savedArray)
        } else {
            self.savedDestinationIds = []
        }
    }
    
    public func addRecentDestination(_ item: SearchResultItem) {
        var recents = recentDestinations.filter { $0.id != item.id && $0.title != item.title }
        let newRecent = RecentSearchDestination(item: item)
        recents.insert(newRecent, at: 0)
        
        if recents.count > 10 {
            recents = Array(recents.prefix(10))
        }
        
        self.recentDestinations = recents
        if let encoded = try? JSONEncoder().encode(recents) {
            userDefaults.set(encoded, forKey: AppStorageKeys.recentSearchDestinations)
        }
    }
    
    public func clearRecentDestinations() {
        self.recentDestinations = []
        userDefaults.removeObject(forKey: AppStorageKeys.recentSearchDestinations)
    }
    
    public func toggleSaved(_ item: SearchResultItem) {
        if savedDestinationIds.contains(item.id) {
            savedDestinationIds.remove(item.id)
        } else {
            savedDestinationIds.insert(item.id)
        }
        userDefaults.set(Array(savedDestinationIds), forKey: AppStorageKeys.savedSearchDestinations)
        
        // Update isSaved in searchResults
        self.searchResults = self.searchResults.map { res in
            var updated = res
            updated.isSaved = savedDestinationIds.contains(res.id)
            return updated
        }
    }
    
    public func isItemSaved(_ id: String) -> Bool {
        savedDestinationIds.contains(id)
    }
    
    // MARK: - Search Orchestration
    
    private func triggerDebouncedSearch() {
        activeSearchTask?.cancel()
        
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty {
            self.isSearching = false
            self.searchResults = []
            return
        }
        
        activeSearchTask = Task {
            try? await Task.sleep(nanoseconds: 120_000_000) // 120ms debounce
            guard !Task.isCancelled else { return }
            await performSearch(query: query)
        }
    }
    
    private func triggerImmediateSearch() {
        activeSearchTask?.cancel()
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty {
            self.isSearching = false
            self.searchResults = []
            return
        }
        
        activeSearchTask = Task {
            await performSearch(query: query)
        }
    }
    
    public func performSearch(query: String) async {
        let cleanQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanQuery.isEmpty else {
            self.searchResults = []
            self.isSearching = false
            return
        }
        
        self.isSearching = true
        self.errorMessage = nil
        let startTime = CFAbsoluteTimeGetCurrent()
        
        do {
            // 1. Search transit stops and routes from SpatialDatabaseManager
            async let stopsTask = spatialDbManager.searchTransitStops(query: cleanQuery, filter: selectedFilter, limit: 15)
            async let routesTask = spatialDbManager.searchTransitRoutes(query: cleanQuery, filter: selectedFilter, limit: 6)
            
            let (stops, routes) = try await (stopsTask, routesTask)
            
            // 2. Search curated landmarks if filter permits
            var landmarkResults: [SearchResultItem] = []
            if selectedFilter == .all || selectedFilter == .saved {
                let lower = cleanQuery.lowercased()
                let matchingLandmarks = HistoricLandmarkCatalog.landmarks.filter { item in
                    item.name.localizedCaseInsensitiveContains(lower) ||
                    item.borough.localizedCaseInsensitiveContains(lower) ||
                    item.category.localizedCaseInsensitiveContains(lower)
                }
                
                landmarkResults = matchingLandmarks.prefix(5).map { lm in
                    SearchResultItem(
                        id: lm.id,
                        title: lm.name,
                        subtitle: "\(lm.borough) • \(lm.category)",
                        category: .landmark(landmarkId: lm.id),
                        coordinate: lm.coordinate,
                        modalClass: nil,
                        routes: [],
                        badgeColorHex: "#FFB300",
                        isSaved: savedDestinationIds.contains(lm.id)
                    )
                }
            }
            
            // 3. Combine and annotate with saved state
            var combined = routes + stops + landmarkResults
            for i in 0..<combined.count {
                combined[i].isSaved = savedDestinationIds.contains(combined[i].id)
            }
            
            // 4. Apply Saved filter if active
            if selectedFilter == .saved {
                combined = combined.filter { $0.isSaved }
            }
            
            self.searchResults = combined
            sortResultsByProximity()
            
            let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000.0
            self.executionLatencyMs = elapsed
            self.isSearching = false
            
        } catch {
            self.errorMessage = "Search failed: \(error.localizedDescription)"
            self.isSearching = false
        }
    }
    
    // MARK: - Sorting & Ranking
    
    private func sortResultsByProximity() {
        let queryLower = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !queryLower.isEmpty else { return }
        
        let userLoc: CLLocation? = userLocation.map { CLLocation(latitude: $0.latitude, longitude: $0.longitude) }
        
        self.searchResults.sort { itemA, itemB in
            let titleA = itemA.title.lowercased()
            let titleB = itemB.title.lowercased()
            
            // Priority 1: Exact prefix match on title
            let prefixA = titleA.hasPrefix(queryLower)
            let prefixB = titleB.hasPrefix(queryLower)
            if prefixA != prefixB {
                return prefixA
            }
            
            // Priority 2: Proximity to user if both have coordinates
            if let user = userLoc,
               let coordA = itemA.coordinate,
               let coordB = itemB.coordinate {
                let distA = user.distance(from: CLLocation(latitude: coordA.latitude, longitude: coordA.longitude))
                let distB = user.distance(from: CLLocation(latitude: coordB.latitude, longitude: coordB.longitude))
                if abs(distA - distB) > 500 { // meaningful distance difference
                    return distA < distB
                }
            }
            
            // Priority 3: Shorter title / Alphabetical
            if titleA.count != titleB.count {
                return titleA.count < titleB.count
            }
            return titleA < titleB
        }
    }
}
