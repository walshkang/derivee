import { requireNativeModule } from 'expo-modules-core';

export interface ExpoBackgroundAssertionNativeModule {
  beginBackgroundTask(name?: string): number;
  endBackgroundTask(taskId: number): void;
}

let nativeModule: ExpoBackgroundAssertionNativeModule | null = null;

try {
  nativeModule = requireNativeModule<ExpoBackgroundAssertionNativeModule>('ExpoBackgroundAssertion');
} catch (e) {
  // Graceful fallback for non-native environments or unit testing before prebuild
  nativeModule = {
    beginBackgroundTask: () => 0,
    endBackgroundTask: () => {},
  };
}

export default nativeModule as ExpoBackgroundAssertionNativeModule;
