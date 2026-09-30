/**
 * routeBadge.ts
 * Pure display model functions and utilities for rendering transit route/line badges.
 *
 * Invariants:
 * - FC-2: Zero internal identifiers (route_id, trip_id) leak into UI copy.
 * - Graceful degradation: If routes.json fails to load or route ID is absent,
 *   renders neutral fallback badge (never crashes, never returns an empty pill).
 */

import type { RouteItem, RouteBadgeModel } from '../types/routing';

export const FALLBACK_ROUTE_COLOR = '#52525B';
export const FALLBACK_TEXT_COLOR = '#FFFFFF';

/**
 * Normalizes a hex color string, ensuring leading '#' and validating hex format.
 */
export function formatHexColor(color: string | undefined | null, fallback = FALLBACK_ROUTE_COLOR): string {
  if (!color || typeof color !== 'string') {
    return fallback;
  }
  const trimmed = color.trim();
  if (!trimmed) {
    return fallback;
  }
  const cleanHex = trimmed.startsWith('#') ? trimmed.slice(1) : trimmed;
  // Match standard 3, 4, 6, or 8 character hex strings
  if (/^[0-9A-Fa-f]{3,8}$/.test(cleanHex)) {
    return `#${cleanHex}`;
  }
  return fallback;
}

/**
 * Converts a routes.json dictionary object into a Map for fast lookups.
 */
export function createRoutesMap(
  data: Record<string, RouteItem> | null | undefined
): Map<string, RouteItem> {
  const map = new Map<string, RouteItem>();
  if (!data || typeof data !== 'object') {
    return map;
  }

  for (const [key, item] of Object.entries(data)) {
    if (item && typeof item === 'object' && typeof item.shortName === 'string') {
      map.set(key, item);
      const upperKey = key.toUpperCase();
      if (!map.has(upperKey)) {
        map.set(upperKey, item);
      }
    }
  }

  return map;
}

/**
 * Sanitizes a badge label to ensure no internal identifiers (e.g. route_id_, trip_id_)
 * leak into user-facing UI copy (Invariant FC-2).
 */
export function sanitizeBadgeLabel(rawLabel: string): string {
  const sanitized = rawLabel
    .replace(/^route_id[_-]?/i, '')
    .replace(/^route[_-]?/i, '')
    .replace(/^trip_id[_-]?/i, '')
    .trim();

  return sanitized || 'Transit';
}

/**
 * Resolves route badge metadata (short name, background color, text color)
 * given a route ID and routes lookup map.
 *
 * Guarantees:
 * - Pure function with zero side effects.
 * - Always returns a non-empty label (never an empty pill).
 * - Degrades gracefully to neutral styling on missing data or fetch failure.
 * - Never throws/crashes on malformed, null, or undefined input.
 */
export function getRouteBadge(
  routeId: string | number | undefined | null,
  routesMap?: Map<string, RouteItem> | Record<string, RouteItem> | null
): RouteBadgeModel {
  if (routeId == null || routeId === '') {
    return {
      label: 'Transit',
      backgroundColor: FALLBACK_ROUTE_COLOR,
      textColor: FALLBACK_TEXT_COLOR,
      isFallback: true,
    };
  }

  const idStr = String(routeId).trim();
  if (!idStr) {
    return {
      label: 'Transit',
      backgroundColor: FALLBACK_ROUTE_COLOR,
      textColor: FALLBACK_TEXT_COLOR,
      isFallback: true,
    };
  }

  let foundItem: RouteItem | undefined;

  if (routesMap instanceof Map) {
    foundItem = routesMap.get(idStr) || routesMap.get(idStr.toUpperCase());
    if (!foundItem) {
      // Secondary lookup by shortName match
      for (const item of routesMap.values()) {
        if (item.shortName && item.shortName.toUpperCase() === idStr.toUpperCase()) {
          foundItem = item;
          break;
        }
      }
    }
  } else if (routesMap && typeof routesMap === 'object') {
    foundItem = (routesMap as Record<string, RouteItem>)[idStr] ||
      (routesMap as Record<string, RouteItem>)[idStr.toUpperCase()];
    if (!foundItem) {
      for (const item of Object.values(routesMap)) {
        if (item && item.shortName && item.shortName.toUpperCase() === idStr.toUpperCase()) {
          foundItem = item;
          break;
        }
      }
    }
  }

  if (foundItem) {
    const rawLabel = foundItem.shortName ? foundItem.shortName.trim() : idStr;
    const label = sanitizeBadgeLabel(rawLabel);
    return {
      label,
      backgroundColor: formatHexColor(foundItem.color),
      textColor: formatHexColor(foundItem.textColor, FALLBACK_TEXT_COLOR),
      isFallback: false,
    };
  }

  // Graceful fallback: neutral badge with sanitized short name or ID
  const fallbackLabel = sanitizeBadgeLabel(idStr);
  return {
    label: fallbackLabel,
    backgroundColor: FALLBACK_ROUTE_COLOR,
    textColor: FALLBACK_TEXT_COLOR,
    isFallback: true,
  };
}
