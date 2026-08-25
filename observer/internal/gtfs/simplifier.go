package gtfs

import (
	"container/heap"
	"math"
)

// TriangleArea computes the effective area of the triangle formed by three points
// Area = 0.5 * | x1*(y2 - y3) + x2*(y3 - y1) + x3*(y1 - y2) |
func TriangleArea(p1, p2, p3 Point2D) float64 {
	return 0.5 * math.Abs(p1.Lon*(p2.Lat-p3.Lat)+p2.Lon*(p3.Lat-p1.Lat)+p3.Lon*(p1.Lat-p2.Lat))
}

// Mode-adaptive area thresholds in deg^2
const (
	ThresholdSubway       = 1.0e-9 // ~12 m^2: High fidelity downtown curves & tunnels
	ThresholdLRT          = 5.0e-9 // Moderate surface rail smoothing
	ThresholdFerry        = 1.0e-8 // Open-water arc smoothing
	ThresholdCommuterRail = 5.0e-8 // Long suburban tangent runs
)

// ThresholdForModalClass returns the standard threshold for a given modal class
func ThresholdForModalClass(modalClass int) float64 {
	switch modalClass {
	case ModalClassSubway:
		return ThresholdSubway
	case ModalClassLRT:
		return ThresholdLRT
	case ModalClassFerry:
		return ThresholdFerry
	default:
		return ThresholdSubway
	}
}

// ThresholdForRoute returns the mode-adaptive threshold for a given Route
func ThresholdForRoute(route Route) float64 {
	if route.RouteType == 2 { // Regional commuter rail
		return ThresholdCommuterRail
	}
	return ThresholdForModalClass(ResolveModalClass(route.RouteType))
}

// vwNode represents a vertex in the doubly-linked polyline during Visvalingam-Whyatt elimination
type vwNode struct {
	point     Point2D
	origIndex int
	prev      *vwNode
	next      *vwNode
	area      float64
	heapIndex int
	isLocked  bool
}

// nodeHeap implements container/heap.Interface for min-heap priority queue
type nodeHeap []*vwNode

func (h nodeHeap) Len() int           { return len(h) }
func (h nodeHeap) Less(i, j int) bool { return h[i].area < h[j].area }
func (h nodeHeap) Swap(i, j int) {
	h[i], h[j] = h[j], h[i]
	h[i].heapIndex = i
	h[j].heapIndex = j
}
func (h *nodeHeap) Push(x any) {
	node := x.(*vwNode)
	node.heapIndex = len(*h)
	*h = append(*h, node)
}
func (h *nodeHeap) Pop() any {
	old := *h
	n := len(old)
	node := old[n-1]
	old[n-1] = nil
	node.heapIndex = -1
	*h = old[0 : n-1]
	return node
}

// ComputeEffectiveAreas computes the Visvalingam-Whyatt effective area for every vertex in a polyline.
// Endpoints are assigned Inf. Interior vertices are assigned their elimination threshold with monotonic progression.
func ComputeEffectiveAreas(pts []Point2D) []float64 {
	n := len(pts)
	if n == 0 {
		return nil
	}
	effectiveAreas := make([]float64, n)
	if n <= 2 {
		for i := range effectiveAreas {
			effectiveAreas[i] = math.Inf(1)
		}
		return effectiveAreas
	}

	// 1. Build doubly-linked list of nodes
	nodes := make([]*vwNode, n)
	for i, p := range pts {
		nodes[i] = &vwNode{
			point:     p,
			origIndex: i,
			heapIndex: -1,
		}
	}
	for i := 0; i < n; i++ {
		if i > 0 {
			nodes[i].prev = nodes[i-1]
		}
		if i < n-1 {
			nodes[i].next = nodes[i+1]
		}
	}

	// 2. Lock endpoints with Inf area
	nodes[0].isLocked = true
	nodes[0].area = math.Inf(1)
	effectiveAreas[0] = math.Inf(1)

	nodes[n-1].isLocked = true
	nodes[n-1].area = math.Inf(1)
	effectiveAreas[n-1] = math.Inf(1)

	// 3. Populate min-heap with initial triangle areas for interior nodes
	h := &nodeHeap{}
	heap.Init(h)

	for i := 1; i < n-1; i++ {
		nodes[i].area = TriangleArea(nodes[i].prev.point, nodes[i].point, nodes[i].next.point)
		heap.Push(h, nodes[i])
	}

	// 4. Iteratively eliminate vertices with smallest effective area
	minAreaSeen := 0.0
	for h.Len() > 0 {
		curr := heap.Pop(h).(*vwNode)

		// Monotonic area progression: effective area is at least the previous minimum
		if curr.area < minAreaSeen {
			curr.area = minAreaSeen
		} else {
			minAreaSeen = curr.area
		}
		effectiveAreas[curr.origIndex] = curr.area

		// Remove curr from linked list
		prev := curr.prev
		next := curr.next
		prev.next = next
		next.prev = prev

		// Recompute triangle areas for neighbors
		if !prev.isLocked && prev.heapIndex >= 0 {
			prev.area = TriangleArea(prev.prev.point, prev.point, prev.next.point)
			heap.Fix(h, prev.heapIndex)
		}
		if !next.isLocked && next.heapIndex >= 0 {
			next.area = TriangleArea(next.prev.point, next.point, next.next.point)
			heap.Fix(h, next.heapIndex)
		}
	}

	return effectiveAreas
}

// SimplifyPoints applies Visvalingam-Whyatt polyline simplification using the given threshold.
// Points with effective area >= threshold (and locked endpoints) are retained.
func SimplifyPoints(pts []Point2D, threshold float64) []Point2D {
	if len(pts) <= 2 {
		return pts
	}
	areas := ComputeEffectiveAreas(pts)
	var simplified []Point2D
	for i, p := range pts {
		if areas[i] >= threshold {
			simplified = append(simplified, p)
		}
	}
	if len(simplified) < 2 {
		return []Point2D{pts[0], pts[len(pts)-1]}
	}
	return simplified
}

// SimplifyArc simplifies a single canonical Arc using the given threshold
func SimplifyArc(arc Arc, threshold float64) []Point2D {
	return SimplifyPoints(arc.Points, threshold)
}

// SimplifyGraph simplifies all canonical Arcs in a TopologyGraph with a unified or mode-adaptive threshold map
func SimplifyGraph(graph *TopologyGraph, defaultThreshold float64, arcThresholds map[int]float64) map[int][]Point2D {
	simplifiedArcs := make(map[int][]Point2D)
	for _, arc := range graph.Arcs {
		thresh := defaultThreshold
		if t, ok := arcThresholds[arc.ID]; ok && t > 0 {
			thresh = t
		}
		simplifiedArcs[arc.ID] = SimplifyArc(arc, thresh)
	}
	return simplifiedArcs
}
