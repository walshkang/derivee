package pack

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"observer/internal/gtfs"
)

func TestRepackNYCWithCanonicalCorridors(t *testing.T) {
	bundledPackPath := "../../../DeriveeNative/Derivee/city-nyc.pack.zst"
	if _, err := os.Stat(bundledPackPath); os.IsNotExist(err) {
		t.Skipf("Skipping NYC repack: %s not found", bundledPackPath)
		return
	}

	tempDir := t.TempDir()
	extractedDir := filepath.Join(tempDir, "extracted")
	if err := ExtractCityPack(bundledPackPath, extractedDir); err != nil {
		t.Fatalf("ExtractCityPack failed: %v", err)
	}

	configPath := filepath.Join(extractedDir, "city_config.json")
	dbPath := filepath.Join(extractedDir, "transit.sqlite")

	// Always use immutable source subway lines from DeriveeNative/Derivee/subway-lines.geojson
	// to avoid destructive feedback loops when re-extracting transit-lines.geojson
	rawSubwayPath := "../../../DeriveeNative/Derivee/subway-lines.geojson"
	geoBytes, err := os.ReadFile(rawSubwayPath)
	if err != nil {
		t.Fatalf("Failed to read raw subway GeoJSON %s: %v", rawSubwayPath, err)
	}

	benchmarkStations := []struct {
		name string
	}{
		{"Queens Plaza"},
		{"Queensboro Plaza"},
		{"Court Sq"},
		{"4th Ave-9th St"},
	}

	ds, err := gtfs.ConvertLegacySubwayToDataset(geoBytes)
	if err != nil {
		t.Fatalf("ConvertLegacySubwayToDataset failed: %v", err)
	}

	if err := gtfs.HydrateStopsFromSQLite(ds, dbPath); err != nil {
		t.Fatalf("HydrateStopsFromSQLite failed: %v", err)
	}

	fc, newGeoBytes, err := gtfs.GenerateTransitLinesGeoJSON(ds)
	if err != nil {
		t.Fatalf("GenerateTransitLinesGeoJSON failed: %v", err)
	}

	capsuleCount := 0
	matchedBenchmarks := make(map[string]bool)
	kCounts := make(map[int]int)

	for _, f := range fc.Features {
		if f.Properties.FeatureType == "platform_capsule" {
			capsuleCount++
			stName := f.Properties.StationName
			for _, b := range benchmarkStations {
				if strings.Contains(strings.ToLower(stName), strings.ToLower(b.name)) ||
					(b.name == "Court Sq" && strings.Contains(stName, "Court")) ||
					(b.name == "4th Ave-9th St" && (strings.Contains(stName, "9 St") || strings.Contains(stName, "4 Av"))) {
					matchedBenchmarks[b.name] = true
					t.Logf("Matched benchmark %s with capsule: %s (StopID=%s, CorridorID=%s, K=%d, Routes=%v)",
						b.name, stName, f.Properties.StopID, f.Properties.CorridorID, f.Properties.BundleSize, f.Properties.Routes)
				}
			}
		} else {
			kCounts[f.Properties.BundleSize]++
			if f.Properties.TrunkColor == "#FFFFFF" || f.Properties.TrunkColorHex == "#FFFFFF" {
				t.Errorf("Line ribbon %s has white trunk color #FFFFFF", f.Properties.CorridorID)
			}
		}
	}
	t.Logf("Generated %d transit features (%d route ribbons, %d platform capsules)",
		len(fc.Features), len(fc.Features)-capsuleCount, capsuleCount)
	t.Logf("NYC Multiplicity Distribution: K=1: %d, K=2: %d, K=3: %d", kCounts[1], kCounts[2], kCounts[3])
	if kCounts[3] == 0 {
		t.Errorf("Expected K=3 multi-ribbon corridors (e.g. Queens Blvd E/F/R), got 0")
	}
	if kCounts[2] == 0 {
		t.Errorf("Expected K=2 multi-ribbon corridors, got 0")
	}

	for _, b := range benchmarkStations {
		if !matchedBenchmarks[b.name] {
			t.Errorf("Benchmark station %s has no generated platform capsule!", b.name)
		}
	}

	newGeoPath := filepath.Join(tempDir, "transit-lines.geojson")
	if err := os.WriteFile(newGeoPath, newGeoBytes, 0644); err != nil {
		t.Fatalf("Failed to write new GeoJSON: %v", err)
	}

	packPath := filepath.Join(tempDir, "city-nyc.pack.zst")
	manifestEntry, err := CreateCityPack(configPath, dbPath, newGeoPath, packPath)
	if err != nil {
		t.Fatalf("CreateCityPack failed: %v", err)
	}

	t.Logf("Generated NYC City Pack: slug=%s, compressed=%d bytes, uncompressed=%d bytes, sha256=%s",
		manifestEntry.Slug, manifestEntry.CompressedSizeBytes, manifestEntry.UncompressedSizeBytes, manifestEntry.SHA256)

	// Verify pack structure
	if err := VerifyCityPack(packPath); err != nil {
		t.Fatalf("VerifyCityPack failed: %v", err)
	}

	packBytes, err := os.ReadFile(packPath)
	if err != nil {
		t.Fatalf("Failed to read generated pack: %v", err)
	}
	if err := os.WriteFile(bundledPackPath, packBytes, 0644); err != nil {
		t.Fatalf("Failed to write to %s: %v", bundledPackPath, err)
	}
	t.Logf("Successfully updated bundled pack at %s (%d bytes)", bundledPackPath, len(packBytes))
}
