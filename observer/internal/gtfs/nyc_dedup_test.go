package gtfs

import (
	"archive/tar"
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"math"
	"os"
	"strings"
	"testing"

	"github.com/klauspost/compress/zstd"
)


func TestNYCTrunkDeduplicationAndCanonicalCorridors(t *testing.T) {
	packPath := "../../../DeriveeNative/Derivee/city-nyc.pack.zst"
	geoBytes, err := extractGeoJSONFromZstPack(packPath)
	if err != nil {
		t.Skipf("Skipping NYC pack test, bundled pack not accessible: %v", err)
		return
	}

	var fc GeoJSONFeatureCollection
	if err := json.Unmarshal(geoBytes, &fc); err != nil {
		t.Fatalf("Failed to unmarshal GeoJSON: %v", err)
	}

	t.Logf("Generated %d canonical corridor features from NYC Subway network", len(fc.Features))

	if len(fc.Features) == 0 {
		t.Fatalf("Expected corridor features, got 0")
	}

	// Verify all invariants on the generated NYC dataset
	kMax := 0
	corridorCounts := make(map[int]int)

	ribbonCount := 0
	capsuleCount := 0

	for _, feat := range fc.Features {
		props := feat.Properties

		if props.FeatureType == "platform_capsule" {
			capsuleCount++
			// Wave V.5 Platform Capsule Invariants:
			if props.CasingColor != "#FFFFFF" || props.CasingColorHex != "#FFFFFF" {
				t.Errorf("Capsule %s: casing color not #FFFFFF: %s", props.CorridorID, props.CasingColor)
			}
			if props.StationName == "" || props.StopID == "" {
				t.Errorf("Capsule %s: missing station name or stop ID", props.CorridorID)
			}
			if props.BundleSize < 2 || props.BundleSize > 3 {
				t.Errorf("Capsule %s: invalid bundle size %d", props.CorridorID, props.BundleSize)
			}
			if props.CasingWidth <= 0 || props.CasingWidthZ11 <= 0 || props.CasingWidthZ17 <= 0 {
				t.Errorf("Capsule %s: invalid casing widths", props.CorridorID)
			}
			if len(props.Routes) == 0 {
				t.Errorf("Capsule %s: empty routes", props.CorridorID)
			}
			continue
		}

		ribbonCount++
		if props.BundleSize > kMax {
			kMax = props.BundleSize
		}
		corridorCounts[props.BundleSize]++

		// INV-CORR-01: Trunk color presence (and reject white #FFFFFF on route ribbons)
		if props.TrunkColor == "" || strings.ToUpper(props.TrunkColor) == "#FFFFFF" || strings.ToUpper(props.TrunkColorHex) == "#FFFFFF" {
			t.Errorf("INV-CORR-01: invalid or white trunk_color in line feature %s: %s", props.CorridorID, props.TrunkColor)
		}

		// Wave V.3+V.4 attributes check
		if props.CasingWidth <= 0 || props.CasingWidthZ11 <= 0 || props.CasingWidthZ17 <= 0 {
			t.Errorf("Invalid casing widths in feature %s: z11=%f, z14=%f, z17=%f",
				props.CorridorID, props.CasingWidthZ11, props.CasingWidth, props.CasingWidthZ17)
		}
		if props.SortKey <= 0 {
			t.Errorf("Invalid sort key in feature %s: %d", props.CorridorID, props.SortKey)
		}
		if props.ArcLengthM <= 0 {
			t.Errorf("Invalid arc length in feature %s: %f", props.CorridorID, props.ArcLengthM)
		}

		// INV-CORR-02: Multiplicity bound
		if props.BundleSize > 3 {
			t.Fatalf("INV-CORR-02 violated: arc %s has bundle size %d > 3", props.CorridorID, props.BundleSize)
		}

		// INV-CORR-03: Canonical direction
		coords, ok := ParseLineCoords(feat.Geometry.Coordinates)
		if !ok || len(coords) < 2 {
			t.Fatalf("Invalid LineString coordinates in feature %s", props.CorridorID)
		}
		startKey := ToPointKey(Point2D{Lon: coords[0][0], Lat: coords[0][1]})
		endKey := ToPointKey(Point2D{Lon: coords[len(coords)-1][0], Lat: coords[len(coords)-1][1]})
		if !LessPointKey(startKey, endKey) && startKey != endKey {
			t.Errorf("INV-CORR-03 violated: feature %s not canonically oriented: start=%v, end=%v",
				props.CorridorID, startKey, endKey)
		}

		// INV-OFFSET-02: Zero self-intersections across all emitted subway features
		var pts2D []Point2D
		for _, c := range coords {
			pts2D = append(pts2D, Point2D{Lon: c[0], Lat: c[1]})
		}
		metricCoords, _, _ := ProjectToLocalM(pts2D)
		if err := ValidateSelfIntersections_INV_OFFSET_02(metricCoords); err != nil {
			t.Errorf("INV-OFFSET-02 failed on %s (bundle %d/%d): %v", props.CorridorID, props.BundleIndex, props.BundleSize, err)
		}

		// Wave V.2b delta_offset assertions
		if props.BundleSize == 1 && props.DeltaOffset != 0.0 {
			t.Errorf("K=1 feature %s should have delta_offset=0, got %f", props.CorridorID, props.DeltaOffset)
		}
		if props.BundleSize > 1 && math.Abs(props.DeltaOffset) > 3.501 {
			t.Errorf("Feature %s delta_offset %f exceeds ceiling of 3.5pt", props.CorridorID, props.DeltaOffset)
		}

		// Additive attributes check
		if !strings.HasPrefix(props.CompositeKey, "badge_") {
			t.Errorf("Invalid composite key: %s", props.CompositeKey)
		}
		if len(props.Routes) == 0 {
			t.Errorf("Empty routes array in feature %s", props.CorridorID)
		}
	}

	if capsuleCount == 0 {
		t.Fatalf("Expected platform capsule features in pack, got 0")
	}
	t.Logf("Verified %d route ribbons and %d platform capsules", ribbonCount, capsuleCount)

	// Verify parallel separation across corridors with K >= 2
	corridorFeatures := make(map[string][]GeoJSONFeature)
	for _, feat := range fc.Features {
		corridorFeatures[feat.Properties.CorridorID] = append(corridorFeatures[feat.Properties.CorridorID], feat)
	}

	for corridorID, feats := range corridorFeatures {
		if len(feats) >= 2 {
			// Check delta_offset symmetry
			var deltaSum float64
			for _, f := range feats {
				deltaSum += f.Properties.DeltaOffset
			}
			if math.Abs(deltaSum) > 1e-4 {
				t.Errorf("Corridor %s delta_offset sum %f is not symmetrical around 0", corridorID, deltaSum)
			}

			// Check that ribbon 0 and ribbon 1 have distinct, offset coordinates
			coords0, _ := ParseLineCoords(feats[0].Geometry.Coordinates)
			coords1, _ := ParseLineCoords(feats[1].Geometry.Coordinates)
			if len(coords0) == len(coords1) {
				allIdentical := true
				for i := 0; i < len(coords0); i++ {
					if coords0[i][0] != coords1[i][0] || coords0[i][1] != coords1[i][1] {
						allIdentical = false
						break
					}
				}
				if allIdentical {
					t.Errorf("Corridor %s parallel ribbons 0 and 1 have identical un-offset coordinates", corridorID)
				}
			}
		}
	}

	t.Logf("NYC Multiplicity Distribution: K=1: %d, K=2: %d, K=3: %d (K_max = %d)",
		corridorCounts[1], corridorCounts[2], corridorCounts[3], kMax)

	colorGroups := make(map[string][]string)
	for _, f := range fc.Features {
		if f.Properties.FeatureType != "platform_capsule" {
			colorGroups[f.Properties.TrunkColor] = append(colorGroups[f.Properties.TrunkColor], f.Properties.CompositeKey)
			if f.Properties.BundleSize >= 2 {
				coords, _ := ParseLineCoords(f.Geometry.Coordinates)
				// Print sample coords and properties for multi-ribbon corridors
				t.Logf("Multi-ribbon arc: Corridor=%s, K=%d, idx=%d, color=%s, routes=%v, offset=%f, pts=%d, start=(%.4f, %.4f)",
					f.Properties.CorridorID, f.Properties.BundleSize, f.Properties.BundleIndex, f.Properties.TrunkColor,
					f.Properties.Routes, f.Properties.DeltaOffset, len(coords), coords[0][0], coords[0][1])
			}
		}
	}
	for col, keys := range colorGroups {
		t.Logf("Trunk color %s: %d ribbons (sample: %s)", col, len(keys), keys[0])
	}

	if corridorCounts[3] == 0 {
		t.Errorf("Expected K=3 multi-ribbon corridors (e.g. Queens Blvd E/F/R), got 0")
	}
	if corridorCounts[2] == 0 {
		t.Errorf("Expected K=2 multi-ribbon corridors, got 0")
	}
}

func TestInspectAllQueensCorridors(t *testing.T) {
	packPath := "../../../DeriveeNative/Derivee/city-nyc.pack.zst"
	geoBytes, err := extractGeoJSONFromZstPack(packPath)
	if err != nil {
		t.Skipf("Skipping: %v", err)
		return
	}

	var fc GeoJSONFeatureCollection
	if err := json.Unmarshal(geoBytes, &fc); err != nil {
		t.Fatalf("Failed: %v", err)
	}

	for _, f := range fc.Features {
		p := f.Properties
		if p.FeatureType == "platform_capsule" {
			continue
		}
		coords, _ := ParseLineCoords(f.Geometry.Coordinates)
		if len(coords) < 2 {
			continue
		}
		// Queens bounding box: Lon between -73.95 and -73.70, Lat between 40.70 and 40.80
		inQueens := false
		for _, c := range coords {
			if c[0] > -73.94 && c[0] < -73.70 && c[1] > 40.72 && c[1] < 40.80 {
				inQueens = true
				break
			}
		}
		if inQueens {
			t.Logf("Queens Arc %s: K=%d idx=%d color=%s routes=%v name=%s start=(%.4f, %.4f) end=(%.4f, %.4f)",
				p.CorridorID, p.BundleSize, p.BundleIndex, p.TrunkColor, p.Routes, p.RouteShortName,
				coords[0][0], coords[0][1], coords[len(coords)-1][0], coords[len(coords)-1][1])
		}
	}
}

func extractGeoJSONFromZstPack(packPath string) ([]byte, error) {
	packFile, err := os.Open(packPath)
	if err != nil {
		return nil, err
	}
	defer packFile.Close()

	zstdReader, err := zstd.NewReader(packFile)
	if err != nil {
		return nil, err
	}
	defer zstdReader.Close()

	tarReader := tar.NewReader(zstdReader)
	for {
		header, err := tarReader.Next()
		if err == io.EOF {
			break
		}
		if err != nil {
			return nil, err
		}
		if header.Name == "transit-lines.geojson" {
			var buf bytes.Buffer
			if _, err := io.Copy(&buf, tarReader); err != nil {
				return nil, err
			}
			return buf.Bytes(), nil
		}
	}
	return nil, fmt.Errorf("transit-lines.geojson not found in pack")
}
