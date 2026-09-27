/**
 * routing.worker.ts
 * Web Worker for 100% offline transit routing via C++ RAPTOR WASM module.
 * Hydrates 55 MB binary assets directly from OPFS into WASM heap views.
 */

import type {
  RoutingSegment,
  RoutingWorkerIncomingMessage,
  RoutingWorkerOutgoingMessage,
} from '../types/routing';

interface DeriveeWasmModule {
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

let wasmModule: DeriveeWasmModule | null = null;
let enginePtr: number | null = null;
let isInitialized = false;
let initPromise: Promise<number> | null = null;

async function loadWasmModule(): Promise<DeriveeWasmModule> {
  const [jsResp, wasmResp] = await Promise.all([
    fetch('/wasm/derivee_core.js'),
    fetch('/wasm/derivee_core.wasm'),
  ]);

  if (!jsResp.ok) {
    throw new Error(`Failed to load WASM script /wasm/derivee_core.js (status ${jsResp.status})`);
  }
  if (!wasmResp.ok) {
    throw new Error(`Failed to load WASM binary /wasm/derivee_core.wasm (status ${wasmResp.status})`);
  }

  const jsText = await jsResp.text();
  const wasmBinary = await wasmResp.arrayBuffer();

  const moduleObj: { exports: any } = { exports: {} };
  const fn = new Function('module', 'exports', 'globalThis', 'self', jsText + '\nreturn module.exports;');
  const factory = fn(moduleObj, moduleObj.exports, self, self);

  const wasm: DeriveeWasmModule = await factory({
    instantiateWasm: (
      info: WebAssembly.Imports,
      receiveInstance: (inst: WebAssembly.Instance) => void
    ) => {
      WebAssembly.instantiate(wasmBinary, info)
        .then((res) => {
          receiveInstance(res.instance);
        })
        .catch((err) => {
          // eslint-disable-next-line no-console
          console.error('[RoutingWorker] WebAssembly.instantiate failed:', err);
        });
      return {};
    },
  });

  return wasm;
}

async function readBinaryIntoWasm(
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
      throw new Error(`Failed to allocate ${size} bytes (64-byte aligned) in WASM heap`);
    }

    // Defensive: read directly into a fresh Uint8Array view of WASM heap
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

async function initEngine(citySlug: string = 'nyc'): Promise<number> {
  const startTime = performance.now();

  // 1. Load WASM Module
  wasmModule = await loadWasmModule();
  const ePtr = wasmModule._engine_create();
  if (!ePtr) {
    throw new Error('Failed to create RaptorEngine instance');
  }
  enginePtr = ePtr;

  // 2. Open OPFS city directory
  const root = await navigator.storage.getDirectory();
  const cityDir = await root.getDirectoryHandle(citySlug, { create: false });

  // 3. Sequential hydration: walk_graph -> timetable -> ultra_transfers
  // 3a. walk_graph.bin (~45-47 MB)
  const walkFile = await cityDir.getFileHandle('walk_graph.bin');
  const walkAlloc = await readBinaryIntoWasm(walkFile, wasmModule, 64);
  const walkOk = wasmModule._engine_load_walk_graph(enginePtr, walkAlloc.ptr, walkAlloc.size);
  if (!walkOk) {
    throw new Error('RaptorEngine rejected walk_graph.bin (format or alignment error)');
  }

  // 3b. timetable.bin (~6.9 MB)
  const ttFile = await cityDir.getFileHandle('timetable.bin');
  const ttAlloc = await readBinaryIntoWasm(ttFile, wasmModule, 64);
  const ttOk = wasmModule._engine_load_timetable(enginePtr, ttAlloc.ptr, ttAlloc.size);
  if (!ttOk) {
    throw new Error('RaptorEngine rejected timetable.bin (schema or CRC error)');
  }

  // 3c. ultra_transfers.csr (~0.6 MB)
  const ultraFile = await cityDir.getFileHandle('ultra_transfers.csr');
  const ultraAlloc = await readBinaryIntoWasm(ultraFile, wasmModule, 64);
  const ultraOk = wasmModule._engine_load_ultra(enginePtr, ultraAlloc.ptr, ultraAlloc.size);
  if (!ultraOk) {
    throw new Error('RaptorEngine rejected ultra_transfers.csr (signature error)');
  }

  isInitialized = true;
  const loadTimeMs = Math.round(performance.now() - startTime);
  return loadTimeMs;
}

function handleRoute(
  originStopId: number,
  destStopId: number,
  departureTimestamp: number
): RoutingSegment[] {
  if (!wasmModule || !enginePtr || !isInitialized) {
    throw new Error('Routing engine is not initialized');
  }

  const wasm = wasmModule;

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
    qDv.setUint16(14, 0, true); // flags: 0

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
          // Re-derive DataView fresh from wasm.HEAPU8.buffer for each 24-byte segment
          const segDv = new DataView(wasm.HEAPU8.buffer, segsPtr + i * 24, 24);
          const board = segDv.getUint32(0, true);
          const exit = segDv.getUint32(4, true);
          const trip = segDv.getUint32(8, true);
          const dep = segDv.getUint32(12, true);
          const arr = segDv.getUint32(16, true);
          const route = segDv.getUint16(20, true);
          const dist = segDv.getUint16(22, true);

          const isTransfer = (trip === 0 || trip === 0xFFFFFFFF || route === 0 || route === 0xFFFF);

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

self.onmessage = async (event: MessageEvent<RoutingWorkerIncomingMessage>) => {
  const msg = event.data;

  try {
    switch (msg.type) {
      case 'INIT': {
        if (isInitialized && enginePtr) {
          const readyMsg: RoutingWorkerOutgoingMessage = { type: 'READY', loadTimeMs: 0 };
          self.postMessage(readyMsg);
          return;
        }

        if (!initPromise) {
          initPromise = initEngine(msg.city || 'nyc');
        }

        const loadTimeMs = await initPromise;
        const readyMsg: RoutingWorkerOutgoingMessage = { type: 'READY', loadTimeMs };
        self.postMessage(readyMsg);
        break;
      }

      case 'ROUTE': {
        const segments = handleRoute(
          msg.origin_stop_id,
          msg.dest_stop_id,
          msg.departure_timestamp
        );
        const resultMsg: RoutingWorkerOutgoingMessage = { type: 'RESULT', segments };
        self.postMessage(resultMsg);
        break;
      }

      default:
        // @ts-expect-error exhaustiveness check
        throw new Error(`Unknown message type: ${msg.type}`);
    }
  } catch (err: any) {
    const errorMsg: RoutingWorkerOutgoingMessage = {
      type: 'ERROR',
      message: err?.message || String(err),
    };
    self.postMessage(errorMsg);
  }
};
