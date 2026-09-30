/// <reference lib="webworker" />

import type { MainToBasemapWorkerMessage } from '../types/basemap.ts';
import { runBasemapInstall } from './basemapInstallerCore.ts';

declare const self: DedicatedWorkerGlobalScope;

self.onmessage = async (e: MessageEvent<MainToBasemapWorkerMessage>) => {
  if (e.data.type === 'START_INSTALL') {
    const slug = e.data.slug || 'nyc';
    const url = e.data.url || `/api/basemap?city=${slug}`;
    await runBasemapInstall(slug, url, {
      postMessage: (msg) => self.postMessage(msg),
    });
  }
};
