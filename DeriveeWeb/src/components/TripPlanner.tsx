import { useState, useEffect, useMemo, useRef } from 'preact/hooks';
import type {
  StopItem,
  RoutingSegment,
  RoutingWorkerIncomingMessage,
  RoutingWorkerOutgoingMessage,
} from '../types/routing';
import { describeItinerary } from '../utils/itineraryDisplay';


interface TripPlannerProps {
  isInstalled: boolean;
}

export function TripPlanner({ isInstalled }: TripPlannerProps) {
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

  // Routing state
  const [isRouting, setIsRouting] = useState<boolean>(false);
  const [routeResult, setRouteResult] = useState<RoutingSegment[] | null>(null);
  const [routeError, setRouteError] = useState<string | null>(null);

  const originContainerRef = useRef<HTMLDivElement | null>(null);
  const destContainerRef = useRef<HTMLDivElement | null>(null);

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
      } else if (data.type === 'ERROR') {
        setEngineStatus('error');
        setEngineError(data.message);
        setIsRouting(false);
      } else if (data.type === 'RESULT') {
        setIsRouting(false);
        setRouteResult(data.segments);
        if (data.segments.length === 0) {
          setRouteError('No route found between selected stops at this departure time.');
        } else {
          setRouteError(null);
        }
      }
    };

    routingWorker.onerror = (err) => {
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

  const handleSelectOrigin = (stop: StopItem) => {
    setSelectedOrigin(stop);
    setOriginInput(stop.name);
    setShowOriginDropdown(false);
    setRouteResult(null);
  };

  const handleSelectDest = (stop: StopItem) => {
    setSelectedDest(stop);
    setDestInput(stop.name);
    setShowDestDropdown(false);
    setRouteResult(null);
  };

  const handleSwapStops = () => {
    const tempStop = selectedOrigin;
    const tempInput = originInput;
    setSelectedOrigin(selectedDest);
    setOriginInput(destInput);
    setSelectedDest(tempStop);
    setDestInput(tempInput);
    setRouteResult(null);
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
    setRouteResult(null);
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

  const handleRoute = () => {
    if (!worker || !selectedOrigin || !selectedDest || engineStatus !== 'ready' || isRouting) {
      return;
    }
    setIsRouting(true);
    setRouteResult(null);
    setRouteError(null);

    const depSec = getDepartureSeconds(departureTime);
    const msg: RoutingWorkerIncomingMessage = {
      type: 'ROUTE',
      origin_stop_id: selectedOrigin.id,
      dest_stop_id: selectedDest.id,
      departure_timestamp: depSec,
    };
    worker.postMessage(msg);
  };

  const formatTime = (sec: number): string => {
    const h = Math.floor(sec / 3600) % 24;
    const m = Math.floor((sec % 3600) / 60);
    return `${h.toString().padStart(2, '0')}:${m.toString().padStart(2, '0')}`;
  };

  const displayLegs = useMemo(() => {
    if (!routeResult) return [];
    return describeItinerary(routeResult, stopsMap);
  }, [routeResult, stopsMap]);


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
                  setRouteResult(null);
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
                  setRouteResult(null);
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

      {/* Routing Error Notice */}
      {routeError && (
        <div class="itinerary-error-box">
          <span>⚠️ {routeError}</span>
        </div>
      )}

      {/* Itinerary Results */}
      {routeResult && routeResult.length > 0 && (
        <div class="itinerary-results-container">
          <div class="itinerary-summary-header">
            <div class="summary-route-endpoints">
              <span class="summary-endpoint-name">
                {selectedOrigin?.name || stopsMap.get(routeResult[0].board_stop_id)?.name}
              </span>
              <span class="summary-arrow">➔</span>
              <span class="summary-endpoint-name">
                {selectedDest?.name ||
                  stopsMap.get(routeResult[routeResult.length - 1].exit_stop_id)?.name}
              </span>
            </div>

            <div class="summary-stats-bar">
              <span class="summary-time">
                {formatTime(routeResult[0].departure_time)} –{' '}
                {formatTime(routeResult[routeResult.length - 1].arrival_time)}
              </span>
              <span class="summary-dot">•</span>
              <span class="summary-duration">
                {Math.max(
                  1,
                  Math.round(
                    (routeResult[routeResult.length - 1].arrival_time -
                      routeResult[0].departure_time) /
                      60
                  )
                )}{' '}
                min
              </span>
              <span class="summary-dot">•</span>
              <span class="summary-legs-count">
                {routeResult.length} {routeResult.length === 1 ? 'leg' : 'legs'}
              </span>
            </div>
          </div>

          <div class="itinerary-legs-list">
            {displayLegs.map((legModel, idx) => {
              if (legModel.kind === 'start') {
                return (
                  <div key={idx} class="itinerary-compact-row itinerary-compact-start">
                    <span class="compact-marker marker-board" />
                    <span class="itinerary-compact-text">Start at {legModel.station}</span>
                    <span class="itinerary-compact-time">{formatTime(legModel.time)}</span>
                  </div>
                );
              }

              if (legModel.kind === 'arrive') {
                return (
                  <div key={idx} class="itinerary-compact-row itinerary-compact-arrive">
                    <span class="compact-marker marker-exit" />
                    <span class="itinerary-compact-text">Arrive at {legModel.station}</span>
                    <span class="itinerary-compact-time">{formatTime(legModel.time)}</span>
                  </div>
                );
              }

              return (
                <div key={idx} class="itinerary-leg-card">
                  <div class="leg-card-header">
                    <span class="leg-index-badge">Leg {idx + 1}</span>
                    <span
                      class={`leg-mode-pill ${
                        legModel.isTransfer ? 'mode-pill-walk' : 'mode-pill-transit'
                      }`}
                    >
                      {legModel.isTransfer ? (
                        <>🚶 Walk / Transfer</>
                      ) : (
                        <>🚇 Route {legModel.routeId}</>
                      )}
                    </span>
                    <span class="leg-duration-tag">
                      {legModel.durationMinutes > 0
                        ? `${legModel.durationMinutes} min`
                        : '< 1 min'}
                    </span>
                  </div>

                  <div class="leg-stops-flow">
                    <div class="leg-stop-row">
                      <div class="leg-stop-marker marker-board" />
                      <div class="leg-stop-details">
                        <span class="leg-stop-name">{legModel.boardStopName}</span>
                        <span class="leg-stop-time">{formatTime(legModel.departureTime)}</span>
                      </div>
                    </div>

                    <div class="leg-connector-line" />

                    <div class="leg-stop-row">
                      <div class="leg-stop-marker marker-exit" />
                      <div class="leg-stop-details">
                        <span class="leg-stop-name">{legModel.exitStopName}</span>
                        <span class="leg-stop-time">{formatTime(legModel.arrivalTime)}</span>
                      </div>
                    </div>
                  </div>

                  {legModel.transferDistanceM > 0 && legModel.isTransfer && (
                    <div class="leg-transfer-distance">
                      Transfer distance: ~{legModel.transferDistanceM} m
                    </div>
                  )}
                </div>
              );
            })}
          </div>
        </div>
      )}
    </div>
  );
}
