import SwiftUI
import CoreLocation
import UniformTypeIdentifiers

enum StatsTab: String, CaseIterable, Identifiable {
    case neighborhoods = "Neighborhoods"
    case journal = "Journal & Milestones"
    
    var id: String { rawValue }
}

struct StatsView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    
    @ObservedObject var trackingEngine: AmbientTrackingEngine
    var spatialStore: SpatialStore
    var cityDetectionService: CityDetectionService? = nil
    var onSwitchCity: ((String, CLLocationCoordinate2D?) -> Void)? = nil
    
    @Binding var targetCoordinate: CLLocationCoordinate2D?
    
    @State private var browsingMode: StatsBrowsingMode = .city(slug: "nyc")
    @State private var selectedTab: StatsTab = .neighborhoods
    @State private var neighborhoods: [SpatialDatabaseManager.NeighborhoodProgress] = []
    @State private var journalData: ExplorationJournalData? = nil
    @State private var allMetrosSummary: AllMetrosSummaryData? = nil
    
    @State private var isImporting = false
    @State private var importProgress: Double = 0.0
    @State private var importSummaryAlertMessage: String? = nil
    @State private var showImportAlert = false
    @State private var showSettings = false
    @State private var showFileImporter = false
    @State private var isLoading = true
    
    private var availableManifestCities: [CityManifestEntry] {
        if let manifest = cityDetectionService?.manifest {
            let installed = cityDetectionService?.installedCitySlugs ?? ["nyc"]
            return manifest.cities.filter { installed.contains($0.slug) || $0.isBundled }
        }
        return CityManifest.defaultManifest.cities
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Top City Selector Menu Pill
                HStack {
                    Spacer()
                    CitySelectorPill(
                        browsingMode: browsingMode,
                        installedPacks: availableManifestCities,
                        userLocation: trackingEngine.lastKnownLocation?.coordinate,
                        onSelectMode: { newMode in
                            browsingMode = newMode
                            Task {
                                await loadAllData()
                            }
                        },
                        onOpenSettings: {
                            showSettings = true
                        }
                    )
                    Spacer()
                }
                .padding(.top, 8)
                .padding(.bottom, 10)
                .background(Color(UIColor.systemGroupedBackground))
                
                if browsingMode.isAllMetros {
                    // Global All Metros Summary View
                    if let summary = allMetrosSummary {
                        AllMetrosSummaryView(
                            summaryData: summary,
                            onSelectCity: { slug in
                                browsingMode = .city(slug: slug)
                                Task {
                                    await loadAllData()
                                }
                            },
                            onViewOnMap: { slug, coord in
                                handleViewOnMap(slug: slug, coordinate: coord)
                            }
                        )
                    } else {
                        loadingView
                    }
                } else {
                    // Single City Mode: Segmented Tabs (Neighborhoods vs Journal)
                    Picker("Section", selection: $selectedTab) {
                        ForEach(StatsTab.allCases) { tab in
                            Text(tab.rawValue).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(Color(UIColor.systemGroupedBackground))
                    
                    if selectedTab == .neighborhoods {
                        neighborhoodsContent
                    } else {
                        journalContent
                    }
                }
                
                // Bottom GPX Import Action Bar (Always visible in single city and All Metros modes)
                VStack(spacing: 16) {
                    if isImporting {
                        VStack(spacing: 8) {
                            Text("Processing Multi-City GPX...")
                                .font(.caption)
                            ProgressView(value: importProgress)
                                .tint(Color(hex: "#FFB300"))
                        }
                        .padding(.horizontal, 40)
                    } else {
                        Button(action: {
                            showFileImporter = true
                        }) {
                            HStack {
                                Image(systemName: "square.and.arrow.down")
                                Text("Upload Previous Workouts")
                            }
                            .font(.headline)
                            .foregroundColor(colorScheme == .dark ? .black : .white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(colorScheme == .dark ? Color.white : Color.black)
                            .cornerRadius(12)
                        }
                    }
                }
                .padding()
                .background(Color(UIColor.systemGroupedBackground))
            }
            .navigationTitle("Exploration Stats")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gear")
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                NavigationStack {
                    SettingsView(trackingEngine: trackingEngine, spatialStore: spatialStore, onDismissToMap: {
                        showSettings = false
                        dismiss()
                    })
                }
            }
            .task {
                if let activeSlug = cityDetectionService?.activeCitySlug {
                    browsingMode = .city(slug: activeSlug)
                }
                await loadAllData()
            }
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: [
                    UTType.xml,
                    UTType(filenameExtension: "gpx") ?? .xml,
                    UTType(filenameExtension: "fit") ?? .data
                ],
                allowsMultipleSelection: false
            ) { result in
                do {
                    guard let selectedFile = try result.get().first else { return }
                    let isSecurityScoped = selectedFile.startAccessingSecurityScopedResource()
                    importGPX(from: selectedFile, isSecurityScoped: isSecurityScoped)
                } catch {
                    print("Error selecting file: \(error)")
                }
            }
            .alert("GPX Workout Import", isPresented: $showImportAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(importSummaryAlertMessage ?? "GPX import completed.")
            }
        }
    }
    
    // MARK: - Neighborhoods Tab Content
    
    @ViewBuilder
    private var neighborhoodsContent: some View {
        if neighborhoods.isEmpty && !isLoading {
            emptyStateView
        } else {
            List {
                let totalCleared = neighborhoods.reduce(0) { $0 + $1.clearedHexes }
                let totalOverall = neighborhoods.reduce(0) { $0 + $1.totalHexes }
                let overallPercentage = totalOverall > 0 ? (Double(totalCleared) / Double(totalOverall)) * 100.0 : 0.0
                let formattedPercentage: String = {
                    if overallPercentage == 0.0 {
                        return "0.0%"
                    } else if overallPercentage < 0.01 {
                        return "< 0.01%"
                    } else if overallPercentage < 0.1 {
                        return String(format: "%.2f%%", overallPercentage)
                    } else {
                        return String(format: "%.1f%%", overallPercentage)
                    }
                }()
                
                Section(header: Text("Macro Metrics")) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("City Explored")
                                .font(.headline)
                            Spacer()
                            Text(formattedPercentage)
                                .font(.system(.headline, design: .monospaced))
                                .bold()
                        }
                        ProgressView(value: overallPercentage, total: 100)
                            .tint(colorScheme == .dark ? .white : .black)
                        
                        HStack {
                            Text("Total Hexes Unlocked")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("\(totalCleared)")
                                .font(.system(.subheadline, design: .monospaced))
                                .foregroundColor(.primary)
                                .bold()
                        }
                    }
                    .padding(.vertical, 8)
                }
                
                Section(header: Text("Neighborhood Progression")) {
                    ForEach(neighborhoods) { nbhd in
                        Button(action: {
                            let currentSlug = browsingMode.slug ?? "nyc"
                            handleViewOnMap(
                                slug: currentSlug,
                                coordinate: CLLocationCoordinate2D(latitude: nbhd.centroidLat, longitude: nbhd.centroidLng)
                            )
                        }) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(nbhd.name)
                                        .font(.headline)
                                    
                                    ProgressView(value: nbhd.percentage, total: 100)
                                        .tint(colorScheme == .dark ? .white : .black)
                                }
                                
                                Spacer()
                                
                                VStack(alignment: .trailing) {
                                    let formattedNbhdPct: String = {
                                        if nbhd.percentage == 0.0 {
                                            return "0.0%"
                                        } else if nbhd.percentage < 0.1 {
                                            return String(format: "%.2f%%", nbhd.percentage)
                                        } else {
                                            return String(format: "%.1f%%", nbhd.percentage)
                                        }
                                    }()
                                    Text(formattedNbhdPct)
                                        .font(.system(.subheadline, design: .monospaced))
                                        .fontWeight(.bold)
                                    
                                    Text("\(nbhd.clearedHexes) / \(nbhd.totalHexes)")
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, 4)
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
    }
    
    // MARK: - Exploration Journal Content
    
    @ViewBuilder
    private var journalContent: some View {
        if let data = journalData {
            List {
                // Macro Badges Summary
                let totalTiers = data.milestoneCards.reduce(0) { $0 + $1.tiers.count }
                let unlockedTiers = data.milestoneCards.reduce(0) { $0 + $1.unlockedTierCount }
                
                Section(header: Text("Exploration Summary")) {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Milestones Unlocked")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                Text("\(unlockedTiers) / \(totalTiers)")
                                    .font(.system(.title2, design: .monospaced))
                                    .bold()
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 4) {
                                Text("City Footprint")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                Text("\(String(format: "%.2f", data.cityPercentage))%")
                                    .font(.system(.title2, design: .monospaced))
                                    .bold()
                                    .foregroundColor(Color(hex: "#FFB300"))
                            }
                        }
                        
                        ProgressView(value: Double(unlockedTiers), total: Double(max(1, totalTiers)))
                            .tint(Color(hex: "#FFB300"))
                    }
                    .padding(.vertical, 6)
                }
                
                // Milestone Progress Cards
                Section(header: Text("Milestone Categories")) {
                    ForEach(data.milestoneCards) { card in
                        VStack(alignment: .leading, spacing: 14) {
                            HStack(spacing: 12) {
                                ApertureMilestoneFrame(category: card.category, isUnlocked: card.unlockedTierCount > 0, size: 38)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(card.category.title)
                                        .font(.headline)
                                    Text(card.category.description)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                
                                Text("\(card.currentCount) / \(card.totalCount)")
                                    .font(.system(.subheadline, design: .monospaced))
                                    .bold()
                            }
                            
                            ProgressView(value: card.percentage, total: 100)
                                .tint(colorScheme == .dark ? .white : .black)
                            
                            // Tiers High-Negative-Space List
                            VStack(spacing: 10) {
                                ForEach(card.tiers) { tier in
                                    HStack(spacing: 12) {
                                        ZStack {
                                            ApertureShape()
                                                .stroke(tier.isUnlocked ? Color(hex: "#FFB300") : Color.secondary.opacity(0.3), lineWidth: 1.2)
                                                .background(
                                                    ApertureShape().fill(tier.isUnlocked ? Color(hex: "#FFB300").opacity(0.15) : Color.gray.opacity(0.08))
                                                )
                                                .frame(width: 28, height: 28)
                                            
                                            if tier.isUnlocked {
                                                Circle()
                                                    .fill(Color(hex: "#FFB300"))
                                                    .frame(width: 6, height: 6)
                                            } else {
                                                Text("\(tier.tierNumber)")
                                                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                                                    .foregroundColor(.secondary)
                                            }
                                        }
                                        
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("Tier \(tier.tierNumber): \(tier.title)")
                                                .font(.subheadline)
                                                .fontWeight(tier.isUnlocked ? .semibold : .regular)
                                                .foregroundColor(tier.isUnlocked ? .primary : .secondary)
                                            Text(tier.requirementDescription)
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                        }
                                        
                                        Spacer()
                                        
                                        if tier.isUnlocked {
                                            HStack(spacing: 4) {
                                                Circle()
                                                    .fill(Color(hex: "#FFB300"))
                                                    .frame(width: 6, height: 6)
                                                Text("COMPLETED")
                                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                                    .foregroundColor(Color(hex: "#FFB300"))
                                            }
                                        } else {
                                            Text("\(tier.targetCount)")
                                                .font(.system(.caption2, design: .monospaced))
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    .padding(.vertical, 2)
                                }
                            }
                            .padding(.top, 4)
                        }
                        .padding(.vertical, 8)
                    }
                }
                
                // NYC Borough Breakdown (if borough progress exists)
                if !data.boroughProgress.isEmpty {
                    Section(header: Text("Regional Footprint")) {
                        ForEach(data.boroughProgress) { b in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(b.name)
                                        .font(.headline)
                                    Spacer()
                                    Text("\(String(format: "%.1f", b.percentage))%")
                                        .font(.system(.subheadline, design: .monospaced))
                                        .bold()
                                }
                                ProgressView(value: b.percentage, total: 100)
                                    .tint(colorScheme == .dark ? .white : .black)
                                
                                HStack {
                                    Text("\(b.exploredNeighborhoodCount) / \(b.neighborhoodCount) Districts")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    Text("\(b.clearedHexes) / \(b.totalHexes) hexes")
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
                
                // Historic Landmarks Catalog
                if !data.landmarks.isEmpty {
                    Section(header: Text("Historic Landmarks (\(data.landmarks.filter { $0.isDiscovered }.count)/\(data.landmarks.count))")) {
                        ForEach(data.landmarks) { lm in
                            HStack(spacing: 12) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(lm.isDiscovered ? Color(hex: "#FFB300").opacity(0.2) : Color.gray.opacity(0.15))
                                        .frame(width: 36, height: 36)
                                    Image(systemName: lm.isDiscovered ? "building.columns.fill" : "lock.fill")
                                        .font(.system(size: 16))
                                        .foregroundColor(lm.isDiscovered ? Color(hex: "#FFB300") : .secondary)
                                }
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack {
                                        Text(lm.name)
                                            .font(.subheadline)
                                            .fontWeight(lm.isDiscovered ? .semibold : .regular)
                                            .foregroundColor(lm.isDiscovered ? .primary : .secondary)
                                        Spacer()
                                        Text(lm.borough)
                                            .font(.caption2)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.secondary.opacity(0.15))
                                            .cornerRadius(4)
                                    }
                                    Text(lm.landmarkDescription)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                        .lineLimit(2)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
        } else {
            loadingView
        }
    }
    
    private var loadingView: some View {
        VStack {
            ProgressView()
                .tint(Color(hex: "#FFB300"))
                .padding()
            Text("Loading Exploration Stats...")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "map.fill")
                .resizable()
                .frame(width: 60, height: 60)
                .foregroundColor(.gray.opacity(0.5))
            
            Text("No Exploration Data")
                .font(.title3)
                .foregroundColor(.secondary)
            
            Text("Walk around to discover neighborhoods and clear the fog.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxHeight: .infinity)
    }
    
    // MARK: - Actions & Handlers
    
    private func handleViewOnMap(slug: String, coordinate: CLLocationCoordinate2D) {
        targetCoordinate = coordinate
        if let cityService = cityDetectionService, cityService.activeCitySlug != slug {
            if let entry = cityService.manifest.findCity(bySlug: slug) {
                cityService.performAutoSwitch(to: entry)
            } else {
                cityService.activeCitySlug = slug
            }
        }
        onSwitchCity?(slug, coordinate)
        dismiss()
    }
    
    // MARK: - Data Loading
    
    private func loadAllData() async {
        isLoading = true
        let currentSlug = browsingMode.slug ?? "nyc"
        let manifest = cityDetectionService?.manifest ?? .defaultManifest
        let installedSlugs = cityDetectionService?.installedCitySlugs ?? ["nyc"]
        
        do {
            async let nbhdStats = SpatialDatabaseManager.shared.fetchNeighborhoodProgression(citySlug: currentSlug)
            async let jData = SpatialDatabaseManager.shared.fetchExplorationJournalData(citySlug: currentSlug)
            async let summaryData = SpatialDatabaseManager.shared.fetchAllMetrosSummary(installedSlugs: installedSlugs, manifest: manifest)
            
            let (fetchedNbhds, fetchedJournal, fetchedSummary) = try await (nbhdStats, jData, summaryData)
            
            await MainActor.run {
                self.neighborhoods = fetchedNbhds
                self.journalData = fetchedJournal
                self.allMetrosSummary = fetchedSummary
                self.isLoading = false
            }
        } catch {
            print("Error loading stats data: \(error)")
            await MainActor.run {
                self.isLoading = false
            }
        }
    }
    
    private func importGPX(from url: URL, isSecurityScoped: Bool = false) {
        isImporting = true
        importProgress = 0.0
        
        Task.detached(priority: .userInitiated) {
            defer {
                if isSecurityScoped {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            do {
                let parser = GPXParser()
                let coordinates = try parser.parse(url: url)
                
                let processor = GPXProcessor()
                let currentLoc = await MainActor.run { trackingEngine.lastKnownLocation?.coordinate }
                let activeSlug = await MainActor.run { cityDetectionService?.activeCitySlug ?? "nyc" }
                let manifest = await MainActor.run { cityDetectionService?.manifest ?? .defaultManifest }
                
                processor.processAndInsertMultiCity(
                    coordinates: coordinates,
                    manifest: manifest,
                    defaultCitySlug: activeSlug,
                    userLocation: currentLoc,
                    onProgress: { progress in
                        Task { @MainActor in
                            self.importProgress = progress
                        }
                    },
                    onComplete: { result in
                        Task { @MainActor in
                            self.isImporting = false
                            if result.totalHexesImported > 0 {
                                let cityBreakdown = result.cityHexCounts.map { "\($0.key.uppercased()): \($0.value)" }.joined(separator: ", ")
                                self.importSummaryAlertMessage = "Successfully imported \(result.totalHexesImported) hexes across \(result.citiesCount) metro(s) (\(cityBreakdown))."
                            } else {
                                self.importSummaryAlertMessage = "No new exploration hexes found in GPX file."
                            }
                            self.showImportAlert = true
                            await self.loadAllData()
                        }
                    }
                )
            } catch {
                print("Failed to process GPX: \(error)")
                await MainActor.run {
                    self.isImporting = false
                    self.importSummaryAlertMessage = "Failed to parse GPX file: \(error.localizedDescription)"
                    self.showImportAlert = true
                }
            }
        }
    }
}
