import { create } from 'zustand';

export interface Location {
  latitude: number;
  longitude: number;
}

import type { Feature, Polygon, MultiPolygon } from 'geojson';
import { generateFogGeoJSON } from '../utils/fogGeoJSON';

export interface ExplorationState {
  isExploring: boolean;
  currentLocation: Location | null;
  /**
   * Unlocked H3 hexagon indices.
   * STRICT ENFORCEMENT (AGENTS.md):
   * H3 indices must strictly be stored and passed as 15-character hexadecimal strings (e.g. "8b2a100d213fff").
   * Never convert them to JS numbers to avoid 64-bit integer truncation beyond Number.MAX_SAFE_INTEGER.
   */
  unlockedHexes: string[];

  /**
   * The inverted GeoJSON polygon representing the fog.
   */
  fogGeoJSON: Feature<Polygon | MultiPolygon> | null;

  // Actions
  setIsExploring: (isExploring: boolean) => void;
  setCurrentLocation: (location: Location | null) => void;
  setUnlockedHexes: (hexes: string[]) => void;
  addUnlockedHexes: (hexes: string[]) => number;
  updateFogGeoJSON: () => Promise<void>;
  resetExploration: () => void;
}

export const useExplorationStore = create<ExplorationState>((set, get) => ({
  isExploring: false,
  currentLocation: null,
  unlockedHexes: [],
  fogGeoJSON: null,

  setIsExploring: (isExploring: boolean) => set({ isExploring }),

  setCurrentLocation: (location: Location | null) => set({ currentLocation: location }),

  setUnlockedHexes: (hexes: string[]) => {
    // Sanity check to guarantee string types (AGENTS.md guardrail)
    const validHexes = hexes.filter((hex): hex is string => typeof hex === 'string');
    set({ unlockedHexes: validHexes });
  },

  addUnlockedHexes: (newHexes: string[]) => {
    const validHexes = newHexes.filter((hex): hex is string => typeof hex === 'string');
    let addedCount = 0;
    set((state) => {
      const existingSet = new Set(state.unlockedHexes);
      const initialSize = existingSet.size;
      validHexes.forEach((h) => existingSet.add(h));
      addedCount = existingSet.size - initialSize;
      return { unlockedHexes: Array.from(existingSet) };
    });
    return addedCount;
  },

  updateFogGeoJSON: async () => {
    const { currentLocation, unlockedHexes } = get();
    if (!currentLocation) return;
    
    const geoJSON = await generateFogGeoJSON(
      currentLocation.latitude,
      currentLocation.longitude,
      unlockedHexes
    );
    
    set({ fogGeoJSON: geoJSON });
  },

  resetExploration: () =>
    set({
      isExploring: false,
      currentLocation: null,
      unlockedHexes: [],
      fogGeoJSON: null,
    }),
}));
