import SwiftUI

public struct CitiesStorageManagerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    // Injectable dependencies
    public var packManager: CityPackManager
    var spatialDatabaseManager: SpatialDatabaseManager
    public var cityDetectionService: CityDetectionService? = nil
    
    @State private var installedPacks: [InstalledCityPack] = []
    @State private var remoteManifest: CityManifest = CityManifest.defaultManifest
    @State private var expandedSlugs: Set<String> = []
    
    // Deletion states
    @State private var packPendingDeletion: InstalledCityPack? = nil
    @State private var showDeleteConfirmation = false
    
    // Exploration reset states
    @State private var cityPendingReset: InstalledCityPack? = nil
    @State private var showResetFirstConfirmation = false
    @State private var showResetFinalConfirmation = false
    
    // Download states: slug -> state
    @State private var downloadingSlugs: [String: CityDownloadState] = [:]
    
    public init(
        packManager: CityPackManager = .shared,
        spatialDatabaseManager: SpatialDatabaseManager = .shared,
        cityDetectionService: CityDetectionService? = nil
    ) {
        self.packManager = packManager
        self.spatialDatabaseManager = spatialDatabaseManager
        self.cityDetectionService = cityDetectionService
    }
    
    init(
        packManager: CityPackManager,
        spatialDatabaseManager: SpatialDatabaseManager
    ) {
        self.packManager = packManager
        self.spatialDatabaseManager = spatialDatabaseManager
        self.cityDetectionService = nil
    }
    
    private var totalStorageBytes: Int64 {
        installedPacks.reduce(0) { $0 + $1.totalDiskSizeBytes }
    }
    
    private var uninstalledCatalogCities: [CityManifestEntry] {
        let installedSlugs = Set(installedPacks.map { $0.slug })
        return remoteManifest.cities.filter { !installedSlugs.contains($0.slug) }
    }
    
    public var body: some View {
        List {
            // MARK: - Storage Overview Section
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Total Pack Footprint")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            
                            Text(CityManifest.formatBytes(totalStorageBytes))
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                                .foregroundColor(.primary)
                        }
                        
                        Spacer()
                        
                        ZStack {
                            Circle()
                                .fill(Color(hex: "#FFB300").opacity(0.15))
                                .frame(width: 50, height: 50)
                            
                            Image(systemName: "internaldrive.fill")
                                .font(.system(size: 24))
                                .foregroundColor(Color(hex: "#FFB300"))
                        }
                    }
                    
                    HStack(spacing: 16) {
                        Label("\(installedPacks.count) Installed", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Label("\(uninstalledCatalogCities.count) Available on R2", systemImage: "icloud.and.arrow.down.fill")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
            
            // MARK: - Installed Cities Section
            Section(
                header: Text("Installed Cities (\(installedPacks.count))"),
                footer: Text("Deleting a pack frees static schedule and vector storage while permanently preserving your personal exploration history in Dérivée.")
            ) {
                if installedPacks.isEmpty {
                    Text("No city packs installed.")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(installedPacks) { pack in
                        installedCityRow(for: pack)
                    }
                }
            }
            
            // MARK: - Available Cities Catalog Section
            if !uninstalledCatalogCities.isEmpty {
                Section(header: Text("Available Cities (Cloud Catalog)")) {
                    ForEach(uninstalledCatalogCities) { entry in
                        availableCityRow(for: entry)
                    }
                }
            }
            
            // MARK: - Attributions Link
            Section(header: Text("Attributions & Legal")) {
                NavigationLink(destination: TransitAttributionsView()) {
                    HStack {
                        Image(systemName: "doc.text.magnifyingglass")
                            .foregroundColor(Color(hex: "#FFB300"))
                        Text("Open Data Sources & Attributions")
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollBounceBehavior(.basedOnSize)
        .navigationTitle("Cities & Storage")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            loadData()
        }
        // Delete Confirmation Alert
        .alert("Delete City Pack?", isPresented: $showDeleteConfirmation, presenting: packPendingDeletion) { pack in
            Button("Cancel", role: .cancel) { }
            Button("Delete Pack", role: .destructive) {
                deleteCityPack(pack)
            }
        } message: { pack in
            Text("This will remove static transit schedules and line geometries for \(pack.config.displayName) (\(pack.breakdown.formattedTotal)). Your personal explored hexes and journal stats will remain permanently saved.")
        }
        // Exploration Reset Step 1 Alert
        .alert("Reset Exploration Data?", isPresented: $showResetFirstConfirmation, presenting: cityPendingReset) { city in
            Button("Cancel", role: .cancel) { }
            Button("Continue...", role: .destructive) {
                showResetFinalConfirmation = true
            }
        } message: { city in
            Text("Are you sure you want to delete all cleared fog, unlocked hexes, and discovered transit stops for \(city.config.displayName)? This cannot be undone.")
        }
        // Exploration Reset Step 2 Double-Confirmation Alert
        .alert("Permanently Erase Exploration?", isPresented: $showResetFinalConfirmation, presenting: cityPendingReset) { city in
            Button("Keep Exploration", role: .cancel) { }
            Button("Permanently Erase", role: .destructive) {
                resetExplorationData(for: city)
            }
        } message: { city in
            Text("Final Confirmation: All exploration progress for \(city.config.displayName) will be permanently erased and returned to complete fog.")
        }
    }
    
    // MARK: - Installed City Row
    
    @ViewBuilder
    private func installedCityRow(for pack: InstalledCityPack) -> some View {
        let isExpanded = expandedSlugs.contains(pack.slug)
        let hasUpdate = packManager.isUpdateAvailable(for: pack.slug, manifest: remoteManifest)
        let manifestEntry = remoteManifest.findCity(bySlug: pack.slug)
        let activeSlug = cityDetectionService?.activeCitySlug ?? "nyc"
        let isActiveMetro = (pack.slug == activeSlug)
        
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(pack.config.displayName)
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        if isActiveMetro {
                            HStack(spacing: 3) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 9))
                                Text("Active")
                                    .font(.system(size: 10, weight: .bold))
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color(hex: "#FFB300").opacity(0.18))
                            .clipShape(Capsule())
                            .foregroundColor(Color(hex: "#D97706"))
                        }
                        
                        if pack.isBundled {
                            HStack(spacing: 3) {
                                Image(systemName: "lock.fill")
                                    .font(.system(size: 9))
                                Text("Core Metro")
                                    .font(.system(size: 10, weight: .bold))
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color(.systemGray5))
                            .clipShape(Capsule())
                            .foregroundColor(.secondary)
                        }
                    }
                    
                    Text("\(pack.config.region) • v\(pack.config.version).0")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text(pack.breakdown.formattedTotal)
                        .font(.system(.subheadline, design: .monospaced))
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    
                    if hasUpdate {
                        Text("Update Available")
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color(hex: "#FFB300").opacity(0.2))
                            .foregroundColor(Color(hex: "#FFB300"))
                            .clipShape(Capsule())
                    }
                }
            }
            
            // Expandable breakdown toggle
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    if isExpanded {
                        expandedSlugs.remove(pack.slug)
                    } else {
                        expandedSlugs.insert(pack.slug)
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(isExpanded ? "Hide Details" : "Storage Breakdown")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(Color(hex: "#FFB300"))
                    
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(Color(hex: "#FFB300"))
                }
            }
            .buttonStyle(.plain)
            
            // Detailed Component Breakdown in SF Mono
            if isExpanded {
                VStack(spacing: 6) {
                    Divider()
                    
                    breakdownRow(title: "transit.sqlite (GTFS Timetable DB)", size: pack.breakdown.formattedTransitDB)
                    if pack.breakdown.neighborhoodDatabaseBytes > 0 {
                        breakdownRow(title: "neighborhood.sqlite (GIS Walkable Boundaries)", size: pack.breakdown.formattedNeighborhoodDB)
                    }
                    breakdownRow(title: "transit-lines.geojson (Route Lines)", size: pack.breakdown.formattedTransitLines)
                    if pack.breakdown.timetableBytes > 0 {
                        breakdownRow(title: "timetable.bin (RAPTOR Timetable)", size: pack.breakdown.formattedTimetable)
                    }
                    if pack.breakdown.ultraTransfersBytes > 0 {
                        breakdownRow(title: "ultra_transfers.csr (ULTRA Shortcuts)", size: pack.breakdown.formattedUltraTransfers)
                    }
                    if pack.breakdown.walkGraphBytes > 0 {
                        breakdownRow(title: "walk_graph.bin (OSM Walk Graph)", size: pack.breakdown.formattedWalkGraph)
                    }
                    breakdownRow(title: "city_config.json (Metro Bounds)", size: pack.breakdown.formattedConfig)
                    if pack.breakdown.otherBytes > 0 {
                        breakdownRow(title: "auxiliary / indexes", size: pack.breakdown.formattedOther)
                    }
                }
                .padding(.top, 2)
            }
            
            // Action Buttons: Switch Active Metro / Update / Delete / Reset
            HStack(spacing: 12) {
                if !isActiveMetro {
                    Button {
                        switchToActiveMetro(pack)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.triangle.swap")
                            Text("Switch Active Metro")
                        }
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.secondary.opacity(0.12))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                
                if hasUpdate, let entry = manifestEntry {
                    Button {
                        startUpdate(for: entry)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                            Text("Update to v\(entry.version)")
                        }
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.black)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color(hex: "#FFB300"))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                
                if !pack.isBundled {
                    Button {
                        packPendingDeletion = pack
                        showDeleteConfirmation = true
                    } label: {
                        Text("Delete Pack")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.plain)
                }
                
                Spacer()
                
                Menu {
                    Button(role: .destructive) {
                        cityPendingReset = pack
                        showResetFirstConfirmation = true
                    } label: {
                        Label("Reset Exploration Data...", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.top, 4)
        }
        .padding(.vertical, 6)
    }
    
    private func breakdownRow(title: String, size: String) -> some View {
        HStack {
            Text(title)
                .font(.system(.caption2, design: .monospaced))
                .foregroundColor(.secondary)
                .lineLimit(1)
            Spacer()
            Text(size)
                .font(.system(.caption2, design: .monospaced))
                .fontWeight(.medium)
                .foregroundColor(.primary)
        }
    }
    
    // MARK: - Available City Catalog Row
    
    @ViewBuilder
    private func availableCityRow(for entry: CityManifestEntry) -> some View {
        let downloadState = downloadingSlugs[entry.slug] ?? .idle
        
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.displayName)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text("\(entry.region) • v\(entry.version)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                switch downloadState {
                case .idle:
                    Button {
                        startDownload(for: entry)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.down.circle.fill")
                            Text("Download")
                            Text("(\(entry.formattedDownloadSize))")
                                .font(.system(size: 11, design: .monospaced))
                                .opacity(0.8)
                        }
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.black)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color(hex: "#FFB300"))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    
                case .downloading(let progress, _, _):
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                        .tint(Color(hex: "#FFB300"))
                        .frame(width: 120)
                    
                case .extracting:
                    HStack(spacing: 6) {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Installing...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                case .completed:
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Installed")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                    
                case .failed(let error):
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Failed")
                            .font(.caption)
                            .foregroundColor(.red)
                        Button("Retry") {
                            startDownload(for: entry)
                        }
                        .font(.caption2)
                        .foregroundColor(Color(hex: "#FFB300"))
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
    
    // MARK: - Actions
    
    private func loadData() {
        installedPacks = packManager.installedCityPacks()
        Task {
            if let manifest = try? await packManager.fetchRemoteManifest() {
                await MainActor.run {
                    self.remoteManifest = manifest
                }
            }
        }
    }
    
    private func switchToActiveMetro(_ pack: InstalledCityPack) {
        let manifestEntry = remoteManifest.findCity(bySlug: pack.slug) ?? CityManifestEntry(
            slug: pack.slug,
            displayName: pack.config.displayName,
            region: pack.config.region,
            compressedSizeBytes: 0,
            uncompressedSizeBytes: pack.totalDiskSizeBytes,
            isBundled: pack.isBundled,
            version: "\(pack.config.version).0.0",
            bounds: pack.config.bounds,
            center: pack.config.center
        )
        
        let impact = UIImpactFeedbackGenerator(style: .medium)
        impact.impactOccurred()
        
        if let service = cityDetectionService {
            service.performAutoSwitch(to: manifestEntry)
        } else {
            Task {
                try? await spatialDatabaseManager.hotSwapTransitDatabase(to: pack.transitDatabaseURL)
            }
        }
        loadData()
    }
    
    private func deleteCityPack(_ pack: InstalledCityPack) {
        do {
            try packManager.deletePack(slug: pack.slug)
            cityDetectionService?.markCityUninstalled(pack.slug)
            let impact = UINotificationFeedbackGenerator()
            impact.notificationOccurred(.success)
            loadData()
        } catch {
            print("Failed to delete pack: \(error)")
        }
    }
    
    private func resetExplorationData(for pack: InstalledCityPack) {
        Task {
            do {
                try await spatialDatabaseManager.resetExplorationData(citySlug: pack.slug)
                await MainActor.run {
                    let impact = UINotificationFeedbackGenerator()
                    impact.notificationOccurred(.success)
                }
            } catch {
                print("Failed to reset exploration: \(error)")
            }
        }
    }
    
    private func startDownload(for entry: CityManifestEntry) {
        downloadingSlugs[entry.slug] = .downloading(progress: 0.05, receivedBytes: 0, totalBytes: entry.compressedSizeBytes)
        
        Task {
            do {
                _ = try await packManager.downloadAndInstallPack(for: entry) { progress, received, total in
                    Task { @MainActor in
                        self.downloadingSlugs[entry.slug] = .downloading(
                            progress: progress,
                            receivedBytes: received,
                            totalBytes: total
                        )
                    }
                }
                
                await MainActor.run {
                    self.downloadingSlugs[entry.slug] = .completed
                    let impact = UINotificationFeedbackGenerator()
                    impact.notificationOccurred(.success)
                    self.cityDetectionService?.markCityInstalled(entry.slug)
                    self.loadData()
                }
            } catch {
                print("⚠️ [CitiesStorageManagerView] Download/install failed for '\(entry.slug)': \(error)")
                await MainActor.run {
                    self.downloadingSlugs[entry.slug] = .idle
                    self.loadData()
                }
            }
        }
    }
    
    private func startUpdate(for entry: CityManifestEntry) {
        startDownload(for: entry)
    }
}

#Preview {
    NavigationStack {
        CitiesStorageManagerView()
    }
}
