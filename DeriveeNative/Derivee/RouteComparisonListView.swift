import SwiftUI

/// Main container view assembling the multi-profile selector bar, predictive comparison cards,
/// active selection highlighting, step drilldowns, and ergonomic thumb-zone action buttons.
public struct RouteComparisonListView: View {
    @State public var viewModel: RouteComparisonViewModel
    @State private var showingDetailSheet: Bool = false
    public var onStartNavigation: ((JourneyItinerary) -> Void)?
    public var onClose: (() -> Void)?
    
    public init(
        viewModel: RouteComparisonViewModel? = nil,
        onStartNavigation: ((JourneyItinerary) -> Void)? = nil,
        onClose: (() -> Void)? = nil
    ) {
        self._viewModel = State(initialValue: viewModel ?? RouteComparisonViewModel())
        self.onStartNavigation = onStartNavigation
        self.onClose = onClose
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // MARK: - Header Bar
            headerBar
            
            Divider()
            
            // MARK: - Multi-Profile Selector Bar
            MultiProfileSelectorBar(
                selectedProfile: $viewModel.selectedProfile
            )
            .background(Color(hex: "#F9F9F6"))
            
            // MARK: - Scrollable Candidate Cards List
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(viewModel.filteredJourneys) { itinerary in
                        RouteComparisonCardView(
                            itinerary: itinerary,
                            isSelected: viewModel.selectedItineraryId == itinerary.id,
                            onSelect: {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    viewModel.selectItinerary(id: itinerary.id)
                                }
                            }
                        )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(Color(hex: "#F9F9F6"))
            
            // MARK: - Lower Third Thumb-Zone Action Button
            bottomActionBar
        }
        .sheet(isPresented: $showingDetailSheet) {
            if let activeItinerary = viewModel.selectedItinerary {
                RouteLegDetailView(itinerary: activeItinerary) {
                    showingDetailSheet = false
                }
                .standardNavigationDetents(interactiveUpThrough: NavigationSheetDetent.half.presentationDetent)
            }
        }
    }
    
    // MARK: - Header Bar
    
    @ViewBuilder
    private var headerBar: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(viewModel.originName)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(Color(hex: "#0F172A"))
                    
                    Image(systemName: "arrow.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.secondary)
                    
                    Text(viewModel.destinationName)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(Color(hex: "#0F172A"))
                }
                
                Text("\(viewModel.filteredJourneys.count) options found • \(viewModel.selectedProfile.displayName)")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if let onClose = onClose {
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(Color.secondary.opacity(0.5))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(Color.white)
    }
    
    // MARK: - Bottom Action Bar (Thumb Zone)
    
    @ViewBuilder
    private var bottomActionBar: some View {
        ThumbZoneActionBar(
            primary: .startJourney(action: {
                if let chosen = viewModel.selectedItinerary {
                    onStartNavigation?(chosen)
                }
            }),
            secondary: .steps {
                showingDetailSheet = true
            }
        )
    }
}
