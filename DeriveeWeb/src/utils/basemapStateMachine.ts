import type { MapState } from '../types/basemap';

export interface BasemapStateSnapshot {
  state: MapState;
  percent: number;
  loadedBytes: number;
  totalBytes: number;
  errorMessage: string | null;
  errorDetails?: string | null;
}

export type BasemapStateListener = (snapshot: BasemapStateSnapshot) => void;

/**
 * State machine managing basemap lifecycle states and transitions.
 * Enforces retrospective Rule 11 states:
 * - map-loading: PMTiles downloading with progress % (first-run only)
 * - map-ready: tiles render, pan/zoom
 * - map-error: download or tile failure -> message + Retry button
 * - map-cached: returning visit: instant render from OPFS, no download flash
 */
export class BasemapStateMachine {
  private currentState: MapState = 'map-loading';
  private percent: number = 0;
  private loadedBytes: number = 0;
  private totalBytes: number = 0;
  private errorMessage: string | null = null;
  private errorDetails: string | null = null;
  private listeners = new Set<BasemapStateListener>();

  constructor(initialState: MapState = 'map-loading') {
    this.currentState = initialState;
  }

  get snapshot(): BasemapStateSnapshot {
    return {
      state: this.currentState,
      percent: this.percent,
      loadedBytes: this.loadedBytes,
      totalBytes: this.totalBytes,
      errorMessage: this.errorMessage,
      errorDetails: this.errorDetails,
    };
  }

  subscribe(listener: BasemapStateListener): () => void {
    this.listeners.add(listener);
    listener(this.snapshot);
    return () => {
      this.listeners.delete(listener);
    };
  }

  private notify(): void {
    const snap = this.snapshot;
    for (const listener of this.listeners) {
      listener(snap);
    }
  }

  /**
   * Called when OPFS already contains a valid basemap.pmtiles file.
   * Instant transition with zero network and no download flash.
   */
  setCached(): void {
    this.currentState = 'map-cached';
    this.errorMessage = null;
    this.errorDetails = null;
    this.notify();
  }

  /**
   * Called when starting first-run PMTiles download.
   */
  startDownloading(totalExpectedBytes: number = 24991495): void {
    this.currentState = 'map-loading';
    this.percent = 0;
    this.loadedBytes = 0;
    this.totalBytes = totalExpectedBytes;
    this.errorMessage = null;
    this.errorDetails = null;
    this.notify();
  }

  /**
   * Called on download progress chunk.
   */
  updateProgress(loadedBytes: number, totalBytes: number, percent: number): void {
    if (this.currentState !== 'map-loading') return;
    this.loadedBytes = loadedBytes;
    this.totalBytes = totalBytes;
    this.percent = Math.min(100, Math.max(0, percent));
    this.notify();
  }

  /**
   * Called when PMTiles is installed or MapLibre renders tiles.
   */
  setReady(): void {
    this.currentState = 'map-ready';
    this.percent = 100;
    this.errorMessage = null;
    this.errorDetails = null;
    this.notify();
  }

  /**
   * Called when download, integrity check, or tile rendering fails.
   */
  setError(message: string, details?: string): void {
    this.currentState = 'map-error';
    this.errorMessage = message;
    this.errorDetails = details || null;
    this.notify();
  }

  /**
   * Retry handler invoked from user tap on Retry button.
   * Restarts the download pipeline from scratch.
   */
  retry(totalExpectedBytes: number = 24991495): void {
    this.startDownloading(totalExpectedBytes);
  }
}
