import { useState, useEffect, useMemo, useRef } from 'preact/hooks';
import type {
  StopItem,
  RoutingSegment,
  RoutingWorkerIncomingMessage,
  RoutingWorkerOutgoingMessage,
  RoutingProfile,
} from '../types/routing';
import { RouteComparisonView } from './RouteComparisonView';
import {
  executeDualProfileRouting,
  buildRankedItineraries,
} from '../utils/routeComparison';
import { RoutingQueryWatchdog } from '../utils/tabSuspension';

interface TripPlannerProps {
  isInstalled: boolean;
  onRoutesFound?: () => void;
}

export function TripPlanner({ isInstalled, onRoutesFound }: TripPlannerProps) {
  // Worker & Engine state
  const [worker, setWorker] = useState<Worker | null>(null);
  const [engineStatus, setEngineStatus] = useState<'warming_up' | 'ready' | 'error'>('warming_up');
  const [loadTimeMs, setLoadTimeMs] = useState<number | null>(null);
  const [engineError, setEngineError] = useState<string | null>(null);

  // Stop data from stops.json
  const [stops, setStops] = useState<StopItem[]>([]);
  const [stopsMap, setStopsMap] = useState<Map<number, StopItem>>(new Map());

  // Search input state
  const [originInput, setOriginInput] = useState<string>('');
  const [destInput, setDestInput] = useState<string>('');
  const [selectedOrigin, setSelectedOrigin] = useState<StopItem | null>(null);
  const [selectedDest, setSelectedDest] = useState<StopItem | null>(null);
  const [showOriginDropdown, setShowOriginDropdown] = useState<boolean>(false);
  const [showDestDropdown, setShowDestDropdown] = useState<boolean>(false);
  const [departureTime, setDepartureTime] = useState<string>('08:00');

  // Screen 4B Dual-Profile Routing State
  const [isRouting, setIsRouting] = useState<boolean>(false);
  const [fastestSegments, setFastestSegments] = useState<RoutingSegment[] | null>(null);
  const [fewestTransfersSegments, setFewestTransfersSegments] = useState<RoutingSegment[] | null>(null);
  const [activeProfile, setActiveProfile] = useState<RoutingProfile>('fastest');
  const [hasQueried, setHasQueried] = useState<boolean>(false);
  const [routeError, setRouteError] = useState<string | null>(null);


  const originContainerRef = useRef<HTMLDivElement | null>(null);
  const destContainerRef = useRef<HTMLDivElement | null>(null);
  const routingWatchdogRef = useRef<RoutingQueryWatchdog | null>(null);

  // 1. Fetch stops.json offline
  useEffect(() => {
    let isMounted = true;
    fetch('/data/stops.json')
      .then((res) => {
        if (!res.ok) throw new Error(`HTTP ${res.status}`);
        return res.json();
      })
      .then((data: StopItem[]) => {
        if (!isMounted) return;
        setStops(data);
        const map = new Map<number, StopItem>();
        for (const item of data) {
          map.set(item.id, item);
        }
        setStopsMap(map);
      })
      .catch((err) => {
        // eslint-disable-next-line no-console
        console.error('[TripPlanner] Failed to load stops.json:', err);
      });

    return () => {
      isMounted = false;
    };
  }, []);

  // 2. Manage Routing Worker lifecycle (lazy on installed, terminate on unmount)
  useEffect(() => {
    if (!isInstalled) return;

    setEngineStatus('warming_up');
    setEngineError(null);

    const routingWorker = new Worker(
      new URL('../workers/routing.worker.ts', import.meta.url)
    );

    routingWorker.onmessage = (event: MessageEvent<RoutingWorkerOutgoingMessage>) => {
      const data = event.data;
      if (data.type === 'READY') {
        setEngineStatus('ready');
        setLoadTimeMs(data.loadTimeMs);
      } else if (data.type === 'ERROR' && data.queryId === undefined) {
        routingWatchdogRef.current?.stop();
        routingWatchdogRef.current = null;
        setEngineStatus('error');
        setEngineError(data.message);
        setIsRouting(false);
      }
    };


    routingWorker.onerror = (err) => {
      routingWatchdogRef.current?.stop();
      routingWatchdogRef.current = null;
      // eslint-disable-next-line no-console
      console.error('[TripPlanner] Worker thread error:', err);
      setEngineStatus('error');
      setEngineError(err.message || 'Routing worker error');
      setIsRouting(false);
    };

    const initMsg: RoutingWorkerIncomingMessage = { type: 'INIT' };
    routingWorker.postMessage(initMsg);
    setWorker(routingWorker);

    return () => {
      routingWorker.terminate();
      setWorker(null);
      setEngineStatus('warming_up');
      if (routingWatchdogRef.current) {
        routingWatchdogRef.current.stop();
        routingWatchdogRef.current = null;
      }
    };
  }, [isInstalled]);

  // Click outside listener for autocomplete dropdowns
  useEffect(() => {
    const handleClickOutside = (e: MouseEvent) => {
      if (
        originContainerRef.current &&
        !originContainerRef.current.contains(e.target as Node)
      ) {
        setShowOriginDropdown(false);
      }
      if (
        destContainerRef.current &&
        !destContainerRef.current.contains(e.target as Node)
      ) {
        setShowDestDropdown(false);
      }
    };
    document.addEventListener('mousedown', handleClickOutside);
    return () => {
      document.removeEventListener('mousedown', handleClickOutside);
    };
  }, []);

  // Filter autocomplete suggestions (deduped by stop name)
  const originSuggestions = useMemo(() => {
    if (
      !originInput ||
      originInput.trim().length < 2 ||
      (selectedOrigin && originInput === selectedOrigin.name)
    ) {
      return [];
    }
    const q = originInput.trim().toLowerCase();
    const matches: StopItem[] = [];
    const seen = new Set<string>();
    for (const s of stops) {
      if (s.name.toLowerCase().includes(q)) {
        if (!seen.has(s.name)) {
          seen.add(s.name);
          matches.push(s);
          if (matches.length >= 8) break;
        }
      }
    }
    return matches;
  }, [originInput, stops, selectedOrigin]);

  const destSuggestions = useMemo(() => {
    if (
      !destInput ||
      destInput.trim().length < 2 ||
      (selectedDest && destInput === selectedDest.name)
    ) {
      return [];
    }
    const q = destInput.trim().toLowerCase();
    const matches: StopItem[] = [];
    const seen = new Set<string>();
    for (const s of stops) {
      if (s.name.toLowerCase().includes(q)) {
        if (!seen.has(s.name)) {
          seen.add(s.name);
          matches.push(s);
          if (matches.length >= 8) break;
        }
      }
    }
    return matches;
  }, [destInput, stops, selectedDest]);

  const resetRoutes = () => {
    setFastestSegments(null);
    setFewestTransfersSegments(null);
    setRouteError(null);
    setHasQueried(false);
  };

  const handleSelectOrigin = (stop: StopItem) => {
    setSelectedOrigin(stop);
    setOriginInput(stop.name);
    setShowOriginDropdown(false);
    resetRoutes();
  };

  const handleSelectDest = (stop: StopItem) => {
    setSelectedDest(stop);
    setDestInput(stop.name);
    setShowDestDropdown(false);
    resetRoutes();
  };

  const handleSwapStops = () => {
    const tempStop = selectedOrigin;
    const tempInput = originInput;
    setSelectedOrigin(selectedDest);
    setOriginInput(destInput);
    setSelectedDest(tempStop);
    setDestInput(tempInput);
    resetRoutes();
  };

  const handleApplyPreset = (origName: string, dstName: string) => {
    const o = stops.find((s) => s.name.toLowerCase().includes(origName.toLowerCase()));
    const d = stops.find((s) => s.name.toLowerCase().includes(dstName.toLowerCase()));
    if (o) {
      setSelectedOrigin(o);
      setOriginInput(o.name);
    }
    if (d) {
      setSelectedDest(d);
      setDestInput(d.name);
    }
    resetRoutes();
  };

  const getDepartureSeconds = (timeStr: string): number => {
    const parts = timeStr.split(':');
    if (parts.length === 2) {
      const h = parseInt(parts[0], 10);
      const m = parseInt(parts[1], 10);
      if (!isNaN(h) && !isNaN(m)) {
        return h * 3600 + m * 60;
      }
    }
    return 28800; // 8:00 AM fallback
  };

  // Monitor tab backgrounding and suspension during route query calculation
  useEffect(() => {
    let lastHidden = 0;

    const handleVisibilityChange = () => {
      if (typeof document === 'undefined') return;

      if (document.visibilityState === 'hidden') {
        lastHidden = Date.now();
      } else if (document.visibilityState === 'visible') {
        const suspendedMs = lastHidden > 0 ? Date.now() - lastHidden : 0;
        lastHidden = 0;

        if (isRouting) {
          routingWatchdogRef.current?.handleResume(suspendedMs);
        }
      }
    };

    document.addEventListener('visibilitychange', handleVisibilityChange);
    return () => {
      document.removeEventListener('visibilitychange', handleVisibilityChange);
    };
  }, [isRouting]);

  const handleRoute = async () => {
    if (!worker || !selectedOrigin || !selectedDest || engineStatus !== 'ready' || isRouting) {
      return;
    }
    setIsRouting(true);
    setFastestSegments(null);
    setFewestTransfersSegments(null);
    setRouteError(null);
    setHasQueried(true);

    const watchdog = new RoutingQueryWatchdog(8_000, (reason) => {
      setIsRouting(false);
      setRouteError(reason);
    });
    routingWatchdogRef.current = watchdog;
    watchdog.start();

    const depSec = getDepartureSeconds(departureTime);

    try {
      const { fastest, fewestTransfers } = await executeDualProfileRouting(
        worker,
        selectedOrigin.id,
        selectedDest.id,
        depSec
      );

      setFastestSegments(fastest);
      setFewestTransfersSegments(fewestTransfers);

      if (fastest.length === 0 && fewestTransfers.length === 0) {
        setRouteError('No route found between selected stops at this departure time.');
      } else {
        setRouteError(null);
        onRoutesFound?.();
      }
    } catch (err: any) {
      setRouteError(err?.message || 'Failed to compute routes');
    } finally {
      routingWatchdogRef.current?.stop();
      routingWatchdogRef.current = null;
      setIsRouting(false);
    }
  };

  const rankedCards = useMemo(() => {
    return buildRankedItineraries(fastestSegments, fewestTransfersSegments, activeProfile);
  }, [fastestSegments, fewestTransfersSegments, activeProfile]);


  return (
    <div class="trip-planner-card">
      {/* Engine Status Banner */}
      <div class="trip-planner-status-bar">
        {engineStatus === 'warming_up' && (
          <div class="engine-status engine-status-warming">
            <span class="engine-dot engine-dot-pulse" />
            <span>Hydrating WASM routing engine from OPFS...</span>
          </div>
        )}
        {engineStatus === 'ready' && (
          <div class="engine-status engine-status-ready">
            <span class="engine-dot engine-dot-green" />
            <span>
              Engine Ready{' '}
              {loadTimeMs !== null && loadTimeMs > 0 && `(loaded in ${loadTimeMs}ms)`}
            </span>
          </div>
        )}
        {engineStatus === 'error' && (
          <div class="engine-status engine-status-error">
            <span class="engine-dot engine-dot-red" />
            <span>Engine Error: {engineError || 'Failed to initialize WASM engine'}</span>
          </div>
        )}
      </div>

      <h2 class="trip-planner-title">Offline Transit Router</h2>
      <p class="trip-planner-subtitle">
        C++ RAPTOR engine pathfinding running 100% offline in WebAssembly
      </p>

      {/* Origin & Destination Inputs */}
      <div class="trip-inputs-container">
        {/* Origin Input */}
        <div class="stop-input-group" ref={originContainerRef}>
          <label class="stop-input-label" htmlFor="origin-stop-input">
            <span class="stop-dot stop-dot-origin" />
            <span>Origin</span>
          </label>
          <div class="stop-input-wrapper">
            <input
              id="origin-stop-input"
              type="text"
              class="stop-text-input"
              placeholder="Origin stop (e.g. Times Sq)"
              value={originInput}
              onInput={(e) => {
                const val = (e.target as HTMLInputElement).value;
                setOriginInput(val);
                setShowOriginDropdown(true);
                if (selectedOrigin && val !== selectedOrigin.name) {
                  setSelectedOrigin(null);
                  resetRoutes();
                }
              }}
              onFocus={() => setShowOriginDropdown(true)}
            />
            {originInput && (
              <button
                type="button"
                class="stop-clear-btn"
                onClick={() => {
                  setOriginInput('');
                  setSelectedOrigin(null);
                  resetRoutes();
                }}
                aria-label="Clear origin"
              >
                ✕
              </button>
            )}
          </div>

          {showOriginDropdown && originSuggestions.length > 0 && (
            <div class="stop-autocomplete-dropdown" role="listbox">
              {originSuggestions.map((stop) => (
                <button
                  key={stop.id}
                  type="button"
                  class="stop-suggestion-item"
                  role="option"
                  aria-selected={selectedOrigin?.id === stop.id}
                  onClick={() => handleSelectOrigin(stop)}
                >
                  <span class="stop-suggestion-name">{stop.name}</span>
                  <span class="stop-suggestion-id">#{stop.id}</span>
                </button>
              ))}
            </div>
          )}
        </div>

        {/* Swap Button */}
        <div class="trip-swap-container">
          <button
            type="button"
            class="trip-swap-btn"
            onClick={handleSwapStops}
            title="Swap origin and destination"
            aria-label="Swap origin and destination"
          >
            ⇅
          </button>
        </div>

        {/* Destination Input */}
        <div class="stop-input-group" ref={destContainerRef}>
          <label class="stop-input-label" htmlFor="dest-stop-input">
            <span class="stop-dot stop-dot-dest" />
            <span>Destination</span>
          </label>
          <div class="stop-input-wrapper">
            <input
              id="dest-stop-input"
              type="text"
              class="stop-text-input"
              placeholder="Destination stop (e.g. Atlantic Av)"
              value={destInput}
              onInput={(e) => {
                const val = (e.target as HTMLInputElement).value;
                setDestInput(val);
                setShowDestDropdown(true);
                if (selectedDest && val !== selectedDest.name) {
                  setSelectedDest(null);
                  resetRoutes();
                }
              }}
              onFocus={() => setShowDestDropdown(true)}
            />
            {destInput && (
              <button
                type="button"
                class="stop-clear-btn"
                onClick={() => {
                  setDestInput('');
                  setSelectedDest(null);
                  resetRoutes();
                }}
                aria-label="Clear destination"
              >
                ✕
              </button>
            )}
          </div>

          {showDestDropdown && destSuggestions.length > 0 && (
            <div class="stop-autocomplete-dropdown" role="listbox">
              {destSuggestions.map((stop) => (
                <button
                  key={stop.id}
                  type="button"
                  class="stop-suggestion-item"
                  role="option"
                  aria-selected={selectedDest?.id === stop.id}
                  onClick={() => handleSelectDest(stop)}
                >
                  <span class="stop-suggestion-name">{stop.name}</span>
                  <span class="stop-suggestion-id">#{stop.id}</span>
                </button>
              ))}
            </div>
          )}
        </div>

        {/* Departure Time & Quick Presets */}
        <div class="trip-options-row">
          <div class="trip-time-selector">
            <label class="trip-time-label" htmlFor="trip-dep-time">
              Departure:
            </label>
            <input
              id="trip-dep-time"
              type="time"
              class="trip-time-input"
              value={departureTime}
              onInput={(e) => setDepartureTime((e.target as HTMLInputElement).value)}
            />
          </div>

          <div class="quick-presets-group">
            <span class="quick-preset-label">Test Preset:</span>
            <button
              type="button"
              class="quick-preset-btn"
              onClick={() => handleApplyPreset('Times Sq', 'Atlantic Av')}
            >
              Times Sq ➔ Atlantic Av
            </button>
          </div>
        </div>

        {/* Route Action Button */}
        <button
          type="button"
          class="installer-primary-btn trip-route-btn"
          disabled={
            !selectedOrigin ||
            !selectedDest ||
            selectedOrigin.id === selectedDest.id ||
            engineStatus !== 'ready' ||
            isRouting
          }
          onClick={handleRoute}
        >
          {isRouting ? (
            <span class="btn-spinner-content">
              <span class="btn-spinner" />
              <span>Routing offline trip...</span>
            </span>
          ) : (
            'Route Trip'
          )}
        </button>
      </div>

      {/* Screen 4B Route Comparison & Profile Cards */}
      <RouteComparisonView
        rankedCards={rankedCards}
        activeProfile={activeProfile}
        onSelectProfile={setActiveProfile}
        stopsMap={stopsMap}
        isRouting={isRouting}
        routeError={routeError}
        hasQueried={hasQueried}
      />
    </div>
  );
}
