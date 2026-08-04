import SwiftUI
import CoreLocation

struct StatsView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    
    @ObservedObject var trackingEngine: AmbientTrackingEngine
    var spatialStore: SpatialStore
    
    @State private var neighborhoods: [SpatialDatabaseManager.NeighborhoodProgress] = []
    @State private var isImporting = false
    @State private var importProgress: Double = 0.0
    
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
                        Section(header: Text("Neighborhood Progression")) {
                            ForEach(neighborhoods) { nbhd in
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
                                            .font(.subheadline)
                                            .fontWeight(.bold)
                                        
                                        Text("\(nbhd.clearedHexes) / \(nbhd.totalHexes)")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
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
                            importGPX()
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
            .navigationTitle("The Archive")
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
    
    private func importGPX() {
        // For demonstration, we load the bundled NYC_Walk.gpx
        guard let url = Bundle.main.url(forResource: "NYC_Walk", withExtension: "gpx") else {
            print("NYC_Walk.gpx not found in bundle")
            return
        }
        
        isImporting = true
        importProgress = 0.0
        
        Task.detached(priority: .userInitiated) {
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
