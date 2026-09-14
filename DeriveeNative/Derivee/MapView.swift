import SwiftUI
import MapLibre
import GRDB
import CoreLocation
import QuartzCore

struct MapView: UIViewRepresentable {
    @Environment(\.colorScheme) var colorScheme
    @ObservedObject var trackingEngine: AmbientTrackingEngine
    var spatialStore: SpatialStore
    var fogShape: MLNShape?
    @Binding var showTransitSheet: Bool
    @Binding var selectedTransitStop: String?
    @Binding var isCentered: Bool
    @Binding var recenterTrigger: Bool
    @Binding var userScreenPosition: CGPoint?
    @Binding var targetCoordinate: CLLocationCoordinate2D?
    @Binding var currentUserLocation: CLLocationCoordinate2D?
    var transientHexShape: MLNShape?
    var selectedTheme: BasemapTheme = .day
    var fogOpacity: Double = MapCustomizationDefaults.defaultFogOpacity
    var showBoundaryBorders: Bool = MapCustomizationDefaults.defaultShowBoundaryBorders
    var showSubwayThoroughfares: Bool = MapCustomizationDefaults.defaultShowSubwayThoroughfares
    var subwayStationMarkerStyle: SubwayStationMarkerStyle = MapCustomizationDefaults.defaultSubwayStationMarkerStyle
    var enableMetalFogEngine: Bool = MapCustomizationDefaults.defaultEnableMetalFogEngine
    var nearbyBusStops: [SpatialDatabaseManager.NearbyBusStop] = []
    var activeSignalCoordinate: CLLocationCoordinate2D? = nil
    var activeInspectionCommand: RouteInspectionCommand? = nil
    var activeCorridorTelemetry: Data? = nil
    var activeFloorLevel: Int? = nil
    var onAmbientMapTap: (() -> Void)? = nil
    var onMapGesture: (() -> Void)? = nil
    
    // Bundled Composite Style URL with runtime key injection
    let styleURL = BasemapStyleLoader.styleURL
    
    func makeUIView(context: Context) -> MLNMapView {
        let mapView = MLNMapView(frame: .zero, styleURL: styleURL)
        mapView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        mapView.showsUserLocation = true
        mapView.showsUserHeadingIndicator = true
        mapView.allowsTilting = false
        mapView.minimumZoomLevel = 10.5
        mapView.setCenter(CLLocationCoordinate2D(latitude: 40.768075, longitude: -73.981897), zoomLevel: 16.0, animated: false)
        mapView.userTrackingMode = .followWithHeading
        mapView.delegate = context.coordinator
        
        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleMapTap(_:)))
        mapView.addGestureRecognizer(tapGesture)
        mapView.compassViewPosition = .bottomRight
        let bottomInset = mapView.safeAreaInsets.bottom > 0 ? mapView.safeAreaInsets.bottom : 34.0
        mapView.compassViewMargins = CGPoint(x: 20, y: 102 + bottomInset)
        mapView.compassView.image = ApertureCompassNeedle.makeNeedleImage()
        
        context.coordinator.mapView = mapView
        context.coordinator.cameraSynchronizer.attach(mapView: mapView)
        context.coordinator.cameraBridge.write(MapCameraState(mapView: mapView))
        context.coordinator.setupCompass()
        
        // Resume tracking if enabled
        DispatchQueue.main.async {
            self.trackingEngine.resumeTrackingIfNeeded()
        }
        
        return mapView
    }
    
    func updateUIView(_ uiView: MLNMapView, context: Context) {
        context.coordinator.parent = self
        
        if let currentCoord = currentUserLocation {
            context.coordinator.lastLocation = CLLocation(latitude: currentCoord.latitude, longitude: currentCoord.longitude)
        } else if let trackingLoc = trackingEngine.lastKnownLocation {
            context.coordinator.lastLocation = trackingLoc
        }
        
        // Wave L-D.3: Check if active city has changed and coordinate atomic viewport handshake
        if context.coordinator.lastAppliedCitySlug != spatialStore.activeCitySlug {
            context.coordinator.performCitySwitchHandshake(
                to: spatialStore.activeCityConfig,
                targetCenter: targetCoordinate,
                animated: false
            )
            if targetCoordinate != nil {
                DispatchQueue.main.async {
                    self.targetCoordinate = nil
                }
            }
        }
        
        context.coordinator.updateExploredHexes(in: uiView, with: fogShape)
        context.coordinator.updateTransientHex(shape: transientHexShape, in: uiView)
        context.coordinator.updateTransientPulse(at: spatialStore.newlyUnlockedHexLocation, in: uiView)
        context.coordinator.updateTransitSheetState(showSheet: showTransitSheet, selectedStop: selectedTransitStop, in: uiView)
        context.coordinator.updateRouteInspection(activeInspectionCommand, in: uiView)
        
        // Wave R.3: Real-Time Corridor Pulse Vehicle & Bunching Telemetry
        if let telemetry = activeCorridorTelemetry {
            context.coordinator.hasActiveCorridorTelemetry = true
            context.coordinator.corridorPulseController.updateTelemetry(geoJsonData: telemetry)
        } else if context.coordinator.hasActiveCorridorTelemetry {
            context.coordinator.hasActiveCorridorTelemetry = false
            context.coordinator.corridorPulseController.clearTelemetry()
        }
        
        // Wave Q.4: Runtime 2D Floorplan Level Filtering (Doc 15 & 20)
        if context.coordinator.lastAppliedFloorLevel != activeFloorLevel {
            context.coordinator.lastAppliedFloorLevel = activeFloorLevel
            if let floor = activeFloorLevel {
                context.coordinator.stationVisualizationManager.applyFloorFilter(level: floor)
            } else {
                context.coordinator.stationVisualizationManager.clearFloorFilter()
            }
        }
        
        if let style = uiView.style {
            context.coordinator.updateTheme(selectedTheme, in: style)
            context.coordinator.updateFogOpacity(fogOpacity, in: style)
            context.coordinator.updateBoundaryBorders(showBoundaryBorders, in: style)
            context.coordinator.updateSubwayThoroughfares(show: showSubwayThoroughfares, theme: selectedTheme, in: style)
            context.coordinator.updateSubwayStationBullets(style: subwayStationMarkerStyle, theme: selectedTheme, in: style)
            context.coordinator.updateNearbyBusStops(nearbyBusStops, in: style)
            context.coordinator.updatePOIs(in: style)
            context.coordinator.updateActiveSignalPin(at: activeSignalCoordinate, in: uiView)
        }
        
        let bottomInset = uiView.safeAreaInsets.bottom > 0 ? uiView.safeAreaInsets.bottom : (uiView.window?.safeAreaInsets.bottom ?? 34.0)
        let targetCompassMargins = CGPoint(x: 20, y: 102 + bottomInset)
        if uiView.compassViewMargins != targetCompassMargins {
            uiView.compassViewMargins = targetCompassMargins
        }
        
        if let target = targetCoordinate {
            uiView.setCenter(target, zoomLevel: 14.5, animated: true)
            DispatchQueue.main.async {
                self.targetCoordinate = nil
            }
        }
        
        if context.coordinator.lastRecenterTrigger != recenterTrigger {
            context.coordinator.lastRecenterTrigger = recenterTrigger
            uiView.setUserTrackingMode(.followWithHeading, animated: true, completionHandler: nil)
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    @MainActor
    class Coordinator: NSObject, MLNMapViewDelegate {
        var parent: MapView
        weak var mapView: MLNMapView?
        
        // Layer Identifiers
        let fogLayerId = "cloud-layer"
        let fogBorderLayerId = MapCustomizationDefaults.fogBorderLayerId
        let hexHolesLayerId = "hex-holes-layer"
        let poiSourceId = "poi-source"
        let lureLayerId = "poi-lure-layer"
        let activeLayerId = "poi-active-layer"
        let archiveLayerId = "poi-archive-layer"
        let ephemeralRouteCasingLayerId = "ephemeral-route-casing-layer"
        let ephemeralRouteLayerId = "ephemeral-route-layer"
        let ephemeralRouteSourceId = "ephemeral-route-source"
        let ephemeralVehicleSourceId = "ephemeral-vehicle-source"
        let ephemeralVehicleHaloLayerId = "ephemeral-vehicle-halo-layer"
        let ephemeralVehiclePuckLayerId = "ephemeral-vehicle-puck-layer"
        let ephemeralVehicleBearingLayerId = "ephemeral-vehicle-bearing-layer"
        let transientHexSourceId = "transient-hex-source"
        let transientHexLayerId = "transient-hex-layer"
        let pulseSourceId = "transient-pulse-source"
        let pulseLayerId = "transient-pulse-layer"
        let subwayLinesSourceId = MapCustomizationDefaults.subwayLinesSourceId
        let subwayLinesCasingLayerId = MapCustomizationDefaults.subwayLinesCasingLayerId
        let subwayLinesLayerId = MapCustomizationDefaults.subwayLinesLayerId
        let lrtLinesCasingLayerId = MapCustomizationDefaults.lrtLinesCasingLayerId
        let lrtLinesLayerId = MapCustomizationDefaults.lrtLinesLayerId
        let ferryLinesLayerId = MapCustomizationDefaults.ferryLinesLayerId
        let subwayStationBulletsSourceId = MapCustomizationDefaults.subwayStationBulletsSourceId
        let subwayStationBulletsLayerId = MapCustomizationDefaults.subwayStationBulletsLayerId
        let smartZoomStationBulletsLayerId = MapCustomizationDefaults.smartZoomStationBulletsLayerId
        let nearbyBusStopsSourceId = MapCustomizationDefaults.nearbyBusStopsSourceId
        let nearbyBusStopsLayerId = MapCustomizationDefaults.nearbyBusStopsLayerId
        let activeSignalSourceId = "active-signal-source"
        let activeSignalLayerId = "active-signal-layer"
        
        var pois: [GhostPOI] = []
        var lastLocation: CLLocation?
        var lastRecenterTrigger: Bool = false
        var lastTransientHexShape: MLNShape? = nil
        var lastPulseLocation: CLLocationCoordinate2D? = nil
        var lastActiveSignalCoord: CLLocationCoordinate2D? = nil
        var pulseTimer: DispatchWorkItem? = nil
        var lastSelectedStop: String? = nil
        var isMapStyleLoaded: Bool = false
        var lastAppliedTheme: BasemapTheme?
        var lastAppliedCitySlug: String? = nil
        var lastAppliedInspectionCommandId: UUID? = nil
        
        var lureTimer: Timer?
        var isLurePulsed: Bool = false
        var isRollingBack: Bool = false
        var metalFogLayer: MetalFogStyleLayer?
        
        // MARK: - Wave O.1: High-Precision Camera Bridge & VSync Synchronizer
        let cameraBridge = LockFreeCameraBridge()
        lazy var cameraSynchronizer: VSyncCameraSynchronizer = {
            let sync = VSyncCameraSynchronizer(cameraBridge: cameraBridge)
            if let mv = self.mapView {
                sync.attach(mapView: mv)
            }
            return sync
        }()
        
        // MARK: - Wave R.3: Corridor Pulse Real-Time Vehicle & Bunching Layers
        var hasActiveCorridorTelemetry: Bool = false
        lazy var corridorPulseController: CorridorPulseMapController = {
            let ctrl = CorridorPulseMapController(mapView: self.mapView)
            return ctrl
        }()
        
        // MARK: - Wave Q.3 / Q.4: Multi-Scale Station Transition Controller & Floor Filtering (Doc 20)
        var lastAppliedFloorLevel: Int? = nil
        lazy var stationVisualizationManager: StationTransitVisualizationManager = {
            let mgr = StationTransitVisualizationManager(mapView: self.mapView)
            return mgr
        }()
        
        init(_ parent: MapView) {
            self.parent = parent
            self.lastAppliedCitySlug = parent.spatialStore.activeCitySlug
            super.init()
            loadPOIs()
            
            NotificationCenter.default.addObserver(self, selector: #selector(appDidEnterBackground), name: UIApplication.didEnterBackgroundNotification, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(appWillEnterForeground), name: UIApplication.willEnterForegroundNotification, object: nil)
        }
        
        deinit {
            pulseTimer?.cancel()
            lureTimer?.invalidate()
            NotificationCenter.default.removeObserver(self)
        }
        
        // MARK: - Wave L-D.3: Viewport Handshake & Fog Cache Invalidation
        
        /// Executes an atomic, synchronous `@MainActor` viewport handshake when switching active metropolitan regions.
        /// Assigns a newly initialized `MLNShapeCollectionFeature` with fresh coordinate arrays to `fogSource.shape`,
        /// invalidating MapLibre's C++ GPU tessellation cache and preventing intermediate frame glitches.
        @MainActor
        func performCitySwitchHandshake(
            to config: CityConfig,
            targetCenter: CLLocationCoordinate2D? = nil,
            targetZoom: Double? = nil,
            animated: Bool = false
        ) {
            guard let mapView = self.mapView else { return }
            
            logPipeline("🤝 [WLD3 Viewport Handshake] Initiating atomic switch to \(config.displayName) (\(config.slug)) on @MainActor")
            
            // 1. Synchronously update CameraBounds configuration
            CameraBounds.setActiveConfig(config)
            self.lastAppliedCitySlug = config.slug
            
            // 2. Generate a fresh baseline MLNShapeCollectionFeature with new coordinate arrays
            // (Guarantees MapLibre C++ GPU tessellation cache invalidation for the global world bounding envelope)
            let freshFogFeature = FogPolygonMath.makeInitialFogShapeFeature()
            
            if let style = mapView.style {
                if let fogSource = style.source(withIdentifier: "fog-source") as? MLNShapeSource {
                    fogSource.shape = freshFogFeature
                    logPipeline("🌫️ [WLD3 Viewport Handshake] Assigned fresh global MLNShapeCollectionFeature to fog-source")
                }
                
                // 3. Update transit lines GeoJSON for the destination city
                updateTransitLines(for: config.slug, in: style)
                
                // 4. Reload station POIs and sub-fog station bullets for the destination city
                loadPOIs(for: config.slug)
            }
            
            if parent.enableMetalFogEngine {
                metalFogLayer?.resetCoverageTexture()
                metalFogLayer?.setNeedsDisplay()
            }
            
            // 5. Synchronously coordinate camera center to destination city center
            let center = targetCenter ?? config.center.coordinate
            let zoom = targetZoom ?? config.center.defaultZoom
            mapView.setCenter(center, zoomLevel: zoom, animated: animated)
            cameraBridge.write(MapCameraState(mapView: mapView))
            
            // 6. Reset transient state & animations
            lastTransientHexShape = nil
            lastPulseLocation = nil
            corridorPulseController.clearTelemetry()
            hasActiveCorridorTelemetry = false
            if let style = mapView.style, let pulseSource = style.source(withIdentifier: pulseSourceId) as? MLNShapeSource {
                pulseSource.shape = nil
            }
            if let style = mapView.style, let transSource = style.source(withIdentifier: transientHexSourceId) as? MLNShapeSource {
                transSource.shape = nil
            }
            
            logPipeline("✅ [WLD3 Viewport Handshake] Atomic switch to \(config.displayName) complete. Center=(\(center.latitude), \(center.longitude)), Zoom=\(zoom)")
        }
        
        func setupCompass() {
            guard let mapView = mapView else { return }
            mapView.compassViewPosition = .bottomRight
            let bottomInset = mapView.safeAreaInsets.bottom > 0 ? mapView.safeAreaInsets.bottom : (mapView.window?.safeAreaInsets.bottom ?? 34.0)
            mapView.compassViewMargins = CGPoint(x: 20, y: 102 + bottomInset)
            mapView.compassView.image = ApertureCompassNeedle.makeNeedleImage()
        }
        
        @objc func appDidEnterBackground() {
            lureTimer?.invalidate()
            lureTimer = nil
            mapView?.showsUserLocation = false
        }
        
        @objc func appWillEnterForeground() {
            startLureTimer()
            mapView?.showsUserLocation = true
            if parent.isCentered {
                mapView?.setUserTrackingMode(.followWithHeading, animated: false, completionHandler: nil)
            }
        }
        
        func startLureTimer() {
            guard lureTimer == nil else { return }
            lureTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
                self?.toggleLurePulse()
            }
        }
        
        func toggleLurePulse() {
            guard let style = mapView?.style, let lureLayer = style.layer(withIdentifier: lureLayerId) as? MLNCircleStyleLayer else { return }
            isLurePulsed.toggle()
            let radius: NSNumber = isLurePulsed ? 18.0 : 12.0
            let opacity: NSNumber = isLurePulsed ? 0.2 : 0.4
            lureLayer.circleRadius = NSExpression(forConstantValue: radius)
            lureLayer.circleOpacity = NSExpression(forConstantValue: opacity)
        }
        
        func loadPOIs(for citySlug: String? = nil) {
            Task {
                do {
                    let loadedPOIs = try await SpatialDatabaseManager.shared.dbWriter.read { db in
                        try SpatialDatabaseManager.shared.ensureTransitAttached(in: db)
                        let tableRows = try Row.fetchAll(db, sql: "PRAGMA transit.table_info(complexes)")
                        let hasComplexes = !tableRows.isEmpty
                        
                        let sql: String
                        if hasComplexes {
                            sql = """
                                SELECT 
                                    COALESCE(cx.complex_id, p.stop_id) AS group_id,
                                    CASE 
                                        WHEN cx.complex_id = 611 THEN 'Times Sq-42 St / 42 St-PABT'
                                        ELSE COALESCE(cx.complex_name, p.stop_name)
                                    END AS stop_name,
                                    COALESCE(cx.latitude, p.stop_lat) AS stop_lat,
                                    COALESCE(cx.longitude, p.stop_lon) AS stop_lon,
                                    MIN(p.stop_id) AS stop_id,
                                    COALESCE(GROUP_CONCAT(DISTINCT ch.routes), GROUP_CONCAT(DISTINCT p.routes), '') AS child_routes
                                FROM transit.stops p
                                LEFT JOIN transit.stop_resolution sr ON sr.parent_station_id = p.stop_id
                                LEFT JOIN transit.complexes cx ON cx.complex_id = sr.complex_id
                                LEFT JOIN transit.stops ch ON ch.parent_station = p.stop_id AND ch.routes IS NOT NULL AND ch.routes != ''
                                WHERE p.location_type = 1
                                GROUP BY COALESCE(cx.complex_id, p.stop_id)
                            """
                        } else {
                            sql = """
                                SELECT p.stop_id, p.stop_name, p.stop_lat, p.stop_lon,
                                       COALESCE(GROUP_CONCAT(DISTINCT c.routes), p.routes, '') AS child_routes
                                FROM transit.stops p
                                LEFT JOIN transit.stops c ON c.parent_station = p.stop_id AND c.routes IS NOT NULL AND c.routes != ''
                                WHERE p.location_type = 1
                                GROUP BY p.stop_id
                            """
                        }
                        
                        let rows = try Row.fetchAll(db, sql: sql)
                        return rows.map { row in
                            let lat: Double = row["stop_lat"]
                            let lon: Double = row["stop_lon"]
                            let id: String = row["stop_id"]
                            let name: String = row["stop_name"]
                            let childRoutes: String = row["child_routes"] ?? ""
                            let parsedRoutes = StationBulletRenderer.parseAndNormalizeRoutes(childRoutes)
                            let iconName = StationBulletRenderer.bulletIconIdentifier(for: parsedRoutes)
                            let h3 = POIMaskManager.computeH3Index(latitude: lat, longitude: lon)
                            return GhostPOI(
                                id: id,
                                name: name,
                                coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                                type: 1,
                                h3Index: h3,
                                routes: parsedRoutes,
                                bulletIconName: iconName
                            )
                        }
                    }
                    await MainActor.run {
                        self.pois = loadedPOIs
                        if let style = self.mapView?.style {
                            self.populateSubwayStationBullets(in: style)
                            self.updatePOIs(in: style)
                        }
                    }
                } catch {
                    print("⚠️ Transit POIs unavailable for \(citySlug ?? "active"): \(error)")
                    await MainActor.run {
                        self.pois = []
                        if let style = self.mapView?.style {
                            self.populateSubwayStationBullets(in: style)
                            self.updatePOIs(in: style)
                        }
                    }
                }
            }
        }
        
        func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
            isMapStyleLoaded = true
            cameraBridge.write(MapCameraState(mapView: mapView))
            let busDot = generateDotImage()
            let subwayDiamond = generateDiamondImage()
            style.setImage(busDot, forName: "poi-bus-3")
            style.setImage(subwayDiamond, forName: "poi-subway-1")
            
            stationVisualizationManager.attach(to: mapView)
            setupLayers(in: style)
            corridorPulseController.configureCorridorLayers(in: style)
            populateSubwayStationBullets(in: style)
            let initialTheme = parent.selectedTheme
            BasemapThemeManager.applyTheme(initialTheme, in: style, animated: false)
            lastAppliedTheme = initialTheme
            
            updateFogOpacity(parent.fogOpacity, in: style)
            updateBoundaryBorders(parent.showBoundaryBorders, in: style)
            updateSubwayThoroughfares(show: parent.showSubwayThoroughfares, theme: initialTheme, in: style)
            updateSubwayStationBullets(style: parent.subwayStationMarkerStyle, theme: initialTheme, in: style)
            updateNearbyBusStops(parent.nearbyBusStops, in: style)
            updatePOIs(in: style)
            updateExploredHexes(in: mapView, with: parent.spatialStore.currentFogShape)
            startLureTimer()
        }
        
        func generateDotImage() -> UIImage {
            let size = CGSize(width: 16, height: 16)
            return UIGraphicsImageRenderer(size: size).image { ctx in
                let rect = CGRect(origin: .zero, size: size)
                ctx.cgContext.setFillColor(UIColor(hex: "#FFB300").cgColor)
                ctx.cgContext.fillEllipse(in: rect)
            }
        }
        
        func generateDiamondImage() -> UIImage {
            let size = CGSize(width: 20, height: 20)
            return UIGraphicsImageRenderer(size: size).image { ctx in
                let rect = CGRect(origin: .zero, size: size)
                let path = UIBezierPath()
                path.move(to: CGPoint(x: rect.midX, y: rect.minY))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
                path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
                path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
                path.close()
                ctx.cgContext.setFillColor(UIColor(hex: "#FFB300").cgColor)
                ctx.cgContext.addPath(path.cgPath)
                ctx.cgContext.fillPath()
            }
        }
        
        func mapView(_ mapView: MLNMapView, didUpdate userLocation: MLNUserLocation?) {
            guard let location = userLocation?.location else { return }
            lastLocation = location
            DispatchQueue.main.async {
                if self.parent.currentUserLocation?.latitude != location.coordinate.latitude ||
                   self.parent.currentUserLocation?.longitude != location.coordinate.longitude {
                    self.parent.currentUserLocation = location.coordinate
                }
            }
            if let style = mapView.style {
                updatePOIs(in: style)
            }
        }
        
        func mapView(_ mapView: MLNMapView, didChange mode: MLNUserTrackingMode, animated: Bool) {
            DispatchQueue.main.async {
                self.parent.isCentered = (mode == .follow || mode == .followWithHeading)
            }
        }
        
        func mapView(_ mapView: MLNMapView, shouldChangeFrom oldCamera: MLNMapCamera, to newCamera: MLNMapCamera, reason: MLNCameraChangeReason) -> Bool {
            return CameraBounds.shouldAllowCameraChange(
                from: oldCamera,
                to: newCamera,
                reason: reason,
                isRollingBack: isRollingBack
            )
        }
        
        func mapView(_ mapView: MLNMapView, regionWillChangeWith reason: MLNCameraChangeReason, animated: Bool) {
            let isUserGesture = reason.contains(.gesturePan) ||
                                reason.contains(.gesturePinch) ||
                                reason.contains(.gestureRotate) ||
                                reason.contains(.gestureZoomIn) ||
                                reason.contains(.gestureZoomOut)
            if isUserGesture {
                DispatchQueue.main.async {
                    self.parent.onMapGesture?()
                }
            }
        }
        
        func mapViewRegionIsChanging(_ mapView: MLNMapView) {
            let state = MapCameraState(mapView: mapView)
            cameraBridge.write(state)
        }
        
        func mapView(_ mapView: MLNMapView, regionDidChangeWith reason: MLNCameraChangeReason, animated: Bool) {
            let currentCoord = mapView.centerCoordinate
            cameraBridge.write(MapCameraState(mapView: mapView))
            
            // If the camera came to rest outside the active bounding envelope, trigger a smooth easeOut rollback
            if !CameraBounds.isWithinBounds(currentCoord) && !isRollingBack {
                let clampedCoord = CameraBounds.clampedCoordinate(for: currentCoord)
                let currentCam = mapView.camera
                let rollbackCamera = MLNMapCamera(
                    lookingAtCenter: clampedCoord,
                    altitude: currentCam.altitude,
                    pitch: 0.0,
                    heading: currentCam.heading
                )
                
                isRollingBack = true
                mapView.setCamera(rollbackCamera, withDuration: 0.4, animationTimingFunction: CAMediaTimingFunction(name: .easeOut)) { [weak self] in
                    self?.isRollingBack = false
                }
            } else if isRollingBack && CameraBounds.isWithinBounds(currentCoord) {
                isRollingBack = false
            }
        }
        
        func setupLayers(in style: MLNStyle) {
            // 0. Multi-Modal Transit Thoroughfare Network (Sub-context Layers beneath the Fog of War)
            let subwaySource = MLNShapeSource(identifier: subwayLinesSourceId, shape: TransitCartographyLoader.loadTransitLinesShapeSync(), options: nil)
            style.addSource(subwaySource)
            
            let casingColor = UIColor(hex: "#FFFFFF")
            
            // 0a. Tier 4 — Maritime Ferry (2.5pt dashed cyan line over water)
            let ferryLinesLayer = MLNLineStyleLayer(identifier: ferryLinesLayerId, source: subwaySource)
            ferryLinesLayer.predicate = NSPredicate(format: "modal_class == 3")
            ferryLinesLayer.lineColor = Self.subwayLineColorExpression()
            ferryLinesLayer.lineWidth = NSExpression(forConstantValue: 2.5)
            ferryLinesLayer.lineDashPattern = NSExpression(forConstantValue: [4.0, 3.0])
            ferryLinesLayer.lineOpacity = NSExpression(forConstantValue: parent.showSubwayThoroughfares ? 0.90 : 0.0)
            ferryLinesLayer.lineCap = NSExpression(forConstantValue: "round")
            ferryLinesLayer.lineJoin = NSExpression(forConstantValue: "round")
            style.addLayer(ferryLinesLayer)
            
            // 0b. Tier 2 — Light Rail (LRT) Casing (6.0pt dashed casing to distinguish surface rail)
            let lrtCasingLayer = MLNLineStyleLayer(identifier: lrtLinesCasingLayerId, source: subwaySource)
            lrtCasingLayer.predicate = NSPredicate(format: "modal_class == 1")
            lrtCasingLayer.lineColor = NSExpression(forConstantValue: casingColor)
            lrtCasingLayer.lineWidth = NSExpression(forConstantValue: 6.0)
            lrtCasingLayer.lineDashPattern = NSExpression(forConstantValue: [3.0, 2.0])
            lrtCasingLayer.lineOpacity = NSExpression(forConstantValue: parent.showSubwayThoroughfares ? 0.75 : 0.0)
            lrtCasingLayer.lineCap = NSExpression(forConstantValue: "round")
            lrtCasingLayer.lineJoin = NSExpression(forConstantValue: "round")
            style.insertLayer(lrtCasingLayer, above: ferryLinesLayer)
            
            // 0c. Tier 2 — Light Rail (LRT) Line (4.0pt solid line)
            let lrtLinesLayer = MLNLineStyleLayer(identifier: lrtLinesLayerId, source: subwaySource)
            lrtLinesLayer.predicate = NSPredicate(format: "modal_class == 1")
            lrtLinesLayer.lineColor = Self.subwayLineColorExpression()
            lrtLinesLayer.lineWidth = NSExpression(forConstantValue: 4.0)
            lrtLinesLayer.lineOpacity = NSExpression(forConstantValue: parent.showSubwayThoroughfares ? 0.95 : 0.0)
            lrtLinesLayer.lineCap = NSExpression(forConstantValue: "round")
            lrtLinesLayer.lineJoin = NSExpression(forConstantValue: "round")
            style.insertLayer(lrtLinesLayer, above: lrtCasingLayer)
            
            // 0d. Tier 1 — Heavy Rail Subway & PATH Casing (6.0pt solid silver casing)
            let subwayCasingLayer = MLNLineStyleLayer(identifier: subwayLinesCasingLayerId, source: subwaySource)
            subwayCasingLayer.predicate = NSPredicate(format: "modal_class == 0")
            subwayCasingLayer.lineColor = NSExpression(forConstantValue: casingColor)
            subwayCasingLayer.lineWidth = NSExpression(forConstantValue: 6.0)
            subwayCasingLayer.lineOpacity = NSExpression(forConstantValue: parent.showSubwayThoroughfares ? 0.75 : 0.0)
            subwayCasingLayer.lineCap = NSExpression(forConstantValue: "round")
            subwayCasingLayer.lineJoin = NSExpression(forConstantValue: "round")
            style.insertLayer(subwayCasingLayer, above: lrtLinesLayer)
            
            // 0e. Tier 1 — Heavy Rail Subway & PATH Line (4.0pt solid line)
            let subwayLinesLayer = MLNLineStyleLayer(identifier: subwayLinesLayerId, source: subwaySource)
            subwayLinesLayer.predicate = NSPredicate(format: "modal_class == 0")
            subwayLinesLayer.lineColor = Self.subwayLineColorExpression()
            subwayLinesLayer.lineWidth = NSExpression(forConstantValue: 4.0)
            subwayLinesLayer.lineOpacity = NSExpression(forConstantValue: parent.showSubwayThoroughfares ? 0.95 : 0.0)
            subwayLinesLayer.lineCap = NSExpression(forConstantValue: "round")
            subwayLinesLayer.lineJoin = NSExpression(forConstantValue: "round")
            style.insertLayer(subwayLinesLayer, above: subwayCasingLayer)
            
            // Wave Q.3 / Q.4: Sub-Fog Station Footprints (Layer 3a) & Platforms (Layer 3b)
            stationVisualizationManager.configureSubFogLayers(in: style, citySlug: parent.spatialStore.activeCitySlug)
            if let floor = parent.activeFloorLevel {
                stationVisualizationManager.applyFloorFilter(level: floor)
            }
            
            // VERIFIED: MapLibre Native (iOS) initial fog shape requires CW winding order for exterior bounds.
            // Matches SpatialStore bounds order (Top-Left -> Top-Right -> Bottom-Right -> Bottom-Left -> Top-Left).
            // Tested & hardened in Wave I.2 (WI2-WINDING) & Wave M.5.1 (WM5.1-GLOBAL-FOG).
            let bounds = FogPolygonMath.makeWorldBounds(jitter: 0.000001)
            let initialFogShape = MLNPolygon(coordinates: bounds, count: UInt(bounds.count))
            
            let fogSource = MLNShapeSource(identifier: "fog-source", shape: initialFogShape, options: nil)
            style.addSource(fogSource)
            
            let fogLayer = MLNFillStyleLayer(identifier: fogLayerId, source: fogSource)
            let colorHex = "#1C1C1E"
            fogLayer.fillColor = NSExpression(forConstantValue: UIColor(hex: colorHex))
            fogLayer.fillOpacity = NSExpression(forConstantValue: parent.fogOpacity)
            
            let subFogAnchor = style.layer(withIdentifier: StationTransitVisualizationManager.Config.platformLayerId) ?? subwayLinesLayer
            style.insertLayer(fogLayer, above: subFogAnchor)
            
            // Wave O.3: Hardware-accelerated Metal Custom Style Layer
            if parent.enableMetalFogEngine {
                let metalFog = MetalFogStyleLayer(
                    identifier: MapCustomizationDefaults.metalFogLayerId,
                    spatialEngine: parent.spatialStore.spatialEngine
                )
                metalFog.fogOpacity = Float(parent.fogOpacity)
                self.metalFogLayer = metalFog
                
                // Research Doc 07 §3 Pattern A & Doc 20 §2:
                // Precise Z-Index Placement: Insert fog directly below MLNSymbolStyleLayer
                // (station bullets, basemap street/place labels, active POI symbols)
                // and strictly above sub-fog transit networks (platformLayer or subwayLinesLayer)
                if let firstSymbolLayer = style.layers.first(where: { $0 is MLNSymbolStyleLayer }) {
                    style.insertLayer(metalFog, below: firstSymbolLayer)
                } else {
                    style.insertLayer(metalFog, above: subFogAnchor)
                }
                
                // Suppress legacy CPU polygon fill when hardware Metal engine is active
                fogLayer.fillOpacity = NSExpression(forConstantValue: 0.0)
            }
            
            let borderLayer = MLNLineStyleLayer(identifier: fogBorderLayerId, source: fogSource)
            borderLayer.lineColor = NSExpression(forConstantValue: UIColor(hex: MapCustomizationDefaults.boundaryBorderColorHex))
            borderLayer.lineWidth = NSExpression(forConstantValue: MapCustomizationDefaults.boundaryBorderWidth)
            borderLayer.lineOpacity = NSExpression(forConstantValue: parent.showBoundaryBorders ? MapCustomizationDefaults.boundaryBorderOpacity : 0.0)
            borderLayer.lineJoin = NSExpression(forConstantValue: "round")
            borderLayer.lineCap = NSExpression(forConstantValue: "round")
            style.insertLayer(borderLayer, above: fogLayer)
            
            // Layer 6a: Station Macro Bullets (Orienting nodes ABOVE Fog of War - Doc 20 §2)
            let bulletsSource = MLNShapeSource(identifier: subwayStationBulletsSourceId, features: [], options: nil)
            style.addSource(bulletsSource)
            
            let bulletsLayer = MLNCircleStyleLayer(identifier: subwayStationBulletsLayerId, source: bulletsSource)
            let bulletFillColor = UIColor(hex: "#1C1C1E")
            let bulletStrokeColor = UIColor(hex: "#FFFFFF")
            bulletsLayer.circleColor = NSExpression(forConstantValue: bulletFillColor)
            bulletsLayer.circleRadius = StationTransitVisualizationManager.bulletRadiusExpression()
            bulletsLayer.circleStrokeColor = NSExpression(forConstantValue: bulletStrokeColor)
            bulletsLayer.circleStrokeWidth = NSExpression(forConstantValue: 1.0)
            bulletsLayer.circleOpacity = parent.subwayStationMarkerStyle == .allStations 
                ? StationTransitVisualizationManager.bulletOpacityExpression() 
                : NSExpression(forConstantValue: 0.0)
            bulletsLayer.circleStrokeOpacity = parent.subwayStationMarkerStyle == .allStations 
                ? StationTransitVisualizationManager.bulletStrokeOpacityExpression() 
                : NSExpression(forConstantValue: 0.0)
            bulletsLayer.circleOpacityTransition = MLNTransition(duration: 0, delay: 0)
            style.insertLayer(bulletsLayer, above: borderLayer)
            
            // Smart Zoom Station Bullets Layer (z >= 14.5): Resolves discrete route bullets ([4][5][6] vs [6])
            let smartZoomBulletsLayer = MLNSymbolStyleLayer(identifier: smartZoomStationBulletsLayerId, source: bulletsSource)
            smartZoomBulletsLayer.minimumZoomLevel = 14.5
            smartZoomBulletsLayer.iconImageName = NSExpression(forKeyPath: "bullet_icon_name")
            smartZoomBulletsLayer.iconAllowsOverlap = NSExpression(forConstantValue: false)
            smartZoomBulletsLayer.iconIgnoresPlacement = NSExpression(forConstantValue: false)
            smartZoomBulletsLayer.iconAnchor = NSExpression(forConstantValue: "bottom")
            smartZoomBulletsLayer.iconOffset = NSExpression(forConstantValue: NSValue(cgVector: CGVector(dx: 0, dy: -6)))
            smartZoomBulletsLayer.iconOpacity = parent.subwayStationMarkerStyle == .allStations 
                ? StationTransitVisualizationManager.smartZoomBulletOpacityExpression() 
                : NSExpression(forConstantValue: 0.0)
            smartZoomBulletsLayer.iconOpacityTransition = MLNTransition(duration: 0.2, delay: 0)
            style.insertLayer(smartZoomBulletsLayer, above: bulletsLayer)
            
            // Layer 6b: Egress Portals (station-exit-symbols) positioned above bulletsLayer (Doc 20 §2)
            stationVisualizationManager.setupExitPortalLayer(in: style, above: smartZoomBulletsLayer)
            
            let transientHexSource = MLNShapeSource(identifier: transientHexSourceId, shape: nil, options: nil)
            style.addSource(transientHexSource)
            
            let transientHexLayer = MLNFillStyleLayer(identifier: transientHexLayerId, source: transientHexSource)
            transientHexLayer.fillColor = NSExpression(forConstantValue: UIColor(hex: colorHex))
            transientHexLayer.fillOpacity = NSExpression(forConstantValue: 0.0)
            let topStationLayer = style.layer(withIdentifier: StationTransitVisualizationManager.Config.exitLayerId) ?? smartZoomBulletsLayer
            style.insertLayer(transientHexLayer, above: topStationLayer)
            
            let pulseSource = MLNShapeSource(identifier: pulseSourceId, shape: nil, options: nil)
            style.addSource(pulseSource)
            
            let pulseLayer = MLNCircleStyleLayer(identifier: pulseLayerId, source: pulseSource)
            pulseLayer.circleColor = NSExpression(forConstantValue: UIColor(hex: "#FFB300"))
            pulseLayer.circleRadius = NSExpression(forConstantValue: 0.0)
            pulseLayer.circleOpacity = NSExpression(forConstantValue: 0.0)
            pulseLayer.circlePitchAlignment = NSExpression(forConstantValue: "map")
            style.insertLayer(pulseLayer, above: transientHexLayer)
            
            // Layer 4: Ephemeral Route Inspection (ephemeral-route-source)
            let routeSource = MLNShapeSource(identifier: ephemeralRouteSourceId, shape: nil, options: nil)
            style.addSource(routeSource)
            
            let routeCasingLayer = MLNLineStyleLayer(identifier: ephemeralRouteCasingLayerId, source: routeSource)
            routeCasingLayer.lineColor = NSExpression(forConstantValue: UIColor(hex: "#FFFFFF"))
            routeCasingLayer.lineWidth = NSExpression(forConstantValue: 6.0)
            routeCasingLayer.lineOpacity = NSExpression(forConstantValue: 0.0)
            routeCasingLayer.lineCap = NSExpression(forConstantValue: "round")
            routeCasingLayer.lineJoin = NSExpression(forConstantValue: "round")
            routeCasingLayer.lineOpacityTransition = MLNTransition(duration: 0.25, delay: 0)
            style.insertLayer(routeCasingLayer, above: pulseLayer)
            
            let routeLayer = MLNLineStyleLayer(identifier: ephemeralRouteLayerId, source: routeSource)
            routeLayer.lineColor = NSExpression(forConstantValue: UIColor(hex: "#FFB300"))
            routeLayer.lineWidth = NSExpression(forConstantValue: 4.0)
            routeLayer.lineOpacity = NSExpression(forConstantValue: 0.0)
            routeLayer.lineCap = NSExpression(forConstantValue: "round")
            routeLayer.lineJoin = NSExpression(forConstantValue: "round")
            routeLayer.lineOpacityTransition = MLNTransition(duration: 0.25, delay: 0)
            style.insertLayer(routeLayer, above: routeCasingLayer)
            
            // Nearby Bus Stops Source & Layer (Clustered to eliminate overlapping grapes at transit hubs)
            let busStopsSource = MLNShapeSource(
                identifier: nearbyBusStopsSourceId,
                features: [],
                options: [
                    .clustered: true,
                    .clusterRadius: 30
                ]
            )
            style.addSource(busStopsSource)
            
            let busStopsLayer = MLNCircleStyleLayer(identifier: nearbyBusStopsLayerId, source: busStopsSource)
            busStopsLayer.circleColor = NSExpression(forConstantValue: UIColor(hex: "#00A1DE"))
            busStopsLayer.circleRadius = NSExpression(forConstantValue: 6.0)
            busStopsLayer.circleStrokeColor = NSExpression(forConstantValue: UIColor.white)
            busStopsLayer.circleStrokeWidth = NSExpression(forConstantValue: 1.5)
            busStopsLayer.circleOpacity = NSExpression(forConstantValue: 0.95)
            busStopsLayer.circleOpacityTransition = MLNTransition(duration: 0.2, delay: 0)
            style.insertLayer(busStopsLayer, above: routeLayer)
            
            let source = MLNShapeSource(identifier: poiSourceId, features: [], options: nil)
            style.addSource(source)
            
            let lureLayer = MLNCircleStyleLayer(identifier: lureLayerId, source: source)
            lureLayer.predicate = NSPredicate(format: "phase == 1")
            lureLayer.circleColor = NSExpression(forConstantValue: UIColor(hex: "#FFB300"))
            lureLayer.circleRadius = NSExpression(forConstantValue: 15)
            lureLayer.circleOpacity = NSExpression(forConstantValue: 0.3)
            lureLayer.circleBlur = NSExpression(forConstantValue: 2.0)
            lureLayer.circleRadiusTransition = MLNTransition(duration: 1.5, delay: 0)
            lureLayer.circleOpacityTransition = MLNTransition(duration: 1.5, delay: 0)
            style.insertLayer(lureLayer, above: fogLayer)
            
            let activeLayer = MLNSymbolStyleLayer(identifier: activeLayerId, source: source)
            activeLayer.predicate = NSPredicate(format: "phase == 2")
            activeLayer.iconImageName = NSExpression(forKeyPath: "icon_name")
            activeLayer.iconScale = NSExpression(forConstantValue: 1.0)
            activeLayer.iconAllowsOverlap = NSExpression(forConstantValue: true)
            activeLayer.iconIgnoresPlacement = NSExpression(forConstantValue: true)
            style.insertLayer(activeLayer, above: lureLayer)
            
            let archiveLayer = MLNCircleStyleLayer(identifier: archiveLayerId, source: source)
            archiveLayer.predicate = NSPredicate(format: "phase == 3")
            archiveLayer.circleColor = NSExpression(forConstantValue: UIColor(hex: "#FFB300"))
            archiveLayer.circleRadius = NSExpression(forConstantValue: 4.5)
            archiveLayer.circleStrokeColor = NSExpression(forConstantValue: UIColor.white)
            archiveLayer.circleStrokeWidth = NSExpression(forConstantValue: 1.0)
            archiveLayer.circleOpacity = NSExpression(forConstantValue: 0.85)
            archiveLayer.minimumZoomLevel = 11.0
            style.insertLayer(archiveLayer, above: activeLayer)
            
            // Ephemeral Active Traffic Signal Pin (Wave N-D.6.1)
            let signalSource = MLNShapeSource(identifier: activeSignalSourceId, shape: nil, options: nil)
            style.addSource(signalSource)
            
            let signalLayer = MLNCircleStyleLayer(identifier: activeSignalLayerId, source: signalSource)
            signalLayer.circleColor = NSExpression(forConstantValue: UIColor(hex: "#FFB300"))
            signalLayer.circleRadius = NSExpression(forConstantValue: 6.5)
            signalLayer.circleStrokeColor = NSExpression(forConstantValue: UIColor.white)
            signalLayer.circleStrokeWidth = NSExpression(forConstantValue: 2.0)
            signalLayer.circleOpacity = NSExpression(forConstantValue: 1.0)
            style.insertLayer(signalLayer, above: archiveLayer)
            
            // Suppress commercial/park vector POIs & base stations in favor of subway POIs
            POIMaskManager.configureBaseVectorLayers(in: style)
        }
        
        nonisolated static func subwayLineColorExpression() -> NSExpression {
            return NSExpression(forKeyPath: "color")
        }
        
        func updateTransitLines(for citySlug: String? = nil, in style: MLNStyle) {
            guard isMapStyleLoaded, let source = style.source(withIdentifier: subwayLinesSourceId) as? MLNShapeSource else { return }
            Task { @MainActor [weak source] in
                let shape = await TransitCartographyLoader.loadTransitLinesShape(for: citySlug)
                source?.shape = shape
            }
            stationVisualizationManager.updateStationShapes(for: citySlug, in: style)
        }
        
        func updateSubwayThoroughfares(show: Bool, theme: BasemapTheme, in style: MLNStyle) {
            guard isMapStyleLoaded else { return }
            let casingColor = UIColor(hex: "#FFFFFF")
            
            if let subwayCasing = style.layer(withIdentifier: subwayLinesCasingLayerId) as? MLNLineStyleLayer {
                subwayCasing.lineColor = NSExpression(forConstantValue: casingColor)
                subwayCasing.lineOpacity = NSExpression(forConstantValue: show ? 0.75 : 0.0)
            }
            if let subwayLines = style.layer(withIdentifier: subwayLinesLayerId) as? MLNLineStyleLayer {
                subwayLines.lineOpacity = NSExpression(forConstantValue: show ? 0.95 : 0.0)
            }
            if let lrtCasing = style.layer(withIdentifier: lrtLinesCasingLayerId) as? MLNLineStyleLayer {
                lrtCasing.lineColor = NSExpression(forConstantValue: casingColor)
                lrtCasing.lineOpacity = NSExpression(forConstantValue: show ? 0.75 : 0.0)
            }
            if let lrtLines = style.layer(withIdentifier: lrtLinesLayerId) as? MLNLineStyleLayer {
                lrtLines.lineOpacity = NSExpression(forConstantValue: show ? 0.95 : 0.0)
            }
            if let ferryLines = style.layer(withIdentifier: ferryLinesLayerId) as? MLNLineStyleLayer {
                ferryLines.lineOpacity = NSExpression(forConstantValue: show ? 0.90 : 0.0)
            }
        }
        
        func updateSubwayStationBullets(style markerStyle: SubwayStationMarkerStyle, theme: BasemapTheme, in style: MLNStyle) {
            guard isMapStyleLoaded else { return }
            if let bulletsLayer = style.layer(withIdentifier: subwayStationBulletsLayerId) as? MLNCircleStyleLayer {
                let bulletFillColor = UIColor(hex: "#1C1C1E")
                let bulletStrokeColor = UIColor(hex: "#FFFFFF")
                bulletsLayer.circleColor = NSExpression(forConstantValue: bulletFillColor)
                bulletsLayer.circleStrokeColor = NSExpression(forConstantValue: bulletStrokeColor)
                bulletsLayer.circleOpacityTransition = MLNTransition(duration: 0, delay: 0)
                bulletsLayer.circleOpacity = markerStyle == .allStations 
                    ? StationTransitVisualizationManager.bulletOpacityExpression() 
                    : NSExpression(forConstantValue: 0.0)
                bulletsLayer.circleRadius = StationTransitVisualizationManager.bulletRadiusExpression()
                bulletsLayer.circleStrokeOpacity = markerStyle == .allStations 
                    ? StationTransitVisualizationManager.bulletStrokeOpacityExpression() 
                    : NSExpression(forConstantValue: 0.0)
            }
            if let smartZoomLayer = style.layer(withIdentifier: smartZoomStationBulletsLayerId) as? MLNSymbolStyleLayer {
                smartZoomLayer.iconOpacityTransition = MLNTransition(duration: 0, delay: 0)
                smartZoomLayer.iconOpacity = markerStyle == .allStations 
                    ? StationTransitVisualizationManager.smartZoomBulletOpacityExpression() 
                    : NSExpression(forConstantValue: 0.0)
            }
        }
        
        func populateSubwayStationBullets(in style: MLNStyle) {
            guard let bulletsSource = style.source(withIdentifier: subwayStationBulletsSourceId) as? MLNShapeSource else { return }
            
            // Pre-render and register composite multi-route bullet images into MLNStyle
            var registeredIcons = Set<String>()
            for poi in pois where !poi.routes.isEmpty {
                let iconName = poi.bulletIconName
                if !registeredIcons.contains(iconName) && style.image(forName: iconName) == nil {
                    let img = StationBulletRenderer.renderCompositeBulletImage(routes: poi.routes)
                    style.setImage(img, forName: iconName)
                    registeredIcons.insert(iconName)
                }
            }
            
            var features: [MLNPointFeature] = []
            for poi in pois {
                let feature = MLNPointFeature()
                feature.coordinate = poi.coordinate
                feature.attributes = [
                    "id": poi.id,
                    "name": poi.name,
                    "type": poi.type,
                    "bullet_icon_name": poi.bulletIconName,
                    "routes_count": poi.routes.count,
                    "routes_label": poi.routes.joined(separator: " • ")
                ]
                features.append(feature)
            }
            bulletsSource.shape = MLNShapeCollectionFeature(shapes: features)
        }
        
        func updateNearbyBusStops(_ stops: [SpatialDatabaseManager.NearbyBusStop], in style: MLNStyle) {
            guard isMapStyleLoaded, let source = style.source(withIdentifier: nearbyBusStopsSourceId) as? MLNShapeSource else { return }
            
            var features: [MLNPointFeature] = []
            for stop in stops {
                let feature = MLNPointFeature()
                feature.coordinate = stop.coordinate
                feature.attributes = [
                    "id": stop.id,
                    "name": stop.name,
                    "type": 3,
                    "phase": 2
                ]
                features.append(feature)
            }
            source.shape = MLNShapeCollectionFeature(shapes: features)
        }
        
        func updateTheme(_ theme: BasemapTheme, in style: MLNStyle) {
            guard isMapStyleLoaded else { return }
            if lastAppliedTheme != theme {
                lastAppliedTheme = theme
                BasemapThemeManager.applyTheme(theme, in: style, animated: true)
                updateSubwayThoroughfares(show: parent.showSubwayThoroughfares, theme: theme, in: style)
                updateSubwayStationBullets(style: parent.subwayStationMarkerStyle, theme: theme, in: style)
            }
        }
        
        func updateFogOpacity(_ opacity: Double, in style: MLNStyle) {
            guard isMapStyleLoaded else { return }
            if parent.enableMetalFogEngine {
                metalFogLayer?.fogOpacity = Float(opacity)
                metalFogLayer?.setNeedsDisplay()
            } else if let fogLayer = style.layer(withIdentifier: fogLayerId) as? MLNFillStyleLayer {
                fogLayer.fillOpacityTransition = MLNTransition(duration: 0, delay: 0)
                fogLayer.fillOpacity = NSExpression(forConstantValue: opacity)
            }
        }
        
        func updateBoundaryBorders(_ show: Bool, in style: MLNStyle) {
            guard isMapStyleLoaded else { return }
            if let borderLayer = style.layer(withIdentifier: fogBorderLayerId) as? MLNLineStyleLayer {
                borderLayer.lineOpacityTransition = MLNTransition(duration: 0, delay: 0)
                borderLayer.lineOpacity = NSExpression(forConstantValue: show ? MapCustomizationDefaults.boundaryBorderOpacity : 0.0)
            }
        }
        
        func updateExploredHexes(in mapView: MLNMapView, with shape: MLNShape?) {
            // Wave O.3 & O.4: Update coverage texture and invalidate Metal fog style layer
            if parent.enableMetalFogEngine, let metalLayer = metalFogLayer {
                let coords = parent.spatialStore.getExploredCoordinates()
                if !coords.isEmpty {
                    metalLayer.updateCoverage(from: coords)
                } else {
                    metalLayer.resetCoverageTexture()
                }
                metalLayer.setNeedsDisplay()
            }
            
            let interiorCount: Int
            if let poly = shape as? MLNPolygon {
                interiorCount = poly.interiorPolygons?.count ?? 0
            } else if let collection = shape as? MLNShapeCollection, let poly = collection.shapes.first as? MLNPolygon {
                interiorCount = poly.interiorPolygons?.count ?? 0
            } else {
                interiorCount = 0
            }
            logPipeline("📍 [S6 - updateExploredHexes] ENTER shape=\(shape != nil ? "present" : "nil"), interiorCount=\(interiorCount), isMapStyleLoaded=\(isMapStyleLoaded)")
            guard let style = mapView.style, let fogSource = style.source(withIdentifier: "fog-source") as? MLNShapeSource else {
                logPipeline("📍 [S6 - updateExploredHexes] fog-source or style not ready yet")
                return
            }
            let previousShape = fogSource.shape as? MLNPolygon
            let isTransitioningFromInitial = previousShape?.interiorPolygons == nil
            
            if let validShape = shape {
                fogSource.shape = validShape
                if isMapStyleLoaded, isTransitioningFromInitial {
                    print("✅ Deferred fog shape applied (\(interiorCount) holes)")
                }
            } else if isMapStyleLoaded {
                let freshFogFeature = FogPolygonMath.makeInitialFogShapeFeature()
                fogSource.shape = freshFogFeature
                logPipeline("🌫️ [updateExploredHexes] Reset fog-source to full solid baseline world fog shape")
            }
        }
        
        func updateTransientHex(shape: MLNShape?, in mapView: MLNMapView) {
            guard let style = mapView.style, 
                  let source = style.source(withIdentifier: transientHexSourceId) as? MLNShapeSource, 
                  let layer = style.layer(withIdentifier: transientHexLayerId) as? MLNFillStyleLayer else { return }
            
            if shape !== lastTransientHexShape {
                lastTransientHexShape = shape
                
                if let newShape = shape {
                    layer.fillOpacityTransition = MLNTransition(duration: 0, delay: 0)
                    layer.fillOpacity = NSExpression(forConstantValue: 0.3)
                    source.shape = newShape
                    
                    if let loc = lastLocation {
                        let point = mapView.convert(loc.coordinate, toPointTo: mapView)
                        DispatchQueue.main.async {
                            self.parent.userScreenPosition = point
                        }
                    }
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        layer.fillOpacityTransition = MLNTransition(duration: 1.5, delay: 0)
                        layer.fillOpacity = NSExpression(forConstantValue: 0.0)
                    }
                }
            }
        }
        
        func updateTransientPulse(at location: CLLocationCoordinate2D?, in mapView: MLNMapView) {
            guard let coord = location else { return }
            guard let style = mapView.style,
                  let source = style.source(withIdentifier: pulseSourceId) as? MLNShapeSource,
                  let layer = style.layer(withIdentifier: pulseLayerId) as? MLNCircleStyleLayer else { return }
            
            if lastPulseLocation?.latitude != coord.latitude || lastPulseLocation?.longitude != coord.longitude {
                lastPulseLocation = coord
                
                let feature = MLNPointFeature()
                feature.coordinate = coord
                source.shape = feature
                
                layer.circleRadiusTransition = MLNTransition(duration: 0, delay: 0)
                layer.circleOpacityTransition = MLNTransition(duration: 0, delay: 0)
                layer.circleRadius = NSExpression(forConstantValue: 0.0)
                layer.circleOpacity = NSExpression(forConstantValue: 0.8)
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { [weak mapView, weak self] in
                    guard let activeStyle = mapView?.style,
                          let activeLayer = activeStyle.layer(withIdentifier: self?.pulseLayerId ?? "") as? MLNCircleStyleLayer else { return }
                    activeLayer.circleRadiusTransition = MLNTransition(duration: 1.2, delay: 0)
                    activeLayer.circleOpacityTransition = MLNTransition(duration: 1.2, delay: 0)
                    activeLayer.circleRadius = NSExpression(forConstantValue: 80.0)
                    activeLayer.circleOpacity = NSExpression(forConstantValue: 0.0)
                }
                
                pulseTimer?.cancel()
                let workItem = DispatchWorkItem { [weak mapView, weak self] in
                    guard let activeStyle = mapView?.style,
                          let activeSource = activeStyle.source(withIdentifier: self?.pulseSourceId ?? "") as? MLNShapeSource else { return }
                    activeSource.shape = nil
                }
                pulseTimer = workItem
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.3, execute: workItem)
            }
        }
        
        func updateActiveSignalPin(at location: CLLocationCoordinate2D?, in mapView: MLNMapView) {
            guard let style = mapView.style,
                  let source = style.source(withIdentifier: activeSignalSourceId) as? MLNShapeSource else { return }
            
            if let coord = location {
                if lastActiveSignalCoord?.latitude != coord.latitude || lastActiveSignalCoord?.longitude != coord.longitude {
                    lastActiveSignalCoord = coord
                    let feature = MLNPointFeature()
                    feature.coordinate = coord
                    source.shape = feature
                }
            } else {
                if lastActiveSignalCoord != nil {
                    lastActiveSignalCoord = nil
                    source.shape = nil
                }
            }
        }
        
        func updateTransitSheetState(showSheet: Bool, selectedStop: String?, in mapView: MLNMapView) {
            if !showSheet {
                lastSelectedStop = nil
            } else if let stopId = selectedStop {
                lastSelectedStop = stopId
            }
        }
        
        // MARK: - Wave PA.5: Synchronized Map Camera + Route Polyline for Inspectors
        
        /// Updates the Layer 4 Ephemeral Route Inspection polyline and casing through the fog.
        /// Dispatched from Run Inspectors via closure-based map commands.
        func updateRouteInspection(_ command: RouteInspectionCommand?, in mapView: MLNMapView) {
            guard let style = mapView.style else { return }
            
            if let cmd = command {
                if lastAppliedInspectionCommandId != cmd.id {
                    lastAppliedInspectionCommandId = cmd.id
                    
                    // 1. Resolve or create shape source
                    let source: MLNShapeSource
                    if let existingSource = style.source(withIdentifier: ephemeralRouteSourceId) as? MLNShapeSource {
                        source = existingSource
                    } else {
                        let newSource = MLNShapeSource(identifier: ephemeralRouteSourceId, shape: nil, options: nil)
                        style.addSource(newSource)
                        source = newSource
                    }
                    
                    // 2. Assign polyline geometry
                    if !cmd.coordinates.isEmpty {
                        let polyline = MLNPolyline(coordinates: cmd.coordinates, count: UInt(cmd.coordinates.count))
                        source.shape = polyline
                    } else {
                        source.shape = nil
                    }
                    
                    // 3. Dual-layer casing technique (6px outline) positioned in Layer 4
                    let casingLayer: MLNLineStyleLayer
                    if let existingCasing = style.layer(withIdentifier: ephemeralRouteCasingLayerId) as? MLNLineStyleLayer {
                        casingLayer = existingCasing
                    } else {
                        let newCasing = MLNLineStyleLayer(identifier: ephemeralRouteCasingLayerId, source: source)
                        newCasing.lineCap = NSExpression(forConstantValue: "round")
                        newCasing.lineJoin = NSExpression(forConstantValue: "round")
                        newCasing.lineOpacityTransition = MLNTransition(duration: 0.25, delay: 0)
                        
                        if let busStops = style.layer(withIdentifier: nearbyBusStopsLayerId) {
                            style.insertLayer(newCasing, below: busStops)
                        } else if let lure = style.layer(withIdentifier: lureLayerId) {
                            style.insertLayer(newCasing, below: lure)
                        } else if let pulse = style.layer(withIdentifier: pulseLayerId) {
                            style.insertLayer(newCasing, above: pulse)
                        } else if let fog = style.layer(withIdentifier: fogLayerId) {
                            style.insertLayer(newCasing, above: fog)
                        } else {
                            style.addLayer(newCasing)
                        }
                        casingLayer = newCasing
                    }
                    
                    casingLayer.lineColor = NSExpression(forConstantValue: cmd.casingColor)
                    casingLayer.lineWidth = NSExpression(forConstantValue: 6.0)
                    casingLayer.lineOpacity = NSExpression(forConstantValue: 0.80)
                    
                    // 4. Primary colored route line (4px stroke in agency official color)
                    let routeLayer: MLNLineStyleLayer
                    if let existingRoute = style.layer(withIdentifier: ephemeralRouteLayerId) as? MLNLineStyleLayer {
                        routeLayer = existingRoute
                    } else {
                        let newRoute = MLNLineStyleLayer(identifier: ephemeralRouteLayerId, source: source)
                        newRoute.lineCap = NSExpression(forConstantValue: "round")
                        newRoute.lineJoin = NSExpression(forConstantValue: "round")
                        newRoute.lineOpacityTransition = MLNTransition(duration: 0.25, delay: 0)
                        style.insertLayer(newRoute, above: casingLayer)
                        routeLayer = newRoute
                    }
                    
                    routeLayer.lineColor = NSExpression(forConstantValue: cmd.agencyColor)
                    routeLayer.lineWidth = NSExpression(forConstantValue: 4.0)
                    routeLayer.lineOpacity = NSExpression(forConstantValue: 0.95)
                    
                    // Maritime Ferries render with dashed line pattern [4.0, 3.0]
                    if cmd.isDashed {
                        routeLayer.lineDashPattern = NSExpression(forConstantValue: [4.0, 3.0])
                    } else {
                        routeLayer.lineDashPattern = nil
                    }
                    
                    // 5. Ephemeral Vehicle Tracking (Task PC.1 / WPC1: "Where Is My Train")
                    if let vehicleCoord = cmd.vehicleCoordinate {
                        let vehicleSource: MLNShapeSource
                        if let existingVehicleSource = style.source(withIdentifier: ephemeralVehicleSourceId) as? MLNShapeSource {
                            vehicleSource = existingVehicleSource
                        } else {
                            let newSource = MLNShapeSource(identifier: ephemeralVehicleSourceId, shape: nil, options: nil)
                            style.addSource(newSource)
                            vehicleSource = newSource
                        }
                        
                        let vehicleFeature = MLNPointFeature()
                        vehicleFeature.coordinate = vehicleCoord
                        vehicleFeature.attributes = [
                            "color": cmd.agencyColorHex,
                            "bearing": cmd.vehicleBearing ?? 0.0,
                            "has_bearing": (cmd.vehicleBearing != nil)
                        ]
                        vehicleSource.shape = vehicleFeature
                        
                        if style.image(forName: CorridorPulseMapController.Config.bearingArrowImageName) == nil {
                            style.setImage(CorridorPulseMapController.makeBearingArrowImage(), forName: CorridorPulseMapController.Config.bearingArrowImageName)
                        }
                        
                        // Halo Layer (breathing pulsing halo)
                        let haloLayer: MLNCircleStyleLayer
                        if let existingHalo = style.layer(withIdentifier: ephemeralVehicleHaloLayerId) as? MLNCircleStyleLayer {
                            haloLayer = existingHalo
                        } else {
                            let newHalo = MLNCircleStyleLayer(identifier: ephemeralVehicleHaloLayerId, source: vehicleSource)
                            newHalo.circlePitchAlignment = NSExpression(forConstantValue: "map")
                            newHalo.circleOpacityTransition = MLNTransition(duration: 0.25, delay: 0)
                            style.insertLayer(newHalo, above: routeLayer)
                            haloLayer = newHalo
                        }
                        haloLayer.circleColor = NSExpression(forConstantValue: cmd.agencyColor)
                        haloLayer.circleRadius = NSExpression(
                            forMLNInterpolating: NSExpression.zoomLevelVariable,
                            curveType: .linear,
                            parameters: nil,
                            stops: NSExpression(forConstantValue: [
                                11: 14.0,
                                14: 20.0,
                                17: 30.0
                            ])
                        )
                        haloLayer.circleOpacity = NSExpression(forConstantValue: 0.40)
                        
                        // Puck Layer (solid circle with high-contrast 2.5pt stroke)
                        let puckLayer: MLNCircleStyleLayer
                        if let existingPuck = style.layer(withIdentifier: ephemeralVehiclePuckLayerId) as? MLNCircleStyleLayer {
                            puckLayer = existingPuck
                        } else {
                            let newPuck = MLNCircleStyleLayer(identifier: ephemeralVehiclePuckLayerId, source: vehicleSource)
                            newPuck.circlePitchAlignment = NSExpression(forConstantValue: "map")
                            newPuck.circleStrokeColor = NSExpression(forConstantValue: UIColor.white)
                            newPuck.circleStrokeWidth = NSExpression(forConstantValue: 2.5)
                            newPuck.circleOpacityTransition = MLNTransition(duration: 0.25, delay: 0)
                            style.insertLayer(newPuck, above: haloLayer)
                            puckLayer = newPuck
                        }
                        puckLayer.circleColor = NSExpression(forConstantValue: cmd.agencyColor)
                        puckLayer.circleRadius = NSExpression(
                            forMLNInterpolating: NSExpression.zoomLevelVariable,
                            curveType: .linear,
                            parameters: nil,
                            stops: NSExpression(forConstantValue: [
                                10: 5.0,
                                13: 8.0,
                                16: 12.0
                            ])
                        )
                        puckLayer.circleOpacity = NSExpression(forConstantValue: 1.0)
                        
                        // Bearing Chevron Layer
                        let bearingLayer: MLNSymbolStyleLayer
                        if let existingBearing = style.layer(withIdentifier: ephemeralVehicleBearingLayerId) as? MLNSymbolStyleLayer {
                            bearingLayer = existingBearing
                        } else {
                            let newBearing = MLNSymbolStyleLayer(identifier: ephemeralVehicleBearingLayerId, source: vehicleSource)
                            newBearing.iconImageName = NSExpression(forConstantValue: CorridorPulseMapController.Config.bearingArrowImageName)
                            newBearing.iconRotationAlignment = NSExpression(forConstantValue: "map")
                            newBearing.iconAllowsOverlap = NSExpression(forConstantValue: true)
                            newBearing.iconIgnoresPlacement = NSExpression(forConstantValue: true)
                            newBearing.iconOpacityTransition = MLNTransition(duration: 0.25, delay: 0)
                            style.insertLayer(newBearing, above: puckLayer)
                            bearingLayer = newBearing
                        }
                        bearingLayer.predicate = NSPredicate(format: "has_bearing == YES")
                        bearingLayer.iconRotation = NSExpression(forKeyPath: "bearing")
                        bearingLayer.iconScale = NSExpression(
                            forMLNInterpolating: NSExpression.zoomLevelVariable,
                            curveType: .linear,
                            parameters: nil,
                            stops: NSExpression(forConstantValue: [
                                11: 0.45,
                                14: 0.70,
                                17: 1.0
                            ])
                        )
                        bearingLayer.iconOpacity = NSExpression(forConstantValue: 1.0)
                    } else {
                        if let vehicleSource = style.source(withIdentifier: ephemeralVehicleSourceId) as? MLNShapeSource {
                            vehicleSource.shape = nil
                        }
                    }
                    
                    // 6. Synchronized map camera framing (frames station, route, and vehicle)
                    if cmd.shouldFrameCamera {
                        frameRouteAndStation(
                            coordinates: cmd.coordinates,
                            station: cmd.stationCoordinate,
                            vehicleCoordinate: cmd.vehicleCoordinate,
                            in: mapView,
                            animated: true
                        )
                    }
                }
            } else {
                if lastAppliedInspectionCommandId != nil {
                    lastAppliedInspectionCommandId = nil
                    
                    if let casingLayer = style.layer(withIdentifier: ephemeralRouteCasingLayerId) as? MLNLineStyleLayer {
                        casingLayer.lineOpacity = NSExpression(forConstantValue: 0.0)
                    }
                    if let routeLayer = style.layer(withIdentifier: ephemeralRouteLayerId) as? MLNLineStyleLayer {
                        routeLayer.lineOpacity = NSExpression(forConstantValue: 0.0)
                    }
                    if let haloLayer = style.layer(withIdentifier: ephemeralVehicleHaloLayerId) as? MLNCircleStyleLayer {
                        haloLayer.circleOpacity = NSExpression(forConstantValue: 0.0)
                    }
                    if let puckLayer = style.layer(withIdentifier: ephemeralVehiclePuckLayerId) as? MLNCircleStyleLayer {
                        puckLayer.circleOpacity = NSExpression(forConstantValue: 0.0)
                    }
                    if let bearingLayer = style.layer(withIdentifier: ephemeralVehicleBearingLayerId) as? MLNSymbolStyleLayer {
                        bearingLayer.iconOpacity = NSExpression(forConstantValue: 0.0)
                    }
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                        guard let self = self, self.lastAppliedInspectionCommandId == nil,
                              let currentStyle = mapView.style else { return }
                        if let currentRouteSource = currentStyle.source(withIdentifier: self.ephemeralRouteSourceId) as? MLNShapeSource {
                            currentRouteSource.shape = nil
                        }
                        if let currentVehicleSource = currentStyle.source(withIdentifier: self.ephemeralVehicleSourceId) as? MLNShapeSource {
                            currentVehicleSource.shape = nil
                        }
                    }
                }
            }
        }
        
        /// Smoothly pans and zooms the camera to frame the user's station and the active route polyline,
        /// accounting for the bottom-sheet presentation detent in edge padding.
        /// Camera Safety Invariant (Wave PB.3): Filters out errant coordinates (>45km / 0.4° lat from station).
        func frameRouteAndStation(
            coordinates: [CLLocationCoordinate2D],
            station: CLLocationCoordinate2D,
            vehicleCoordinate: CLLocationCoordinate2D? = nil,
            in mapView: MLNMapView,
            animated: Bool = true
        ) {
            let validCoords = coordinates.filter { pt in
                abs(pt.latitude - station.latitude) < 0.4 &&
                abs(pt.longitude - station.longitude) < 0.5
            }
            var allPoints = validCoords
            allPoints.append(station)
            
            if let vCoord = vehicleCoordinate {
                if abs(vCoord.latitude - station.latitude) < 0.4 &&
                   abs(vCoord.longitude - station.longitude) < 0.5 {
                    allPoints.append(vCoord)
                }
            }
            
            guard let first = allPoints.first else { return }
            
            var minLat = first.latitude
            var maxLat = first.latitude
            var minLon = first.longitude
            var maxLon = first.longitude
            
            for pt in allPoints {
                minLat = min(minLat, pt.latitude)
                maxLat = max(maxLat, pt.latitude)
                minLon = min(minLon, pt.longitude)
                maxLon = max(maxLon, pt.longitude)
            }
            
            // Minimum span prevents over-zooming on single station or short segment
            let minSpan = 0.008
            if (maxLat - minLat) < minSpan {
                let mid = (maxLat + minLat) / 2.0
                minLat = mid - minSpan / 2.0
                maxLat = mid + minSpan / 2.0
            }
            if (maxLon - minLon) < minSpan {
                let mid = (maxLon + minLon) / 2.0
                minLon = mid - minSpan / 2.0
                maxLon = mid + minSpan / 2.0
            }
            
            let bounds = MLNCoordinateBounds(
                sw: CLLocationCoordinate2D(latitude: minLat, longitude: minLon),
                ne: CLLocationCoordinate2D(latitude: maxLat, longitude: maxLon)
            )
            
            // Asymmetric edge padding tailored to bottom-sheet detents (.fraction(0.40))
            let bottomPadding = max(340.0, mapView.bounds.height * 0.42)
            let edgePadding = UIEdgeInsets(top: 80, left: 40, bottom: bottomPadding, right: 40)
            
            let targetCamera = mapView.cameraThatFitsCoordinateBounds(bounds, edgePadding: edgePadding)
            
            // Enforce strict 2D top-down perspective (pitch = 0)
            let finalCamera = MLNMapCamera(
                lookingAtCenter: targetCamera.centerCoordinate,
                altitude: targetCamera.altitude,
                pitch: 0.0,
                heading: mapView.camera.heading
            )
            
            if animated {
                mapView.setCamera(
                    finalCamera,
                    withDuration: 0.6,
                    animationTimingFunction: CAMediaTimingFunction(name: .easeInEaseOut)
                ) { [weak self] in
                    guard let self = self, let mv = self.mapView else { return }
                    self.cameraBridge.write(MapCameraState(mapView: mv))
                }
            } else {
                mapView.setCamera(finalCamera, animated: false)
                cameraBridge.write(MapCameraState(mapView: mapView))
            }
        }
        
        @MainActor
        func updatePOIs(in style: MLNStyle) {
            guard let source = style.source(withIdentifier: poiSourceId) as? MLNShapeSource else { return }
            
            if pois.isEmpty {
                loadPOIs(for: parent.spatialStore.activeCitySlug)
            }
            
            let effectiveLocation = lastLocation ??
                (parent.currentUserLocation.map { CLLocation(latitude: $0.latitude, longitude: $0.longitude) }) ??
                parent.trackingEngine.lastKnownLocation
            
            var features: [MLNPointFeature] = []
            let exploredHexes = parent.spatialStore.exploredHexes
            let discoveredPOIs = parent.spatialStore.discoveredPOIs
            let markerStyle = parent.subwayStationMarkerStyle
            
            for poi in pois {
                guard let phase = POIMaskManager.resolvePhase(
                    poi: poi,
                    userLocation: effectiveLocation,
                    exploredHexes: exploredHexes,
                    discoveredPOIs: discoveredPOIs,
                    markerStyle: markerStyle
                ) else {
                    continue
                }
                
                let feature = MLNPointFeature()
                feature.coordinate = poi.coordinate
                feature.attributes = [
                    "id": poi.id, 
                    "name": poi.name,
                    "icon_name": poi.type == 1 ? "poi-subway-1" : "poi-bus-3",
                    "phase": phase
                ]
                
                if phase == 2 {
                    // Wave F.2: Discovery Trigger
                    DispatchQueue.main.async {
                        self.parent.spatialStore.discoverPOI(id: poi.id, name: poi.name)
                    }
                }
                
                features.append(feature)
            }
            
            source.shape = MLNShapeCollectionFeature(shapes: features)
        }
        
        @objc func handleMapTap(_ gesture: UITapGestureRecognizer) {
            guard let mapView = mapView else { return }
            let point = gesture.location(in: mapView)
            let hitBox = TransitHitTest.hitBox(for: point)
            let targetLayers: Set<String> = [
                activeLayerId,
                archiveLayerId,
                subwayStationBulletsLayerId,
                smartZoomStationBulletsLayerId,
                nearbyBusStopsLayerId
            ]
            let features = mapView.visibleFeatures(in: hitBox, styleLayerIdentifiers: targetLayers)
            
            if let closest = TransitHitTest.closestFeature(to: point, among: features, in: mapView) {
                if let stopId = closest.attributes["id"] as? String {
                    DispatchQueue.main.async {
                        self.parent.selectedTransitStop = stopId
                        self.parent.showTransitSheet = true
                    }
                } else if let clusterFeature = closest as? MLNPointFeatureCluster,
                          let busSource = mapView.style?.source(withIdentifier: nearbyBusStopsSourceId) as? MLNShapeSource {
                    let leaves = busSource.leaves(of: clusterFeature, offset: 0, limit: 1)
                    if let firstStop = leaves.first, let stopId = firstStop.attributes["id"] as? String {
                        DispatchQueue.main.async {
                            self.parent.selectedTransitStop = stopId
                            self.parent.showTransitSheet = true
                        }
                    } else {
                        DispatchQueue.main.async {
                            self.parent.onAmbientMapTap?()
                        }
                    }
                } else {
                    DispatchQueue.main.async {
                        self.parent.onAmbientMapTap?()
                    }
                }
            } else {
                DispatchQueue.main.async {
                    self.parent.onAmbientMapTap?()
                }
            }
        }
    }
}

struct GhostPOI {
    let id: String
    let name: String
    let coordinate: CLLocationCoordinate2D
    let type: Int
    var h3Index: String = ""
    var routes: [String] = []
    var bulletIconName: String = ""
}

extension UIColor {
    convenience init(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0
        Scanner(string: hexSanitized).scanHexInt64(&rgb)

        let r = CGFloat((rgb & 0xFF0000) >> 16) / 255.0
        let g = CGFloat((rgb & 0x00FF00) >> 8) / 255.0
        let b = CGFloat(rgb & 0x0000FF) / 255.0

        self.init(red: r, green: g, blue: b, alpha: 1.0)
    }
}
