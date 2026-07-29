import * as Location from 'expo-location';
import {
  requestLocationPermissions,
  checkLocationPermissions,
  startBackgroundTracking,
  stopBackgroundTracking,
  isBackgroundTrackingActive,
} from '../locationService';
import { BACKGROUND_LOCATION_TASK } from '../locationTask';
import { useExplorationStore } from '../../store/useExplorationStore';

describe('Location Service Lifecycle (locationService.ts)', () => {
  beforeEach(() => {
    useExplorationStore.getState().resetExploration();
    jest.clearAllMocks();
  });

  it('requests foreground and background location permissions', async () => {
    const result = await requestLocationPermissions();
    expect(result).toEqual({ foreground: true, background: true });
    expect(Location.requestForegroundPermissionsAsync).toHaveBeenCalled();
    expect(Location.requestBackgroundPermissionsAsync).toHaveBeenCalled();
  });

  it('checks location permissions without prompting user', async () => {
    const result = await checkLocationPermissions();
    expect(result).toEqual({ foreground: true, background: true });
    expect(Location.getForegroundPermissionsAsync).toHaveBeenCalled();
    expect(Location.getBackgroundPermissionsAsync).toHaveBeenCalled();
  });

  it('starts background tracking with correct battery-conscious parameters', async () => {
    const success = await startBackgroundTracking();
    expect(success).toBe(true);
    const callArgs = (Location.startLocationUpdatesAsync as jest.Mock).mock.calls[0];
    expect(callArgs[0]).toBe(BACKGROUND_LOCATION_TASK);
    expect(callArgs[1]).toEqual(
      expect.objectContaining({
        accuracy: Location.Accuracy.Balanced,
        distanceInterval: 10,
        deferredUpdatesDistance: 50,
        pausesUpdatesAutomatically: true,
        activityType: Location.ActivityType.Fitness,
        showsBackgroundLocationIndicator: true,
      })
    );
    expect(callArgs[1].timeInterval).toBeUndefined();
    expect(useExplorationStore.getState().isExploring).toBe(true);
  });

  it('stops background tracking and updates exploration store', async () => {
    await startBackgroundTracking();
    expect(useExplorationStore.getState().isExploring).toBe(true);

    await stopBackgroundTracking();
    expect(Location.stopLocationUpdatesAsync).toHaveBeenCalledWith(BACKGROUND_LOCATION_TASK);
    expect(useExplorationStore.getState().isExploring).toBe(false);
  });

  it('checks if background tracking is active', async () => {
    (Location as any)._setIsTrackingStarted(true);
    const isActive = await isBackgroundTrackingActive();
    expect(isActive).toBe(true);
  });
});
