import { AppState, AppStateStatus, NativeEventSubscription } from 'react-native';
import { useExplorationStore } from '../store/useExplorationStore';

let appStateSubscription: NativeEventSubscription | null = null;

/**
 * AppState listener handler.
 * Triggers `commitActiveBuffer()` on `useExplorationStore` when the app moves to background or inactive state.
 */
export function handleAppStateChange(nextAppState: AppStateStatus): void {
  if (nextAppState === 'background' || nextAppState === 'inactive') {
    useExplorationStore.getState().commitActiveBuffer().catch((err) => {
      console.warn('[AppStateListener] Error executing commitActiveBuffer on app backgrounding:', err);
    });
  }
}

/**
 * Initializes the React Native AppState change listener.
 * Automatically commits active buffer hexes to disk whenever the phone is locked or backgrounded.
 *
 * @returns Subscription object cleanup callback function.
 */
export function initAppStateListener(): () => void {
  if (appStateSubscription) {
    appStateSubscription.remove();
  }

  appStateSubscription = AppState.addEventListener('change', handleAppStateChange);

  return () => {
    if (appStateSubscription) {
      appStateSubscription.remove();
      appStateSubscription = null;
    }
  };
}

/**
 * Removes active AppState change listener.
 */
export function removeAppStateListener(): void {
  if (appStateSubscription) {
    appStateSubscription.remove();
    appStateSubscription = null;
  }
}
