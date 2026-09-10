import Foundation
import UIKit
import MapLibre
import CoreLocation
import SwiftProtobuf

/// MapLibre Native Layer Controller managing real-time transit telemetry and headway regularity visualization.
/// Built strictly to Research Doc 19 (§3, §5, §6) for Wave R.3 (WR3-CORRIDOR-MAP-LAYERS).
///
/// Features:
/// - Decoupled dynamic `MLNShapeSource` instances for transient vehicle tokens and bunching segments.
/// - Casing and dashed line layers for platooning segments (`feature_class == 'bunching_segment'`).
/// - Circle base, selection halo, heading arrow, and label layers for vehicles (`feature_class == 'vehicle_marker'`).
/// - Programmatic generation and registration of the `transit-bearing-arrow` icon asset.
/// - Asynchronous background Protobuf (`TransitRealtime_FeedMessage`) and GeoJSON unmarshaling keeping main thread at 60–120 FPS.
public final class CorridorPulseMapController: NSObject, @unchecked Sendable {
    
    public private(set) weak var mapView: MLNMapView?
    
    public enum Config {
        public static let vehicleSourceID = "corridor-vehicles-source"
        public static let bunchingSegmentsSourceID = "corridor-bunching-segments-source"
        
        public static let bunchingCasingLayerID = "corridor-bunching-casing-layer"
        public static let bunchingLineLayerID = "corridor-bunching-line-layer"
        
        public static let vehicleTargetHaloLayerID = "vehicle-target-halo-layer"
        public static let vehicleCircleBaseLayerID = "vehicle-circle-base-layer"
        public static let vehicleDirectionArrowLayerID = "vehicle-direction-arrow-layer"
        public static let vehicleLabelLayerID = "vehicle-label-layer"
        
        public static let bearingArrowImageName = "transit-bearing-arrow"
        
        // Color tokens matching Research Doc 19 §5
        public static let colorBunchedStatus = "#D32F2F"
        public static let colorBunchedHalo = "#FFCDD2"
        public static let colorGapStatus = "#F57C00"
        public static let colorGapHalo = "#FFE0B2"
        public static let colorNormalStatus = "#388E3C"
        public static let colorNormalHalo = "#C8E6C9"
        public static let colorBunchingLine = "#B71C1C"
        public static let colorBunchingCasing = "#FFEBEE"
    }

    public init(mapView: MLNMapView? = nil) {
        self.mapView = mapView
        super.init()
    }
    
    @MainActor
    public func attach(to mapView: MLNMapView) {
        self.mapView = mapView
    }
    
    // MARK: - Layer & Source Configuration (Doc 19 §6)
    
    /// Configures decoupled dynamic sources and GPU vector style layers in the provided MapLibre style.
    @MainActor
    public func configureCorridorLayers(in style: MLNStyle) {
        registerBearingArrowImage(in: style)
        setupDynamicSources(in: style)
        setupBunchingSegmentLayers(in: style)
        setupVehicleTokenLayers(in: style)
    }
    
    // MARK: - Style Image Registration
    
    @MainActor
    public func registerBearingArrowImage(in style: MLNStyle) {
        if style.image(forName: Config.bearingArrowImageName) == nil {
            let arrowImage = Self.makeBearingArrowImage()
            style.setImage(arrowImage, forName: Config.bearingArrowImageName)
        }
    }
    
    /// Generates a crisp vector navigation chevron/arrow pointing North (upwards, 0 degrees).
    /// Styled with a white core and subtle dark outline for high contrast against any basemap or token color.
    public static func makeBearingArrowImage() -> UIImage {
        let size = CGSize(width: 24, height: 24)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            let cgContext = ctx.cgContext
            
            let path = UIBezierPath()
            path.move(to: CGPoint(x: 12.0, y: 3.5))       // Top tip (North)
            path.addLine(to: CGPoint(x: 19.5, y: 19.5))   // Bottom right wing
            path.addLine(to: CGPoint(x: 12.0, y: 15.0))   // Inner notch
            path.addLine(to: CGPoint(x: 4.5, y: 19.5))    // Bottom left wing
            path.close()
            
            // Contrast dark stroke outline
            cgContext.saveGState()
            cgContext.setLineWidth(2.0)
            cgContext.setLineJoin(.round)
            cgContext.setLineCap(.round)
            cgContext.setStrokeColor(UIColor.black.withAlphaComponent(0.70).cgColor)
            cgContext.addPath(path.cgPath)
            cgContext.strokePath()
            cgContext.restoreGState()
            
            // Crisp white fill
            cgContext.setFillColor(UIColor.white.cgColor)
            cgContext.addPath(path.cgPath)
            cgContext.fillPath()
        }
    }
    
    // MARK: - Dynamic Sources Setup
    
    @MainActor
    private func setupDynamicSources(in style: MLNStyle) {
        let emptyCollection = MLNShapeCollectionFeature(shapes: [])
        
        if style.source(withIdentifier: Config.bunchingSegmentsSourceID) == nil {
            let bunchingSource = MLNShapeSource(
                identifier: Config.bunchingSegmentsSourceID,
                shape: emptyCollection,
                options: nil
            )
            style.addSource(bunchingSource)
        }
        
        if style.source(withIdentifier: Config.vehicleSourceID) == nil {
            let vehicleSource = MLNShapeSource(
                identifier: Config.vehicleSourceID,
                shape: emptyCollection,
                options: nil
            )
            style.addSource(vehicleSource)
        }
    }
    
    // MARK: - Bunching Segment Layers Setup
    
    @MainActor
    private func setupBunchingSegmentLayers(in style: MLNStyle) {
        guard let bunchSource = style.source(withIdentifier: Config.bunchingSegmentsSourceID) else { return }
        
        let segmentFilter = NSPredicate(format: "feature_class == 'bunching_segment'")
        
        // 1. Casing Layer (Doc 19 §6)
        if style.layer(withIdentifier: Config.bunchingCasingLayerID) == nil {
            let casingLayer = MLNLineStyleLayer(identifier: Config.bunchingCasingLayerID, source: bunchSource)
            casingLayer.predicate = segmentFilter
            casingLayer.lineJoin = NSExpression(forConstantValue: "round")
            casingLayer.lineCap = NSExpression(forConstantValue: "round")
            casingLayer.lineColor = NSExpression(forKeyPath: "casing_color")
            casingLayer.lineOpacity = NSExpression(forConstantValue: 0.85)
            casingLayer.lineWidth = NSExpression(
                forMLNInterpolating: NSExpression.zoomLevelVariable,
                curveType: .linear,
                parameters: nil,
                stops: NSExpression(forConstantValue: [
                    11: 4.0,
                    14: 8.0,
                    17: 16.0
                ])
            )
            insertBunchingLayer(casingLayer, in: style)
        }
        
        // 2. Dashed Line Layer (Doc 19 §6)
        if style.layer(withIdentifier: Config.bunchingLineLayerID) == nil {
            let lineLayer = MLNLineStyleLayer(identifier: Config.bunchingLineLayerID, source: bunchSource)
            lineLayer.predicate = segmentFilter
            lineLayer.lineJoin = NSExpression(forConstantValue: "round")
            lineLayer.lineCap = NSExpression(forConstantValue: "round")
            lineLayer.lineColor = NSExpression(forKeyPath: "line_color")
            lineLayer.lineWidth = NSExpression(
                forMLNInterpolating: NSExpression.zoomLevelVariable,
                curveType: .linear,
                parameters: nil,
                stops: NSExpression(forConstantValue: [
                    11: 2.0,
                    14: 4.0,
                    17: 8.0
                ])
            )
            lineLayer.lineDashPattern = NSExpression(forConstantValue: [1.5, 0.75])
            
            if let casing = style.layer(withIdentifier: Config.bunchingCasingLayerID) {
                style.insertLayer(lineLayer, above: casing)
            } else {
                insertBunchingLayer(lineLayer, in: style)
            }
        }
    }
    
    // MARK: - Vehicle Token Layers Setup
    
    @MainActor
    private func setupVehicleTokenLayers(in style: MLNStyle) {
        guard let vehicleSource = style.source(withIdentifier: Config.vehicleSourceID) else { return }
        
        let vehicleFilter = NSPredicate(format: "feature_class == 'vehicle_marker'")
        
        // 1. Target Selection Halo Layer (Doc 19 §6)
        if style.layer(withIdentifier: Config.vehicleTargetHaloLayerID) == nil {
            let haloLayer = MLNCircleStyleLayer(identifier: Config.vehicleTargetHaloLayerID, source: vehicleSource)
            haloLayer.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                vehicleFilter,
                NSPredicate(format: "is_target == YES")
            ])
            haloLayer.circlePitchAlignment = NSExpression(forConstantValue: "map")
            haloLayer.circleColor = NSExpression(forKeyPath: "halo_color")
            haloLayer.circleOpacity = NSExpression(forConstantValue: 0.60)
            haloLayer.circleRadius = NSExpression(
                forMLNInterpolating: NSExpression.zoomLevelVariable,
                curveType: .linear,
                parameters: nil,
                stops: NSExpression(forConstantValue: [
                    11: 12.0,
                    14: 20.0,
                    17: 34.0
                ])
            )
            
            if let bunchLine = style.layer(withIdentifier: Config.bunchingLineLayerID) {
                style.insertLayer(haloLayer, above: bunchLine)
            } else {
                insertVehicleLayer(haloLayer, in: style)
            }
        }
        
        // 2. Base Circle Layer (Doc 19 §6)
        if style.layer(withIdentifier: Config.vehicleCircleBaseLayerID) == nil {
            let circleLayer = MLNCircleStyleLayer(identifier: Config.vehicleCircleBaseLayerID, source: vehicleSource)
            circleLayer.predicate = vehicleFilter
            circleLayer.circlePitchAlignment = NSExpression(forConstantValue: "map")
            circleLayer.circleColor = NSExpression(forKeyPath: "status_color")
            circleLayer.circleStrokeColor = NSExpression(forConstantValue: UIColor.white)
            circleLayer.circleStrokeWidth = NSExpression(
                forMLNInterpolating: NSExpression.zoomLevelVariable,
                curveType: .linear,
                parameters: nil,
                stops: NSExpression(forConstantValue: [
                    10: 1.0,
                    14: 2.0,
                    17: 3.0
                ])
            )
            circleLayer.circleRadius = NSExpression(
                forMLNInterpolating: NSExpression.zoomLevelVariable,
                curveType: .linear,
                parameters: nil,
                stops: NSExpression(forConstantValue: [
                    10: 4.0,
                    13: 7.0,
                    16: 12.0
                ])
            )
            
            if let halo = style.layer(withIdentifier: Config.vehicleTargetHaloLayerID) {
                style.insertLayer(circleLayer, above: halo)
            } else {
                insertVehicleLayer(circleLayer, in: style)
            }
        }
        
        // 3. Direction Arrow Layer (Doc 19 §6)
        if style.layer(withIdentifier: Config.vehicleDirectionArrowLayerID) == nil {
            let directionLayer = MLNSymbolStyleLayer(identifier: Config.vehicleDirectionArrowLayerID, source: vehicleSource)
            directionLayer.predicate = vehicleFilter
            directionLayer.iconImageName = NSExpression(forConstantValue: Config.bearingArrowImageName)
            directionLayer.iconRotationAlignment = NSExpression(forConstantValue: "map")
            directionLayer.iconRotation = NSExpression(forKeyPath: "bearing")
            directionLayer.iconAllowsOverlap = NSExpression(forConstantValue: true)
            directionLayer.iconIgnoresPlacement = NSExpression(forConstantValue: true)
            directionLayer.iconScale = NSExpression(
                forMLNInterpolating: NSExpression.zoomLevelVariable,
                curveType: .linear,
                parameters: nil,
                stops: NSExpression(forConstantValue: [
                    11: 0.4,
                    14: 0.7,
                    17: 1.0
                ])
            )
            
            if let circle = style.layer(withIdentifier: Config.vehicleCircleBaseLayerID) {
                style.insertLayer(directionLayer, above: circle)
            } else {
                insertVehicleLayer(directionLayer, in: style)
            }
        }
        
        // 4. Vehicle ID Label Layer (Doc 19 §6)
        if style.layer(withIdentifier: Config.vehicleLabelLayerID) == nil {
            let labelLayer = MLNSymbolStyleLayer(identifier: Config.vehicleLabelLayerID, source: vehicleSource)
            labelLayer.predicate = vehicleFilter
            labelLayer.minimumZoomLevel = 13.5
            labelLayer.text = NSExpression(format: "vehicle_id")
            labelLayer.textFontSize = NSExpression(forConstantValue: 11.0)
            labelLayer.textTranslation = NSExpression(forConstantValue: NSValue(cgVector: CGVector(dx: 0, dy: 14)))
            labelLayer.textColor = NSExpression(forConstantValue: UIColor.black)
            labelLayer.textHaloColor = NSExpression(forConstantValue: UIColor.white)
            labelLayer.textHaloWidth = NSExpression(forConstantValue: 1.5)
            labelLayer.textAllowsOverlap = NSExpression(forConstantValue: false)
            
            if let direction = style.layer(withIdentifier: Config.vehicleDirectionArrowLayerID) {
                style.insertLayer(labelLayer, above: direction)
            } else {
                insertVehicleLayer(labelLayer, in: style)
            }
        }
    }
    
    // MARK: - Z-Stack Layer Insertion Helpers
    
    @MainActor
    private func insertBunchingLayer(_ layer: MLNStyleLayer, in style: MLNStyle) {
        if let routeLayer = style.layer(withIdentifier: "ephemeral-route-layer") {
            style.insertLayer(layer, above: routeLayer)
        } else if let pulseLayer = style.layer(withIdentifier: "transient-pulse-layer") {
            style.insertLayer(layer, above: pulseLayer)
        } else if let fogLayer = style.layer(withIdentifier: "cloud-layer") {
            style.insertLayer(layer, above: fogLayer)
        } else {
            style.addLayer(layer)
        }
    }
    
    @MainActor
    private func insertVehicleLayer(_ layer: MLNStyleLayer, in style: MLNStyle) {
        if let bunchLine = style.layer(withIdentifier: Config.bunchingLineLayerID) {
            style.insertLayer(layer, above: bunchLine)
        } else if let bunchCasing = style.layer(withIdentifier: Config.bunchingCasingLayerID) {
            style.insertLayer(layer, above: bunchCasing)
        } else {
            insertBunchingLayer(layer, in: style)
        }
    }
    
    // MARK: - Background Telemetry Ingestion (GeoJSON)
    
    /// Deserializes a Doc 19 §5 GeoJSON FeatureCollection on a background QoS queue,
    /// extracting vehicle markers and bunching segments into separate shape collections,
    /// and atomically updating the decoupled shape sources on `@MainActor` to maintain 60–120 FPS.
    public func updateTelemetry(geoJsonData: Data) {
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else { return }
            
            let parsed = Self.parseCorridorGeoJSON(data: geoJsonData)
            
            await MainActor.run {
                guard let mapView = self.mapView, let style = mapView.style else { return }
                
                if let vehicleSource = style.source(withIdentifier: Config.vehicleSourceID) as? MLNShapeSource {
                    vehicleSource.shape = parsed.vehiclesShape
                }
                
                if let bunchSource = style.source(withIdentifier: Config.bunchingSegmentsSourceID) as? MLNShapeSource {
                    bunchSource.shape = parsed.bunchingShape
                }
            }
        }
    }
    
    /// Internal parsing helper for GeoJSON data into separate shape collection features.
    public static func parseCorridorGeoJSON(data: Data) -> (vehiclesShape: MLNShapeCollectionFeature, bunchingShape: MLNShapeCollectionFeature) {
        guard let jsonObject = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let featureList = jsonObject["features"] as? [[String: Any]] else {
            return (MLNShapeCollectionFeature(shapes: []), MLNShapeCollectionFeature(shapes: []))
        }
        
        var vehicleShapes: [MLNShape] = []
        var bunchingShapes: [MLNShape] = []
        
        for feat in featureList {
            guard let geom = feat["geometry"] as? [String: Any],
                  let geomType = geom["type"] as? String,
                  let props = feat["properties"] as? [String: Any] else {
                continue
            }
            
            let featureClass = props["feature_class"] as? String ?? ""
            
            if geomType == "Point", let coords = geom["coordinates"] as? [Double], coords.count >= 2 {
                let point = MLNPointFeature()
                point.coordinate = CLLocationCoordinate2D(latitude: coords[1], longitude: coords[0])
                point.attributes = props
                if featureClass.isEmpty {
                    point.attributes["feature_class"] = "vehicle_marker"
                }
                vehicleShapes.append(point)
            } else if geomType == "LineString", let coordArray = geom["coordinates"] as? [[Double]], coordArray.count >= 2 {
                var coordinates: [CLLocationCoordinate2D] = []
                for pt in coordArray {
                    if pt.count >= 2 {
                        coordinates.append(CLLocationCoordinate2D(latitude: pt[1], longitude: pt[0]))
                    }
                }
                if coordinates.count >= 2 {
                    let polyline = MLNPolylineFeature(coordinates: coordinates, count: UInt(coordinates.count))
                    polyline.attributes = props
                    if featureClass.isEmpty {
                        polyline.attributes["feature_class"] = "bunching_segment"
                    }
                    bunchingShapes.append(polyline)
                }
            }
        }
        
        return (
            MLNShapeCollectionFeature(shapes: vehicleShapes),
            MLNShapeCollectionFeature(shapes: bunchingShapes)
        )
    }
    
    // MARK: - Background Telemetry Ingestion (Protobuf FeedMessage)
    
    /// Deserializes a GTFS-RT Protobuf FeedMessage on a background queue, filters active vehicles,
    /// computes attributes matching Research Doc 19, and pushes updates to the vehicle shape source.
    public func updateFromProtobuf(
        data: Data,
        targetRouteId: String? = nil,
        targetVehicleId: String? = nil
    ) {
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else { return }
            
            guard let feed = try? TransitRealtime_FeedMessage(serializedBytes: data) else {
                return
            }
            
            let vehiclesShape = Self.parseProtobufVehicles(
                feed: feed,
                targetRouteId: targetRouteId,
                targetVehicleId: targetVehicleId
            )
            
            await MainActor.run {
                guard let mapView = self.mapView, let style = mapView.style else { return }
                if let vehicleSource = style.source(withIdentifier: Config.vehicleSourceID) as? MLNShapeSource {
                    vehicleSource.shape = vehiclesShape
                }
            }
        }
    }
    
    /// Parses GTFS-RT Protobuf `FeedMessage` into an `MLNShapeCollectionFeature` of vehicle point features.
    static func parseProtobufVehicles(
        feed: TransitRealtime_FeedMessage,
        targetRouteId: String? = nil,
        targetVehicleId: String? = nil
    ) -> MLNShapeCollectionFeature {
        var vehicleShapes: [MLNShape] = []
        
        for entity in feed.entity where entity.hasVehicle {
            let veh = entity.vehicle
            guard veh.hasPosition else { continue }
            
            let routeId = veh.trip.routeID.trimmingCharacters(in: .whitespacesAndNewlines)
            if let targetRoute = targetRouteId, !targetRoute.isEmpty {
                if routeId.caseInsensitiveCompare(targetRoute) != .orderedSame {
                    continue
                }
            }
            
            let vehId = veh.vehicle.id.isEmpty ? entity.id : veh.vehicle.id
            let tripId = veh.trip.tripID
            let lat = Double(veh.position.latitude)
            let lon = Double(veh.position.longitude)
            let bearing = Double(veh.position.bearing)
            let speed = Double(veh.position.speed)
            
            // Check target vehicle match
            let isTarget = (targetVehicleId != nil && !targetVehicleId!.isEmpty) &&
                           (vehId == targetVehicleId || tripId == targetVehicleId)
            
            // Resolve status color and halo color
            let statusColor: String
            let haloColor: String
            
            let lineInfo = TransitRouteData.lineInfo(for: routeId)
            let defaultColor = lineInfo.colorHex.isEmpty ? Config.colorNormalStatus : lineInfo.colorHex
            
            statusColor = defaultColor
            haloColor = isTarget ? Config.colorBunchedHalo : Config.colorNormalHalo
            
            let point = MLNPointFeature()
            point.coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
            point.attributes = [
                "feature_class": "vehicle_marker",
                "vehicle_id": vehId,
                "trip_id": tripId,
                "route_id": routeId,
                "bearing": bearing,
                "speed_mps": speed,
                "is_target": isTarget,
                "is_bunched": false,
                "is_service_gap": false,
                "status_color": statusColor,
                "halo_color": haloColor
            ]
            vehicleShapes.append(point)
        }
        
        return MLNShapeCollectionFeature(shapes: vehicleShapes)
    }
    
    // MARK: - Direct Typed Telemetry Update
    
    /// Updates vehicle markers and bunching segments directly from strongly-typed Swift models.
    @MainActor
    public func updateTelemetry(
        vehicles: [CorridorVehicleTelemetry],
        bunchingSegments: [CorridorBunchingSegmentTelemetry] = []
    ) {
        guard let mapView = mapView, let style = mapView.style else { return }
        
        var vehicleFeatures: [MLNShape] = []
        for v in vehicles {
            let pt = MLNPointFeature()
            pt.coordinate = v.coordinate
            pt.attributes = [
                "feature_class": "vehicle_marker",
                "vehicle_id": v.vehicleId,
                "trip_id": v.tripId,
                "route_id": v.routeId,
                "bearing": v.bearing,
                "speed_mps": v.speedMps,
                "delay_sec": v.delaySec,
                "is_target": v.isTarget,
                "is_bunched": v.isBunched,
                "is_service_gap": v.isServiceGap,
                "status_color": v.statusColorHex,
                "halo_color": v.haloColorHex
            ]
            vehicleFeatures.append(pt)
        }
        
        var segmentFeatures: [MLNShape] = []
        for seg in bunchingSegments where seg.coordinates.count >= 2 {
            let poly = MLNPolylineFeature(coordinates: seg.coordinates, count: UInt(seg.coordinates.count))
            poly.attributes = [
                "feature_class": "bunching_segment",
                "trailing_vehicle_id": seg.trailingVehicleId,
                "leading_vehicle_id": seg.leadingVehicleId,
                "line_color": seg.lineColorHex,
                "casing_color": seg.casingColorHex,
                "severity": seg.severity,
                "segment_length_m": seg.segmentLengthM,
                "headway_compression_ratio": seg.compressionRatio
            ]
            segmentFeatures.append(poly)
        }
        
        if let vehicleSource = style.source(withIdentifier: Config.vehicleSourceID) as? MLNShapeSource {
            vehicleSource.shape = MLNShapeCollectionFeature(shapes: vehicleFeatures)
        }
        if let bunchSource = style.source(withIdentifier: Config.bunchingSegmentsSourceID) as? MLNShapeSource {
            bunchSource.shape = MLNShapeCollectionFeature(shapes: segmentFeatures)
        }
    }
    
    // MARK: - Teardown & Reset
    
    /// Clears active vehicle markers and bunching segments without tearing down style layers.
    /// Used during city hot-swaps or when dismissing inspected corridors.
    @MainActor
    public func clearTelemetry() {
        guard let mapView = mapView, let style = mapView.style else { return }
        let empty = MLNShapeCollectionFeature(shapes: [])
        if let vehicleSource = style.source(withIdentifier: Config.vehicleSourceID) as? MLNShapeSource {
            vehicleSource.shape = empty
        }
        if let bunchSource = style.source(withIdentifier: Config.bunchingSegmentsSourceID) as? MLNShapeSource {
            bunchSource.shape = empty
        }
    }
}
