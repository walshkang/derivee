import { useEffect, useState } from 'preact/hooks';

export function MapPlaceholder() {
  const [opfsSupported, setOpfsSupported] = useState<boolean | null>(null);

  useEffect(() => {
    if (typeof navigator !== 'undefined' && 'storage' in navigator && typeof navigator.storage?.getDirectory === 'function') {
      setOpfsSupported(true);
    } else {
      setOpfsSupported(false);
    }
  }, []);

  return (
    <main class="map-container-placeholder" aria-label="Map viewport placeholder">
      {/* Fog-of-war & Radar Cartography Background */}
      <div class="fog-canvas-overlay" aria-hidden="true">
        <div class="radar-circle circle-1" />
        <div class="radar-circle circle-2" />
        <div class="radar-circle circle-3" />
        <div class="radar-sweep" />
        <div class="grid-lines" />
        
        {/* Subtle NYC Geo-coordinates */}
        <div class="geo-coord coord-nw">40.8000° N, 73.9600° W</div>
        <div class="geo-coord coord-ne">40.8000° N, 73.9100° W</div>
        <div class="geo-coord coord-sw">40.7000° N, 74.0200° W</div>
        <div class="geo-coord coord-se">40.7000° N, 73.9400° W</div>
      </div>

      {/* Atmospheric Center Card */}
      <div class="map-empty-state-card">
        <div class="empty-state-beacon" aria-hidden="true">
          <div class="beacon-pulse" />
          <svg viewBox="0 0 48 48" width="32" height="32" fill="none">
            <polygon points="24,6 40,14 40,34 24,42 8,34 8,14" stroke="#0284c7" stroke-width="2" />
            <circle cx="24" cy="24" r="8" stroke="#38bdf8" stroke-width="2" stroke-dasharray="3 3" />
            <circle cx="24" cy="24" r="3" fill="#f59e0b" />
          </svg>
        </div>

        <div class="empty-state-badge">
          <span class="badge-dot" />
          <span>Pack Not Installed</span>
        </div>

        <h2 class="empty-state-title">Map Standby</h2>
        <p class="empty-state-desc">
          Offline vector map and RAPTOR routing graph load after city pack installation.
        </p>

        <div class="empty-state-metadata">
          <div class="metadata-row">
            <span class="metadata-label">Engine</span>
            <span class="metadata-val">C++ RAPTOR (WASM)</span>
          </div>
          <div class="metadata-row">
            <span class="metadata-label">Map Engine</span>
            <span class="metadata-val">PMTiles + MapLibre</span>
          </div>
          <div class="metadata-row">
            <span class="metadata-label">Data Pack</span>
            <span class="metadata-val">city-nyc.pack.zst (28 MB)</span>
          </div>
          <div class="metadata-row">
            <span class="metadata-label">OPFS Storage</span>
            <span class="metadata-val">
              {opfsSupported === null ? 'Detecting...' : opfsSupported ? 'Supported' : 'Unavailable'}
            </span>
          </div>
        </div>
      </div>
    </main>
  );
}
