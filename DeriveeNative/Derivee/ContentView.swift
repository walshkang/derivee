import SwiftUI
import CoreLocation

/// Unified mutually exclusive presentation state machine for Screen 0-4 modal sheets (Wave PE.9).
/// Enforces single-sheet architecture with zero background sheet retention (FC-5 invariant).
enum ActiveSheet: Identifiable, Equatable {
    case cityPrompt(CityManifestEntry)
    case transit(stopId: String)
    case search
    case routeComparison(RouteComparisonViewModel)
    case navigation(JourneyItinerary)
    case stats
    case driftControls
    
    var id: String {
        switch self {
        case .cityPrompt(let city):
            return "cityPrompt_\(city.slug)"
        case .transit(let stopId):
            return "transit_\(stopId)"
        case .search:
            return "search"
        case .routeComparison:
            return "routeComparison"
        case .navigation(let itin):
            return "navigation_\(itin.id)"
        case .stats:
            return "stats"
        case .driftControls:
            return "driftControls"
        }
    }
    
    static func == (lhs: ActiveSheet, rhs: ActiveSheet) -> Bool {
        switch (lhs, rhs) {
        case (.cityPrompt(let l), .cityPrompt(let r)):
            return l.slug == r.slug
        case (.transit(let l), .transit(let r)):
            return l == r
        case (.search, .search):
            return true
        case (.routeComparison(let l), .routeComparison(let r)):
            return l === r
        case (.navigation(let l), .navigation(let r)):
            return l.id == r.id
        case (.stats, .stats):
            return true
        case (.driftControls, .driftControls):
            return true
        default:
            return false
        }
    }
}

struct ContentView: View {
    @State private var isHydrationComplete = false
    @State private var isCheckingHydration = true
    @StateObject private var trackingEngine = AmbientTrackingEngine.shared
    @State private var spatialStore = SpatialStore()
    @State private var cityDetectionService = CityDetectionService()
    @State private var activeSheet: ActiveSheet? = nil
    @State private var isMapCentered = true
    @State private var recenterTrigger = false
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
    @State private var navigationDetent: PresentationDetent = NavigationSheetDetent.half.presentationDetent
    @State private var activeRouteInspection: RouteInspectionCommand? = nil
    @State private var activeFloorLevel: Int? = nil
    @State private var activeTransitSheetDetent: PresentationDetent = .medium
    @State private var activeOffScreenBeacon: OffScreenBeaconState? = nil
    @State private var vehicleFrameRelay = VehicleFrameRelay()
    
    private var currentTheme: BasemapTheme {
        if let theme = BasemapTheme(rawValue: storedTheme) {
            return theme
        }
        return .day
    }
    
    private var stationMarkerStyle: SubwayStationMarkerStyle {
        SubwayStationMarkerStyle(rawValue: storedStationMarkerStyle) ?? .exploredOnly
    }
    
    /// True when the user is actively inspecting a station or train/bus corridor (Wave PE.3 - FC-10).
    private var isTransitInspecting: Bool {
        if case .transit = activeSheet { return true }
        return activeRouteInspection != nil
    }
    
    /// Mode-adaptive master fog opacity (Wave PE.3).
    /// Automatically attenuates ambient fog from baseline down to `MapCustomizationDefaults.transitFogOpacity` (0.40)
    /// during station or active corridor inspection, revealing street grids, parks, and water in Light Mode parchment (#F9F9F6).
    /// Retains user baseline `AppStorageKeys.fogOpacity` for smooth restoration upon inspection exit.
    private var effectiveFogOpacity: Double {
        if isTransitInspecting {
            return min(fogOpacity, MapCustomizationDefaults.transitFogOpacity)
        }
        return fogOpacity
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
                            showTransitSheet: Binding(
                                get: {
                                    if case .transit = activeSheet { return true }
                                    return false
                                },
                                set: { isShowing in
                                    if !isShowing, case .transit = activeSheet {
                                        activeSheet = nil
                                    }
                                }
                            ),
                            selectedTransitStop: Binding(
                                get: {
                                    if case .transit(let stopId) = activeSheet { return stopId }
                                    return nil
                                },
                                set: { newStopId in
                                    if let stopId = newStopId {
                                        isNearbyBusesExpanded = false
                                        activeSheet = .transit(stopId: stopId)
                                    } else if case .transit = activeSheet {
                                        activeSheet = nil
                                    }
                                }
                            ),
                            isCentered: $isMapCentered,
                            recenterTrigger: $recenterTrigger,
                            userScreenPosition: $userScreenPosition,
                            targetCoordinate: $targetCoordinate,
                            currentUserLocation: $currentUserLocation,
                            transientHexShape: spatialStore.transientHexShape,
                            selectedTheme: currentTheme,
                            fogOpacity: effectiveFogOpacity,
                            showBoundaryBorders: showBoundaryBorders,
                            showSubwayThoroughfares: showSubwayThoroughfares,
                            subwayStationMarkerStyle: stationMarkerStyle,
                            nearbyBusStops: nearbyBusStops,
                            activeSignalCoordinate: activeNavigationSession?.activeSignalCoordinate,
                            activeInspectionCommand: activeRouteInspection,
                            activeSheetDetent: {
                                if case .transit = activeSheet { return activeTransitSheetDetent }
                                return nil
                            }(),
                            activeFloorLevel: activeFloorLevel,
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
                            },
                            onUpdateBeaconState: { beacon in
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    activeOffScreenBeacon = beacon
                                }
                            },
                            vehicleFrameRelay: vehicleFrameRelay)
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
                        HStack(alignment: .center, spacing: 10) {
                            SearchCapsuleOverlay {
                                activeSheet = .search
                            }
                            
                            AmbientDriftFAB(isTracking: trackingEngine.isTracking) {
                                activeSheet = .driftControls
                            }
                            
                            ProfileFAB {
                                activeSheet = .stats
                            }
                        }
                        .padding(.top, 50)
                        .padding(.horizontal, 20)
                        
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
                                        activeSheet = .transit(stopId: stop.id)
                                    },
                                    onRefresh: {
                                        scanNearbyBuses(force: true)
                                    }
                                )
                                .padding(.leading, 20)
                                .opacity(activeSheet == nil ? 1.0 : 0.0)
                                .allowsHitTesting(activeSheet == nil)
                                .animation(.easeInOut(duration: 0.2), value: activeSheet == nil)
                            }
                            
                            Spacer()
                            
                            RecenterFAB(isCentered: isMapCentered) {
                                recenterTrigger.toggle()
                                isMapCentered = true
                            }
                            .padding(.trailing, 20)
                            .opacity(activeSheet == nil ? 1.0 : 0.0)
                            .allowsHitTesting(activeSheet == nil)
                            .animation(.easeInOut(duration: 0.2), value: activeSheet == nil)
                        }
                        .padding(.bottom, 40)
                        .allowsHitTesting(activeSheet == nil)
                    }
                    
                    if let beacon = activeOffScreenBeacon, activeRouteInspection != nil {
                        OffScreenVectorBeacon(beacon: beacon) {
                            targetCoordinate = beacon.vehicleCoordinate
                            isMapCentered = false
                        }
                        .position(beacon.screenPosition)
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                        .zIndex(2)
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
                .onChange(of: cityDetectionService.promptCity) { _, newCity in
                    if let city = newCity {
                        activeSheet = .cityPrompt(city)
                    }
                }
                .onChange(of: activeNavigationItinerary) { _, newItin in
                    if let itin = newItin {
                        navigationManager.startTripNavigation(itinerary: itin)
                    }
                }
                .onChange(of: activeSheet) { oldSheet, newSheet in
                    if newSheet != nil {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            isNearbyBusesExpanded = false
                        }
                    }
                    if case .transit = oldSheet, newSheet == nil {
                        activeRouteInspection = nil
                        activeFloorLevel = nil
                        activeTransitSheetDetent = .medium
                    } else if case .navigation = oldSheet, newSheet == nil {
                        activeNavigationItinerary = nil
                        activeNavigationSession = nil
                        activeCyclingSession = nil
                        navigationManager.endNavigation()
                    } else if case .cityPrompt = oldSheet, newSheet == nil {
                        cityDetectionService.promptCity = nil
                    }
                }
                .sheet(item: $activeSheet) { sheet in
                    switch sheet {
                    case .cityPrompt(let city):
                        CityDownloadPromptSheet(
                            city: city,
                            onDownloadComplete: { installedCity in
                                cityDetectionService.markCityInstalled(installedCity.slug)
                                cityDetectionService.performAutoSwitch(to: installedCity)
                                activeSheet = nil
                            },
                            onDismiss: {
                                cityDetectionService.promptCity = nil
                                activeSheet = nil
                            },
                            onSnooze: { snoozedCity in
                                cityDetectionService.snoozeCity(slug: snoozedCity.slug)
                                activeSheet = nil
                            }
                        )
                        .presentationDetents([.fraction(0.38), .medium])
                        .presentationDragIndicator(.visible)
                        .presentationContentInteraction(.scrolls)
                        .transitSheetGlassBackground()
                        
                    case .transit(let stopId):
                        TransitRevealSheet(
                            stopId: stopId,
                            selectedDetent: $activeTransitSheetDetent,
                            onFocusMap: { coord in
                                targetCoordinate = coord
                                isMapCentered = false
                            },
                            onInspectRoute: { command in
                                activeRouteInspection = command
                            },
                            onClearRouteInspection: {
                                activeRouteInspection = nil
                            },
                            onSelectFloor: { floor in
                                activeFloorLevel = floor.ordinal
                            },
                            onDetentChange: { detent in
                                activeTransitSheetDetent = detent
                            },
                            onVehicleFrame: { coord, bearing in
                                vehicleFrameRelay.emit(coordinate: coord, bearing: bearing)
                            }
                        )
                        
                    case .search:
                        PlaceSearchView(
                            viewModel: SearchViewModel(
                                spatialDbManager: .shared,
                                initialLocation: currentUserLocation ?? trackingEngine.lastKnownLocation?.coordinate
                            ),
                            onSelectStation: { stopId, coord in
                                activeSheet = .transit(stopId: stopId)
                                if let c = coord {
                                    targetCoordinate = c
                                    isMapCentered = false
                                }
                            },
                            onSelectDestination: { routingLoc in
                                startRouteComparison(to: routingLoc)
                            },
                            onClose: {
                                activeSheet = nil
                            }
                        )
                        .presentationDetents([.large])
                        .presentationDragIndicator(.visible)
                        .presentationContentInteraction(.scrolls)
                        .transitSheetGlassBackground()
                        
                    case .routeComparison(let vm):
                        RouteComparisonListView(
                            viewModel: vm,
                            onStartNavigation: { itinerary in
                                activeNavigationItinerary = itinerary
                                activeSheet = .navigation(itinerary)
                                navigationDetent = NavigationSheetDetent.half.presentationDetent
                            },
                            onClose: {
                                activeSheet = nil
                            }
                        )
                        .presentationDetents([.fraction(0.50), .large])
                        .presentationDragIndicator(.visible)
                        .presentationContentInteraction(.scrolls)
                        .transitSheetGlassBackground()
                        
                    case .navigation(let itinerary):
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
                                activeSheet = nil
                                activeNavigationItinerary = nil
                                activeNavigationSession = nil
                                activeCyclingSession = nil
                                navigationManager.endNavigation()
                            }
                        )
                        
                    case .stats:
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
                        .transitSheetGlassBackground()
                        
                    case .driftControls:
                        AmbientDriftControlCard(trackingEngine: trackingEngine)
                            .presentationDetents([.height(340)])
                            .presentationDragIndicator(.visible)
                            .presentationContentInteraction(.scrolls)
                            .transitSheetGlassBackground()
                    }
                }
                .onOpenURL { url in
                    guard url.scheme == "derivee" else { return }
                    if url.host == "progress" {
                        activeSheet = nil
                        isMapCentered = true
                        recenterTrigger.toggle()
                        
                        glowScale = 1.0
                        glowOpacity = 0.8
                        withAnimation(.easeOut(duration: 1.5)) {
                            glowScale = 4.0
                            glowOpacity = 0.0
                        }
                    } else if url.host == "navigation" {
                        activeSheet = nil
                        if let itin = activeNavigationItinerary ?? navigationManager.itinerary {
                            activeSheet = .navigation(itin)
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
    
    // MARK: - Multimodal Route Comparison Navigation (Wave PA.4)
    
    private func startRouteComparison(to destination: RoutingLocation) {
        let originCoord = currentUserLocation ?? trackingEngine.lastKnownLocation?.coordinate ?? spatialStore.activeCityConfig.center.coordinate
        let origin = RoutingLocation.coordinate(latitude: originCoord.latitude, longitude: originCoord.longitude, name: "Current Location")
        
        let vm = RouteComparisonViewModel(planner: JourneyPlanner.shared)
        self.activeSheet = .routeComparison(vm)
        
        Task {
            await vm.searchJourneys(origin: origin, destination: destination)
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
        ComplexDepartureService.shared.prepareForCitySwap()
        activeSheet = nil
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
