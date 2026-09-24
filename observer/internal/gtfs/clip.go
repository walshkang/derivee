package gtfs

import (
	"fmt"
	"math"
)

// IntersectionResult stores the segment indices and intersection coordinates
type IntersectionResult struct {
	Seg1Index int
	Seg2Index int
	Point     Vec2D
	T1        float64
	T2        float64
}

// FindSegmentIntersection computes the intersection between segment AB and segment CD.
// Returns true and the intersection point if they intersect strictly within (0+eps, 1-eps).
func FindSegmentIntersection(a, b, c, d Vec2D, eps float64) (Vec2D, float64, float64, bool) {
	rx := b.X - a.X
	ry := b.Y - a.Y
	sx := d.X - c.X
	sy := d.Y - c.Y

	det := rx*sy - ry*sx
	if math.Abs(det) < 1e-9 {
		// Parallel or collinear
		return Vec2D{}, 0, 0, false
	}

	qpx := c.X - a.X
	qpy := c.Y - a.Y

	t := (qpx*sy - qpy*sx) / det
	u := (qpx*ry - qpy*rx) / det

	if t > eps && t < (1.0-eps) && u > eps && u < (1.0-eps) {
		pt := Vec2D{
			X: a.X + t*rx,
			Y: a.Y + t*ry,
		}
		return pt, t, u, true
	}

	return Vec2D{}, 0, 0, false
}

// DistancePointToSegment calculates minimum Euclidean distance from point P to segment AB
func DistancePointToSegment(p, a, b Vec2D) float64 {
	abx := b.X - a.X
	aby := b.Y - a.Y
	abLenSq := abx*abx + aby*aby
	if abLenSq < 1e-9 {
		return math.Hypot(p.X-a.X, p.Y-a.Y)
	}

	apx := p.X - a.X
	apy := p.Y - a.Y
	t := (apx*abx + apy*aby) / abLenSq
	if t < 0.0 {
		return math.Hypot(p.X-a.X, p.Y-a.Y)
	} else if t > 1.0 {
		return math.Hypot(p.X-b.X, p.Y-b.Y)
	}

	projX := a.X + t*abx
	projY := a.Y + t*aby
	return math.Hypot(p.X-projX, p.Y-projY)
}

// MinDistanceToPolyline calculates minimum Euclidean distance from point P to any segment of polyline
func MinDistanceToPolyline(p Vec2D, poly []Vec2D) float64 {
	if len(poly) == 0 {
		return math.MaxFloat64
	}
	if len(poly) == 1 {
		return math.Hypot(p.X-poly[0].X, p.Y-poly[0].Y)
	}
	minDist := math.MaxFloat64
	for i := 0; i < len(poly)-1; i++ {
		d := DistancePointToSegment(p, poly[i], poly[i+1])
		if d < minDist {
			minDist = d
		}
	}
	return minDist
}

// FindFirstSelfIntersection sweeps through polyline segments to detect the earliest self-intersection
func FindFirstSelfIntersection(pts []Vec2D, eps float64) (IntersectionResult, bool) {
	n := len(pts)
	if n < 4 {
		return IntersectionResult{}, false
	}

	for i := 0; i < n-2; i++ {
		p1, p2 := pts[i], pts[i+1]
		// Skip adjacent segments (j = i + 1)
		for j := i + 2; j < n-1; j++ {
			p3, p4 := pts[j], pts[j+1]
			if pt, t1, t2, ok := FindSegmentIntersection(p1, p2, p3, p4, eps); ok {
				return IntersectionResult{
					Seg1Index: i,
					Seg2Index: j,
					Point:     pt,
					T1:        t1,
					T2:        t2,
				}, true
			}
		}
	}
	return IntersectionResult{}, false
}

// HasSelfIntersections returns true if the polyline contains any self-intersecting segments
func HasSelfIntersections(pts []Vec2D) bool {
	_, found := FindFirstSelfIntersection(pts, 1e-4)
	return found
}

// ValidateSelfIntersections_INV_OFFSET_02 enforces that offset polyline has zero self-intersections
func ValidateSelfIntersections_INV_OFFSET_02(pts []Vec2D) error {
	if hit, found := FindFirstSelfIntersection(pts, 1e-4); found {
		return fmt.Errorf("INV-OFFSET-02 violated: self-intersection detected between segments %d and %d at (%.4f, %.4f)",
			hit.Seg1Index, hit.Seg2Index, hit.Point.X, hit.Point.Y)
	}
	return nil
}

// ClipSwallowtailsMetric removes self-intersecting swallowtail lobes from offset polyline relative to generator polyline.
// Follows Research Doc 22 §1.4:
// 1. Detect candidate self-intersections (j < k).
// 2. Classify if intermediate vertices penetrate inward (D(v', P) < |d| - eps).
// 3. Excise invalid loop sequence and splice directly at the intersection node.
func ClipSwallowtailsMetric(offsetPts []Vec2D, generatorPts []Vec2D, d float64) []Vec2D {
	if len(offsetPts) < 4 || math.Abs(d) < 1e-6 {
		return offsetPts
	}

	current := make([]Vec2D, len(offsetPts))
	copy(current, offsetPts)

	absD := math.Abs(d)
	epsDist := math.Min(0.25*absD, 0.5) // tolerance for inward distance test (0.5m)
	maxIterations := 50

	for iter := 0; iter < maxIterations; iter++ {
		hit, found := FindFirstSelfIntersection(current, 1e-4)
		if !found {
			break
		}

		j := hit.Seg1Index
		k := hit.Seg2Index

		// Check intermediate vertices v_{j+1} ... v_k
		// If ANY intermediate vertex is closer to generator than |d| - eps, it is an invalid inward loop
		isSwallowtail := false
		for m := j + 1; m <= k; m++ {
			dist := MinDistanceToPolyline(current[m], generatorPts)
			if dist < (absD - epsDist) {
				isSwallowtail = true
				break
			}
		}

		// Also check loop midpoint
		loopMidDist := MinDistanceToPolyline(hit.Point, generatorPts)
		if loopMidDist < (absD - epsDist) {
			isSwallowtail = true
		}

		if isSwallowtail {
			// Excise vertices j+1 through k, and insert hit.Point
			var spliced []Vec2D
			spliced = append(spliced, current[:j+1]...)
			spliced = append(spliced, hit.Point)
			spliced = append(spliced, current[k+1:]...)
			current = CleanMetricPolyline(spliced)
		} else {
			// If not a swallowtail (e.g. valid outer loop or tight S-curve), excise the loop to preserve simple path
			var spliced []Vec2D
			spliced = append(spliced, current[:j+1]...)
			spliced = append(spliced, hit.Point)
			spliced = append(spliced, current[k+1:]...)
			current = CleanMetricPolyline(spliced)
		}
	}

	return current
}

// ClipSwallowtails applies swallowtail detection and clipping in WGS84 coordinate space
func ClipSwallowtails(offsetPts []Point2D, generatorPts []Point2D, d float64) []Point2D {
	if len(offsetPts) < 4 || math.Abs(d) < 1e-6 {
		return offsetPts
	}
	metricOffset, refLat, refLon := ProjectToLocalM(offsetPts)
	metricGen, _, _ := ProjectToLocalM(generatorPts)

	clippedMetric := ClipSwallowtailsMetric(metricOffset, metricGen, d)
	return UnprojectFromLocalM(clippedMetric, refLat, refLon)
}
