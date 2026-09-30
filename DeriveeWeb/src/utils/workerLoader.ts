export interface WorkerLoaderOptions {
  maxRetries?: number;
  retryDelayMs?: number;
  sleep?: (ms: number) => Promise<void>;
}

/**
 * Creates a Web Worker with bounded retry and exponential backoff.
 * Hardens worker construction against transient network blips and iOS WebKit loading errors.
 * Ensures any diagnostic error message explicitly names the target worker script URL.
 */
export async function createWorkerWithRetry(
  workerFactory: () => Worker,
  scriptUrl: URL | string,
  options?: WorkerLoaderOptions
): Promise<Worker> {
  const maxRetries = options?.maxRetries ?? 2;
  const initialDelayMs = options?.retryDelayMs ?? 300;
  const sleepFn = options?.sleep ?? ((ms: number) => new Promise((resolve) => setTimeout(resolve, ms)));

  const urlObj = scriptUrl instanceof URL
    ? scriptUrl
    : new URL(scriptUrl, typeof document !== 'undefined' ? document.baseURI : 'http://localhost');
  const resourcePath = urlObj.pathname || urlObj.href;

  let lastError: unknown = null;

  for (let attempt = 0; attempt <= maxRetries; attempt++) {
    try {
      return workerFactory();
    } catch (err: unknown) {
      lastError = err;
      if (attempt < maxRetries) {
        await sleepFn(initialDelayMs * Math.pow(2, attempt));
      }
    }
  }

  const rawMessage = lastError instanceof Error ? lastError.message : String(lastError);
  const formattedError = (rawMessage === 'Load failed' || rawMessage === 'Failed to fetch')
    ? `Failed to load worker script (${resourcePath}): network connection failed (${rawMessage}).`
    : `Failed to load worker script (${resourcePath}): ${rawMessage}`;

  throw new Error(formattedError);
}
