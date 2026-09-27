import { useState } from 'preact/hooks';

export function SearchBar() {
  const [isFocused, setIsFocused] = useState(false);

  return (
    <section class="search-section" aria-label="Transit search">
      <div class={`search-bar-container ${isFocused ? 'search-bar-focused' : ''}`}>
        <div class="search-icon-slot" aria-hidden="true">
          <svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" stroke-width="2">
            <circle cx="11" cy="11" r="7" />
            <line x1="16.5" y1="16.5" x2="21" y2="21" stroke-linecap="round" />
          </svg>
        </div>
        <input
          type="text"
          class="search-input"
          placeholder="Search stations, lines, or destinations..."
          aria-label="Search stations, lines, or destinations"
          onFocus={() => setIsFocused(true)}
          onBlur={() => setIsFocused(false)}
        />
        <div class="search-badge-slot" aria-hidden="true">
          <span class="offline-ready-badge">Offline Shell</span>
        </div>
      </div>

      {isFocused && (
        <div class="search-notice-banner" role="status">
          <div class="notice-icon">ℹ</div>
          <div class="notice-content">
            <div class="notice-title">Offline Routing Engine Standby</div>
            <div class="notice-description">
              Origin-destination transit pathfinding (WASM RAPTOR) activates once the 28 MB NYC city pack is installed in Milestone 2.
            </div>
          </div>
        </div>
      )}

      <div class="transit-chips-row" aria-label="Subway Lines">
        <span class="subway-chip line-red" title="Broadway-Seventh Avenue Line">1 2 3</span>
        <span class="subway-chip line-green" title="Lexington Avenue Line">4 5 6</span>
        <span class="subway-chip line-purple" title="Flushing Line">7</span>
        <span class="subway-chip line-blue" title="Eighth Avenue Line">A C E</span>
        <span class="subway-chip line-orange" title="Sixth Avenue Line">B D F M</span>
        <span class="subway-chip line-yellow" title="Broadway Line">N Q R W</span>
        <span class="subway-chip line-grey" title="Canarsie Line">L</span>
        <span class="subway-chip line-lime" title="Crosstown Line">G</span>
      </div>
    </section>
  );
}
