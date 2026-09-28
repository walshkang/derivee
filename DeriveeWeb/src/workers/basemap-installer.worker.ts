/// <reference lib="webworker" />

import type { MainToBasemapWorkerMessage, BasemapWorkerToMainMessage } from '../types/basemap';
import { validatePMTilesHeader, PMTILES_HEADER_SIZE } from '../utils/pmtilesIntegrity';

declare const self: DedicatedWorkerGlobalScope;

async function getCityDirectoryHandle(slug: string = 'nyc'): Promise<FileSystemDirectoryHandle> {
  const root = await navigator.storage.getDirectory();
  const citiesDir = await root.getDirectoryHandle('cities', { create: true });
  return await citiesDir.getDirectoryHandle(slug, { create: true });
}

async function deletePartialFile(slug: string = 'nyc'): Promise<void> {
  try {
    const root = await navigator.storage.getDirectory();
    const citiesDir = await root.getDirectoryHandle('cities', { create: false });
    const cityDir = await citiesDir.getDirectoryHandle(slug, { create: false });
    await cityDir.removeEntry('basemap.pmtiles');
  } catch {
    // Ignore if not exists
  }
}

async function runBasemapInstall(slug: string = 'nyc', basemapUrl: string = '/api/basemap?city=nyc'): Promise<void> {
  try {
    self.postMessage({
      type: 'PROGRESS',
      loadedBytes: 0,
      totalBytes: 24991495, // Default NYC PMTiles extract size
      percent: 0,
    } satisfies BasemapWorkerToMainMessage);

    const response = await fetch(basemapUrl, {
      credentials: 'include',
      headers: {
        Accept: 'application/vnd.pmtiles, application/octet-stream',
      },
    });

    if (!response.ok || !response.body) {
      throw new Error('Download request failed. Please check your connection.');
    }

    const contentLengthHeader = response.headers.get('Content-Length');
    const totalBytes = contentLengthHeader ? parseInt(contentLengthHeader, 10) : 24991495;

    const cityDir = await getCityDirectoryHandle(slug);
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

    const reader = response.body.getReader();
    let loadedBytes = 0;
    let writeOffset = 0;
    let lastProgressTime = 0;

    try {
      while (true) {
        const { done, value } = await reader.read();
        if (done) break;
        if (value) {
          // Normalize to byteOffset 0 for iOS Safari bug
          const payload = (value.byteOffset === 0 && value.byteLength === value.buffer.byteLength)
            ? value
            : value.slice();

          if (syncHandle) {
            syncHandle.write(payload as unknown as BufferSource, { at: writeOffset });
          } else if (writable) {
            await writable.write(payload as unknown as BufferSource);
          }

          writeOffset += payload.byteLength;
          loadedBytes += payload.byteLength;

          const now = Date.now();
          if (now - lastProgressTime >= 100 || (totalBytes > 0 && loadedBytes === totalBytes)) {
            lastProgressTime = now;
            const percent = totalBytes > 0 ? Math.min(100, Math.round((loadedBytes / totalBytes) * 100)) : 50;
            self.postMessage({
              type: 'PROGRESS',
              loadedBytes,
              totalBytes,
              percent,
            } satisfies BasemapWorkerToMainMessage);
          }
        }
      }

      if (syncHandle) {
        syncHandle.flush();
      }
    } finally {
      if (syncHandle) {
        syncHandle.close();
      }
      if (writable) {
        await writable.close();
      }
    }

    // Verify written file integrity
    const savedFile = await fileHandle.getFile();
    const physicalSize = savedFile.size;
    if (physicalSize < PMTILES_HEADER_SIZE) {
      throw new Error('Downloaded file is incomplete.');
    }

    const headerSlice = savedFile.slice(0, PMTILES_HEADER_SIZE);
    const headerBuffer = await headerSlice.arrayBuffer();
    validatePMTilesHeader(new Uint8Array(headerBuffer), physicalSize, `cities/${slug}/basemap.pmtiles`);

    self.postMessage({
      type: 'READY',
      fileSize: physicalSize,
    } satisfies BasemapWorkerToMainMessage);
  } catch (err: unknown) {
    await deletePartialFile(slug);
    const rawMessage = err instanceof Error ? err.message : String(err);
    const userMessage = rawMessage.includes('corrupt') || rawMessage.includes('verification failed') || rawMessage.includes('magic')
      ? 'The downloaded map file is corrupt. Please try again.'
      : 'Download was interrupted. Please check your connection and try again.';

    self.postMessage({
      type: 'ERROR',
      message: userMessage,
    } satisfies BasemapWorkerToMainMessage);
  }
}

self.onmessage = async (e: MessageEvent<MainToBasemapWorkerMessage>) => {
  if (e.data.type === 'START_INSTALL') {
    const slug = e.data.slug || 'nyc';
    const url = e.data.url || `/api/basemap?city=${slug}`;
    await runBasemapInstall(slug, url);
  }
};
