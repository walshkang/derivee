import SwiftUI
import CoreLocation
import UserNotifications

struct SettingsView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    @ObservedObject var trackingEngine: AmbientTrackingEngine
    var spatialStore: SpatialStore
    
    @AppStorage(AppStorageKeys.selectedBasemapTheme) private var storedTheme: String = BasemapTheme.night.rawValue
    @AppStorage(AppStorageKeys.fogOpacity) private var fogOpacity: Double = MapCustomizationDefaults.defaultFogOpacity
    @AppStorage(AppStorageKeys.showBoundaryBorders) private var showBoundaryBorders: Bool = MapCustomizationDefaults.defaultShowBoundaryBorders
    
    @State private var showResetAlert = false
    @State private var showCacheAlert = false
    @State private var showPauseTrackingAlert = false
    @State private var locationStatus: String = "Undetermined"
    @State private var notificationsEnabled: Bool = false
    
    var body: some View {
        Form {
            Section(header: Text("Map Aesthetics & Exploration"), footer: Text("Visual styles and boundary highlights update instantly on the GPU with zero database overhead.")) {
                Picker("Basemap Theme", selection: $storedTheme) {
                    ForEach(BasemapTheme.allCases) { theme in
                        Text(theme.displayName).tag(theme.rawValue)
                    }
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Fog Density")
                        Spacer()
                        Text("\(Int(round(fogOpacity * 100)))%")
                            .font(.system(.subheadline, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    Slider(
                        value: $fogOpacity,
                        in: MapCustomizationDefaults.minFogOpacity...MapCustomizationDefaults.maxFogOpacity,
                        step: 0.01
                    )
                    .tint(colorScheme == .dark ? .white : .black)
                }
                .padding(.vertical, 4)
                
                Toggle("Exploration Boundary Borders", isOn: $showBoundaryBorders)
            }
            
            Section(header: Text("Tracking")) {
                Toggle("Ambient Tracking", isOn: Binding(
                    get: { trackingEngine.isTracking },
                    set: { newValue in
                        if newValue {
                            trackingEngine.startTracking()
                        } else {
                            showPauseTrackingAlert = true
                        }
                    }
                ))
                .alert("Pause Ambient Exploration?", isPresented: $showPauseTrackingAlert) {
                    Button("Keep Tracking On", role: .cancel) { }
                    Button("Pause Tracking", role: .destructive) {
                        Task {
                            await trackingEngine.stopTracking()
                        }
                    }
                } message: {
                    Text("Pausing tracking will stop discovering new hexes while your screen is off or the app is closed. Remember to re-enable tracking before your next drift.")
                }
                
                HStack {
                    Text("Permission Status")
                    Spacer()
                    Text(locationStatus)
                        .foregroundColor(.secondary)
                }
                
                if locationStatus == "Not Determined" || locationStatus == "Denied" {
                    Button("Request Permissions") {
                        trackingEngine.requestPermissions()
                        updateLocationStatus()
                    }
                }
            }
            
            Section(header: Text("Notifications")) {
                Toggle("Push Notifications", isOn: Binding(
                    get: { notificationsEnabled },
                    set: { newValue in
                        if newValue {
                            requestNotificationPermissions()
                        } else {
                            notificationsEnabled = false
                        }
                    }
                ))
            }
            
            Section(header: Text("Data Management"), footer: Text("Clearing the cache will require downloading transit and tile data on the next launch.")) {
                Button(role: .destructive) {
                    showCacheAlert = true
                } label: {
                    Text("Clear Local Cache")
                }
                .alert("Clear Cache?", isPresented: $showCacheAlert) {
                    Button("Cancel", role: .cancel) { }
                    Button("Clear", role: .destructive) {
                        Task {
                            do {
                                try await SpatialDatabaseManager.shared.clearLocalCache()
                            } catch {
                                print("Failed to clear cache: \(error)")
                            }
                        }
                    }
                } message: {
                    Text("This will force the Onboarding Gate to download base data on the next launch.")
                }
                
                Button(role: .destructive) {
                    showResetAlert = true
                } label: {
                    Text("Reset Exploration Data")
                }
                .alert("Reset Data?", isPresented: $showResetAlert) {
                    Button("Cancel", role: .cancel) { }
                    Button("Reset", role: .destructive) {
                        Task {
                            do {
                                try await SpatialDatabaseManager.shared.resetExplorationData()
                                await MainActor.run {
                                    spatialStore.clearData()
                                }
                            } catch {
                                print("Failed to reset exploration data: \(error)")
                            }
                        }
                    }
                } message: {
                    Text("This will permanently delete all your explored hexes and discovered transit stops. The fog will return entirely.")
                }
            }
            
            Section(header: Text("About")) {
                NavigationLink(destination: PhilosophyView()) {
                    Text("The Philosophy")
                }
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            updateLocationStatus()
            checkNotificationStatus()
        }
    }
    
    private func updateLocationStatus() {
        let manager = CLLocationManager()
        switch manager.authorizationStatus {
        case .notDetermined: locationStatus = "Not Determined"
        case .restricted: locationStatus = "Restricted"
        case .denied: locationStatus = "Denied"
        case .authorizedAlways: locationStatus = "Authorized Always"
        case .authorizedWhenInUse: locationStatus = "Authorized When In Use"
        @unknown default: locationStatus = "Unknown"
        }
    }
    
    private func checkNotificationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                self.notificationsEnabled = (settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional)
            }
        }
    }
    
    private func requestNotificationPermissions() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            DispatchQueue.main.async {
                self.notificationsEnabled = granted
            }
        }
    }
}
