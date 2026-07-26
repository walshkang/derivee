import { create } from 'zustand';

export interface Location {
  latitude: number;
  longitude: number;
}

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

  // Actions
  setIsExploring: (isExploring: boolean) => void;
  setCurrentLocation: (location: Location | null) => void;
  setUnlockedHexes: (hexes: string[]) => void;
  addUnlockedHexes: (hexes: string[]) => void;
  resetExploration: () => void;
}

export const useExplorationStore = create<ExplorationState>((set) => ({
  isExploring: false,
  currentLocation: null,
  unlockedHexes: [],

  setIsExploring: (isExploring: boolean) => set({ isExploring }),

  setCurrentLocation: (location: Location | null) => set({ currentLocation: location }),

  setUnlockedHexes: (hexes: string[]) => {
    // Sanity check to guarantee string types (AGENTS.md guardrail)
    const validHexes = hexes.filter((hex): hex is string => typeof hex === 'string');
    set({ unlockedHexes: validHexes });
  },

  addUnlockedHexes: (newHexes: string[]) => {
    const validHexes = newHexes.filter((hex): hex is string => typeof hex === 'string');
    set((state) => {
      const existingSet = new Set(state.unlockedHexes);
      validHexes.forEach((h) => existingSet.add(h));
      return { unlockedHexes: Array.from(existingSet) };
    });
  },

  resetExploration: () =>
    set({
      isExploring: false,
      currentLocation: null,
      unlockedHexes: [],
    }),
}));
