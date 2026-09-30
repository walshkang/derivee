import { useEffect, useRef, useState } from 'preact/hooks';
import type { BasemapWorkerToMainMessage, BasemapStage } from '../types/basemap';
import { BasemapStateMachine, type BasemapStateSnapshot } from '../utils/basemapStateMachine';
import { checkBasemapInstalled, getBasemapFile } from '../utils/opfs';
import { initOfflineMap } from '../utils/maplibreAdapter';
import { BasemapWatchdog } from '../utils/basemapWatchdog';
import { withTimeout } from '../utils/withTimeout';
import type { Map } from 'maplibre-gl';
import 'maplibre-gl/dist/maplibre-gl.css';

interface BasemapViewProps {
  slug?: string;
  onMapLoaded?: (map: Map) => void;
}

export function BasemapView({ slug = 'nyc', onMapLoaded }: BasemapViewProps) {
  const mapContainerRef = useRef<HTMLDivElement | null>(null);
  const mapInstanceRef = useRef<Map | null>(null);
  const workerRef = useRef<Worker | null>(null);
  const wakeLockRef = useRef<WakeLockSentinel | null>(null);
  const watchdogRef = useRef<BasemapWatchdog | null>(null);

  if (!watchdogRef.current) {
    watchdogRef.current = new BasemapWatchdog(20_000);
  }

  const [stateMachine] = useState(() => new BasemapStateMachine('map-loading'));
  const [snapshot, setSnapshot] = useState<BasemapStateSnapshot>(() => stateMachine.snapshot);

  useEffect(() => {
    return stateMachine.subscribe(setSnapshot);
  }, [stateMachine]);

  const acquireWakeLock = async () => {
    if ('wakeLock' in navigator && !wakeLockRef.current) {
      try {
        const lock = await navigator.wakeLock.request('screen');
        wakeLockRef.current = lock;
        if (typeof lock.addEventListener === 'function') {
          lock.addEventListener('release', () => {
            if (wakeLockRef.current === lock) {
              wakeLockRef.current = null;
            }
          });
        }
      } catch {
        // Wake lock can fail if window is backgrounded; safe to ignore
      }
    }
  };

  const releaseWakeLock = async () => {
    if (wakeLockRef.current) {
      const lock = wakeLockRef.current;
      wakeLockRef.current = null;
      try {
        await withTimeout(lock.release(), 5000, 'Release wake lock timed out');
      } catch {
        // Safe to ignore
      }
    }
  };

  // Re-acquire wake lock and complement watchdog on tab visibility resume
  useEffect(() => {
    let lastHidden = 0;

    const handleVisibilityChange = () => {
      if (typeof document === 'undefined') return;

      if (document.visibilityState === 'hidden') {
        lastHidden = Date.now();
      } else if (document.visibilityState === 'visible') {
        const suspendedMs = lastHidden > 0 ? Date.now() - lastHidden : 0;
        lastHidden = 0;

        if (stateMachine.snapshot.state === 'map-loading') {
          acquireWakeLock();

          // If backgrounded for more than stall threshold (20s) without progress,
          // invoke stall handler immediately rather than waiting for next watchdog tick
          if (suspendedMs >= 20_000) {
            const currentStage = watchdogRef.current?.getStage() || 'DOWNLOADING';
            handleStall(currentStage);
          }
        }
      }
    };

    document.addEventListener('visibilitychange', handleVisibilityChange);
    return () => {
      document.removeEventListener('visibilitychange', handleVisibilityChange);
    };
  }, [stateMachine]);

  const handleStall = (stalledStage: BasemapStage) => {
    if (workerRef.current) {
      workerRef.current.terminate();
      workerRef.current = null;
    }
    if (mapInstanceRef.current) {
      mapInstanceRef.current.remove();
      mapInstanceRef.current = null;
    }
    releaseWakeLock();
    stateMachine.setError(
      `Map setup stalled (stage: ${stalledStage}). Please tap Retry.`,
      `Stage: ${stalledStage}\nDiagnostic: Operation timed out after 20s of inactivity with no forward progress.`,
      stalledStage
    );
  };

  const startWorkerDownload = async () => {
    if (workerRef.current) {
      workerRef.current.terminate();
      workerRef.current = null;
    }
    if (mapInstanceRef.current) {
      mapInstanceRef.current.remove();
      mapInstanceRef.current = null;
    }

    watchdogRef.current?.reset('STARTING_DOWNLOAD');
    watchdogRef.current?.start(handleStall);

    await acquireWakeLock();
    stateMachine.startDownloading();

    try {
      const worker = new Worker(
        new URL('../workers/basemap-installer.worker.ts', import.meta.url),
        { type: 'module' }
      );
      workerRef.current = worker;

      worker.onmessage = async (e: MessageEvent<BasemapWorkerToMainMessage>) => {
        const msg = e.data;
        if (msg.type === 'STAGE') {
          watchdogRef.current?.recordProgress(msg.stage);
          stateMachine.setStage(msg.stage);
        } else if (msg.type === 'PROGRESS') {
          watchdogRef.current?.recordProgress('DOWNLOADING');
          stateMachine.updateProgress(msg.loadedBytes, msg.totalBytes, msg.percent);
        } else if (msg.type === 'READY') {
          watchdogRef.current?.recordProgress('WORKER_READY');
          stateMachine.setStage('WORKER_READY');
          if (workerRef.current) {
            workerRef.current.terminate();
            workerRef.current = null;
          }
          await releaseWakeLock();
          await mountMapFromOpfs();
        } else if (msg.type === 'ERROR') {
          watchdogRef.current?.stop();
          if (workerRef.current) {
            workerRef.current.terminate();
            workerRef.current = null;
          }
          await releaseWakeLock();
          const stage = msg.stage || watchdogRef.current?.getStage() || 'DOWNLOADING';
          stateMachine.setError(
            msg.message,
            msg.details || `Stage: ${stage}\nDiagnostic: Map installer encountered an error.`,
            stage
          );
        }
      };

      worker.onerror = async () => {
        watchdogRef.current?.stop();
        if (workerRef.current) {
          workerRef.current.terminate();
          workerRef.current = null;
        }
        await releaseWakeLock();
        const stage = watchdogRef.current?.getStage() || 'DOWNLOADING';
        stateMachine.setError(
          'Download was interrupted. Please check your connection and try again.',
          `Stage: ${stage}\nDiagnostic: Worker thread failed or crashed.`,
          stage
        );
      };

      worker.postMessage({ type: 'START_INSTALL', slug });
    } catch (err: unknown) {
      watchdogRef.current?.stop();
      await releaseWakeLock();
      const stage = watchdogRef.current?.getStage() || 'STARTING_DOWNLOAD';
      const raw = err instanceof Error ? err.message : String(err);
      stateMachine.setError(
        'Unable to initialize map download. Please check your connection and try again.',
        `Stage: ${stage}\nDiagnostic: ${raw}`,
        stage
      );
    }
  };

  const mountMapFromOpfs = async () => {
    if (!mapContainerRef.current) return;
    if (mapInstanceRef.current) {
      mapInstanceRef.current.remove();
      mapInstanceRef.current = null;
    }

    watchdogRef.current?.recordProgress('READING_STORAGE');
    stateMachine.setStage('READING_STORAGE');

    try {
      const file = await withTimeout(
        getBasemapFile(slug),
        10_000,
        'Reading offline map file from storage timed out.'
      );
      if (!file) {
        watchdogRef.current?.stop();
        stateMachine.setError(
          'Offline map file is not available. Please retry download.',
          'Stage: READING_STORAGE\nDiagnostic: Basemap file not found in storage.',
          'READING_STORAGE'
        );
        return;
      }

      watchdogRef.current?.recordProgress('INITIALIZING_MAP');
      stateMachine.setStage('INITIALIZING_MAP');

      watchdogRef.current?.recordProgress('MAP_MOUNTING');
      stateMachine.setStage('MAP_MOUNTING');

      const map = initOfflineMap({
        container: mapContainerRef.current,
        file,
        styleUrl: '/map-style-dark.json',
        mountTimeoutMs: 20_000,
        onLoad: (loadedMap) => {
          watchdogRef.current?.stop();
          mapInstanceRef.current = loadedMap;
          stateMachine.setReady();
          onMapLoaded?.(loadedMap);
        },
        onError: (err) => {
          watchdogRef.current?.stop();
          stateMachine.setError(
            'Unable to display offline map. Please check your connection and try again.',
            `Stage: MAP_MOUNTING\nDiagnostic: ${err.message}`,
            'MAP_MOUNTING'
          );
        },
        onTimeout: () => {
          watchdogRef.current?.stop();
          if (mapInstanceRef.current) {
            mapInstanceRef.current.remove();
            mapInstanceRef.current = null;
          }
          stateMachine.setError(
            'Map setup stalled (stage: MAP_MOUNTING). Please tap Retry.',
            'Stage: MAP_MOUNTING\nDiagnostic: MapLibre failed to load style and tiles within 20s.',
            'MAP_MOUNTING'
          );
        },
      });
      mapInstanceRef.current = map;
    } catch (err: unknown) {
      watchdogRef.current?.stop();
      const raw = err instanceof Error ? err.message : String(err);
      stateMachine.setError(
        'Unable to load offline map from storage. Please retry download.',
        `Stage: READING_STORAGE\nDiagnostic: ${raw}`,
        'READING_STORAGE'
      );
    }
  };

  useEffect(() => {
    let isCancelled = false;

    const checkAndInitialize = async () => {
      const isCached = await checkBasemapInstalled(slug);
      if (isCancelled) return;

      if (isCached) {
        // Returning visit: instant render from OPFS, no download flash
        stateMachine.setCached();
        watchdogRef.current?.reset('READING_STORAGE');
        watchdogRef.current?.start(handleStall);
        await mountMapFromOpfs();
      } else {
        // First run: download PMTiles extract with progress
        await startWorkerDownload();
      }
    };

    checkAndInitialize();

    return () => {
      isCancelled = true;
      watchdogRef.current?.stop();
      releaseWakeLock();
      if (workerRef.current) {
        workerRef.current.terminate();
        workerRef.current = null;
      }
      if (mapInstanceRef.current) {
        mapInstanceRef.current.remove();
        mapInstanceRef.current = null;
      }
    };
  }, [slug]);

  const handleRetry = () => {
    watchdogRef.current?.reset('STARTING_DOWNLOAD');
    startWorkerDownload();
  };

  return (
    <div
      class="basemap-view-wrapper"
      data-state={snapshot.state}
      aria-label="Offline NYC Basemap"
    >
      {/* MapLibre GL Canvas Container */}
      <div
        id="map-container"
        ref={mapContainerRef}
        class="map-viewport-canvas"
        tabIndex={-1}
      />

      {/* State Overlay: map-loading (First run download progress) */}
      {snapshot.state === 'map-loading' && (
        <div class="map-state-overlay" role="status" aria-live="polite">
          <div class="map-state-card map-loading-card">
            <div class="map-loading-beacon" aria-hidden="true">
              <div class="beacon-pulse" />
              <svg viewBox="0 0 48 48" width="36" height="36" fill="none">
                <polygon points="24,6 40,14 40,34 24,42 8,34 8,14" stroke="#00e5ff" stroke-width="2" />
                <circle cx="24" cy="24" r="8" stroke="#38bdf8" stroke-width="2" stroke-dasharray="3 3" />
                <circle cx="24" cy="24" r="3" fill="#00e5ff" />
              </svg>
            </div>

            <div class="map-state-badge">
              <span class="badge-dot badge-dot-loading" />
              <span>Downloading Map</span>
            </div>

            <h2 class="map-state-title">Downloading offline map</h2>
            <p class="map-state-desc">
              Preparing New York City vector basemap for offline navigation...
            </p>

            <div class="map-progress-container">
              <div
                class="map-progress-bar"
                role="progressbar"
                aria-valuenow={snapshot.percent}
                aria-valuemin={0}
                aria-valuemax={100}
              >
                <div
                  class="map-progress-fill"
                  style={{ width: `${snapshot.percent}%` }}
                />
              </div>
              <span class="map-progress-percent">{snapshot.percent}%</span>
            </div>
          </div>
        </div>
      )}

      {/* State Overlay: map-error (Failure with Retry button) */}
      {snapshot.state === 'map-error' && (
        <div class="map-state-overlay" role="alert">
          <div class="map-state-card map-error-card">
            <div class="map-error-beacon" aria-hidden="true">
              <svg viewBox="0 0 24 24" width="32" height="32" fill="none" stroke="#ef4444" stroke-width="2">
                <circle cx="12" cy="12" r="10" />
                <line x1="12" y1="8" x2="12" y2="12" />
                <line x1="12" y1="16" x2="12.01" y2="16" />
              </svg>
            </div>

            <div class="map-state-badge badge-error">
              <span class="badge-dot badge-dot-error" />
              <span>Map Error</span>
            </div>

            <h2 class="map-state-title">Unable to load offline map</h2>
            <p class="map-state-desc">
              {snapshot.errorMessage || 'Check your connection and try again.'}
            </p>

            {snapshot.errorDetails && (
              <details class="map-error-details" style={{ marginTop: '1rem', marginBottom: '1rem', fontSize: '0.85rem', color: '#9ca3af', textAlign: 'left' }}>
                <summary style={{ cursor: 'pointer', marginBottom: '0.5rem' }}>Error Details</summary>
                <div style={{ padding: '0.5rem', background: 'rgba(0,0,0,0.2)', borderRadius: '4px', whiteSpace: 'pre-wrap', wordBreak: 'break-word', fontFamily: 'monospace' }}>
                  {snapshot.errorDetails}
                </div>
              </details>
            )}

            <button
              type="button"
              class="map-retry-btn"
              onClick={handleRetry}
            >
              Retry
            </button>
          </div>
        </div>
      )}
    </div>
  );
}
