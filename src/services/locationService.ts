import * as Location from 'expo-location';
import { BACKGROUND_LOCATION_TASK, handleBackgroundLocationUpdate } from './locationTask';
import { useExplorationStore } from '../store/useExplorationStore';

export interface LocationPermissionResult {
  foreground: boolean;
  background: boolean;
}

let foregroundSubscription: Location.LocationSubscription | null = null;

/**
 * Requests Foreground and Background location permissions via expo-location.
 */
export async function requestLocationPermissions(): Promise<LocationPermissionResult> {
  const foregroundResult = await Location.requestForegroundPermissionsAsync();
  if (foregroundResult.status !== 'granted') {
    return { foreground: false, background: false };
  }

  let backgroundGranted = false;
  try {
    const backgroundResult = await Location.requestBackgroundPermissionsAsync();
    backgroundGranted = backgroundResult.status === 'granted';
  } catch (e) {
    console.warn('Background location permission request failed or unsupported:', e);
  }

  return {
    foreground: true,
    background: backgroundGranted,
  };
}

/**
 * Checks current Foreground and Background location permissions without prompting the user.
 */
export async function checkLocationPermissions(): Promise<LocationPermissionResult> {
  const foregroundResult = await Location.getForegroundPermissionsAsync();
  const backgroundResult = await Location.getBackgroundPermissionsAsync();
  return {
    foreground: foregroundResult.status === 'granted',
    background: backgroundResult.status === 'granted',
  };
}

/**
 * Starts continuous location updates:
 * - If background permission is granted: Uses expo-task-manager background tracking per energy economics rules in architecture.md.
 * - If foreground permission is granted ("While Using App"): Uses watchPositionAsync to track exploration in the active app.
 */
export async function startBackgroundTracking(): Promise<boolean> {
  let permissions = await checkLocationPermissions();
  if (!permissions.foreground) {
    permissions = await requestLocationPermissions();
    if (!permissions.foreground) {
      throw new Error('Location permission denied by user.');
    }
  }

  if (permissions.background) {
    const isStarted = await Location.hasStartedLocationUpdatesAsync(BACKGROUND_LOCATION_TASK);
    if (!isStarted) {
      await Location.startLocationUpdatesAsync(BACKGROUND_LOCATION_TASK, {
        accuracy: Location.Accuracy.Balanced,
        distanceInterval: 10,
        deferredUpdatesDistance: 50,
        pausesUpdatesAutomatically: true,
        activityType: Location.ActivityType.Fitness,
        showsBackgroundLocationIndicator: true,
        foregroundService: {
          notificationTitle: 'Fog of Wburg Exploration',
          notificationBody: 'Mapping your unexplored surroundings in the background.',
          notificationColor: '#0d1117',
        },
      });
    }
  } else {
    // Fallback: If only "While Using App" is granted, track via active foreground location watcher
    if (!foregroundSubscription) {
      foregroundSubscription = await Location.watchPositionAsync(
        {
          accuracy: Location.Accuracy.Balanced,
          distanceInterval: 10,
          timeInterval: 3000,
        },
        (location) => {
          handleBackgroundLocationUpdate([location]);
        }
      );
    }
  }

  useExplorationStore.getState().setIsExploring(true);
  return true;
}

/**
 * Stops location tracking (both background task manager and foreground watcher) and updates store.
 */
export async function stopBackgroundTracking(): Promise<boolean> {
  const isStarted = await Location.hasStartedLocationUpdatesAsync(BACKGROUND_LOCATION_TASK);
  if (isStarted) {
    await Location.stopLocationUpdatesAsync(BACKGROUND_LOCATION_TASK);
  }

  if (foregroundSubscription) {
    foregroundSubscription.remove();
    foregroundSubscription = null;
  }

  useExplorationStore.getState().setIsExploring(false);
  return true;
}

/**
 * Checks if location tracking is currently active (either background task manager or foreground watcher).
 */
export async function isBackgroundTrackingActive(): Promise<boolean> {
  const isBackgroundStarted = await Location.hasStartedLocationUpdatesAsync(BACKGROUND_LOCATION_TASK);
  return isBackgroundStarted || foregroundSubscription !== null;
}

