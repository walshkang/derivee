import ExpoBackgroundAssertionModule from './src/ExpoBackgroundAssertionModule';

/**
 * Begins an iOS background task assertion (`UIApplication.shared.beginBackgroundTask`).
 * Prevents iOS Watchdog from terminating JS execution during long-running background operations.
 *
 * @param name Optional identifier name for debugging/tracing in iOS Instruments.
 * @returns Numeric taskId handle (0 if failed or on non-iOS platforms).
 */
export function beginBackgroundTask(name?: string): number {
  try {
    return ExpoBackgroundAssertionModule.beginBackgroundTask(name);
  } catch (error) {
    console.warn('[ExpoBackgroundAssertion] Failed to begin background task:', error);
    return 0;
  }
}

/**
 * Ends an active iOS background task assertion (`UIApplication.shared.endBackgroundTask`).
 * Releases the background execution assertion back to iOS.
 *
 * @param taskId Numeric handle returned by `beginBackgroundTask`.
 */
export function endBackgroundTask(taskId: number): void {
  if (!taskId) return;
  try {
    ExpoBackgroundAssertionModule.endBackgroundTask(taskId);
  } catch (error) {
    console.warn('[ExpoBackgroundAssertion] Failed to end background task:', error);
  }
}

/**
 * High-level async wrapper to execute a task within an iOS background task assertion.
 * Guarantees `endBackgroundTask` execution via a `finally` block even if the task throws.
 *
 * @param name Task name for iOS Watchdog tracing.
 * @param task Async function to execute.
 * @returns Result of the async task function.
 */
export async function withBackgroundTask<T>(
  name: string,
  task: () => Promise<T>
): Promise<T> {
  const taskId = beginBackgroundTask(name);
  try {
    return await task();
  } finally {
    if (taskId) {
      endBackgroundTask(taskId);
    }
  }
}
