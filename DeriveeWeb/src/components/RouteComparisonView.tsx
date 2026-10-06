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
  RouteItem,
  RoutingProfile,
  RankedItinerary,
  RoutePatternEntry,
} from '../types/routing';
import {
  describeItinerary,
  countTransfers,
  type TransitLegDisplay,
} from '../utils/itineraryDisplay';
import {
  formatTransferCount,
  formatClockTime,
  formatArrivalTime,
  getRouteComparisonUIState,
} from '../utils/routeComparison';
import { getRouteBadge } from '../utils/routeBadge';

interface RouteComparisonViewProps {
  rankedCards: RankedItinerary[];
  activeProfile: RoutingProfile;
  onSelectProfile: (profile: RoutingProfile) => void;
  stopsMap: Map<number, StopItem>;
  routesMap?: Map<string, RouteItem>;
  isRouting: boolean;
  routeError: string | null;
  hasQueried: boolean;
  patternsMap?: RoutePatternEntry[] | null;
  onSelectLeg?: (leg: TransitLegDisplay) => void;
}

export function RouteComparisonView({
  rankedCards,
  activeProfile,
  onSelectProfile,
  stopsMap,
  routesMap,
  isRouting,
  routeError,
  hasQueried,
  patternsMap,
  onSelectLeg,
}: RouteComparisonViewProps) {
  const uiState = getRouteComparisonUIState({
    isRouting,
    routeError,
    rankedCards,
    hasQueried,
  });

  if (uiState.state === 'loading') {
    return (
      <div class="route-comparison-loading" role="status" aria-label="Calculating routes...">
        <div class="itinerary-skeleton-card">
          <div class="skeleton-header-row">
            <div class="skeleton-pills-row">
              <span class="skeleton-pill skeleton-rank-pill shimmer" />
              <span class="skeleton-pill skeleton-badge-pill shimmer" />
            </div>
            <div class="skeleton-arrival-block">
              <span class="skeleton-line skeleton-arrival-label shimmer" />
              <span class="skeleton-line skeleton-arrival-time shimmer" />
            </div>
          </div>
          <div class="skeleton-glance-bar shimmer" />
          <div class="skeleton-legs">
            <div class="skeleton-leg-row">
              <span class="skeleton-marker shimmer" />
              <span class="skeleton-line skeleton-station shimmer" />
              <span class="skeleton-line skeleton-time shimmer" />
            </div>
            <div class="skeleton-connector-line shimmer" />
            <div class="skeleton-leg-row">
              <span class="skeleton-marker shimmer" />
              <span class="skeleton-line skeleton-station shimmer" />
              <span class="skeleton-line skeleton-time shimmer" />
            </div>
          </div>
        </div>
      </div>
    );
  }

  if (uiState.state === 'error') {
    return (
      <div class="itinerary-error-box" role="alert">
        <div class="error-icon-slot" aria-hidden="true">
          <svg viewBox="0 0 20 20" width="18" height="18" fill="currentColor">
            <path fill-rule="evenodd" d="M8.257 3.099c.765-1.36 2.722-1.36 3.486 0l5.58 9.92c.75 1.334-.213 2.98-1.742 2.98H4.42c-1.53 0-2.493-1.646-1.743-2.98l5.58-9.92zM11 13a1 1 0 11-2 0 1 1 0 012 0zm-1-8a1 1 0 00-1 1v3a1 1 0 002 0V6a1 1 0 00-1-1z" clip-rule="evenodd" />
          </svg>
        </div>
        <div class="error-content">
          <span class="error-title">Routing Unavailable</span>
          <span class="error-description">{uiState.userFacingDescription}</span>
        </div>
      </div>
    );
  }

  if (uiState.state === 'empty') {
    if (!hasQueried) return null;
    return (
      <div class="route-comparison-empty" role="status">
        <div class="empty-icon-slot" aria-hidden="true">
          <svg viewBox="0 0 24 24" width="28" height="28" fill="none" stroke="currentColor" stroke-width="1.75">
            <circle cx="12" cy="12" r="9" />
            <line x1="9" y1="9" x2="15" y2="15" />
            <line x1="15" y1="9" x2="9" y2="15" />
          </svg>
        </div>
        <span class="empty-title">No direct transit route found</span>
        <span class="empty-subtitle">
          No scheduled trips connect these stations at the selected departure time. Try adjusting your departure time or choosing an adjacent station.
        </span>
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
          const legModels = describeItinerary(card.segments, stopsMap, patternsMap ?? undefined);
          const transferCount = countTransfers(card.segments, stopsMap);
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
                <span class="glance-transfers">{formatTransferCount(transferCount)}</span>
              </div>

              {/* Leg Breakdown */}
              <div class="itinerary-legs-list">
                {legModels.map((legModel, legIdx) => {
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

                  if (legModel.kind === 'connector') {
                    return (
                      <div
                        key={legIdx}
                        class="itinerary-compact-row transfer-connector-row itinerary-transfer-connector"
                      >
                        <span
                          class="compact-marker marker-transfer"
                          style={{ borderColor: '#f59e0b' }}
                        />
                        <span class="itinerary-compact-text">
                          <span class="leg-mode-pill mode-pill-walk" aria-hidden="true" style={{ display: 'none' }} />
                          {legModel.text}
                          {legModel.transferDistanceM > 0 ? (
                            <span
                              style={{
                                color: 'var(--text-muted)',
                                fontWeight: 'normal',
                                marginLeft: '6px',
                              }}
                            >
                              (~{legModel.transferDistanceM} m
                              {legModel.durationMinutes > 0
                                ? ` • ${legModel.durationMinutes} min`
                                : ''}
                              )
                            </span>
                          ) : null}
                        </span>
                        <span class="itinerary-compact-time">
                          {legModel.durationMinutes > 0
                            ? `${legModel.durationMinutes} min`
                            : '< 1 min'}
                        </span>
                      </div>
                    );
                  }

                  if (legModel.kind === 'walk') {
                    return (
                      <div key={legIdx} class="itinerary-compact-row itinerary-walk-access">
                        <span class="compact-marker" style={{ borderColor: '#94a3b8' }} />
                        <span class="itinerary-compact-text">
                          <span class="leg-mode-pill mode-pill-walk" aria-hidden="true" style={{ display: 'none' }} />
                          Walk {legModel.boardStopName} → {legModel.exitStopName}
                          {legModel.transferDistanceM > 0 ? (
                            <span
                              style={{
                                color: 'var(--text-muted)',
                                fontWeight: 'normal',
                                marginLeft: '6px',
                              }}
                            >
                              (~{legModel.transferDistanceM} m)
                            </span>
                          ) : null}
                        </span>
                        <span class="itinerary-compact-time">
                          {legModel.durationMinutes > 0
                            ? `${legModel.durationMinutes} min`
                            : '< 1 min'}
                        </span>
                      </div>
                    );
                  }

                  const routeBadge = getRouteBadge(legModel.routeId, routesMap);
                  const isTappable = Boolean(onSelectLeg);

                  return (
                    <div
                      key={legIdx}
                      class={`itinerary-leg-card ${isTappable ? 'itinerary-leg-card-tappable' : ''}`}
                      role={isTappable ? 'button' : undefined}
                      tabIndex={isTappable ? 0 : undefined}
                      onClick={isTappable ? () => onSelectLeg?.(legModel) : undefined}
                      onKeyDown={
                        isTappable
                          ? (e) => {
                              if (e.key === 'Enter' || e.key === ' ') {
                                e.preventDefault();
                                onSelectLeg?.(legModel);
                              }
                            }
                          : undefined
                      }
                      aria-label={`View stops for Leg ${legModel.legIndex + 1}: ${routeBadge?.label || 'Transit'}, ${legModel.boardStopName} to ${legModel.exitStopName}`}
                    >
                      <div class="leg-card-header">
                        <span class="leg-index-badge">Leg {legModel.legIndex + 1}</span>
                        {routeBadge ? (
                          <span class="route-badge-container">
                            <span
                              class={`route-pill-badge ${
                                routeBadge.isFallback ? 'route-pill-fallback' : ''
                              }`}
                              style={{
                                backgroundColor: routeBadge.backgroundColor,
                                color: routeBadge.textColor,
                              }}
                              data-route-id={String(routeBadge.label)}
                              aria-label={`Line ${routeBadge.label}`}
                            >
                              {routeBadge.label}
                            </span>
                          </span>
                        ) : null}
                        <div class="leg-header-right">
                          <span class="leg-duration-tag">
                            {legModel.durationMinutes > 0
                              ? `${legModel.durationMinutes} min`
                              : '< 1 min'}
                          </span>
                          {isTappable && (
                            <span class="leg-card-chevron" aria-hidden="true">
                              ›
                            </span>
                          )}
                        </div>
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

                      {legModel.intermediateStopsCount && legModel.intermediateStopsCount > 0 ? (
                        <div class="leg-transit-meta">
                          {legModel.intermediateStopsCount} intermediate{' '}
                          {legModel.intermediateStopsCount === 1 ? 'stop' : 'stops'}
                        </div>
                      ) : null}
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
