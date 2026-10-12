import { useState, useEffect, useMemo, useRef } from 'preact/hooks';
import type {
  StopItem,
  RouteItem,
  RoutingSegment,
  RoutingWorkerIncomingMessage,
  RoutingWorkerOutgoingMessage,
  RoutingProfile,
  RoutePatternEntry,
} from '../types/routing';
import { RouteComparisonView } from './RouteComparisonView';
import {
  executeDualProfileRouting,
  buildRankedItineraries,
  createRankedItinerary,
  computeDepartureSeconds,
} from '../utils/routeComparison';
import { RoutingQueryWatchdog } from '../utils/tabSuspension';
import { createRoutesMap } from '../utils/routeBadge';
import { CityPicker } from './CityPicker';
import { findBikeCandidates, type BikeStation, type TransitStop } from '../utils/bikeCatchment';
import { getCityDirectory } from '../utils/opfs';
import { searchPlaces, findNearestStopByCoordinates, type GeocodedPlace } from '../utils/geocoder';
import type { CityPickerState } from '../types/cityPicker';
import { reduceCityPickerState, fetchCitiesManifest } from '../utils/cityPicker';
import type { WorkerToMainMessage } from '../types/pack';
import { LegDetailView } from './LegDetailView';
import type { TransitLegDisplay } from '../utils/itineraryDisplay';
import type { JourneyHighlightState } from './TransitOverlays';

interface TripPlannerProps {
  isInstalled: boolean;
  onRoutesFound?: () => void;
  onFocusedRouteIdChange?: (routeId: string | null) => void;
  onSelectLeg?: (
    leg: TransitLegDisplay | null,
    highlight?: JourneyHighlightState | null
  ) => void;
}

export function TripPlanner({
  isInstalled,
  onRoutesFound,
  onFocusedRouteIdChange,
  onSelectLeg,
}: TripPlannerProps) {
  // Worker & Engine state
  const [worker, setWorker] = useState<Worker | null>(null);
  const [engineStatus, setEngineStatus] = useState<'warming_up' | 'ready' | 'error'>('warming_up');
  const [loadTimeMs, setLoadTimeMs] = useState<number | null>(null);
  const [engineError, setEngineError] = useState<string | null>(null);
  const [patterns, setPatterns] = useState<RoutePatternEntry[] | null>(null);

  // Stop data from stops.json
  const [stops, setStops] = useState<StopItem[]>([]);
  const [stopsMap, setStopsMap] = useState<Map<number, StopItem>>(new Map());
  // GTFS ID -> timetable index mapping (engine uses sorted GTFS ID order)
  const [stopIndexMap, setStopIndexMap] = useState<Map<string, number>>(new Map());

  // Helper: get timetable index for a stop (engine expects sorted GTFS ID order)
  const getTimetableIndex = (stop: StopItem): number => {
    if (stop.gtfs_id) {
      const idx = stopIndexMap.get(stop.gtfs_id);
      if (idx !== undefined) return idx;
    }
    // Fallback to numeric id (may not match, but better than crashing)
    return stop.id;
  };

  // Route metadata from routes.json
  const [routesMap, setRoutesMap] = useState<Map<string, RouteItem>>(new Map());

  // Search input state
  const [originInput, setOriginInput] = useState<string>('');
  const [destInput, setDestInput] = useState<string>('');
  const [selectedOrigin, setSelectedOrigin] = useState<StopItem | null>(null);
  const [selectedDest, setSelectedDest] = useState<StopItem | null>(null);
  const [showOriginDropdown, setShowOriginDropdown] = useState<boolean>(false);
  const [showDestDropdown, setShowDestDropdown] = useState<boolean>(false);
  const [originPlaces, setOriginPlaces] = useState<GeocodedPlace[]>([]);
  const [destPlaces, setDestPlaces] = useState<GeocodedPlace[]>([]);
  const [includeBike, setIncludeBike] = useState<boolean>(false);
  const [bikeComparison, setBikeComparison] = useState<{
    bikeStationName: string;
    bikeAccessMin: number;
    pickupDockName: string;
    savingsMin: number; // positive = saves time, negative = slower
    walkTotalMin: number;
    bikeTotalMin: number;
  } | null>(null);
  const [departureTime, setDepartureTime] = useState<string>(() => {
    const d = new Date();
    return `${String(d.getHours()).padStart(2, '0')}:${String(d.getMinutes()).padStart(2, '0')}`;
  });
  const [departureMode, setDepartureMode] = useState<'now' | 'depart_at'>('now');

  // Debounced place search (Nominatim) for origin/destination inputs
  useEffect(() => {
    if (!originInput || originInput.trim().length < 3) {
      setOriginPlaces([]);
      return;
    }
    const timer = setTimeout(async () => {
      try {
        const places = await searchPlaces(originInput, { limit: 3 });
        setOriginPlaces(places);
      } catch { setOriginPlaces([]); }
    }, 500);
    return () => clearTimeout(timer);
  }, [originInput]);

  useEffect(() => {
    if (!destInput || destInput.trim().length < 3) {
      setDestPlaces([]);
      return;
    }
    const timer = setTimeout(async () => {
      try {
        const places = await searchPlaces(destInput, { limit: 3 });
        setDestPlaces(places);
      } catch { setDestPlaces([]); }
    }, 500);
    return () => clearTimeout(timer);
  }, [destInput]);

  // Screen 4B Dual-Profile Routing State
  const [isRouting, setIsRouting] = useState<boolean>(false);
  const [fastestSegments, setFastestSegments] = useState<RoutingSegment[] | null>(null);
  const [fewestTransfersSegments, setFewestTransfersSegments] = useState<RoutingSegment[] | null>(null);
  const [lessWalkingSegments, setLessWalkingSegments] = useState<RoutingSegment[] | null>(null);
  const [activeProfile, setActiveProfile] = useState<RoutingProfile>('fastest');
  const [hasQueried, setHasQueried] = useState<boolean>(false);
  const [routeError, setRouteError] = useState<string | null>(null);
  const [selectedLeg, setSelectedLeg] = useState<TransitLegDisplay | null>(null);


  const originContainerRef = useRef<HTMLDivElement | null>(null);
  const destContainerRef = useRef<HTMLDivElement | null>(null);
  const routingWatchdogRef = useRef<RoutingQueryWatchdog | null>(null);
  const isRoutingRef = useRef<boolean>(false);
  const pendingRouteRef = useRef<{ mode: 'now' | 'depart_at'; time: string } | null>(null);

  // 1. Fetch stops.json and routes.json offline
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

    // Load stop_index.json (GTFS ID -> timetable index)
    fetch('/data/stop_index.json')
      .then((res) => {
        if (!res.ok) throw new Error(`HTTP ${res.status}`);
        return res.json();
      })
      .then((data: Record<string, number>) => {
        if (!isMounted) return;
        setStopIndexMap(new Map(Object.entries(data)));
      })
      .catch((err) => {
        // eslint-disable-next-line no-console
        console.error('[TripPlanner] Failed to load stop_index.json:', err);
      });

    fetch('/data/routes.json')
      .then((res) => {
        if (!res.ok) throw new Error(`HTTP ${res.status}`);
        return res.json();
      })
      .then((data: Record<string, RouteItem>) => {
        if (!isMounted) return;
        setRoutesMap(createRoutesMap(data));
      })
      .catch((err) => {
        // eslint-disable-next-line no-console
        console.error('[TripPlanner] Failed to load routes.json:', err);
      });

    return () => {
      isMounted = false;
    };
  }, []);

  // City Picker State (Wave M5c)
  const [cityPickerState, setCityPickerState] = useState<CityPickerState>({
    status: 'loading',
    activeCitySlug: 'nyc',
    cities: [],
    errorMessage: null,
    switchProgress: null,
  });

  const routingWorkerRef = useRef<Worker | null>(null);
  const installerWorkerRef = useRef<Worker | null>(null);

  const startRoutingWorker = (slug: string) => {
    if (routingWorkerRef.current) {
      routingWorkerRef.current.terminate();
      routingWorkerRef.current = null;
    }

    setEngineStatus('warming_up');
    setEngineError(null);

    const routingWorker = new Worker(
      new URL('../workers/routing.worker.ts', import.meta.url)
    );
    routingWorkerRef.current = routingWorker;

    routingWorker.onmessage = (event: MessageEvent<RoutingWorkerOutgoingMessage>) => {
      const data = event.data;
      if (data.type === 'READY') {
        setEngineStatus('ready');
        setLoadTimeMs(data.loadTimeMs);
        setPatterns(data.patterns ?? null);
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

    const initMsg: RoutingWorkerIncomingMessage = { type: 'INIT', city: slug };
    routingWorker.postMessage(initMsg);
    setWorker(routingWorker);
  };

  const loadCities = async () => {
    setCityPickerState((prev) => reduceCityPickerState(prev, { type: 'FETCH_START' }));
    try {
      const cities = await fetchCitiesManifest('/api/cities');
      setCityPickerState((prev) =>
        reduceCityPickerState(prev, { type: 'FETCH_SUCCESS', cities })
      );
    } catch (err: any) {
      setCityPickerState((prev) =>
        reduceCityPickerState(prev, {
          type: 'FETCH_ERROR',
          error: err?.message || 'Failed to load cities',
        })
      );
    }
  };

  // 2. Fetch cities manifest on mount
  useEffect(() => {
    loadCities();
  }, []);

  // 3. Manage Routing Worker lifecycle (lazy on installed, terminate on unmount)
  useEffect(() => {
    if (!isInstalled) return;

    startRoutingWorker(cityPickerState.activeCitySlug);

    return () => {
      if (routingWorkerRef.current) {
        routingWorkerRef.current.terminate();
        routingWorkerRef.current = null;
      }
      if (installerWorkerRef.current) {
        installerWorkerRef.current.terminate();
        installerWorkerRef.current = null;
      }
      setWorker(null);
      setEngineStatus('warming_up');
      if (routingWatchdogRef.current) {
        routingWatchdogRef.current.stop();
        routingWatchdogRef.current = null;
      }
    };
  }, [isInstalled]);

  // 4. Handle city switch flow (clear engine, install pack, re-hydrate)
  const handleSelectCity = (targetSlug: string) => {
    if (targetSlug === cityPickerState.activeCitySlug || cityPickerState.status === 'switching') {
      return;
    }

    const targetCity = cityPickerState.cities.find((c) => c.slug === targetSlug);
    const targetName = targetCity?.name || targetSlug.toUpperCase();

    setCityPickerState((prev) =>
      reduceCityPickerState(prev, { type: 'START_SWITCH', targetSlug, targetName })
    );

    // Clear current WASM engine instance and reset query state
    if (routingWorkerRef.current) {
      routingWorkerRef.current.terminate();
      routingWorkerRef.current = null;
      setWorker(null);
    }
    setEngineStatus('warming_up');
    resetRoutes();
    setSelectedOrigin(null);
    setSelectedDest(null);
    setOriginInput('');
    setDestInput('');

    // Spawn pack-installer worker
    if (installerWorkerRef.current) {
      installerWorkerRef.current.terminate();
      installerWorkerRef.current = null;
    }

    const installer = new Worker(
      new URL('../workers/pack-installer.worker.ts', import.meta.url),
      { type: 'module' }
    );
    installerWorkerRef.current = installer;

    installer.onmessage = (event: MessageEvent<WorkerToMainMessage>) => {
      const data = event.data;
      if (data.type === 'PROGRESS') {
        setCityPickerState((prev) =>
          reduceCityPickerState(prev, {
            type: 'SWITCH_PROGRESS',
            stage: data.stage,
            percent: data.percent,
            message: data.message,
          })
        );
      } else if (data.type === 'SUCCESS') {
        installer.terminate();
        installerWorkerRef.current = null;
        setCityPickerState((prev) =>
          reduceCityPickerState(prev, {
            type: 'SWITCH_SUCCESS',
            newActiveSlug: targetSlug,
          })
        );
        // Re-hydrate WASM engine with new city slug
        startRoutingWorker(targetSlug);
      } else if (data.type === 'ERROR') {
        installer.terminate();
        installerWorkerRef.current = null;
        setCityPickerState((prev) =>
          reduceCityPickerState(prev, {
            type: 'SWITCH_ERROR',
            error: data.message,
          })
        );
        setEngineStatus('error');
        setEngineError(data.message);
      }
    };

    installer.onerror = (err) => {
      installer.terminate();
      installerWorkerRef.current = null;
      setCityPickerState((prev) =>
        reduceCityPickerState(prev, {
          type: 'SWITCH_ERROR',
          error: err.message || 'Installer error',
        })
      );
      setEngineStatus('error');
      setEngineError(err.message || 'Pack installer error');
    };

    installer.postMessage({
      type: 'START_INSTALL',
      slug: targetSlug,
      packUrl: targetSlug === 'nyc' ? '/api/pack' : `/api/pack?city=${encodeURIComponent(targetSlug)}`,
    });
  };

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
  // Apple Maps pattern: subway/rail stations rank above bus stops; bus results capped
  const rankSuggestions = (query: string): StopItem[] => {
    const q = query.trim().toLowerCase();
    const stations: StopItem[] = [];
    const busStops: StopItem[] = [];
    const seen = new Set<string>();
    for (const s of stops) {
      if (!s.name.toLowerCase().includes(q)) continue;
      if (seen.has(s.name)) continue;
      seen.add(s.name);
      if (s.t === 'b') {
        if (busStops.length < 3) busStops.push(s);
      } else {
        if (stations.length < 8) stations.push(s);
      }
      if (stations.length >= 8 && busStops.length >= 3) break;
    }
    return [...stations, ...busStops].slice(0, 8);
  };

  const originSuggestions = useMemo(() => {
    if (
      !originInput ||
      originInput.trim().length < 2 ||
      (selectedOrigin && originInput === selectedOrigin.name)
    ) {
      return [];
    }
    return rankSuggestions(originInput);
  }, [originInput, stops, selectedOrigin]);

  const destSuggestions = useMemo(() => {
    if (
      !destInput ||
      destInput.trim().length < 2 ||
      (selectedDest && destInput === selectedDest.name)
    ) {
      return [];
    }
    return rankSuggestions(destInput);
  }, [destInput, stops, selectedDest]);

  const resetRoutes = () => {
    setFastestSegments(null);
    setFewestTransfersSegments(null);
    setLessWalkingSegments(null);
    setRouteError(null);
    setHasQueried(false);
    setSelectedLeg(null);
    onFocusedRouteIdChange?.(null);
    onSelectLeg?.(null);
  };

  const handleSelectLeg = (leg: TransitLegDisplay) => {
    setSelectedLeg(leg);
    const routeIdStr = leg.routeId ? String(leg.routeId) : null;
    onFocusedRouteIdChange?.(routeIdStr);
    onSelectLeg?.(leg);
  };

  const handleBackFromLegDetail = () => {
    setSelectedLeg(null);
    onFocusedRouteIdChange?.(null);
    onSelectLeg?.(null);
  };

  const handleSelectOrigin = (stop: StopItem) => {
    setSelectedOrigin(stop);
    setOriginInput(stop.name);
    setShowOriginDropdown(false);
    setOriginPlaces([]);
    resetRoutes();
  };

  const handleSelectOriginPlace = (place: GeocodedPlace) => {
    // Resolve place to nearest SUBWAY station (not bus stop — engine is subway-only for now)
    const subwayStops = stops.filter(s => s.t === 's');
    const nearest = findNearestStopByCoordinates(place.lat, place.lon, subwayStops.length > 0 ? subwayStops : stops);
    if (nearest) {
      setSelectedOrigin(nearest);
      setOriginInput(place.displayName);
      setShowOriginDropdown(false);
      setOriginPlaces([]);
      resetRoutes();
    }
  };

  const handleSelectDest = (stop: StopItem) => {
    setSelectedDest(stop);
    setDestInput(stop.name);
    setShowDestDropdown(false);
    setDestPlaces([]);
    resetRoutes();
  };

  const handleSelectDestPlace = (place: GeocodedPlace) => {
    const subwayStops = stops.filter(s => s.t === 's');
    const nearest = findNearestStopByCoordinates(place.lat, place.lon, subwayStops.length > 0 ? subwayStops : stops);
    if (nearest) {
      setSelectedDest(nearest);
      setDestInput(place.displayName);
      setShowDestDropdown(false);
      setDestPlaces([]);
      resetRoutes();
    }
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

  const handleRoute = async (modeOverride?: 'now' | 'depart_at', timeOverride?: string) => {
    if (!worker || !selectedOrigin || !selectedDest || engineStatus !== 'ready') {
      // Show why routing is blocked instead of silently returning
      if (engineStatus !== 'ready') {
        setRouteError(
          engineStatus === 'warming_up'
            ? 'Engine still loading — please wait.'
            : `Engine error: ${engineError || 'unknown'}. Try reopening the planner.`
        );
      } else if (!selectedOrigin || !selectedDest) {
        setRouteError('Select both origin and destination.');
      }
      return;
    }

    const mode = modeOverride ?? departureMode;
    const time = timeOverride ?? departureTime;

    if (isRoutingRef.current) {
      pendingRouteRef.current = { mode, time };
      return;
    }

    isRoutingRef.current = true;
    setIsRouting(true);
    setFastestSegments(null);
    setFewestTransfersSegments(null);
    setLessWalkingSegments(null);
    setRouteError(null);
    setHasQueried(true);

    const watchdog = new RoutingQueryWatchdog(8_000, (reason) => {
      setIsRouting(false);
      isRoutingRef.current = false;
      setRouteError(reason);
    });
    routingWatchdogRef.current = watchdog;
    watchdog.start();

    const depSec = computeDepartureSeconds(mode, time);

    try {
      let fastest: RoutingSegment[];
      let fewestTransfers: RoutingSegment[];
      let lessWalking: RoutingSegment[];

      if (includeBike) {
        // Bike-share enabled: dual RAPTOR — compare walk vs bike access honestly
        setBikeComparison(null);
        try {
          const [stopsRes, bikeData] = await Promise.all([
            fetch('/data/stops.json'),
            (async () => {
              const dir = await getCityDirectory('nyc');
              if (!dir) return null;
              try {
                const handle = await dir.getFileHandle('bikestations.json');
                const file = await handle.getFile();
                return JSON.parse(await file.text());
              } catch { return null; }
            })(),
          ]);

          // Always run walk routing first (baseline)
          const walkResult = await executeDualProfileRouting(
            worker, getTimetableIndex(selectedOrigin), getTimetableIndex(selectedDest), depSec
          );

          if (stopsRes.ok && bikeData?.stations) {
            const allStops = (await stopsRes.json()) as StopItem[];
            const bikeStations: BikeStation[] = bikeData.stations;
            const transitStops: TransitStop[] = allStops
              .filter(s => s.t === 's')
              .map(s => ({ id: String(s.id), name: s.name, lat: s.lat, lon: s.lon }));

            const candidates = findBikeCandidates(
              selectedOrigin.lat,
              selectedOrigin.lon,
              bikeStations,
              transitStops
            ).slice(0, 3);

            if (candidates.length > 0) {
              const best = candidates[0];
              const bikeAccessSec = Math.round(best.bikeTimeSeconds);
              const bikeDepSec = depSec + bikeAccessSec;
              // Map bike candidate stopId (numeric string) to timetable index via stopsMap
              const bikeStopIdNum = typeof best.stopId === 'string' ? parseInt(best.stopId) : best.stopId;
              const bikeStopItem = stopsMap.get(bikeStopIdNum);
              const bikeTimetableIdx = bikeStopItem ? getTimetableIndex(bikeStopItem) : bikeStopIdNum;
              const bikeResult = await executeDualProfileRouting(
                worker,
                bikeTimetableIdx,
                getTimetableIndex(selectedDest),
                bikeDepSec
              );

              // Compare total journey times (honest dual RAPTOR)
              const walkSegs = walkResult.fastest;
              const bikeSegs = bikeResult.fastest;
              if (walkSegs.length > 0 && bikeSegs.length > 0) {
                const walkTotalSec = walkSegs[walkSegs.length - 1].arrival_time - walkSegs[0].departure_time;
                const bikeTransitSec = bikeSegs[bikeSegs.length - 1].arrival_time - bikeSegs[0].departure_time;
                const bikeTotalSec = bikeAccessSec + bikeTransitSec;
                const savingsSec = walkTotalSec - bikeTotalSec;

                setBikeComparison({
                  bikeStationName: best.stopName,
                  bikeAccessMin: Math.round(bikeAccessSec / 60),
                  pickupDockName: best.pickupDockName,
                  savingsMin: Math.round(savingsSec / 60),
                  walkTotalMin: Math.round(walkTotalSec / 60),
                  bikeTotalMin: Math.round(bikeTotalSec / 60),
                });

                // Use whichever is actually faster
                if (bikeTotalSec < walkTotalSec) {
                  ({ fastest, fewestTransfers, lessWalking } = bikeResult);
                } else {
                  ({ fastest, fewestTransfers, lessWalking } = walkResult);
                }
              } else {
                ({ fastest, fewestTransfers, lessWalking } = walkResult);
              }
            } else {
              ({ fastest, fewestTransfers, lessWalking } = walkResult);
            }
          } else {
            ({ fastest, fewestTransfers, lessWalking } = walkResult);
          }
        } catch (bikeErr) {
          console.warn('[Bike] Routing failed, falling back to transit-only:', bikeErr);
          ({ fastest, fewestTransfers, lessWalking } = await executeDualProfileRouting(
            worker, getTimetableIndex(selectedOrigin), getTimetableIndex(selectedDest), depSec
          ));
        }
      } else {
        setBikeComparison(null);
        ({ fastest, fewestTransfers, lessWalking } = await executeDualProfileRouting(
          worker,
          getTimetableIndex(selectedOrigin),
          getTimetableIndex(selectedDest),
          depSec
        ));
      }

      setFastestSegments(fastest);
      setFewestTransfersSegments(fewestTransfers);
      setLessWalkingSegments(lessWalking);
      setRouteError(null);
      if (fastest.length > 0 || fewestTransfers.length > 0) {
        onRoutesFound?.();
      }
    } catch (err: any) {
      setRouteError(err?.message || 'Failed to compute routes');
    } finally {
      routingWatchdogRef.current?.stop();
      routingWatchdogRef.current = null;
      setIsRouting(false);
      isRoutingRef.current = false;

      if (pendingRouteRef.current) {
        const next = pendingRouteRef.current;
        pendingRouteRef.current = null;
        handleRoute(next.mode, next.time);
      }
    }
  };

  const rankedCards = useMemo(() => {
    if (activeProfile === 'less_walking') {
      if (!lessWalkingSegments || lessWalkingSegments.length === 0) return [];
      // Direct display for less_walking (no comparison dedup)
      return [createRankedItinerary(lessWalkingSegments, 'less_walking', ['less_walking'], false)];
    }
    return buildRankedItineraries(fastestSegments, fewestTransfersSegments, activeProfile);
  }, [fastestSegments, fewestTransfersSegments, lessWalkingSegments, activeProfile]);


  return (
    <div class="trip-planner-card">
      {/* Header & Engine Status */}
      <div class="trip-planner-header-row">
        <div class="trip-planner-title-group">
          <h2 class="trip-planner-title">Directions</h2>
          <p class="trip-planner-subtitle">Instant on-device routing across NYC</p>
        </div>
        <div class="trip-planner-status-bar">
          {engineStatus === 'warming_up' && (
            <div class="engine-status engine-status-warming">
              <span class="engine-dot engine-dot-pulse" />
              <span>Warming engine...</span>
            </div>
          )}
          {engineStatus === 'ready' && (
            <div class="engine-status engine-status-ready">
              <span class="engine-dot engine-dot-green" />
              <span>
                Offline Ready{' '}
                {loadTimeMs !== null && loadTimeMs > 0 && `(${loadTimeMs}ms)`}
              </span>
            </div>
          )}
          {engineStatus === 'error' && (
            <div class="engine-status engine-status-error">
              <span class="engine-dot engine-dot-red" />
              <span>{engineError || 'Engine error'}</span>
            </div>
          )}
        </div>
      </div>

      {/* City Picker / Pack Manager UI (Wave M5c) */}
      <CityPicker
        state={cityPickerState}
        onSelectCity={handleSelectCity}
        onRetry={loadCities}
      />

      {/* Origin & Destination Inputs */}
      {/* Mode filter pills: Subway active for MVP, Bus disabled. Bike is a supplement toggle. */}
      <div class="mode-filter-pills">
        <button type="button" class="mode-pill mode-pill-active" disabled>
          🚇 Subway
        </button>
        <button type="button" class="mode-pill mode-pill-disabled" title="Coming soon" disabled>
          🚌 Bus
        </button>
        <button
          type="button"
          class={`mode-pill ${includeBike ? 'mode-pill-active' : ''}`}
          title="Include bike-share for access/egress"
          onClick={() => setIncludeBike(!includeBike)}
        >
          🚲 Bike{includeBike ? ' ✓' : ''}
        </button>
      </div>
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
              placeholder="Where from? (e.g. Times Sq)"
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

          {showOriginDropdown && (originSuggestions.length > 0 || originPlaces.length > 0) && (
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
                  <span class="stop-suggestion-type">{stop.t === 'b' ? 'Bus stop' : 'Station'}</span>
                </button>
              ))}
              {originPlaces.map((place, i) => (
                <button
                  key={`place-${i}`}
                  type="button"
                  class="stop-suggestion-item place-suggestion-item"
                  role="option"
                  onClick={() => handleSelectOriginPlace(place)}
                >
                  <span class="stop-suggestion-name">📍 {place.displayName}</span>
                  <span class="stop-suggestion-type">Place</span>
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
              placeholder="Where to? (e.g. Atlantic Av)"
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

          {showDestDropdown && (destSuggestions.length > 0 || destPlaces.length > 0) && (
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
                  <span class="stop-suggestion-type">{stop.t === 'b' ? 'Bus stop' : 'Station'}</span>
                </button>
              ))}
              {destPlaces.map((place, i) => (
                <button
                  key={`place-${i}`}
                  type="button"
                  class="stop-suggestion-item place-suggestion-item"
                  role="option"
                  onClick={() => handleSelectDestPlace(place)}
                >
                  <span class="stop-suggestion-name">📍 {place.displayName}</span>
                  <span class="stop-suggestion-type">Place</span>
                </button>
              ))}
            </div>
          )}
        </div>

        {/* Departure Timing & Query Modes (Leave now / Depart at - §12.3) */}
        <div class="trip-options-row">
          <div class="departure-control-group">
            <div class="departure-mode-selector" role="radiogroup" aria-label="Departure timing">
              <button
                type="button"
                role="radio"
                aria-checked={departureMode === 'now'}
                class={`dep-mode-btn dep-mode-now ${departureMode === 'now' ? 'dep-mode-active' : ''}`}
                onClick={() => {
                  setDepartureMode('now');
                  handleRoute('now');
                }}
              >
                <span class="dep-mode-icon">⚡</span>
                <span>Leave now</span>
              </button>
              <button
                type="button"
                role="radio"
                aria-checked={departureMode === 'depart_at'}
                class={`dep-mode-btn dep-mode-depart-at ${departureMode === 'depart_at' ? 'dep-mode-active' : ''}`}
                onClick={() => setDepartureMode('depart_at')}
              >
                <span class="dep-mode-icon">🕐</span>
                <span>Depart at</span>
              </button>
            </div>

            <div class="trip-time-selector" style={{ display: departureMode === 'depart_at' ? 'flex' : 'none' }}>
              <label class="trip-time-label" htmlFor="trip-dep-time">
                Time
              </label>
              <input
                id="trip-dep-time"
                type="time"
                class="trip-time-input"
                value={departureTime}
                onInput={(e) => {
                  const val = (e.target as HTMLInputElement).value;
                  setDepartureTime(val);
                  if (val) {
                    handleRoute('depart_at', val);
                  }
                }}
                onChange={(e) => {
                  const val = (e.target as HTMLInputElement).value;
                  setDepartureTime(val);
                  if (val) {
                    handleRoute('depart_at', val);
                  }
                }}
              />
            </div>
          </div>

          <div class="quick-presets-group">
            <span class="quick-preset-label">Quick route:</span>
            <button
              type="button"
              class="quick-preset-btn"
              onClick={() => handleApplyPreset('Times Sq', 'Atlantic Av')}
            >
              Times Sq ➔ Atlantic Av
            </button>
          </div>
        </div>

        {/* Confident Primary Action Button */}
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
          onClick={() => handleRoute(departureMode, departureTime)}
        >
          {isRouting ? (
            <span class="btn-spinner-content">
              <span class="btn-spinner" />
              <span>Finding routes...</span>
            </span>
          ) : (
            <span class="btn-primary-content">
              <span>Find Routes</span>
              <svg viewBox="0 0 20 20" width="16" height="16" fill="currentColor" aria-hidden="true">
                <path fill-rule="evenodd" d="M10.293 3.293a1 1 0 011.414 0l6 6a1 1 0 010 1.414l-6 6a1 1 0 01-1.414-1.414L14.586 11H3a1 1 0 110-2h11.586l-4.293-4.293a1 1 0 010-1.414z" clip-rule="evenodd" />
              </svg>
            </span>
          )}
        </button>
      </div>

      {/* Screen 4B Route Comparison & Profile Cards OR Leg Detail View (Wave T2) */}
      {selectedLeg ? (
        <LegDetailView
          leg={selectedLeg}
          routesMap={routesMap}
          stopsMap={stopsMap}
          onBack={handleBackFromLegDetail}
        />
      ) : (
        <>
          {bikeComparison && (
            <div class="bike-comparison-banner">
              {bikeComparison.savingsMin > 0 ? (
                <span>
                  🚲 Bike {bikeComparison.bikeAccessMin} min to {bikeComparison.bikeStationName} via {bikeComparison.pickupDockName} — <strong>saves {bikeComparison.savingsMin} min</strong> vs walking ({bikeComparison.walkTotalMin} min → {bikeComparison.bikeTotalMin} min)
                </span>
              ) : bikeComparison.savingsMin < 0 ? (
                <span>
                  🚲 Bike {bikeComparison.bikeAccessMin} min to {bikeComparison.bikeStationName} — {Math.abs(bikeComparison.savingsMin)} min slower than walking, showing walk route
                </span>
              ) : (
                <span>
                  🚲 Bike {bikeComparison.bikeAccessMin} min to {bikeComparison.bikeStationName} via {bikeComparison.pickupDockName} — same time as walking
                </span>
              )}
            </div>
          )}
          <RouteComparisonView
          rankedCards={rankedCards}
          activeProfile={activeProfile}
          onSelectProfile={setActiveProfile}
          stopsMap={stopsMap}
          routesMap={routesMap}
          isRouting={isRouting}
          routeError={routeError}
          hasQueried={hasQueried}
          patternsMap={patterns}
          onSelectLeg={handleSelectLeg}
        />
        </>
      )}
    </div>
  );
}
