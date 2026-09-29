import { Map, addProtocol, type ErrorEvent } from 'maplibre-gl';
import { Protocol, PMTiles, FileSource } from 'pmtiles';
import { isFatalMapError } from './mapErrorClassification.ts';

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
  onLoad?: (map: Map) => void;
  onError?: (err: Error) => void;
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
  onLoad,
  onError,
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

  map.once('load', () => {
    onLoad?.(map);
  });

  map.on('error', (e: ErrorEvent) => {
    // eslint-disable-next-line no-console
    console.warn('[MapLibre] Map error:', e.error);
    if (e.error && isFatalMapError(e.error)) {
      const err = e.error instanceof Error ? e.error : new Error(e.error.message || 'Map error');
      onError?.(err);
    }
  });

  return map;
}
