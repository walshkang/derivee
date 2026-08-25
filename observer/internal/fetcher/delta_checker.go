package fetcher

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"sync"
	"time"
)

// FeedState holds the cache metadata for a specific feed URL or file
type FeedState struct {
	URL          string    `json:"url"`
	ETag         string    `json:"etag,omitempty"`
	LastModified string    `json:"lastModified,omitempty"`
	ContentHash  string    `json:"contentHash"`
	LastChecked  time.Time `json:"lastChecked"`
	LastUpdated  time.Time `json:"lastUpdated"`
}

// DeltaCheckerState holds all cached feed metadata
type DeltaCheckerState struct {
	Version int                  `json:"version"`
	Feeds   map[string]FeedState `json:"feeds"`
}

// DeltaChecker manages 3-tier feed delta checking (HTTP Headers, SHA-256 hashing, 12h schedule)
type DeltaChecker struct {
	stateFilePath string
	httpClient    *http.Client
	mu            sync.RWMutex
	state         DeltaCheckerState
}

// NewDeltaChecker creates an initialized DeltaChecker with state stored at stateFilePath
func NewDeltaChecker(stateFilePath string, client *http.Client) (*DeltaChecker, error) {
	if client == nil {
		client = &http.Client{
			Timeout: 60 * time.Second,
		}
	}

	dc := &DeltaChecker{
		stateFilePath: stateFilePath,
		httpClient:    client,
		state: DeltaCheckerState{
			Version: 1,
			Feeds:   make(map[string]FeedState),
		},
	}

	if err := dc.loadState(); err != nil && !os.IsNotExist(err) {
		log.Printf("Warning: failed to load delta checker state from %s: %v", stateFilePath, err)
	}

	return dc, nil
}

func (dc *DeltaChecker) loadState() error {
	dc.mu.Lock()
	defer dc.mu.Unlock()

	data, err := os.ReadFile(dc.stateFilePath)
	if err != nil {
		return err
	}

	var state DeltaCheckerState
	if err := json.Unmarshal(data, &state); err != nil {
		return fmt.Errorf("failed to unmarshal delta state: %w", err)
	}

	if state.Feeds == nil {
		state.Feeds = make(map[string]FeedState)
	}
	dc.state = state
	return nil
}

func (dc *DeltaChecker) saveState() error {
	dc.mu.RLock()
	defer dc.mu.RUnlock()

	if dc.stateFilePath == "" {
		return nil
	}

	if err := os.MkdirAll(filepath.Dir(dc.stateFilePath), 0755); err != nil {
		return fmt.Errorf("failed to create state directory: %w", err)
	}

	data, err := json.MarshalIndent(&dc.state, "", "  ")
	if err != nil {
		return fmt.Errorf("failed to marshal delta state: %w", err)
	}

	return os.WriteFile(dc.stateFilePath, append(data, '\n'), 0644)
}

// CheckAndFetch executes 3-tier delta checking for a remote or local feed source:
// Tier 1: Conditional HTTP GET using ETag / If-Modified-Since headers.
// Tier 2: SHA-256 payload digest verification.
// Returns feed data bytes, a boolean indicating if changes were detected, and any error.
func (dc *DeltaChecker) CheckAndFetch(ctx context.Context, source string) ([]byte, bool, error) {
	now := time.Now().UTC()

	dc.mu.RLock()
	cachedState, hasCached := dc.state.Feeds[source]
	dc.mu.RUnlock()

	// Check if source is a local file
	if !isHTTPURL(source) {
		return dc.checkLocalFile(source, cachedState, hasCached, now)
	}

	// Remote HTTP(S) source: Tier 1 conditional request
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, source, nil)
	if err != nil {
		return nil, false, fmt.Errorf("failed to create HTTP request for %s: %w", source, err)
	}

	req.Header.Set("User-Agent", "Derivee-Observer-Ingestion/1.0")

	if hasCached {
		if cachedState.ETag != "" {
			req.Header.Set("If-None-Match", cachedState.ETag)
		}
		if cachedState.LastModified != "" {
			req.Header.Set("If-Modified-Since", cachedState.LastModified)
		}
	}

	resp, err := dc.httpClient.Do(req)
	if err != nil {
		return nil, false, fmt.Errorf("HTTP request failed for %s: %w", source, err)
	}
	defer resp.Body.Close()

	// Tier 1: HTTP 304 Not Modified
	if resp.StatusCode == http.StatusNotModified {
		log.Printf("[Tier 1] HTTP 304 Not Modified for feed %s (ETag: %s)", source, cachedState.ETag)
		dc.updateLastChecked(source, now)
		_ = dc.saveState()
		return nil, false, nil
	}

	if resp.StatusCode != http.StatusOK {
		return nil, false, fmt.Errorf("feed %s returned unexpected HTTP status: %d %s", source, resp.StatusCode, resp.Status)
	}

	bodyBytes, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, false, fmt.Errorf("failed to read response body for %s: %w", source, err)
	}

	// Tier 2: SHA-256 payload digest verification
	hasher := sha256.New()
	hasher.Write(bodyBytes)
	contentHash := hex.EncodeToString(hasher.Sum(nil))

	if hasCached && cachedState.ContentHash == contentHash {
		log.Printf("[Tier 2] SHA-256 hash match (%s) for feed %s - content unchanged despite HTTP 200", contentHash[:12], source)
		dc.updateHeadersAndChecked(source, resp.Header.Get("ETag"), resp.Header.Get("Last-Modified"), now)
		_ = dc.saveState()
		return bodyBytes, false, nil
	}

	// Feed is modified / newly ingested
	log.Printf("[Tier 3] Feed %s modified/new. Previous hash: %s -> New hash: %s (Size: %d bytes)",
		source, safeTruncate(cachedState.ContentHash, 12), contentHash[:12], len(bodyBytes))

	dc.mu.Lock()
	dc.state.Feeds[source] = FeedState{
		URL:          source,
		ETag:         resp.Header.Get("ETag"),
		LastModified: resp.Header.Get("Last-Modified"),
		ContentHash:  contentHash,
		LastChecked:  now,
		LastUpdated:  now,
	}
	dc.mu.Unlock()

	_ = dc.saveState()
	return bodyBytes, true, nil
}

func (dc *DeltaChecker) checkLocalFile(filePath string, cachedState FeedState, hasCached bool, now time.Time) ([]byte, bool, error) {
	data, err := os.ReadFile(filePath)
	if err != nil {
		return nil, false, fmt.Errorf("failed to read local feed file %s: %w", filePath, err)
	}

	hasher := sha256.New()
	hasher.Write(data)
	contentHash := hex.EncodeToString(hasher.Sum(nil))

	if hasCached && cachedState.ContentHash == contentHash {
		dc.updateLastChecked(filePath, now)
		_ = dc.saveState()
		return data, false, nil
	}

	dc.mu.Lock()
	dc.state.Feeds[filePath] = FeedState{
		URL:         filePath,
		ContentHash: contentHash,
		LastChecked: now,
		LastUpdated: now,
	}
	dc.mu.Unlock()

	_ = dc.saveState()
	return data, true, nil
}

func (dc *DeltaChecker) updateLastChecked(source string, checkedTime time.Time) {
	dc.mu.Lock()
	defer dc.mu.Unlock()
	if entry, exists := dc.state.Feeds[source]; exists {
		entry.LastChecked = checkedTime
		dc.state.Feeds[source] = entry
	}
}

func (dc *DeltaChecker) updateHeadersAndChecked(source, etag, lastModified string, checkedTime time.Time) {
	dc.mu.Lock()
	defer dc.mu.Unlock()
	if entry, exists := dc.state.Feeds[source]; exists {
		if etag != "" {
			entry.ETag = etag
		}
		if lastModified != "" {
			entry.LastModified = lastModified
		}
		entry.LastChecked = checkedTime
		dc.state.Feeds[source] = entry
	}
}

// GetFeedState returns the cached state for a feed
func (dc *DeltaChecker) GetFeedState(source string) (FeedState, bool) {
	dc.mu.RLock()
	defer dc.mu.RUnlock()
	entry, exists := dc.state.Feeds[source]
	return entry, exists
}

func isHTTPURL(s string) bool {
	return len(s) > 7 && (s[:7] == "http://" || (len(s) > 8 && s[:8] == "https://"))
}

func safeTruncate(s string, maxLen int) string {
	if len(s) <= maxLen {
		return s
	}
	return s[:maxLen]
}
