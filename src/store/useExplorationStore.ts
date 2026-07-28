import { create } from 'zustand';

export interface Location {
  latitude: number;
  longitude: number;
}

import type { Feature, Polygon, MultiPolygon, LineString } from 'geojson';
import { generateFogGeoJSON } from '../utils/fogGeoJSON';
import { NeighborhoodStat, getCurrentNeighborhoodStat, getAllUnlockedHexes, insertUnlockedHexes, clearExploredHexes } from '../db/database';
import { coordToH3 } from '../utils/h3Utils';
import { withBackgroundTask } from '../../modules/expo-background-assertion';

export interface ExplorationState {
  isExploring: boolean;
  currentLocation: Location | null;

  /**
   * Hexagons loaded from disk / database (committed history).
   */
  historicalHexes: string[];

  /**
   * Hexagons unlocked during active movement in current session (uncommitted buffer).
   */
  activeBufferHexes: string[];

  /**
   * Combined unlocked H3 hexagon indices (historicalHexes + activeBufferHexes).
   * STRICT ENFORCEMENT (AGENTS.md):
   * H3 indices must strictly be stored and passed as 15-character hexadecimal strings (e.g. "8b2a100d213fff").
   * Never convert them to JS numbers to avoid 64-bit integer truncation beyond Number.MAX_SAFE_INTEGER.
   */
  unlockedHexes: string[];

  /**
   * The actively visible hexes based on the user's current 200m vicinity bubble.
   */
  visibleHexes: string[];

  /**
   * The inverted GeoJSON polygon representing the fog.
   */
  fogGeoJSON: Feature<Polygon | MultiPolygon> | null;

  // W13-FOG: Positional Delta tracking
  lastProcessedHexesHash: string;

  // Wave 10: Macro Reveal State
  isMacroRevealing: boolean;
  macroRevealCount: number;

  // Screen 3: Historical Route Highlight
  selectedHistoricalRoute: Feature<LineString> | null;

  // Wave 14: Contextual Stats
  sessionUnlockedCount: number;
  sessionDistanceMeters: number;
  currentNeighborhoodStat: NeighborhoodStat | null;

  // Actions
  setIsExploring: (isExploring: boolean) => void;
  setCurrentLocation: (location: Location | null) => void;
  loadUnlockedHexes: () => void;
  setUnlockedHexes: (hexes: string[]) => void;
  setVisibleHexes: (hexes: string[]) => void;
  addUnlockedHexes: (hexes: string[]) => number;
  commitActiveBuffer: () => Promise<number>;
  incrementSessionDistance: (distanceMeters: number) => void;
  updateFogGeoJSON: () => Promise<void>;
  resetExploration: () => void;
  triggerMacroReveal: (count: number) => void;
  clearMacroReveal: () => void;
  setSelectedHistoricalRoute: (route: Feature<LineString> | null) => void;
  refreshCurrentNeighborhoodStat: () => void;
}

export const useExplorationStore = create<ExplorationState>((set, get) => ({
  isExploring: false,
  currentLocation: null,
  historicalHexes: [],
  activeBufferHexes: [],
  unlockedHexes: [],
  visibleHexes: [],
  fogGeoJSON: null,
  lastProcessedHexesHash: '',
  isMacroRevealing: false,
  macroRevealCount: 0,
  selectedHistoricalRoute: null,
  sessionUnlockedCount: 0,
  sessionDistanceMeters: 0,
  currentNeighborhoodStat: null,

  setIsExploring: (isExploring: boolean) => set({ isExploring }),

  setCurrentLocation: (location: Location | null) => set({ currentLocation: location }),

  loadUnlockedHexes: () => {
    try {
      const hexes = getAllUnlockedHexes();
      const validHexes = hexes.filter((hex): hex is string => typeof hex === 'string' && hex.length > 0);
      set({
        historicalHexes: validHexes,
        activeBufferHexes: [],
        unlockedHexes: validHexes,
      });
    } catch (e) {
      console.warn('Failed to load unlocked hexes from database:', e);
    }
  },

  setUnlockedHexes: (hexes: string[]) => {
    // Sanity check to guarantee string types (AGENTS.md guardrail)
    const validHexes = hexes.filter((hex): hex is string => typeof hex === 'string' && hex.length > 0);
    set({
      historicalHexes: validHexes,
      activeBufferHexes: [],
      unlockedHexes: validHexes,
    });
  },

  setVisibleHexes: (hexes: string[]) => {
    const validHexes = hexes.filter((hex): hex is string => typeof hex === 'string' && hex.length > 0);
    set({ visibleHexes: validHexes });
  },

  addUnlockedHexes: (newHexes: string[]) => {
    const validHexes = newHexes.filter((hex): hex is string => typeof hex === 'string' && hex.length > 0);
    let addedCount = 0;
    set((state) => {
      const existingSet = new Set([...state.historicalHexes, ...state.activeBufferHexes]);
      const initialSize = existingSet.size;
      const bufferSet = new Set(state.activeBufferHexes);

      validHexes.forEach((h) => {
        if (!existingSet.has(h)) {
          existingSet.add(h);
          bufferSet.add(h);
        }
      });

      addedCount = existingSet.size - initialSize;
      const updatedBufferHexes = Array.from(bufferSet);
      const updatedUnlockedHexes = Array.from(existingSet);

      return {
        activeBufferHexes: updatedBufferHexes,
        unlockedHexes: updatedUnlockedHexes,
        sessionUnlockedCount: state.sessionUnlockedCount + addedCount,
      };
    });
    return addedCount;
  },

  commitActiveBuffer: async (): Promise<number> => {
    const { activeBufferHexes } = get();
    if (!activeBufferHexes || activeBufferHexes.length === 0) {
      return 0;
    }

    const hexesToCommit = [...activeBufferHexes];
    return withBackgroundTask('commitActiveBuffer', async () => {
      try {
        const inserted = insertUnlockedHexes(hexesToCommit);
        set((state) => {
          const mergedHistorical = Array.from(new Set([...state.historicalHexes, ...hexesToCommit]));
          const remainingBuffer = state.activeBufferHexes.filter((h) => !hexesToCommit.includes(h));
          const combinedUnlocked = Array.from(new Set([...mergedHistorical, ...remainingBuffer]));
          return {
            historicalHexes: mergedHistorical,
            activeBufferHexes: remainingBuffer,
            unlockedHexes: combinedUnlocked,
          };
        });
        return inserted;
      } catch (e) {
        console.warn('Failed to commit active buffer hexes to database:', e);
        return 0;
      }
    });
  },

  incrementSessionDistance: (distanceMeters: number) => {
    set((state) => ({ sessionDistanceMeters: state.sessionDistanceMeters + distanceMeters }));
  },

  updateFogGeoJSON: async () => {
    const { currentLocation, unlockedHexes, visibleHexes, lastProcessedHexesHash } = get();
    if (!currentLocation) return;

    // W13-FOG: Positional Delta Processing
    // Merge unlocked and visible hexes
    const allActiveHexes = Array.from(new Set([...unlockedHexes, ...visibleHexes]));

    // Create a fast hash/string to check if the set of hexes has changed
    const currentHash = allActiveHexes.sort().join('');

    if (currentHash === lastProcessedHexesHash && lastProcessedHexesHash !== '') {
      // Delta is empty; skip expensive h3.cellsToMultiPolygon worker call
      return;
    }

    const geoJSON = await generateFogGeoJSON(
      currentLocation.latitude,
      currentLocation.longitude,
      allActiveHexes
    );

    set({
      fogGeoJSON: geoJSON,
      lastProcessedHexesHash: currentHash,
    });
  },

  resetExploration: () => {
    try {
      clearExploredHexes();
    } catch (e) {
      console.warn('Failed to clear database on reset:', e);
    }
    set({
      isExploring: false,
      currentLocation: null,
      historicalHexes: [],
      activeBufferHexes: [],
      unlockedHexes: [],
      visibleHexes: [],
      fogGeoJSON: null,
      lastProcessedHexesHash: '',
      isMacroRevealing: false,
      macroRevealCount: 0,
      sessionUnlockedCount: 0,
      sessionDistanceMeters: 0,
    });
  },

  triggerMacroReveal: (count: number) =>
    set({
      isMacroRevealing: true,
      macroRevealCount: count,
    }),

  clearMacroReveal: () =>
    set({
      isMacroRevealing: false,
      macroRevealCount: 0,
    }),

  setSelectedHistoricalRoute: (route: Feature<LineString> | null) =>
    set({ selectedHistoricalRoute: route }),

  refreshCurrentNeighborhoodStat: () => {
    const { currentLocation } = get();
    if (!currentLocation) return;
    const h3Index = coordToH3(currentLocation.latitude, currentLocation.longitude);
    const stat = getCurrentNeighborhoodStat(h3Index);
    set({ currentNeighborhoodStat: stat });
  },
}));

