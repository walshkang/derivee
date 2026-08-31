import SwiftUI
import CoreLocation

public struct AllMetrosSummaryView: View {
    public let summaryData: AllMetrosSummaryData
    public let onSelectCity: (String) -> Void
    public let onViewOnMap: (String, CLLocationCoordinate2D) -> Void
    public var packManager: CityPackManager = .shared
    public var cityDetectionService: CityDetectionService? = nil
    public var onCityInstalled: ((String) -> Void)? = nil
    
    @State private var downloadingSlugs: [String: CityDownloadState] = [:]
    @Environment(\.colorScheme) private var colorScheme
    
    public init(
        summaryData: AllMetrosSummaryData,
        onSelectCity: @escaping (String) -> Void,
        onViewOnMap: @escaping (String, CLLocationCoordinate2D) -> Void,
        packManager: CityPackManager = .shared,
        cityDetectionService: CityDetectionService? = nil,
        onCityInstalled: ((String) -> Void)? = nil
    ) {
        self.summaryData = summaryData
        self.onSelectCity = onSelectCity
        self.onViewOnMap = onViewOnMap
        self.packManager = packManager
        self.cityDetectionService = cityDetectionService
        self.onCityInstalled = onCityInstalled
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
                        downloadState: downloadingSlugs[city.slug] ?? .idle,
                        onViewStats: {
                            onSelectCity(city.slug)
                        },
                        onViewOnMap: {
                            onViewOnMap(city.slug, city.centerCoordinate)
                        },
                        onStartDownload: {
                            startDownload(for: city)
                        }
                    )
                    .padding(.vertical, 4)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollBounceBehavior(.basedOnSize)
    }
    
    private func startDownload(for city: CityOverviewProgress) {
        let manifest = cityDetectionService?.manifest ?? .defaultManifest
        let entry = manifest.findCity(bySlug: city.slug) ?? CityManifestEntry(
            slug: city.slug,
            displayName: city.displayName,
            region: city.region,
            compressedSizeBytes: city.compressedSizeBytes > 0 ? city.compressedSizeBytes : 9_400_000,
            uncompressedSizeBytes: city.compressedSizeBytes > 0 ? city.compressedSizeBytes * 2 : 22_000_000,
            isBundled: false,
            version: "1.0.0",
            bounds: city.bounds,
            center: CityCenter(latitude: city.centerCoordinate.latitude, longitude: city.centerCoordinate.longitude)
        )
        
        let initialTotal = entry.compressedSizeBytes > 0 ? entry.compressedSizeBytes : 9_400_000
        downloadingSlugs[city.slug] = .downloading(
            progress: 0.05,
            receivedBytes: Int64(Double(initialTotal) * 0.05),
            totalBytes: initialTotal
        )
        
        Task {
            do {
                _ = try await packManager.downloadAndInstallPack(for: entry) { progress, received, total in
                    Task { @MainActor in
                        self.downloadingSlugs[city.slug] = .downloading(
                            progress: progress,
                            receivedBytes: received,
                            totalBytes: total
                        )
                    }
                }
                
                await MainActor.run {
                    self.downloadingSlugs[city.slug] = .completed
                    let impact = UINotificationFeedbackGenerator()
                    impact.notificationOccurred(.success)
                    self.cityDetectionService?.markCityInstalled(city.slug)
                }
                
                try? await Task.sleep(nanoseconds: 600_000_000)
                
                await MainActor.run {
                    self.downloadingSlugs.removeValue(forKey: city.slug)
                    self.onCityInstalled?(city.slug)
                }
            } catch {
                print("⚠️ [AllMetrosSummaryView] Download/install failed for '\(city.slug)': \(error)")
                await MainActor.run {
                    self.downloadingSlugs[city.slug] = .failed(error: error.localizedDescription)
                }
            }
        }
    }
}

// MARK: - City Overview Card

public struct CityOverviewCard: View {
    public let city: CityOverviewProgress
    public var downloadState: CityDownloadState = .idle
    public let onViewStats: () -> Void
    public let onViewOnMap: () -> Void
    public var onStartDownload: (() -> Void)? = nil
    
    @Environment(\.colorScheme) private var colorScheme
    
    public init(
        city: CityOverviewProgress,
        downloadState: CityDownloadState = .idle,
        onViewStats: @escaping () -> Void,
        onViewOnMap: @escaping () -> Void,
        onStartDownload: (() -> Void)? = nil
    ) {
        self.city = city
        self.downloadState = downloadState
        self.onViewStats = onViewStats
        self.onViewOnMap = onViewOnMap
        self.onStartDownload = onStartDownload
    }
    
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
                        
                        if !city.isInstalled && downloadState != .completed {
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
            
            // Action Section: 1-Tap Download for uninstalled vs Actions for installed
            if !city.isInstalled && downloadState != .completed {
                uninstalledDownloadActionView
            } else {
                installedActionsView
            }
        }
        .padding(.vertical, 4)
    }
    
    @ViewBuilder
    private var installedActionsView: some View {
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
    
    @ViewBuilder
    private var uninstalledDownloadActionView: some View {
        switch downloadState {
        case .idle:
            Button(action: {
                onStartDownload?()
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.down.circle.fill")
                    Text("Download Pack")
                    if !city.formattedDownloadSize.isEmpty && city.formattedDownloadSize != "0 B" {
                        Text("(\(city.formattedDownloadSize))")
                            .font(.system(size: 11, design: .monospaced))
                            .opacity(0.85)
                    }
                }
                .font(.system(size: 13, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(Color(hex: "#FFB300"))
                .foregroundColor(.black)
                .cornerRadius(8)
                .shadow(color: Color(hex: "#FFB300").opacity(0.25), radius: 4, x: 0, y: 2)
            }
            .buttonStyle(.plain)
            
        case .downloading(let progress, let received, let total):
            VStack(spacing: 6) {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .tint(Color(hex: "#FFB300"))
                
                HStack {
                    Text("\(CityManifest.formatBytes(received)) of \(CityManifest.formatBytes(total))")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(Int(progress * 100))%")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.primary)
                }
            }
            .padding(.vertical, 2)
            
        case .extracting:
            HStack(spacing: 8) {
                ProgressView()
                    .scaleEffect(0.8)
                    .tint(Color(hex: "#FFB300"))
                Text("Installing city assets...")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            
        case .completed:
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text("Installed")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.green)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            
        case .failed(let error):
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Download Failed")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.red)
                    Text(error)
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Button("Retry") {
                    onStartDownload?()
                }
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(Color(hex: "#FFB300"))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.secondary.opacity(0.12))
                .cornerRadius(6)
            }
        }
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
