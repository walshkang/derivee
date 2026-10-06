import type { BasemapWorkerToMainMessage, BasemapStage } from '../types/basemap.ts';
import { validatePMTilesHeader, PMTILES_HEADER_SIZE } from '../utils/pmtilesIntegrity.ts';
import { withTimeout } from '../utils/withTimeout.ts';

export interface BasemapInstallerDependencies {
  postMessage: (msg: BasemapWorkerToMainMessage) => void;
  fetch?: (url: string, init?: RequestInit) => Promise<Response>;
  getCityDirectoryHandle?: (slug: string) => Promise<FileSystemDirectoryHandle>;
  deletePartialFile?: (slug: string) => Promise<void>;
  validatePMTilesHeader?: (header: Uint8Array, size: number, path: string) => void;
  readChunkTimeoutMs?: number;
  readEofTimeoutMs?: number;
  writeChunkTimeoutMs?: number;
  closeStreamTimeoutMs?: number;
  getFileTimeoutMs?: number;
  readHeaderTimeoutMs?: number;
  cleanupTimeoutMs?: number;
  fetchRetries?: number;
  retryDelayMs?: number;
}

async function defaultGetCityDirectoryHandle(slug: string = 'nyc'): Promise<FileSystemDirectoryHandle> {
  const root = await navigator.storage.getDirectory();
  const citiesDir = await root.getDirectoryHandle('cities', { create: true });
  return await citiesDir.getDirectoryHandle(slug, { create: true });
}

async function defaultDeletePartialFile(slug: string = 'nyc'): Promise<void> {
  try {
    const root = await navigator.storage.getDirectory();
    const citiesDir = await root.getDirectoryHandle('cities', { create: false });
    const cityDir = await citiesDir.getDirectoryHandle(slug, { create: false });
    await cityDir.removeEntry('basemap.pmtiles');
  } catch {
    // Ignore if not exists
  }
}

export async function runBasemapInstall(
  slug: string = 'nyc',
  basemapUrl: string = '/api/basemap?city=nyc',
  deps: BasemapInstallerDependencies
): Promise<void> {
  const fetchFn = deps.fetch ?? fetch;
  const getDirHandle = deps.getCityDirectoryHandle ?? defaultGetCityDirectoryHandle;
  const deletePartial = deps.deletePartialFile ?? defaultDeletePartialFile;
  const validateHeader = deps.validatePMTilesHeader ?? validatePMTilesHeader;

  let currentStage: BasemapStage = 'STARTING_DOWNLOAD';

  try {
    deps.postMessage({
      type: 'STAGE',
      stage: 'STARTING_DOWNLOAD',
    });

    deps.postMessage({
      type: 'PROGRESS',
      loadedBytes: 0,
      totalBytes: 24991495, // Default NYC PMTiles extract size
      percent: 0,
    });

    let response: Response | null = null;
    const maxFetchRetries = deps.fetchRetries ?? 2;
    let lastFetchError: unknown = null;

    for (let attempt = 0; attempt <= maxFetchRetries; attempt++) {
      try {
        response = await fetchFn(basemapUrl, {
          credentials: 'include',
          headers: {
            Accept: 'application/vnd.pmtiles, application/octet-stream',
          },
        });

        if (response.ok && response.body) {
          lastFetchError = null;
          break;
        }

        throw new Error(
          `Download request failed with status ${response.status}. Please check your connection.`
        );
      } catch (err: unknown) {
        lastFetchError = err;
        if (attempt < maxFetchRetries) {
          const delay = (deps.retryDelayMs ?? 500) * Math.pow(2, attempt);
          await new Promise((r) => setTimeout(r, delay));
        }
      }
    }

    if (!response || !response.ok || !response.body) {
      if (lastFetchError) {
        throw lastFetchError;
      }
      throw new Error('Download request failed. Please check your connection.');
    }

    const contentLengthHeader = response.headers.get('Content-Length');
    const totalBytes = contentLengthHeader ? parseInt(contentLengthHeader, 10) : 24991495;

    const cityDir = await getDirHandle(slug);
    const fileHandle = await cityDir.getFileHandle('basemap.pmtiles', { create: true });

    const handleAny = fileHandle as unknown as {
      createSyncAccessHandle?: () => Promise<{
        truncate: (size: number) => void;
        write: (buffer: BufferSource, options?: { at: number }) => number;
        flush: () => void;
        close: () => void;
      }>;
      createWritable?: () => Promise<FileSystemWritableFileStream>;
    };

    let syncHandle: {
      truncate: (size: number) => void;
      write: (buffer: BufferSource, options?: { at: number }) => number;
      flush: () => void;
      close: () => void;
    } | null = null;

    let writable: FileSystemWritableFileStream | null = null;

    if (typeof handleAny.createSyncAccessHandle === 'function' && typeof handleAny.createWritable !== 'function') {
      syncHandle = await handleAny.createSyncAccessHandle();
      syncHandle.truncate(0);
    } else {
      writable = await fileHandle.createWritable();
    }

    currentStage = 'DOWNLOADING';
    deps.postMessage({
      type: 'STAGE',
      stage: 'DOWNLOADING',
    });

    const reader = response.body.getReader();
    let loadedBytes = 0;
    let writeOffset = 0;
    let lastProgressTime = 0;

    try {
      while (true) {
        const isAtEnd = totalBytes > 0 && loadedBytes >= totalBytes;
        const readTimeout = isAtEnd
          ? (deps.readEofTimeoutMs ?? 10_000)
          : (deps.readChunkTimeoutMs ?? 20_000);

        const { done, value } = await withTimeout(
          reader.read(),
          readTimeout,
          isAtEnd
            ? 'Download stream stalled waiting for stream completion after receiving all bytes.'
            : 'Download stream stalled: no data received for 20s.'
        );

        if (done) break;
        if (value) {
          // Normalize to byteOffset 0 for iOS Safari bug
          const payload = (value.byteOffset === 0 && value.byteLength === value.buffer.byteLength)
            ? value
            : value.slice();

          if (syncHandle) {
            syncHandle.write(payload as unknown as BufferSource, { at: writeOffset });
          } else if (writable) {
            await withTimeout(
              writable.write(payload as unknown as BufferSource),
              deps.writeChunkTimeoutMs ?? 10_000,
              'Writing chunk to storage timed out.'
            );
          }

          writeOffset += payload.byteLength;
          loadedBytes += payload.byteLength;

          const now = Date.now();
          if (now - lastProgressTime >= 100 || (totalBytes > 0 && loadedBytes === totalBytes)) {
            lastProgressTime = now;
            const percent = totalBytes > 0 ? Math.min(100, Math.round((loadedBytes / totalBytes) * 100)) : 50;
            deps.postMessage({
              type: 'PROGRESS',
              loadedBytes,
              totalBytes,
              percent,
            });
          }

          if (totalBytes > 0 && loadedBytes >= totalBytes && currentStage !== 'DOWNLOAD_COMPLETE') {
            currentStage = 'DOWNLOAD_COMPLETE';
            deps.postMessage({
              type: 'STAGE',
              stage: 'DOWNLOAD_COMPLETE',
            });
          }
        }
      }

      if (currentStage !== 'DOWNLOAD_COMPLETE') {
        currentStage = 'DOWNLOAD_COMPLETE';
        deps.postMessage({
          type: 'STAGE',
          stage: 'DOWNLOAD_COMPLETE',
        });
      }

      currentStage = 'CLOSING_FILE';
      deps.postMessage({
        type: 'STAGE',
        stage: 'CLOSING_FILE',
      });

      if (syncHandle) {
        syncHandle.flush();
      }
    } finally {
      if (syncHandle) {
        syncHandle.close();
      }
      if (writable) {
        await withTimeout(
          writable.close(),
          deps.closeStreamTimeoutMs ?? 10_000,
          'Closing storage file stream timed out.'
        );
      }
    }

    currentStage = 'VERIFYING';
    deps.postMessage({
      type: 'STAGE',
      stage: 'VERIFYING',
    });

    // Verify written file integrity
    const savedFile = await withTimeout(
      fileHandle.getFile(),
      deps.getFileTimeoutMs ?? 10_000,
      'Retrieving saved file for verification timed out.'
    );
    const physicalSize = savedFile.size;
    if (physicalSize < PMTILES_HEADER_SIZE) {
      throw new Error('Downloaded file is incomplete.');
    }

    const headerSlice = savedFile.slice(0, PMTILES_HEADER_SIZE);
    const headerBuffer = await withTimeout(
      headerSlice.arrayBuffer(),
      deps.readHeaderTimeoutMs ?? 10_000,
      'Reading file header for verification timed out.'
    );
    validateHeader(new Uint8Array(headerBuffer), physicalSize, `cities/${slug}/basemap.pmtiles`);

    currentStage = 'WORKER_READY';
    deps.postMessage({
      type: 'READY',
      fileSize: physicalSize,
    });
  } catch (err: unknown) {
    try {
      await withTimeout(
        deletePartial(slug),
        deps.cleanupTimeoutMs ?? 3000,
        'Cleanup timed out'
      );
    } catch {
      // Safe to ignore so error dispatch to main thread is never blocked
    }

    const rawMessage = err instanceof Error ? err.message : String(err);
    const diagnosticMessage = (rawMessage === 'Load failed' || rawMessage === 'Failed to fetch')
      ? `Failed to load map extract resource (${basemapUrl}): network connection failed (${rawMessage}).`
      : rawMessage;

    const userMessage = rawMessage.includes('corrupt') || rawMessage.includes('verification failed') || rawMessage.includes('magic')
      ? 'The downloaded map file is corrupt. Please try again.'
      : rawMessage.includes('stalled') || rawMessage.includes('timed out')
      ? `Map download stalled (stage: ${currentStage}). Please tap Retry.`
      : 'Download was interrupted. Please check your connection and try again.';

    deps.postMessage({
      type: 'ERROR',
      message: userMessage,
      stage: currentStage,
      details: `Stage: ${currentStage}\nDiagnostic: ${diagnosticMessage}`,
    });
  }
}
