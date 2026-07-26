/**
 * Privacy & Data Exporter Utilities
 * Fog of Wburg — Offline-First Architecture
 *
 * Guaranteed strict local storage:
 * All H3 spatial indices and location history are stored purely on-device in op-sqlite (JSI).
 * No location telemetry or spatial data is ever transmitted to external servers.
 */

export interface ExportedSpatialPayload {
  app: string;
  version: string;
  exportedAt: string;
  privacyDeclaration: string;
  metrics: {
    totalUnlockedHexes: number;
    estimatedAreaKm2: number;
  };
  unlockedHexes: string[];
}

export const PRIVACY_STATEMENT = `Fog of Wburg operates under a strict Offline-First & Zero-Telemetry Privacy Policy. All GPS coordinates, H3 hexagon indices, and discovered points of interest remain encrypted and saved exclusively on your local device via @op-engineering/op-sqlite. Your real-world location is never tracked, stored on cloud servers, or sold to third parties.`;

/**
 * Serializes unlocked hexes and exploration stats into a formatted JSON payload for offline backup and privacy auditing.
 */
export function exportSpatialDataJSON(unlockedHexes: string[], totalUnlockedHexes: number): string {
  // Ensure strict string array precision for H3 hexes
  const hexStrings = unlockedHexes.filter((hex): hex is string => typeof hex === 'string');

  const payload: ExportedSpatialPayload = {
    app: 'Fog of Wburg',
    version: '1.0.0',
    exportedAt: new Date().toISOString(),
    privacyDeclaration: PRIVACY_STATEMENT,
    metrics: {
      totalUnlockedHexes: hexStrings.length,
      estimatedAreaKm2: Number((hexStrings.length * 0.05).toFixed(2)),
    },
    unlockedHexes: hexStrings,
  };

  return JSON.stringify(payload, null, 2);
}
