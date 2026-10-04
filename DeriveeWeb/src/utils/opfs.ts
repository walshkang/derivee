import type { InstalledPackState, PackFileEntry } from '../types/pack';

export const REQUIRED_PACK_FILES = [
  'city_config.json',
  'transit.sqlite',
  'transit-lines.geojson',
  'ultra_transfers.csr',
  'timetable.bin',
  'walk_graph.bin',
] as const;

export const LOCAL_STORAGE_PACK_KEY = 'derivee_pack_nyc';
export const LOCAL_STORAGE_PACK_DISMISSED_KEY = 'derivee_pack_dismissed';

export function isPackDismissed(): boolean {
  try {
    return localStorage.getItem(LOCAL_STORAGE_PACK_DISMISSED_KEY) === 'true';
  } catch {
    return false;
  }
}

export function setPackDismissed(dismissed: boolean): void {
  try {
    if (dismissed) {
      localStorage.setItem(LOCAL_STORAGE_PACK_DISMISSED_KEY, 'true');
    } else {
      localStorage.removeItem(LOCAL_STORAGE_PACK_DISMISSED_KEY);
    }
  } catch {
    // Ignore storage quota or permission errors
  }
}

export function isOpfsSupported(): boolean {
  return typeof navigator !== 'undefined' &&
    'storage' in navigator &&
    typeof navigator.storage?.getDirectory === 'function';
}

/**
 * Returns the OPFS root directory handle.
 */
export async function getOpfsRoot(): Promise<FileSystemDirectoryHandle> {
  if (!isOpfsSupported()) {
    throw new Error('Origin Private File System (OPFS) is not supported in this browser.');
  }
  return await navigator.storage.getDirectory();
}

/**
 * Returns the city directory handle (e.g. "nyc").
 */
export async function getCityDirectory(
  slug: string = 'nyc',
  create: boolean = false
): Promise<FileSystemDirectoryHandle | null> {
  const root = await getOpfsRoot();
  try {
    return await root.getDirectoryHandle(slug, { create });
  } catch (err) {
    if (!create) return null;
    throw err;
  }
}

/**
 * Writes a binary chunk to an OPFS file handle.
 * Compatible with standard createWritable() and Safari Web Worker createSyncAccessHandle().
 */
export async function writeOpfsFile(
  dirHandle: FileSystemDirectoryHandle,
  fileName: string,
  data: Uint8Array
): Promise<void> {
  const fileHandle = await dirHandle.getFileHandle(fileName, { create: true });

  // WebKit Safari Web Worker fallback
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

/**
 * Reads header bytes or full content from a file in OPFS.
 */
export async function readOpfsFileHeader(
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

/**
 * Recursively deletes a city pack folder from OPFS.
 */
export async function deleteCityPack(slug: string = 'nyc'): Promise<void> {
  try {
    const root = await getOpfsRoot();
    try {
      await root.removeEntry(slug, { recursive: true });
    } catch (dirRemoveErr) {
      // eslint-disable-next-line no-console
      console.warn(`[OPFS] Recursive removeEntry failed for ${slug}, attempting individual file deletion:`, dirRemoveErr);
      try {
        const dir = await root.getDirectoryHandle(slug);
        for (const name of REQUIRED_PACK_FILES) {
          try {
            await dir.removeEntry(name);
          } catch {
            // Ignore missing file
          }
        }
        await root.removeEntry(slug, { recursive: true });
      } catch {
        // Safe to ignore fallback error
      }
    }
    localStorage.removeItem(LOCAL_STORAGE_PACK_KEY);
    localStorage.removeItem(LOCAL_STORAGE_PACK_DISMISSED_KEY);
  } catch (err) {
    // Ignore error if directory did not exist
    // eslint-disable-next-line no-console
    console.warn(`[OPFS] Cleanup for ${slug} produced error (safe to ignore if not exists):`, err);
  }
}

/**
 * Validates that all required pack files exist in OPFS and returns their sizes.
 * Returns null if any required file is missing or empty.
 */
export async function verifyOpfsPackFiles(slug: string = 'nyc'): Promise<PackFileEntry[] | null> {
  if (!isOpfsSupported()) return null;

  try {
    const dirHandle = await getCityDirectory(slug, false);
    if (!dirHandle) return null;

    const files: PackFileEntry[] = [];

    for (const name of REQUIRED_PACK_FILES) {
      try {
        const fileHandle = await dirHandle.getFileHandle(name);
        const file = await fileHandle.getFile();
        if (file.size <= 0) {
          return null; // Empty file is invalid
        }
        files.push({ name, size: file.size });
      } catch {
        return null; // File missing
      }
    }

    return files;
  } catch {
    return null;
  }
}

/**
 * Checks both localStorage and real OPFS filesystem to confirm installed status.
 */
export async function checkFullPackInstallState(slug: string = 'nyc'): Promise<InstalledPackState | null> {
  const rawMeta = localStorage.getItem(LOCAL_STORAGE_PACK_KEY);
  const filesOnDisk = await verifyOpfsPackFiles(slug);

  if (!filesOnDisk) {
    if (rawMeta) {
      localStorage.removeItem(LOCAL_STORAGE_PACK_KEY);
    }
    return null;
  }

  if (rawMeta) {
    try {
      const parsed = JSON.parse(rawMeta) as InstalledPackState;
      parsed.files = filesOnDisk;
      parsed.totalBytes = filesOnDisk.reduce((acc, f) => acc + f.size, 0);
      return parsed;
    } catch {
      // Fallback below
    }
  }

  let diskVersion = 4;
  let displayName = slug === 'nyc' ? 'New York City' : slug.toUpperCase();
  let seasonLabel = 'Summer 2026 Timetable';
  try {
    const dir = await getCityDirectory(slug, false);
    if (dir) {
      const cfgHandle = await dir.getFileHandle('city_config.json');
      const file = await cfgHandle.getFile();
      const text = await file.text();
      const parsed = JSON.parse(text);
      if (typeof parsed.version === 'number') diskVersion = parsed.version;
      if (parsed.displayName) displayName = parsed.displayName;
      if (parsed.transit?.scheduleValidity?.seasonLabel) {
        seasonLabel = parsed.transit.scheduleValidity.seasonLabel;
      }
    }
  } catch {
    // Fallback defaults
  }

  // Files exist on disk, synthesize state if localStorage was cleared
  return {
    isInstalled: true,
    slug,
    version: diskVersion,
    displayName,
    seasonLabel,
    installedAt: new Date().toISOString(),
    totalBytes: filesOnDisk.reduce((acc, f) => acc + f.size, 0),
    files: filesOnDisk,
  };
}

export function saveInstalledPackState(state: InstalledPackState | null): void {
  if (!state) {
    localStorage.removeItem(LOCAL_STORAGE_PACK_KEY);
  } else {
    localStorage.setItem(LOCAL_STORAGE_PACK_KEY, JSON.stringify(state));
    try {
      const raw = localStorage.getItem('derivee_city_pack_versions');
      const versions = raw ? JSON.parse(raw) : {};
      versions[state.slug] = state.version;
      localStorage.setItem('derivee_city_pack_versions', JSON.stringify(versions));
    } catch {
      // Ignore storage errors
    }
  }
}

// ============================================================================
// M4a: Offline NYC Basemap OPFS Storage
// Path: cities/nyc/basemap.pmtiles
// ============================================================================

export const BASEMAP_DIR = 'cities';
export const BASEMAP_CITY = 'nyc';
export const BASEMAP_FILENAME = 'basemap.pmtiles';
export const BASEMAP_OPFS_PATH = 'cities/nyc/basemap.pmtiles';

/**
 * Returns the directory handle for cities/<city>/ in OPFS.
 */
export async function getBasemapDirectory(
  city: string = 'nyc',
  create: boolean = false
): Promise<FileSystemDirectoryHandle | null> {
  const root = await getOpfsRoot();
  try {
    const citiesDir = await root.getDirectoryHandle(BASEMAP_DIR, { create });
    return await citiesDir.getDirectoryHandle(city, { create });
  } catch (err) {
    if (!create) return null;
    throw err;
  }
}

/**
 * Returns the File object for cities/<city>/basemap.pmtiles, or null if missing.
 */
export async function getBasemapFile(
  city: string = 'nyc'
): Promise<File | null> {
  const dir = await getBasemapDirectory(city, false);
  if (!dir) return null;
  try {
    const handle = await dir.getFileHandle(BASEMAP_FILENAME);
    return await handle.getFile();
  } catch {
    return null;
  }
}

/**
 * Deletes the basemap file cities/<city>/basemap.pmtiles if present.
 */
export async function deleteBasemap(city: string = 'nyc'): Promise<void> {
  try {
    const root = await getOpfsRoot();
    try {
      const citiesDir = await root.getDirectoryHandle(BASEMAP_DIR, { create: false });
      const cityDir = await citiesDir.getDirectoryHandle(city, { create: false });
      await cityDir.removeEntry(BASEMAP_FILENAME);
    } catch {
      // Safe to ignore if missing
    }
  } catch {
    // Safe to ignore if OPFS unavailable
  }
}

/**
 * Validates that the basemap file exists in OPFS and has a valid PMTiles v3 header.
 */
export async function checkBasemapInstalled(city: string = 'nyc'): Promise<boolean> {
  if (!isOpfsSupported()) return false;

  try {
    const file = await getBasemapFile(city);
    if (!file || file.size < 127) return false;

    const slice = file.slice(0, 127);
    const arrayBuffer = await slice.arrayBuffer();
    const { validatePMTilesHeader } = await import('./pmtilesIntegrity');
    validatePMTilesHeader(new Uint8Array(arrayBuffer), file.size, `cities/${city}/${BASEMAP_FILENAME}`);
    return true;
  } catch {
    return false;
  }
}

