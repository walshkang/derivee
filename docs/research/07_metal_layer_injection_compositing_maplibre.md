# Architectural Evaluation of Metal-Accelerated Layer Injection and Compositing in MapLibre Native iOS

Evaluating the migration of Dérivée's atmospheric fog rendering engine from an inverted GeoJSON vector mask (`MLNShapeSource` and `MLNFillStyleLayer`) to a hardware-accelerated Metal pipeline requires analyzing the structural mechanics of MapLibre Native for iOS (`MLNMapView`). 

The core architectural decision lies between placing an external `MTKView` overlay above the map canvas in the UIKit view hierarchy or injecting custom Metal render hooks directly into MapLibre Native's C++ rendering core via `MLNCustomStyleLayer`. This report analyzes the technical trade-offs between these paradigms, examining command encoder interoperability, context layer stacking, label occlusion, graphics memory consumption, and 120Hz gesture passthrough performance.

---

## 1. Comparative Paradigm Analysis: Overlay Architecture vs. Custom Layer Injection

Integrating custom graphics into a vector map engine introduces challenges regarding frame pacing, layer ordering, depth buffer management, and view interaction. The system can be structured using an external `MTKView` overlay, an in-pipeline `MLNCustomStyleLayer` injection, or a multi-pass offscreen render-to-texture (RTT) architecture.

| Architectural Vector | External `MTKView` Overlay | In-Pipeline `MLNCustomStyleLayer` | Multi-Pass Dual-`MapView` Compositing |
|:---|:---|:---|:---|
| **Pipeline Interoperability** | Out-of-band execution using an independent `MTKView` frame loop. | Direct injection into MapLibre's active `MTLRenderCommandEncoder`. | Dual render pipelines targeting intermediate offscreen framebuffers. |
| **Layer Stacking & Label Occlusion** | Rigid top-level overlay that occludes all vector map content, including symbols. | Precise z-index positioning between raster basemaps and label symbol layers. | Flexible layer separation achieved via multi-canvas framebuffer blending. |
| **GPU Target & Memory Footprint** | Allocates distinct drawable textures; requires a secondary compositing pass. | Zero auxiliary target allocation; reuses active framebuffers and depth targets. | High memory penalty due to duplicate tile backing stores and intermediate textures. |
| **Display Loop Synchronization** | Asynchronous frame pacing risk between `CAMetalLayer` and map rendering. | Single-pass frame lock synchronized with the engine camera state. | High frame-jitter risk from dual CPU-bound map state synchronizations. |
| **UIKit Interaction & Gestures** | Requires explicit touch passthrough (`isUserInteractionEnabled = false`). | Zero touch-system interaction; lives entirely inside the rendering core. | Complex event forwarding required if the overlay intercepts inputs. |
| **Maintenance & Core Version Risks** | Independent of MapLibre internals; relies on standard Apple MetalKit APIs. | Binds to Darwin bridge headers (`MLNCustomStyleLayer`). | High maintenance burden due to private state synchronization across instances. |

An external `MTKView` overlay isolates custom visual effects from MapLibre Native's release cycles. However, placing an `MTKView` above an `MLNMapView` in the UIKit hierarchy creates a rigid rendering boundary. The overlay renders over the entire map surface beneath it, obscuring road networks, spatial markers, and text labels (`MLNSymbolStyleLayer`).

`MLNCustomStyleLayer` addresses this limitation by executing native Metal draw commands within MapLibre Native's main render pass. Subclassing `MLNCustomStyleLayer` allows custom Metal commands to be inserted at any point in the style layer hierarchy using methods such as `insertLayer:belowLayer:`. This places spatial effects (such as dynamic fog or radar) above base raster imagery (`MLNRasterStyleLayer`) while allowing vector labels and POI icons (`MLNSymbolStyleLayer`) to render cleanly on top.

---

## 2. Pipeline Mechanics and Native Metal Command Encoding

MapLibre Native's Metal rendering backend exposes pipeline execution hooks through `MLNCustomStyleLayer` on iOS. When configured, the core renderer provides the active `MTLRenderCommandEncoder` directly to the custom layer during frame execution.

### Execution Lifecycle and Command Encoder Access

The lifecycle of an `MLNCustomStyleLayer` relies on three primary methods:
- **`didMoveToMapView:`** Executed when the layer is added to the map's style hierarchy. This phase initializes GPU resources, compiles Metal Shading Language (MSL) source files, creates `MTLRenderPipelineState` instances, and allocates vertex/uniform buffers.
- **`drawInMapView:withContext:`** Called on every frame update within MapLibre's render loop. The layer accesses the current frame's command encoder through its `renderEncoder` property, cast to an `id<MTLRenderCommandEncoder>`.
- **`willMoveFromMapView:`** Invoked when the layer is removed from the active style. This releases compiled state objects and GPU memory allocations.

When `drawInMapView:withContext:` is invoked, the engine's active `MTLRenderCommandEncoder` is already bound to the map's render targets, depth buffers, and stencil state. Custom layer implementations should not attempt to end the pass or rebind color attachments. Instead, they encode pipeline states, bind custom vertex and fragment buffers, set state parameters, and issue draw calls directly into the active render encoder. Custom fragments drawn at the map plane should output a depth value of `1.0` in clip space to align with MapLibre's fragment culling.

### Projection Matrix Mathematics and Near-Plane Clipping

Aligning custom Metal geometry with the geographic map surface requires transforming Mercator coordinates into clip space using parameters supplied in the `MLNStyleLayerDrawingContext` structure:

```objc
typedef struct MLNStyleLayerDrawingContext {
    CGSize size;
    CLLocationCoordinate2D centerCoordinate;
    double zoomLevel;
    CLLocationDirection direction;
    CGFloat pitch;
    CGFloat fieldOfView;
    MLNMatrix4 projectionMatrix;
} MLNStyleLayerDrawingContext;
```

Geographic coordinates are first converted to normalized Mercator space $[0.0, 1.0]$:

$$x_{\text{mercator}} = \frac{180.0 + \text{longitude}}{360.0}$$

$$y_{\text{mercator}} = \frac{180.0 - \frac{180.0}{\pi} \ln\left(\tan\left(\frac{\pi}{4} + \frac{\text{latitude} \cdot \pi}{360.0}\right)\right)}{360.0}$$

To position vertices correctly in 3D space, the shader transforms these normalized Mercator coordinates using the context's projection matrix:

$$\mathbf{v}_{\text{clip}} = \mathbf{M}_{\text{proj}} \cdot \begin{bmatrix} x_{\text{mercator}} \cdot 2^{\text{zoom}} \\ y_{\text{mercator}} \cdot 2^{\text{zoom}} \\ z_{\text{elevation}} \\ 1.0 \end{bmatrix}$$

At steep camera angles ($\text{pitch} > 60^\circ$), standard projection matrices can clip geometry near the camera. Recent versions of MapLibre Native updated `MLNCustomStyleLayer` by adding a dedicated `nearClippedProjectionMatrix`. This matrix adjusts the near clipping plane to prevent visual clipping artifacts near the horizon under high tilt.

### C++ Engine Refactoring, Build Flags, and API Stability

Integrating directly with `MLNCustomStyleLayer` introduces technical considerations across MapLibre Native releases:
- **API Status:** MapLibre documentation classifies `MLNCustomStyleLayer` as experimental, meaning public interface definitions may evolve across minor SDK versions.
- **Core Namespace Migration:** Recent updates migrated internal C++ namespaces from `mbgl` to `mln`. While Objective-C dynamic wrappers (`MLNCustomStyleLayer`) shield Swift code from these internal renames, low-level C++ rendering extensions must adapt to updated namespace declarations.
- **Compilation Flag Dependencies:** Binary releases distributed via SPM (such as `maplibre-gl-native-distribution`) require the `MLN_RENDER_BACKEND_METAL` preprocessor macro. If headers lack this build flag, Metal-specific properties like `renderEncoder` will fail to expose, defaulting to legacy backend structures.

---

## 3. Context Layer Stacking and Label Occlusion Strategies

Preserving the legibility of vector text, road labels, and POI symbols (`MLNSymbolStyleLayer`) above spatial visual effects is essential for map usability. Two main architectural patterns address this requirement.

```
Pattern A: In-Pipeline Inter-Layer Insertion
┌─────────────────────────────────────────────────────────────┐
│ [Layer 3] MLNSymbolStyleLayer (Station Labels, Road Text)   │  ▲ (Rendered On Top)
├─────────────────────────────────────────────────────────────┤  │
│ [Layer 2] MLNCustomFogLayer (Metal GPU Fog & Amber Border)  │  │ (Interleaved Pass)
├─────────────────────────────────────────────────────────────┤  │
│ [Layer 1] MLNLineStyleLayer / MLNFillStyleLayer (Transit)   │  │
├─────────────────────────────────────────────────────────────┤  │
│ [Layer 0] MLNRasterStyleLayer (Parchment Basemap Tiles)     │  │ (Base)
└─────────────────────────────────────────────────────────────┘
```

### Pattern A: In-Pipeline Inter-Layer Insertion

In-pipeline insertion places the custom layer directly into MapLibre Native's internal layer array using `insertLayer:belowLayer:`. During rendering, MapLibre draws style layers in sequential z-index order:
1. The engine renders background tiles (`MLNBackgroundStyleLayer`) and raster imagery (`MLNRasterStyleLayer`).
2. MapLibre executes the custom layer's Metal commands within the active pass.
3. The engine renders vector symbols (`MLNSymbolStyleLayer`) on top.

This approach requires no auxiliary framebuffers or intermediate offscreen target textures, writing output directly into the main render pass target. Executing commands within a single pass avoids target-switching overhead and tile store/load penalties. Furthermore, text labels remain naturally visible over the visual effect without requiring camera or state synchronization across separate instances.

### Pattern B: Multi-Pass Dual MapView / Offscreen Compositing

Multi-Pass compositing isolates visual effects by splitting map rendering across multiple rendering passes or distinct map view instances:
1. Basemap features are drawn into a primary offscreen render target.
2. Custom Metal effects (such as atmospheric fog) are rendered into a secondary target texture.
3. Label symbol layers are drawn into a separate transparent render pass.
4. The resulting textures are composited together before presenting the final frame.

This multi-pass approach introduces noticeable performance and memory costs:
- **VRAM Penalty:** Storing separate offscreen targets requires allocating auxiliary textures ($2 \times \text{width} \times \text{height} \times 4 \text{ bytes}$). On ProMotion displays ($2796 \times 1290$ at $3\times$ scale), each intermediate target consumes over $14\text{ MB}$ of GPU memory.
- **Phase Jitter:** Synchronizing two map views across gestures requires matching camera state parameters (`centerCoordinate`, `zoomLevel`, `pitch`, `direction`) on every frame update. Any frame timing mismatch between views causes visual jitter and label floating artifacts. In addition, running duplicate map instances doubles vector parsing, tile decoding, and draw call evaluation CPU overhead.

---

## 4. Swift and Objective-C++ Integration Blueprint

The following integration code demonstrates how to implement an `MLNCustomStyleLayer` that encodes custom Metal drawing operations directly inside MapLibre Native's iOS Metal render pass.

### 1. Metal Shader Implementation (`FogShader.metal`)

```metal
#include <metal_stdlib>
using namespace metal;

struct CustomVertexInput {
    float2 position [[attribute(0)]];
    float2 uv       [[attribute(1)]];
};

struct RasterizerData {
    float4 position [[position]];
    float2 uv;
};

struct Uniforms {
    float4x4 projectionMatrix;
    float4   fogColor;
    float    density;
    float    time;
};

vertex RasterizerData customLayerVertexShader(
    CustomVertexInput in [[stage_in]],
    constant Uniforms &uniforms [[buffer(1)]]
) {
    RasterizerData out;
    out.position = uniforms.projectionMatrix * float4(in.position, 0.0, 1.0);
    out.uv = in.uv;
    return out;
}

fragment float4 customLayerFragmentShader(
    RasterizerData in [[stage_in]],
    constant Uniforms &uniforms [[buffer(1)]]
) {
    float noise = sin(in.uv.x * 12.0 + uniforms.time) * cos(in.uv.y * 12.0 + uniforms.time);
    float alpha = clamp((noise * 0.5 + 0.5) * uniforms.density, 0.0, 1.0);
    return float4(uniforms.fogColor.rgb, alpha);
}
```

### 2. Objective-C++ Custom Style Layer (`MLNCustomFogLayer.mm`)

```objc
#import <MapLibre/MapLibre.h>
#import <Metal/Metal.h>
#import <simd/simd.h>

typedef struct __attribute__((packed)) {
    simd_float4x4 projectionMatrix;
    simd_float4   fogColor;
    float         density;
    float         time;
} CustomFogUniforms;

typedef struct {
    simd_float2 position;
    simd_float2 uv;
} CustomVertex;

@interface MLNCustomFogLayer : MLNCustomStyleLayer
@property (nonatomic, strong) id<MTLRenderPipelineState> pipelineState;
@property (nonatomic, strong) id<MTLBuffer> vertexBuffer;
@property (nonatomic, strong) id<MTLDepthStencilState> depthStencilState;
@property (nonatomic, assign) float timeAccumulator;
@end

@implementation MLNCustomFogLayer

- (instancetype)initWithIdentifier:(NSString *)identifier {
    self = [super initWithIdentifier:identifier];
    if (self) {
        _timeAccumulator = 0.0f;
    }
    return self;
}

- (void)didMoveToMapView:(MLNMapView *)mapView {
#if defined(MLN_RENDER_BACKEND_METAL)
    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    if (!device) return;

    NSError *error = nil;
    NSString *shaderSource = @"... MSL Source Code ...";
    id<MTLLibrary> library = [device newLibraryWithSource:shaderSource options:nil error:&error];
    if (!library) {
        NSLog(@"[MLNCustomFogLayer] Shader compilation failed: %@", error);
        return;
    }

    id<MTLFunction> vertexFunc = [library newFunctionWithName:@"customLayerVertexShader"];
    id<MTLFunction> fragmentFunc = [library newFunctionWithName:@"customLayerFragmentShader"];

    MTLVertexDescriptor *vertexDescriptor = [MTLVertexDescriptor vertexDescriptor];
    vertexDescriptor.attributes[0].format = MTLVertexFormatFloat2;
    vertexDescriptor.attributes[0].offset = offsetof(CustomVertex, position);
    vertexDescriptor.attributes[0].bufferIndex = 0;
    vertexDescriptor.attributes[1].format = MTLVertexFormatFloat2;
    vertexDescriptor.attributes[1].offset = offsetof(CustomVertex, uv);
    vertexDescriptor.attributes[1].bufferIndex = 0;
    vertexDescriptor.layouts[0].stride = sizeof(CustomVertex);

    MTLRenderPipelineDescriptor *pipelineDescriptor = [[MTLRenderPipelineDescriptor alloc] init];
    pipelineDescriptor.vertexFunction = vertexFunc;
    pipelineDescriptor.fragmentFunction = fragmentFunc;
    pipelineDescriptor.vertexDescriptor = vertexDescriptor;
    pipelineDescriptor.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
    pipelineDescriptor.colorAttachments[0].blendingEnabled = YES;
    pipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorSourceAlpha;
    pipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
    pipelineDescriptor.depthAttachmentPixelFormat = MTLPixelFormatDepth32Float_Stencil8;

    self.pipelineState = [device newRenderPipelineStateWithDescriptor:pipelineDescriptor error:&error];

    MTLDepthStencilDescriptor *depthDescriptor = [[MTLDepthStencilDescriptor alloc] init];
    depthDescriptor.depthCompareFunction = MTLCompareFunctionLessEqual;
    depthDescriptor.depthWriteEnabled = NO;
    self.depthStencilState = [device newDepthStencilStateWithDescriptor:depthDescriptor];

    CustomVertex quadVertices[] = {
        { {0.0f, 0.0f}, {0.0f, 0.0f} },
        { {1.0f, 0.0f}, {1.0f, 0.0f} },
        { {0.0f, 1.0f}, {0.0f, 1.0f} },
        { {1.0f, 1.0f}, {1.0f, 1.0f} }
    };
    self.vertexBuffer = [device newBufferWithBytes:quadVertices
                                            length:sizeof(quadVertices)
                                           options:MTLResourceStorageModeShared];
#endif
}

- (void)drawInMapView:(MLNMapView *)mapView withContext:(MLNStyleLayerDrawingContext)context {
#if defined(MLN_RENDER_BACKEND_METAL)
    id<MTLRenderCommandEncoder> encoder = (id<MTLRenderCommandEncoder>)self.renderEncoder;
    if (!encoder || !self.pipelineState) return;

    self.timeAccumulator += 0.016f;

    CustomFogUniforms uniforms;
    for (int i = 0; i < 16; i++) {
        uniforms.projectionMatrix.columns[i / 4][i % 4] = context.projectionMatrix.m[i];
    }
    
    uniforms.fogColor = simd_make_float4(0.88f, 0.92f, 0.95f, 0.55f);
    uniforms.density = 0.80f;
    uniforms.time = self.timeAccumulator;

    [encoder setRenderPipelineState:self.pipelineState];
    [encoder setDepthStencilState:self.depthStencilState];
    [encoder setVertexBuffer:self.vertexBuffer offset:0 atIndex:0];
    [encoder setVertexBytes:&uniforms length:sizeof(CustomFogUniforms) atIndex:1];
    [encoder setFragmentBytes:&uniforms length:sizeof(CustomFogUniforms) atIndex:1];

    [encoder drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0 vertexCount:4];
#endif
}

- (void)willMoveFromMapView:(MLNMapView *)mapView {
    self.pipelineState = nil;
    self.vertexBuffer = nil;
    self.depthStencilState = nil;
}

@end
```

### 3. Swift Map Interoperability Wrapper (`MapViewContainer.swift`)

```swift
import SwiftUI
import MapLibre

struct MapViewContainer: UIViewRepresentable {
    
    func makeUIView(context: Context) -> MLNMapView {
        let mapView = MLNMapView(frame: .zero)
        mapView.delegate = context.coordinator
        return mapView
    }

    func updateUIView(_ uiView: MLNMapView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator: NSObject, MLNMapViewDelegate {
        func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
            let fogLayer = MLNCustomFogLayer(identifier: "derived-atmospheric-fog")
            
            // Precise Z-Index Placement: Insert fog directly below text & icon symbols
            if let firstSymbolLayer = style.layers.first(where: { $0 is MLNSymbolStyleLayer }) {
                style.insertLayer(fogLayer, below: firstSymbolLayer)
            } else {
                style.addLayer(fogLayer)
            }
        }
    }
}
```

---

## 5. High-Frequency (120Hz) Gesture Event Passthrough and Responder Chain Dynamics

### Hit-Testing Mechanics and Responder Traversal

When an overlay view (such as an `MTKView`) is positioned over an `MLNMapView`, touch events trigger a hit-test search starting at the root `UIWindow`:

```objc
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event
```

UIKit checks three primary properties to determine if a view accepts touch events:
1. `isHidden == false`
2. `alpha > 0.01`
3. `isUserInteractionEnabled == true`

Setting `isUserInteractionEnabled = false` on an overlay view causes its implementation of `hitTest:withEvent:` to return `nil` immediately. UIKit then bypasses the overlay and routes the touch event to the underlying `MLNMapView`.

### 120Hz Gesture Momentum and Inertia Calculation

Disabling interaction on the overlay allows touch events to reach MapLibre Native's gesture recognizers (`UIPanGestureRecognizer`, `UIPinchGestureRecognizer`, and `UIRotationGestureRecognizer`) directly:
- **Touch Event Sampling:** High-frequency 120Hz/240Hz touch inputs pass directly to MapLibre without delay or event drops.
- **Velocity Decay:** MapLibre's momentum engines compute velocity vectors and deceleration curves directly from original `UITouch` timestamps.
- **Multi-Touch Gestures:** Pinch-to-zoom, two-finger pitch, and map rotation gestures process without input interruption or event cancellation.

### Frame Pacing and Presentation Synchronization

Although setting `isUserInteractionEnabled = false` resolves gesture routing for overlays, running an external `MTKView` alongside an `MLNMapView` can introduce display pacing challenges. An external `MTKView` operates on its own drawing lifecycle (driven by `CADisplayLink` or MetalKit timer loops), which runs asynchronously from MapLibre Native's core frame scheduler. This phase separation can cause subtle frame tearing or visual latency between map updates and overlay rendering during pan operations.

In contrast, `MLNCustomStyleLayer` executes commands inside MapLibre Native's main render pass. Because custom draw calls are encoded directly into the map's primary command encoder, visual effects update in exact lockstep with camera movement at 120Hz.

---

## 6. Strategic Recommendations and Engineering Outlook

1. **Adopt In-Pipeline Injection (`MLNCustomStyleLayer`):** For production spatial applications requiring custom graphics alongside visible map labels, `MLNCustomStyleLayer` provides the most efficient execution architecture. It avoids intermediate texture allocations, eliminates duplicate rendering work, and preserves label visibility above rendered effects.
2. **Encapsulate Experimental APIs:** Because `MLNCustomStyleLayer` is marked as experimental, custom Metal rendering code should be isolated behind bridge wrappers. Build configurations must ensure the `MLN_RENDER_BACKEND_METAL` macro is active across all target builds.
3. **Overlay Fallback Consideration:** If complete separation from MapLibre Native updates is required, an external `MTKView` overlay can be used for rapid prototyping. When using this approach, set `isUserInteractionEnabled = false` to preserve 120Hz gesture interaction with the underlying map view.
