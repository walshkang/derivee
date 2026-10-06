/**
 * routing.worker.ts
 * Web Worker for 100% offline transit routing via C++ RAPTOR WASM module.
 * Hydrates 55 MB binary assets directly from OPFS into WASM heap views.
 */

import type {
  RoutingWorkerIncomingMessage,
} from '../types/routing';
import {
  createRoutingWorkerHandler,
} from './routingEngine';

const handler = createRoutingWorkerHandler({
  postMessage: (msg) => self.postMessage(msg),
});

self.onmessage = async (event: MessageEvent<RoutingWorkerIncomingMessage>) => {
  await handler(event.data);
};
