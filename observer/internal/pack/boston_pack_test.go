package pack

import (
	"database/sql"
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	_ "github.com/mattn/go-sqlite3"

	"observer/internal/builder"
	"observer/internal/gtfs"
)

func TestBostonMBTA_MultiModalPackCompilationAndVerification(t *testing.T) {
	tempDir := t.TempDir()
	anchorDate := time.Date(2026, 8, 25, 0, 0, 0, 0, time.UTC)

	// 1. Build Multi-Modal Boston GTFS Dataset
	ds := gtfs.NewDataset(anchorDate)

	// Agencies
	ds.Agencies["MBTA"] = gtfs.Agency{
		AgencyID:       "1",
		AgencyName:     "Massachusetts Bay Transportation Authority",
		AgencyURL:      "https://www.mbta.com",
		AgencyTimezone: "America/New_York",
	}

	// Routes
	// Heavy Rail Subway (route_type = 1)
	ds.Routes["Red"] = gtfs.Route{RouteID: "Red", AgencyID: "1", RouteShortName: "Red", RouteLongName: "Red Line", RouteType: 1, RouteColor: "DA291C", RouteTextColor: "FFFFFF"}
	ds.Routes["Orange"] = gtfs.Route{RouteID: "Orange", AgencyID: "1", RouteShortName: "Orange", RouteLongName: "Orange Line", RouteType: 1, RouteColor: "ED8B00", RouteTextColor: "FFFFFF"}
	ds.Routes["Blue"] = gtfs.Route{RouteID: "Blue", AgencyID: "1", RouteShortName: "Blue", RouteLongName: "Blue Line", RouteType: 1, RouteColor: "003DA5", RouteTextColor: "FFFFFF"}

	// Light Rail LRT (route_type = 0)
	ds.Routes["Green-B"] = gtfs.Route{RouteID: "Green-B", AgencyID: "1", RouteShortName: "Green-B", RouteLongName: "Green Line B", RouteType: 0, RouteColor: "00843D", RouteTextColor: "FFFFFF"}
	ds.Routes["Green-C"] = gtfs.Route{RouteID: "Green-C", AgencyID: "1", RouteShortName: "Green-C", RouteLongName: "Green Line C", RouteType: 0, RouteColor: "00843D", RouteTextColor: "FFFFFF"}
	ds.Routes["Green-D"] = gtfs.Route{RouteID: "Green-D", AgencyID: "1", RouteShortName: "Green-D", RouteLongName: "Green Line D", RouteType: 0, RouteColor: "00843D", RouteTextColor: "FFFFFF"}
	ds.Routes["Green-E"] = gtfs.Route{RouteID: "Green-E", AgencyID: "1", RouteShortName: "Green-E", RouteLongName: "Green Line E", RouteType: 0, RouteColor: "00843D", RouteTextColor: "FFFFFF"}
	ds.Routes["Mattapan"] = gtfs.Route{RouteID: "Mattapan", AgencyID: "1", RouteShortName: "Mattapan", RouteLongName: "Mattapan High Speed Line", RouteType: 0, RouteColor: "DA291C", RouteTextColor: "FFFFFF"}

	// BRT (route_type = 3, Silver Line)
	ds.Routes["SL1"] = gtfs.Route{RouteID: "SL1", AgencyID: "1", RouteShortName: "SL1", RouteLongName: "Silver Line 1 (Logan Airport)", RouteType: 3, RouteColor: "7C878E", RouteTextColor: "FFFFFF"}
	ds.Routes["SL2"] = gtfs.Route{RouteID: "SL2", AgencyID: "1", RouteShortName: "SL2", RouteLongName: "Silver Line 2 (Design Center)", RouteType: 3, RouteColor: "7C878E", RouteTextColor: "FFFFFF"}

	// Maritime Ferry (route_type = 4)
	ds.Routes["Boat-F4"] = gtfs.Route{RouteID: "Boat-F4", AgencyID: "1", RouteShortName: "F4", RouteLongName: "Charlestown Ferry", RouteType: 4, RouteColor: "00A3E0", RouteTextColor: "FFFFFF"}
	ds.Routes["Boat-F1"] = gtfs.Route{RouteID: "Boat-F1", AgencyID: "1", RouteShortName: "F1", RouteLongName: "Hingham Ferry", RouteType: 4, RouteColor: "00A3E0", RouteTextColor: "FFFFFF"}

	// Stops & Parent Hubs
	// Park Street Hub
	ds.Stops["place-pktrm"] = gtfs.Stop{StopID: "place-pktrm", StopName: "Park Street", StopLat: 42.356395, StopLon: -71.062424, LocationType: 1}
	ds.Stops["70075"] = gtfs.Stop{StopID: "70075", StopName: "Park Street - Red Line Northbound", StopLat: 42.356395, StopLon: -71.062424, LocationType: 0, ParentStation: "place-pktrm", PlatformCode: "Northbound"}
	ds.Stops["70076"] = gtfs.Stop{StopID: "70076", StopName: "Park Street - Red Line Southbound", StopLat: 42.356395, StopLon: -71.062424, LocationType: 0, ParentStation: "place-pktrm", PlatformCode: "Southbound"}
	ds.Stops["70200"] = gtfs.Stop{StopID: "70200", StopName: "Park Street - Green Line Westbound", StopLat: 42.356395, StopLon: -71.062424, LocationType: 0, ParentStation: "place-pktrm", PlatformCode: "Westbound"}
	ds.Stops["70201"] = gtfs.Stop{StopID: "70201", StopName: "Park Street - Green Line Eastbound", StopLat: 42.356395, StopLon: -71.062424, LocationType: 0, ParentStation: "place-pktrm", PlatformCode: "Eastbound"}

	// Downtown Crossing Hub
	ds.Stops["place-dwnrn"] = gtfs.Stop{StopID: "place-dwnrn", StopName: "Downtown Crossing", StopLat: 42.355518, StopLon: -71.060225, LocationType: 1}
	ds.Stops["70077"] = gtfs.Stop{StopID: "70077", StopName: "Downtown Crossing - Red Line Northbound", StopLat: 42.355518, StopLon: -71.060225, LocationType: 0, ParentStation: "place-dwnrn", PlatformCode: "Northbound"}
	ds.Stops["70016"] = gtfs.Stop{StopID: "70016", StopName: "Downtown Crossing - Orange Line Northbound", StopLat: 42.355518, StopLon: -71.060225, LocationType: 0, ParentStation: "place-dwnrn", PlatformCode: "Northbound"}

	// Government Center Hub
	ds.Stops["place-gover"] = gtfs.Stop{StopID: "place-gover", StopName: "Government Center", StopLat: 42.359705, StopLon: -71.059215, LocationType: 1}
	ds.Stops["70038"] = gtfs.Stop{StopID: "70038", StopName: "Government Center - Blue Line", StopLat: 42.359705, StopLon: -71.059215, LocationType: 0, ParentStation: "place-gover"}
	ds.Stops["70202"] = gtfs.Stop{StopID: "70202", StopName: "Government Center - Green Line", StopLat: 42.359705, StopLon: -71.059215, LocationType: 0, ParentStation: "place-gover"}

	// Boylston & Copley Green Line Stations
	ds.Stops["place-boyls"] = gtfs.Stop{StopID: "place-boyls", StopName: "Boylston", StopLat: 42.353020, StopLon: -71.064590, LocationType: 1}
	ds.Stops["70158"] = gtfs.Stop{StopID: "70158", StopName: "Boylston - Inbound", StopLat: 42.353020, StopLon: -71.064590, LocationType: 0, ParentStation: "place-boyls"}
	ds.Stops["place-coecl"] = gtfs.Stop{StopID: "place-coecl", StopName: "Copley", StopLat: 42.349974, StopLon: -71.077447, LocationType: 1}
	ds.Stops["70154"] = gtfs.Stop{StopID: "70154", StopName: "Copley - Inbound", StopLat: 42.349974, StopLon: -71.077447, LocationType: 0, ParentStation: "place-coecl"}

	// South Station & Seaport Ferry Piers
	ds.Stops["place-sstat"] = gtfs.Stop{StopID: "place-sstat", StopName: "South Station", StopLat: 42.352271, StopLon: -71.055242, LocationType: 1}
	ds.Stops["70080"] = gtfs.Stop{StopID: "70080", StopName: "South Station - Red Line", StopLat: 42.352271, StopLon: -71.055242, LocationType: 0, ParentStation: "place-sstat"}
	ds.Stops["74614"] = gtfs.Stop{StopID: "74614", StopName: "South Station - Silver Line Busway", StopLat: 42.352271, StopLon: -71.055242, LocationType: 0, ParentStation: "place-sstat"}

	ds.Stops["place-lngwh"] = gtfs.Stop{StopID: "place-lngwh", StopName: "Long Wharf (North)", StopLat: 42.360150, StopLon: -71.049880, LocationType: 1}
	ds.Stops["Boat-Long-Charlestown"] = gtfs.Stop{StopID: "Boat-Long-Charlestown", StopName: "Long Wharf Pier 4", StopLat: 42.360150, StopLon: -71.049880, LocationType: 0, ParentStation: "place-lngwh"}
	ds.Stops["place-cnavy"] = gtfs.Stop{StopID: "place-cnavy", StopName: "Charlestown Navy Yard Pier 6", StopLat: 42.373560, StopLon: -71.050370, LocationType: 1}
	ds.Stops["Boat-Charlestown"] = gtfs.Stop{StopID: "Boat-Charlestown", StopName: "Charlestown Navy Yard", StopLat: 42.373560, StopLon: -71.050370, LocationType: 0, ParentStation: "place-cnavy"}

	// Calendars
	ds.Calendars["WEEKDAY"] = gtfs.Calendar{
		ServiceID: "WEEKDAY",
		Monday:    true,
		Tuesday:   true,
		Wednesday: true,
		Thursday:  true,
		Friday:    true,
		Saturday:  false,
		Sunday:    false,
		StartDate: "20260601",
		EndDate:   "20260901",
	}

	// Trips & Shapes
	// Red Line Trip
	ds.Trips["trip_red_001"] = gtfs.Trip{TripID: "trip_red_001", RouteID: "Red", ServiceID: "WEEKDAY", TripHeadsign: "Alewife", DirectionID: 0, ShapeID: "shape_red"}
	ds.StopTimes["trip_red_001"] = []gtfs.StopTime{
		{TripID: "trip_red_001", StopID: "70080", StopSequence: 1, ArrivalTimeSec: 28800, DepartureTimeSec: 28800}, // 08:00 South Station
		{TripID: "trip_red_001", StopID: "70077", StopSequence: 2, ArrivalTimeSec: 28920, DepartureTimeSec: 28920}, // 08:02 Downtown Crossing
		{TripID: "trip_red_001", StopID: "70075", StopSequence: 3, ArrivalTimeSec: 29040, DepartureTimeSec: 29040}, // 08:04 Park Street
	}

	// Green Line B & C Trips (Frequency-based with shared Tremont Street tunnel segment)
	ds.Trips["trip_green_b_001"] = gtfs.Trip{TripID: "trip_green_b_001", RouteID: "Green-B", ServiceID: "WEEKDAY", TripHeadsign: "Government Center", DirectionID: 0, ShapeID: "shape_green_b"}
	ds.StopTimes["trip_green_b_001"] = []gtfs.StopTime{
		{TripID: "trip_green_b_001", StopID: "70154", StopSequence: 1, ArrivalTimeSec: 28800, DepartureTimeSec: 28800}, // 08:00 Copley
		{TripID: "trip_green_b_001", StopID: "70158", StopSequence: 2, ArrivalTimeSec: 28920, DepartureTimeSec: 28920}, // 08:02 Boylston
		{TripID: "trip_green_b_001", StopID: "70200", StopSequence: 3, ArrivalTimeSec: 29040, DepartureTimeSec: 29040}, // 08:04 Park St
		{TripID: "trip_green_b_001", StopID: "70202", StopSequence: 4, ArrivalTimeSec: 29160, DepartureTimeSec: 29160}, // 08:06 Gov Center
	}
	// Frequencies expansion: 6 minute headways from 06:00 to 22:00
	ds.Frequencies["trip_green_b_001"] = []gtfs.Frequency{
		{TripID: "trip_green_b_001", StartTimeSec: 21600, EndTimeSec: 79200, HeadwaySecs: 360, ExactTimes: 0},
	}

	ds.Trips["trip_green_c_001"] = gtfs.Trip{TripID: "trip_green_c_001", RouteID: "Green-C", ServiceID: "WEEKDAY", TripHeadsign: "Government Center", DirectionID: 0, ShapeID: "shape_green_c"}
	ds.StopTimes["trip_green_c_001"] = []gtfs.StopTime{
		{TripID: "trip_green_c_001", StopID: "70154", StopSequence: 1, ArrivalTimeSec: 28860, DepartureTimeSec: 28860}, // Copley
		{TripID: "trip_green_c_001", StopID: "70158", StopSequence: 2, ArrivalTimeSec: 28980, DepartureTimeSec: 28980}, // Boylston
		{TripID: "trip_green_c_001", StopID: "70200", StopSequence: 3, ArrivalTimeSec: 29100, DepartureTimeSec: 29100}, // Park St
		{TripID: "trip_green_c_001", StopID: "70202", StopSequence: 4, ArrivalTimeSec: 29220, DepartureTimeSec: 29220}, // Gov Center
	}
	ds.Frequencies["trip_green_c_001"] = []gtfs.Frequency{
		{TripID: "trip_green_c_001", StartTimeSec: 21600, EndTimeSec: 79200, HeadwaySecs: 420, ExactTimes: 0},
	}

	// Silver Line BRT Trip
	ds.Trips["trip_sl1_001"] = gtfs.Trip{TripID: "trip_sl1_001", RouteID: "SL1", ServiceID: "WEEKDAY", TripHeadsign: "Logan Airport", DirectionID: 0, ShapeID: "shape_sl1"}
	ds.StopTimes["trip_sl1_001"] = []gtfs.StopTime{
		{TripID: "trip_sl1_001", StopID: "74614", StopSequence: 1, ArrivalTimeSec: 30000, DepartureTimeSec: 30000},
	}

	// Ferry Trip (Charlestown Ferry)
	ds.Trips["trip_f4_001"] = gtfs.Trip{TripID: "trip_f4_001", RouteID: "Boat-F4", ServiceID: "WEEKDAY", TripHeadsign: "Charlestown Navy Yard", DirectionID: 0, ShapeID: "shape_f4"}
	ds.StopTimes["trip_f4_001"] = []gtfs.StopTime{
		{TripID: "trip_f4_001", StopID: "Boat-Long-Charlestown", StopSequence: 1, ArrivalTimeSec: 30000, DepartureTimeSec: 30000},
		{TripID: "trip_f4_001", StopID: "Boat-Charlestown", StopSequence: 2, ArrivalTimeSec: 30900, DepartureTimeSec: 30900},
	}

	// Shapes:
	// Red line shape: South Station -> DTX -> Park St -> Longfellow bridge
	ds.Shapes["shape_red"] = []gtfs.ShapePoint{
		{ShapeID: "shape_red", ShapePtLat: 42.352271, ShapePtLon: -71.055242, ShapePtSequence: 1},
		{ShapeID: "shape_red", ShapePtLat: 42.355518, ShapePtLon: -71.060225, ShapePtSequence: 2},
		{ShapeID: "shape_red", ShapePtLat: 42.356395, ShapePtLon: -71.062424, ShapePtSequence: 3},
		{ShapeID: "shape_red", ShapePtLat: 42.361500, ShapePtLon: -71.076000, ShapePtSequence: 4}, // Longfellow Bridge span
	}

	// Shared Tremont trunk between Copley, Boylston, Park St, Gov Center
	tremontJunctionBoylston := gtfs.ShapePoint{ShapeID: "shared", ShapePtLat: 42.353020, ShapePtLon: -71.064590, ShapePtSequence: 2}
	tremontJunctionPark := gtfs.ShapePoint{ShapeID: "shared", ShapePtLat: 42.356395, ShapePtLon: -71.062424, ShapePtSequence: 3}
	tremontJunctionGov := gtfs.ShapePoint{ShapeID: "shared", ShapePtLat: 42.359705, ShapePtLon: -71.059215, ShapePtSequence: 4}

	ds.Shapes["shape_green_b"] = []gtfs.ShapePoint{
		{ShapeID: "shape_green_b", ShapePtLat: 42.349974, ShapePtLon: -71.077447, ShapePtSequence: 1}, // Copley
		tremontJunctionBoylston,
		tremontJunctionPark,
		tremontJunctionGov,
	}

	ds.Shapes["shape_green_c"] = []gtfs.ShapePoint{
		{ShapeID: "shape_green_c", ShapePtLat: 42.349974, ShapePtLon: -71.077447, ShapePtSequence: 1}, // Copley
		tremontJunctionBoylston,
		tremontJunctionPark,
		tremontJunctionGov,
	}

	ds.Shapes["shape_sl1"] = []gtfs.ShapePoint{
		{ShapeID: "shape_sl1", ShapePtLat: 42.352271, ShapePtLon: -71.055242, ShapePtSequence: 1},
		{ShapeID: "shape_sl1", ShapePtLat: 42.365000, ShapePtLon: -71.018000, ShapePtSequence: 2}, // Logan Airport
	}

	ds.Shapes["shape_f4"] = []gtfs.ShapePoint{
		{ShapeID: "shape_f4", ShapePtLat: 42.360150, ShapePtLon: -71.049880, ShapePtSequence: 1},
		{ShapeID: "shape_f4", ShapePtLat: 42.367000, ShapePtLon: -71.050000, ShapePtSequence: 2},
		{ShapeID: "shape_f4", ShapePtLat: 42.373560, ShapePtLon: -71.050370, ShapePtSequence: 3},
	}

	// 2. Generate Scheduled Patterns (with frequency expansion verification)
	patterns := gtfs.CompactDataset(ds)
	if len(patterns) == 0 {
		t.Fatalf("Expected compacted patterns from multi-modal dataset, got 0")
	}

	// Verify Green Line frequency expansion produced multiple hourly patterns
	greenPatternsFound := 0
	for _, p := range patterns {
		if strings.HasPrefix(p.RouteID, "Green") {
			greenPatternsFound++
		}
	}
	if greenPatternsFound < 10 {
		t.Errorf("Expected at least 10 Green Line hourly pattern rows from frequency expansion, got %d", greenPatternsFound)
	}

	// 3. Generate Stop Resolution Closure (Rules 1-4)
	resolutions := gtfs.BuildStopResolutionClosure(ds.Stops)
	if len(resolutions) == 0 {
		t.Fatalf("Expected stop_resolution entries, got 0")
	}

	// Verify Park Street parent maps to all child platforms
	parkStChildren := 0
	for _, r := range resolutions {
		if r.ParentStopID == "place-pktrm" {
			parkStChildren++
		}
	}
	// Park Street has 4 platforms + self = 5 entries
	if parkStChildren != 5 {
		t.Errorf("Expected 5 stop_resolution entries for Park Street, got %d", parkStChildren)
	}

	// 4. Generate Normalized transit-lines.geojson via Arc-Topology Simplification
	fc, rawGeoJSON, err := gtfs.GenerateTransitLinesGeoJSON(ds)
	if err != nil {
		t.Fatalf("GenerateTransitLinesGeoJSON failed: %v", err)
	}

	if len(fc.Features) == 0 {
		t.Fatalf("Expected GeoJSON features for Boston lines, got 0")
	}

	// Verify multi-modal features exist in GeoJSON
	routeFeatureMap := make(map[string]gtfs.GeoJSONRouteProperties)
	for _, feat := range fc.Features {
		routeFeatureMap[feat.Properties.RouteID] = feat.Properties
	}

	// Subway Red
	if redProp, ok := routeFeatureMap["Red"]; !ok {
		t.Errorf("Red Line missing from GeoJSON")
	} else {
		if redProp.ColorHex != "#DA291C" {
			t.Errorf("Expected Red Line color #DA291C, got %s", redProp.ColorHex)
		}
		if redProp.ModalClass != gtfs.ModalClassSubway {
			t.Errorf("Expected Red Line modal class 0 (Subway), got %d", redProp.ModalClass)
		}
	}

	// Light Rail Green-B
	if greenProp, ok := routeFeatureMap["Green-B"]; !ok {
		t.Errorf("Green-B missing from GeoJSON")
	} else {
		if greenProp.ColorHex != "#00843D" {
			t.Errorf("Expected Green Line color #00843D, got %s", greenProp.ColorHex)
		}
		if greenProp.ModalClass != gtfs.ModalClassLRT {
			t.Errorf("Expected Green Line modal class 1 (LRT), got %d", greenProp.ModalClass)
		}
	}

	// Ferry Boat-F4
	if ferryProp, ok := routeFeatureMap["Boat-F4"]; !ok {
		t.Errorf("Charlestown Ferry missing from GeoJSON")
	} else {
		if ferryProp.ColorHex != "#00A3E0" {
			t.Errorf("Expected Ferry color #00A3E0, got %s", ferryProp.ColorHex)
		}
		if ferryProp.ModalClass != gtfs.ModalClassFerry {
			t.Errorf("Expected Ferry modal class 3 (Ferry), got %d", ferryProp.ModalClass)
		}
	}

	// BRT Silver Line
	if slProp, ok := routeFeatureMap["SL1"]; !ok {
		t.Errorf("Silver Line SL1 missing from GeoJSON")
	} else {
		if slProp.ColorHex != "#7C878E" {
			t.Errorf("Expected Silver Line color #7C878E, got %s", slProp.ColorHex)
		}
		if slProp.ModalClass != gtfs.ModalClassBus {
			t.Errorf("Expected Silver Line modal class 2 (Bus), got %d", slProp.ModalClass)
		}
	}

	// 5. Populate SQLite transit.sqlite Database & Pre-compile Optimizer Stats
	dbPath := filepath.Join(tempDir, "transit.sqlite")
	db, err := builder.InitTransitDB(dbPath)
	if err != nil {
		t.Fatalf("InitTransitDB failed: %v", err)
	}

	stopRoutes := map[string][]string{
		"70075": {"Red"},
		"70200": {"Green-B", "Green-C"},
	}

	if err := builder.BulkInsertRoutes(db, ds.Routes); err != nil {
		t.Fatalf("BulkInsertRoutes failed: %v", err)
	}
	if err := builder.BulkInsertStops(db, ds.Stops, stopRoutes); err != nil {
		t.Fatalf("BulkInsertStops failed: %v", err)
	}
	if err := builder.BulkInsertStopResolution(db, resolutions); err != nil {
		t.Fatalf("BulkInsertStopResolution failed: %v", err)
	}
	if err := builder.BulkInsertPatterns(db, patterns); err != nil {
		t.Fatalf("BulkInsertPatterns failed: %v", err)
	}

	// Optimize and embed sqlite_stat1
	if err := builder.OptimizeDatabase(db); err != nil {
		t.Fatalf("OptimizeDatabase failed: %v", err)
	}
	db.Close()

	// 6. Save GeoJSON and Config
	geojsonPath := filepath.Join(tempDir, "transit-lines.geojson")
	if err := os.WriteFile(geojsonPath, rawGeoJSON, 0644); err != nil {
		t.Fatalf("Failed to write geojson: %v", err)
	}

	// Load official Boston config from repository observer/config/bos_config.json
	repoConfigPath := filepath.Join("..", "..", "config", "bos_config.json")
	var bostonConfig *CityConfig
	if _, err := os.Stat(repoConfigPath); err == nil {
		bostonConfig, err = LoadCityConfig(repoConfigPath)
		if err != nil {
			t.Fatalf("Failed to load repo bos_config.json: %v", err)
		}
	} else {
		// Fallback to synthetic config if relative path differs
		bostonConfig = &CityConfig{
			Version:     1,
			Slug:        "bos",
			DisplayName: "Boston",
			Region:      "Massachusetts, USA",
			Bounds: GeoBounds{
				MinLatitude:  42.20,
				MaxLatitude:  42.50,
				MinLongitude: -71.25,
				MaxLongitude: -70.90,
			},
			Center: MapCenter{
				Latitude:    42.3601,
				Longitude:   -71.0589,
				DefaultZoom: 13.0,
			},
			Transit: TransitConfig{
				AgencyName:   "Massachusetts Bay Transportation Authority",
				Attributions: []string{"MBTA Subway, Bus & Commuter Rail", "MassDOT Ferry Operations"},
			},
		}
	}

	configPath := filepath.Join(tempDir, "city_config.json")
	if err := SaveCityConfig(bostonConfig, configPath); err != nil {
		t.Fatalf("Failed to save city config: %v", err)
	}

	// 7. Package into city-bos.pack.zst
	packPath := filepath.Join(tempDir, "city-bos.pack.zst")
	manifestEntry, err := CreateCityPack(configPath, dbPath, geojsonPath, packPath)
	if err != nil {
		t.Fatalf("CreateCityPack failed: %v", err)
	}

	if manifestEntry.Slug != "bos" {
		t.Errorf("Expected slug 'bos', got '%s'", manifestEntry.Slug)
	}
	if manifestEntry.CompressedSizeBytes <= 0 || manifestEntry.UncompressedSizeBytes <= 0 {
		t.Errorf("Invalid pack sizes: compressed=%d, uncompressed=%d", manifestEntry.CompressedSizeBytes, manifestEntry.UncompressedSizeBytes)
	}
	if len(manifestEntry.SHA256) != 64 {
		t.Errorf("Expected 64-char SHA256 hex digest, got %s", manifestEntry.SHA256)
	}

	// 8. Verify Pack Structure
	if err := VerifyCityPack(packPath); err != nil {
		t.Fatalf("VerifyCityPack failed: %v", err)
	}

	// 9. Extract and Inspect Contents
	extractDir := filepath.Join(tempDir, "extracted_boston")
	if err := ExtractCityPack(packPath, extractDir); err != nil {
		t.Fatalf("ExtractCityPack failed: %v", err)
	}

	// Inspect extracted SQLite DB
	extractedDBPath := filepath.Join(extractDir, "transit.sqlite")
	extractedDB, err := sql.Open("sqlite3", extractedDBPath)
	if err != nil {
		t.Fatalf("Failed to open extracted DB: %v", err)
	}
	defer extractedDB.Close()

	var stopCount, resCount, patCount, statCount int
	_ = extractedDB.QueryRow("SELECT COUNT(*) FROM stops").Scan(&stopCount)
	_ = extractedDB.QueryRow("SELECT COUNT(*) FROM stop_resolution").Scan(&resCount)
	_ = extractedDB.QueryRow("SELECT COUNT(*) FROM scheduled_hourly_patterns").Scan(&patCount)
	_ = extractedDB.QueryRow("SELECT COUNT(*) FROM sqlite_stat1").Scan(&statCount)

	if stopCount == 0 || resCount == 0 || patCount == 0 || statCount == 0 {
		t.Errorf("Extracted DB missing rows: stops=%d, res=%d, patterns=%d, stats=%d", stopCount, resCount, patCount, statCount)
	}

	// Inspect extracted GeoJSON
	extractedGeoJSONPath := filepath.Join(extractDir, "transit-lines.geojson")
	geoBytes, err := os.ReadFile(extractedGeoJSONPath)
	if err != nil {
		t.Fatalf("Failed to read extracted geojson: %v", err)
	}

	var extractedFC gtfs.GeoJSONFeatureCollection
	if err := json.Unmarshal(geoBytes, &extractedFC); err != nil {
		t.Fatalf("Failed to unmarshal extracted GeoJSON: %v", err)
	}
	if len(extractedFC.Features) != len(fc.Features) {
		t.Errorf("Feature count mismatch: expected %d, got %d", len(fc.Features), len(extractedFC.Features))
	}
}
