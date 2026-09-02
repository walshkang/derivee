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
                .presentationDetents([.fraction(0.5), .fraction(0.9)])
                .presentationDragIndicator(.visible)
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
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                // Inspect Steps Button
                Button {
                    showingDetailSheet = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "list.bullet")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Steps")
                            .font(.system(size: 14.5, weight: .semibold, design: .rounded))
                    }
                    .foregroundColor(Color(hex: "#0F172A"))
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Color.primary.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .frame(width: 110)
                
                // Primary Action Button (Start Navigation)
                Button {
                    if let chosen = viewModel.selectedItinerary {
                        let generator = UIImpactFeedbackGenerator(style: .medium)
                        generator.prepare()
                        generator.impactOccurred()
                        onStartNavigation?(chosen)
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "location.fill")
                            .font(.system(size: 14, weight: .bold))
                        Text("Start Journey")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                    }
                    .foregroundColor(Color(hex: "#0F172A"))
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Color(hex: "#FFB300"))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .shadow(color: Color(hex: "#FFB300").opacity(0.4), radius: 8, x: 0, y: 3)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 16)
        .background(Color.white)
        .overlay(
            Divider(), alignment: .top
        )
    }
}
