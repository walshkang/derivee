import { Map, addProtocol, setWorkerUrl, type ErrorEvent } from 'maplibre-gl';
import maplibreWorkerUrl from 'maplibre-gl/dist/maplibre-gl-worker.mjs?worker&url';
import { Protocol, PMTiles, FileSource } from 'pmtiles';
import { isFatalMapError, formatMapWorkerError } from './mapErrorClassification.ts';
import type { MountSubStage, MountDiagnostic } from '../types/basemap.ts';

// Configure MapLibre worker asset URL before any Map instance is created
setWorkerUrl(maplibreWorkerUrl);

export { maplibreWorkerUrl };
export type { MountSubStage, MountDiagnostic };

export const MOUNT_SUB_STAGE_ORDER: Record<MountSubStage, number> = {
  MOUNT_STYLE_LOADING: 1,
  MOUNT_STYLE_PARSED: 2,
  MOUNT_FIRST_TILE_REQUESTED: 3,
  MOUNT_FIRST_TILE_LOADED: 4,
  MOUNT_GLYPHS_LOADED: 5,
};

export function formatMountDiagnostic(diag?: MountDiagnostic | null): string {
  if (!diag) {
    return 'Stage: MAP_MOUNTING\nDiagnostic: MapLibre failed to load style and tiles within 20s.';
  }
  const tileInfo = `tiles requested: ${diag.tilesRequested}, loaded: ${diag.tilesLoaded}, errored: ${diag.tilesErrored}${
    diag.firstTileError ? `, first error: ${diag.firstTileError}` : ''
  }`;
  return `Stage: MAP_MOUNTING\nDiagnostic: MapLibre failed to load style and tiles within 20s (sub-stage: ${diag.subStage}, ${tileInfo}).`;
}

export type TileEvent =
  | { type: 'tile_requested'; url: string }
  | { type: 'tile_loaded'; url: string; byteLength: number }
  | { type: 'tile_error'; url: string; error: unknown };

let protocolInstance: Protocol | null = null;
let isProtocolAdded = false;
let activeTileTracker: ((event: TileEvent) => void) | null = null;

export function setActiveTileTracker(tracker: ((event: TileEvent) => void) | null): void {
  activeTileTracker = tracker;
}

export function getGlobalPMTilesProtocol(): Protocol {
  if (!protocolInstance) {
    protocolInstance = new Protocol();
    const originalTile = protocolInstance.tile.bind(protocolInstance);

    const wrappedTile = (params: any, arg2: any) => {
      const isTile = params?.type !== 'json' && /\/\d+\/\d+\/\d+/.test(params?.url || '');
      if (isTile) {
        activeTileTracker?.({ type: 'tile_requested', url: params.url });
      }

      if (typeof arg2 === 'function') {
        const wrappedCallback = (err: any, data: any, cacheControl: any, expires: any) => {
          if (isTile) {
            if (err) {
              activeTileTracker?.({ type: 'tile_error', url: params.url, error: err });
            } else {
              const byteLength = data?.byteLength || 0;
              activeTileTracker?.({ type: 'tile_loaded', url: params.url, byteLength });
            }
          }
          return arg2(err, data, cacheControl, expires);
        };
        return originalTile(params, wrappedCallback);
      } else {
        try {
          const res = originalTile(params, arg2);
          if (res && 'then' in res && typeof (res as any).then === 'function') {
            return (res as Promise<any>).then(
              (val: any) => {
                if (isTile) {
                  const byteLength = val?.data?.byteLength || 0;
                  activeTileTracker?.({ type: 'tile_loaded', url: params.url, byteLength });
                }
                return val;
              },
              (err: any) => {
                if (isTile) {
                  activeTileTracker?.({ type: 'tile_error', url: params.url, error: err });
                }
                throw err;
              }
            );
          }
          return res;
        } catch (err: any) {
          if (isTile) {
            activeTileTracker?.({ type: 'tile_error', url: params.url, error: err });
          }
          throw err;
        }
      }
    };

    protocolInstance.tile = wrappedTile as any;
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
  onTimeout?: (diagnostic?: MountDiagnostic) => void;
  onSubStageChange?: (subStage: MountSubStage) => void;
  onDiagnosticUpdate?: (diagnostic: MountDiagnostic) => void;
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
  onSubStageChange,
  onDiagnosticUpdate,
}: InitMapOptions): Map {
  const telemetry: MountDiagnostic = {
    subStage: 'MOUNT_STYLE_LOADING',
    tilesRequested: 0,
    tilesLoaded: 0,
    tilesErrored: 0,
    firstTileError: null,
  };

  const notifyUpdate = () => {
    onDiagnosticUpdate?.({ ...telemetry });
  };

  const recordSubStage = (next: MountSubStage) => {
    if (MOUNT_SUB_STAGE_ORDER[next] > MOUNT_SUB_STAGE_ORDER[telemetry.subStage]) {
      telemetry.subStage = next;
      onSubStageChange?.(next);
      notifyUpdate();
    }
  };

  notifyUpdate();

  const protocol = getGlobalPMTilesProtocol();
  const pmtiles = new PMTiles(new FileSource(file));
  protocol.add(pmtiles);

  let isSettled = false;
  let timer: ReturnType<typeof setTimeout> | undefined;

  const tileTracker = (event: TileEvent) => {
    if (isSettled) return;
    if (event.type === 'tile_requested') {
      telemetry.tilesRequested++;
      recordSubStage('MOUNT_FIRST_TILE_REQUESTED');
      notifyUpdate();
    } else if (event.type === 'tile_loaded') {
      telemetry.tilesLoaded++;
      if (event.byteLength > 0) {
        recordSubStage('MOUNT_FIRST_TILE_LOADED');
      }
      notifyUpdate();
    } else if (event.type === 'tile_error') {
      telemetry.tilesErrored++;
      if (!telemetry.firstTileError) {
        const msg = event.error instanceof Error ? event.error.message : String(event.error);
        telemetry.firstTileError = msg;
      }
      notifyUpdate();
    }
  };

  setActiveTileTracker(tileTracker);

  const cleanup = () => {
    if (activeTileTracker === tileTracker) {
      setActiveTileTracker(null);
    }
    if (timer !== undefined) {
      clearTimeout(timer);
      timer = undefined;
    }
  };

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

  function attachGlyphTracker(style: any) {
    if (!style || typeof style.getGlyphs !== 'function' || style._glyphsTracked) return;
    style._glyphsTracked = true;
    const origGetGlyphs = style.getGlyphs.bind(style);
    style.getGlyphs = async function (...args: any[]) {
      try {
        const res = await origGetGlyphs(...args);
        recordSubStage('MOUNT_GLYPHS_LOADED');
        return res;
      } catch (err) {
        if (!telemetry.firstTileError) {
          const msg = err instanceof Error ? err.message : String(err);
          telemetry.firstTileError = msg;
          notifyUpdate();
        }
        throw err;
      }
    };
  }

  if ((map as any).style) {
    attachGlyphTracker((map as any).style);
  }

  map.on('style.load', () => {
    recordSubStage('MOUNT_STYLE_PARSED');
    if ((map as any).style) {
      attachGlyphTracker((map as any).style);
    }
  });

  map.on('styledata', () => {
    if (map.isStyleLoaded()) {
      recordSubStage('MOUNT_STYLE_PARSED');
    }
  });

  map.on('sourcedata', (e: any) => {
    if (e.sourceId === 'basemap' || e.isSourceLoaded) {
      recordSubStage('MOUNT_STYLE_PARSED');
    }
  });

  map.on('remove', cleanup);

  if (mountTimeoutMs > 0) {
    timer = setTimeout(() => {
      if (!isSettled) {
        isSettled = true;
        cleanup();
        if (onTimeout) {
          onTimeout({ ...telemetry });
        } else if (onError) {
          onError(new Error(formatMountDiagnostic(telemetry)));
        }
      }
    }, mountTimeoutMs);
  }

  map.once('load', () => {
    if (isSettled) return;
    isSettled = true;
    cleanup();
    onLoad?.(map);
  });

  map.on('error', (e: ErrorEvent) => {
    // eslint-disable-next-line no-console
    console.warn('[MapLibre] Map error:', e.error);

    if (e.error) {
      const msg = e.error instanceof Error ? e.error.message : String(e.error);
      const isRecoverableMapError = !isFatalMapError(e.error);
      if (isRecoverableMapError) {
        if (!telemetry.firstTileError) {
          telemetry.firstTileError = msg;
          notifyUpdate();
        }
        if (msg.toLowerCase().includes('tile') && telemetry.tilesErrored === 0 && telemetry.tilesRequested > 0) {
          telemetry.tilesErrored++;
          notifyUpdate();
        }
      }
    }

    if (e.error && isFatalMapError(e.error)) {
      if (isSettled) return;
      isSettled = true;
      cleanup();
      const workerUrl = typeof maplibreWorkerUrl === 'string' ? maplibreWorkerUrl : '';
      const err = formatMapWorkerError(e.error, workerUrl);
      onError?.(err);
    }
  });

  (map as any).getMountDiagnostic = () => ({ ...telemetry });

  return map;
}
