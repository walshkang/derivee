import { type HybridObject } from 'react-native-nitro-modules';

export interface HybridTracking extends HybridObject<{ ios: 'swift' }> {
  /**
   * Initialize the native CLLocationManager and SQLite connection.
   */
  startTracking(): void;

  /**
   * Terminate the background service and release resources.
   */
  stopTracking(): void;

  /**
   * Register a JS callback for real-time foreground notifications when new hexes are discovered.
   */
  addListener(callback: (h3Index: string) => void): void;

  /**
   * Unregister the callback.
   */
  removeListener(): void;

  /**
   * Synchronous delta query for AppState hydration.
   * @param timestamp The timestamp to query since.
   */
  getDiscoveredHexesSince(timestamp: number): string[];
}
