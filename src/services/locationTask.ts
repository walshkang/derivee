import * as TaskManager from 'expo-task-manager';
import type { LocationObject } from 'expo-location';
import { processAndStoreLocationHexes } from '../utils/h3Utils';
import { useExplorationStore } from '../store/useExplorationStore';

/**
 * Task identifier for background location updates in expo-task-manager.
 */
export const BACKGROUND_LOCATION_TASK = 'FOG_BACKGROUND_LOCATION_TASK';

/**
 * Data payload format passed by expo-task-manager for location updates.
 */
export interface LocationTaskPayload {
  locations?: LocationObject[];
}

/**
 * Pure handler function to process a batch of location updates from background GPS.
 * Decoupled from Expo's task manager listener context for clean unit testing per AGENTS.md.
 *
 * @param locations Array of Expo LocationObject items
 * @returns Array of newly generated H3 buffer hex strings
 */
export function handleBackgroundLocationUpdate(locations: LocationObject[]): string[] {
  if (!Array.isArray(locations) || locations.length === 0) {
    return [];
  }

  const allUnlockedHexes: string[] = [];

  for (const location of locations) {
    if (!location || !location.coords) continue;
    const { latitude, longitude } = location.coords;

    if (
      typeof latitude !== 'number' ||
      isNaN(latitude) ||
      typeof longitude !== 'number' ||
      isNaN(longitude)
    ) {
      continue;
    }

    // Convert GPS coordinate to H3 resolution 11 & buffer hexes, insert to op-sqlite DB, update store
    const { bufferHexes } = processAndStoreLocationHexes(latitude, longitude);

    // Enforce 15-character hex string precision guardrail (AGENTS.md)
    const validHexes = bufferHexes.filter(
      (hex): hex is string => typeof hex === 'string' && hex.length === 15
    );
    allUnlockedHexes.push(...validHexes);
  }

  // Synchronously update GeoJSON polygon fog if current location exists
  const store = useExplorationStore.getState();
  if (store.currentLocation) {
    // Non-blocking trigger to update fog polygon
    store.updateFogGeoJSON().catch((err) => {
      console.warn('Failed updating fog GeoJSON in background task handler:', err);
    });
  }

  return allUnlockedHexes;
}

/**
 * Register the headless background task with expo-task-manager.
 * This runs when the app is in the background or killed when triggered by OS location changes.
 */
if (TaskManager.isTaskDefined && !TaskManager.isTaskDefined(BACKGROUND_LOCATION_TASK)) {
  TaskManager.defineTask(BACKGROUND_LOCATION_TASK, ({ data, error }: { data: LocationTaskPayload; error: TaskManager.TaskManagerError | null }) => {
    if (error) {
      console.error(`[${BACKGROUND_LOCATION_TASK}] TaskManager error:`, error.message);
      return;
    }

    if (data && Array.isArray(data.locations)) {
      handleBackgroundLocationUpdate(data.locations);
    }
  });
}
