import {
  BACKGROUND_LOCATION_TASK,
  handleBackgroundLocationUpdate,
  resetLastAcceptedLocation,
} from '../locationTask';
import { useExplorationStore } from '../../store/useExplorationStore';
import { initDatabase, closeDatabase, getAllUnlockedHexes } from '../../db/database';
import type { LocationObject } from 'expo-location';

describe('Background Location Task (locationTask.ts)', () => {
  beforeEach(() => {
    initDatabase();
    useExplorationStore.getState().resetExploration();
    resetLastAcceptedLocation();
  });

  afterEach(() => {
    closeDatabase();
  });

  it('exports the correct background task name constant', () => {
    expect(BACKGROUND_LOCATION_TASK).toBe('FOG_BACKGROUND_LOCATION_TASK');
  });

  it('handles empty or undefined location batch gracefully', () => {
    const resultEmpty = handleBackgroundLocationUpdate([]);
    expect(resultEmpty).toEqual([]);

    const resultNull = handleBackgroundLocationUpdate(null as any);
    expect(resultNull).toEqual([]);
  });

  it('processes a batch of valid GPS coordinates and updates H3 buffer hexes', () => {
    const mockLocations: LocationObject[] = [
      {
        coords: {
          latitude: 40.7128,
          longitude: -73.956,
          altitude: null,
          accuracy: 5,
          altitudeAccuracy: null,
          heading: null,
          speed: null,
        },
        timestamp: Date.now(),
      },
    ];

    const unlockedHexes = handleBackgroundLocationUpdate(mockLocations);

    // Should return 7 hexes (1 center + 6 radius 1 buffer hexes)
    expect(unlockedHexes.length).toBe(7);

    // AGENTS.md Guardrail assertion: Every H3 index must strictly be a 15-character string
    unlockedHexes.forEach((hex) => {
      expect(typeof hex).toBe('string');
      expect(hex.length).toBe(15);
    });

    // Verify Zustand store updated
    const storeState = useExplorationStore.getState();
    expect(storeState.currentLocation).toEqual({ latitude: 40.7128, longitude: -73.956 });
    expect(storeState.unlockedHexes.length).toBe(7);

    // Verify op-sqlite DB persisted hexes
    const dbHexes = getAllUnlockedHexes();
    expect(dbHexes.length).toBe(7);
  });

  it('filters out GPS drift coordinates exceeding 12 m/s velocity gate', () => {
    const now = Date.now();
    const mockLocations: LocationObject[] = [
      {
        coords: {
          latitude: 40.7128,
          longitude: -73.956,
          altitude: null,
          accuracy: 5,
          altitudeAccuracy: null,
          heading: null,
          speed: null,
        },
        timestamp: now,
      },
      {
        // 500m jump after 2 seconds => 250 m/s (drift jump)
        coords: {
          latitude: 40.7173,
          longitude: -73.956,
          altitude: null,
          accuracy: 5,
          altitudeAccuracy: null,
          heading: null,
          speed: null,
        },
        timestamp: now + 2000,
      },
    ];

    const unlockedHexes = handleBackgroundLocationUpdate(mockLocations);

    // Only the first location's 7 hexes should be processed; drift jump discarded
    expect(unlockedHexes.length).toBe(7);
  });

  it('skips invalid coordinate objects without throwing exceptions', () => {
    const mockLocations: LocationObject[] = [
      {
        coords: {
          latitude: NaN,
          longitude: -73.956,
          altitude: null,
          accuracy: null,
          altitudeAccuracy: null,
          heading: null,
          speed: null,
        },
        timestamp: Date.now(),
      },
      {
        coords: {
          latitude: 40.7128,
          longitude: -73.956,
          altitude: null,
          accuracy: 5,
          altitudeAccuracy: null,
          heading: null,
          speed: null,
        },
        timestamp: Date.now(),
      },
    ];

    const unlockedHexes = handleBackgroundLocationUpdate(mockLocations);
    expect(unlockedHexes.length).toBe(7);
  });

  it('W14.8: drops execution and returns 0 new hexes when location update is in already unlocked hexes', () => {
    const mockLocation: LocationObject[] = [
      {
        coords: {
          latitude: 40.7128,
          longitude: -73.956,
          altitude: null,
          accuracy: 5,
          altitudeAccuracy: null,
          heading: null,
          speed: null,
        },
        timestamp: Date.now(),
      },
    ];

    // First GPS update unlocks 7 hexes
    const firstPass = handleBackgroundLocationUpdate(mockLocation);
    expect(firstPass.length).toBe(7);

    // Second GPS update at exact same location encounters O(1) in-memory Set gatekeeper
    const secondPass = handleBackgroundLocationUpdate(mockLocation);
    expect(secondPass.length).toBe(0);
  });

  it('W14.8: resets in-memory gatekeeper state on store resetExploration()', () => {
    const mockLocation: LocationObject[] = [
      {
        coords: {
          latitude: 40.7128,
          longitude: -73.956,
          altitude: null,
          accuracy: 5,
          altitudeAccuracy: null,
          heading: null,
          speed: null,
        },
        timestamp: Date.now(),
      },
    ];

    handleBackgroundLocationUpdate(mockLocation);
    expect(getAllUnlockedHexes().length).toBe(7);

    // Reset exploration state
    useExplorationStore.getState().resetExploration();
    expect(getAllUnlockedHexes().length).toBe(0);

    // Subsequent update after reset unlocks 7 hexes again
    const postResetPass = handleBackgroundLocationUpdate(mockLocation);
    expect(postResetPass.length).toBe(7);
  });
});
