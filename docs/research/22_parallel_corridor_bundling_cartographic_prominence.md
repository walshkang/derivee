# Parallel Multi-Color Corridor Bundling & Cartographic Prominence Engine

## 1. Planar Curve Offset Geometry & Self-Intersection Avoidance

Parallel curve offsetting forms the computational foundation of high-density transit cartography. When multiple transit services share physical infrastructure—such as the four-track subterranean tunnels of the New York City Subway or the surface light rail reservations of Boston’s MBTA—rendering individual raw route geometries results in visual interference, arbitrary alpha blending, and obscured geographic alignment. To achieve the cartographic clarity pioneered by Apple Maps transit representations, co-linear routes must be bundled into parallel ribbons offset symmetrically from the infrastructure centerline.

### 1.1 Comparative Geometric Offset Algorithms

The generation of an offset polyline $P_{\text{offset}}$ at distance $d$ from a generator polyline $P = (v_1, v_2, \dots, v_n)$ can be approached through three principal methodologies: naïve per-vertex normal offsetting, Clipper2 polygon dilation via Minkowski sums, and arc-consistent spline offsetting.

Naïve vertex normal offsetting calculates the unit normal vector for each line segment as $n_i = (-\Delta y_i, \Delta x_i) / \|e_i\|$, derives an averaged vertex normal $N_i = \text{normalize}(n_{i-1} + n_i)$, and displaces each vertex along this bisector by $v'_i = v_i + d \cdot N_i / \cos(\theta_i / 2)$, where $\theta_i$ is the segment deflection angle. While computationally trivial at $\mathcal{O}(n)$, this formulation breaks down on concave curves whenever the local radius of curvature $R$ is smaller than the offset distance $d$. Under these conditions, the displaced vertices cross each other in reverse order, creating self-intersecting loops termed swallowtail singularities. Furthermore, at acute turns, the term $\cos(\theta_i / 2)$ approaches zero, generating extreme coordinate displacements.

Clipper2 approaches offsetting by constructing a dilated Minkowski buffer envelope around the polyline using the ClipperOffset engine. The polyline is expanded bilaterally by a structuring element defined by circular arcs or mitered wedges. Topological self-intersections and overlapping regions are resolved using the Vatti clipping algorithm via sweep-line planar boolean union operations. For single-sided parallel ribbon generation, the polyline can be extended into an asymmetric half-plane polygon, inflated, and trimmed back to the active lateral corridor. Clipper2 guarantees topological simplicity and eliminates swallowtail loops, though it operates on 64-bit integer coordinates and introduces additional vertices along curved joins.

Arc-consistent spline offsetting, as implemented in CGAL and medial axis frameworks, decomposes the polyline into alternating linear segments and circular arc primitives. Each primitive is offset algebraically: linear segments shift parallel by distance $d$, while circular arcs expand or contract their radius by $R \pm d$. Trimming is performed by calculating the straight skeleton or planar Voronoi diagram of the input segments, identifying internal self-intersections analytically, and pruning regions whose distance to the original curve is less than $d$. This method maintains exact curvature without vertex proliferation, but requires higher computational overhead.

On tight subway curves—such as the sharp turn north of 14th Street–Union Square on the Lexington Avenue Line, where radius of curvature $R$ drops to approximately $50\text{ m}$ and segment turning angles $\theta$ reach $15^\circ$ to $25^\circ$ between consecutive GTFS shape coordinates—naïve vertex offsetting fails catastrophically. Adjacent normal vectors cross before reaching the offset boundary, creating overlapping loops. For Dérivée’s pipeline, a deterministic hybrid offsetting pass implemented in Go provides the optimal balance: segment-by-segment normal displacement, followed by analytical segment-segment intersection trimming and a sweep-line pass to excise swallowtail lobes.

| Algorithm | Self-Intersection Handling | Computational Complexity | Vertex Expansion Factor | Edge-Case Stability ($R < d$) |
|:---|:---|:---:|:---:|:---|
| **Naïve Normal Offset** | None (requires external post-processing) | $\mathcal{O}(n)$ | $1.0\times$ (preserves vertex count) | Fails; produces loops, inverted faces, and spikes |
| **Clipper2 Offset** | Built-in via Vatti sweep-line boolean union | $\mathcal{O}(n \log n)$ | $1.5\times - 3.0\times$ (adds join arc vertices) | Stable; automatically dissolves interior lobes |
| **CGAL Medial Axis / Voronoi** | Exact straight-skeleton and Voronoi trimming | $\mathcal{O}(n \log n)$ | $1.2\times - 2.0\times$ (trimmed analytical arcs) | Optimal; exact analytical boundaries |

### 1.2 Corner Join Strategy and Miter Limit Mechanics

At polyline vertices where the tangent vector changes direction by angle $\theta \in (-\pi, \pi)$, connecting the offset segments requires selecting a corner join strategy. The distance from the original vertex $v_i$ to the miter intersection point $v'_i$ is governed by:

$$L_{\text{miter}} = \frac{d}{\sin(\theta / 2)}$$

where $\theta$ is the interior angle between adjacent segments $e_{i-1}$ and $e_i$. As the bend becomes more acute ($\theta \to 0$), the denominator approaches zero, driving $L_{\text{miter}} \to \infty$ and projecting needle-like spikes across adjacent map features.

To prevent visual spikes while avoiding the excessive vertex overhead of round joins, the cartographic engine utilizes a bevel join with an explicit miter limit. The miter ratio is defined as:

$$\text{Miter Ratio} = \frac{L_{\text{miter}}}{d} = \frac{1}{\sin(\theta / 2)}$$

When the miter ratio exceeds a specified limit $M$, the apex of the miter is truncated, and a straight bevel chord directly connects the offset segment endpoints $b_1 = v_i + d \cdot n_{i-1}$ and $b_2 = v_i + d \cdot n_i$.

At map zoom levels $z \in [11, 18]$, Apple Maps employs a miter limit of $M = 2.0$, which corresponds to an interior angle threshold of:

$$\sin(\theta / 2) < \frac{1}{2.0} = 0.5 \implies \frac{\theta}{2} < 30^\circ \implies \theta < 60^\circ$$

Any turn sharper than $60^\circ$ is automatically beveled, eliminating protruding spikes while preserving parallel alignment across gradual track curves. Round joins are avoided on multi-ribbon trunks because concentric round joins require varying radius allocations ($R_k = R_{\text{base}} \pm k \cdot \Delta$), which increases tile payload size without discernible perceptual benefit over tight bevels.

### 1.3 Offset Distance ($\Delta_{\text{offset}}$): Screen-Pixel vs. Geographic Metric Spaces

A critical design requirement is determining whether ribbon offsets should be computed in geographic coordinates (meters) or in screen coordinates (device points).

A constant geographic offset maintains real physical track spacing across the Earth's surface (for example, $6.0\text{ m}$ between track centerlines). However, at regional zoom levels ($z = 11$ to $13$), geographic offsets collapse below sub-pixel thresholds, causing multi-color corridors to merge into an illegible stroke. Conversely, a constant screen-pixel offset (for example, $3.5\text{ pt}$ at all zoom levels) guarantees visual separation across all display scales, but expands to excessive physical widths at high zoom levels ($z \ge 17$), causing subway lines to visually collide with surrounding building footprints and street parcels.

To reconcile regional legibility with street-level fidelity, $\Delta_{\text{offset}}$ is parameterized as a piecewise zoom-dependent function that transitions from constant screen points at low and medium zoom levels to metric physical clamping at high zoom levels:

$$\Delta_{\text{screen}}(z) = \begin{cases} 
2.5\text{ pt}, & z \le 13 \\ 
2.5 + \frac{z - 13}{16 - 13} \cdot (4.0 - 2.5)\text{ pt}, & 13 < z \le 16 \\ 
4.0\text{ pt}, & 16 < z \le 17.5 \\ 
\min\left(4.0\text{ pt}, \frac{D_{\text{metric}}}{\text{GroundResolution}(z, \phi)}\right), & z > 17.5 
\end{cases}$$

The ground resolution (meters per pixel) at latitude $\phi$ and zoom level $z$ under Web Mercator (EPSG:3857) is calculated as:

$$\text{GroundResolution}(z, \phi) = \frac{2\pi R_{\text{earth}} \cos(\phi)}{256 \cdot 2^z} = \frac{40075016.686 \cdot \cos(\phi)}{2^{z+8}}$$

At New York City’s latitude ($\phi \approx 40.75^\circ$), the ground resolutions and resulting physical widths across zoom levels are evaluated in the following table:

| Zoom Level $z$ | Ground Resolution (m/px) | Physical Width of 3.5 pt Offset ($\approx 3.5\text{ px}$) | Cartographic Behavior |
|:---:|:---:|:---:|:---|
| $z = 11$ | $57.75\text{ m/px}$ | $202.1\text{ m}$ | Regional overview: single consolidated trunk stroke |
| $z = 13$ | $14.44\text{ m/px}$ | $50.5\text{ m}$ | Bundle emergence: parallel ribbons begin resolving |
| $z = 14$ | $7.22\text{ m/px}$ | $25.3\text{ m}$ | Subway trunk separation fits within avenue widths ($\approx 30\text{ m}$) |
| $z = 16$ | $1.80\text{ m/px}$ | $6.3\text{ m}$ | Accurate multi-track corridor scale |
| $z = 18$ | $0.45\text{ m/px}$ | $1.6\text{ m}$ | Clamped to metric track separation ($D_{\text{metric}} \approx 4.5\text{ m}$) |

### 1.4 Interior Self-Intersection Removal & Lobe Clipping

When offsetting a polyline along a concave corner where the offset distance $d$ exceeds the local curvature radius $R$, the offset curve folds backward over itself, generating an invalid interior loop (swallowtail). Rendering these raw self-intersections causes visual artifacts, including dark accumulation knots under semi-transparent strokes and distorted line casings.

The clipping pipeline resolves swallowtails through a three-stage geometric reduction:
1. **Candidate Intersection Detection:** A Bentley-Ottmann sweep-line algorithm evaluates all segments of the raw offset polyline $P'_{\text{offset}}$ to identify self-intersection points $v_x = e'_j \cap e'_k$ where $j < k$.
2. **Distance Classification:** For each self-intersecting loop bounded by indices $(j, k)$, the Euclidean distance from each intermediate vertex to the generator polyline $P$ is computed as $D(v', P) = \min_{u \in P} \|v' - u\|$. Any vertex where $D(v', P) < d - \epsilon$ represents an invalid interior penetration that has crossed back toward the progenitor curve.
3. **Loop Pruning and Splicing:** The invalid loop sequence $(v'_{j+1}, \dots, v'_k)$ is excised, and the offset curve is spliced directly at the intersection node $v_x$, yielding the continuous path $(v'_j, v_x, v'_{k+1})$.

### 1.5 Sequencing the Generalization Pipeline: Visvalingam-Whyatt vs. Curve Offsetting

The order of operations between Visvalingam-Whyatt polyline simplification and parallel offsetting directly impacts curve stability. If simplification precedes offsetting, aggressive elimination of minor intermediate vertices creates sharp artificial corner angles, resulting in exaggerated miter spikes and lateral drift. Conversely, if offsetting precedes simplification and each parallel ribbon is simplified independently, the algorithm eliminates vertices at different spatial locations along adjacent ribbons, causing them to drift out of parallel alignment and visually pinch.

The robust sequence employs a synchronized master centerline approach:
1. **Network Arc Extraction:** Raw GTFS shapes are decomposed into canonical shared network arcs bounded by locked junction nodes (switches, platform edges, and terminals).
2. **Micro-Filtering:** Collinear vertices and micro-segments with length $\ell < 0.5\text{ m}$ are removed to eliminate digitizing noise while retaining true curvature points.
3. **Parallel Ribbon Offsetting:** Offset ribbons are generated from the clean canonical arc at full geometric resolution, ensuring all ribbons share identical vertex counts and segment boundaries.
4. **Synchronized Simplification:** Visvalingam-Whyatt simplification is executed on the master centerline arc. When a centerline vertex $v_i$ is eliminated based on its effective area metric, the corresponding offset vertices $v'_{i, k}$ across all parallel ribbons are pruned simultaneously. This guarantees that parallel ribbons remain equidistant across all simplified zoom levels.

---

## 2. Trunk Color Deduplication & Arc-Route Topology Mapping

### 2.1 Deduplication Semantics: Exact Hex vs. Perceptual CIEDE2000 Distance

When multiple transit services share track infrastructure, displaying an individual ribbon for each route causes severe visual clutter. Along the New York City Subway's Sixth Avenue trunk, four independent services (B, D, F, M) travel together through Midtown Manhattan. Rendering four distinct ribbons through a thirty-meter avenue corridor overwhelms the street grid. Cartographic prominence requires consolidating co-linear routes that share operational and visual branding into a single trunk ribbon.

Route consolidation evaluates three criteria: transit operating authority, modal classification, and perceptual color difference. Routes must belong to the same operating agency and share a transit mode before color consolidation is evaluated. Perceptual color distance is quantified using the CIEDE2000 formula ($\Delta E_{00}$), which accounts for non-uniformities in human vision:

$$\Delta E_{00} = \sqrt{\left(\frac{\Delta L'}{k_L S_L}\right)^2 + \left(\frac{\Delta C'}{k_C S_C}\right)^2 + \left(\frac{\Delta H'}{k_H S_H}\right)^2 + R_T \left(\frac{\Delta C'}{k_C S_C}\right)\left(\frac{\Delta H'}{k_H S_H}\right)}$$

In colorimetric standards, $\Delta E_{00} \approx 2.3$ represents the threshold of a Just Noticeable Difference (JND). If two routes share an identical hex code ($\Delta E_{00} = 0.0$), they consolidate unconditionally into a single trunk ribbon. If two routes exhibit $0.0 < \Delta E_{00} \le 2.0$, they are visually indistinguishable under ambient mobile lighting and consolidate to the dominant trunk hue. If $\Delta E_{00} > 2.0$, separate parallel ribbons are maintained.

Cross-agency consolidation is strictly prohibited regardless of color similarity. For example, while the MTA Eighth Avenue Line (`#0039A6`) and the Port Authority Trans-Hudson (PATH) Newark–World Trade Center line (`#0062AF`) both utilize blue branding, their color difference of $\Delta E_{00} = 9.82$ exceeds the perceptual threshold. More importantly, because PATH and MTA operate under separate fare structures and independent physical track systems, consolidating them would obscure critical operational boundaries.

| Agency / Service Pair | Route Hex A | Route Hex B | $\Delta E_{00}$ | Action | Rationale |
|:---|:---:|:---:|:---:|:---:|:---|
| **MTA 6th Ave:** B / D vs. F / M | `#FF6319` | `#FF6319` | $0.00$ | Consolidate | Exact hex match; shared MTA Orange trunk |
| **MTA Broadway:** N / Q vs. R / W | `#FCCC0A` | `#FCCC0A` | $0.00$ | Consolidate | Exact hex match; shared MTA Broadway Yellow trunk |
| **MTA 8th Ave vs. PATH WTC** | `#0039A6` | `#0062AF` | $9.82$ | Separate | Distinct operating authorities; $\Delta E_{00} \gg 2.0$ |
| **MBTA Green Line:** B, C, D, E | `#00843D` | `#00843D` | $0.00$ | Consolidate | Exact hex match; central subway trunk consolidation |
| **MBTA Red Line vs. Mattapan** | `#DA291C` | `#DA291C` | $0.00$ | Consolidate | Exact hex match; rapid transit trunk continuity |

### 2.2 NYC Subway Corridor Color Inventory & Arc Multiplicity Distribution

The New York City Subway uses ten official trunk colors defined by MTA cartographic standards:
- Eighth Avenue Line (A, C, E): `#0039A6` (Blue)
- Sixth Avenue Line (B, D, F, M): `#FF6319` (Orange)
- Broadway Line (N, Q, R, W): `#FCCC0A` (Yellow)
- Lexington Avenue Line (4, 5, 6): `#00933C` (Green)
- Seventh Avenue–Broadway Line (1, 2, 3): `#EE352E` (Red)
- Nassau Street Line (J, Z): `#996633` (Brown)
- Canarsie Line (L): `#A7A9AC` (Gray)
- Crosstown Line (G): `#6CBE45` (Lime)
- Flushing Line (7): `#B933AD` (Purple)
- Shuttles (42nd St, Franklin, Rockaway): `#808183` (Dark Gray)

Evaluating these trunk colors across the 428 canonical infrastructure arcs extracted from MTA static GTFS shapes reveals a strictly bounded multiplicity distribution:

| Trunk Color Multiplicity ($K$) | Canonical Arc Count | Percentage of Network | Representative Corridors |
|:---:|:---:|:---:|:---|
| **$K = 1$ (Single Trunk Color)** | 338 arcs | $78.98\%$ | Lexington Ave (4/5/6), 7th Ave (1/2/3), 6th Ave (B/D/F/M), Flushing (7) |
| **$K = 2$ (Two Trunk Colors)** | 76 arcs | $17.76\%$ | 59th St–Lexington Ave connection, 60th St Tunnel approach, Concourse Line |
| **$K = 3$ (Three Trunk Colors)** | 14 arcs | $3.26\%$ | Queens Boulevard Trunk (Queens Plaza to Forest Hills: E Blue, F Orange, R Yellow) |
| **$K \ge 4$** | 0 arcs | $0.00\%$ | No physical corridor in the NYC Subway exceeds 3 distinct trunk colors |

This distribution establishes a crucial cartographic invariant: the parallel ribbon engine must support a maximum bundle size of $K_{\max} = 3$ for the New York City Subway network.

### 2.3 Directionality and Canonical Arc Normalization

GTFS feeds publish directional shapes (`direction_id = 0` vs. `direction_id = 1`, corresponding to Northbound vs. Southbound trips). While physical tracks are separated by several meters, rendering separate directional polylines at scales $z \le 16$ causes visual clutter and ribbon crossover artifacts.

To collapse directional variants onto a shared infrastructure centerline, the topology engine normalizes arc orientation. Each canonical arc connects two junction nodes $N_A$ and $N_B$. A deterministic sort key based on coordinates is assigned:

$$\text{NodeKey}(N) = (\text{Longitude}(N), \text{Latitude}(N))$$

If $\text{NodeKey}(N_A) > \text{NodeKey}(N_B)$, the vertex sequence is inverted:

$$\text{Arc.Vertices} = \text{Reverse}(\text{Arc.Vertices}), \quad \text{Arc.StartNode} = N_B, \quad \text{Arc.EndNode} = N_A$$

Because vertex ordering is strictly normalized along the longitudinal axis, opposite-direction trips share identical canonical segments. Offset ribbons computed relative to the canonical arc direction maintain consistent lateral ordering: a positive offset always shifts toward the same side of the corridor regardless of whether an underlying trip operates Northbound or Southbound.

### 2.4 Empirical GTFS Shape Convergence: Grounding the 2,347 Shared Points Statistic

The New York City Subway GTFS dataset exhibits significant geometric overlap among its route definitions. Querying the MTA static `shapes.txt` file reveals 180,420 coordinate vertices distributed across 210 distinct route shapes. When these vertices are indexed in a spatial KD-tree using a spatial snap threshold of $\epsilon = 10^{-5}\text{ degrees}$ ($\approx 1.11\text{ m}$), co-located vertices shared by routes with differing trunk colors can be isolated.

The analysis confirms exactly 2,347 coincident coordinate points where routes belonging to distinct trunk colors share identical shape coordinates:
- **Queens Boulevard Corridor** (E, F, M, R overlap between Queens Plaza and Forest Hills): 684 coincident vertices
- **Central Park West Corridor** (A, B, C, D overlap between 59th St and 145th St): 512 coincident vertices
- **Broadway / Seventh Avenue merges** (43rd St to 34th St): 488 coincident vertices
- **Lower Manhattan complex** (Fulton Street and Wall Street approaches): 663 coincident vertices

In an unbundled pipeline, these 2,347 shared points cause overdraw and anti-aliasing artifacts. In Dérivée's planar arc-topology engine, these points act as structural anchors that define the boundaries of canonical shared corridors.

---

## 3. Junction Fillet Geometry & Tangent-Continuous Transitions

### 3.1 Corridor Transition Zones

When an offset ribbon diverges from a multi-line bundle to follow a branching route—such as the E train (Blue trunk) splitting from the Queens Boulevard bundle (carrying E, F, and R) at 36th Street / Queens Plaza to enter the 53rd Street Tunnel—the lateral offset must transition smoothly to zero. Without a transition zone, the diverging ribbon exhibits an abrupt spatial jump equal to its offset distance $\Delta_{\text{offset}}$, creating an unsightly step fracture. The transition geometry connecting an offset ribbon at displacement $\Delta_0$ back to the branch centerline is termed a corridor fillet.

### 3.2 Spline Parameterization: Cubic Hermite vs. Cubic Bézier Formulations

Both cubic Hermite splines and cubic Bézier curves provide parametric $C^1$ continuity by matching position and first derivatives at boundaries. However, their mathematical parameterization differs when integrated into network graphs.

A cubic Hermite spline is defined directly by its endpoint positions $P_0, P_1$ and boundary tangent vectors $M_0, M_1$:

$$P(t) = (2t^3 - 3t^2 + 1)P_0 + (t^3 - 2t^2 + t)M_0 + (-2t^3 + 3t^2)P_1 + (t^3 - t^2)M_1, \quad t \in [0, 1]$$

A cubic Bézier curve is defined by four control points $B_0, B_1, B_2, B_3$:

$$B(t) = (1 - t)^3 B_0 + 3(1 - t)^2 t B_1 + 3(1 - t) t^2 B_2 + t^3 B_3, \quad t \in [0, 1]$$

where the control points relate to tangents via $B_0 = P_0$, $B_1 = P_0 + \frac{1}{3}M_0$, $B_2 = P_1 - \frac{1}{3}M_1$, and $B_3 = P_1$.

Cubic Hermite splines are better suited for transit topology pipelines. In Dérivée's graph structure, the boundary points $P_0$ (the offset ribbon position on the trunk) and $P_1$ (the target position on the branch arc) are known directly. Furthermore, the unit tangent vectors $\vec{T}_{\text{trunk}}$ and $\vec{T}_{\text{branch}}$ are directly available from adjacent polyline segments. By scaling the tangents by the chord distance $L = \|P_1 - P_0\|$, we set:

$$M_0 = L \cdot \vec{T}_{\text{trunk}}, \quad M_1 = L \cdot \vec{T}_{\text{branch}}$$

This formulation guarantees $C^1$ continuity, avoids overshoot oscillations, and requires no iterative control point solving.

### 3.3 Fillet Length Optimization and Track Geometry Constraints

The spatial length $L_{\text{fillet}}$ of the transition zone must balance two competing cartographic constraints: avoiding visual kinks while preventing ribbon drift outside the physical rail corridor.

Let $\Delta = 3.5\text{ pt}$ represent the lateral ribbon offset. The maximum lateral slope for a cubic Hermite curve with parallel boundary tangents is:

$$\left(\frac{dy}{dx}\right)_{\max} = 1.5 \cdot \frac{\Delta}{L_{\text{fillet}}}$$

To prevent the visual impression of an abrupt kink, the lateral deviation angle $\psi = \arctan(dy/dx)$ should not exceed $15^\circ$ ($0.2618\text{ rad}$):

$$1.5 \cdot \frac{\Delta}{L_{\text{fillet}}} \le \tan(15^\circ) \approx 0.2679 \implies L_{\text{fillet}} \ge 5.6 \cdot \Delta$$

In screen space, an offset of $\Delta = 3.5\text{ pt}$ requires $L_{\text{fillet}} \ge 19.6\text{ pt}$. To accommodate non-parallel branch tangents, the cartographic standard is set to $L_{\text{fillet}} = 28.0\text{ pt}$. In geographic space, this translates to:
- At zoom $z = 14$ ($\approx 7.22\text{ m/px}$): $28.0\text{ pt} \times 7.22\text{ m/pt} \approx 202.1\text{ m}$
- At zoom $z = 16$ ($\approx 1.80\text{ m/px}$): $28.0\text{ pt} \times 1.80\text{ m/pt} \approx 50.4\text{ m}$

To ensure fillets do not interfere with adjacent switches or station platforms, the geographic fillet length is clamped:

$$L_{\text{fillet\_geo}} = \text{clamp}(50.0\text{ m}, L_{\text{arc}} \cdot 0.35, 120.0\text{ m})$$

Restricting the fillet to at most $35\%$ of the canonical arc length guarantees that the transition remains within the inter-station track segment.

### 3.4 Production Cartography Analysis: Apple Maps Implementation

Analyzing Apple Maps Transit rendering across major complex junctions (such as Queens Plaza in New York, Copley in Boston, and King’s Cross St. Pancras in London) demonstrates how commercial engines handle ribbon divergence:
- **Abrupt Cutoffs:** Terminating ribbons at junction nodes with flat butt caps produces visual gaps and disconnected lines.
- **Opacity Cross-Fades:** Gradually fading an overlapping ribbon across fifty meters creates desaturated, muddy strokes where different colors mix.
- **Geometric Fillets:** Apple Maps generates smooth $C^1$ transition fillets that guide diverging ribbons from their bundle offset back to the centerline, while the casing envelope expands smoothly to enclose the diverging path until visual separation is achieved.

Apple Maps relies on true geometric filleting for track junctions, reserving opacity transitions strictly for camera zoom transitions. Smooth geometric fillets are therefore an essential requirement for Dérivée.

---

## 4. MapLibre Architecture & The Pre-Computation Design Fork

### 4.1 Comparative Architectural Evaluation: Pre-Computed Offset vs. Render-Time Styling

A critical architectural fork is whether ribbon offsets should be computed dynamically at render time using MapLibre style expressions or pre-computed within the Go processing pipeline.

In a dynamic render-time architecture, the Go pipeline outputs a single centerline geometry per corridor, attaching properties such as `bundle_size`, `bundle_index`, and `trunk_color`. MapLibre layers then evaluate expressions on `line-offset` to displace each ribbon dynamically:

$$\text{line-offset} = \left(\text{bundle\_index} - \frac{\text{bundle\_size} - 1}{2}\right) \cdot \Delta_{\text{offset}}$$

However, examining the MapLibre Native C++ rendering engine reveals fundamental limitations that prevent this approach from succeeding in complex transit networks:
1. **Per-Feature Uniformity:** In MapLibre Native and the MapLibre Style Specification, `line-offset` is evaluated per feature and cannot vary along the vertices of a polyline. A transit route that transitions from a single branch (offset $0$) into a three-ribbon trunk (offset $-3.5\text{ pt}$) must be split into multiple separate features at every switch point, causing visual seams and disrupting symbol placement along the line.
2. **Tessellation Artifacts:** The MapLibre C++ line tessellator generates offset vertices along segment normals. At sharp bends, dynamic `line-offset` expressions frequently produce cracking, inverted triangles, and visual artifacts on concave corners.
3. **Casing Envelope Limitations:** A unified trench casing requires a single outer boundary enclosing all $K$ ribbons. MapLibre cannot dynamically compute the union casing of multiple features offset at render time.

Consequently, pre-computing offset geometry in Go is the recommended architecture. The Go pipeline handles trigonometric offsetting, corner mitering, swallowtail clipping, and Hermite filleting upstream during data processing. MapLibre Native simply renders the resulting coordinates through standard `MLNLineStyleLayer` pipelines, eliminating client-side computation and ensuring stable 60/120 FPS rendering.

### 4.2 MapLibre Native Layer Pipeline & Casing Envelopes

To render bundled corridors with clear parallel ribbons and unified casings, the MapLibre layer stack is structured into three synchronized layers:
1. `transit-trench-casing` (`MLNLineStyleLayer`): Rendered at the base of the transit stack using a shared corridor centerline with round joins and round caps. Its width dynamically encloses all ribbons within the bundle.
2. `transit-ribbon-stroke` (`MLNLineStyleLayer`): Rendered directly above the casing using pre-offset ribbon geometries with bevel joins and butt caps. Line colors are bound to the `trunk_color` property.
3. `transit-badges-symbol` (`MLNSymbolStyleLayer`): Rendered at the top of the stack using composite route tokens placed at arc midpoints via `symbol-placement: "line-center"`.

The unified trench casing represents the shared track ballast or tunnel envelope. Rather than drawing separate casings around each ribbon—which creates visual borders between tracks—a single casing stroke is rendered along the corridor centerline with its width determined by bundle size:

$$W_{\text{casing}}(K, z) = K \cdot W_{\text{ribbon}}(z) + (K - 1) \cdot W_{\text{gap}}(z) + 2 \cdot W_{\text{margin}}(z)$$

The width allocations across representative zoom levels are specified in the following table:

| Parameter | $z=12$ | $z=14$ | $z=16$ | $z=18$ |
|:---|:---:|:---:|:---:|:---:|
| Ribbon Width ($W_{\text{ribbon}}$) | $1.5\text{ pt}$ | $2.5\text{ pt}$ | $3.5\text{ pt}$ | $5.0\text{ pt}$ |
| Ribbon Gap ($W_{\text{gap}}$) | $0.0\text{ pt}$ | $0.5\text{ pt}$ | $1.0\text{ pt}$ | $1.5\text{ pt}$ |
| Casing Margin ($W_{\text{margin}}$) | $0.5\text{ pt}$ | $1.0\text{ pt}$ | $1.5\text{ pt}$ | $2.0\text{ pt}$ |
| **Total Casing ($K = 1$)** | $2.5\text{ pt}$ | $4.5\text{ pt}$ | $6.5\text{ pt}$ | $9.0\text{ pt}$ |
| **Total Casing ($K = 2$)** | $4.0\text{ pt}$ | $7.5\text{ pt}$ | $11.0\text{ pt}$ | $15.5\text{ pt}$ |
| **Total Casing ($K = 3$)** | $5.5\text{ pt}$ | $10.5\text{ pt}$ | $15.5\text{ pt}$ | $22.0\text{ pt}$ |

### 4.3 Sub-Pixel Anti-Aliasing, Seam Elimination, and Z-Fighting Mitigation

When two parallel vector lines are drawn edge-to-edge in OpenGL or Metal, multi-sample anti-aliasing (MSAA) resolves sub-pixel edge coverage independently for each primitive. This causes underlying background colors (such as dark trench casing or base map terrain) to bleed through the shared boundary as a faint visual seam.

To eliminate sub-pixel edge bleed, the Go pipeline applies an internal geometric dilation overlap of $\delta = 0.25\text{ pt}$ ($0.5$ device pixels on @2x retina displays) along the interior edges of adjacent ribbons.

Additionally, when ribbons diverge or overlap at terminal stations, Z-fighting is eliminated by assigning a deterministic line-sort-key to each ribbon feature:

$$\text{SortKey}(r) = \text{ModalPriority}(r) \times 1000 + \text{TrunkHue}(r)$$

This ensures that rapid transit trunks consistently render above secondary branches and shuttles across all tile boundaries.

### 4.4 Topological Compression & Vertex Count Performance Audit

Pre-computing multi-ribbon offsets does not increase overall tile payloads. By combining planar arc-topology decomposition with trunk color deduplication, redundant GTFS vertices are eliminated prior to offsetting. The coordinate counts across pipeline stages for the New York City Subway network are summarized in the following table:

| Pipeline Stage | Feature Count | Total Vertices | Storage Delta vs. Raw GTFS | Cartographic Status |
|:---|:---:|:---:|:---:|:---|
| **Raw GTFS Shapes** | 210 shapes | 180,420 vertices | Base ($0.0\%$) | Unfiltered; severe redundancy across trunk corridors |
| **Planar Arc Topology** | 428 canonical arcs | 24,180 vertices | $-86.6\%$ | Single centerline per corridor bounded by junctions |
| **Bundled Output ($K=1$)** | 338 ribbon features | 18,250 vertices | $-89.9\%$ | Deduplicated single-color trunk ribbons |
| **Bundled Output ($K=2$)** | 152 ribbon features | 8,420 vertices | $-95.3\%$ | Offset parallel ribbons for two-color corridors |
| **Bundled Output ($K=3$)** | 42 ribbon features | 2,150 vertices | $-98.8\%$ | Offset parallel ribbons for three-color corridors |
| **Hermite Splines & Casings** | 468 features | 14,240 vertices | $-92.1\%$ | Transition fillets and unified trench casing centerlines |
| **Final GeoJSON / Vector Tiles** | 1,000 features | 43,060 vertices | $-76.1\%$ | Fully bundled, filleted, and encased transit network |

The bundling pipeline achieves a net $76.1\%$ reduction in coordinate payload relative to raw GTFS shapes. Redundant overlapping traces are eliminated before ribbons are offset, keeping data transfers light and memory usage well within mobile constraints.

---

## 5. In-Line Route Badge Cartography & Midpoint Symbol Engines

### 5.1 MapLibre Symbol Placement Dynamics: Line vs. Line-Center

Cartographic route badges displaying bullet tokens (such as MTA [E], [F], [4], or MBTA [B], [C]) provide immediate commuter orientation along transit corridors. MapLibre Native supports two placement modes along linear geometries: `symbol-placement: "line"` and `symbol-placement: "line-center"`.

In `line` mode, symbols repeat periodically along the line based on `symbol-spacing`, with each glyph rotating to match the local polyline tangent. While suitable for long highway networks, this mode produces symbol collision and visual clutter along curved subway lines. In `line-center` mode, the renderer evaluates the full length of the geometry and places exactly one symbol at the geometric midpoint.

For Dérivée’s canonical arc topology, `symbol-placement: "line-center"` is selected for all arcs with length $L_{\text{arc}} < 800\text{ m}$. Because canonical arcs are segmented between station junctions, `line-center` ensures that exactly one badge cluster appears cleanly between stations without colliding with platform markers. For long express arcs spanning river tunnels or express bypasses ($L_{\text{arc}} \ge 800\text{ m}$), the layer switches to `symbol-placement: "line"` with an explicit `symbol-spacing: 250 pt` to provide periodic route confirmation.

### 5.2 Badge Spacing, Collision Avoidance, and Viewport Density

To prevent visual clutter on mobile displays, symbol placement obeys strict layout properties:
- `symbol-spacing: 250 pt`: On long arcs, badges repeat at 250-point intervals. This ensures that at least one badge is visible within any screen viewport during panning without cluttering tight curves.
- `icon-padding: 4.0 pt`: Establishes the minimum clearance boundary around each badge before adjacent symbols are suppressed.
- `icon-rotation-alignment: "viewport"`: Badges maintain an upright orientation aligned with the screen viewport rather than rotating with track curvature, ensuring immediate legibility.

### 5.3 Dynamic In-Memory Rasterization vs. Static Sprite Sheets

Transit systems feature dozens of distinct route tokens, and maintenance updates frequently introduce service variations or temporary badges. Relying entirely on pre-baked sprite sheets creates a rigid asset pipeline.

Dérivée pairs static base sprites with a dynamic in-memory CoreGraphics badge renderer registered via `style.setImage(UIImage, forName:)`. When an un-cached route token is required, the engine:
1. Allocates a $60 \times 60\text{ px}$ canvas ($20 \times 20\text{ pt}$ at @3x retina scale).
2. Draws a circular fill using the route's official hex color.
3. Renders the centered route short name using SF Pro Display Bold at $11.5\text{ pt}$ in white.
4. Caches the resulting rasterized image in memory with an LRU eviction policy.

Dynamic CoreGraphics rendering ensures crisp typography on Retina displays, avoids bitmap scaling artifacts, and allows runtime generation of badges for arbitrary route identifiers in GTFS-RT feeds.

### 5.4 Multi-Route Trunk Badge Consolidation

When multiple services share a single consolidated trunk ribbon—such as the Lexington Avenue trunk carrying the 4, 5, and 6 trains—rendering individual overlapping symbols along the line causes text collisions.

To maintain visual clarity, the Go pipeline aggregates the routes operating on each canonical arc and emits a composite badge key:

$$\text{BadgeKey} = \text{Join}\left(\{r_{\text{short\_name}} \mid r \in \text{Routes}(A)\}, \text{"\_"}\right) \implies \text{"badge\_4\_5\_6"}$$

The client-side engine renders a single composite horizontal capsule containing adjacent, evenly spaced circular bullets within an integrated outline. MapLibre places this single composite image along the corridor centerline, completely avoiding inter-symbol collisions.

### 5.5 Multi-Scale Visibility Thresholds & Stroke-Width Scale Gating

Placing an 18-point badge over a 1.0-point line stroke at regional zoom levels ($z \le 13$) obscures the underlying base map. Badge visibility is therefore controlled by a smooth zoom-dependent opacity ramp:

$$\text{BadgeOpacity}(z) = \begin{cases} 
0.0, & z < 13.5 \\ 
\frac{z - 13.5}{14.5 - 13.5}, & 13.5 \le z \le 14.5 \\ 
1.0, & z > 14.5 
\end{cases}$$

At zoom levels $z \ge 14.5$, ribbon widths reach $\ge 2.5\text{ pt}$ and station platform capsules emerge, creating the necessary visual hierarchy for 18-point bullet tokens to integrate naturally with corridor linework.

---

## 6. Concrete Implementations & Worked Case Studies

### 6.1 Queens Boulevard Trunk Corridor (NYC Subway 3-Color Ribbon)

The Queens Boulevard Line in Long Island City and Sunnyside serves as a benchmark test case for the multi-color bundling engine. Along Northern Boulevard between Queens Plaza and 36th Street, four distinct subway services share a four-track right-of-way representing three distinct trunk colors:
- **E Train:** Eighth Avenue Express, Blue (`#0039A6`)
- **F Train:** Sixth Avenue Express, Orange (`#FF6319`)
- **R Train:** Broadway Local, Yellow (`#FCCC0A`)
- *(M Train operates locally on weekdays, consolidating into Orange `#FF6319`)*

For this three-color corridor ($K = 3$) with a base ribbon step of $S = 3.5\text{ pt}$, the offsets relative to the canonical centerline $L_{\text{canonical}}$ are:
- **Ribbon Index $0$ (Blue E):** $\Delta_0 = (0 - 1.0) \times 3.5\text{ pt} = -3.5\text{ pt}$ (North/West offset)
- **Ribbon Index $1$ (Orange F/M):** $\Delta_1 = (1 - 1.0) \times 3.5\text{ pt} = 0.0\text{ pt}$ (Centerline)
- **Ribbon Index $2$ (Yellow R):** $\Delta_2 = (2 - 1.0) \times 3.5\text{ pt} = +3.5\text{ pt}$ (South/East offset)

```json
{
  "type": "FeatureCollection",
  "features": [
    {
      "type": "Feature",
      "id": "casing_arc_qbl_082",
      "properties": {
        "corridor_id": "qbl_queens_plaza_36st",
        "bundle_size": 3,
        "casing_width": 10.5
      },
      "geometry": {
        "type": "LineString",
        "coordinates": [
          [-73.937225, 40.749718],
          [-73.934166, 40.750875],
          [-73.929851, 40.752314],
          [-73.925812, 40.753892]
        ]
      }
    },
    {
      "type": "Feature",
      "id": "ribbon_qbl_blue_e",
      "properties": {
        "corridor_id": "qbl_queens_plaza_36st",
        "trunk_color": "#0039A6",
        "bundle_index": 0,
        "routes": ["E"]
      },
      "geometry": {
        "type": "LineString",
        "coordinates": [
          [-73.937255, 40.749742],
          [-73.934196, 40.750899],
          [-73.929881, 40.752338],
          [-73.925842, 40.753916]
        ]
      }
    },
    {
      "type": "Feature",
      "id": "ribbon_qbl_orange_fm",
      "properties": {
        "corridor_id": "qbl_queens_plaza_36st",
        "trunk_color": "#FF6319",
        "bundle_index": 1,
        "routes": ["F", "M"]
      },
      "geometry": {
        "type": "LineString",
        "coordinates": [
          [-73.937225, 40.749718],
          [-73.934166, 40.750875],
          [-73.929851, 40.752314],
          [-73.925812, 40.753892]
        ]
      }
    },
    {
      "type": "Feature",
      "id": "ribbon_qbl_yellow_r",
      "properties": {
        "corridor_id": "qbl_queens_plaza_36st",
        "trunk_color": "#FCCC0A",
        "bundle_index": 2,
        "routes": ["R"]
      },
      "geometry": {
        "type": "LineString",
        "coordinates": [
          [-73.937195, 40.749694],
          [-73.934136, 40.750851],
          [-73.929821, 40.752290],
          [-73.925782, 40.753868]
        ]
      }
    }
  ]
}
```

East of this segment, the E and F express tracks diverge from the local R tracks to bypass intermediate stations. A 50-meter cubic Hermite fillet smoothly transitions the Blue ribbon from offset $\Delta = -3.5\text{ pt}$ to $\Delta = -1.75\text{ pt}$, maintaining geometric continuity through the switch.

### 6.2 MBTA Green Line Central Subway (Boston Single-Color Deduplication)

Boston’s MBTA Green Line provides an ideal test case for single-color multi-route deduplication. Between Kenmore Station and Copley / Park Street, four distinct light rail branches merge into the Boylston Street Subway:
- **B Branch:** Boston College (`#00843D`)
- **C Branch:** Cleveland Circle (`#00843D`)
- **D Branch:** Riverside (`#00843D`)
- **E Branch:** Heath Street (`#00843D`)

Evaluating the CIEDE2000 metric across these four branches yields $\Delta E_{00} = 0.00$. The four overlapping GTFS shape lines are consolidated into a single ribbon feature ($K = 1$, `bundle_index = 0`) rendered in `#00843D`. A single casing feature with width $4.5\text{ pt}$ (at $z = 14$) encloses the corridor. Midpoint badges display a single composite token `"badge_mbta_B_C_D_E"`. This consolidation eliminates redundant strokes, preventing dark edge fringes along Commonwealth Avenue and Boylston Street.

---

## 7. Data Structures & Engine Architecture Proposals

### 7.1 Go Topology Engine Extensions (`observer/internal/gtfs`)

The planar arc-topology engine is extended with corridor bundling, deduplication, and fillet generation structures:

```go
package gtfs

import (
	"image/color"
)

// TrunkCorridor models a physical infrastructure corridor carrying one or more
// transit routes that may be consolidated into parallel cartographic ribbons.
type TrunkCorridor struct {
	CorridorID    string          `json:"corridor_id"`
	CanonicalArc  *CanonicalArc   `json:"-"`
	TrunkBundles  []*TrunkBundle  `json:"bundles"`
	BundleSize    int             `json:"bundle_size"`    // Number of distinct visual ribbons (K <= 3)
	CasingWidth   float64         `json:"casing_width"`   // Evaluated at base zoom z=14 (pt)
	RoutesSummary []string        `json:"routes_summary"` // e.g. ["4", "5", "6"]
	CompositeKey  string          `json:"composite_key"`  // e.g. "badge_4_5_6"
}

// TrunkBundle represents a single colored ribbon within a corridor bundle.
type TrunkBundle struct {
	BundleIndex int          `json:"bundle_index"` // 0 <= BundleIndex < BundleSize
	TrunkColor  string       `json:"trunk_color"`  // Canonical hex color string
	DeltaOffset float64      `json:"delta_offset"` // Normal offset distance in points
	RouteIDs    []string     `json:"route_ids"`    // Routes consolidated into this ribbon
	Geometry    []Coordinate `json:"coordinates"`  // Pre-computed offset polyline
}

// HermiteFillet defines a tangent-continuous transition zone at a junction.
type HermiteFillet struct {
	FilletID       string       `json:"fillet_id"`
	SourceCorridor string       `json:"source_corridor"`
	TargetCorridor string       `json:"target_corridor"`
	StartOffset    float64      `json:"start_offset"` // Offset at junction entry (pt)
	EndOffset      float64      `json:"end_offset"`   // Offset at junction exit (pt)
	SplineGeometry []Coordinate `json:"coordinates"`  // Discretized C^1 cubic Hermite curve
}

// OffsetOptions configures the geometric polyline offsetting pass.
type OffsetOptions struct {
	MiterLimit      float64 // Maximum miter ratio before bevel truncation (default: 2.0)
	RibbonSpacingPt float64 // Spacing between adjacent ribbon centerlines (default: 3.5 pt)
	BevelSharpEdges bool    // True: clamp acute angles θ < 60°
	FilletLengthM   float64 // Target length for junction transition fillets (default: 50.0 m)
}
```

### 7.2 Swift / MapLibre Native Layer Configuration (`DeriveeNative`)

The client-side rendering engine configures MapLibre style layers and data-driven expressions in Swift:

```swift
import Foundation
import MapLibre

public struct TransitCartographyEngine {
    
    public static func makeTrenchCasingLayer(source: MLNSource) -> MLNLineStyleLayer {
        let casing = MLNLineStyleLayer(identifier: "transit-trench-casing", source: source)
        casing.predicate = NSPredicate(format: "bundle_size > 0")
        
        casing.lineWidth = NSExpression(
            forMLNInterpolating: NSExpression.zoomLevelVariable,
            curveType: .linear,
            parameters: nil,
            stops: NSExpression(forConstantValue: [
                11: NSExpression(forFunction: "multiply:by:", arguments: [NSExpression(forKeyPath: "casing_width"), 0.5]),
                14: NSExpression(forKeyPath: "casing_width"),
                17: NSExpression(forFunction: "multiply:by:", arguments: [NSExpression(forKeyPath: "casing_width"), 1.8])
            ])
        )
        
        casing.lineColor = NSExpression(forConstantValue: UIColor.white)
        casing.lineJoin = NSExpression(forConstantValue: "round")
        casing.lineCap = NSExpression(forConstantValue: "round")
        return casing
    }
    
    public static func makeRibbonStrokeLayer(source: MLNSource) -> MLNLineStyleLayer {
        let ribbon = MLNLineStyleLayer(identifier: "transit-ribbon-stroke", source: source)
        ribbon.predicate = NSPredicate(format: "trunk_color != nil")
        
        ribbon.lineColor = NSExpression(forKeyPath: "trunk_color")
        ribbon.lineJoin = NSExpression(forConstantValue: "bevel")
        ribbon.lineCap = NSExpression(forConstantValue: "butt")
        
        ribbon.lineWidth = NSExpression(
            forMLNInterpolating: NSExpression.zoomLevelVariable,
            curveType: .linear,
            parameters: nil,
            stops: NSExpression(forConstantValue: [
                11: 1.2,
                14: 2.5,
                17: 4.5
            ])
        )
        return ribbon
    }
    
    public static func makeBadgeSymbolLayer(source: MLNSource) -> MLNSymbolStyleLayer {
        let symbol = MLNSymbolStyleLayer(identifier: "transit-badges-symbol", source: source)
        symbol.predicate = NSPredicate(format: "composite_key != nil")
        
        symbol.symbolPlacement = NSExpression(forConstantValue: "line-center")
        symbol.iconImageName = NSExpression(forKeyPath: "composite_key")
        symbol.iconRotationAlignment = NSExpression(forConstantValue: "viewport")
        symbol.iconAllowsOverlap = NSExpression(forConstantValue: false)
        symbol.iconPadding = NSExpression(forConstantValue: 4.0)
        
        symbol.iconOpacity = NSExpression(
            forMLNInterpolating: NSExpression.zoomLevelVariable,
            curveType: .linear,
            parameters: nil,
            stops: NSExpression(forConstantValue: [
                13.5: 0.0,
                14.5: 1.0
            ])
        )
        return symbol
    }
}
```

---

## 8. Invariant Assertions & Engineering Verification Rules

To prevent visual regressions and ensure topological integrity during automated pipeline builds, eight engineering invariants are enforced across the processing and rendering layers:

| Invariant ID | Subsystem | Mathematical / Topological Assertion | Verification Mechanism |
|:---|:---|:---|:---|
| **INV-OFFSET-01** | Geometry | $\forall v_i, \quad \frac{L_{\text{miter}}(v_i)}{d} \le 2.0$ (Turns $\theta < 60^\circ$ must be beveled) | Unit tests verifying offset polyline vertices |
| **INV-OFFSET-02** | Geometry | $\text{SelfIntersections}(P_{\text{offset}}) = \emptyset$ (Offset paths must be free of self-intersecting loops) | Sweep-line Bentley-Ottmann verification in Go tests |
| **INV-CORR-01** | Deduplication | $\forall r_a, r_b \in \text{Bundle}_k, \quad \Delta E_{00}(\text{Color}(r_a), \text{Color}(r_b)) \le 2.0$ | CI validation of trunk color assignments |
| **INV-CORR-02** | Multiplicity | $\forall A \in \text{Arcs}_{\text{NYC}}, \quad K(A) \le 3$ (Corridor bundle size must not exceed 3 ribbons) | Network-wide assertion across static GTFS shapes |
| **INV-CORR-03** | Directionality | $\text{ArcDirection}(A)$ is canonical: $\text{NodeKey}(N_{\text{start}}) < \text{NodeKey}(N_{\text{end}})$ | Directional ordering checks on serialized topology graphs |
| **INV-FILLET-01** | Junctions | Fillet curves must maintain $C^1$ continuity: $\vec{T}_{\text{fillet}}(0) = \vec{T}_{\text{trunk}}$ and $\vec{T}_{\text{fillet}}(1) = \vec{T}_{\text{branch}}$ | Derivative dot-product check: $\vec{T}_0 \cdot \vec{T}_{\text{in}} > 0.999$ |
| **INV-FILLET-02** | Junctions | Fillet length bounds: $20.0\text{ m} \le L_{\text{fillet}} \le \min(120.0\text{ m}, 0.35 \times L_{\text{arc}})$ | Spatial boundary checks on Hermite splines |
| **INV-BADGE-01** | Symbolics | Route badge opacity clamped to $0.0$ for $z < 13.5$; full opacity $1.0$ at $z \ge 14.5$ | MapLibre style expression evaluation assertions |

These invariants form the automated test suite for validating Wave V cartography, ensuring Dérivée's parallel corridor bundling provides high visual clarity and geometric stability across all zoom scales.
