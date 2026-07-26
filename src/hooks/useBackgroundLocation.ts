import { useState, useEffect, useCallback } from 'react';
import { useExplorationStore } from '../store/useExplorationStore';
import {
  requestLocationPermissions,
  checkLocationPermissions,
  startBackgroundTracking,
  stopBackgroundTracking,
  isBackgroundTrackingActive,
  LocationPermissionResult,
} from '../services/locationService';

export function useBackgroundLocation() {
  const isExploring = useExplorationStore((state) => state.isExploring);
  const [permissions, setPermissions] = useState<LocationPermissionResult>({
    foreground: false,
    background: false,
  });
  const [isLoading, setIsLoading] = useState<boolean>(false);
  const [error, setError] = useState<string | null>(null);

  const refreshPermissions = useCallback(async () => {
    try {
      const perms = await checkLocationPermissions();
      setPermissions(perms);
    } catch (e: any) {
      setError(e?.message || 'Failed checking location permissions.');
    }
  }, []);

  const syncTrackingStatus = useCallback(async () => {
    try {
      const active = await isBackgroundTrackingActive();
      useExplorationStore.getState().setIsExploring(active);
    } catch (e: any) {
      console.warn('Failed syncing background location tracking status:', e);
    }
  }, []);

  useEffect(() => {
    refreshPermissions();
    syncTrackingStatus();
  }, [refreshPermissions, syncTrackingStatus]);

  const requestPermissions = async (): Promise<LocationPermissionResult> => {
    setIsLoading(true);
    setError(null);
    try {
      const perms = await requestLocationPermissions();
      setPermissions(perms);
      return perms;
    } catch (e: any) {
      const msg = e?.message || 'Failed requesting location permissions.';
      setError(msg);
      throw e;
    } finally {
      setIsLoading(false);
    }
  };

  const startTracking = async () => {
    setIsLoading(true);
    setError(null);
    try {
      await startBackgroundTracking();
    } catch (e: any) {
      const msg = e?.message || 'Failed starting background location tracking.';
      setError(msg);
      throw e;
    } finally {
      setIsLoading(false);
    }
  };

  const stopTracking = async () => {
    setIsLoading(true);
    setError(null);
    try {
      await stopBackgroundTracking();
    } catch (e: any) {
      const msg = e?.message || 'Failed stopping background location tracking.';
      setError(msg);
      throw e;
    } finally {
      setIsLoading(false);
    }
  };

  const toggleTracking = async () => {
    if (isExploring) {
      await stopTracking();
    } else {
      await startTracking();
    }
  };

  return {
    isExploring,
    permissions,
    isLoading,
    error,
    requestPermissions,
    refreshPermissions,
    startTracking,
    stopTracking,
    toggleTracking,
  };
}
