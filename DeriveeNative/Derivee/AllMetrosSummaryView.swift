import SwiftUI
import CoreLocation

public struct AllMetrosSummaryView: View {
    public let summaryData: AllMetrosSummaryData
    public let onSelectCity: (String) -> Void
    public let onViewOnMap: (String, CLLocationCoordinate2D) -> Void
    
    @Environment(\.colorScheme) private var colorScheme
    
    public init(
        summaryData: AllMetrosSummaryData,
        onSelectCity: @escaping (String) -> Void,
        onViewOnMap: @escaping (String, CLLocationCoordinate2D) -> Void
    ) {
        self.summaryData = summaryData
        self.onSelectCity = onSelectCity
        self.onViewOnMap = onViewOnMap
    }
    
    public var body: some View {
        List {
            // 1. Global Macro Metrics Header
            Section(header: Text("Global Lifetime Footprint")) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Total Hexes Unlocked")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Text("\(summaryData.totalGlobalClearedHexes)")
                                .font(.system(.title, design: .monospaced))
                                .bold()
                        }
                        
                        Spacer()
                        
                        VStack(alignment: .trailing, spacing: 4) {
                            Text("Drift Distance")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Text(summaryData.formattedDriftDistance)
                                .font(.system(.title2, design: .monospaced))
                                .bold()
                                .foregroundColor(Color(hex: "#FFB300"))
                        }
                    }
                    
                    ProgressView(value: summaryData.globalPercentage, total: 100)
                        .tint(Color(hex: "#FFB300"))
                    
                    HStack {
                        Text("Metros Explored")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(summaryData.citiesExploredCount) of \(summaryData.totalCitiesCount) Cities")
                            .font(.system(.caption, design: .monospaced))
                            .bold()
                    }
                }
                .padding(.vertical, 8)
            }
            
            // 2. Per-City Overview Cards Section
            Section(header: Text("Metropolitan Breakdown")) {
                ForEach(summaryData.cityOverviews) { city in
                    CityOverviewCard(
                        city: city,
                        onViewStats: {
                            onSelectCity(city.slug)
                        },
                        onViewOnMap: {
                            onViewOnMap(city.slug, city.centerCoordinate)
                        }
                    )
                    .padding(.vertical, 4)
                }
            }
        }
        .listStyle(.insetGrouped)
    }
}

// MARK: - City Overview Card

public struct CityOverviewCard: View {
    public let city: CityOverviewProgress
    public let onViewStats: () -> Void
    public let onViewOnMap: () -> Void
    
    @Environment(\.colorScheme) private var colorScheme
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                // Circular Progress Ring
                CircularProgressRing(
                    progress: city.percentage,
                    lineWidth: 4.5,
                    ringColor: Color(hex: "#FFB300"),
                    showPercentageText: false
                )
                .frame(width: 42, height: 42)
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(city.displayName)
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        if !city.isInstalled {
                            Text("Available")
                                .font(.system(size: 10, weight: .bold))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.15))
                                .foregroundColor(.secondary)
                                .cornerRadius(4)
                        }
                    }
                    
                    Text(city.region)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    Text(city.formattedPercentage)
                        .font(.system(.subheadline, design: .monospaced))
                        .fontWeight(.bold)
                        .foregroundColor(city.clearedHexes > 0 ? Color(hex: "#FFB300") : .primary)
                    
                    Text("\(city.clearedHexes) / \(city.totalHexes)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }
            
            // Action Buttons Strip
            HStack(spacing: 10) {
                Button(action: onViewStats) {
                    HStack(spacing: 4) {
                        Image(systemName: "chart.bar.xaxis")
                        Text("View Stats")
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(Color.secondary.opacity(0.12))
                    .foregroundColor(.primary)
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
                
                Button(action: onViewOnMap) {
                    HStack(spacing: 4) {
                        Image(systemName: "map")
                        Text("View on Map")
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(Color(hex: "#FFB300").opacity(0.18))
                    .foregroundColor(Color(hex: "#D97706"))
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    NavigationStack {
        AllMetrosSummaryView(
            summaryData: AllMetrosSummaryData(
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
                        centerCoordinate: CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060)
                    ),
                    CityOverviewProgress(
                        slug: "bos",
                        displayName: "Boston",
                        region: "Massachusetts, USA",
                        clearedHexes: 140,
                        totalHexes: 115000,
                        isInstalled: true,
                        centerCoordinate: CLLocationCoordinate2D(latitude: 42.3601, longitude: -71.0589)
                    ),
                    CityOverviewProgress(
                        slug: "chi",
                        displayName: "Chicago",
                        region: "Illinois, USA",
                        clearedHexes: 0,
                        totalHexes: 220000,
                        isInstalled: false,
                        centerCoordinate: CLLocationCoordinate2D(latitude: 41.8781, longitude: -87.6298)
                    )
                ]
            ),
            onSelectCity: { _ in },
            onViewOnMap: { _, _ in }
        )
        .navigationTitle("All Metros")
    }
}
