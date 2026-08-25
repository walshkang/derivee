package fetcher

import (
	"context"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"
	"time"
)

func TestDeltaChecker_ThreeTierDeltaDetection(t *testing.T) {
	tempDir := t.TempDir()
	stateFile := filepath.Join(tempDir, "delta_state.json")

	var currentETag string = "\"v1-etag\""
	var currentLastMod string = "Wed, 25 Aug 2026 12:00:00 GMT"
	var currentPayload string = "GTFS-ZIP-CONTENT-VERSION-1"
	var returnStatus int = http.StatusOK

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		// Check conditional headers
		if r.Header.Get("If-None-Match") == currentETag {
			w.WriteHeader(http.StatusNotModified)
			return
		}
		if returnStatus == http.StatusNotModified {
			w.WriteHeader(http.StatusNotModified)
			return
		}

		w.Header().Set("ETag", currentETag)
		w.Header().Set("Last-Modified", currentLastMod)
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte(currentPayload))
	}))
	defer server.Close()

	dc, err := NewDeltaChecker(stateFile, server.Client())
	if err != nil {
		t.Fatalf("NewDeltaChecker failed: %v", err)
	}

	ctx := context.Background()

	// 1. First fetch: Cold cache -> Expect modified = true
	data, modified, err := dc.CheckAndFetch(ctx, server.URL)
	if err != nil {
		t.Fatalf("First fetch failed: %v", err)
	}
	if !modified {
		t.Errorf("Expected modified=true on first fetch")
	}
	if string(data) != currentPayload {
		t.Errorf("Expected payload %q, got %q", currentPayload, string(data))
	}

	feedState, exists := dc.GetFeedState(server.URL)
	if !exists {
		t.Fatalf("Expected feed state to exist")
	}
	if feedState.ETag != currentETag {
		t.Errorf("Expected ETag %s, got %s", currentETag, feedState.ETag)
	}

	// 2. Second fetch: Server returns 304 Not Modified -> Expect modified = false, data = nil
	data, modified, err = dc.CheckAndFetch(ctx, server.URL)
	if err != nil {
		t.Fatalf("Second fetch failed: %v", err)
	}
	if modified {
		t.Errorf("Expected modified=false on 304 response")
	}
	if data != nil {
		t.Errorf("Expected nil data on 304, got %v", data)
	}

	// 3. Third fetch: Server returns 200 OK without ETag but identical payload -> Tier 2 hash match
	currentETag = "" // Drop ETag so server returns 200
	data, modified, err = dc.CheckAndFetch(ctx, server.URL)
	if err != nil {
		t.Fatalf("Third fetch failed: %v", err)
	}
	if modified {
		t.Errorf("Expected modified=false on identical payload hash (Tier 2)")
	}
	if string(data) != currentPayload {
		t.Errorf("Expected payload %q, got %q", currentPayload, string(data))
	}

	// 4. Fourth fetch: Server returns 200 OK with new payload -> Tier 3 update detected
	currentPayload = "GTFS-ZIP-CONTENT-VERSION-2-UPDATED"
	currentETag = "\"v2-etag\""
	data, modified, err = dc.CheckAndFetch(ctx, server.URL)
	if err != nil {
		t.Fatalf("Fourth fetch failed: %v", err)
	}
	if !modified {
		t.Errorf("Expected modified=true on changed payload")
	}
	if string(data) != currentPayload {
		t.Errorf("Expected new payload %q, got %q", currentPayload, string(data))
	}

	// 5. Test State Reload from Disk
	dc2, err := NewDeltaChecker(stateFile, server.Client())
	if err != nil {
		t.Fatalf("NewDeltaChecker reload failed: %v", err)
	}
	reloadedState, exists := dc2.GetFeedState(server.URL)
	if !exists {
		t.Fatalf("Expected reloaded feed state to exist")
	}
	if reloadedState.ETag != currentETag {
		t.Errorf("Expected reloaded ETag %s, got %s", currentETag, reloadedState.ETag)
	}
}

func TestDeltaChecker_LocalFileCheck(t *testing.T) {
	tempDir := t.TempDir()
	stateFile := filepath.Join(tempDir, "delta_state.json")
	feedFile := filepath.Join(tempDir, "local_gtfs.zip")

	if err := os.WriteFile(feedFile, []byte("initial local content"), 0644); err != nil {
		t.Fatalf("Failed to write initial feed file: %v", err)
	}

	dc, err := NewDeltaChecker(stateFile, nil)
	if err != nil {
		t.Fatalf("NewDeltaChecker failed: %v", err)
	}

	ctx := context.Background()

	// 1. Cold check
	data, modified, err := dc.CheckAndFetch(ctx, feedFile)
	if err != nil {
		t.Fatalf("Check failed: %v", err)
	}
	if !modified || string(data) != "initial local content" {
		t.Errorf("Expected modified=true on first local check")
	}

	// 2. Unchanged check
	_, modified, err = dc.CheckAndFetch(ctx, feedFile)
	if err != nil {
		t.Fatalf("Check failed: %v", err)
	}
	if modified {
		t.Errorf("Expected modified=false for unchanged local file")
	}

	// 3. Mutated check
	time.Sleep(10 * time.Millisecond)
	if err := os.WriteFile(feedFile, []byte("mutated local content"), 0644); err != nil {
		t.Fatalf("Failed to update feed file: %v", err)
	}

	data, modified, err = dc.CheckAndFetch(ctx, feedFile)
	if err != nil {
		t.Fatalf("Check failed: %v", err)
	}
	if !modified {
		t.Errorf("Expected modified=true for mutated local file")
	}
	if string(data) != "mutated local content" {
		t.Errorf("Expected mutated content, got %s", string(data))
	}
}

func TestDeltaChecker_HttpErrorHandling(t *testing.T) {
	tempDir := t.TempDir()
	stateFile := filepath.Join(tempDir, "delta_state.json")

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusInternalServerError)
	}))
	defer server.Close()

	dc, err := NewDeltaChecker(stateFile, server.Client())
	if err != nil {
		t.Fatalf("NewDeltaChecker failed: %v", err)
	}

	_, _, err = dc.CheckAndFetch(context.Background(), server.URL)
	if err == nil {
		t.Errorf("Expected error on HTTP 500 status")
	}
}
