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
    var nearbyBusStops: [SpatialDatabaseManager.NearbyBusStop] = []
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
        context.coordinator.setupCompass()
        
        // Resume tracking if enabled
        DispatchQueue.main.async {
            self.trackingEngine.resumeTrackingIfNeeded()
        }
        
        return mapView
    }
    
    func updateUIView(_ uiView: MLNMapView, context: Context) {
        context.coordinator.parent = self
        
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
        if let style = uiView.style {
            context.coordinator.updateTheme(selectedTheme, in: style)
            context.coordinator.updateFogOpacity(fogOpacity, in: style)
            context.coordinator.updateBoundaryBorders(showBoundaryBorders, in: style)
            context.coordinator.updateSubwayThoroughfares(show: showSubwayThoroughfares, theme: selectedTheme, in: style)
            context.coordinator.updateSubwayStationBullets(style: subwayStationMarkerStyle, theme: selectedTheme, in: style)
            context.coordinator.updateNearbyBusStops(nearbyBusStops, in: style)
            context.coordinator.updatePOIs(in: style)
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
        let nearbyBusStopsSourceId = MapCustomizationDefaults.nearbyBusStopsSourceId
        let nearbyBusStopsLayerId = MapCustomizationDefaults.nearbyBusStopsLayerId
        
        var pois: [GhostPOI] = []
        var lastLocation: CLLocation?
        var lastRecenterTrigger: Bool = false
        var lastTransientHexShape: MLNShape? = nil
        var lastPulseLocation: CLLocationCoordinate2D? = nil
        var pulseTimer: DispatchWorkItem? = nil
        var lastSelectedStop: String? = nil
        var isMapStyleLoaded: Bool = false
        var lastAppliedTheme: BasemapTheme?
        var lastAppliedCitySlug: String? = nil
        
        var lureTimer: Timer?
        var isLurePulsed: Bool = false
        var isRollingBack: Bool = false
        
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
            // (Guarantees MapLibre C++ GPU tessellation cache invalidation for the new city's bounding envelope)
            let freshFogFeature = FogPolygonMath.makeInitialFogShapeFeature(for: config)
            
            if let style = mapView.style {
                if let fogSource = style.source(withIdentifier: "fog-source") as? MLNShapeSource {
                    fogSource.shape = freshFogFeature
                    logPipeline("🌫️ [WLD3 Viewport Handshake] Assigned fresh MLNShapeCollectionFeature to fog-source for \(config.slug)")
                }
                
                // 3. Update transit lines GeoJSON for the destination city
                updateTransitLines(for: config.slug, in: style)
                
                // 4. Reload station POIs and sub-fog station bullets for the destination city
                loadPOIs(for: config.slug)
            }
            
            // 5. Synchronously coordinate camera center to destination city center
            let center = targetCenter ?? config.center.coordinate
            let zoom = targetZoom ?? config.center.defaultZoom
            mapView.setCenter(center, zoomLevel: zoom, animated: animated)
            
            // 6. Reset transient state & animations
            lastTransientHexShape = nil
            lastPulseLocation = nil
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
                        let rows = try Row.fetchAll(db, sql: "SELECT stop_id, stop_name, stop_lat, stop_lon FROM transit.stops WHERE location_type = 1")
                        return rows.map { row in
                            let lat: Double = row["stop_lat"]
                            let lon: Double = row["stop_lon"]
                            let id: String = row["stop_id"]
                            let name: String = row["stop_name"]
                            let h3 = POIMaskManager.computeH3Index(latitude: lat, longitude: lon)
                            return GhostPOI(
                                id: id,
                                name: name,
                                coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                                type: 1,
                                h3Index: h3
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
            let busDot = generateDotImage()
            let subwayDiamond = generateDiamondImage()
            style.setImage(busDot, forName: "poi-bus-3")
            style.setImage(subwayDiamond, forName: "poi-subway-1")
            
            setupLayers(in: style)
            populateSubwayStationBullets(in: style)
            let initialTheme = parent.selectedTheme
            BasemapThemeManager.applyTheme(initialTheme, in: style, animated: false)
            lastAppliedTheme = initialTheme
            
            updateFogOpacity(parent.fogOpacity, in: style)
            updateBoundaryBorders(parent.showBoundaryBorders, in: style)
            updateSubwayThoroughfares(show: parent.showSubwayThoroughfares, theme: initialTheme, in: style)
            updateSubwayStationBullets(style: parent.subwayStationMarkerStyle, theme: initialTheme, in: style)
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
        
        func mapView(_ mapView: MLNMapView, regionDidChangeWith reason: MLNCameraChangeReason, animated: Bool) {
            let currentCoord = mapView.centerCoordinate
            
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
            
            // Sub-fog Subway Station Bullets (Orienting nodes beneath Fog of War)
            let bulletsSource = MLNShapeSource(identifier: subwayStationBulletsSourceId, features: [], options: nil)
            style.addSource(bulletsSource)
            
            let bulletsLayer = MLNCircleStyleLayer(identifier: subwayStationBulletsLayerId, source: bulletsSource)
            let bulletFillColor = UIColor(hex: "#1C1C1E")
            let bulletStrokeColor = UIColor(hex: "#FFFFFF")
            bulletsLayer.circleColor = NSExpression(forConstantValue: bulletFillColor)
            bulletsLayer.circleRadius = NSExpression(forConstantValue: 4.5)
            bulletsLayer.circleStrokeColor = NSExpression(forConstantValue: bulletStrokeColor)
            bulletsLayer.circleStrokeWidth = NSExpression(forConstantValue: 1.0)
            bulletsLayer.circleOpacity = NSExpression(forConstantValue: parent.subwayStationMarkerStyle == .allStations ? 0.95 : 0.0)
            bulletsLayer.circleOpacityTransition = MLNTransition(duration: 0, delay: 0)
            style.insertLayer(bulletsLayer, above: subwayLinesLayer)
            
            // VERIFIED: MapLibre Native (iOS) initial fog shape requires CW winding order for exterior bounds.
            // Matches SpatialStore bounds order (Top-Left -> Top-Right -> Bottom-Right -> Bottom-Left -> Top-Left).
            // Tested & hardened in Wave I.2 (WI2-WINDING).
            let bounds = FogPolygonMath.makeBounds(for: CameraBounds.activeConfig.bounds, jitter: 0.000001)
            let initialFogShape = MLNPolygon(coordinates: bounds, count: UInt(bounds.count))
            
            let fogSource = MLNShapeSource(identifier: "fog-source", shape: initialFogShape, options: nil)
            style.addSource(fogSource)
            
            let fogLayer = MLNFillStyleLayer(identifier: fogLayerId, source: fogSource)
            let colorHex = "#1C1C1E"
            fogLayer.fillColor = NSExpression(forConstantValue: UIColor(hex: colorHex))
            fogLayer.fillOpacity = NSExpression(forConstantValue: parent.fogOpacity)
            style.insertLayer(fogLayer, above: bulletsLayer)
            
            let borderLayer = MLNLineStyleLayer(identifier: fogBorderLayerId, source: fogSource)
            borderLayer.lineColor = NSExpression(forConstantValue: UIColor(hex: MapCustomizationDefaults.boundaryBorderColorHex))
            borderLayer.lineWidth = NSExpression(forConstantValue: MapCustomizationDefaults.boundaryBorderWidth)
            borderLayer.lineOpacity = NSExpression(forConstantValue: parent.showBoundaryBorders ? MapCustomizationDefaults.boundaryBorderOpacity : 0.0)
            borderLayer.lineJoin = NSExpression(forConstantValue: "round")
            borderLayer.lineCap = NSExpression(forConstantValue: "round")
            style.insertLayer(borderLayer, above: fogLayer)
            
            let transientHexSource = MLNShapeSource(identifier: transientHexSourceId, shape: nil, options: nil)
            style.addSource(transientHexSource)
            
            let transientHexLayer = MLNFillStyleLayer(identifier: transientHexLayerId, source: transientHexSource)
            transientHexLayer.fillColor = NSExpression(forConstantValue: UIColor(hex: colorHex))
            transientHexLayer.fillOpacity = NSExpression(forConstantValue: 0.0)
            style.insertLayer(transientHexLayer, above: fogLayer)
            
            let pulseSource = MLNShapeSource(identifier: pulseSourceId, shape: nil, options: nil)
            style.addSource(pulseSource)
            
            let pulseLayer = MLNCircleStyleLayer(identifier: pulseLayerId, source: pulseSource)
            pulseLayer.circleColor = NSExpression(forConstantValue: UIColor(hex: "#FFB300"))
            pulseLayer.circleRadius = NSExpression(forConstantValue: 0.0)
            pulseLayer.circleOpacity = NSExpression(forConstantValue: 0.0)
            pulseLayer.circlePitchAlignment = NSExpression(forConstantValue: "map")
            style.insertLayer(pulseLayer, above: fogLayer)
            
            // Nearby Bus Stops Source & Layer
            let busStopsSource = MLNShapeSource(identifier: nearbyBusStopsSourceId, features: [], options: nil)
            style.addSource(busStopsSource)
            
            let busStopsLayer = MLNCircleStyleLayer(identifier: nearbyBusStopsLayerId, source: busStopsSource)
            busStopsLayer.circleColor = NSExpression(forConstantValue: UIColor(hex: "#00A1DE"))
            busStopsLayer.circleRadius = NSExpression(forConstantValue: 6.0)
            busStopsLayer.circleStrokeColor = NSExpression(forConstantValue: UIColor.white)
            busStopsLayer.circleStrokeWidth = NSExpression(forConstantValue: 1.5)
            busStopsLayer.circleOpacity = NSExpression(forConstantValue: 0.95)
            busStopsLayer.circleOpacityTransition = MLNTransition(duration: 0.2, delay: 0)
            style.insertLayer(busStopsLayer, above: fogLayer)
            
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
            
            // Suppress commercial/park vector POIs & base stations in favor of subway POIs
            POIMaskManager.configureBaseVectorLayers(in: style)
        }
        
        static func subwayLineColorExpression() -> NSExpression {
            return NSExpression(forKeyPath: "color")
        }
        
        func updateTransitLines(for citySlug: String? = nil, in style: MLNStyle) {
            guard isMapStyleLoaded, let source = style.source(withIdentifier: subwayLinesSourceId) as? MLNShapeSource else { return }
            Task { @MainActor [weak source] in
                let shape = await TransitCartographyLoader.loadTransitLinesShape(for: citySlug)
                source?.shape = shape
            }
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
                bulletsLayer.circleOpacity = NSExpression(forConstantValue: markerStyle == .allStations ? 0.95 : 0.0)
            }
        }
        
        func populateSubwayStationBullets(in style: MLNStyle) {
            guard let bulletsSource = style.source(withIdentifier: subwayStationBulletsSourceId) as? MLNShapeSource else { return }
            var features: [MLNPointFeature] = []
            for poi in pois {
                let feature = MLNPointFeature()
                feature.coordinate = poi.coordinate
                feature.attributes = [
                    "id": poi.id,
                    "name": poi.name,
                    "type": poi.type
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
            if let fogLayer = style.layer(withIdentifier: fogLayerId) as? MLNFillStyleLayer {
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
                let freshFogFeature = FogPolygonMath.makeInitialFogShapeFeature(for: CameraBounds.activeConfig)
                fogSource.shape = freshFogFeature
                logPipeline("🌫️ [updateExploredHexes] Reset fog-source to full solid baseline fog shape for \(CameraBounds.activeConfig.slug)")
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
        
        func updateTransitSheetState(showSheet: Bool, selectedStop: String?, in mapView: MLNMapView) {
            guard let style = mapView.style else { return }
            
            if showSheet, let stopId = selectedStop {
                if lastSelectedStop != stopId || style.source(withIdentifier: ephemeralRouteSourceId) == nil {
                    lastSelectedStop = stopId
                    
                    // ARCHITECT GUARDRAIL 1: Load/Decode GeoJSON polyline off main thread
                    Task.detached(priority: .userInitiated) {
                        do {
                            let details = try await SpatialDatabaseManager.shared.fetchStopDetails(for: stopId)
                            let coords = await TransitRouteData.loadRouteCoordinates(for: stopId)
                            let lineInfo = TransitRouteData.lineInfo(for: details.routeId)
                            
                            await MainActor.run {
                            guard self.parent.showTransitSheet && self.parent.selectedTransitStop == stopId else { return }
                            
                            // Remove stale layers/sources if any
                            if let layer = style.layer(withIdentifier: self.ephemeralRouteLayerId) { style.removeLayer(layer) }
                            if let casing = style.layer(withIdentifier: self.ephemeralRouteCasingLayerId) { style.removeLayer(casing) }
                            if let source = style.source(withIdentifier: self.ephemeralRouteSourceId) { style.removeSource(source) }
                            
                            guard !coords.isEmpty else { return }
                            
                            let line = MLNPolyline(coordinates: coords, count: UInt(coords.count))
                            let source = MLNShapeSource(identifier: self.ephemeralRouteSourceId, shape: line, options: nil)
                            style.addSource(source)
                            
                            // ARCHITECT GUARDRAIL 2: Dual-layer casing technique for dark MTA colors
                            // 1. Background Casing Layer (White/Light silver outline)
                            let casingLayer = MLNLineStyleLayer(identifier: self.ephemeralRouteCasingLayerId, source: source)
                            casingLayer.lineColor = NSExpression(forConstantValue: UIColor(hex: "#E5E5EA"))
                            casingLayer.lineWidth = NSExpression(forConstantValue: 6)
                            casingLayer.lineOpacity = NSExpression(forConstantValue: 0.8)
                            casingLayer.lineCap = NSExpression(forConstantValue: "round")
                            casingLayer.lineJoin = NSExpression(forConstantValue: "round")
                            casingLayer.lineOpacityTransition = MLNTransition(duration: 0.2, delay: 0)
                            style.addLayer(casingLayer)
                            
                            // 2. Primary Colored Route Line Layer
                            let routeLayer = MLNLineStyleLayer(identifier: self.ephemeralRouteLayerId, source: source)
                            routeLayer.lineColor = NSExpression(forConstantValue: lineInfo.uiColor)
                            routeLayer.lineWidth = NSExpression(forConstantValue: 4)
                            routeLayer.lineOpacity = NSExpression(forConstantValue: 0.95)
                            routeLayer.lineCap = NSExpression(forConstantValue: "round")
                            routeLayer.lineJoin = NSExpression(forConstantValue: "round")
                            routeLayer.lineOpacityTransition = MLNTransition(duration: 0.2, delay: 0)
                            style.addLayer(routeLayer)
                        }
                    } catch {
                        print("Map POI Fetch Error: \(error)")
                    }
                }
            }
        } else {
                lastSelectedStop = nil
                if let layer = style.layer(withIdentifier: ephemeralRouteLayerId) {
                    style.removeLayer(layer)
                }
                if let casing = style.layer(withIdentifier: ephemeralRouteCasingLayerId) {
                    style.removeLayer(casing)
                }
                if let source = style.source(withIdentifier: ephemeralRouteSourceId) {
                    style.removeSource(source)
                }
            }
        }
        
        func updatePOIs(in style: MLNStyle) {
            guard let source = style.source(withIdentifier: poiSourceId) as? MLNShapeSource else { return }
            guard let userLoc = lastLocation else { return }
            
            var features: [MLNPointFeature] = []
            let exploredHexes = parent.spatialStore.exploredHexes
            let discoveredPOIs = parent.spatialStore.discoveredPOIs
            let markerStyle = parent.subwayStationMarkerStyle
            
            for poi in pois {
                guard let phase = POIMaskManager.resolvePhase(
                    poi: poi,
                    userLocation: userLoc,
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
                nearbyBusStopsLayerId
            ]
            let features = mapView.visibleFeatures(in: hitBox, styleLayerIdentifiers: targetLayers)
            
            if let closest = TransitHitTest.closestFeature(to: point, among: features, in: mapView),
               let stopId = closest.attributes["id"] as? String {
                DispatchQueue.main.async {
                    self.parent.selectedTransitStop = stopId
                    self.parent.showTransitSheet = true
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
