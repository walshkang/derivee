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
    var transientHexShape: MLNShape?
    
    // MapTiler Streets URL
    let styleURL = URL(string: "https://api.maptiler.com/maps/streets-v2/style.json?key=\(Secrets.mapTilerKey)")!
    
    func makeUIView(context: Context) -> MLNMapView {
        let mapView = MLNMapView(frame: .zero, styleURL: styleURL)
        mapView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        mapView.showsUserLocation = true
        mapView.showsUserHeadingIndicator = true
        mapView.minimumZoomLevel = 10.5
        mapView.setCenter(CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060), zoomLevel: 15.5, animated: false)
        mapView.userTrackingMode = .followWithHeading
        mapView.delegate = context.coordinator
        
        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleMapTap(_:)))
        mapView.addGestureRecognizer(tapGesture)
        
        context.coordinator.mapView = mapView
        context.coordinator.setupCompassObservation()
        
        // Resume tracking if enabled
        DispatchQueue.main.async {
            self.trackingEngine.resumeTrackingIfNeeded()
        }
        
        return mapView
    }
    
    func updateUIView(_ uiView: MLNMapView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.updateFogColor(for: colorScheme, in: uiView)
        context.coordinator.updateExploredHexes(in: uiView, with: fogShape)
        context.coordinator.updateTransientHex(shape: transientHexShape, in: uiView)
        context.coordinator.updateTransitSheetState(showSheet: showTransitSheet, selectedStop: selectedTransitStop, in: uiView)
        
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
        
        var pois: [GhostPOI] = []
        var lastLocation: CLLocation?
        var lastRecenterTrigger: Bool = false
        var lastTransientHexShape: MLNShape? = nil
        var lastSelectedStop: String? = nil
        var isMapStyleLoaded: Bool = false
        
        var compassHiddenObserver: NSKeyValueObservation?
        var compassAlphaObserver: NSKeyValueObservation?
        
        var lureTimer: Timer?
        var isLurePulsed: Bool = false
        var isRollingBack: Bool = false
        
        init(_ parent: MapView) {
            self.parent = parent
            super.init()
            loadPOIs()
            
            NotificationCenter.default.addObserver(self, selector: #selector(appDidEnterBackground), name: UIApplication.didEnterBackgroundNotification, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(appWillEnterForeground), name: UIApplication.willEnterForegroundNotification, object: nil)
        }
        
        deinit {
            lureTimer?.invalidate()
            compassHiddenObserver?.invalidate()
            compassAlphaObserver?.invalidate()
            NotificationCenter.default.removeObserver(self)
        }
        
        func setupCompassObservation() {
            guard let mapView = mapView else { return }
            compassHiddenObserver = mapView.compassView.observe(\.isHidden, options: [.initial, .new]) { view, _ in
                if view.isHidden {
                    view.isHidden = false
                }
            }
            compassAlphaObserver = mapView.compassView.observe(\.alpha, options: [.initial, .new]) { view, _ in
                if view.alpha == 0 {
                    view.alpha = 1.0
                }
            }
        }
        
        @objc func appDidEnterBackground() {
            lureTimer?.invalidate()
            lureTimer = nil
        }
        
        @objc func appWillEnterForeground() {
            startLureTimer()
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
        
        func loadPOIs() {
            Task {
                do {
                    pois = try await SpatialDatabaseManager.shared.dbWriter.read { db in
                        let rows = try Row.fetchAll(db, sql: "SELECT stop_id, stop_name, stop_lat, stop_lon FROM transit.stops WHERE location_type = 1 OR location_type = 0")
                        return rows.map { row in
                            return GhostPOI(
                                id: row["stop_id"] as? String ?? "",
                                name: row["stop_name"] as? String ?? "",
                                coordinate: CLLocationCoordinate2D(latitude: row["stop_lat"] as? Double ?? 0, longitude: row["stop_lon"] as? Double ?? 0),
                                type: 1
                            )
                        }
                    }
                } catch {
                    print("⚠️ Transit POIs unavailable: \(error)")
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
        
        func mapView(_ mapView: MLNMapView, regionDidChangeWith reason: MLNCameraChangeReason, animated: Bool) {
            let currentCoord = mapView.centerCoordinate
            
            // If the camera came to rest outside the active bounding envelope, trigger a smooth easeOut rollback
            if !CameraBounds.isWithinBounds(currentCoord) && !isRollingBack {
                let clampedCoord = CameraBounds.clampedCoordinate(for: currentCoord)
                let currentCam = mapView.camera
                let rollbackCamera = MLNMapCamera(
                    lookingAtCenter: clampedCoord,
                    altitude: currentCam.altitude,
                    pitch: currentCam.pitch,
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
            // VERIFIED: MapLibre Native (iOS) initial fog shape requires CW winding order for exterior bounds.
            // Matches SpatialStore bounds order (Top-Left -> Top-Right -> Bottom-Right -> Bottom-Left -> Top-Left).
            // Tested & hardened in Wave I.2 (WI2-WINDING).
            let bounds = [
                CLLocationCoordinate2D(latitude: 41.500001, longitude: -74.500001),
                CLLocationCoordinate2D(latitude: 41.500001, longitude: -73.0),
                CLLocationCoordinate2D(latitude: 40.0, longitude: -73.0),
                CLLocationCoordinate2D(latitude: 40.0, longitude: -74.500001),
                CLLocationCoordinate2D(latitude: 41.500001, longitude: -74.500001)
            ]
            let initialFogShape = MLNPolygon(coordinates: bounds, count: UInt(bounds.count))
            
            let fogSource = MLNShapeSource(identifier: "fog-source", shape: initialFogShape, options: nil)
            style.addSource(fogSource)
            
            let fogLayer = MLNFillStyleLayer(identifier: fogLayerId, source: fogSource)
            let colorHex = parent.colorScheme == .dark ? "#000000" : "#1C1C1E"
            fogLayer.fillColor = NSExpression(forConstantValue: UIColor(hex: colorHex))
            fogLayer.fillOpacity = NSExpression(forConstantValue: 0.3)
            style.addLayer(fogLayer)
            
            let transientHexSource = MLNShapeSource(identifier: transientHexSourceId, shape: nil, options: nil)
            style.addSource(transientHexSource)
            
            let transientHexLayer = MLNFillStyleLayer(identifier: transientHexLayerId, source: transientHexSource)
            transientHexLayer.fillColor = NSExpression(forConstantValue: UIColor(hex: colorHex))
            transientHexLayer.fillOpacity = NSExpression(forConstantValue: 0.0)
            style.insertLayer(transientHexLayer, above: fogLayer)
            
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
            archiveLayer.circleRadius = NSExpression(forConstantValue: 6)
            archiveLayer.circleOpacity = NSExpression(forConstantValue: 0.15)
            archiveLayer.minimumZoomLevel = 16.5
            style.insertLayer(archiveLayer, above: activeLayer)
        }
        
        func updateFogColor(for colorScheme: ColorScheme, in mapView: MLNMapView) {
            guard let style = mapView.style, let fogLayer = style.layer(withIdentifier: fogLayerId) as? MLNFillStyleLayer else { return }
            let colorHex = colorScheme == .dark ? "#000000" : "#1C1C1E"
            fogLayer.fillColor = NSExpression(forConstantValue: UIColor(hex: colorHex))
            fogLayer.fillOpacity = NSExpression(forConstantValue: 0.3)
        }
        
        func updateExploredHexes(in mapView: MLNMapView, with shape: MLNShape?) {
            let interiorCount = (shape as? MLNPolygon)?.interiorPolygons?.count ?? 0
            logPipeline("📍 [S6 - updateExploredHexes] ENTER shape=\(shape != nil ? "present" : "nil"), interiorCount=\(interiorCount), isMapStyleLoaded=\(isMapStyleLoaded)")
            guard let style = mapView.style, let fogSource = style.source(withIdentifier: "fog-source") as? MLNShapeSource else {
                logPipeline("📍 [S6 - updateExploredHexes] fog-source or style not ready yet")
                return
            }
            let previousShape = fogSource.shape as? MLNPolygon
            let isTransitioningFromInitial = previousShape?.interiorPolygons == nil
            
            if let validShape = shape {
                fogSource.shape = validShape
                if isMapStyleLoaded, isTransitioningFromInitial, let poly = validShape as? MLNPolygon {
                    let holes = poly.interiorPolygons?.count ?? 0
                    print("✅ Deferred fog shape applied (\(holes) holes)")
                }
            } else if isMapStyleLoaded {
                print("⚠️ Fog shape not yet ready, will apply on next update")
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
                            
                            let line = MLNPolyline(coordinates: coords, count: UInt(coords.count))
                            let source = MLNShapeSource(identifier: self.ephemeralRouteSourceId, shape: line, options: nil)
                            style.addSource(source)
                            
                            // ARCHITECT GUARDRAIL 2: Dual-layer casing technique for dark MTA colors
                            // 1. Background Casing Layer (White/Light silver outline)
                            let casingLayer = MLNLineStyleLayer(identifier: self.ephemeralRouteCasingLayerId, source: source)
                            casingLayer.lineColor = NSExpression(forConstantValue: UIColor.white)
                            casingLayer.lineWidth = NSExpression(forConstantValue: 6)
                            casingLayer.lineOpacity = NSExpression(forConstantValue: 0.5)
                            casingLayer.lineCap = NSExpression(forConstantValue: "round")
                            casingLayer.lineJoin = NSExpression(forConstantValue: "round")
                            style.addLayer(casingLayer)
                            
                            // 2. Primary Colored Route Line Layer
                            let routeLayer = MLNLineStyleLayer(identifier: self.ephemeralRouteLayerId, source: source)
                            routeLayer.lineColor = NSExpression(forConstantValue: lineInfo.uiColor)
                            routeLayer.lineWidth = NSExpression(forConstantValue: 4)
                            routeLayer.lineOpacity = NSExpression(forConstantValue: 0.9)
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
            for poi in pois {
                let feature = MLNPointFeature()
                feature.coordinate = poi.coordinate
                feature.attributes = [
                    "id": poi.id, 
                    "name": poi.name,
                    "icon_name": poi.type == 1 ? "poi-subway-1" : "poi-bus-3"
                ]
                
                let distance = userLoc.distance(from: CLLocation(latitude: poi.coordinate.latitude, longitude: poi.coordinate.longitude))
                
                // 1 = Lure, 2 = Active, 3 = Archive
                if distance < 200 {
                    feature.attributes["phase"] = 2
                    
                    // Wave F.2: Discovery Trigger
                    DispatchQueue.main.async {
                        self.parent.spatialStore.discoverPOI(id: poi.id, name: poi.name)
                    }
                } else if distance < 1000 {
                    feature.attributes["phase"] = 1
                } else {
                    feature.attributes["phase"] = 3
                }
                
                features.append(feature)
            }
            
            source.shape = MLNShapeCollectionFeature(shapes: features)
        }
        
        @objc func handleMapTap(_ gesture: UITapGestureRecognizer) {
            guard let mapView = mapView else { return }
            let point = gesture.location(in: mapView)
            let features = mapView.visibleFeatures(at: point, styleLayerIdentifiers: [activeLayerId])
            
            if let first = features.first, let phase = first.attributes["phase"] as? Int, phase == 2 {
                if let stopId = first.attributes["id"] as? String {
                    DispatchQueue.main.async {
                        self.parent.selectedTransitStop = stopId
                        self.parent.showTransitSheet = true
                    }
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
