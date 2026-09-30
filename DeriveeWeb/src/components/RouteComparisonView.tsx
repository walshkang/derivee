/**
 * RouteComparisonView.tsx
 * Screen 4B Multimodal Route Comparison UI (design.md §12.3 / §13.2).
 *
 * Implements:
 * 1. Profile selector bar: [⚡ Fastest] [🔄 Fewest Transfers]
 * 2. Ranked itinerary cards: arrival time hero, human duration, transfer count, leg breakdown.
 * 3. Deduplication UX: identical itineraries collapse to 1 card badged with both profiles.
 * 4. Leg rendering structured cleanly so M5b can swap route ID displays for line badges.
 * 5. Complete state coverage: loading, error, empty, one_result, two_results, deduped.
 */

import type {
  StopItem,
  RoutingProfile,
  RankedItinerary,
} from '../types/routing';
import {
  describeItinerary,
} from '../utils/itineraryDisplay';
import {
  formatTransferCount,
  formatClockTime,
  formatArrivalTime,
  getRouteComparisonUIState,
} from '../utils/routeComparison';

interface RouteComparisonViewProps {
  rankedCards: RankedItinerary[];
  activeProfile: RoutingProfile;
  onSelectProfile: (profile: RoutingProfile) => void;
  stopsMap: Map<number, StopItem>;
  isRouting: boolean;
  routeError: string | null;
  hasQueried: boolean;
}

export function RouteComparisonView({
  rankedCards,
  activeProfile,
  onSelectProfile,
  stopsMap,
  isRouting,
  routeError,
  hasQueried,
}: RouteComparisonViewProps) {
  const uiState = getRouteComparisonUIState({
    isRouting,
    routeError,
    rankedCards,
    hasQueried,
  });

  if (uiState.state === 'loading') {
    return (
      <div class="route-comparison-loading">
        <span class="btn-spinner" />
        <div class="loading-text-group">
          <span class="loading-title">{uiState.userFacingTitle}</span>
          <span class="loading-subtitle">{uiState.userFacingDescription}</span>
        </div>
      </div>
    );
  }

  if (uiState.state === 'error') {
    return (
      <div class="itinerary-error-box">
        <span>⚠️ {uiState.userFacingDescription}</span>
      </div>
    );
  }

  if (uiState.state === 'empty') {
    if (!hasQueried) return null;
    return (
      <div class="route-comparison-empty">
        <span class="empty-icon">📍</span>
        <span class="empty-title">{uiState.userFacingTitle}</span>
        <span class="empty-subtitle">{uiState.userFacingDescription}</span>
      </div>
    );
  }

  return (
    <div class="route-comparison-container">
      {/* 1. Profile Selector Pill Bar (design.md §12.3 / §13.2) */}
      <div class="profile-selector-bar" role="tablist" aria-label="Route comparison profiles">
        <button
          type="button"
          role="tab"
          aria-selected={activeProfile === 'fastest'}
          class={`profile-pill ${activeProfile === 'fastest' ? 'profile-pill-active' : ''}`}
          onClick={() => onSelectProfile('fastest')}
        >
          <span class="profile-pill-icon">⚡</span>
          <span class="profile-pill-label">Fastest</span>
        </button>
        <button
          type="button"
          role="tab"
          aria-selected={activeProfile === 'fewest_transfers'}
          class={`profile-pill ${activeProfile === 'fewest_transfers' ? 'profile-pill-active' : ''}`}
          onClick={() => onSelectProfile('fewest_transfers')}
        >
          <span class="profile-pill-icon">🔄</span>
          <span class="profile-pill-label">Fewest Transfers</span>
        </button>
      </div>

      {/* 2. Ranked Itinerary Cards (design.md §12.3) */}
      <div class="itinerary-results-container">
        {rankedCards.map((card, idx) => {
          const isSelected = card.profile === activeProfile || card.isDeduped;
          return (
            <div
              key={card.id}
              class={`itinerary-ranked-card ${
                card.isDeduped ? 'ranked-card-optimal' : ''
              } ${isSelected ? 'ranked-card-selected' : ''}`}
            >
              {/* Card Header: Rank # + Badges + Arrival Hero */}
              <div class="ranked-card-header">
                <div class="ranked-badges-row">
                  <span class="rank-number-badge">#{idx + 1}</span>
                  {card.isDeduped ? (
                    <>
                      <span class="profile-badge badge-fastest">
                        <span class="badge-icon">⚡</span> Fastest
                      </span>
                      <span class="profile-badge badge-transfers">
                        <span class="badge-icon">🔄</span> Fewest Transfers
                      </span>
                      <span class="badge-optimal-pill">Best Match</span>
                    </>
                  ) : card.profile === 'fastest' ? (
                    <span class="profile-badge badge-fastest">
                      <span class="badge-icon">⚡</span> Fastest
                    </span>
                  ) : (
                    <span class="profile-badge badge-transfers">
                      <span class="badge-icon">🔄</span> Fewest Transfers
                    </span>
                  )}
                </div>

                <div class="ranked-arrival-block">
                  <span class="arrival-label">Arrive at</span>
                  <span class="arrival-time-hero">{formatArrivalTime(card.arrivalTime)}</span>
                </div>
              </div>

              {/* Glance Metrics Bar: Duration + Timetable window + Transfers */}
              <div class="ranked-glance-metrics">
                <span class="glance-duration">{card.durationMinutes} min</span>
                <span class="glance-dot">•</span>
                <span class="glance-time-range">
                  {formatClockTime(card.departureTime)} – {formatClockTime(card.arrivalTime)}
                </span>
                <span class="glance-dot">•</span>
                <span class="glance-transfers">{formatTransferCount(card.transferCount)}</span>
              </div>

              {/* Leg Breakdown */}
              <div class="itinerary-legs-list">
                {describeItinerary(card.segments, stopsMap).map((legModel, legIdx) => {
                  if (legModel.kind === 'start') {
                    return (
                      <div key={legIdx} class="itinerary-compact-row itinerary-compact-start">
                        <span class="compact-marker marker-board" />
                        <span class="itinerary-compact-text">Start at {legModel.station}</span>
                        <span class="itinerary-compact-time">
                          {formatClockTime(legModel.time)}
                        </span>
                      </div>
                    );
                  }

                  if (legModel.kind === 'arrive') {
                    return (
                      <div key={legIdx} class="itinerary-compact-row itinerary-compact-arrive">
                        <span class="compact-marker marker-exit" />
                        <span class="itinerary-compact-text">Arrive at {legModel.station}</span>
                        <span class="itinerary-compact-time">
                          {formatClockTime(legModel.time)}
                        </span>
                      </div>
                    );
                  }

                  return (
                    <div key={legIdx} class="itinerary-leg-card">
                      <div class="leg-card-header">
                        <span class="leg-index-badge">Leg {legIdx + 1}</span>
                        <span
                          class={`leg-mode-pill ${
                            legModel.isTransfer ? 'mode-pill-walk' : 'mode-pill-transit'
                          }`}
                        >
                          {legModel.isTransfer ? (
                            <>🚶 Walk / Transfer</>
                          ) : (
                            <span class="route-id-container">
                              {/* Structured for M5b route badge swap */}
                              <span class="route-id-display">🚇 Route {legModel.routeId}</span>
                            </span>
                          )}
                        </span>
                        <span class="leg-duration-tag">
                          {legModel.durationMinutes > 0
                            ? `${legModel.durationMinutes} min`
                            : '< 1 min'}
                        </span>
                      </div>

                      <div class="leg-stops-flow">
                        <div class="leg-stop-row">
                          <div class="leg-stop-marker marker-board" />
                          <div class="leg-stop-details">
                            <span class="leg-stop-name">{legModel.boardStopName}</span>
                            <span class="leg-stop-time">
                              {formatClockTime(legModel.departureTime)}
                            </span>
                          </div>
                        </div>

                        <div class="leg-connector-line" />

                        <div class="leg-stop-row">
                          <div class="leg-stop-marker marker-exit" />
                          <div class="leg-stop-details">
                            <span class="leg-stop-name">{legModel.exitStopName}</span>
                            <span class="leg-stop-time">
                              {formatClockTime(legModel.arrivalTime)}
                            </span>
                          </div>
                        </div>
                      </div>

                      {legModel.transferDistanceM > 0 && legModel.isTransfer && (
                        <div class="leg-transfer-distance">
                          Transfer distance: ~{legModel.transferDistanceM} m
                        </div>
                      )}
                    </div>
                  );
                })}
              </div>
            </div>
          );
        })}
      </div>
    </div>
  );
}
