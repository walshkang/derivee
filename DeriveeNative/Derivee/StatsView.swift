import SwiftUI
import CoreLocation
import UniformTypeIdentifiers

struct StatsView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    
    @ObservedObject var trackingEngine: AmbientTrackingEngine
    var spatialStore: SpatialStore
    
    @Binding var targetCoordinate: CLLocationCoordinate2D?
    
    @State private var neighborhoods: [SpatialDatabaseManager.NeighborhoodProgress] = []
    @State private var isImporting = false
    @State private var importProgress: Double = 0.0
    @State private var showFileImporter = false
    
    var body: some View {
        NavigationStack {
            VStack {
                if neighborhoods.isEmpty {
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
                                Text("Import Workout (.gpx)")
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
                    NavigationLink(destination: SettingsView(trackingEngine: trackingEngine, spatialStore: spatialStore)) {
                        Image(systemName: "gear")
                    }
                }
            }
            .onAppear {
                loadStats()
            }
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: [UTType.xml, UTType(filenameExtension: "gpx") ?? .xml],
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
    
    private func loadStats() {
        Task {
            do {
                let stats = try await SpatialDatabaseManager.shared.fetchNeighborhoodProgression()
                await MainActor.run {
                    self.neighborhoods = stats
                }
            } catch {
                print("Error loading neighborhood stats: \(error)")
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
                // Use a default user location or actual user location if available
                let defaultLoc = CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060)
                let userLoc = await MainActor.run { trackingEngine.isTracking ? defaultLoc : defaultLoc } // In a real scenario, use actual location
                
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
