package health

import (
	"math"
	"testing"
)

func TestWelford_EmptyAndSingle(t *testing.T) {
	w := NewWelfordAccumulator()
	if w.Count() != 0 {
		t.Errorf("expected count 0, got %d", w.Count())
	}
	if w.Mean() != 0.0 || w.Variance() != 0.0 || w.StdDev() != 0.0 || w.CV() != 0.0 {
		t.Errorf("empty accumulator should return 0 for all metrics")
	}

	w.Update(42.0)
	if w.Count() != 1 {
		t.Errorf("expected count 1, got %d", w.Count())
	}
	if w.Mean() != 42.0 {
		t.Errorf("expected mean 42.0, got %f", w.Mean())
	}
	if w.Variance() != 0.0 || w.StdDev() != 0.0 || w.CV() != 0.0 {
		t.Errorf("single observation should have zero variance")
	}
}

func TestWelford_KnownDataset(t *testing.T) {
	// Dataset: [2, 4, 4, 4, 5, 5, 7, 9]
	// Mean = 40 / 8 = 5.0
	// Sum of squared diffs: (2-5)^2 + 3*(4-5)^2 + 2*(5-5)^2 + (7-5)^2 + (9-5)^2
	//                     = 9 + 3*1 + 0 + 4 + 16 = 32
	// Population Variance = 32 / 8 = 4.0
	// Population StdDev = 2.0
	// CV = 2.0 / 5.0 = 0.4
	// Sample Variance = 32 / 7 = 4.57142857...
	data := []float64{2, 4, 4, 4, 5, 5, 7, 9}
	w := NewWelfordAccumulator()
	for _, x := range data {
		w.Update(x)
	}

	if w.Count() != 8 {
		t.Fatalf("expected count 8, got %d", w.Count())
	}
	if math.Abs(w.Mean()-5.0) > 1e-9 {
		t.Errorf("expected mean 5.0, got %f", w.Mean())
	}
	if math.Abs(w.Variance()-4.0) > 1e-9 {
		t.Errorf("expected variance 4.0, got %f", w.Variance())
	}
	if math.Abs(w.StdDev()-2.0) > 1e-9 {
		t.Errorf("expected stdDev 2.0, got %f", w.StdDev())
	}
	if math.Abs(w.CV()-0.4) > 1e-9 {
		t.Errorf("expected CV 0.4, got %f", w.CV())
	}
	expectedSampleVar := 32.0 / 7.0
	if math.Abs(w.SampleVariance()-expectedSampleVar) > 1e-9 {
		t.Errorf("expected sample variance %f, got %f", expectedSampleVar, w.SampleVariance())
	}
}

func TestWelford_NumericalStability(t *testing.T) {
	// Catastrophic cancellation test with large base offset:
	// data = [1e9 + 1, 1e9 + 2, 1e9 + 3]
	// True mean = 1e9 + 2
	// True population variance = ((1-2)^2 + (2-2)^2 + (3-2)^2) / 3 = 2/3 ≈ 0.6666666666666666
	base := 1e9
	data := []float64{base + 1.0, base + 2.0, base + 3.0}

	w := NewWelfordAccumulator()
	for _, x := range data {
		w.Update(x)
	}

	expectedMean := base + 2.0
	expectedVar := 2.0 / 3.0

	if math.Abs(w.Mean()-expectedMean) > 1e-6 {
		t.Errorf("expected mean %f, got %f", expectedMean, w.Mean())
	}
	if math.Abs(w.Variance()-expectedVar) > 1e-6 {
		t.Errorf("expected variance %f, got %f", expectedVar, w.Variance())
	}
}
