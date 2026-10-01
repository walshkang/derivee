import { Map, addProtocol, setWorkerUrl, type ErrorEvent } from 'maplibre-gl';
import maplibreWorkerUrl from 'maplibre-gl/dist/maplibre-gl-worker.mjs?worker&url';
import { Protocol, PMTiles, FileSource } from 'pmtiles';
import { isFatalMapError, formatMapWorkerError } from './mapErrorClassification.ts';

// Configure MapLibre worker asset URL before any Map instance is created
setWorkerUrl(maplibreWorkerUrl);

export { maplibreWorkerUrl };

let protocolInstance: Protocol | null = null;
let isProtocolAdded = false;

export function getGlobalPMTilesProtocol(): Protocol {
  if (!protocolInstance) {
    protocolInstance = new Protocol();
  }
  if (!isProtocolAdded && typeof addProtocol !== 'undefined') {
    addProtocol('pmtiles', protocolInstance.tile);
    isProtocolAdded = true;
  }
  return protocolInstance;
}

export interface InitMapOptions {
  container: HTMLElement | string;
  file: File;
  styleUrl?: string;
  mountTimeoutMs?: number;
  onLoad?: (map: Map) => void;
  onError?: (err: Error) => void;
  onTimeout?: () => void;
}

/**
 * Initializes MapLibre GL JS with PMTiles file read directly from OPFS via FileSource.
 * Zero network requests after install.
 * Viewport: unlimited (no camera clamp per M4a specification).
 */
export function initOfflineMap({
  container,
  file,
  styleUrl = '/map-style-dark.json',
  mountTimeoutMs = 20_000,
  onLoad,
  onError,
  onTimeout,
}: InitMapOptions): Map {
  const protocol = getGlobalPMTilesProtocol();
  const pmtiles = new PMTiles(new FileSource(file));
  protocol.add(pmtiles);

  const map = new Map({
    container,
    style: styleUrl,
    center: [-73.98, 40.75], // Midtown Manhattan
    zoom: 12,
    maxZoom: 18,
    dragRotate: false,
    pitchWithRotate: false,
    // Unlimited viewport: no maxBounds per locked design specification
  });

  let isSettled = false;
  let timer: ReturnType<typeof setTimeout> | undefined;

  if (mountTimeoutMs > 0) {
    timer = setTimeout(() => {
      if (!isSettled) {
        isSettled = true;
        if (onTimeout) {
          onTimeout();
        } else if (onError) {
          onError(new Error('Map load timed out waiting for style and tiles.'));
        }
      }
    }, mountTimeoutMs);
  }

  map.once('load', () => {
    if (isSettled) return;
    isSettled = true;
    if (timer !== undefined) {
      clearTimeout(timer);
      timer = undefined;
    }
    onLoad?.(map);
  });

  map.on('error', (e: ErrorEvent) => {
    // eslint-disable-next-line no-console
    console.warn('[MapLibre] Map error:', e.error);
    if (e.error && isFatalMapError(e.error)) {
      if (isSettled) return;
      isSettled = true;
      if (timer !== undefined) {
        clearTimeout(timer);
        timer = undefined;
      }
      const workerUrl = typeof maplibreWorkerUrl === 'string' ? maplibreWorkerUrl : '';
      const err = formatMapWorkerError(e.error, workerUrl);
      onError?.(err);
    }
  });

  return map;
}
