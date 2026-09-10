package health

import "math"

// WelfordAccumulator computes online, single-pass mean, variance, standard deviation,
// and coefficient of variation without suffering from catastrophic floating-point cancellation.
type WelfordAccumulator struct {
	count int
	mean  float64
	m2    float64
}

// NewWelfordAccumulator creates an initialized Welford accumulator.
func NewWelfordAccumulator() *WelfordAccumulator {
	return &WelfordAccumulator{}
}

// Update incorporates a new observation into the accumulator.
func (w *WelfordAccumulator) Update(x float64) {
	w.count++
	delta := x - w.mean
	w.mean += delta / float64(w.count)
	delta2 := x - w.mean
	w.m2 += delta * delta2
}

// Count returns the total number of accumulated observations.
func (w *WelfordAccumulator) Count() int {
	return w.count
}

// Mean returns the empirical mean of all observations.
func (w *WelfordAccumulator) Mean() float64 {
	return w.mean
}

// Variance returns the population variance (sigma^2) of the observations.
func (w *WelfordAccumulator) Variance() float64 {
	if w.count == 0 {
		return 0.0
	}
	v := w.m2 / float64(w.count)
	if v < 0.0 {
		return 0.0
	}
	return v
}

// SampleVariance returns the sample variance (s^2) with Bessel's correction (N - 1).
func (w *WelfordAccumulator) SampleVariance() float64 {
	if w.count <= 1 {
		return 0.0
	}
	v := w.m2 / float64(w.count-1)
	if v < 0.0 {
		return 0.0
	}
	return v
}

// StdDev returns the population standard deviation (sigma).
func (w *WelfordAccumulator) StdDev() float64 {
	return math.Sqrt(w.Variance())
}

// CV returns the Coefficient of Variation (CV = sigma / mean).
func (w *WelfordAccumulator) CV() float64 {
	if w.mean <= 0.0 {
		return 0.0
	}
	return w.StdDev() / w.mean
}
