package gtfs

import (
	"fmt"
	"math"
)

// WGS84 Earth Equatorial Radius in meters
const EarthRadiusM = 6378137.0

// BaseTrackSpacingM defines the canonical visual corridor ribbon spacing in meters (~22.0m / 3.0pt at z=14, Doc 22 §1.3)
const BaseTrackSpacingM = 22.0

// DefaultMiterLimit defines the maximum miter apex expansion ratio before bevel truncation (INV-OFFSET-01: M <= 2.0)
const DefaultMiterLimit = 2.0

// DilationOverlapM defines the sub-pixel MSAA dilation overlap in meters (~1.5m ≈ 0.2pt, Doc 22 §4.3)
const DilationOverlapM = 1.5

// OffsetOptions configures geometric parallel offsetting
type OffsetOptions struct {
	MiterLimit      float64 // Maximum miter ratio before bevel truncation (default: 2.0)
	TrackSpacingM   float64 // Track spacing distance (default: 22.0m)
	BevelSharpEdges bool    // Clamp acute turns (theta < 60°) with bevel join
	DilationM       float64 // Sub-pixel MSAA dilation overlap (default: 1.5m)
}

// DefaultOffsetOptions provides production defaults conforming to Research Doc 22
var DefaultOffsetOptions = OffsetOptions{
	MiterLimit:      DefaultMiterLimit,
	TrackSpacingM:   BaseTrackSpacingM,
	BevelSharpEdges: true,
	DilationM:       DilationOverlapM,
}

// Vec2D represents a 2D Euclidean vector in local metric space (meters)
type Vec2D struct {
	X float64
	Y float64
}

// ProjectToLocalM converts a slice of Point2D (WGS84 lon/lat degrees) to local metric Vec2D coordinates
// using an equirectangular projection anchored at the centroid reference coordinates.
func ProjectToLocalM(pts []Point2D) ([]Vec2D, float64, float64) {
	if len(pts) == 0 {
		return nil, 0, 0
	}
	// Compute reference centroid (lat/lon)
	var sumLat, sumLon float64
	for _, p := range pts {
		sumLat += p.Lat
		sumLon += p.Lon
	}
	refLat := sumLat / float64(len(pts))
	refLon := sumLon / float64(len(pts))

	radLat := refLat * math.Pi / 180.0
	cosLat := math.Cos(radLat)
	metersPerDegLat := (math.Pi / 180.0) * EarthRadiusM
	metersPerDegLon := metersPerDegLat * cosLat

	metricPts := make([]Vec2D, len(pts))
	for i, p := range pts {
		metricPts[i] = Vec2D{
			X: (p.Lon - refLon) * metersPerDegLon,
			Y: (p.Lat - refLat) * metersPerDegLat,
		}
	}
	return metricPts, refLat, refLon
}

// UnprojectFromLocalM converts a slice of local metric Vec2D coordinates back to WGS84 Point2D degrees.
func UnprojectFromLocalM(vecs []Vec2D, refLat, refLon float64) []Point2D {
	radLat := refLat * math.Pi / 180.0
	cosLat := math.Cos(radLat)
	metersPerDegLat := (math.Pi / 180.0) * EarthRadiusM
	metersPerDegLon := metersPerDegLat * cosLat

	pts := make([]Point2D, len(vecs))
	for i, v := range vecs {
		pts[i] = Point2D{
			Lon: refLon + (v.X / metersPerDegLon),
			Lat: refLat + (v.Y / metersPerDegLat),
		}
	}
	return pts
}

// CleanMetricPolyline removes adjacent duplicate vertices (< 1mm distance) to prevent division by zero in tangent math
func CleanMetricPolyline(vecs []Vec2D) []Vec2D {
	if len(vecs) <= 1 {
		return vecs
	}
	clean := []Vec2D{vecs[0]}
	for i := 1; i < len(vecs); i++ {
		dx := vecs[i].X - clean[len(clean)-1].X
		dy := vecs[i].Y - clean[len(clean)-1].Y
		if (dx*dx + dy*dy) > 1e-6 { // > 1mm separation
			clean = append(clean, vecs[i])
		}
	}
	return clean
}

// OffsetPolylineMetric computes the parallel offset of a metric polyline by lateral distance d (meters).
// Positive d offsets to the left of the direction of travel; negative d offsets to the right.
// Enforces INV-OFFSET-01: bevels sharp corners whenever miter ratio exceeds opts.MiterLimit (default: 2.0).
func OffsetPolylineMetric(vecs []Vec2D, d float64, opts OffsetOptions) []Vec2D {
	clean := CleanMetricPolyline(vecs)
	n := len(clean)
	if n < 2 {
		return clean
	}
	if math.Abs(d) < 1e-6 {
		return clean
	}

	limit := opts.MiterLimit
	if limit <= 1.0 {
		limit = DefaultMiterLimit
	}

	// 1. Calculate segment lengths, tangents, and left-facing normal vectors
	type SegmentInfo struct {
		Length float64
		T      Vec2D // Unit tangent
		N      Vec2D // Unit left normal (-T.Y, T.X)
	}

	segs := make([]SegmentInfo, n-1)
	for i := 0; i < n-1; i++ {
		dx := clean[i+1].X - clean[i].X
		dy := clean[i+1].Y - clean[i].Y
		length := math.Hypot(dx, dy)
		if length < 1e-7 {
			length = 1e-7
		}
		tx := dx / length
		ty := dy / length
		segs[i] = SegmentInfo{
			Length: length,
			T:      Vec2D{X: tx, Y: ty},
			N:      Vec2D{X: -ty, Y: tx},
		}
	}

	var offsetPts []Vec2D

	// 2. Start vertex
	offsetPts = append(offsetPts, Vec2D{
		X: clean[0].X + d*segs[0].N.X,
		Y: clean[0].Y + d*segs[0].N.Y,
	})

	// 3. Intermediate vertices
	for i := 1; i < n-1; i++ {
		nPrev := segs[i-1].N
		nCurr := segs[i].N

		// Bisector normal vector
		bx := nPrev.X + nCurr.X
		by := nPrev.Y + nCurr.Y
		bLen := math.Hypot(bx, by)

		if bLen < 1e-6 {
			// Degenerate 180° hairpin reversal: insert bevel between both segment normals
			b1 := Vec2D{X: clean[i].X + d*nPrev.X, Y: clean[i].Y + d*nPrev.Y}
			b2 := Vec2D{X: clean[i].X + d*nCurr.X, Y: clean[i].Y + d*nCurr.Y}
			offsetPts = append(offsetPts, b1, b2)
			continue
		}

		unitBisect := Vec2D{X: bx / bLen, Y: by / bLen}

		// cos(alpha) = unitBisect · nPrev
		cosAlpha := unitBisect.X*nPrev.X + unitBisect.Y*nPrev.Y
		if cosAlpha < 1e-6 {
			cosAlpha = 1e-6
		}

		miterRatio := 1.0 / cosAlpha

		// INV-OFFSET-01: When miter ratio exceeds limit (angle < 60°), truncate with bevel join
		if opts.BevelSharpEdges && miterRatio > limit {
			b1 := Vec2D{X: clean[i].X + d*nPrev.X, Y: clean[i].Y + d*nPrev.Y}
			b2 := Vec2D{X: clean[i].X + d*nCurr.X, Y: clean[i].Y + d*nCurr.Y}
			offsetPts = append(offsetPts, b1, b2)
		} else {
			// Clean miter apex within limit
			miterDist := d / cosAlpha
			apex := Vec2D{
				X: clean[i].X + miterDist*unitBisect.X,
				Y: clean[i].Y + miterDist*unitBisect.Y,
			}
			offsetPts = append(offsetPts, apex)
		}
	}

	// 4. End vertex
	lastSeg := segs[n-2]
	offsetPts = append(offsetPts, Vec2D{
		X: clean[n-1].X + d*lastSeg.N.X,
		Y: clean[n-1].Y + d*lastSeg.N.Y,
	})

	return offsetPts
}

// OffsetPolyline offsets a WGS84 polyline by lateral distance in meters, enforcing INV-OFFSET-01
func OffsetPolyline(pts []Point2D, d float64, opts OffsetOptions) ([]Point2D, error) {
	if len(pts) < 2 {
		return pts, nil
	}
	metricPts, refLat, refLon := ProjectToLocalM(pts)
	offsetMetric := OffsetPolylineMetric(metricPts, d, opts)
	offsetWGS84 := UnprojectFromLocalM(offsetMetric, refLat, refLon)
	return offsetWGS84, nil
}

// CalculateBundleOffsetDistance evaluates the lateral offset distance in meters for ribbon index i in bundle of size K.
// Applies internal dilation overlap (delta = 0.25pt ≈ 0.35m) along shared internal edges (Doc 22 §4.3).
func CalculateBundleOffsetDistance(bundleIndex, bundleSize int, opts OffsetOptions) float64 {
	if bundleSize <= 1 {
		return 0.0
	}
	spacing := opts.TrackSpacingM
	if spacing <= 0 {
		spacing = BaseTrackSpacingM
	}

	// Symmetrical offset centered on the infrastructure centerline: delta_i = (i - (K-1)/2) * Spacing
	centerOffset := (float64(bundleIndex) - float64(bundleSize-1)/2.0) * spacing

	// Internal dilation overlap: expand toward neighboring ribbons by opts.DilationM along internal boundaries
	dilation := opts.DilationM
	if dilation <= 0 {
		dilation = DilationOverlapM
	}

	if bundleSize == 2 {
		// Index 0 (-spacing/2) dilates positive (+dilation); Index 1 (+spacing/2) dilates negative (-dilation)
		if bundleIndex == 0 {
			return centerOffset + dilation/2.0
		}
		return centerOffset - dilation/2.0
	}

	if bundleSize == 3 {
		// Index 0 (-spacing) dilates positive (+dilation); Index 1 (0) neutral; Index 2 (+spacing) dilates negative (-dilation)
		if bundleIndex == 0 {
			return centerOffset + dilation/2.0
		} else if bundleIndex == 2 {
			return centerOffset - dilation/2.0
		}
		return centerOffset
	}

	return centerOffset
}

// CalculateMiterRatioAtVertex computes the miter expansion ratio (L_miter / |d|) at an offset vertex relative to the progenitor
func CalculateMiterRatioAtVertex(v, pOrig Vec2D, d float64) float64 {
	if math.Abs(d) < 1e-6 {
		return 1.0
	}
	actualDist := math.Hypot(v.X-pOrig.X, v.Y-pOrig.Y)
	return actualDist / math.Abs(d)
}

// ValidateMiterLimit_INV_OFFSET_01 checks if all vertices in offset polyline satisfy miter ratio <= limit
func ValidateMiterLimit_INV_OFFSET_01(offsetPts, origPts []Vec2D, d float64, limit float64) error {
	if math.Abs(d) < 1e-6 || len(offsetPts) == 0 || len(origPts) == 0 {
		return nil
	}
	// For each offset vertex, find minimum distance to any original vertex
	for i, ov := range offsetPts {
		minDist := math.MaxFloat64
		for _, pv := range origPts {
			dist := math.Hypot(ov.X-pv.X, ov.Y-pv.Y)
			if dist < minDist {
				minDist = dist
			}
		}
		ratio := minDist / math.Abs(d)
		// Allow small numerical epsilon (1.05 * limit) for projection/interpolation tolerances
		if ratio > limit*1.05 {
			return fmt.Errorf("INV-OFFSET-01 violated at vertex %d: miter ratio %.3f exceeds limit %.2f", i, ratio, limit)
		}
	}
	return nil
}
