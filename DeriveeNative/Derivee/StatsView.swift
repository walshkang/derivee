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
    
    @Binding var targetCoordinate: CLLocationCoordinate2D?
    
    @State private var selectedTab: StatsTab = .neighborhoods
    @State private var neighborhoods: [SpatialDatabaseManager.NeighborhoodProgress] = []
    @State private var journalData: ExplorationJournalData? = nil
    @State private var isImporting = false
    @State private var importProgress: Double = 0.0
    @State private var showFileImporter = false
    @State private var isLoading = true
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Segmented Tab Selector
                Picker("Section", selection: $selectedTab) {
                    ForEach(StatsTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 10)
                .background(Color(UIColor.systemGroupedBackground))
                
                if selectedTab == .neighborhoods {
                    neighborhoodsContent
                } else {
                    journalContent
                }
                
                if selectedTab == .neighborhoods {
                    VStack(spacing: 16) {
                        if isImporting {
                            VStack(spacing: 8) {
                                Text("Processing GPX...")
                                    .font(.caption)
                                ProgressView(value: importProgress)
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
                    NavigationLink(destination: SettingsView(trackingEngine: trackingEngine, spatialStore: spatialStore)) {
                        Image(systemName: "gear")
                    }
                }
            }
            .task {
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
                
                Section(header: Text("Macro Metrics")) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("City Explored")
                                .font(.headline)
                            Spacer()
                            Text("\(String(format: "%.1f", overallPercentage))%")
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
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 8)
                }
                
                Section(header: Text("Neighborhood Progression")) {
                    ForEach(neighborhoods) { nbhd in
                        Button(action: {
                            targetCoordinate = CLLocationCoordinate2D(latitude: nbhd.centroidLat, longitude: nbhd.centroidLng)
                            dismiss()
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
                                    Text("\(String(format: "%.1f", nbhd.percentage))%")
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
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 10) {
                                Image(systemName: card.category.systemImage)
                                    .font(.title3)
                                    .foregroundColor(Color(hex: "#FFB300"))
                                    .frame(width: 28)
                                
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
                            
                            // Tiers Carousel / Badges List
                            VStack(spacing: 8) {
                                ForEach(card.tiers) { tier in
                                    HStack(spacing: 12) {
                                        ZStack {
                                            Circle()
                                                .fill(tier.isUnlocked ? Color(hex: "#FFB300").opacity(0.2) : Color.gray.opacity(0.15))
                                                .frame(width: 32, height: 32)
                                            Image(systemName: tier.badgeIconName)
                                                .font(.system(size: 14))
                                                .foregroundColor(tier.isUnlocked ? Color(hex: "#FFB300") : .secondary)
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
                                            Image(systemName: "checkmark.seal.fill")
                                                .foregroundColor(Color(hex: "#FFB300"))
                                                .font(.subheadline)
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
                
                // NYC Borough Breakdown
                Section(header: Text("NYC Borough Footprint")) {
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
                                Text("\(b.exploredNeighborhoodCount) / \(b.neighborhoodCount) Neighborhoods")
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
                
                // Historic Landmarks Catalog
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
            .listStyle(.insetGrouped)
        } else {
            VStack {
                ProgressView()
                    .padding()
                Text("Loading Exploration Journal...")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
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
    
    // MARK: - Data Loading
    
    private func loadAllData() async {
        isLoading = true
        do {
            async let nbhdStats = SpatialDatabaseManager.shared.fetchNeighborhoodProgression()
            async let jData = SpatialDatabaseManager.shared.fetchExplorationJournalData()
            
            let (fetchedNbhds, fetchedJournal) = try await (nbhdStats, jData)
            
            await MainActor.run {
                self.neighborhoods = fetchedNbhds
                self.journalData = fetchedJournal
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
                let defaultLoc = CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060)
                let userLoc = await MainActor.run { trackingEngine.isTracking ? defaultLoc : defaultLoc }
                
                let existingHexes = await MainActor.run { spatialStore.exploredHexes }
                
                processor.processAndInsert(coordinates: coordinates, userLocation: userLoc, existingHexes: existingHexes) { progress in
                    self.importProgress = progress
                } onComplete: {
                    self.isImporting = false
                    self.dismiss()
                }
            } catch {
                print("Failed to process GPX: \(error)")
                await MainActor.run {
                    self.isImporting = false
                }
            }
        }
    }
}
