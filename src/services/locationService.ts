import * as Location from 'expo-location';
import { BACKGROUND_LOCATION_TASK } from './locationTask';
import { useExplorationStore } from '../store/useExplorationStore';

export interface LocationPermissionResult {
  foreground: boolean;
  background: boolean;
}

/**
 * Requests Foreground and Background location permissions via expo-location.
 */
export async function requestLocationPermissions(): Promise<LocationPermissionResult> {
  const foregroundResult = await Location.requestForegroundPermissionsAsync();
  if (foregroundResult.status !== 'granted') {
    return { foreground: false, background: false };
  }

  const backgroundResult = await Location.requestBackgroundPermissionsAsync();
  return {
    foreground: true,
    background: backgroundResult.status === 'granted',
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
 * Starts continuous background location updates configured per energy economics rules in architecture.md:
 * - accuracy: Location.Accuracy.Balanced (~10-25m precision, battery-friendly)
 * - distanceInterval: 10 meters (wakes app only on physical movement)
 * - deferredUpdatesDistance: 50 meters (batches updates in GPS hardware buffer)
 * - pausesLocationUpdatesAutomatically: true (allows CPU sleep when stationary)
 * - activityType: Location.ActivityType.Fitness
 * - showsBackgroundLocationIndicator: true (iOS requirement for transparency)
 * - foregroundService: Android requirement for background service notifications
 */
export async function startBackgroundTracking(): Promise<boolean> {
  const permissions = await checkLocationPermissions();
  if (!permissions.foreground || !permissions.background) {
    const requested = await requestLocationPermissions();
    if (!requested.foreground || !requested.background) {
      throw new Error('Background location permission denied by user.');
    }
  }

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

  useExplorationStore.getState().setIsExploring(true);
  return true;
}

/**
 * Stops continuous background location tracking and updates exploration store.
 */
export async function stopBackgroundTracking(): Promise<boolean> {
  const isStarted = await Location.hasStartedLocationUpdatesAsync(BACKGROUND_LOCATION_TASK);
  if (isStarted) {
    await Location.stopLocationUpdatesAsync(BACKGROUND_LOCATION_TASK);
  }

  useExplorationStore.getState().setIsExploring(false);
  return true;
}

/**
 * Checks if background location tracking is currently running.
 */
export async function isBackgroundTrackingActive(): Promise<boolean> {
  return await Location.hasStartedLocationUpdatesAsync(BACKGROUND_LOCATION_TASK);
}
