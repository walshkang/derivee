/**
 * routingEngine.ts
 * Core logic and WASM lifecycle orchestration for offline transit routing.
 */

import type {
  RoutingSegment,
  RoutingWorkerIncomingMessage,
  RoutingWorkerOutgoingMessage,
  RoutingProfile,
  RoutePatternEntry,
} from '../types/routing.ts';
import {
  ROUTING_FLAG_NONE,
  ROUTING_FLAG_AVOID_TRANSFERS,
} from '../types/routing.ts';


export { ROUTING_FLAG_NONE, ROUTING_FLAG_AVOID_TRANSFERS };
export const TRIP_TRANSFER = 0xFFFFFFFF;
export const ROUTE_TRANSFER = 0xFFFF;


export interface DeriveeWasmModule {
  HEAPU8: Uint8Array;
  HEAP32: Int32Array;
  HEAPF32: Float32Array;
  _allocate_aligned(size: number, alignment: number): number;
  _engine_create(): number;
  _engine_destroy(enginePtr: number): void;
  _engine_load_timetable(enginePtr: number, buffer: number, size: number): number | boolean;
  _engine_load_ultra(enginePtr: number, buffer: number, size: number): number | boolean;
  _engine_load_walk_graph(enginePtr: number, buffer: number, size: number): number | boolean;
  _engine_compute_journey(enginePtr: number, paramsPtr: number): number;
  _engine_free_result(resultPtr: number): void;
  _malloc(size: number): number;
  _free(ptr: number): void;
}

/**
 * Aligns exactly with native JourneySegment::is_transfer_leg()
 * in TimetableStructs.hpp:123-125 (TRIP_TRANSFER = 0xFFFFFFFF, ROUTE_TRANSFER = 0xFFFF).
 */
export function isTransferLeg(tripId: number, routeId: number): boolean {
  return tripId === TRIP_TRANSFER || routeId === ROUTE_TRANSFER;
}

/**
 * Instantiates the Emscripten WASM module ensuring errors in WebAssembly.instantiate
 * propagate immediately rather than hanging indefinitely when receiveInstance is not called.
 */
export async function instantiateDeriveeCore(
  factory: (moduleArg: any) => Promise<DeriveeWasmModule>,
  wasmBinary: ArrayBuffer | Uint8Array
): Promise<DeriveeWasmModule> {
  let rejectInstantiate: ((err: any) => void) | null = null;
  const instantiateFailPromise = new Promise<never>((_, reject) => {
    rejectInstantiate = reject;
  });

  const modulePromise = factory({
    instantiateWasm: (
      info: WebAssembly.Imports,
      receiveInstance: (inst: WebAssembly.Instance) => void
    ) => {
      try {
        WebAssembly.instantiate(wasmBinary, info)
          .then((res: any) => {
            receiveInstance(res.instance ?? res);
          })
          .catch((err) => {
            if (rejectInstantiate) {
              rejectInstantiate(err);
            }
          });
      } catch (err) {
        if (rejectInstantiate) {
          rejectInstantiate(err);
        }
      }
      return {};
    },
  });

  return await Promise.race([modulePromise, instantiateFailPromise]);
}

/**
 * Loads the WASM module glue in a classic worker via importScripts('/wasm/derivee_core.js')
 * and hydrates the binary via instantiateDeriveeCore.
 */
export async function loadWasmModule(options?: {
  factory?: (arg: any) => Promise<DeriveeWasmModule>;
  wasmBinary?: ArrayBuffer | Uint8Array;
}): Promise<DeriveeWasmModule> {
  let factory = options?.factory;
  if (!factory) {
    const globalScope = self as unknown as {
      DeriveeCoreModule?: (arg: any) => Promise<DeriveeWasmModule>;
      importScripts?: (...urls: string[]) => void;
    };

    if (typeof globalScope.DeriveeCoreModule !== 'function') {
      if (typeof globalScope.importScripts === 'function') {
        globalScope.importScripts('/wasm/derivee_core.js');
      } else {
        throw new Error('importScripts is not available in this environment');
      }
    }

    factory = globalScope.DeriveeCoreModule;
  }

  if (typeof factory !== 'function') {
    throw new Error('DeriveeCoreModule factory not found after importScripts');
  }

  let wasmBinary = options?.wasmBinary;
  if (!wasmBinary) {
    const wasmResp = await fetch('/wasm/derivee_core.wasm');
    if (!wasmResp.ok) {
      throw new Error(`Failed to load WASM binary /wasm/derivee_core.wasm (status ${wasmResp.status})`);
    }
    wasmBinary = await wasmResp.arrayBuffer();
  }

  return await instantiateDeriveeCore(factory, wasmBinary);
}

export async function readBinaryIntoWasm(
  fileHandle: FileSystemFileHandle,
  wasm: DeriveeWasmModule,
  alignment: number = 64
): Promise<{ ptr: number; size: number }> {
  const accessHandle = await fileHandle.createSyncAccessHandle();
  try {
    const size = accessHandle.getSize();
    if (size <= 0) {
      throw new Error(`File ${fileHandle.name} is empty (0 bytes)`);
    }

    const ptr = wasm._allocate_aligned(size, alignment);
    if (!ptr) {
      throw new Error(`Failed to allocate ${size} bytes (${alignment}-byte aligned) in WASM heap`);
    }

    let bytesRead = 0;
    while (bytesRead < size) {
      const slice = new Uint8Array(wasm.HEAPU8.buffer, ptr + bytesRead, size - bytesRead);
      const readChunk = accessHandle.read(slice, { at: bytesRead });
      if (readChunk === 0) break;
      bytesRead += readChunk;
    }

    if (bytesRead < size) {
      throw new Error(`Incomplete read for ${fileHandle.name}: read ${bytesRead} of ${size} bytes`);
    }

    return { ptr, size };
  } finally {
    accessHandle.close();
  }
}

export async function hydrateOpfsBinaries(
  wasm: DeriveeWasmModule,
  enginePtr: number,
  citySlug: string = 'nyc'
): Promise<void> {
  const root = await navigator.storage.getDirectory();
  const cityDir = await root.getDirectoryHandle(citySlug, { create: false });

  // 1. walk_graph.bin (~45-47 MB)
  const walkFile = await cityDir.getFileHandle('walk_graph.bin');
  const walkAlloc = await readBinaryIntoWasm(walkFile, wasm, 64);
  const walkOk = wasm._engine_load_walk_graph(enginePtr, walkAlloc.ptr, walkAlloc.size);
  if (!walkOk) {
    throw new Error('RaptorEngine rejected walk_graph.bin (format or alignment error)');
  }

  // 2. timetable.bin (~6.9 MB)
  const ttFile = await cityDir.getFileHandle('timetable.bin');
  const ttAlloc = await readBinaryIntoWasm(ttFile, wasm, 64);
  const ttOk = wasm._engine_load_timetable(enginePtr, ttAlloc.ptr, ttAlloc.size);
  if (!ttOk) {
    throw new Error('RaptorEngine rejected timetable.bin (schema or CRC error)');
  }

  // 3. ultra_transfers.csr (~0.6 MB)
  const ultraFile = await cityDir.getFileHandle('ultra_transfers.csr');
  const ultraAlloc = await readBinaryIntoWasm(ultraFile, wasm, 64);
  const ultraOk = wasm._engine_load_ultra(enginePtr, ultraAlloc.ptr, ultraAlloc.size);
  if (!ultraOk) {
    throw new Error('RaptorEngine rejected ultra_transfers.csr (signature error)');
  }
}

export function computeJourneySegments(
  wasm: DeriveeWasmModule,
  enginePtr: number,
  originStopId: number,
  destStopId: number,
  departureTimestamp: number,
  flags: number = ROUTING_FLAG_NONE
): RoutingSegment[] {
  // QueryParams struct: origin(4) + dest(4) + dep(4) + max_transfers(2) + flags(2) = 16 bytes
  const qPtr = wasm._malloc(16);
  if (!qPtr) {
    throw new Error('Failed to allocate 16 bytes for QueryParams');
  }

  try {
    const qDv = new DataView(wasm.HEAPU8.buffer, qPtr, 16);
    qDv.setUint32(0, originStopId, true);
    qDv.setUint32(4, destStopId, true);
    qDv.setUint32(8, departureTimestamp, true);
    qDv.setUint16(12, 4, true); // max_transfers: 4
    qDv.setUint16(14, flags, true); // flags: 0 (Fastest) or 2 (Fewest Transfers)


    const resPtr = wasm._engine_compute_journey(enginePtr, qPtr);
    if (!resPtr) {
      return [];
    }

    try {
      // JourneyResult struct: segs* (uint32_t) + count (uint32_t) = 8 bytes
      const resDv = new DataView(wasm.HEAPU8.buffer, resPtr, 8);
      const segsPtr = resDv.getUint32(0, true);
      const count = resDv.getUint32(4, true);

      const segments: RoutingSegment[] = [];

      if (segsPtr && count > 0) {
        for (let i = 0; i < count; i++) {
          const segDv = new DataView(wasm.HEAPU8.buffer, segsPtr + i * 24, 24);
          const board = segDv.getUint32(0, true);
          const exit = segDv.getUint32(4, true);
          const trip = segDv.getUint32(8, true);
          const dep = segDv.getUint32(12, true);
          const arr = segDv.getUint32(16, true);
          const route = segDv.getUint16(20, true);
          const dist = segDv.getUint16(22, true);

          const isTransfer = isTransferLeg(trip, route);

          segments.push({
            board_stop_id: board,
            exit_stop_id: exit,
            trip_id: trip,
            departure_time: dep,
            arrival_time: arr,
            route_id: route,
            transfer_distance_m: dist,
            is_transfer: isTransfer,
          });
        }
      }

      return segments;
    } finally {
      wasm._engine_free_result(resPtr);
    }
  } finally {
    wasm._free(qPtr);
  }
}

export interface WorkerOrchestrationOptions {
  postMessage: (msg: RoutingWorkerOutgoingMessage) => void;
  loadWasm?: () => Promise<DeriveeWasmModule>;
  hydrateBinaries?: (wasm: DeriveeWasmModule, enginePtr: number, citySlug: string) => Promise<void>;
  initTimeoutMs?: number;
}

export function createRoutingWorkerHandler(options: WorkerOrchestrationOptions) {
  const timeoutMs = options.initTimeoutMs ?? 30000;
  let wasmModule: DeriveeWasmModule | null = null;
  let enginePtr: number | null = null;
  let isInitialized = false;
  let cachedPatterns: RoutePatternEntry[] | undefined;
  let initPromise: Promise<{ loadTimeMs: number; patterns?: RoutePatternEntry[] }> | null = null;

  async function init(citySlug: string): Promise<{ loadTimeMs: number; patterns?: RoutePatternEntry[] }> {
    const startTime = performance.now();
    const wasm = options.loadWasm ? await options.loadWasm() : await loadWasmModule();
    const ePtr = wasm._engine_create();
    if (!ePtr) {
      throw new Error('Failed to create RaptorEngine instance');
    }
    wasmModule = wasm;
    enginePtr = ePtr;

    if (options.hydrateBinaries) {
      await options.hydrateBinaries(wasm, ePtr, citySlug);
    } else {
      await hydrateOpfsBinaries(wasm, ePtr, citySlug);
    }

    let patternsTable: RoutePatternEntry[] | null = null;
    try {
      const root = await navigator.storage.getDirectory();
      const cityDir = await root.getDirectoryHandle(citySlug, { create: false });
      const patternsHandle = await cityDir.getFileHandle('patterns.json');
      const file = await patternsHandle.getFile();
      const text = await file.text();
      patternsTable = JSON.parse(text);
    } catch {
      // Old pack or file absent: degrade gracefully to null
      patternsTable = null;
    }

    cachedPatterns = patternsTable ?? undefined;
    isInitialized = true;
    return {
      loadTimeMs: Math.round(performance.now() - startTime),
      patterns: cachedPatterns,
    };
  }

  return async function onMessage(msg: RoutingWorkerIncomingMessage): Promise<void> {
    try {
      switch (msg.type) {
        case 'INIT': {
          if (isInitialized && enginePtr) {
            options.postMessage({ type: 'READY', loadTimeMs: 0, patterns: cachedPatterns });
            return;
          }

          if (!initPromise) {
            initPromise = init(msg.city || 'nyc');
          }

          let timer: ReturnType<typeof setTimeout> | null = null;
          const timeoutPromise = new Promise<never>((_, reject) => {
            timer = setTimeout(() => {
              reject(new Error('engine init timed out'));
            }, timeoutMs);
          });

          try {
            const initResult = await Promise.race([initPromise, timeoutPromise]);
            if (timer) clearTimeout(timer);
            options.postMessage({ type: 'READY', loadTimeMs: initResult.loadTimeMs, patterns: initResult.patterns });
          } catch (err: any) {
            if (timer) clearTimeout(timer);
            initPromise = null;
            throw err;
          }
          break;
        }

        case 'ROUTE': {
          if (!wasmModule || !enginePtr || !isInitialized) {
            throw new Error('Routing engine is not initialized');
          }
          const flags = msg.flags !== undefined
            ? msg.flags
            : (msg.profile === 'fewest_transfers' ? ROUTING_FLAG_AVOID_TRANSFERS : ROUTING_FLAG_NONE);
          const profile: RoutingProfile = msg.profile ?? (flags === ROUTING_FLAG_AVOID_TRANSFERS ? 'fewest_transfers' : 'fastest');
          const segments = computeJourneySegments(
            wasmModule,
            enginePtr,
            msg.origin_stop_id,
            msg.dest_stop_id,
            msg.departure_timestamp,
            flags
          );
          options.postMessage({
            type: 'RESULT',
            segments,
            profile,
            flags,
            queryId: msg.queryId,
          });
          break;
        }

        default:
          throw new Error(`Unknown message type: ${(msg as any).type}`);
      }
    } catch (err: any) {
      options.postMessage({
        type: 'ERROR',
        message: err?.message || String(err),
        queryId: (msg as any)?.queryId,
      });
    }

  };
}
