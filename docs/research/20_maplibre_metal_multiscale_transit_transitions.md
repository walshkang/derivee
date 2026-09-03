# Architecture and Implementation of Multi-Scale Transit Transitions in MapLibre Native (Metal)

## 1. Cross-Scale Transition Mechanics: 0D Station Pins to 2D Micro-Geometries

Cartographic representation transitions between macroscopic point symbols and microscopic architectural footprints present severe visual discontinuity when handled through discrete zoom thresholds. In standard map styling paradigms, abruptly switching layers via strict zoom cutoffs induces visual popping, momentary draw-call starvation, and pipeline stalls as underlying geometry representations are swapped within tile trees. Achieving imperceptible level-of-detail transitions across the intermediate zoom band between zoom 15.0 and 16.5 requires a continuous cross-dissolve architecture governed by camera-driven interpolation functions.

MapLibre Native segregates style layer attributes into **layout properties** and **paint properties**, a separation that directly impacts Metal rendering efficiency:
- **Layout properties** dictate spatial distribution, geometric configuration, and label collision passes handled by CPU-side bucket processing. Modifying layout properties or adding discrete layers forces background worker threads to rebuild geometry buckets and retriangulate vertex arrays via Earcut.
- **Paint properties** are evaluated per frame on the GPU via uniform buffer objects or per-vertex attribute streams bound by layer tweakers. 

By maintaining continuous presence of all geometric features across the transition threshold and driving visual emergence exclusively through paint opacity and radius scaling, the engine completely avoids vertex buffer invalidation.

### Staggered Geometric Phases Across $z \in [15.0, 16.5]$
The cross-scale visual handover operates through three staggered geometric phases:
1. **Station bullet pins** (`MLNCircleStyleLayer`) represent macro-scale centroids that gradually decay in opacity and physical screen radius, contracting toward their topological origin.
2. **Station boundary fills** (`MLNFillStyleLayer`) emerge slightly after bullet decay begins, providing an overlap band of 0.8 zoom levels wherein the structural shell becomes legible beneath the disappearing centroid.
3. **Platform edge strokes & tracks** (`MLNLineStyleLayer`) and **egress exit icons** (`MLNSymbolStyleLayer`) fade in once the floor boundary is firmly established.

### Mathematical Formulation of Continuous Transitions

1. **Station Bullet Pin Opacity ($z \in [15.0, 16.0]$):**
   $$\alpha_{\text{bullet}}(z) = \text{clamp}\left(1.0 - \frac{z - 15.0}{16.0 - 15.0}, \, 0.0, \, 1.0\right)$$

2. **Station Bullet Radius Contraction ($z \in [15.0, 16.0]$):**
   $$r_{\text{bullet}}(z) = \text{clamp}\left(6.0 - 3.0 \cdot \frac{z - 15.0}{16.0 - 15.0}, \, 3.0, \, 6.0\right)$$

3. **Station Polygon Footprint Fill Ingress ($z \in [15.2, 16.2]$):**
   $$\alpha_{\text{fill}}(z) = \text{clamp}\left(\frac{z - 15.2}{16.2 - 15.2}, \, 0.0, \, 1.0\right) \times 0.85$$

4. **Platform Edge Line Ingress & Width ($z \in [15.5, 16.5]$):**
   $$\alpha_{\text{line}}(z) = \text{clamp}\left(\frac{z - 15.5}{16.5 - 15.5}, \, 0.0, \, 1.0\right), \quad w_{\text{line}}(z) = 1.5 \cdot 2^{0.585 \cdot (z - 16.0)}$$

5. **Exit Portal Emergence ($z \in [16.0, 16.5]$):**
   $$\alpha_{\text{exit}}(z) = \text{clamp}\left(\frac{z - 16.0}{16.5 - 16.0}, \, 0.0, \, 1.0\right)$$

### Summary of Transition Profiles

| Transition Phase | Zoom Interval ($z$) | Style Layer Type | Target Property | Interpolation Mathematical Profile |
|:---|:---:|:---|:---|:---|
| **Centroid Decay** | $15.0 \to 16.0$ | `MLNCircleStyleLayer` | `circleOpacity` | Linear interpolation: $1.0 \to 0.0$ |
| **Centroid Contraction**| $15.0 \to 16.0$ | `MLNCircleStyleLayer` | `circleRadius` | Linear interpolation: $6.0\,\text{pt} \to 3.0\,\text{pt}$ |
| **Centroid Outline** | $15.0 \to 16.0$ | `MLNCircleStyleLayer` | `circleStrokeOpacity` | Linear interpolation: $1.0 \to 0.0$ |
| **Footprint Ingress** | $15.2 \to 16.2$ | `MLNFillStyleLayer` | `fillOpacity` | Linear interpolation: $0.0 \to 0.85$ |
| **Platform Stroke Ingress** | $15.5 \to 16.5$ | `MLNLineStyleLayer` | `lineOpacity` | Linear interpolation: $0.0 \to 1.0$ |
| **Platform Width Expansion**| $16.0 \to 20.0$ | `MLNLineStyleLayer` | `lineWidth` | Exponential curve ($\text{base} = 1.5$): $1.5\,\text{pt} \to 8.0\,\text{pt}$ |
| **Exit Portal Emergence** | $16.0 \to 16.5$ | `MLNSymbolStyleLayer` | `iconOpacity` | Linear interpolation: $0.0 \to 1.0$ |

---

## 2. Layer Hierarchy and Metal Rendering Pipeline Integration

### Layer Z-Stack Architecture
MapLibre Native processes scene rendering across an immutable base stack. Integrating micro-scale indoor station geometry into this arrangement requires strict preservation of spatial occlusion logic without compromising environmental fog or interactive HUD elements:
- Structural station floor plans (`station-interior-fill`) and platform lines (`station-platform-lines`) are injected **below the Fog layer** (`environmental-fog`). This ensures that unrevealed or geographically distant transit hubs remain shrouded beneath exploration fog masks.
- Macroscopic station bullet pins (`station-macro-bullet`) and microscopic exit symbols (`station-exit-symbols`) are injected **above the Fog and Unlocked Hexes strata**, directly beneath the Vicinity Bubble (`vicinity-bubble-overlay`), ensuring immediate navigational visibility.

```
+-----------------------------------------------------------------------------------+
| Top: Layer 7: vicinity-bubble-overlay (MLNFillStyleLayer - Radar & Touch Surface) |
+-----------------------------------------------------------------------------------+
|      Layer 6b: station-exit-symbols (MLNSymbolStyleLayer - Egress Portals)        |
+-----------------------------------------------------------------------------------+
|      Layer 6a: station-macro-bullet (MLNCircleStyleLayer - Macro Centroids)       |
+-----------------------------------------------------------------------------------+
|      Layer 5:  unlocked-hex-mesh (MLNLineStyleLayer - Discovered Territory Grid)  |
+-----------------------------------------------------------------------------------+
|      Layer 4:  environmental-fog (MLNFillStyleLayer - Volumetric H3 Fog Mask)     |
+-----------------------------------------------------------------------------------+
|      Layer 3b: station-platform-lines (MLNLineStyleLayer - Platforms & Tracks)    |
+-----------------------------------------------------------------------------------+
|      Layer 3a: station-interior-fill (MLNFillStyleLayer - 2D Station Footprints)  |
+-----------------------------------------------------------------------------------+
|      Layer 2:  subcontext-urban (MLNLineStyleLayer - Surface Roads & Parcels)     |
+-----------------------------------------------------------------------------------+
| Bot: Layer 1:  base-topography (MLNBackgroundStyleLayer - Land Cover & Water)     |
+-----------------------------------------------------------------------------------+
```

### Metal Execution Architecture: Drawables, Tweakers, and Pipeline State
MapLibre Native’s Metal engine decouples stylistic state representation from GPU command generation:
- Each style layer implements an `update()` cycle creating persistent `Drawable` instances.
- Per-frame mutations (camera matrices, zoom-interpolated colors, and alphas) are processed through **Tweakers**, which modify dynamic uniform buffers without touching vertex array memory.
- **Opaque vs. Translucent Render Passes:**
  - When evaluated opacity equals $1.0$, geometry is queued front-to-back in the **Opaque Pass** with depth writing enabled (`depthWriteEnabled = true`, `MTLCompareFunctionLessEqual`), maximizing Early-Z rejection in Apple Silicon Tile-Based Deferred Rendering (TBDR).
  - During the transition band $z \in [15.0, 16.5]$ where evaluated opacity $< 1.0$, drawables are assigned to the **Translucent Pass**: depth writing is disabled, alpha blending is activated (`MTLBlendFactorSourceAlpha`, `MTLBlendFactorOneMinusSourceAlpha`), and drawables render strictly in layer index order.
- **Eliminating Pipeline Stalls:** Dynamic layer insertion during active map navigation forces the engine to alter its layer tree, rebuild drawable index lists, and allocate fresh `MTLRenderPipelineState` objects. All transit layers must be **statically allocated and bound to the render graph at initial style compilation**, controlling visual throughput exclusively via uniform buffer alpha modulation.

---

## 3. Dynamic Multi-Level Floor Plan Filtering

### Predicate Evaluation vs. Paint Feature-State
Managing vertical station levels ($L = -1$ concourse, $L = -2$ platform) requires selective spatial isolation:
- **Mutating `MLNVectorStyleLayer.predicate`:** Operates as a selective visibility index during drawable compilation. Discards out-of-level drawables while retaining the pre-parsed tile bucket. Inactive floor vertices never enter the Metal command encoder, minimizing mobile GPU memory bandwidth.
- **Paint Feature-State (`setFeatureState`):** Forces every triangle across all vertical storeys through vertex transform passes, relying on fragment discarding. Mandates individual asynchronous state dispatches across features, increasing memory overhead.

| Architectural Attribute | Runtime Layer Predicates (`MLNVectorStyleLayer.predicate`) | Paint Feature-State (`setFeatureState`) |
|:---|:---|:---|
| **GPU Vertex Ingestion** | Minimal. Inactive floor geometry is culled before draw submission. | High. Vertices for all floors undergo transform passes. |
| **Metal Command Encoding** | Low draw call footprint; drawables match active floor boundaries. | Unaltered draw call count; inactive fragments blend transparently. |
| **CPU Tessellation Impact** | Zero re-tessellation; operates against pre-triangulated bucket cache. | Zero re-tessellation; updates uniform buffer lookup tables. |
| **Client Code Complexity** | Concise. Single predicate update applied across the style layer. | High. Requires feature ID mapping, state tracking, and batch dispatch. |
| **Multi-Level Connectors** | Evaluates string and array containment logic natively via predicates. | Requires duplicating state entries across interconnected features. |

### Type-Safe Filter Construction and Vertical Connectors
Vector tiles derived from heterogeneous transit databases often store floor levels as 64-bit integers or ASCII strings. Explicit runtime casting via `CAST()` resolves this discrepancy while string containment captures multi-level connectors (e.g., stairs/elevators spanning `levels = "-1;-2"`):

```swift
func makeFloorFilterPredicate(targetLevel: Int) -> NSPredicate {
    let levelString = String(targetLevel)
    return NSPredicate(
        format: """
        (CAST(level, 'NSString') == %@) OR 
        (levels != nil AND CAST(levels, 'NSString') CONTAINS %@) OR 
        (%@ IN levels)
        """,
        levelString, levelString, levelString
    )
}
```

---

## 4. High-Performance Data Architecture

### Vector Tile Packaging and Hardware-Accelerated Overzooming
Vector tiles generated up to zoom 22 result in file explosion and memory thrashing. The vector pipeline caps tiles at $\text{maxzoom} = 16$. When zooming beyond 16, MapLibre Native suppresses further fetching and scales the transformation matrix in vertex shaders:
$$\mathbf{M}_{\text{tile}} = \mathbf{M}_{\text{viewport}} \cdot \mathbf{T}_{\text{offset}} \cdot \begin{bmatrix} 2^{z - 16} & 0 & 0 & 0 \\ 0 & 2^{z - 16} & 0 & 0 \\ 0 & 0 & 1 & 0 \\ 0 & 0 & 0 & 1 \end{bmatrix}$$
Because vertex coordinates are already cached within Metal buffer objects on the GPU, overzoomed rendering executes with zero CPU overhead.

### In-Memory GeoJSON Source Optimizations (`MLNShapeSource`)
When using local `MLNShapeSource` for offline stations:
- `maximumZoomLevel: 16` halts internal pyramid tiling and activates overzoom logic.
- `clipsCoordinates: false` bypasses boundary polygon clipping algorithms.
- `clustered: false` suppresses point-clustering spatial evaluation.
- `synchronousUpdate: false` forces deserialization onto background worker threads.

```swift
func makeOptimizedStationSource(identifier: String, geoJSONData: Data) -> MLNShapeSource? {
    let sourceOptions: [MLNShapeSourceOption: Any] = [
        .maximumZoomLevel: 16,
        .clipsCoordinates: false,
        .clustered: false,
        .synchronousUpdate: false
    ]
    guard let shape = try? MLNShape(data: geoJSONData, encoding: String.Encoding.utf8.rawValue) else {
        return nil
    }
    return MLNShapeSource(identifier: identifier, shape: shape, options: sourceOptions)
}
```

---

## 5. Production Swift Implementation

```swift
import Foundation
import UIKit
import MapLibre

public final class StationTransitVisualizationManager {
    
    private weak var mapView: MLNMapView?
    private let sourceIdentifier = "transit-station-vector-source"
    
    private let bulletLayerId = "station-macro-bullet"
    private let footprintLayerId = "station-interior-fill"
    private let platformLayerId = "station-platform-lines"
    private let exitLayerId = "station-exit-symbols"
    
    public init(mapView: MLNMapView) {
        self.mapView = mapView
    }
    
    public func configureTransitLayers(
        in style: MLNStyle,
        subContextLayerId: String,
        fogLayerId: String,
        unlockedHexLayerId: String,
        vicinityBubbleLayerId: String
    ) {
        guard let source = style.source(withIdentifier: sourceIdentifier) else {
            assertionFailure("Vector source \(sourceIdentifier) must be added to style prior to layer binding.")
            return
        }
        
        // 1. Zoom Interpolation Expressions (Continuous Camera-Driven Functions)
        let bulletOpacity = NSExpression(
            format: "mgl_interpolate:withCurveType:parameters:stops:($zoomLevel, 'linear', nil, %@)",
            [15.0: 1.0, 16.0: 0.0]
        )
        
        let bulletRadius = NSExpression(
            format: "mgl_interpolate:withCurveType:parameters:stops:($zoomLevel, 'linear', nil, %@)",
            [15.0: 6.0, 16.0: 3.0]
        )
        
        let bulletStrokeOpacity = NSExpression(
            format: "mgl_interpolate:withCurveType:parameters:stops:($zoomLevel, 'linear', nil, %@)",
            [15.0: 1.0, 16.0: 0.0]
        )
        
        let footprintOpacity = NSExpression(
            format: "mgl_interpolate:withCurveType:parameters:stops:($zoomLevel, 'linear', nil, %@)",
            [15.2: 0.0, 16.2: 0.85]
        )
        
        let platformOpacity = NSExpression(
            format: "mgl_interpolate:withCurveType:parameters:stops:($zoomLevel, 'linear', nil, %@)",
            [15.5: 0.0, 16.5: 1.0]
        )
        
        let platformWidth = NSExpression(
            format: "mgl_interpolate:withCurveType:parameters:stops:($zoomLevel, 'exponential', 1.5, %@)",
            [16.0: 1.5, 20.0: 8.0]
        )
        
        let exitOpacity = NSExpression(
            format: "mgl_interpolate:withCurveType:parameters:stops:($zoomLevel, 'linear', nil, %@)",
            [16.0: 0.0, 16.5: 1.0]
        )
        
        // 2. Layer Instantiation
        let footprintLayer = MLNFillStyleLayer(identifier: footprintLayerId, source: source)
        footprintLayer.sourceLayerIdentifier = "station_footprints"
        footprintLayer.fillColor = NSExpression(forConstantValue: UIColor(red: 0.16, green: 0.18, blue: 0.22, alpha: 1.0))
        footprintLayer.fillOpacity = footprintOpacity
        footprintLayer.fillAntialiased = NSExpression(forConstantValue: true)
        
        let platformLayer = MLNLineStyleLayer(identifier: platformLayerId, source: source)
        platformLayer.sourceLayerIdentifier = "station_platforms"
        platformLayer.lineColor = NSExpression(forConstantValue: UIColor(red: 0.98, green: 0.72, blue: 0.24, alpha: 1.0))
        platformLayer.lineOpacity = platformOpacity
        platformLayer.lineWidth = platformWidth
        platformLayer.lineCap = NSExpression(forConstantValue: "round")
        platformLayer.lineJoin = NSExpression(forConstantValue: "round")
        
        let bulletLayer = MLNCircleStyleLayer(identifier: bulletLayerId, source: source)
        bulletLayer.sourceLayerIdentifier = "station_centroids"
        bulletLayer.circleRadius = bulletRadius
        bulletLayer.circleColor = NSExpression(forConstantValue: UIColor(red: 0.0, green: 0.48, blue: 1.0, alpha: 1.0))
        bulletLayer.circleOpacity = bulletOpacity
        bulletLayer.circleStrokeColor = NSExpression(forConstantValue: UIColor.white)
        bulletLayer.circleStrokeWidth = NSExpression(forConstantValue: 2.0)
        bulletLayer.circleStrokeOpacity = bulletStrokeOpacity
        
        let exitLayer = MLNSymbolStyleLayer(identifier: exitLayerId, source: source)
        exitLayer.sourceLayerIdentifier = "station_exits"
        exitLayer.iconImageName = NSExpression(forConstantValue: "station-exit-portal")
        exitLayer.iconOpacity = exitOpacity
        exitLayer.iconAllowsOverlap = NSExpression(forConstantValue: true)
        exitLayer.iconIgnoresPlacement = NSExpression(forConstantValue: true)
        
        // 3. Deterministic Z-Stack Injection
        if let fogLayer = style.layer(withIdentifier: fogLayerId) {
            style.insertLayer(footprintLayer, below: fogLayer)
            style.insertLayer(platformLayer, above: footprintLayer)
        } else if let subContextLayer = style.layer(withIdentifier: subContextLayerId) {
            style.insertLayer(footprintLayer, above: subContextLayer)
            style.insertLayer(platformLayer, above: footprintLayer)
        } else {
            style.addLayer(footprintLayer)
            style.addLayer(platformLayer)
        }
        
        if let vicinityLayer = style.layer(withIdentifier: vicinityBubbleLayerId) {
            style.insertLayer(bulletLayer, below: vicinityLayer)
            style.insertLayer(exitLayer, above: bulletLayer)
        } else if let hexLayer = style.layer(withIdentifier: unlockedHexLayerId) {
            style.insertLayer(bulletLayer, above: hexLayer)
            style.insertLayer(exitLayer, above: bulletLayer)
        } else {
            style.addLayer(bulletLayer)
            style.addLayer(exitLayer)
        }
        
        applyFloorFilter(level: -1)
    }
    
    public func applyFloorFilter(level: Int) {
        guard let style = mapView?.style else { return }
        
        let levelString = String(level)
        let predicate = NSPredicate(
            format: "(CAST(level, 'NSString') == %@) OR (levels != nil AND CAST(levels, 'NSString') CONTAINS %@)",
            levelString, levelString
        )
        
        let dynamicIndoorLayers = [footprintLayerId, platformLayerId, exitLayerId]
        for layerId in dynamicIndoorLayers {
            if let vectorLayer = style.layer(withIdentifier: layerId) as? MLNVectorStyleLayer {
                vectorLayer.predicate = predicate
            }
        }
    }
}
```

---

## 6. Declarative Style JSON Specification

```json
{
  "version": 8,
  "sources": {
    "transit-station-vector-source": {
      "type": "vector",
      "url": "pmtiles://https://cdn.transit-map.net/tiles/indoors.pmtiles",
      "maxzoom": 16
    }
  },
  "layers": [
    {
      "id": "station-interior-fill",
      "type": "fill",
      "source": "transit-station-vector-source",
      "source-layer": "station_footprints",
      "filter": [
        "any",
        ["==", ["to-string", ["get", "level"]], "-1"],
        ["in", "-1", ["to-string", ["get", "levels"]]]
      ],
      "paint": {
        "fill-color": "#292E38",
        "fill-opacity": [
          "interpolate",
          ["linear"],
          ["zoom"],
          15.2, 0.0,
          16.2, 0.85
        ],
        "fill-antialias": true
      }
    },
    {
      "id": "station-platform-lines",
      "type": "line",
      "source": "transit-station-vector-source",
      "source-layer": "station_platforms",
      "filter": [
        "any",
        ["==", ["to-string", ["get", "level"]], "-1"],
        ["in", "-1", ["to-string", ["get", "levels"]]]
      ],
      "layout": {
        "line-cap": "round",
        "line-join": "round"
      },
      "paint": {
        "line-color": "#FAB83D",
        "line-opacity": [
          "interpolate",
          ["linear"],
          ["zoom"],
          15.5, 0.0,
          16.5, 1.0
        ],
        "line-width": [
          "interpolate",
          ["exponential", 1.5],
          ["zoom"],
          16.0, 1.5,
          20.0, 8.0
        ]
      }
    },
    {
      "id": "station-macro-bullet",
      "type": "circle",
      "source": "transit-station-vector-source",
      "source-layer": "station_centroids",
      "paint": {
        "circle-radius": [
          "interpolate",
          ["linear"],
          ["zoom"],
          15.0, 6.0,
          16.0, 3.0
        ],
        "circle-color": "#007AFF",
        "circle-opacity": [
          "interpolate",
          ["linear"],
          ["zoom"],
          15.0, 1.0,
          16.0, 0.0
        ],
        "circle-stroke-width": 2.0,
        "circle-stroke-color": "#FFFFFF",
        "circle-stroke-opacity": [
          "interpolate",
          ["linear"],
          ["zoom"],
          15.0, 1.0,
          16.0, 0.0
        ]
      }
    },
    {
      "id": "station-exit-symbols",
      "type": "symbol",
      "source": "transit-station-vector-source",
      "source-layer": "station_exits",
      "filter": [
        "any",
        ["==", ["to-string", ["get", "level"]], "-1"],
        ["in", "-1", ["to-string", ["get", "levels"]]]
      ],
      "layout": {
        "icon-image": "station-exit-portal",
        "icon-allow-overlap": true,
        "icon-ignore-placement": true
      },
      "paint": {
        "icon-opacity": [
          "interpolate",
          ["linear"],
          ["zoom"],
          16.0, 0.0,
          16.5, 1.0
        ]
      }
    }
  ]
}
```
