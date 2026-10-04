/**
 * LegDetailView.tsx
 * Detail drill-in view for transit ride legs (Wave T2).
 *
 * Implements:
 * 1. Headsign-first destination header ("To [Terminal]" - design.md PB.5).
 * 2. Route badge pill in official MTA color with zero internal ID leaks (FC-2).
 * 3. Stop ladder with scheduled times from pack stop_times / timetable.
 * 4. Boarding and alighting stops emphasized.
 * 5. Complete state coverage: loading, loaded, empty (graceful fallback), error/retry.
 * 6. Live times (stretch): probes /api/realtime/arrivals; degrades cleanly on 503 kv_not_configured.
 */

import { useState, useEffect } from 'preact/hooks';
import type { RouteItem } from '../types/routing.ts';
import {
  type TransitLegDisplay,
  formatHeadsign,
} from '../utils/itineraryDisplay.ts';
import { formatClockTime } from '../utils/routeComparison.ts';
import { getRouteBadge } from '../utils/routeBadge.ts';

export interface LegDetailViewProps {
  leg: TransitLegDisplay;
  routesMap?: Map<string, RouteItem>;
  onBack: () => void;
  isLoading?: boolean;
  error?: string | null;
  onRetry?: () => void;
}

interface LiveArrivalInfo {
  minutesAway: number;
  isApproaching?: boolean;
}

export function LegDetailView({
  leg,
  routesMap,
  onBack,
  isLoading = false,
  error = null,
  onRetry,
}: LegDetailViewProps) {
  const [liveArrival, setLiveArrival] = useState<LiveArrivalInfo | null>(null);
  const routeBadge = getRouteBadge(leg.routeId, routesMap);
  const routeColor = routeBadge?.backgroundColor || '#38bdf8';

  // Live Times Probe (Stretch Goal - M7a /api/realtime/arrivals)
  // Gracefully handles 503 kv_not_configured without showing errors to user
  useEffect(() => {
    let isCancelled = false;

    if (!leg.boardStopId) return;

    const probeLiveTimes = async () => {
      try {
        const controller = new AbortController();
        const timeoutId = setTimeout(() => controller.abort(), 2000);

        const res = await fetch(`/api/realtime/arrivals?stop_id=${leg.boardStopId}`, {
          signal: controller.signal,
        });
        clearTimeout(timeoutId);

        if (!res.ok) {
          // 503 kv_not_configured or other status -> degrade cleanly to scheduled times
          return;
        }

        const data = await res.json();
        if (isCancelled || !data || !Array.isArray(data.arrivals)) return;

        const targetRoute = routeBadge?.label?.toLowerCase();
        const match = data.arrivals.find((arr: any) => {
          if (!targetRoute) return false;
          return String(arr.route_id || '').toLowerCase() === targetRoute;
        });

        if (match && typeof match.minutesAway === 'number') {
          setLiveArrival({
            minutesAway: match.minutesAway,
            isApproaching: Boolean(match.isApproaching),
          });
        }
      } catch {
        // Network offline or timeout -> clean fallback to scheduled times
      }
    };

    probeLiveTimes();

    return () => {
      isCancelled = true;
    };
  }, [leg.boardStopId, routeBadge?.label]);

  const headsignTitle = formatHeadsign(leg.headsign, leg.exitStopName);
  const stops = leg.stops ?? [];
  const hasStops = stops.length > 0;

  // 1. Loading State
  if (isLoading) {
    return (
      <div class="leg-detail-container" role="region" aria-label="Loading leg details">
        <div class="leg-detail-header">
          <button
            type="button"
            class="leg-detail-back-btn"
            onClick={onBack}
            aria-label="Back to routes"
          >
            <span class="back-arrow" aria-hidden="true">←</span>
            <span>Back to routes</span>
          </button>
        </div>
        <div class="leg-detail-loading" role="status" aria-label="Resolving route shape and stops...">
          <div class="skeleton-line shimmer" style={{ width: '40%', height: '22px', marginBottom: '14px' }} />
          <div class="skeleton-line shimmer" style={{ width: '60%', height: '14px', marginBottom: '24px' }} />
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

  // 2. Error State
  if (error) {
    return (
      <div class="leg-detail-container" role="region" aria-label="Leg detail error">
        <div class="leg-detail-header">
          <button
            type="button"
            class="leg-detail-back-btn"
            onClick={onBack}
            aria-label="Back to routes"
          >
            <span class="back-arrow" aria-hidden="true">←</span>
            <span>Back to routes</span>
          </button>
        </div>
        <div class="leg-detail-error" role="alert">
          <div class="error-icon-slot" aria-hidden="true">
            <svg viewBox="0 0 20 20" width="18" height="18" fill="currentColor">
              <path fill-rule="evenodd" d="M8.257 3.099c.765-1.36 2.722-1.36 3.486 0l5.58 9.92c.75 1.334-.213 2.98-1.742 2.98H4.42c-1.53 0-2.493-1.646-1.743-2.98l5.58-9.92zM11 13a1 1 0 11-2 0 1 1 0 012 0zm-1-8a1 1 0 00-1 1v3a1 1 0 002 0V6a1 1 0 00-1-1z" clip-rule="evenodd" />
            </svg>
          </div>
          <span class="error-title">Unable to display leg details</span>
          <span class="error-description">{error}</span>
          {onRetry && (
            <button type="button" class="leg-detail-retry-btn" onClick={onRetry}>
              Retry
            </button>
          )}
        </div>
      </div>
    );
  }

  // 3. Loaded State with Stop Ladder (or Empty Fallback)
  return (
    <div class="leg-detail-container" role="region" aria-label="Leg details">
      {/* Detail Header */}
      <div class="leg-detail-header">
        <button
          type="button"
          class="leg-detail-back-btn"
          onClick={onBack}
          aria-label="Back to routes"
        >
          <span class="back-arrow" aria-hidden="true">←</span>
          <span>Back to routes</span>
        </button>

        <div class="leg-detail-title-row">
          {routeBadge ? (
            <span
              class={`route-pill-badge leg-detail-route-badge ${routeBadge.isFallback ? 'route-pill-fallback' : ''}`}
              style={{
                backgroundColor: routeBadge.backgroundColor,
                color: routeBadge.textColor,
              }}
              data-route-id={String(routeBadge.label)}
              aria-label={`Line ${routeBadge.label}`}
            >
              {routeBadge.label}
            </span>
          ) : null}
          <h3 class="leg-detail-headsign">{headsignTitle}</h3>
        </div>

        {/* Glance Metrics */}
        <div class="leg-detail-glance">
          <span class="glance-duration">
            {leg.durationMinutes > 0 ? `${leg.durationMinutes} min` : '< 1 min'}
          </span>
          <span class="glance-dot">•</span>
          <span class="glance-time-range">
            {formatClockTime(leg.departureTime)} – {formatClockTime(leg.arrivalTime)}
          </span>
          {hasStops && (
            <>
              <span class="glance-dot">•</span>
              <span class="glance-stops-count">
                {stops.length} {stops.length === 1 ? 'stop' : 'stops'}
              </span>
            </>
          )}
          {liveArrival && (
            <>
              <span class="glance-dot">•</span>
              <span class="live-eta-pill">
                ⚡ Live in {liveArrival.minutesAway} min
              </span>
            </>
          )}
        </div>
      </div>

      {/* Stop Ladder or Graceful Empty State */}
      {!hasStops ? (
        <div class="leg-detail-empty" role="status">
          <div class="empty-icon-slot" aria-hidden="true">
            <svg viewBox="0 0 24 24" width="24" height="24" fill="none" stroke="currentColor" stroke-width="1.75">
              <circle cx="12" cy="12" r="9" />
              <line x1="9" y1="9" x2="15" y2="15" />
              <line x1="15" y1="9" x2="9" y2="15" />
            </svg>
          </div>
          <span class="empty-title">Intermediate stop details unavailable</span>
          <span class="empty-subtitle">
            Scheduled timetable stops for this line could not be resolved from the offline pack. Board at {leg.boardStopName} and alight at {leg.exitStopName}.
          </span>
        </div>
      ) : (
        <div class="leg-stops-ladder" role="list" aria-label="Stop list for this leg">
          {stops.map((stop, idx) => {
            const isFirst = stop.isBoarding || idx === 0;
            const isLast = stop.isAlighting || idx === stops.length - 1;
            const isInterim = !isFirst && !isLast;

            return (
              <div
                key={idx}
                class={`ladder-stop-item leg-stop-item ${isFirst ? 'ladder-stop-board is-boarding' : ''} ${
                  isLast ? 'ladder-stop-alight is-alighting' : ''
                } ${isInterim ? 'ladder-stop-interim' : ''}`}
                role="listitem"
              >
                <div class="ladder-marker-col">
                  <div
                    class={`ladder-marker ${
                      isFirst
                        ? 'ladder-marker-board'
                        : isLast
                        ? 'ladder-marker-alight'
                        : 'ladder-marker-interim'
                    }`}
                    style={{ borderColor: routeColor }}
                  />
                  {!isLast && (
                    <div
                      class="ladder-connector-segment"
                      style={{ backgroundColor: routeColor }}
                    />
                  )}
                </div>

                <div class="ladder-stop-info">
                  <div class="ladder-stop-name-row">
                    <span
                      class={`ladder-stop-name leg-stop-name ${
                        isFirst || isLast ? 'ladder-stop-name-bold' : ''
                      }`}
                    >
                      {stop.stopName}
                    </span>
                    {isFirst && <span class="ladder-role-tag leg-stop-role-badge tag-board">Board</span>}
                    {isLast && <span class="ladder-role-tag leg-stop-role-badge tag-alight">Alight</span>}
                  </div>
                  <span class="ladder-stop-time leg-stop-time">
                    {formatClockTime(stop.time)}
                  </span>
                </div>
              </div>
            );
          })}
        </div>
      )}
    </div>
  );
}
