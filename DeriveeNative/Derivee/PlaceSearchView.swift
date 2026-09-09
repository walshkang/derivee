import SwiftUI
import CoreLocation

/// Screen 4A: Place & Station Search (Wave PA.4 / design.md §12.2 / Guardrail G10).
/// Provides instant offline prefix search across stops, routes, and landmarks,
/// with recent destinations history and quick-access mode filters.
public struct PlaceSearchView: View {
    @State public var viewModel: SearchViewModel
    @FocusState private var isFieldFocused: Bool
    
    public var onSelectStation: ((String, CLLocationCoordinate2D?) -> Void)?
    public var onSelectDestination: ((RoutingLocation) -> Void)?
    public var onClose: (() -> Void)?
    
    public init(
        viewModel: SearchViewModel? = nil,
        onSelectStation: ((String, CLLocationCoordinate2D?) -> Void)? = nil,
        onSelectDestination: ((RoutingLocation) -> Void)? = nil,
        onClose: (() -> Void)? = nil
    ) {
        self._viewModel = State(initialValue: viewModel ?? SearchViewModel())
        self.onSelectStation = onSelectStation
        self.onSelectDestination = onSelectDestination
        self.onClose = onClose
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // MARK: - Search Input Bar & Close Button
            searchHeaderBar
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 12)
            
            // MARK: - Quick-Access Mode Filter Strip
            filterStrip
                .padding(.bottom, 12)
            
            Divider()
            
            // MARK: - Content Body
            ScrollView {
                VStack(spacing: 16) {
                    if viewModel.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        // Empty query state: Recent destinations and Curated landmarks
                        emptyQueryContent
                    } else if viewModel.isSearching {
                        // Searching indicator
                        loadingView
                    } else if viewModel.searchResults.isEmpty {
                        // No results state
                        noResultsView
                    } else {
                        // Active search results
                        resultsListView
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
        .background(Color(hex: "#F9F9F6"))
        .onAppear {
            isFieldFocused = true
        }
    }
    
    // MARK: - Search Header Bar
    
    @ViewBuilder
    private var searchHeaderBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(Color(hex: "#FFB300"))
                
                TextField("Search stations, lines, places...", text: $viewModel.searchQuery)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .focused($isFieldFocused)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                
                if !viewModel.searchQuery.isEmpty {
                    Button(action: {
                        viewModel.searchQuery = ""
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 15))
                            .foregroundColor(.secondary.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color(uiColor: .systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.black.opacity(0.08), lineWidth: 1)
            )
            
            if let onClose = onClose {
                Button(action: onClose) {
                    Text("Cancel")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundColor(Color(hex: "#0F172A"))
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    // MARK: - Filter Strip
    
    @ViewBuilder
    private var filterStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(SearchModeFilter.allCases) { filter in
                    let isSelected = viewModel.selectedFilter == filter
                    Button(action: {
                        let impact = UIImpactFeedbackGenerator(style: .light)
                        impact.impactOccurred()
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                            viewModel.selectedFilter = filter
                        }
                    }) {
                        HStack(spacing: 5) {
                            Image(systemName: filter.iconName)
                                .font(.system(size: 11, weight: .bold))
                            Text(filter.displayName)
                                .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(isSelected ? Color(hex: "#0F172A") : Color.black.opacity(0.05))
                        .foregroundColor(isSelected ? .white : .primary)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
    }
    
    // MARK: - Empty Query Content
    
    @ViewBuilder
    private var emptyQueryContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Recent Searches
            if !viewModel.recentDestinations.isEmpty && viewModel.selectedFilter != .saved {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("RECENT SEARCHES")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(.secondary)
                        Spacer()
                        Button(action: {
                            viewModel.clearRecentDestinations()
                        }) {
                            Text("Clear")
                                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    VStack(spacing: 8) {
                        ForEach(viewModel.recentDestinations) { recent in
                            let item = recent.toSearchResultItem(isSaved: viewModel.isItemSaved(recent.id))
                            searchResultRow(item: item)
                        }
                    }
                }
            }
            
            // Saved Places (if Saved filter active or empty state)
            if viewModel.selectedFilter == .saved {
                savedPlacesSection
            } else {
                // Curated Landmarks
                curatedLandmarksSection
            }
        }
    }
    
    // MARK: - Saved Places Section
    
    @ViewBuilder
    private var savedPlacesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("SAVED PLACES")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(.secondary)
            
            let savedItems = HistoricLandmarkCatalog.landmarks.filter { viewModel.isItemSaved($0.id) }
            if savedItems.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "bookmark")
                            .font(.system(size: 28))
                            .foregroundColor(.secondary.opacity(0.4))
                        Text("No saved places yet")
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 30)
                    Spacer()
                }
            } else {
                VStack(spacing: 8) {
                    ForEach(savedItems, id: \.id) { lm in
                        let item = SearchResultItem(
                            id: lm.id,
                            title: lm.name,
                            subtitle: "\(lm.borough) • \(lm.category)",
                            category: .landmark(landmarkId: lm.id),
                            coordinate: lm.coordinate,
                            badgeColorHex: "#FFB300",
                            isSaved: true
                        )
                        searchResultRow(item: item)
                    }
                }
            }
        }
    }
    
    // MARK: - Curated Landmarks Section
    
    @ViewBuilder
    private var curatedLandmarksSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("CURATED LANDMARKS")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.secondary)
                Spacer()
            }
            
            VStack(spacing: 8) {
                ForEach(HistoricLandmarkCatalog.landmarks.prefix(6), id: \.id) { lm in
                    let item = SearchResultItem(
                        id: lm.id,
                        title: lm.name,
                        subtitle: "\(lm.borough) • \(lm.category)",
                        category: .landmark(landmarkId: lm.id),
                        coordinate: lm.coordinate,
                        badgeColorHex: "#FFB300",
                        isSaved: viewModel.isItemSaved(lm.id)
                    )
                    searchResultRow(item: item)
                }
            }
        }
    }
    
    // MARK: - Results List View
    
    @ViewBuilder
    private var resultsListView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(viewModel.searchResults.count) RESULTS")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.secondary)
                Spacer()
                if viewModel.executionLatencyMs > 0 {
                    Text("\(String(format: "%.1f", viewModel.executionLatencyMs))ms")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundColor(.secondary.opacity(0.7))
                }
            }
            
            ForEach(viewModel.searchResults) { item in
                searchResultRow(item: item)
            }
        }
    }
    
    // MARK: - Search Result Row
    
    @ViewBuilder
    private func searchResultRow(item: SearchResultItem) -> some View {
        HStack(spacing: 12) {
            // Icon / Category Badge
            resultIconView(for: item)
            
            // Title and Subtitle
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(Color(hex: "#0F172A"))
                    .lineLimit(1)
                
                Text(item.subtitle)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            // Bookmark Toggle
            Button(action: {
                let impact = UIImpactFeedbackGenerator(style: .light)
                impact.impactOccurred()
                withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) {
                    viewModel.toggleSaved(item)
                }
            }) {
                Image(systemName: item.isSaved ? "bookmark.fill" : "bookmark")
                    .font(.system(size: 14))
                    .foregroundColor(item.isSaved ? Color(hex: "#FFB300") : .secondary.opacity(0.4))
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            
            // Directions / Navigate Action Button
            Button(action: {
                handleItemDirectionsTap(item)
            }) {
                Image(systemName: "arrow.triangle.turn.up.right.circle.fill")
                    .font(.system(size: 22))
                    .foregroundColor(Color(hex: "#FFB300"))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(uiColor: .systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.black.opacity(0.06), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            handleItemRowTap(item)
        }
    }
    
    // MARK: - Result Icon View
    
    @ViewBuilder
    private func resultIconView(for item: SearchResultItem) -> some View {
        ZStack {
            Circle()
                .fill(Color(hex: item.badgeColorHex ?? "#0F172A").opacity(0.12))
                .frame(width: 38, height: 38)
            
            switch item.category {
            case .station(_, let modalClass):
                Image(systemName: modalClass.symbolName)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(Color(hex: item.badgeColorHex ?? "#0F172A"))
            case .route:
                if let firstRoute = item.routes.first, firstRoute.count <= 3 {
                    Text(firstRoute)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(Color(hex: item.badgeColorHex ?? "#0F172A"))
                } else {
                    Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(Color(hex: item.badgeColorHex ?? "#0F172A"))
                }
            case .landmark:
                Image(systemName: "building.2.crop.circle.fill")
                    .font(.system(size: 18))
                    .foregroundColor(Color(hex: "#FFB300"))
            case .recent:
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.secondary)
            case .custom:
                Image(systemName: "mappin.and.ellipse")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(Color(hex: "#FFB300"))
            }
        }
    }
    
    // MARK: - Row & Directions Tap Handling
    
    private func handleItemRowTap(_ item: SearchResultItem) {
        viewModel.addRecentDestination(item)
        
        switch item.category {
        case .station(let stopId, _):
            // Spec: Tapping a station opens Screen 2 (Transit Reveal)
            onSelectStation?(stopId, item.coordinate)
        case .landmark, .custom, .recent:
            // Spec: Tapping a place/destination transitions to Screen 4B Route Comparison
            if let routingLoc = item.routingLocation {
                onSelectDestination?(routingLoc)
            }
        case .route:
            // For route, if coordinate exists navigate, else if stops exist open first
            if let routingLoc = item.routingLocation {
                onSelectDestination?(routingLoc)
            }
        }
    }
    
    private func handleItemDirectionsTap(_ item: SearchResultItem) {
        viewModel.addRecentDestination(item)
        
        if let routingLoc = item.routingLocation {
            onSelectDestination?(routingLoc)
        } else if case .station(let stopId, _) = item.category {
            if let num = UInt32(stopId) {
                onSelectDestination?(.stop(stopId: num, name: item.title))
            }
        }
    }
    
    // MARK: - Loading & No Results Views
    
    @ViewBuilder
    private var loadingView: some View {
        HStack(spacing: 8) {
            ProgressView()
                .scaleEffect(0.9)
            Text("Searching offline transit & places...")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 30)
    }
    
    @ViewBuilder
    private var noResultsView: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 28))
                .foregroundColor(.secondary.opacity(0.4))
            Text("No results found")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
            Text("Try searching for station names (e.g. \"Times Sq\"), subway lines (e.g. \"L\"), or landmarks.")
                .font(.system(size: 12.5, weight: .medium, design: .rounded))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .padding(.vertical, 36)
    }
}

#Preview {
    PlaceSearchView()
}
