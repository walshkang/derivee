package pack

import (
	"database/sql"
	"os"
	"path/filepath"
	"testing"
	"time"

	_ "github.com/mattn/go-sqlite3"

	"observer/internal/builder"
	"observer/internal/gtfs"
)

func TestEndToEnd_PackCreationAndVerification(t *testing.T) {
	tempDir := t.TempDir()

	// 1. Create dummy city_config.json
	cfg := CityConfig{
		Version:     1,
		Slug:        "testcity",
		DisplayName: "Test City",
		Region:      "Testing Region",
		Bounds: GeoBounds{
			MinLatitude:  40.0,
			MaxLatitude:  41.0,
			MinLongitude: -74.0,
			MaxLongitude: -73.0,
		},
		Center: MapCenter{
			Latitude:    40.5,
			Longitude:   -73.5,
			DefaultZoom: 13.0,
		},
		Transit: TransitConfig{
			AgencyName:   "Test Transit Agency",
			Attributions: []string{"Test Agency Open Data"},
			RealtimeEndpoints: []RealtimeEndpoint{
				{
					FeedID:              "test_feed",
					URL:                 "https://example.com/gtfs-rt",
					PollIntervalSeconds: 15,
				},
			},
			FeedRouteMapping: map[string]string{
				"T1": "test_feed",
			},
			ScheduleValidity: ScheduleValidity{
				StartDate:   "2026-01-01",
				EndDate:     "2026-12-31",
				SeasonLabel: "Testing 2026",
			},
		},
	}

	configPath := filepath.Join(tempDir, "city_config.json")
	if err := SaveCityConfig(&cfg, configPath); err != nil {
		t.Fatalf("Failed to save city config: %v", err)
	}

	// 2. Create dummy transit-lines.geojson
	geojsonPath := filepath.Join(tempDir, "transit-lines.geojson")
	geojsonContent := `{"type":"FeatureCollection","features":[]}`
	if err := os.WriteFile(geojsonPath, []byte(geojsonContent), 0644); err != nil {
		t.Fatalf("Failed to write geojson: %v", err)
	}

	// 3. Build synthetic transit.sqlite
	dbPath := filepath.Join(tempDir, "transit.sqlite")
	db, err := builder.InitTransitDB(dbPath)
	if err != nil {
		t.Fatalf("Failed to init transit DB: %v", err)
	}

	stops := map[string]gtfs.Stop{
		"P1": {StopID: "P1", StopName: "Main Terminal", StopLat: 40.5, StopLon: -73.5, LocationType: 1},
		"S1": {StopID: "S1", StopName: "Main Track 1", StopLat: 40.5, StopLon: -73.5, LocationType: 0, ParentStation: "P1", PlatformCode: "1"},
		"S2": {StopID: "S2", StopName: "Second St", StopLat: 40.51, StopLon: -73.51, LocationType: 0},
	}

	routes := map[string]gtfs.Route{
		"R1": {RouteID: "R1", RouteShortName: "1", RouteLongName: "Main Line", RouteType: 1, RouteColor: "#FF0000"},
	}

	resolutions := gtfs.BuildStopResolutionClosure(stops)

	patterns := []gtfs.ScheduledHourlyPattern{
		{
			StopID:             "S1",
			RouteID:            "R1",
			DirectionID:        0,
			HourOfDay:          8,
			ServiceMask:        0b0000000010000000,
			BaselineDaysOfWeek: 0b00111110,
			MinuteOffsets:      "05,15,25,35,45,55",
			Headsign:           "Northbound",
		},
	}

	if err := builder.BulkInsertStops(db, stops, map[string][]string{"S1": {"R1"}}); err != nil {
		t.Fatalf("BulkInsertStops failed: %v", err)
	}
	if err := builder.BulkInsertRoutes(db, routes); err != nil {
		t.Fatalf("BulkInsertRoutes failed: %v", err)
	}
	if err := builder.BulkInsertStopResolution(db, resolutions); err != nil {
		t.Fatalf("BulkInsertStopResolution failed: %v", err)
	}
	if err := builder.BulkInsertPatterns(db, patterns); err != nil {
		t.Fatalf("BulkInsertPatterns failed: %v", err)
	}

	// 4. Run Optimizer and verify sqlite_stat1
	if err := builder.OptimizeDatabase(db); err != nil {
		t.Fatalf("OptimizeDatabase failed: %v", err)
	}
	db.Close()

	// 5. Create .pack.zst
	packPath := filepath.Join(tempDir, "city-testcity.pack.zst")
	entry, err := CreateCityPack(configPath, dbPath, geojsonPath, packPath)
	if err != nil {
		t.Fatalf("CreateCityPack failed: %v", err)
	}

	if entry.Slug != "testcity" {
		t.Errorf("Expected slug 'testcity', got '%s'", entry.Slug)
	}
	if entry.CompressedSizeBytes <= 0 || entry.UncompressedSizeBytes <= 0 {
		t.Errorf("Invalid size metrics: compressed=%d, uncompressed=%d", entry.CompressedSizeBytes, entry.UncompressedSizeBytes)
	}
	if entry.SHA256 == "" {
		t.Errorf("Expected non-empty SHA256 hash")
	}

	// 6. Verify pack archive structure
	if err := VerifyCityPack(packPath); err != nil {
		t.Fatalf("VerifyCityPack failed: %v", err)
	}

	// 7. Extract and check contents
	extractDir := filepath.Join(tempDir, "extracted")
	if err := ExtractCityPack(packPath, extractDir); err != nil {
		t.Fatalf("ExtractCityPack failed: %v", err)
	}

	extractedDBPath := filepath.Join(extractDir, "transit.sqlite")
	extractedDB, err := sql.Open("sqlite3", extractedDBPath)
	if err != nil {
		t.Fatalf("Failed to open extracted DB: %v", err)
	}
	defer extractedDB.Close()

	var patternCount int
	if err := extractedDB.QueryRow("SELECT COUNT(*) FROM scheduled_hourly_patterns").Scan(&patternCount); err != nil {
		t.Fatalf("Failed to query scheduled_hourly_patterns: %v", err)
	}
	if patternCount != 1 {
		t.Errorf("Expected 1 pattern, got %d", patternCount)
	}

	var statCount int
	if err := extractedDB.QueryRow("SELECT COUNT(*) FROM sqlite_stat1").Scan(&statCount); err != nil {
		t.Fatalf("Failed to query sqlite_stat1 in extracted DB: %v", err)
	}
	if statCount == 0 {
		t.Errorf("Expected sqlite_stat1 to be present and populated in extracted DB")
	}
}

func TestManifestSaveLoad(t *testing.T) {
	tempDir := t.TempDir()
	manifestPath := filepath.Join(tempDir, "cities.json")

	manifest := CitiesManifest{
		Version:     1,
		LastUpdated: time.Now().UTC().Format(time.RFC3339),
		Cities: []CityManifestEntry{
			{
				Slug:                  "nyc",
				DisplayName:           "New York City",
				Region:                "New York, USA",
				CompressedSizeBytes:   12800000,
				UncompressedSizeBytes: 28500000,
				IsBundled:             true,
				Version:               "1.1.0",
				SHA256:                "abc123",
			},
		},
	}

	if err := SaveCitiesManifest(&manifest, manifestPath); err != nil {
		t.Fatalf("Failed to save manifest: %v", err)
	}

	loaded, err := LoadCitiesManifest(manifestPath)
	if err != nil {
		t.Fatalf("Failed to load manifest: %v", err)
	}

	if len(loaded.Cities) != 1 || loaded.Cities[0].Slug != "nyc" {
		t.Errorf("Loaded manifest mismatch: %+v", loaded)
	}
}
