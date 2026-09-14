import SwiftUI
import CoreLocation
import UserNotifications
import UniformTypeIdentifiers

public enum SettingsSection: String, Hashable, CaseIterable, Identifiable {
    case mapAesthetics = "mapAesthetics"
    case transitWayfinding = "transitWayfinding"
    case tracking = "tracking"
    case notifications = "notifications"
    case citiesStorage = "citiesStorage"
    case dataManagement = "dataManagement"
    case about = "about"
    
    public var id: String { rawValue }
}

struct SettingsView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    @ObservedObject var trackingEngine: AmbientTrackingEngine
    var spatialStore: SpatialStore
    var cityDetectionService: CityDetectionService? = nil
    var onDismissToMap: (() -> Void)? = nil
    var scrollToSection: SettingsSection? = nil
    
    @AppStorage(AppStorageKeys.selectedBasemapTheme) private var storedTheme: String = BasemapTheme.day.rawValue
    @AppStorage(AppStorageKeys.fogOpacity) private var fogOpacity: Double = MapCustomizationDefaults.defaultFogOpacity
    @AppStorage(AppStorageKeys.showBoundaryBorders) private var showBoundaryBorders: Bool = MapCustomizationDefaults.defaultShowBoundaryBorders
    @AppStorage(AppStorageKeys.showSubwayThoroughfares) private var showSubwayThoroughfares: Bool = MapCustomizationDefaults.defaultShowSubwayThoroughfares
    @AppStorage(AppStorageKeys.subwayStationMarkerStyle) private var storedStationMarkerStyle: String = MapCustomizationDefaults.defaultSubwayStationMarkerStyle.rawValue
    @AppStorage(AppStorageKeys.showNearbyBusesLens) private var showNearbyBusesLens: Bool = MapCustomizationDefaults.defaultShowNearbyBusesLens
    
    @State private var showResetAlert = false
    @State private var showCacheAlert = false
    @State private var showPauseTrackingAlert = false
    @State private var locationStatus: String = "Undetermined"
    @State private var notificationsEnabled: Bool = false
    @State private var showFileImporter = false
    @State private var isImporting = false
    @State private var importProgress = 0.0
    @State private var showImportAlert = false
    @State private var importSummaryAlertMessage: String? = nil
    
    var body: some View {
        ScrollViewReader { proxy in
            Form {
                Section(header: Text("Map Aesthetics & Exploration"), footer: Text("Visual styles and boundary highlights update instantly on the GPU with zero database overhead.")) {
                    Picker("Basemap Theme", selection: $storedTheme) {
                        ForEach(BasemapTheme.allCases) { theme in
                            Text(theme.displayName).tag(theme.rawValue)
                        }
                    }
                    .onChange(of: storedTheme) { _, newTheme in
                        if newTheme == BasemapTheme.transit.rawValue {
                            withAnimation {
                                fogOpacity = MapCustomizationDefaults.transitFogOpacity
                            }
                        } else if newTheme == BasemapTheme.day.rawValue {
                            withAnimation {
                                fogOpacity = MapCustomizationDefaults.defaultFogOpacity
                            }
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
                        .tint(Color.primary)
                    }
                    .padding(.vertical, 4)
                    
                    Toggle("Exploration Boundary Borders", isOn: $showBoundaryBorders)
                }
                .id(SettingsSection.mapAesthetics)
                
                Section(header: Text("Transit & Wayfinding"), footer: Text("Subway thoroughfares render as ambient orienting sub-context under the fog, lighting up vibrantly in explored territory.")) {
                    Toggle("Subway Thoroughfares", isOn: $showSubwayThoroughfares)
                    
                    Picker("Station Markers", selection: $storedStationMarkerStyle) {
                        ForEach(SubwayStationMarkerStyle.allCases) { style in
                            Text(style.rawValue).tag(style.rawValue)
                        }
                    }
                    
                    Toggle("Nearby Buses Quick Lens", isOn: $showNearbyBusesLens)
                }
                .id(SettingsSection.transitWayfinding)
                
                Section(header: Text("Tracking")) {
                    Toggle("Ambient Tracking", isOn: Binding(
                        get: { trackingEngine.isTracking },
                        set: { newValue in
                            if newValue {
                                trackingEngine.isTrackingEnabled = true
                                trackingEngine.startTracking()
                            } else {
                                showPauseTrackingAlert = true
                            }
                        }
                    ))
                    .alert("Pause Ambient Exploration?", isPresented: $showPauseTrackingAlert) {
                        Button("Keep Tracking On", role: .cancel) { }
                        Button("Pause Tracking", role: .destructive) {
                            trackingEngine.isTrackingEnabled = false
                            Task {
                                await trackingEngine.stopTracking()
                            }
                        }
                    } message: {
                        Text("Pausing tracking will stop discovering new hexes while your screen is off or the app is closed. Remember to re-enable tracking before your next drift.")
                    }
                    
                    Toggle("Dynamic Island Glance", isOn: Binding(
                        get: { trackingEngine.isLiveActivityEnabled },
                        set: { newValue in
                            trackingEngine.updateLiveActivityPreference(enabled: newValue)
                        }
                    ))
                    
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
                .id(SettingsSection.tracking)
                
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
                .id(SettingsSection.notifications)
                
                Section(header: Text("Cities & Storage"), footer: Text("Manage offline city packs, GTFS transit databases, and vector route lines with zero loss to your personal exploration history.")) {
                    NavigationLink(destination: CitiesStorageManagerView()) {
                        HStack {
                            Image(systemName: "internaldrive")
                                .foregroundColor(Color(hex: "#FFB300"))
                            Text("Manage Cities & Storage")
                        }
                    }
                }
                .id(SettingsSection.citiesStorage)
                .id("citiesStorage")
                
                Section(header: Text("Data Management"), footer: Text("Upload past workout files (GPX or FIT) to backfill your exploration map across metros. Clearing the cache will require downloading transit and tile data on the next launch.")) {
                    Button {
                        showFileImporter = true
                    } label: {
                        HStack {
                            Label("Upload Previous Workouts", systemImage: "square.and.arrow.down")
                                .foregroundColor(.primary)
                            Spacer()
                            if isImporting {
                                ProgressView(value: importProgress)
                                    .tint(Color(hex: "#FFB300"))
                                    .frame(width: 48)
                            }
                        }
                    }
                    .disabled(isImporting)
                    
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
                        Text("This will permanently delete all your explored hexes and discovered transit stops across all cities. The fog will return entirely.")
                    }
                }
                .id(SettingsSection.dataManagement)
                
                Section(header: Text("About & Open Data")) {
                    NavigationLink(destination: PhilosophyView()) {
                        Text("The Philosophy")
                    }
                    
                    NavigationLink(destination: TransitAttributionsView()) {
                        Text("Open Data & Attributions")
                    }
                }
                .id(SettingsSection.about)
                
                Section {
                    ApertureSignatureView()
                        .listRowBackground(Color.clear)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        if let onDismissToMap = onDismissToMap {
                            onDismissToMap()
                        } else {
                            dismiss()
                        }
                    }
                }
            }
            .onAppear {
                updateLocationStatus()
                checkNotificationStatus()
                if let target = scrollToSection {
                    withAnimation {
                        proxy.scrollTo(target, anchor: .top)
                    }
                }
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
