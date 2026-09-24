package pack

import (
	"os"
	"path/filepath"
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
	geoPath := filepath.Join(extractedDir, "transit-lines.geojson")

	geoBytes, err := os.ReadFile(geoPath)
	if err != nil {
		t.Fatalf("Failed to read extracted GeoJSON: %v", err)
	}

	ds, err := gtfs.ConvertLegacySubwayToDataset(geoBytes)
	if err != nil {
		t.Fatalf("ConvertLegacySubwayToDataset failed: %v", err)
	}

	_, newGeoBytes, err := gtfs.GenerateTransitLinesGeoJSON(ds)
	if err != nil {
		t.Fatalf("GenerateTransitLinesGeoJSON failed: %v", err)
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
