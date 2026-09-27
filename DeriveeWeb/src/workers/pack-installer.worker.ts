/// <reference lib="webworker" />

import { init, decompress } from '@bokuweb/zstd-wasm';
import { parseTar } from 'nanotar';
import type { MainToWorkerMessage, WorkerToMainMessage, InstalledPackState, PackFileEntry } from '../types/pack';
import {
  MAGIC_TIMETABLE_DRV1,
  MAGIC_WALK_GRAPH,
  MAGIC_ULTRA_CSR,
  validateSqliteDatabase,
  validateMasterHeader,
  validateBinaryHeader,
  validateCityConfig,
  validateTransitLinesGeoJson,
  PackIntegrityError,
} from '../utils/packIntegrity';

declare const self: DedicatedWorkerGlobalScope;

async function writeOpfsEntry(
  dirHandle: FileSystemDirectoryHandle,
  fileName: string,
  data: Uint8Array
): Promise<void> {
  const fileHandle = await dirHandle.getFileHandle(fileName, { create: true });

  // WebKit / Safari Web Worker FileSystemSyncAccessHandle
  const handleAny = fileHandle as unknown as {
    createSyncAccessHandle?: () => Promise<{
      truncate: (size: number) => void;
      write: (buffer: BufferSource, options?: { at: number }) => number;
      flush: () => void;
      close: () => void;
    }>;
    createWritable?: () => Promise<FileSystemWritableFileStream>;
  };

  // Ensure buffer starts at byteOffset 0 to guard against WebKit bug where
  // FileSystemSyncAccessHandle.write ignores byteOffset.
  const payload = (data.byteOffset === 0 && data.byteLength === data.buffer.byteLength)
    ? data
    : data.slice();

  if (typeof handleAny.createSyncAccessHandle === 'function' && typeof handleAny.createWritable !== 'function') {
    const accessHandle = await handleAny.createSyncAccessHandle();
    try {
      accessHandle.truncate(0);
      accessHandle.write(payload as unknown as BufferSource, { at: 0 });
      accessHandle.flush();
    } finally {
      accessHandle.close();
    }
    return;
  }

  // Standard FileSystemWritableFileStream
  const writable = await fileHandle.createWritable();
  try {
    await writable.write(payload as unknown as BufferSource);
  } finally {
    await writable.close();
  }
}

async function readFileHeader(
  dirHandle: FileSystemDirectoryHandle,
  fileName: string,
  byteCount: number
): Promise<{ headerBytes: Uint8Array; physicalSize: number }> {
  const fileHandle = await dirHandle.getFileHandle(fileName);
  const file = await fileHandle.getFile();
  const physicalSize = file.size;
  const slice = file.slice(0, Math.min(byteCount, physicalSize));
  const arrayBuffer = await slice.arrayBuffer();
  return {
    headerBytes: new Uint8Array(arrayBuffer),
    physicalSize,
  };
}

async function readFullText(
  dirHandle: FileSystemDirectoryHandle,
  fileName: string
): Promise<string> {
  const fileHandle = await dirHandle.getFileHandle(fileName);
  const file = await fileHandle.getFile();
  return await file.text();
}

async function runInstallation(slug: string = 'nyc', packUrl: string = '/api/pack'): Promise<void> {
  let rootHandle: FileSystemDirectoryHandle | null = null;
  let packDirHandle: FileSystemDirectoryHandle | null = null;

  try {
    rootHandle = await navigator.storage.getDirectory();

    // 1. Fetch pack stream from Worker
    self.postMessage({
      type: 'PROGRESS',
      stage: 'downloading',
      loadedBytes: 0,
      totalBytes: 29688421, // default NYC compressed size
      percent: 0,
    } satisfies WorkerToMainMessage);

    const response = await fetch(packUrl, {
      credentials: 'include',
      headers: {
        Accept: 'application/zstd, application/octet-stream',
      },
    });

    if (response.status === 401) {
      self.postMessage({
        type: 'ERROR',
        code: 401,
        message: 'Unauthorized: Session missing Cloudflare Access identity. Please sign in.',
      } satisfies WorkerToMainMessage);
      return;
    }

    if (response.status === 429) {
      self.postMessage({
        type: 'ERROR',
        code: 429,
        message: 'Rate limited: 10 downloads per minute exceeded. Please try again in a minute.',
      } satisfies WorkerToMainMessage);
      return;
    }

    if (!response.ok || !response.body) {
      self.postMessage({
        type: 'ERROR',
        code: response.status,
        message: `Pack download failed with HTTP ${response.status} (${response.statusText})`,
      } satisfies WorkerToMainMessage);
      return;
    }

    const contentLengthHeader = response.headers.get('Content-Length');
    const totalBytes = contentLengthHeader ? parseInt(contentLengthHeader, 10) : 29688421;

    // 2. Stream download chunks with progress
    const reader = response.body.getReader();
    const chunks: Uint8Array[] = [];
    let loadedBytes = 0;
    let lastProgressTime = 0;

    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      if (value) {
        chunks.push(value);
        loadedBytes += value.length;
        const now = Date.now();
        if (now - lastProgressTime >= 100 || loadedBytes === totalBytes) {
          lastProgressTime = now;
          self.postMessage({
            type: 'PROGRESS',
            stage: 'downloading',
            loadedBytes,
            totalBytes,
            percent: Math.min(100, Math.round((loadedBytes / totalBytes) * 100)),
          } satisfies WorkerToMainMessage);
        }
      }
    }

    // 3. Assemble compressed buffer
    const compressedBuffer = new Uint8Array(loadedBytes);
    let chunkOffset = 0;
    for (const chunk of chunks) {
      compressedBuffer.set(chunk, chunkOffset);
      chunkOffset += chunk.length;
    }

    // 4. Decompress Zstandard archive via @bokuweb/zstd-wasm
    self.postMessage({
      type: 'PROGRESS',
      stage: 'decompressing',
      message: 'Decompressing 29.7 MB NYC transit archive via Zstandard WASM...',
    } satisfies WorkerToMainMessage);

    await init();
    const decompressed = decompress(compressedBuffer);

    // 5. Parse Tar Archive
    const parsedEntries = parseTar(decompressed);
    const validFiles = parsedEntries
      .filter((e) => (e.type === 'file' || !e.type) && e.name && e.data)
      .map((e) => ({ ...e, data: e.data!.slice() })); // slice() copies → byteOffset 0

    if (validFiles.length === 0) {
      throw new Error('Tar archive contained no valid files.');
    }

    // 6. Write files to OPFS directory (e.g. /nyc/)
    packDirHandle = await rootHandle.getDirectoryHandle(slug, { create: true });
    const totalFiles = validFiles.length;
    let filesWritten = 0;

    for (const entry of validFiles) {
      self.postMessage({
        type: 'PROGRESS',
        stage: 'writing',
        filesWritten,
        totalFiles,
        currentFile: entry.name,
        percent: Math.round((filesWritten / totalFiles) * 100),
      } satisfies WorkerToMainMessage);

      await writeOpfsEntry(packDirHandle, entry.name, entry.data!);
      filesWritten++;
    }

    self.postMessage({
      type: 'PROGRESS',
      stage: 'writing',
      filesWritten: totalFiles,
      totalFiles,
      percent: 100,
    } satisfies WorkerToMainMessage);

    // 7. Verify Integrity per T.1b Swift Mirror (CityPackManager.swift)
    self.postMessage({
      type: 'PROGRESS',
      stage: 'verifying',
      message: 'Verifying binary signatures, headers, and schemas...',
    } satisfies WorkerToMainMessage);

    // Validate transit.sqlite
    const sqliteHeader = await readFileHeader(packDirHandle, 'transit.sqlite', 16);
    validateSqliteDatabase(sqliteHeader.headerBytes, sqliteHeader.physicalSize, 'transit.sqlite');

    // Validate timetable.bin (MasterHeader, DRV1, 232B)
    const timetableHeader = await readFileHeader(packDirHandle, 'timetable.bin', 40);
    validateMasterHeader(
      timetableHeader.headerBytes,
      timetableHeader.physicalSize,
      MAGIC_TIMETABLE_DRV1,
      1,
      'timetable.bin'
    );

    // Validate walk_graph.bin (MasterHeader, WALK, 232B)
    const walkHeader = await readFileHeader(packDirHandle, 'walk_graph.bin', 40);
    validateMasterHeader(
      walkHeader.headerBytes,
      walkHeader.physicalSize,
      MAGIC_WALK_GRAPH,
      1,
      'walk_graph.bin'
    );

    // Validate ultra_transfers.csr (BinaryHeader, ULTR, 32B)
    const ultraHeader = await readFileHeader(packDirHandle, 'ultra_transfers.csr', 8);
    validateBinaryHeader(
      ultraHeader.headerBytes,
      ultraHeader.physicalSize,
      MAGIC_ULTRA_CSR,
      1,
      'ultra_transfers.csr'
    );

    // Validate city_config.json
    const configText = await readFullText(packDirHandle, 'city_config.json');
    const config = validateCityConfig(configText);

    // Validate transit-lines.geojson
    const geojsonText = await readFullText(packDirHandle, 'transit-lines.geojson');
    validateTransitLinesGeoJson(geojsonText);

    // Collect finalized file list
    const finalizedFiles: PackFileEntry[] = [];
    let totalUncompressedBytes = 0;
    for (const entry of validFiles) {
      const fileHandle = await packDirHandle.getFileHandle(entry.name);
      const file = await fileHandle.getFile();
      finalizedFiles.push({ name: entry.name, size: file.size });
      totalUncompressedBytes += file.size;
    }

    const packState: InstalledPackState = {
      isInstalled: true,
      slug,
      version: config.version,
      displayName: config.displayName || 'New York City',
      seasonLabel: config.transit?.scheduleValidity?.seasonLabel || 'Summer 2026 Timetable',
      installedAt: new Date().toISOString(),
      totalBytes: totalUncompressedBytes,
      files: finalizedFiles,
    };

    self.postMessage({
      type: 'SUCCESS',
      packState,
    } satisfies WorkerToMainMessage);
  } catch (err) {
    // eslint-disable-next-line no-console
    console.error('[PackInstallerWorker] Error during installation:', err);

    // Atomically purge corrupt / incomplete pack files from OPFS
    try {
      const root = rootHandle || (await navigator.storage?.getDirectory?.());
      if (root && slug) {
        try {
          await root.removeEntry(slug, { recursive: true });
          // eslint-disable-next-line no-console
          console.warn(`[PackInstallerWorker] Purged partial directory /${slug} due to install failure.`);
        } catch (dirRemoveErr) {
          // Fallback: If recursive removeEntry fails, delete files individually to guarantee clean state
          // eslint-disable-next-line no-console
          console.warn(`[PackInstallerWorker] Recursive removeEntry failed for /${slug}, attempting individual file deletion:`, dirRemoveErr);
          try {
            const dir = packDirHandle || (await root.getDirectoryHandle(slug));
            const knownFiles = [
              'city_config.json',
              'transit.sqlite',
              'transit-lines.geojson',
              'ultra_transfers.csr',
              'timetable.bin',
              'walk_graph.bin',
            ];
            for (const file of knownFiles) {
              try {
                await dir.removeEntry(file);
              } catch {
                // Ignore missing file
              }
            }
            await root.removeEntry(slug, { recursive: true });
          } catch {
            // Safe to ignore fallback error
          }
        }
      }
    } catch {
      // Safe to ignore if storage inaccessible
    }

    const message = err instanceof PackIntegrityError
      ? err.message
      : err instanceof Error
        ? err.message
        : String(err);

    self.postMessage({
      type: 'ERROR',
      message: `Installation failed: ${message}`,
    } satisfies WorkerToMainMessage);
  }
}

self.onmessage = async (event: MessageEvent<MainToWorkerMessage>) => {
  const { type, slug = 'nyc', packUrl = '/api/pack' } = event.data;
  if (type === 'START_INSTALL') {
    await runInstallation(slug, packUrl);
  }
};
