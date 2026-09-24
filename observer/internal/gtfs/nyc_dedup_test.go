package gtfs

import (
	"archive/tar"
	"bytes"
	"encoding/json"
	"fmt"
	"io"
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

	for _, feat := range fc.Features {
		props := feat.Properties
		if props.BundleSize > kMax {
			kMax = props.BundleSize
		}
		corridorCounts[props.BundleSize]++

		// INV-CORR-01: Color consistency
		if props.Color != props.TrunkColor {
			t.Errorf("INV-CORR-01: color %s != trunk_color %s", props.Color, props.TrunkColor)
		}

		// INV-CORR-02: Multiplicity bound
		if props.BundleSize > 3 {
			t.Fatalf("INV-CORR-02 violated: arc %s has bundle size %d > 3", props.CorridorID, props.BundleSize)
		}

		// INV-CORR-03: Canonical direction
		coords, ok := parseLineCoords(feat.Geometry.Coordinates)
		if !ok || len(coords) < 2 {
			t.Fatalf("Invalid LineString coordinates in feature %s", props.CorridorID)
		}
		startKey := ToPointKey(Point2D{Lon: coords[0][0], Lat: coords[0][1]})
		endKey := ToPointKey(Point2D{Lon: coords[len(coords)-1][0], Lat: coords[len(coords)-1][1]})
		if !LessPointKey(startKey, endKey) && startKey != endKey {
			t.Errorf("INV-CORR-03 violated: feature %s not canonically oriented: start=%v, end=%v",
				props.CorridorID, startKey, endKey)
		}

		// Additive attributes check
		if !strings.HasPrefix(props.CompositeKey, "badge_") {
			t.Errorf("Invalid composite key: %s", props.CompositeKey)
		}
		if len(props.Routes) == 0 {
			t.Errorf("Empty routes array in feature %s", props.CorridorID)
		}
	}

	t.Logf("NYC Multiplicity Distribution: K=1: %d, K=2: %d, K=3: %d (K_max = %d)",
		corridorCounts[1], corridorCounts[2], corridorCounts[3], kMax)
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
