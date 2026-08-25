package gtfs

import (
	"math"
	"sort"
)

// Point2D represents a geographic coordinate (Lon = X, Lat = Y)
type Point2D struct {
	Lon float64 `json:"lon"`
	Lat float64 `json:"lat"`
}

// PointKey quantizes coordinates to 7 decimal places (~1.1cm) for robust topological indexing
type PointKey struct {
	Lon int64
	Lat int64
}

// ToPointKey converts Point2D into quantized PointKey
func ToPointKey(p Point2D) PointKey {
	return PointKey{
		Lon: int64(math.Round(p.Lon * 1e7)),
		Lat: int64(math.Round(p.Lat * 1e7)),
	}
}

// Arc represents a canonical linear path bounded by locked junction nodes
type Arc struct {
	ID       int
	Points   []Point2D
	StartKey PointKey
	EndKey   PointKey
}

// ShapeArcRef represents an oriented reference to a canonical Arc
type ShapeArcRef struct {
	ArcID    int
	Reversed bool
}

// TopologyGraph holds the extracted planar topology across transit shapes
type TopologyGraph struct {
	Junctions map[PointKey]bool
	Arcs      []Arc
	ShapeArcs map[string][]ShapeArcRef // Keyed by shape_id
}

// BuildTopologyGraph extracts planar topology from GTFS shapes.
// It detects junction nodes (terminals, branch/merge points, degree >= 3) and decomposes lines into canonical Arcs.
func BuildTopologyGraph(shapes map[string][]ShapePoint) *TopologyGraph {
	// 1. Convert and clean raw shape points into clean Point2D slices (removing consecutive duplicate points)
	cleanShapes := make(map[string][]Point2D)
	for shapeID, pts := range shapes {
		if len(pts) == 0 {
			continue
		}
		var clean []Point2D
		for _, pt := range pts {
			p := Point2D{Lon: pt.ShapePtLon, Lat: pt.ShapePtLat}
			if len(clean) == 0 {
				clean = append(clean, p)
			} else {
				last := clean[len(clean)-1]
				if ToPointKey(last) != ToPointKey(p) {
					clean = append(clean, p)
				}
			}
		}
		if len(clean) >= 2 {
			cleanShapes[shapeID] = clean
		}
	}

	// 2. Identify Junction Nodes
	// Rule A: Terminal endpoints (first and last point of every shape) are locked junctions.
	junctions := make(map[PointKey]bool)
	for _, pts := range cleanShapes {
		junctions[ToPointKey(pts[0])] = true
		junctions[ToPointKey(pts[len(pts)-1])] = true
	}

	// Rule B: Graph vertex degree and branching analysis across all shapes
	// Track undirected adjacent edges for each vertex
	neighbors := make(map[PointKey]map[PointKey]bool)
	addNeighbor := func(a, b PointKey) {
		if a == b {
			return
		}
		if neighbors[a] == nil {
			neighbors[a] = make(map[PointKey]bool)
		}
		neighbors[a][b] = true
		if neighbors[b] == nil {
			neighbors[b] = make(map[PointKey]bool)
		}
		neighbors[b][a] = true
	}

	for _, pts := range cleanShapes {
		for i := 0; i < len(pts)-1; i++ {
			k1 := ToPointKey(pts[i])
			k2 := ToPointKey(pts[i+1])
			addNeighbor(k1, k2)
		}
	}

	// Any vertex where degree != 2 (i.e. degree 1 terminal or degree >= 3 intersection/branch) is a junction
	for k, nbrs := range neighbors {
		if len(nbrs) != 2 {
			junctions[k] = true
		}
	}

	// Rule C: Shape divergence/convergence points
	// If two shapes enter vertex V from U, but exit to different vertices W1 and W2, V is a junction
	type Transition struct {
		from PointKey
		to   PointKey
	}
	transitionsAtVertex := make(map[PointKey]map[Transition]bool)
	for _, pts := range cleanShapes {
		for i := 1; i < len(pts)-1; i++ {
			prevK := ToPointKey(pts[i-1])
			currK := ToPointKey(pts[i])
			nextK := ToPointKey(pts[i+1])
			if transitionsAtVertex[currK] == nil {
				transitionsAtVertex[currK] = make(map[Transition]bool)
			}
			transitionsAtVertex[currK][Transition{from: prevK, to: nextK}] = true
		}
	}

	for k, trans := range transitionsAtVertex {
		if len(trans) > 1 {
			// Multiple distinct transitions flow through k -> mark as junction
			junctions[k] = true
		}
	}

	// 3. Decompose clean shapes into Canonical Arcs
	type ArcKey struct {
		k1   PointKey
		k2   PointKey
		hash int64
	}

	canonicalArcs := make(map[ArcKey]int) // Maps canonical key to Arc ID
	var arcs []Arc
	shapeArcs := make(map[string][]ShapeArcRef)

	// Helper to compute a hash of intermediate points for collision avoidance
	hashPoints := func(pts []Point2D) int64 {
		var h int64 = 17
		for _, p := range pts {
			k := ToPointKey(p)
			h = h*31 + k.Lon
			h = h*31 + k.Lat
		}
		return h
	}

	// Sort shape IDs for deterministic processing order
	sortedShapeIDs := make([]string, 0, len(cleanShapes))
	for sID := range cleanShapes {
		sortedShapeIDs = append(sortedShapeIDs, sID)
	}
	sort.Strings(sortedShapeIDs)

	for _, shapeID := range sortedShapeIDs {
		pts := cleanShapes[shapeID]
		var currentArcPoints []Point2D
		currentArcPoints = append(currentArcPoints, pts[0])

		for i := 1; i < len(pts); i++ {
			p := pts[i]
			currentArcPoints = append(currentArcPoints, p)
			pKey := ToPointKey(p)

			if junctions[pKey] || i == len(pts)-1 {
				// Arc slice complete
				if len(currentArcPoints) >= 2 {
					startK := ToPointKey(currentArcPoints[0])
					endK := ToPointKey(currentArcPoints[len(currentArcPoints)-1])

					forwardHash := hashPoints(currentArcPoints)
					// Compute reversed points & hash
					revPoints := make([]Point2D, len(currentArcPoints))
					for j, pt := range currentArcPoints {
						revPoints[len(currentArcPoints)-1-j] = pt
					}
					revHash := hashPoints(revPoints)

					// Canonical ordering: compare startK and endK
					isCanonicalForward := false
					if startK.Lon < endK.Lon || (startK.Lon == endK.Lon && startK.Lat <= endK.Lat) {
						isCanonicalForward = true
					}

					var canonKey ArcKey
					var isReversed bool

					if isCanonicalForward {
						canonKey = ArcKey{k1: startK, k2: endK, hash: forwardHash}
						isReversed = false
					} else {
						canonKey = ArcKey{k1: endK, k2: startK, hash: revHash}
						isReversed = true
					}

					arcID, exists := canonicalArcs[canonKey]
					if !exists {
						arcID = len(arcs)
						canonicalPoints := currentArcPoints
						if !isCanonicalForward {
							canonicalPoints = revPoints
						}
						newArc := Arc{
							ID:       arcID,
							Points:   canonicalPoints,
							StartKey: ToPointKey(canonicalPoints[0]),
							EndKey:   ToPointKey(canonicalPoints[len(canonicalPoints)-1]),
						}
						arcs = append(arcs, newArc)
						canonicalArcs[canonKey] = arcID
					}

					shapeArcs[shapeID] = append(shapeArcs[shapeID], ShapeArcRef{
						ArcID:    arcID,
						Reversed: isReversed,
					})
				}

				// Start next arc slice from junction
				currentArcPoints = []Point2D{p}
			}
		}
	}

	return &TopologyGraph{
		Junctions: junctions,
		Arcs:      arcs,
		ShapeArcs: shapeArcs,
	}
}
