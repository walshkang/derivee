package fetcher

import (
	"archive/zip"
	"bytes"
	"testing"
)

func TestCleanStopName(t *testing.T) {
	tests := []struct {
		name     string
		input    string
		expected string
	}{
		{
			name:     "Kent Av & N 6 St - compass prefix must not become NB",
			input:    "KENT AV/N 6 ST",
			expected: "Kent Av & N 6 St",
		},
		{
			name:     "Kent Av & S 6 St - compass prefix must not become SB",
			input:    "KENT AV/S 6 ST",
			expected: "Kent Av & S 6 St",
		},
		{
			name:     "Kent Av with directional token NB before street - must isolate as qualifier",
			input:    "KENT AV/NB 6 ST",
			expected: "Kent Av & 6 St (NB)",
		},
		{
			name:     "Kent Av with trailing NB token",
			input:    "KENT AV/6 ST NB",
			expected: "Kent Av & 6 St (NB)",
		},
		{
			name:     "Kent Av with parenthesized (NB) token",
			input:    "KENT AV/6 ST (NB)",
			expected: "Kent Av & 6 St (NB)",
		},
		{
			name:     "Leading NB token before street",
			input:    "NB KENT AV/6 ST",
			expected: "Kent Av & 6 St (NB)",
		},
		{
			name:     "5 Av & W 42 St - W compass prefix must not become WB",
			input:    "5 AV/W 42 ST",
			expected: "5 Av & W 42 St",
		},
		{
			name:     "1 Av & E 14 St - E compass prefix must not become EB",
			input:    "1 AV/E 14 ST",
			expected: "1 Av & E 14 St",
		},
		{
			name:     "Central Park North - full word North must not become NB",
			input:    "CENTRAL PARK NORTH/5 AV",
			expected: "Central Park North & 5 Av",
		},
		{
			name:     "Central Park West - full word West must not become WB",
			input:    "CENTRAL PARK WEST/W 72 ST",
			expected: "Central Park West & W 72 St",
		},
		{
			name:     "Varick St & N Moore St - N must not become NB",
			input:    "VARICK ST/N MOORE ST",
			expected: "Varick St & N Moore St",
		},
		{
			name:     "Vesey St & North End Av - North must not become NB",
			input:    "VESEY ST/NORTH END AV",
			expected: "Vesey St & North End Av",
		},
		{
			name:     "Willis Av & E 138 St - E must not become EB",
			input:    "WILLIS AV/E 138 ST",
			expected: "Willis Av & E 138 St",
		},
		{
			name:     "Words with NB/SB/EB/WB substrings must not trigger regex (boundary check)",
			input:    "NEWBURGH ST/OSBORN ST",
			expected: "Newburgh St & Osborn St",
		},
		{
			name:     "Webster Av and DeKalb Av - words containing eb/wb",
			input:    "WEBSTER AV/DEKALB AV",
			expected: "Webster Av & Dekalb Av",
		},
		{
			name:     "Times Sq - 42 St - non-intersection dash format preserved",
			input:    "Times Sq - 42 St",
			expected: "Times Sq - 42 St",
		},
		{
			name:     "Port Authority Bus Terminal - standard terminal name preserved",
			input:    "Port Authority Bus Terminal",
			expected: "Port Authority Bus Terminal",
		},
		{
			name:     "SBS route indicator preserved uppercase",
			input:    "14 ST SBS/1 AV",
			expected: "14 St SBS & 1 Av",
		},
		{
			name:     "Multiple slashes and extra whitespace normalized",
			input:    "  KENT AV  //   N 6 ST  ",
			expected: "Kent Av & N 6 St",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			actual := CleanStopName(tt.input)
			if actual != tt.expected {
				t.Errorf("CleanStopName(%q) = %q; want %q", tt.input, actual, tt.expected)
			}
		})
	}
}

func TestParseStopNameQualifiers(t *testing.T) {
	cleanName, qual := ParseStopName("KENT AV/NB 6 ST")
	if cleanName != "Kent Av & 6 St" {
		t.Errorf("cleanName = %q; want %q", cleanName, "Kent Av & 6 St")
	}
	if qual != "NB" {
		t.Errorf("qualifier = %q; want %q", qual, "NB")
	}

	cleanName2, qual2 := ParseStopName("KENT AV/N 6 ST")
	if cleanName2 != "Kent Av & N 6 St" {
		t.Errorf("cleanName = %q; want %q", cleanName2, "Kent Av & N 6 St")
	}
	if qual2 != "" {
		t.Errorf("qualifier = %q; want empty", qual2)
	}

	cleanName3, qual3 := ParseStopName("BROADWAY / W 231 ST SB")
	if cleanName3 != "Broadway & W 231 St" {
		t.Errorf("cleanName = %q; want %q", cleanName3, "Broadway & W 231 St")
	}
	if qual3 != "SB" {
		t.Errorf("qualifier = %q; want %q", qual3, "SB")
	}
}

func TestParseStopsToDBWithCleanStopName(t *testing.T) {
	// Construct a synthetic zip archive containing stops.txt
	stopsCSV := `stop_id,stop_name,stop_lat,stop_lon,location_type,parent_station
308667,KENT AV/N 6 ST,40.7180,-73.9620,0,
308668,KENT AV/NB 6 ST,40.7181,-73.9621,0,
308396,KENT AV/S 6 ST,40.7130,-73.9650,0,
`
	buf := new(bytes.Buffer)
	zw := zip.NewWriter(buf)
	f, err := zw.Create("stops.txt")
	if err != nil {
		t.Fatalf("failed to create stops.txt in zip: %v", err)
	}
	if _, err := f.Write([]byte(stopsCSV)); err != nil {
		t.Fatalf("failed to write stops.txt: %v", err)
	}
	if err := zw.Close(); err != nil {
		t.Fatalf("failed to close zip: %v", err)
	}

	zr, err := zip.NewReader(bytes.NewReader(buf.Bytes()), int64(buf.Len()))
	if err != nil {
		t.Fatalf("failed to open zip reader: %v", err)
	}

	var parsedStops []GTFSStop
	err = parseStopsToDB(zr.File[0], func(stops []GTFSStop) error {
		parsedStops = append(parsedStops, stops...)
		return nil
	})
	if err != nil {
		t.Fatalf("parseStopsToDB returned error: %v", err)
	}

	if len(parsedStops) != 3 {
		t.Fatalf("expected 3 stops, got %d", len(parsedStops))
	}

	if parsedStops[0].StopName != "Kent Av & N 6 St" {
		t.Errorf("stop 308667 name = %q; want %q", parsedStops[0].StopName, "Kent Av & N 6 St")
	}
	if parsedStops[1].StopName != "Kent Av & 6 St (NB)" {
		t.Errorf("stop 308668 name = %q; want %q", parsedStops[1].StopName, "Kent Av & 6 St (NB)")
	}
	if parsedStops[2].StopName != "Kent Av & S 6 St" {
		t.Errorf("stop 308396 name = %q; want %q", parsedStops[2].StopName, "Kent Av & S 6 St")
	}
}
