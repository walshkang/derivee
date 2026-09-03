import SwiftUI
import CoreLocation

struct ContentView: View {
    @State private var isHydrationComplete = false
    @State private var isCheckingHydration = true
    @StateObject private var trackingEngine = AmbientTrackingEngine()
    @State private var spatialStore = SpatialStore()
    @State private var cityDetectionService = CityDetectionService()
    @State private var showTransitSheet = false
    @State private var selectedTransitStop: String? = nil
    @State private var isMapCentered = true
    @State private var recenterTrigger = false
    @State private var showStatsView = false
    @State private var userScreenPosition: CGPoint? = nil
    @State private var targetCoordinate: CLLocationCoordinate2D? = nil
    @State private var currentUserLocation: CLLocationCoordinate2D? = nil
    @State private var lastScannedLocation: CLLocationCoordinate2D? = nil
    
    @State private var glowScale: CGFloat = 1.0
    @State private var glowOpacity: Double = 0.0
    
    @Environment(\.colorScheme) var colorScheme
    @AppStorage(AppStorageKeys.selectedBasemapTheme) private var storedTheme: String = ""
    @AppStorage(AppStorageKeys.fogOpacity) private var fogOpacity: Double = MapCustomizationDefaults.defaultFogOpacity
    @AppStorage(AppStorageKeys.showBoundaryBorders) private var showBoundaryBorders: Bool = MapCustomizationDefaults.defaultShowBoundaryBorders
    @AppStorage(AppStorageKeys.showSubwayThoroughfares) private var showSubwayThoroughfares: Bool = MapCustomizationDefaults.defaultShowSubwayThoroughfares
    @AppStorage(AppStorageKeys.subwayStationMarkerStyle) private var storedStationMarkerStyle: String = MapCustomizationDefaults.defaultSubwayStationMarkerStyle.rawValue
    @AppStorage(AppStorageKeys.showNearbyBusesLens) private var showNearbyBusesLens: Bool = MapCustomizationDefaults.defaultShowNearbyBusesLens
    
    @State private var nearbyBusStops: [SpatialDatabaseManager.NearbyBusStop] = []
    @State private var isNearbyBusesExpanded: Bool = false
    @State private var isScanningBuses: Bool = false
    @State private var isReadyForToasts: Bool = false
    @State private var activeNavigationItinerary: JourneyItinerary? = nil
    @State private var activeNavigationSession: ActiveWalkingNavigationSession? = nil
    @State private var activeCyclingSession: ActiveCyclingNavigationSession? = nil
    @State private var navigationManager = MultimodalTripNavigationManager.shared
    @State private var showNavigationSheet: Bool = false
    @State private var navigationDetent: PresentationDetent = NavigationSheetDetent.half.presentationDetent
    
    private var currentTheme: BasemapTheme {
        if let theme = BasemapTheme(rawValue: storedTheme) {
            return theme
        }
        return .day
    }
    
    private var stationMarkerStyle: SubwayStationMarkerStyle {
        SubwayStationMarkerStyle(rawValue: storedStationMarkerStyle) ?? .exploredOnly
    }
    
    var body: some View {
        Group {
            if isCheckingHydration {
                Color.black.ignoresSafeArea()
                    .task {
                        let activeSlug = cityDetectionService.activeCitySlug
                        if activeSlug != spatialStore.activeCitySlug {
                            let config = (try? CityPackManager.shared.loadConfig(for: activeSlug)) ?? .nycDefault
                            spatialStore.setActiveCity(config)
                        }
                        isHydrationComplete = (try? await SpatialDatabaseManager.shared.isHydrationComplete()) ?? false
                        isCheckingHydration = false
                        let targetSlug = activeSlug
                        Task {
                            try? await JourneyPlanner.shared.configureForCity(slug: targetSlug)
                        }
                    }
            } else if !isHydrationComplete {
                OnboardingView(trackingEngine: trackingEngine, isHydrationComplete: $isHydrationComplete)
            } else {
                ZStack {
                    MapView(trackingEngine: trackingEngine,
                            spatialStore: spatialStore,
                            fogShape: spatialStore.currentFogShape,
                            showTransitSheet: $showTransitSheet,
                            selectedTransitStop: $selectedTransitStop,
                            isCentered: $isMapCentered,
                            recenterTrigger: $recenterTrigger,
                            userScreenPosition: $userScreenPosition,
                            targetCoordinate: $targetCoordinate,
                            currentUserLocation: $currentUserLocation,
                            transientHexShape: spatialStore.transientHexShape,
                            selectedTheme: currentTheme,
                            fogOpacity: fogOpacity,
                            showBoundaryBorders: showBoundaryBorders,
                            showSubwayThoroughfares: showSubwayThoroughfares,
                            subwayStationMarkerStyle: stationMarkerStyle,
                            nearbyBusStops: nearbyBusStops,
                            activeSignalCoordinate: activeNavigationSession?.activeSignalCoordinate,
                            onAmbientMapTap: {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                    isNearbyBusesExpanded = false
                                    spatialStore.newlyDiscoveredPOIName = nil
                                    cityDetectionService.autoSwitchToast = nil
                                }
                            },
                            onMapGesture: {
                                if isNearbyBusesExpanded {
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                        isNearbyBusesExpanded = false
                                    }
                                }
                            })
                        .ignoresSafeArea()
                    
                    GeometryReader { geo in
                        Circle()
                            .strokeBorder(Color.white, lineWidth: 4)
                            .frame(width: 80, height: 80)
                            .shadow(color: .white, radius: 10)
                            .scaleEffect(glowScale)
                            .opacity(glowOpacity)
                            .position(userScreenPosition ?? CGPoint(x: geo.size.width / 2, y: geo.size.height / 2))
                    }
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    
                    VStack {
                        HStack {
                            Spacer()
                            ProfileFAB {
                                showStatsView = true
                            }
                            .padding(.top, 50)
                            .padding(.trailing, 20)
                        }
                        
                        Spacer()
                        
                        HStack(alignment: .bottom) {
                            if showNearbyBusesLens {
                                NearbyBusesCapsule(
                                    busStops: nearbyBusStops,
                                    isExpanded: $isNearbyBusesExpanded,
                                    isLoading: isScanningBuses,
                                    hasLocation: currentUserLocation != nil || trackingEngine.lastKnownLocation != nil,
                                    onSelectStop: { stop in
                                        isNearbyBusesExpanded = false
                                        selectedTransitStop = stop.id
                                        showTransitSheet = true
                                    },
                                    onRefresh: {
                                        scanNearbyBuses(force: true)
                                    }
                                )
                                .padding(.leading, 20)
                            }
                            
                            Spacer()
                            
                            RecenterFAB(isCentered: isMapCentered) {
                                recenterTrigger.toggle()
                                isMapCentered = true
                            }
                            .padding(.trailing, 20)
                        }
                        .padding(.bottom, 40)
                    }
                    
                    if let poiName = spatialStore.newlyDiscoveredPOIName, isReadyForToasts {
                        VStack {
                            DiscoveryToast(stationName: poiName) {
                                spatialStore.newlyDiscoveredPOIName = nil
                            }
                            .transition(.move(edge: .top).combined(with: .opacity))
                            
                            Spacer()
                        }
                        .padding(.top, 50)
                        .zIndex(2)
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                                if spatialStore.newlyDiscoveredPOIName == poiName {
                                    withAnimation {
                                        spatialStore.newlyDiscoveredPOIName = nil
                                    }
                                }
                            }
                        }
                    }
                    
                    if let autoSwitch = cityDetectionService.autoSwitchToast, isReadyForToasts {
                        VStack {
                            CityAutoSwitchToast(cityName: autoSwitch.cityName, message: autoSwitch.message) {
                                cityDetectionService.autoSwitchToast = nil
                            }
                            .transition(.move(edge: .top).combined(with: .opacity))
                            
                            Spacer()
                        }
                        .padding(.top, 50)
                        .zIndex(3)
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                                if cityDetectionService.autoSwitchToast?.id == autoSwitch.id {
                                    withAnimation {
                                        cityDetectionService.autoSwitchToast = nil
                                    }
                                }
                            }
                        }
                    }
                }
                .onAppear {
                    cityDetectionService.onActiveCityChanged = { [self] newSlug in
                        self.executeCityHotSwap(to: newSlug)
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                        isReadyForToasts = true
                    }
                    if let loc = trackingEngine.lastKnownLocation {
                        cityDetectionService.evaluateLocation(loc)
                    }
                    if showNearbyBusesLens {
                        scanNearbyBuses()
                    }
                }
                .onChange(of: currentUserLocation?.latitude) {
                    if let cur = currentUserLocation {
                        cityDetectionService.evaluateLocation(CLLocation(latitude: cur.latitude, longitude: cur.longitude))
                    }
                    if showNearbyBusesLens {
                        scanNearbyBuses()
                    }
                }
                .onChange(of: trackingEngine.lastKnownLocation) { _, newLoc in
                    if let loc = newLoc {
                        cityDetectionService.evaluateLocation(loc)
                        activeNavigationSession?.updateUserLocation(loc.coordinate, horizontalAccuracy: loc.horizontalAccuracy)
                        activeCyclingSession?.updateUserLocation(loc.coordinate, horizontalAccuracy: loc.horizontalAccuracy)
                        navigationManager.updateUserLocation(loc)
                    }
                    if showNearbyBusesLens {
                        scanNearbyBuses()
                    }
                }
                .animation(.spring(), value: spatialStore.newlyDiscoveredPOIName)
                .animation(.spring(), value: cityDetectionService.autoSwitchToast)
                .onChange(of: spatialStore.newlyUnlockedHexLocation != nil) {
                    if spatialStore.newlyUnlockedHexLocation != nil {
                        glowScale = 1.0
                        glowOpacity = 0.8
                        
                        withAnimation(.easeOut(duration: 1.5)) {
                            glowScale = 4.0
                            glowOpacity = 0.0
                        }
                        
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            spatialStore.newlyUnlockedHexLocation = nil
                        }
                    }
                }
                .sheet(item: $cityDetectionService.promptCity) { city in
                    CityDownloadPromptSheet(
                        city: city,
                        onDownloadComplete: { installedCity in
                            cityDetectionService.markCityInstalled(installedCity.slug)
                            cityDetectionService.performAutoSwitch(to: installedCity)
                        },
                        onDismiss: {
                            cityDetectionService.promptCity = nil
                        },
                        onSnooze: { snoozedCity in
                            cityDetectionService.snoozeCity(slug: snoozedCity.slug)
                        }
                    )
                    .presentationDetents([.fraction(0.38), .medium])
                    .presentationDragIndicator(.visible)
                    .presentationBackground(.ultraThinMaterial)
                }
                .sheet(isPresented: Binding(
                    get: { showTransitSheet && selectedTransitStop != nil },
                    set: { newValue in
                        showTransitSheet = newValue
                        if !newValue {
                            selectedTransitStop = nil
                        }
                    }
                )) {
                    if let stopId = selectedTransitStop {
                        TransitRevealSheet(stopId: stopId, onFocusMap: { coord in
                            targetCoordinate = coord
                            isMapCentered = false
                        })
                            .presentationDetents([.medium, .large])
                            .presentationDragIndicator(.visible)
                            .presentationContentInteraction(.scrolls)
                    }
                }
                .onChange(of: activeNavigationItinerary) { _, newItin in
                    if let itin = newItin {
                        navigationManager.startTripNavigation(itinerary: itin)
                    }
                }
                .sheet(isPresented: Binding(
                    get: { showNavigationSheet && (activeNavigationItinerary != nil || navigationManager.isNavigating) },
                    set: { newValue in
                        showNavigationSheet = newValue
                        if !newValue {
                            activeNavigationItinerary = nil
                            activeNavigationSession = nil
                            activeCyclingSession = nil
                            navigationManager.endNavigation()
                        }
                    }
                )) {
                    if let itinerary = activeNavigationItinerary ?? navigationManager.itinerary {
                        NavigationGuidanceSheet(
                            itinerary: itinerary,
                            selectedDetent: $navigationDetent,
                            navigationSession: navigationManager.walkingSession ?? activeNavigationSession,
                            cyclingSession: navigationManager.cyclingSession ?? activeCyclingSession,
                            navigationManager: navigationManager,
                            onFocusLeg: { leg in
                                isMapCentered = false
                            },
                            onEndJourney: {
                                showNavigationSheet = false
                                activeNavigationItinerary = nil
                                activeNavigationSession = nil
                                activeCyclingSession = nil
                                navigationManager.endNavigation()
                            }
                        )
                    }
                }
                .sheet(isPresented: $showStatsView) {
                    StatsView(
                        trackingEngine: trackingEngine,
                        spatialStore: spatialStore,
                        cityDetectionService: cityDetectionService,
                        onSwitchCity: { slug, coord in
                            let targetConfig = (try? CityPackManager.shared.loadConfig(for: slug)) ??
                                               CityManifest.defaultManifest.findCity(bySlug: slug).map { entry in
                                                   CityConfig(slug: entry.slug, displayName: entry.displayName, region: entry.region, bounds: entry.bounds ?? CityConfig.nycDefault.bounds, center: entry.center ?? CityConfig.nycDefault.center)
                                               } ?? CityConfig.nycDefault
                            
                            if spatialStore.activeCitySlug != slug {
                                executeCityHotSwap(to: slug)
                            }
                            
                            // Disambiguate coordinate: if within bounds, target it; otherwise default to destination city center
                            let resolvedCoord: CLLocationCoordinate2D
                            if let c = coord, c.latitude != 0, c.longitude != 0, targetConfig.bounds.contains(coordinate: c) {
                                resolvedCoord = c
                            } else {
                                resolvedCoord = targetConfig.center.coordinate
                            }
                            
                            targetCoordinate = resolvedCoord
                            isMapCentered = false
                        },
                        targetCoordinate: $targetCoordinate
                    )
                    .presentationDragIndicator(.visible)
                    .presentationContentInteraction(.scrolls)
                }
                .onOpenURL { url in
                    guard url.scheme == "derivee" else { return }
                    if url.host == "progress" {
                        showStatsView = false
                        showTransitSheet = false
                        isMapCentered = true
                        recenterTrigger.toggle()
                        
                        glowScale = 1.0
                        glowOpacity = 0.8
                        withAnimation(.easeOut(duration: 1.5)) {
                            glowScale = 4.0
                            glowOpacity = 0.0
                        }
                    } else if url.host == "navigation" {
                        showStatsView = false
                        showTransitSheet = false
                        if activeNavigationItinerary != nil || navigationManager.isNavigating {
                            showNavigationSheet = true
                            navigationDetent = NavigationSheetDetent.half.presentationDetent
                            isMapCentered = true
                            recenterTrigger.toggle()
                        }
                    }
                }
            }
        }
        .preferredColorScheme(.light)
    }
    
    private func scanNearbyBuses(force: Bool = false) {
        guard let center = currentUserLocation ?? trackingEngine.lastKnownLocation?.coordinate else {
            // GPS acquisition in progress — avoid querying synthetic/fallback coordinates
            return
        }
        
        let userLoc = CLLocation(latitude: center.latitude, longitude: center.longitude)
        
        // 1. Immediately update distance and re-sort existing stops relative to current live location
        if !nearbyBusStops.isEmpty {
            var updatedStops = nearbyBusStops.map { stop in
                let stopLoc = CLLocation(latitude: stop.coordinate.latitude, longitude: stop.coordinate.longitude)
                let dist = userLoc.distance(from: stopLoc)
                return SpatialDatabaseManager.NearbyBusStop(
                    id: stop.id,
                    name: stop.name,
                    coordinate: stop.coordinate,
                    distanceMeters: dist,
                    routes: stop.routes,
                    direction: stop.direction
                )
            }
            updatedStops.sort { $0.distanceMeters < $1.distanceMeters }
            self.nearbyBusStops = updatedStops
        }
        
        // 2. Query SQLite if forced, or if stops are empty, or if user walked > 30m since last full DB query
        if !force, let lastScanned = lastScannedLocation {
            let lastLoc = CLLocation(latitude: lastScanned.latitude, longitude: lastScanned.longitude)
            if userLoc.distance(from: lastLoc) < 30.0 && !nearbyBusStops.isEmpty {
                return
            }
        }
        
        guard !isScanningBuses else { return }
        isScanningBuses = true
        lastScannedLocation = center
        
        Task {
            do {
                let stops = try await SpatialDatabaseManager.shared.fetchNearbyBusStops(coordinate: center, radiusMeters: 400.0)
                await MainActor.run {
                    self.nearbyBusStops = stops
                    self.isScanningBuses = false
                }
            } catch {
                await MainActor.run {
                    self.isScanningBuses = false
                }
            }
        }
    }
    
    // MARK: - Coordinated Two-Phase Transit DB Hot-Swap (Wave L-B.3)
    
    private func executeCityHotSwap(to slug: String) {
        logPipeline("🏙️ [ContentView] executeCityHotSwap triggered for slug: \(slug)")
        
        let newConfig = (try? CityPackManager.shared.loadConfig(for: slug)) ??
                        CityManifest.defaultManifest.findCity(bySlug: slug).map { entry in
                            CityConfig(slug: entry.slug, displayName: entry.displayName, region: entry.region, bounds: entry.bounds ?? CityConfig.nycDefault.bounds, center: entry.center ?? CityConfig.nycDefault.center)
                        } ?? CityConfig.nycDefault
        
        // Synchronously update SpatialStore and CameraBounds on @MainActor immediately
        // so that camera viewport bounds, fog envelope, and UI states align with the target city before async DB tasks
        spatialStore.setActiveCity(newConfig)
        
        // Phase 1: Pre-Swap UI Query Teardown
        TransitRealtimeService.shared.prepareForCitySwap()
        showTransitSheet = false
        selectedTransitStop = nil
        isScanningBuses = false
        nearbyBusStops = []
        
        Task {
            await JourneyPlanner.shared.prepareForCitySwap()
            await GBFSSyncService.shared.prepareForCitySwap()
            await GBFSSyncService.shared.configureForCity(config: newConfig.transit?.gbfs)
            
            // Phase 2: GRDB Serialized Write Barrier & Hot-Swap
            let packTransitURL = CityPackManager.shared.transitDatabaseURL(for: slug)
            let packNbhdURL = CityPackManager.shared.neighborhoodDatabaseURL(for: slug)
            let validNbhdURL = FileManager.default.fileExists(atPath: packNbhdURL.path) ? packNbhdURL : nil
            
            if FileManager.default.fileExists(atPath: packTransitURL.path) {
                do {
                    try await SpatialDatabaseManager.shared.hotSwapCityDatabase(transitURL: packTransitURL, neighborhoodURL: validNbhdURL)
                } catch {
                    logPipeline("⚠️ [ContentView] hotSwapCityDatabase failed: \(error)")
                }
            }
            
            // Phase 3: Post-Swap State Sync & Re-enablement
            try? await JourneyPlanner.shared.configureForCity(slug: slug)
            await MainActor.run {
                if showNearbyBusesLens {
                    scanNearbyBuses(force: true)
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
