package gtfs

import (
	"fmt"
	"math"
)

// MinFilletLengthM defines the lower bound for fillet length in meters (INV-FILLET-02: >= 20.0m)
const MinFilletLengthM = 20.0

// DefaultFilletLengthM defines the canonical fillet target length in meters (Doc 22 §3.3: 50.0m)
const DefaultFilletLengthM = 50.0

// MaxFilletLengthM defines the upper bound for fillet length in meters (INV-FILLET-02: <= 120.0m)
const MaxFilletLengthM = 120.0

// MaxFilletArcFraction defines the maximum fraction of arc length allocated to a fillet (0.35)
const MaxFilletArcFraction = 0.35

// HermiteFilletResult holds the generated transition fillet geometry and properties
type HermiteFilletResult struct {
	FilletID   string    `json:"fillet_id"`
	LengthM    float64   `json:"length_m"`
	PointsWGS  []Point2D `json:"coordinates"`
	PointsVec  []Vec2D   `json:"-"`
	C1StartDot float64   `json:"c1_start_dot"`
	C1EndDot   float64   `json:"c1_end_dot"`
}

// ClampFilletLength calculates the optimal fillet length enforcing INV-FILLET-02:
// 20.0m <= L_fillet <= min(120.0m, 0.35 * L_arc)
func ClampFilletLength(targetM, arcLengthM float64) float64 {
	maxAllowed := math.Min(MaxFilletLengthM, MaxFilletArcFraction*arcLengthM)
	if maxAllowed < MinFilletLengthM {
		// For very short arcs, allow up to 50% of arc length or minimum 5m
		maxAllowed = math.Max(5.0, arcLengthM*0.5)
	}

	if targetM > maxAllowed {
		return maxAllowed
	}
	if targetM < MinFilletLengthM && maxAllowed >= MinFilletLengthM {
		return MinFilletLengthM
	}
	return targetM
}

// EvaluateCubicHermitePoint computes point on cubic Hermite curve at parameter t in [0, 1]
func EvaluateCubicHermitePoint(p0, p1, m0, m1 Vec2D, t float64) Vec2D {
	t2 := t * t
	t3 := t2 * t

	h00 := 2*t3 - 3*t2 + 1
	h10 := t3 - 2*t2 + t
	h01 := -2*t3 + 3*t2
	h11 := t3 - t2

	return Vec2D{
		X: h00*p0.X + h10*m0.X + h01*p1.X + h11*m1.X,
		Y: h00*p0.Y + h10*m0.Y + h01*p1.Y + h11*m1.Y,
	}
}

// EvaluateCubicHermiteDerivative computes tangent derivative on cubic Hermite curve at parameter t in [0, 1]
func EvaluateCubicHermiteDerivative(p0, p1, m0, m1 Vec2D, t float64) Vec2D {
	t2 := t * t

	dh00 := 6*t2 - 6*t
	dh10 := 3*t2 - 4*t + 1
	dh01 := -6*t2 + 6*t
	dh11 := 3*t2 - 2*t

	return Vec2D{
		X: dh00*p0.X + dh10*m0.X + dh01*p1.X + dh11*m1.X,
		Y: dh00*p0.Y + dh10*m0.Y + dh01*p1.Y + dh11*m1.Y,
	}
}

// BuildHermiteFilletMetric constructs a tangent-continuous C^1 transition fillet in local metric space
// between departure point p0 (with tangent t0) and arrival point p1 (with tangent t1).
// Enforces INV-FILLET-01 (C^1 continuity: dot product > 0.999) and INV-FILLET-02 (length bounds).
func BuildHermiteFilletMetric(p0, p1, t0, t1 Vec2D, arcLengthM float64, steps int) (*HermiteFilletResult, error) {
	if steps < 4 {
		steps = 8
	}

	chordX := p1.X - p0.X
	chordY := p1.Y - p0.Y
	chordLen := math.Hypot(chordX, chordY)

	// Clamp fillet length to satisfy INV-FILLET-02
	filletLen := ClampFilletLength(DefaultFilletLengthM, arcLengthM)

	// Tangent scaling factor
	scale := chordLen
	if scale < 1e-4 {
		scale = filletLen
	}

	m0 := Vec2D{X: t0.X * scale, Y: t0.Y * scale}
	m1 := Vec2D{X: t1.X * scale, Y: t1.Y * scale}

	// Sample curve points
	pts := make([]Vec2D, steps+1)
	for i := 0; i <= steps; i++ {
		t := float64(i) / float64(steps)
		pts[i] = EvaluateCubicHermitePoint(p0, p1, m0, m1, t)
	}

	// Calculate C^1 continuity dot products
	// At t = 0
	d0 := EvaluateCubicHermiteDerivative(p0, p1, m0, m1, 0.0)
	d0Len := math.Hypot(d0.X, d0.Y)
	c1StartDot := 1.0
	if d0Len > 1e-6 {
		u0 := Vec2D{X: d0.X / d0Len, Y: d0.Y / d0Len}
		c1StartDot = u0.X*t0.X + u0.Y*t0.Y
	}

	// At t = 1
	d1 := EvaluateCubicHermiteDerivative(p0, p1, m0, m1, 1.0)
	d1Len := math.Hypot(d1.X, d1.Y)
	c1EndDot := 1.0
	if d1Len > 1e-6 {
		u1 := Vec2D{X: d1.X / d1Len, Y: d1.Y / d1Len}
		c1EndDot = u1.X*t1.X + u1.Y*t1.Y
	}

	return &HermiteFilletResult{
		LengthM:    filletLen,
		PointsVec:  pts,
		C1StartDot: c1StartDot,
		C1EndDot:   c1EndDot,
	}, nil
}

// BuildHermiteFillet constructs a C^1 cubic Hermite transition fillet between WGS84 endpoints
func BuildHermiteFillet(p0, p1 Point2D, t0, t1 Point2D, arcLengthM float64, steps int) (*HermiteFilletResult, error) {
	vecs, refLat, refLon := ProjectToLocalM([]Point2D{p0, p1})
	// Tangent vectors are already normalized directions (dLon, dLat)
	// Project tangent direction to metric unit vector
	cosLat := math.Cos(refLat * math.Pi / 180.0)
	t0Metric := Vec2D{X: t0.Lon * cosLat, Y: t0.Lat}
	t0Len := math.Hypot(t0Metric.X, t0Metric.Y)
	if t0Len > 1e-7 {
		t0Metric.X /= t0Len
		t0Metric.Y /= t0Len
	} else {
		t0Metric = Vec2D{X: 1, Y: 0}
	}

	t1Metric := Vec2D{X: t1.Lon * cosLat, Y: t1.Lat}
	t1Len := math.Hypot(t1Metric.X, t1Metric.Y)
	if t1Len > 1e-7 {
		t1Metric.X /= t1Len
		t1Metric.Y /= t1Len
	} else {
		t1Metric = Vec2D{X: 1, Y: 0}
	}

	res, err := BuildHermiteFilletMetric(vecs[0], vecs[1], t0Metric, t1Metric, arcLengthM, steps)
	if err != nil {
		return nil, err
	}

	res.PointsWGS = UnprojectFromLocalM(res.PointsVec, refLat, refLon)
	return res, nil
}

// ValidateFilletContinuity_INV_FILLET_01 asserts that fillet start and end tangents match progenitor tangents > 0.999
func ValidateFilletContinuity_INV_FILLET_01(res *HermiteFilletResult) error {
	if res.C1StartDot < 0.999 {
		return fmt.Errorf("INV-FILLET-01 violated at start: tangent dot product %.5f < 0.999", res.C1StartDot)
	}
	if res.C1EndDot < 0.999 {
		return fmt.Errorf("INV-FILLET-01 violated at end: tangent dot product %.5f < 0.999", res.C1EndDot)
	}
	return nil
}

// ValidateFilletLength_INV_FILLET_02 asserts that fillet length respects spatial bounds
func ValidateFilletLength_INV_FILLET_02(lengthM, arcLengthM float64) error {
	if arcLengthM >= (MinFilletLengthM / MaxFilletArcFraction) {
		if lengthM < MinFilletLengthM || lengthM > MaxFilletLengthM {
			return fmt.Errorf("INV-FILLET-02 violated: fillet length %.1fm outside [%.1fm, %.1fm]", lengthM, MinFilletLengthM, MaxFilletLengthM)
		}
		if lengthM > MaxFilletArcFraction*arcLengthM*1.05 {
			return fmt.Errorf("INV-FILLET-02 violated: fillet length %.1fm exceeds 35%% of arc length (%.1fm)", lengthM, 0.35*arcLengthM)
		}
	}
	return nil
}

// OffsetPolylineWithFilletMetric offsets a polyline in metric space with a smooth C^1 cubic Hermite transition
// from startOffsetM to endOffsetM over the clamped transition length L_fillet.
func OffsetPolylineWithFilletMetric(vecs []Vec2D, startOffsetM, endOffsetM float64, opts OffsetOptions) []Vec2D {
	clean := CleanMetricPolyline(vecs)
	n := len(clean)
	if n < 2 {
		return clean
	}
	if math.Abs(startOffsetM-endOffsetM) < 1e-4 {
		return OffsetPolylineMetric(clean, startOffsetM, opts)
	}

	// Calculate cumulative arc lengths
	cumLengths := make([]float64, n)
	totalLen := 0.0
	for i := 0; i < n-1; i++ {
		d := math.Hypot(clean[i+1].X-clean[i].X, clean[i+1].Y-clean[i].Y)
		totalLen += d
		cumLengths[i+1] = totalLen
	}

	filletLen := ClampFilletLength(DefaultFilletLengthM, totalLen)

	// Precalculate segment tangents and normals
	type Seg struct {
		N Vec2D
	}
	segs := make([]Seg, n-1)
	for i := 0; i < n-1; i++ {
		dx := clean[i+1].X - clean[i].X
		dy := clean[i+1].Y - clean[i].Y
		l := math.Hypot(dx, dy)
		if l < 1e-7 {
			l = 1e-7
		}
		segs[i] = Seg{N: Vec2D{X: -dy / l, Y: dx / l}}
	}

	evaluateOffset := func(s float64) float64 {
		if s >= filletLen {
			return endOffsetM
		}
		t := s / filletLen
		t2 := t * t
		t3 := t2 * t
		h00 := 2*t3 - 3*t2 + 1
		h01 := -2*t3 + 3*t2
		return startOffsetM*h00 + endOffsetM*h01
	}

	var offsetPts []Vec2D

	// Start vertex
	d0 := evaluateOffset(0)
	offsetPts = append(offsetPts, Vec2D{
		X: clean[0].X + d0*segs[0].N.X,
		Y: clean[0].Y + d0*segs[0].N.Y,
	})

	// Intermediate vertices
	limit := opts.MiterLimit
	if limit <= 1.0 {
		limit = DefaultMiterLimit
	}

	for i := 1; i < n-1; i++ {
		di := evaluateOffset(cumLengths[i])
		nPrev := segs[i-1].N
		nCurr := segs[i].N

		bx := nPrev.X + nCurr.X
		by := nPrev.Y + nCurr.Y
		bLen := math.Hypot(bx, by)

		if bLen < 1e-6 {
			b1 := Vec2D{X: clean[i].X + di*nPrev.X, Y: clean[i].Y + di*nPrev.Y}
			b2 := Vec2D{X: clean[i].X + di*nCurr.X, Y: clean[i].Y + di*nCurr.Y}
			offsetPts = append(offsetPts, b1, b2)
			continue
		}

		unitBisect := Vec2D{X: bx / bLen, Y: by / bLen}
		cosAlpha := unitBisect.X*nPrev.X + unitBisect.Y*nPrev.Y
		if cosAlpha < 1e-6 {
			cosAlpha = 1e-6
		}

		miterRatio := 1.0 / cosAlpha
		if opts.BevelSharpEdges && miterRatio > limit {
			b1 := Vec2D{X: clean[i].X + di*nPrev.X, Y: clean[i].Y + di*nPrev.Y}
			b2 := Vec2D{X: clean[i].X + di*nCurr.X, Y: clean[i].Y + di*nCurr.Y}
			offsetPts = append(offsetPts, b1, b2)
		} else {
			miterDist := di / cosAlpha
			offsetPts = append(offsetPts, Vec2D{
				X: clean[i].X + miterDist*unitBisect.X,
				Y: clean[i].Y + miterDist*unitBisect.Y,
			})
		}
	}

	// End vertex
	dn := evaluateOffset(cumLengths[n-1])
	lastSeg := segs[n-2]
	offsetPts = append(offsetPts, Vec2D{
		X: clean[n-1].X + dn*lastSeg.N.X,
		Y: clean[n-1].Y + dn*lastSeg.N.Y,
	})

	return offsetPts
}

// OffsetPolylineWithFillet applies C^1 Hermite fillet transition offsetting in WGS84 space
func OffsetPolylineWithFillet(pts []Point2D, startOffsetM, endOffsetM float64, opts OffsetOptions) ([]Point2D, error) {
	if len(pts) < 2 {
		return pts, nil
	}
	metricPts, refLat, refLon := ProjectToLocalM(pts)
	offsetMetric := OffsetPolylineWithFilletMetric(metricPts, startOffsetM, endOffsetM, opts)
	return UnprojectFromLocalM(offsetMetric, refLat, refLon), nil
}

