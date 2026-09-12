import Foundation
import UIKit
import MapLibre

/// MapLibre Native Layer Controller managing multi-scale station transitions (0D centroids to 2D architectural micro-geometries).
/// Built strictly to Research Doc 20 (§1, §2, §4, §5) for Wave Q.3 (WQ3-MULTISCALE-TRANSITIONS).
///
/// Features:
/// - Continuous camera-driven paint-property cross-dissolve across $z \in [15.0, 16.5]$ with zero Earcut re-triangulation.
/// - Linear contraction & fade of 0D station bullets ($z \in [15.0, 16.0]$).
/// - Linear emergence of 2D station footprint boundaries ($z \in [15.2, 16.2]$).
/// - Linear ingress of platform edge lines ($z \in [15.5, 16.5]$) and exponential width scaling ($z \in [16.0, 20.0]$).
/// - Linear emergence of egress portal icons ($z \in [16.0, 16.5]$).
/// - Strict 7-layer Z-stack placing footprints and platforms below Fog, and bullets and exits above Fog.
/// - Type-safe floor filtering predicate using `CAST(level, 'NSString')` for multi-level floorplan viewing (Doc 20 §3).
public final class StationTransitVisualizationManager: NSObject, @unchecked Sendable {
    
    public private(set) weak var mapView: MLNMapView?
    
    public enum Config {
        public static let stationShapesSourceId = "station-shapes-source"
        
        public static let footprintLayerId = "station-interior-fill"
        public static let platformLayerId = "station-platform-lines"
        public static let exitLayerId = "station-exit-symbols"
        
        // Associated macro bullet layer IDs from MapView
        public static let bulletLayerId = "subway-station-bullets-layer"
        public static let smartZoomBulletLayerId = "smart-zoom-station-bullets-layer"
        
        public static let exitPortalImageName = "station-exit-portal"
        
        // Color tokens matching Research Doc 20 §5
        public static let colorFootprintFill = "#292E38"
        public static let colorPlatformLine = "#FAB83D"
        public static let colorExitPortalPill = "#008542"
    }
    
    public init(mapView: MLNMapView? = nil) {
        self.mapView = mapView
        super.init()
    }
    
    @MainActor
    public func attach(to mapView: MLNMapView) {
        self.mapView = mapView
    }
    
    // MARK: - Zoom Interpolation Expressions (Doc 20 §1 & §5)
    
    /// Station Bullet Pin Opacity: Linear decay from 1.0 at z=15.0 to 0.0 at z=16.0.
    public static func bulletOpacityExpression() -> NSExpression {
        return NSExpression(
            forMLNInterpolating: .zoomLevelVariable,
            curveType: .linear,
            parameters: nil,
            stops: NSExpression(forConstantValue: [15.0: 1.0, 16.0: 0.0])
        )
    }
    
    /// Station Bullet Radius Contraction: Linear contraction from 6.0pt at z=15.0 to 3.0pt at z=16.0.
    public static func bulletRadiusExpression() -> NSExpression {
        return NSExpression(
            forMLNInterpolating: .zoomLevelVariable,
            curveType: .linear,
            parameters: nil,
            stops: NSExpression(forConstantValue: [15.0: 6.0, 16.0: 3.0])
        )
    }
    
    /// Station Bullet Stroke Opacity: Linear decay from 1.0 at z=15.0 to 0.0 at z=16.0.
    public static func bulletStrokeOpacityExpression() -> NSExpression {
        return NSExpression(
            forMLNInterpolating: .zoomLevelVariable,
            curveType: .linear,
            parameters: nil,
            stops: NSExpression(forConstantValue: [15.0: 1.0, 16.0: 0.0])
        )
    }
    
    /// Smart Zoom Composite Bullet Opacity: Linear decay from 1.0 at z=15.0 to 0.0 at z=16.0.
    public static func smartZoomBulletOpacityExpression() -> NSExpression {
        return NSExpression(
            forMLNInterpolating: .zoomLevelVariable,
            curveType: .linear,
            parameters: nil,
            stops: NSExpression(forConstantValue: [15.0: 1.0, 16.0: 0.0])
        )
    }
    
    /// Station Polygon Footprint Fill Ingress: Linear emergence from 0.0 at z=15.2 to 0.85 at z=16.2.
    public static func footprintOpacityExpression() -> NSExpression {
        return NSExpression(
            forMLNInterpolating: .zoomLevelVariable,
            curveType: .linear,
            parameters: nil,
            stops: NSExpression(forConstantValue: [15.2: 0.0, 16.2: 0.85])
        )
    }
    
    /// Platform Edge Line Ingress: Linear emergence from 0.0 at z=15.5 to 1.0 at z=16.5.
    public static func platformOpacityExpression() -> NSExpression {
        return NSExpression(
            forMLNInterpolating: .zoomLevelVariable,
            curveType: .linear,
            parameters: nil,
            stops: NSExpression(forConstantValue: [15.5: 0.0, 16.5: 1.0])
        )
    }
    
    /// Platform Line Width Expansion: Exponential scaling (base 1.5) from 1.5pt at z=16.0 to 8.0pt at z=20.0.
    public static func platformWidthExpression() -> NSExpression {
        return NSExpression(
            forMLNInterpolating: .zoomLevelVariable,
            curveType: .exponential,
            parameters: NSExpression(forConstantValue: 1.5),
            stops: NSExpression(forConstantValue: [16.0: 1.5, 20.0: 8.0])
        )
    }
    
    /// Exit Portal Icon Emergence: Linear emergence from 0.0 at z=16.0 to 1.0 at z=16.5.
    public static func exitOpacityExpression() -> NSExpression {
        return NSExpression(
            forMLNInterpolating: .zoomLevelVariable,
            curveType: .linear,
            parameters: nil,
            stops: NSExpression(forConstantValue: [16.0: 0.0, 16.5: 1.0])
        )
    }
    
    // MARK: - Style Layer Configuration (Doc 20 §2 & §5)
    
    /// Configures Sub-Fog station transition layers (Footprints & Platforms) into the MapLibre style (Doc 20 §2 Layers 3a & 3b).
    @MainActor
    public func configureSubFogLayers(
        in style: MLNStyle,
        citySlug: String? = nil
    ) {
        registerExitPortalImage(in: style)
        setupStationShapesSource(in: style, citySlug: citySlug)
        setupFootprintAndPlatformLayers(in: style)
    }
    
    /// Configures the multi-scale station transition layers into the MapLibre style following the strict 7-layer Z-stack.
    @MainActor
    public func configureTransitLayers(
        in style: MLNStyle,
        citySlug: String? = nil
    ) {
        configureSubFogLayers(in: style, citySlug: citySlug)
        setupExitPortalLayer(in: style)
        applyTransitionsToExistingBullets(in: style)
    }
    
    // MARK: - Image Registration
    
    @MainActor
    public func registerExitPortalImage(in style: MLNStyle) {
        if style.image(forName: Config.exitPortalImageName) == nil {
            let portalImage = Self.makeExitPortalImage()
            style.setImage(portalImage, forName: Config.exitPortalImageName)
        }
    }
    
    /// Generates a crisp vector egress portal icon (24×24 pt).
    /// Features an emerald transit pill with a white subterranean staircase and directional exit chevron.
    public static func makeExitPortalImage() -> UIImage {
        let size = CGSize(width: 24, height: 24)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            let cg = ctx.cgContext
            
            // 1. Drop shadow
            cg.saveGState()
            cg.setShadow(offset: CGSize(width: 0, height: 1.5), blur: 3.0, color: UIColor.black.withAlphaComponent(0.40).cgColor)
            
            // 2. Base rounded badge
            let badgeRect = CGRect(x: 2.0, y: 2.0, width: 20.0, height: 20.0)
            let badgePath = UIBezierPath(roundedRect: badgeRect, cornerRadius: 6.0)
            UIColor(hex: Config.colorExitPortalPill).setFill()
            badgePath.fill()
            cg.restoreGState()
            
            // 3. Crisp white 1.0pt rim
            UIColor.white.setStroke()
            badgePath.lineWidth = 1.0
            badgePath.stroke()
            
            // 4. White staircase glyph (subterranean egress metaphor)
            let stairPath = UIBezierPath()
            // Top platform
            stairPath.move(to: CGPoint(x: 6.5, y: 8.0))
            stairPath.addLine(to: CGPoint(x: 9.5, y: 8.0))
            // Step 1 down
            stairPath.addLine(to: CGPoint(x: 9.5, y: 11.0))
            stairPath.addLine(to: CGPoint(x: 12.5, y: 11.0))
            // Step 2 down
            stairPath.addLine(to: CGPoint(x: 12.5, y: 14.0))
            stairPath.addLine(to: CGPoint(x: 15.5, y: 14.0))
            // Step 3 down
            stairPath.addLine(to: CGPoint(x: 15.5, y: 16.5))
            stairPath.addLine(to: CGPoint(x: 6.5, y: 16.5))
            stairPath.close()
            
            UIColor.white.setFill()
            stairPath.fill()
            
            // 5. Upward/Egress Arrow Accent at top right
            let arrowPath = UIBezierPath()
            arrowPath.move(to: CGPoint(x: 14.0, y: 6.5))
            arrowPath.addLine(to: CGPoint(x: 17.5, y: 6.5))
            arrowPath.addLine(to: CGPoint(x: 17.5, y: 10.0))
            arrowPath.move(to: CGPoint(x: 17.5, y: 6.5))
            arrowPath.addLine(to: CGPoint(x: 12.5, y: 11.5))
            
            UIColor.white.setStroke()
            arrowPath.lineWidth = 1.5
            arrowPath.lineCapStyle = .round
            arrowPath.stroke()
        }
    }
    
    // MARK: - Source Setup
    
    @MainActor
    private func setupStationShapesSource(in style: MLNStyle, citySlug: String?) {
        if style.source(withIdentifier: Config.stationShapesSourceId) == nil {
            let shapeCollection = StationCartographyLoader.loadStationShapesSync(for: citySlug)
            let source = StationCartographyLoader.makeOptimizedStationSource(
                identifier: Config.stationShapesSourceId,
                shape: shapeCollection
            )
            style.addSource(source)
        }
    }
    
    // MARK: - Layers Setup (7-Layer Z-Stack)
    
    @MainActor
    public private(set) var currentFloorLevel: Int? = nil
    
    // MARK: - Layer Predicate Specifications (Doc 20 §3 & Wave Q.4)
    
    /// Returns the base feature_type predicate for a given indoor layer.
    public static func basePredicate(for layerId: String) -> NSPredicate? {
        switch layerId {
        case Config.footprintLayerId:
            return NSPredicate(format: "feature_type IN {'mezzanine', 'corridor', 'room', 'station_footprint'}")
        case Config.platformLayerId:
            return NSPredicate(format: "feature_type IN {'platform', 'station_platform', 'track', 'steps', 'escalator'}")
        case Config.exitLayerId:
            return NSPredicate(format: "feature_type IN {'subway_entrance', 'portal', 'elevator', 'station_exit'}")
        default:
            return nil
        }
    }
    
    @MainActor
    private func setupFootprintAndPlatformLayers(in style: MLNStyle) {
        guard let source = style.source(withIdentifier: Config.stationShapesSourceId) else { return }
        
        // 1. Layer 3a: station-interior-fill (2D Station Footprints)
        if style.layer(withIdentifier: Config.footprintLayerId) == nil {
            let footprintLayer = MLNFillStyleLayer(identifier: Config.footprintLayerId, source: source)
            footprintLayer.predicate = Self.basePredicate(for: Config.footprintLayerId)
            footprintLayer.fillColor = NSExpression(forConstantValue: UIColor(hex: Config.colorFootprintFill))
            footprintLayer.fillOpacity = Self.footprintOpacityExpression()
            footprintLayer.fillAntialiased = NSExpression(forConstantValue: true)
            
            insertSubFogLayer(footprintLayer, in: style)
        }
        
        // 2. Layer 3b: station-platform-lines (Platforms & Tracks & Vertical Circulation)
        if style.layer(withIdentifier: Config.platformLayerId) == nil {
            let platformLayer = MLNLineStyleLayer(identifier: Config.platformLayerId, source: source)
            platformLayer.predicate = Self.basePredicate(for: Config.platformLayerId)
            platformLayer.lineColor = NSExpression(forConstantValue: UIColor(hex: Config.colorPlatformLine))
            platformLayer.lineOpacity = Self.platformOpacityExpression()
            platformLayer.lineWidth = Self.platformWidthExpression()
            platformLayer.lineCap = NSExpression(forConstantValue: "round")
            platformLayer.lineJoin = NSExpression(forConstantValue: "round")
            
            if let footprint = style.layer(withIdentifier: Config.footprintLayerId) {
                style.insertLayer(platformLayer, above: footprint)
            } else {
                insertSubFogLayer(platformLayer, in: style)
            }
        }
    }
    
    @MainActor
    public func setupExitPortalLayer(in style: MLNStyle, above siblingLayer: MLNStyleLayer? = nil) {
        guard let source = style.source(withIdentifier: Config.stationShapesSourceId) else { return }
        
        // If layer already exists in style, remove it first so repositioning or re-adding is safe and never throws a duplicate identifier error.
        if let existingLayer = style.layer(withIdentifier: Config.exitLayerId) {
            style.removeLayer(existingLayer)
        }
        
        // Layer 6b: station-exit-symbols (Egress Portals) - Above Fog & Bullets
        let exitLayer = MLNSymbolStyleLayer(identifier: Config.exitLayerId, source: source)
        exitLayer.predicate = Self.basePredicate(for: Config.exitLayerId)
        exitLayer.iconImageName = NSExpression(forConstantValue: Config.exitPortalImageName)
        exitLayer.iconOpacity = Self.exitOpacityExpression()
        exitLayer.iconAllowsOverlap = NSExpression(forConstantValue: true)
        exitLayer.iconIgnoresPlacement = NSExpression(forConstantValue: true)
        
        if let sibling = siblingLayer {
            style.insertLayer(exitLayer, above: sibling)
        } else {
            insertAboveFogLayer(exitLayer, in: style)
        }
    }
    
    @MainActor
    public func applyTransitionsToExistingBullets(in style: MLNStyle) {
        if let bulletsLayer = style.layer(withIdentifier: Config.bulletLayerId) as? MLNCircleStyleLayer {
            bulletsLayer.circleOpacity = Self.bulletOpacityExpression()
            bulletsLayer.circleRadius = Self.bulletRadiusExpression()
            bulletsLayer.circleStrokeOpacity = Self.bulletStrokeOpacityExpression()
        }
        
        if let smartZoomLayer = style.layer(withIdentifier: Config.smartZoomBulletLayerId) as? MLNSymbolStyleLayer {
            smartZoomLayer.iconOpacity = Self.smartZoomBulletOpacityExpression()
        }
    }
    
    // MARK: - Z-Stack Layer Insertion Helpers (Doc 20 §2)
    
    @MainActor
    public func insertSubFogLayer(_ layer: MLNStyleLayer, in style: MLNStyle) {
        // Must be inserted BELOW Fog layer (environmental-fog or metalFogLayer)
        if let metalFog = style.layer(withIdentifier: MapCustomizationDefaults.metalFogLayerId) {
            style.insertLayer(layer, below: metalFog)
        } else if let fogLayer = style.layer(withIdentifier: "cloud-layer") {
            style.insertLayer(layer, below: fogLayer)
        } else if let subwayLines = style.layer(withIdentifier: "subway-lines-layer") {
            style.insertLayer(layer, above: subwayLines)
        } else {
            style.addLayer(layer)
        }
    }
    
    @MainActor
    public func insertAboveFogLayer(_ layer: MLNStyleLayer, in style: MLNStyle) {
        // Must be inserted ABOVE Fog, and above/below vicinity bubble
        if let vicinityBubble = style.layer(withIdentifier: "vicinity-bubble-overlay") {
            style.insertLayer(layer, below: vicinityBubble)
        } else if let smartZoomBullets = style.layer(withIdentifier: Config.smartZoomBulletLayerId) {
            style.insertLayer(layer, above: smartZoomBullets)
        } else if let bulletsLayer = style.layer(withIdentifier: Config.bulletLayerId) {
            style.insertLayer(layer, above: bulletsLayer)
        } else if let hexLayer = style.layer(withIdentifier: "boundary-borders-layer") {
            style.insertLayer(layer, above: hexLayer)
        } else if let fogLayer = style.layer(withIdentifier: "cloud-layer") {
            style.insertLayer(layer, above: fogLayer)
        } else {
            style.addLayer(layer)
        }
    }
    
    // MARK: - Discrete Floor Filtering (Doc 20 §3 & Q.4 Foundation)
    
    /// Constructs a type-safe NSPredicate for discrete floorplan filtering.
    /// Handles single floor levels, string-based level tags, and multi-level connectors.
    public static func makeFloorFilterPredicate(targetLevel: Int) -> NSPredicate {
        return makeFloorFilterPredicate(targetLevel: Double(targetLevel))
    }
    
    /// Constructs a type-safe NSPredicate for discrete floorplan filtering supporting fractional levels.
    public static func makeFloorFilterPredicate(targetLevel: Double) -> NSPredicate {
        let levelInt = Int(targetLevel)
        let isInteger = (targetLevel == Double(levelInt))
        let levelString = isInteger ? String(levelInt) : String(format: "%.1f", targetLevel)
        let doubleVal = targetLevel
        return NSPredicate(
            format: """
            (CAST(level, 'NSString') == %@) OR 
            (level == %lf) OR 
            (levels != nil AND CAST(levels, 'NSString') CONTAINS %@) OR 
            (%@ IN levels)
            """,
            levelString, doubleVal, levelString, levelString
        )
    }
    
    /// Constructs a compound predicate combining the layer's base feature_type filter with the target floor filter.
    /// Ensures inactive vertical storeys are culled while keeping fills, lines, and portals cleanly separated.
    public static func makeCompoundLayerFloorPredicate(layerId: String, targetLevel: Int) -> NSPredicate {
        let floorPred = makeFloorFilterPredicate(targetLevel: targetLevel)
        guard let basePred = basePredicate(for: layerId) else {
            return floorPred
        }
        return NSCompoundPredicate(andPredicateWithSubpredicates: [basePred, floorPred])
    }
    
    /// Applies active floor slice filtering across all indoor station layers using compound predicates.
    @MainActor
    public func applyFloorFilter(level: Int) {
        guard let style = mapView?.style else { return }
        self.currentFloorLevel = level
        
        let indoorLayers = [Config.footprintLayerId, Config.platformLayerId, Config.exitLayerId]
        for layerId in indoorLayers {
            if let layer = style.layer(withIdentifier: layerId) as? MLNVectorStyleLayer {
                layer.predicate = Self.makeCompoundLayerFloorPredicate(layerId: layerId, targetLevel: level)
            }
        }
    }
    
    /// Clears active floor filtering, restoring base feature_type predicates across all indoor layers.
    @MainActor
    public func clearFloorFilter() {
        guard let style = mapView?.style else { return }
        self.currentFloorLevel = nil
        
        let indoorLayers = [Config.footprintLayerId, Config.platformLayerId, Config.exitLayerId]
        for layerId in indoorLayers {
            if let layer = style.layer(withIdentifier: layerId) as? MLNVectorStyleLayer {
                layer.predicate = Self.basePredicate(for: layerId)
            }
        }
    }
    
    /// Updates station shapes dataset dynamically upon city switching.
    @MainActor
    public func updateStationShapes(for citySlug: String?, in style: MLNStyle) {
        guard let source = style.source(withIdentifier: Config.stationShapesSourceId) as? MLNShapeSource else { return }
        Task { @MainActor [weak source] in
            let shapes = await StationCartographyLoader.loadStationShapes(for: citySlug)
            source?.shape = shapes
        }
    }
}
