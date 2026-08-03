import SwiftUI
import MapLibre
import GRDB
import CoreLocation

struct MapView: UIViewRepresentable {
    @Environment(\.colorScheme) var colorScheme
    @StateObject var trackingEngine = AmbientTrackingEngine()
    var spatialStore: SpatialStore
    var fogShape: MLNShape?
    @Binding var showTransitSheet: Bool
    @Binding var selectedTransitStop: String?
    @Binding var isCentered: Bool
    @Binding var recenterTrigger: Bool
    
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
        
        // Start tracking
        DispatchQueue.main.async {
            self.trackingEngine.startTracking()
        }
        
        return mapView
    }
    
    func updateUIView(_ uiView: MLNMapView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.updateFogColor(for: colorScheme, in: uiView)
        context.coordinator.updateExploredHexes(in: uiView, with: fogShape)
        context.coordinator.updateTransitSheetState(showSheet: showTransitSheet, selectedStop: selectedTransitStop, in: uiView)
        
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
        let ephemeralRouteLayerId = "ephemeral-route-layer"
        let ephemeralRouteSourceId = "ephemeral-route-source"
        
        var pois: [GhostPOI] = []
        var lastLocation: CLLocation?
        var lastRecenterTrigger: Bool = false
        
        init(_ parent: MapView) {
            self.parent = parent
            super.init()
            loadPOIs()
        }
        
        func loadPOIs() {
            Task {
                do {
                    pois = try await SpatialDatabaseManager.shared.dbPool.read { db in
                        let rows = try Row.fetchAll(db, sql: "SELECT stop_id, stop_name, stop_lat, stop_lon FROM transit.stops WHERE location_type = 1 OR location_type = 0")
                        return rows.map { row in
                            GhostPOI(
                                id: row["stop_id"] as? String ?? "",
                                name: row["stop_name"] as? String ?? "",
                                coordinate: CLLocationCoordinate2D(latitude: row["stop_lat"] as? Double ?? 0, longitude: row["stop_lon"] as? Double ?? 0)
                            )
                        }
                    }
                } catch {
                    print("⚠️ Transit POIs unavailable: \(error)")
                }
            }
        }
        
        func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
            setupLayers(in: style)
            updatePOIs(in: style)
            updateExploredHexes(in: mapView, with: parent.spatialStore.currentFogShape)
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
        
        func setupLayers(in style: MLNStyle) {
            let fogSource = MLNShapeSource(identifier: "fog-source", shape: nil, options: nil)
            style.addSource(fogSource)
            
            let fogLayer = MLNFillStyleLayer(identifier: fogLayerId, source: fogSource)
            let colorHex = parent.colorScheme == .dark ? "#000000" : "#1C1C1E"
            fogLayer.fillColor = NSExpression(forConstantValue: UIColor(hex: colorHex))
            fogLayer.fillOpacity = NSExpression(forConstantValue: 0.3)
            style.addLayer(fogLayer)
            
            let source = MLNShapeSource(identifier: poiSourceId, features: [], options: nil)
            style.addSource(source)
            
            let lureLayer = MLNCircleStyleLayer(identifier: lureLayerId, source: source)
            lureLayer.predicate = NSPredicate(format: "phase == 1")
            lureLayer.circleColor = NSExpression(forConstantValue: UIColor(hex: "#FFB300"))
            lureLayer.circleRadius = NSExpression(forConstantValue: 15)
            lureLayer.circleOpacity = NSExpression(forConstantValue: 0.3)
            lureLayer.circleBlur = NSExpression(forConstantValue: 2.0)
            style.insertLayer(lureLayer, above: fogLayer)
            
            let activeLayer = MLNCircleStyleLayer(identifier: activeLayerId, source: source)
            activeLayer.predicate = NSPredicate(format: "phase == 2")
            activeLayer.circleColor = NSExpression(forConstantValue: UIColor(hex: "#FFB300"))
            activeLayer.circleRadius = NSExpression(forConstantValue: 8)
            activeLayer.circleOpacity = NSExpression(forConstantValue: 1.0)
            style.insertLayer(activeLayer, above: lureLayer)
            
            let archiveLayer = MLNCircleStyleLayer(identifier: archiveLayerId, source: source)
            archiveLayer.predicate = NSPredicate(format: "phase == 3")
            archiveLayer.circleColor = NSExpression(forConstantValue: UIColor(hex: "#FFB300"))
            archiveLayer.circleRadius = NSExpression(forConstantValue: 6)
            archiveLayer.circleOpacity = NSExpression(forConstantValue: 0.15)
            style.insertLayer(archiveLayer, above: activeLayer)
        }
        
        func updateFogColor(for colorScheme: ColorScheme, in mapView: MLNMapView) {
            guard let style = mapView.style, let fogLayer = style.layer(withIdentifier: fogLayerId) as? MLNFillStyleLayer else { return }
            let colorHex = colorScheme == .dark ? "#000000" : "#1C1C1E"
            fogLayer.fillColor = NSExpression(forConstantValue: UIColor(hex: colorHex))
            fogLayer.fillOpacity = NSExpression(forConstantValue: 0.3)
        }
        
        func updateExploredHexes(in mapView: MLNMapView, with shape: MLNShape?) {
            guard let style = mapView.style, let fogSource = style.source(withIdentifier: "fog-source") as? MLNShapeSource else { return }
            fogSource.shape = shape
        }
        
        func updateTransitSheetState(showSheet: Bool, selectedStop: String?, in mapView: MLNMapView) {
            guard let style = mapView.style else { return }
            
            if showSheet, let _ = selectedStop {
                if style.source(withIdentifier: ephemeralRouteSourceId) == nil {
                    // Mock route geometry for Layer 6
                    let lineCoords = [
                        CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060),
                        CLLocationCoordinate2D(latitude: 40.7580, longitude: -73.9855)
                    ]
                    let line = MLNPolyline(coordinates: lineCoords, count: UInt(lineCoords.count))
                    let source = MLNShapeSource(identifier: ephemeralRouteSourceId, shape: line, options: nil)
                    style.addSource(source)
                    
                    let routeLayer = MLNLineStyleLayer(identifier: ephemeralRouteLayerId, source: source)
                    routeLayer.lineColor = NSExpression(forConstantValue: UIColor.gray)
                    routeLayer.lineWidth = NSExpression(forConstantValue: 4)
                    routeLayer.lineOpacity = NSExpression(forConstantValue: 0.7)
                    style.addLayer(routeLayer)
                }
            } else {
                if let layer = style.layer(withIdentifier: ephemeralRouteLayerId) {
                    style.removeLayer(layer)
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
                feature.attributes = ["id": poi.id, "name": poi.name]
                
                let distance = userLoc.distance(from: CLLocation(latitude: poi.coordinate.latitude, longitude: poi.coordinate.longitude))
                
                // 1 = Lure, 2 = Active, 3 = Archive
                if distance < 200 {
                    feature.attributes["phase"] = 2
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
