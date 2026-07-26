import { create } from 'zustand';
import { POI, getAllPOIs, markPOIDiscovered, seedPOIs } from '../db/poiQueries';

export interface POIState {
  pois: POI[];
  recentlyDiscovered: POI | null;

  // Actions
  loadPOIs: () => void;
  checkIntersections: (bufferHexes: string[]) => void;
  clearRecentPOI: () => void;
}

export const usePOIStore = create<POIState>((set, get) => ({
  pois: [],
  recentlyDiscovered: null,

  loadPOIs: () => {
    // Seed DB if it's empty
    seedPOIs();
    // Fetch all POIs
    const pois = getAllPOIs();
    set({ pois });
  },

  checkIntersections: (bufferHexes: string[]) => {
    const { pois } = get();

    // Strict array inclusion check (O(1) against the small buffer hexes array per POI)
    // Find all undiscovered POIs that match any hex in the buffer
    const newlyDiscovered = pois.filter(
      (poi) => !poi.discovered && bufferHexes.includes(poi.h3_index)
    );

    if (newlyDiscovered.length > 0) {
      // Pick the first discovered POI to trigger a reward modal event
      const discoveredPOI = newlyDiscovered[0];

      // Update local SQLite DB
      markPOIDiscovered(discoveredPOI.id);

      // Update Zustand state
      set((state) => ({
        pois: state.pois.map((poi) =>
          poi.id === discoveredPOI.id ? { ...poi, discovered: true } : poi
        ),
        recentlyDiscovered: discoveredPOI,
      }));
    }
  },

  clearRecentPOI: () => {
    set({ recentlyDiscovered: null });
  },
}));
